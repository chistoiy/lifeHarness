import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/widgets/confirm_dialog.dart' show lhConfirm;
import '../../../shared/widgets/ui_kit.dart' show AppToast;
import '../data/nfc_tag_io.dart';
import '../domain/nfc_tag_content.dart';

/// 卡片内容工具（批3 · 产品令 2026-10-17）：**读取 / 修改 / 清空**任意 NDEF 卡片。
///
/// 入口＝NFC 管理屏右上角「贴卡设置」→「卡片内容」。
///
/// 三条口径：
/// · **贴卡才动天线**（§6.3 功耗）：本层关闭即停会话，不留后台监听。
/// · **原文优先**：读到什么先原样给人看；base64 的再补一行解码结果。
/// · **改完贴卡才写**：保存后进入「等卡」态，卡片贴上来才真正写——避免「点了保存
///   但卡已经拿走」这种假成功。
Future<void> showNfcTagToolSheet(
  BuildContext context, {
  NfcTagIo? io,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _NfcTagToolSheet(io: io),
  );
}

/// 工具层阶段。
enum _Stage { waiting, loaded, editing, writing, done }

class _NfcTagToolSheet extends StatefulWidget {
  const _NfcTagToolSheet({this.io});

  /// 测试注入缝（widget 用例注入假 IO，全程不碰真硬件）。
  final NfcTagIo? io;

  @override
  State<_NfcTagToolSheet> createState() => _NfcTagToolSheetState();
}

