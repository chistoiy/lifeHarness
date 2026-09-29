// 工具屏 · Base64 转换（原型 `TOOLS.b64` / `b64*` 同源 · 批3）。
//
// 四 tab（图→串 / 串→图 / 文本→串 / 串→文本）全走 `dart:convert` 的真实 UTF-8 +
// Base64 通道，字符数与体积都是实算；错误口径逐条同原型（非法字符 / 长度非 4
// 倍数 / 解不出图片流）。取图与解码复用 `KitImgz.loader` 注入缝，另存走
// `KitB64.save`，widget 测试不碰真实异步 I/O。近期 8 条 + 记录 6 条落
// `kit_tool_data.tool='b64'`（键名同原型 `KITS.b64Recent`·`KITS.b64Hist`）。
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/kit_b64.dart';
import '../../domain/kit_calc.dart' show kitBytesText, kitRelText;
import '../../domain/kit_models.dart';
import '../kit_providers.dart';
import 'kit_imgz_page.dart' show KitImgz, KitImgzSource;
import 'kit_tools_kit.dart';

/// 生产通道与注入缝（测试替换三个静态字段即可全程离线）。
class KitB64 {
  KitB64._();

  static Future<String?> Function() pickImage = _defaultPickImage;

  /// 字节流探针：能否解出图片 + 宽高（原型 `im.onload` / `im.onerror` 的等价物）。
  static Future<(int w, int h)?> Function(Uint8List bytes) probe =
      _defaultProbe;

  static Future<String?> Function(String fileName, Uint8List bytes) save =
      (name, bytes) =>
          kitToolSaveBytes(fileName: name, bytes: bytes, dialogTitle: '保存文本');

  static Future<String?> _defaultPickImage() async {
    try {
      return (await ImagePicker().pickImage(source: ImageSource.gallery))?.path;
    } catch (_) {
      return null;
    }
  }

  static Future<(int, int)?> _defaultProbe(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = (frame.image.width, frame.image.height);
      frame.image.dispose();
      return size;
    } catch (_) {
      return null;
    }
  }
}

/// Base64 转换屏主体。
class KitB64Body extends ConsumerStatefulWidget {
  const KitB64Body({super.key});

  @override
  ConsumerState<KitB64Body> createState() => _KitB64BodyState();
}

class _KitB64BodyState extends ConsumerState<KitB64Body> {
  final TextEditingController _decCtrl = TextEditingController();
  final TextEditingController _txtCtrl = TextEditingController();
  final TextEditingController _txtInCtrl = TextEditingController();