class _NfcTagToolSheetState extends State<_NfcTagToolSheet>
    with WidgetsBindingObserver {
  late final NfcTagIo _io = widget.io ?? NfcManagerTagIo();
  final TextEditingController _text = TextEditingController();

  _Stage _stage = _Stage.waiting;
  NfcTagContent _content = NfcTagContent.empty;
  int _sizeBytes = 0;
  bool _writable = false;

  /// 正在编辑的那条记录下标（-1＝没有）。
  int _editIndex = -1;

  /// 编辑时的存储类型：`'uri'`＝网址（RTD-URI·系统可识别）／`'text'`＝文本。
  ///
  /// 默认沿用原记录类型；**空卡写网址必须选 uri**——存成文本系统不认，
  /// 贴卡不会拉起 App（2026-10-17 真机报障）。
  String _editKind = 'text';

  /// 待写记录（非 null ⇒ 下一张贴上来的卡就写它）。
  List<NfcRawRecord>? _pendingWrite;

  /// 写失败后留在层里的原因（给用户看的一句话）。
  String? _error;

  /// 天线贴住不动会反复回调 ⇒ 同一次处理只走一遍。
  bool _handling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 编辑框内容变化要驱动「保存」按钮的可用态（空内容不给保存）。
    _text.addListener(_onTextChanged);
    _startSession();
  }

  void _onTextChanged() {
    if (mounted && _stage == _Stage.editing) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _text.removeListener(_onTextChanged);
    _text.dispose();
    unawaited(_io.stop()); // 离开层即停会话（§6.3）
    super.dispose();
  }

  /// 切后台停会话；回前台且还在等卡时重开（B34 同口径）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_stage == _Stage.waiting || _stage == _Stage.writing) _startSession();
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_io.stop());
    }
  }

  void _startSession() {
    unawaited(_io.startRead(onProbe: _onTag, onError: _onError));
  }

  Future<void> _onTag(NfcTagProbe probe) async {
    if (_handling || !mounted) return;
    _handling = true;
    try {
      if (!probe.isNdef) {
        setState(() {
          _stage = _Stage.waiting;
          _error = '这张卡不支持 NDEF 记录（读不出也写不了）';
        });
        return;
      }
      // 有待写内容 ⇒ 这张卡就是要写的那张。
      final pending = _pendingWrite;
      if (pending != null) {
        setState(() => _stage = _Stage.writing);
        try {
          await _io.writeRecords(pending);
          if (!mounted) return;
          setState(() {
            _pendingWrite = null;
            _stage = _Stage.done;
            _error = null;
          });
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _stage = _Stage.waiting;
            _error = _writeErrorText(e);
          });
        }
        return;
      }
      final content = nfcContentOf(probe.records);
      if (!mounted) return;
      setState(() {
        _content = content;
        _sizeBytes = probe.maxSize;
        _writable = probe.isWritable;
        _stage = _Stage.loaded;
        _error = null;
      });
    } finally {
      _handling = false;
    }
  }

  void _onError(String code) {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.waiting;
      _error = code == 'nfc_disabled'
          ? '系统 NFC 没开，去设置里打开后再贴卡'
          : '读卡失败（$code），把卡贴稳再试';
    });
  }

  /// 写失败的给人文案（不暴露类名/异常码以外的实现细节）。
  String _writeErrorText(Object e) {
    final code = codeOf(e);
    if (code == 'tag_not_found') return '卡片离开了，贴回去就会继续写';
    if (code == 'IOException') return '写不进去（可能是只读卡或容量不够）';
    if (code == 'FormatException') return '这张卡不是 NDEF 格式，写不了';
    return '写入失败（$code）';
  }

  /// 进入编辑态：有可改的记录就改那条，没有就**新增一条**
  /// （空卡／只有 AAR 的卡也能用来写内容）。
  void _beginEdit() {
    final i = _content.firstEditableIndex;
    if (i == null) {
      _text.text = '';
      _editKind = _kindOfInput('');
      setState(() {
        _editIndex = _content.raw.length; // ＝「追加一条」，超出原下标
        _stage = _Stage.editing;
        _error = null;
      });
      return;
    }
    final rec = _content.records.firstWhere((r) => r.index == i);
    _text.text = rec.editValue;
    // 默认沿用原记录的类型（改网址仍是网址，改文本仍是文本）。
    _editKind = rec.kind == NfcContentKind.uri ? 'uri' : 'text';
    setState(() {
      _editIndex = i;
      _stage = _Stage.editing;
      _error = null;
    });
  }

  /// 根据输入猜类型：像网址就默认存成网址（**网址必须存 RTD-URI，否则系统不认**）。
  String _kindOfInput(String s) =>
      RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://').hasMatch(s.trim()) ? 'uri' : 'text';

  /// 保存编辑 ⇒ 组装新记录集 ⇒ 进入等卡写入态。
  void _saveEdit() {
    final i = _editIndex;
    if (i < 0) return;
    // ⚠ 存网址时**必须 trim**（批3c 真机报障）：从卡片里长按复制出来的网址常带
    // 尾随空格/换行，原样写进 RTD-URI ⇒ 系统解析出的 path 带空白 ⇒ cardId 校验
    // 不过 ⇒ 贴卡静默无反应（用户只看到「没反应」）。文本记录保留原样（可能有意换行）。
    final wantUri = _editKind == 'uri';
    final input = wantUri ? _text.text.trim() : _text.text;
    if (input.isEmpty) return;
    List<NfcRawRecord> next;
    if (i >= _content.raw.length) {
      // 新增：按选定的类型造一条（底稿已被 nfcContentOf 滤掉 EMPTY，
      // 故新记录必然成为首条——这是「清空后写入再读不回空」的关键）。
      next = <NfcRawRecord>[
        ..._content.raw,
        wantUri ? nfcNewUriRecord(input) : nfcNewTextRecord(input),
      ];
    } else {
      final rec = _content.records.firstWhere((r) => r.index == i);
      // base64 卡：用户改的是解码后的可读文本，写回时按原样重新编码。
      final stored = rec.isBase64 ? encodeBase64Text(input) : input;
      next = <NfcRawRecord>[
        for (var k = 0; k < _content.raw.length; k++)
          if (k != i)
            _content.raw[k]
          else
            (rec.kind == NfcContentKind.uri) == wantUri
                ? nfcRecordWithText(_content.raw[k], stored) // 同型：保留前缀码/语言码
                : wantUri
                    ? nfcNewUriRecord(stored) // 换型：按选定类型重建
                    : nfcNewTextRecord(stored),
      ];
    }
    // 批3c（2026-10-17 真机报障·根因①）：**写本 App 网址必须同时带 AAR**。
    // 「清空」那一步会把 AAR 一起抹掉（EMPTY 记录是唯一的），之后写回时底稿里
    // 已经没有 AAR 可保留——于是系统只弹「NFC 卡片」通知、不启动本 App，贴卡等于
    // 没反应（读回内容却完全正常，正是用户报的「改写过的卡不触发」）。
    final withAar = nfcEnsureSelfAar(next, kNfcAarPackage);
    final addedAar = withAar.length > next.length;
    setState(() {
      _pendingWrite = withAar;
      _stage = _Stage.writing;
      _error = null;
    });
    AppToast.show(
      context,
      addedAar
          ? '已补上本 App 绑定记录，把卡片贴回手机背面，贴稳就写'
          : '把卡片贴回手机背面，贴稳就写',
    );
  }

  Future<void> _confirmClear() async {
    final ok = await lhConfirm(
      context,
      '清空后这张卡里的内容会被抹掉，且不能撤销。确定要清空吗？',
      title: '清空卡片内容',
      okLabel: '清空',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() {
      _pendingWrite = nfcEmptyRecords();
      _stage = _Stage.writing;
      _error = null;
    });
    AppToast.show(context, '把卡片贴回手机背面，贴稳就清空');
  }

  void _restart() {
    setState(() {
      _stage = _Stage.waiting;
      _content = NfcTagContent.empty;
      _pendingWrite = null;
      _error = null;
      _editIndex = -1;
    });
    _startSession();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 34,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Center(
                child: Text('卡片内容',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  '读取 · 修改 · 清空任意 NFC 卡片',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 14),
              ..._body(scheme),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(ColorScheme scheme) {
    switch (_stage) {
      case _Stage.waiting:
        return [
          _hintBox(scheme, Icons.nfc, '把卡片贴到手机背面',
              _pendingWrite == null ? '读完就能看到卡里存了什么' : '贴稳后自动写入'),
          if (_error != null) _errLine(scheme, _error!),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: const ValueKey('nfc-tool-cancel'),
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ),
        ];
      case _Stage.loaded:
        return [
          _metaLine(scheme),
          const SizedBox(height: 8),
          ..._recordTiles(scheme),
          if (_error != null) _errLine(scheme, _error!),
          const SizedBox(height: 12),
          if (_content.isEmpty)
            _hintBox(scheme, Icons.crop_free, '这张卡是空的', '可以点「修改内容」写入一段文本'),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  key: const ValueKey('nfc-tool-edit'),
                  onPressed: _writable ? _beginEdit : null,
                  child: const Text('修改内容'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonal(
                  key: const ValueKey('nfc-tool-clear'),
                  onPressed: _content.isEmpty || !_writable ? null : _confirmClear,
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.errorContainer,
                    foregroundColor: scheme.onErrorContainer,
                  ),
                  child: const Text('清空卡片'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: const ValueKey('nfc-tool-reread'),
              onPressed: _restart,
              child: const Text('换一张卡 / 重新读取'),
            ),
          ),
          const SizedBox(height: 4),
          // 显式「关闭」：读到内容后不该只能靠下滑手势（真机上拇指不好够）。
          SizedBox(
            width: double.infinity,
            child: TextButton(
              key: const ValueKey('nfc-tool-close'),
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ),
          const SizedBox(height: 4),
          _tiny(scheme, '只改这张卡的存储内容，不动 App 里的卡片绑定'),
        ];
      case _Stage.editing:
        final isNew = _editIndex >= _content.raw.length;
        final rec = isNew
            ? null
            : _content.records.firstWhere((r) => r.index == _editIndex);
        return [
          Text(isNew ? '正在写入：新增一条内容' : '正在修改：${rec!.typeLabel}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _kindPicker(scheme),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('nfc-tool-text'),
            controller: _text,
            maxLines: 6,
            minLines: 3,
            autofocus: true,
            onChanged: (v) {
              // 新建态下按输入自动切类型（粘进网址就切到网址）。
              if (isNew && _editKind != _kindOfInput(v)) {
                setState(() => _editKind = _kindOfInput(v));
              }
            },
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              isDense: true,
              hintText: _editKind == 'uri' ? '要写进卡片的网址' : '要写进卡片的文本',
            ),
          ),
          const SizedBox(height: 8),
          if (_editKind == 'uri')
            _tiny(scheme, '按网址存储：贴这张卡时系统能认出并打开对应 App'),
          if (rec != null &&
              rec.kind == NfcContentKind.text &&
              _editKind == 'uri')
            _tiny(scheme, '原内容是文本，改成网址后系统才会按网址识别'),
          if (rec != null && rec.isBase64)
            _tiny(scheme, '原内容是 base64 编码，这里显示解码后的文本；保存时会按原样重新编码写回'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('nfc-tool-edit-cancel'),
                  onPressed: () => setState(() {
                    _stage = _Stage.loaded;
                    _editIndex = -1;
                  }),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('nfc-tool-edit-save'),
                  onPressed: _text.text.trim().isEmpty ? null : _saveEdit,
                  child: const Text('保存并写回'),
                ),
              ),
            ],
          ),
        ];
      case _Stage.writing:
        return [
          _hintBox(scheme, Icons.nfc, '把卡片贴回手机背面',
              _pendingWrite != null && _pendingWrite!.length == 1 && _pendingWrite![0].tnf == 0
                  ? '贴稳就清空这张卡'
                  : '贴稳就写入新内容'),
          if (_error != null) _errLine(scheme, _error!),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: const ValueKey('nfc-tool-write-cancel'),
              onPressed: () => setState(() {
                _pendingWrite = null;
                _stage = _content.isEmpty ? _Stage.waiting : _Stage.loaded;
              }),
              child: const Text('取消写入'),
            ),
          ),
        ];
      case _Stage.done:
        return [
          _hintBox(scheme, Icons.check_circle_outline, '已写入', '可以拿开卡片了'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('nfc-tool-done-close'),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('完成'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonal(
                  key: const ValueKey('nfc-tool-done-again'),
                  onPressed: _restart,
                  child: const Text('再读一次'),
                ),
              ),
            ],
          ),
        ];
    }
  }

  /// 存储类型二选一（网址／文本）。默认沿用原类型，新建态按输入自动切。
  Widget _kindPicker(ColorScheme scheme) {
    return Row(
      children: [
        _kindChip(scheme, 'uri', '网址', Icons.link),
        const SizedBox(width: 8),
        _kindChip(scheme, 'text', '文本', Icons.subject),
        const Spacer(),
        Text('存为',
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _kindChip(ColorScheme scheme, String kind, String label, IconData icon) {
    final on = _editKind == kind;
    final bg = on ? scheme.primary : scheme.surfaceContainerHighest;
    final fg = on ? scheme.onPrimary : scheme.onSurfaceVariant;
    return InkWell(
      key: ValueKey<String>('nfc-tool-kind-$kind'),
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _editKind = kind),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
          ],
        ),
      ),
    );
  }

  /// 容量与可写态一行（读出来后立刻给「能不能改」的判据）。
  Widget _metaLine(ColorScheme scheme) {
    final size = _sizeBytes > 0 ? '$_sizeBytes 字节' : '容量未报出';
    final w = _writable ? '可写' : '只读卡';
    return Text(
      '$size · $w · ${_content.raw.length} 条记录',
      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
    );
  }

  List<Widget> _recordTiles(ColorScheme scheme) {
    if (_content.isEmpty) return const [];
    return [
      for (final r in _content.records)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(r.typeLabel,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: scheme.primary)),
                  const SizedBox(width: 6),
                  if (r.isBase64)
                    Text('base64',
                        style: TextStyle(
                            fontSize: 10, color: scheme.onSurfaceVariant)),
                  const Spacer(),
                  if (!r.editable)
                    Text('只读',
                        style: TextStyle(
                            fontSize: 10, color: scheme.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 4),
              SelectableText(
                r.text.isEmpty ? '（空）' : r.text,
                style: const TextStyle(fontSize: 12, height: 1.45),
              ),
              if (r.decodedText != null) ...[
                const SizedBox(height: 6),
                Text('解码后',
                    style: TextStyle(
                        fontSize: 10, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 2),
                SelectableText(
                  r.decodedText!,
                  style: TextStyle(
                      fontSize: 12, height: 1.45, color: scheme.primary),
                ),
              ],
            ],
          ),
        ),
      if (_content.isLifeHarnessCard)
        _tiny(
          scheme,
          _content.hasAar
              ? '这是本 App 的卡片：改掉里面的 lh:// 内容会让卡片失效'
              : '这张卡缺本 App 绑定记录（贴卡不会被系统拉起）；保存时会自动补上',
        ),
    ];
  }

  Widget _hintBox(ColorScheme scheme, IconData icon, String title, String sub) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(icon, size: 26, color: scheme.primary),
          const SizedBox(height: 8),
          Text(title,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(sub, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _errLine(ColorScheme scheme, String msg) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(msg,
            style: TextStyle(fontSize: 11, color: scheme.error, height: 1.5)),
      );

  Widget _tiny(ColorScheme scheme, String s) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(s,
            style: TextStyle(
                fontSize: 10.5, height: 1.5, color: scheme.onSurfaceVariant)),
      );
}