  String _tab = kKitB64TabEnc;
  KitImgzSource? _src;
  String _name = '';
  String _decErr = '';
  String? _decInfo;
  Uint8List? _decBytes;
  String _txtErr = '';
  String? _txtBack;
  List<KitB64Recent> _recent = const [];
  List<KitB64Log> _hist = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _decCtrl.dispose();
    _txtCtrl.dispose();
    _txtInCtrl.dispose();
    _src?.preview?.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final s = KitB64State.decode(
      await ref.read(kitRepositoryProvider).toolData(kitToolKeyB64),
    );
    if (!mounted) return;
    setState(() {
      _recent = s.recent;
      _hist = s.hist;
      _loaded = true;
    });
  }

  /// 留痕：写内存 + 落库（原型 `b64Log` + `b64RecentRender` 同一次完成）。
  Future<void> _push({
    KitB64Recent? recent,
    required String log,
    bool ok = true,
  }) async {
    setState(() {
      if (recent != null) {
        _recent = kitB64Push(_recent, recent, kKitB64RecentMax);
      }
      _hist = kitB64Push(
        _hist,
        KitB64Log(t: log, ok: ok, ts: DateTime.now().millisecondsSinceEpoch),
        kKitB64HistMax,
      );
    });
    await ref
        .read(kitRepositoryProvider)
        .setToolData(kitToolKeyB64, kitB64Encode(recent: _recent, hist: _hist));
  }

  String get _imgRaw => _src == null ? '' : kitB64EncodeBytes(_src!.bytes);

  String get _txtRaw => kitB64EncodeText(_txtCtrl.text);

  // ── tab 1 · 图片 → Base64 ────────────────────────────────────────────
  Future<void> _pickEncode() async {
    final path = await KitB64.pickImage();
    if (path == null || !mounted) return;
    final src = await KitImgz.loader(path);
    if (!mounted) return;
    if (src == null) {
      AppToast.show(context, '本机读不到这张图 · 换一张试试');
      return;
    }
    _src?.preview?.dispose();
    final name = path.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).last;
    final raw = kitB64EncodeBytes(src.bytes);
    setState(() {
      _src = src;
      _name = name;
    });
    await _push(
      recent: KitB64Recent(
        name: name,
        size: src.bytes.length,
        len: raw.length,
        ts: DateTime.now().millisecondsSinceEpoch,
      ),
      log: '编码 $name → ${raw.length} 字符',
    );
  }

  // ── tab 2 · Base64 → 图片 ────────────────────────────────────────────
  Future<void> _decodeImage() async {
    final s = kitB64Split(_decCtrl.text);
    final bad = kitB64Validate(s.raw);
    if (bad != null) {
      await _fail(bad, isText: false);
      return;
    }
    final bytes = kitB64DecodeBytes(s.raw);
    if (bytes == null) {
      await _fail('Base64 解码失败 · 字符串被截断或含非法字符', isText: false);
      return;
    }
    final dims = await KitB64.probe(bytes);
    if (!mounted) return;
    if (dims == null) {
      await _fail('内容可解码但不是有效图片流', isText: false);
      return;
    }
    setState(() {
      _decErr = '';
      _decBytes = bytes;
      _decInfo =
          '还原成功 · ${dims.$1}×${dims.$2} · '
          '${kitBytesText(bytes.length)} · 本地解码';
    });
    await _push(log: '解码 ${s.raw.length} 字符 → ${dims.$1}×${dims.$2}');
    if (mounted) AppToast.show(context, '已还原为图片 · 可保存');
  }

  Future<void> _decodeText() async {
    final s = kitB64Split(_txtInCtrl.text);
    final bad = kitB64Validate(s.raw);
    if (bad != null) {
      await _fail(bad, isText: true);
      return;
    }
    final txt = kitB64DecodeText(s.raw);
    if (txt == null) {
      await _fail('解码失败 · 字符串被截断或含非法字符', isText: true);
      return;
    }
    setState(() {
      _txtErr = '';
      _txtBack = txt;
    });
    await _push(log: '解码 ${s.raw.length} 字符 → ${txt.length} 字文本');
    if (mounted) AppToast.show(context, '已还原为文本 · 本地解码');
  }

  Future<void> _fail(String msg, {required bool isText}) async {
    setState(() {
      if (isText) {
        _txtErr = msg;
        _txtBack = null;
      } else {
        _decErr = msg;
        _decInfo = null;
        _decBytes = null;
      }
    });
    await _push(log: msg, ok: false);
    if (mounted) AppToast.show(context, msg);
  }

  void _takeFromEncode() {
    if (_txtCtrl.text.isEmpty) {
      AppToast.show(context, '先在「文本 → Base64」生成一次');
      return;
    }
    setState(() {
      _txtInCtrl.text = _txtRaw;
      _tab = kKitB64TabTextDec;
    });
  }

  Future<void> _saveText(String fileName, String content) =>
      KitB64.save(fileName, Uint8List.fromList(utf8.encode(content))).then((
        path,
      ) async {
        if (!mounted) return;
        AppToast.show(context, path == null ? '已取消保存' : '已保存 → $path');
        await _push(log: '导出 $fileName', ok: path != null);
      });

  void _clearHist() {
    setState(() => _hist = const []);
    ref
        .read(kitRepositoryProvider)
        .setToolData(kitToolKeyB64, kitB64Encode(recent: _recent, hist: _hist));
    AppToast.show(context, '操作记录已清空');
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in kKitB64Tabs)
              KitToolChip(
                keyName: 'kit-b64-tab-$t',
                label: kitB64TabLabel(t),
                on: _tab == t,
                onTap: () => setState(() => _tab = t),
              ),
          ],
        ),
        const SizedBox(height: 10),
        ..._panel(),
        const SizedBox(height: 12),
        kitToolSection('近期转换 · 本机留痕'),
        _recentRows(now),
        const SizedBox(height: 10),
        kitToolSection(
          '操作记录',
          trailing: [
            kitToolBtn(
              context,
              '清空',
              _hist.isEmpty ? null : _clearHist,
              keyName: 'kit-b64-hist-clear',
              small: true,
            ),
          ],
        ),
        kitToolNote(
          _hist.isEmpty ? (_loaded ? '尚无操作记录 · 编码/解码后自动留痕' : '正在读本机记录…') : '',
          key: const ValueKey('kit-b64-hist-empty'),
        ),
        for (var i = 0; i < _hist.length; i++) _histRow(i, now),
        kitToolSubCard(
          context,
          kitToolNote(
            '限定图片与文本两类 · 全程本机转换 · 留痕随本机备份',
            key: const ValueKey('kit-b64-note'),
          ),
        ),
      ],
    );
  }

  Widget _histRow(int i, DateTime now) {
    final e = _hist[i];
    return Padding(
      key: ValueKey('kit-b64-hist-$i'),
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              kitRelText(e.ts, now),
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              e.t,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5),
            ),
          ),
          Text(
            e.mark(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: e.ok ? context.tokens.accent : Colors.redAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _recentRows(DateTime now) {
    if (_recent.isEmpty) {
      return kitToolNote(
        '尚无转换记录 · 选图或粘贴文本后即留痕',
        key: const ValueKey('kit-b64-recent-empty'),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < _recent.length; i++)
          kitToolSubCard(
            context,
            Text(
              _recent[i].text(now),
              key: ValueKey('kit-b64-recent-$i'),
              style: const TextStyle(fontSize: 10.5),
            ),
          ),
      ],
    );
  }

  /// 多行输入框（原型 `textarea.inp`；等宽用于串）。
  Widget _input(
    String keyName,
    TextEditingController c,
    String hint, {
    bool mono = false,
  }) => TextField(
    key: ValueKey(keyName),
    controller: c,
    maxLines: 4,
    minLines: 2,
    style: TextStyle(
      fontSize: mono ? 10 : 12,
      fontFamily: mono ? 'monospace' : null,
    ),
    // 文本 tab 要实时出计数与结果，其余 tab 只在点按钮时算。
    onChanged: mono ? null : (_) => setState(() {}),
    decoration: InputDecoration(
      isDense: true,
      hintText: hint,
      border: const OutlineInputBorder(),
    ),
  );

  /// 只读结果区（SelectableText 而非临时 TextEditingController：不泄漏、可长按复制）。
  Widget _out(String keyName, String text, String hint) => Container(
    width: double.infinity,
    constraints: const BoxConstraints(minHeight: 56),
    padding: const EdgeInsets.all(9),
    margin: const EdgeInsets.only(top: 6),
    decoration: BoxDecoration(
      border: Border.all(color: context.tokens.cardBorder),
      borderRadius: BorderRadius.circular(10),
    ),
    child: SingleChildScrollView(
      child: SelectableText(
        text.isEmpty ? hint : text,
        key: ValueKey(keyName),
        style: TextStyle(
          fontSize: 10,
          fontFamily: 'monospace',
          color: text.isEmpty ? Colors.grey : null,
        ),
      ),
    ),
  );

  List<Widget> _panel() {
    final tokens = context.tokens;
    final raw = _imgRaw;
    switch (_tab) {
      case kKitB64TabEnc:
        return [
          GestureDetector(
            key: const ValueKey('kit-b64-pick'),
            behavior: HitTestBehavior.opaque,
            onTap: _pickEncode,
            child: kitToolSubCard(
              context,
              Column(
                children: [
                  Icon(Icons.image_outlined, size: 30, color: tokens.accent),
                  const Text(
                    '选择图片 · 本机转 Base64',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_src != null) ...[
            SizedBox(
              height: 96,
              child: _src!.preview == null
                  // 键放 Text 上：用例按文案读数（键留在 SizedBox 上 cast 不成 Text）。
                  ? kitToolNote(
                      '$_name · ${_src!.width}×${_src!.height}',
                      key: const ValueKey('kit-b64-prev'),
                    )
                  : RawImage(image: _src!.preview, fit: BoxFit.contain),
            ),
            kitToolNote(
              kitB64OutLenText(
                srcBytes: _src!.bytes.length,
                b64Len: raw.length,
              ),
              key: const ValueKey('kit-b64-outlen'),
            ),
            kitToolNote(kitB64Peek(raw), key: const ValueKey('kit-b64-peek')),
            _out('kit-b64-out', raw, '编码结果将出现在这里'),
            Wrap(
              spacing: 2,
              children: [
                kitToolBtn(
                  context,
                  '复制裸串',
                  raw.isEmpty
                      ? null
                      : () => kitToolCopy(context, raw, msg: '已复制 Base64 裸串'),
                  keyName: 'kit-b64-copy-raw',
                  small: true,
                ),
                kitToolBtn(
                  context,
                  '复制 data URI',
                  raw.isEmpty
                      ? null
                      : () => kitToolCopy(
                          context,
                          kitB64DataUri(raw),
                          msg: '已复制 data URI',
                        ),
                  keyName: 'kit-b64-copy-uri',
                  small: true,
                ),
                kitToolBtn(
                  context,
                  '存 .txt',
                  raw.isEmpty ? null : () => _saveText('$_name.b64.txt', raw),
                  keyName: 'kit-b64-save-txt',
                  small: true,
                ),
                kitToolBtn(
                  context,
                  '存 dataURI',
                  raw.isEmpty
                      ? null
                      : () => _saveText('$_name.uri.txt', kitB64DataUri(raw)),
                  keyName: 'kit-b64-save-uri',
                  small: true,
                ),
              ],
            ),
          ],
        ];
      case kKitB64TabDec:
        return [
          _input(
            'kit-b64-in',
            _decCtrl,
            '粘贴 data:image/png;base64,… 或裸 Base64 串',
            mono: true,
          ),
          Wrap(
            spacing: 2,
            children: [
              kitToolBtn(
                context,
                '解码并还原',
                _decodeImage,
                keyName: 'kit-b64-decode',
              ),
              kitToolBtn(
                context,
                '填入示例',
                () {
                  setState(() => _decCtrl.text = kKitB64SampleDataUri);
                  _decodeImage();
                },
                keyName: 'kit-b64-sample',
                small: true,
              ),
              kitToolBtn(
                context,
                '补前缀',
                () => setState(
                  () => _decCtrl.text = kitB64AddPrefix(_decCtrl.text),
                ),
                keyName: 'kit-b64-prefix',
                small: true,
              ),
            ],
          ),
          if (_decErr.isNotEmpty)
            kitToolNote(_decErr, key: const ValueKey('kit-b64-err')),
          if (_decInfo != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: kitToolSubCard(
                context,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _decInfo!,
                      key: const ValueKey('kit-b64-back'),
                      style: TextStyle(
                        fontSize: 11,
                        color: tokens.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    kitToolBtn(
                      context,
                      '保存还原图片',
                      () =>
                          KitB64.save(
                            'decoded.dat',
                            _decBytes ?? Uint8List(0),
                          ).then((p) {
                            if (mounted) {
                              AppToast.show(
                                context,
                                p == null ? '已取消保存' : '已保存 → $p',
                              );
                            }
                          }),
                      keyName: 'kit-b64-save-img',
                      small: true,
                    ),
                  ],
                ),
              ),
            ),
        ];
      case kKitB64TabTextEnc:
        return [
          _input('kit-b64-src', _txtCtrl, '输入或粘贴文本…'),
          kitToolNote(
            kitB64Meta(text: _txtCtrl.text),
            key: const ValueKey('kit-b64-meta'),
          ),
          _out('kit-b64-txtout', _txtRaw, '文本的 Base64 结果将出现在这里'),
          Wrap(
            spacing: 2,
            children: [
              kitToolBtn(
                context,
                '复制裸串',
                _txtCtrl.text.isEmpty
                    ? null
                    : () =>
                          kitToolCopy(context, _txtRaw, msg: '已复制文本 Base64 串'),
                keyName: 'kit-b64-txt-copy',
                small: true,
              ),
              kitToolBtn(
                context,
                '填入示例',
                () => setState(() => _txtCtrl.text = 'LifeHarness · 数据在自己手里'),
                keyName: 'kit-b64-txt-demo',
                small: true,
              ),
              kitToolBtn(
                context,
                '转去解码验证',
                _txtCtrl.text.isEmpty ? null : _takeFromEncode,
                keyName: 'kit-b64-txt-take',
                small: true,
              ),
            ],
          ),
        ];
      default:
        return [
          _input(
            'kit-b64-txtin',
            _txtInCtrl,
            '粘贴 Base64 串（按 UTF-8 还原）',
            mono: true,
          ),
          Wrap(
            spacing: 2,
            children: [
              kitToolBtn(
                context,
                '解码为文本',
                _decodeText,
                keyName: 'kit-b64-txtdec',
              ),
              kitToolBtn(
                context,
                '取上方编码结果',
                _takeFromEncode,
                keyName: 'kit-b64-txt-take2',
                small: true,
              ),
            ],
          ),
          if (_txtErr.isNotEmpty)
            kitToolNote(_txtErr, key: const ValueKey('kit-b64-txterr')),
          if (_txtBack != null) ...[
            _out('kit-b64-txtback', _txtBack!, '还原出的文本'),
            Wrap(
              spacing: 2,
              children: [
                kitToolBtn(
                  context,
                  '复制还原文本',
                  () => kitToolCopy(context, _txtBack ?? '', msg: '已复制还原文本'),
                  keyName: 'kit-b64-back-copy',
                  small: true,
                ),
                kitToolBtn(
                  context,
                  '存 .txt',
                  () => _saveText('decoded.txt', _txtBack ?? ''),
                  keyName: 'kit-b64-back-save',
                  small: true,
                ),
              ],
            ),
          ],
        ];
    }
  }
}
