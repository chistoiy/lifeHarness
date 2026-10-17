import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/linkage/media_mounts.dart';
import '../../../shared/widgets/image_attach.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/media_repo_goal.dart';
import '../data/media_repo_note.dart';
import '../domain/media_item.dart';
import '../domain/media_note.dart';
import 'media_providers.dart';

/// 影音笔记唯一录入表单（原型 `m-sheet-note-edit` · 词典 LH-S35 · 批5）。
///
/// 字段顺序＝工单 §1.3 ＋拍板④（创建时间挪到时间点旁，两个「何时」并排）：
/// 条目 → 类型五 chips（选中项左边色标跟变）→ 时间点 ＋ 创建时间 → 附件截图 →
/// 标签 → 正文 → 粘贴文本／识图 → →日记 ／ →待办 → 保存。
///
/// 四条口径：
/// - **空正文＝就地红字（LH-K32），不借道提示条**；仓储侧 `addNote` 返回 null 是同一道闸，
///   屏侧不再自己判空一遍（两处判空迟早分叉）；
/// - **防重入**＝按钮忙态 ＋ `addNote` 的在册判重（连点只落一条，第二次返回既有行 id）；
/// - **子项（集/曲/章节）本期不铺**：`unit_ref` 是 `media_units` 外键，而子项的管理面属
///   批4 剩余面（表在册、无仓储出口）——铺一个写了没人读的文本框就是假入口（偏离登记工单）；
/// - OCR **置灰不隐藏**（计划 §风险 L319）：手机端 `title` 取不到（批5 拍板⑤），
///   所以点击给一句实话 toast，而不是无声无息。
class MediaNoteEditSheet extends ConsumerStatefulWidget {
  const MediaNoteEditSheet({
    super.key,
    this.initialItemId,
    this.initialAtMin,
    this.origin = MediaNote.kOriginManual,
  });

  final String? initialItemId;

  /// 从计时页/详情页带进来的时间点（分钟）。
  final int? initialAtMin;

  /// 录入来源（`origin` 列）：手动＝manual，计时明细「记一次」＝session。
  final String origin;

  @override
  ConsumerState<MediaNoteEditSheet> createState() => _MediaNoteEditSheetState();
}

/// 打开唯一录入表单；返回是否落了库（null＝取消）。
Future<bool?> showMediaNoteEditSheet(
  BuildContext context,
  WidgetRef ref, {
  String? initialItemId,
  int? initialAtMin,
  String origin = MediaNote.kOriginManual,
}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MediaNoteEditSheet(
        initialItemId: initialItemId,
        initialAtMin: initialAtMin,
        origin: origin,
      ),
    );

class _MediaNoteEditSheetState extends ConsumerState<MediaNoteEditSheet> {
  final _body = TextEditingController();
  final _tag = TextEditingController();
  final _at = TextEditingController();
  final _when = TextEditingController();

  String? _itemId;
  String _type = MediaNote.kScene;
  final List<String> _images = <String>[];

  /// 空正文就地报错（LH-K32）。
  String? _bodyErr;

  /// 忙态＝防重入连点（真落库只有一次）。
  bool _busy = false;

  /// 「→日记 / →待办」在保存后是否已联动过（同一表单只联动一次，重复点给实话）。
  bool _linkedJournal = false;
  bool _linkedTodo = false;

  @override
  void initState() {
    super.initState();
    _itemId = widget.initialItemId;
    if (widget.initialAtMin != null) _at.text = mediaNoteAtTx(widget.initialAtMin);
    // 默认「现在」＝创建时间留空（仓储侧落当下时刻），改过才带值（工单 §1.3）。
    _initAutoPos();
  }

  /// autoPos 生效面（LH-C23 铁口径①）：开着且没带时间点进来＝预填该条最近流水终点；
  /// 没会话/读数取不到＝留空不编（算不出不编数＝批4 §0.2）。
  Future<void> _initAutoPos() async {
    final id = widget.initialItemId;
    if (id == null || widget.initialAtMin != null || _at.text.isNotEmpty) return;
    final repo = ref.read(mediaRepositoryProvider);
    if (await mediaKvSafe(repo, 'media.autoPos', 'true') != 'true') return;
    final to = await repo.lastSessionToMin(id);    if (to == null || !mounted || _at.text.isNotEmpty) return;
    setState(() => _at.text = mediaNoteAtTx(to));
  }

  @override
  void dispose() {
    _body.dispose();
    _tag.dispose();
    _at.dispose();
    _when.dispose();
    super.dispose();
  }

  void _bump() {
    final tick = ref.read(mediaTickProvider.notifier);
    tick.state = tick.state + 1;
  }

  List<MediaItem> get _items =>
      ref.read(mediaAllItemsProvider).valueOrNull ?? const <MediaItem>[];

  MediaItem? get _item {
    final id = _itemId;
    if (id == null) return null;
    for (final x in _items) {
      if (x.id == id) return x;
    }
    return null;
  }

  /// 条目标题（联动文案与出处行都用它；条目已删/未取到＝给一句实话）。
  String get _itemTitle => _item?.title ?? '未选条目';

  Future<void> _pickItem() async {
    if (_items.isEmpty) {
      AppToast.show(context, '影音架还没有条目 · 先收一条再记笔记');
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ItemPickerSheet(initial: _itemId, items: _items),
    );
    if (picked != null) setState(() => _itemId = picked);
  }

  Future<void> _attach() async {
    final scheme = Theme.of(context).colorScheme;
    final path = await pickAndStoreImage(
      context,
      bg: scheme.surface,
      fg: scheme.onSurface,
    );
    if (path == null) return;
    setState(() => _images.add(path));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text ?? '';
    if (!mounted) return;
    if (t.isEmpty) {
      AppToast.show(context, '剪贴板是空的');
      return;
    }
    final merged = _body.text.isEmpty ? t : '${_body.text}\n$t';
    setState(() {
      _body.text = merged;
      _body.selection = TextSelection.collapsed(offset: merged.length);
      _bodyErr = null;
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_body.text.trim().isEmpty) {
      // 就地红字，补输入即撤（不弹提示条——提示条会自己消失，用户回头看不到成因）。
      // 文案照原型 `#mdNoteErr`＝「先写正文」（另两句＝另造口径，产品未拍）。
      setState(() => _bodyErr = '先写正文');
      return;
    }
    final item = _item;
    if (item == null) {
      AppToast.show(context, '先选一条影音条目');
      return;
    }
    final when = mediaNoteParseWhen(_when.text);
    if (_when.text.trim().isNotEmpty && when == null) {
      setState(() => _bodyErr = null);
      AppToast.show(context, '创建时间没看懂 · 用 2026-03-05 这种写法');
      return;
    }
    setState(() {
      _busy = true;
      _bodyErr = null;
    });
    final note = MediaNote(
      itemId: item.id,
      kind: item.kind,
      noteType: _type,
      body: _body.text,
      tag: _tag.text.trim().isEmpty ? null : _tag.text.trim(),
      atMin: mediaNoteParseAt(_at.text),
      imagePaths: List<String>.from(_images),
      createdAt: when ?? 0,
      origin: widget.origin,
    );
    final repo = ref.read(mediaRepositoryProvider);
    // 「保存」回执要说实话：仓储侧撞在册判重会**返回既有行 id**（连点只落一条），
    // 光看返回值得不出「新记的」还是「已有那条」，所以前后各数一次在册条数——
    // 条数没涨就是同一句已经记过，不许把重复说成成功。
    final before = await repo.noteCount();
    final id = await repo.addNote(note);
    final after = id == null ? before : await repo.noteCount();
    if (!mounted) return;
    setState(() => _busy = false);
    _bump();
    Navigator.of(context).pop(true);
    AppToast.show(
        context,
        id == null
            ? '这条已经记过了 · 内容是同一句'
            : (after > before ? '已记入影音笔记库' : '这条已经记过了 · 内容是同一句'));
  }

  /// L5 联动＝真写入（日记草稿/待办各只接一次，重复点给实话不重复生成）。
  Future<void> _link({required bool toTodo}) async {
    final body = _body.text.trim();
    if (body.isEmpty) {
      setState(() => _bodyErr = '先写正文');
      return;
    }
    if (toTodo ? _linkedTodo : _linkedJournal) {
      AppToast.show(context, toTodo ? '这条已生成过待办' : '这条已插入过今日日记');
      return;
    }
    if (toTodo) {
      await mediaNoteCreateTodo(ref, body: body, itemTitle: _itemTitle);
      if (!mounted) return;
      _linkedTodo = true;
      AppToast.show(context, '已生成待办 · 去待办页可见');
    } else {
      await mediaNoteAppendJournal(ref, body: body, itemTitle: _itemTitle);
      if (!mounted) return;
      _linkedJournal = true;
      AppToast.show(context, '已插入今日日记草稿');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = _item;
    final tags = ref.watch(mediaNoteTagsProvider).valueOrNull ?? const <String>[];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '记一条影音笔记',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              // —— 条目（唯一必选项，从详情/计时进入＝已预置）——
              _fieldLabel('影音条目'),
              InkWell(
                key: const ValueKey('mde-item'),
                borderRadius: BorderRadius.circular(12),
                onTap: _pickItem,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item == null ? '选一条影音条目' : '《${item.title}」'.replaceFirst('」', '》'),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: item == null ? scheme.onSurfaceVariant : null,
                          ),
                        ),
                      ),
                      if (item != null)
                        Text(MediaItem.labelOf(item.kind),
                            style: TextStyle(
                                fontSize: 10, color: scheme.onSurfaceVariant)),
                      const SizedBox(width: 6),
                      Icon(Icons.expand_more, size: 16, color: scheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // —— 类型五 chips（每枚自带该类色标；选中态＝描边＋底色）——
              // 原型的 `border-left:3px solid 类色` 在 Flutter 里不能与圆角共存
              // （BoxDecoration 的圆角只容得下四边同色的 Border，paint 阶段直接炸表单），
              // 落面＝同色竖条画进胶囊内部，视觉语义与词典 LH-C18 一致。
              _fieldLabel('类型'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in MediaNote.noteTypes)
                    GestureDetector(
                      key: ValueKey('mde-type-$t'),
                      onTap: () => setState(() => _type = t),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _type == t
                              ? mediaNoteTypeColor(t).withValues(alpha: .16)
                              : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _type == t
                                ? mediaNoteTypeColor(t)
                                : scheme.outlineVariant,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              key: ValueKey('mde-type-accent-$t'),
                              width: 3,
                              height: 13,
                              decoration: BoxDecoration(
                                color: mediaNoteTypeColor(t),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              MediaNote.typeLabels[t] ?? t,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // —— 两个「何时」并排（拍板④）——
              Row(
                children: [
                  Expanded(
                    child: _textField(
                      key: const ValueKey('mde-at'),
                      controller: _at,
                      label: '时间点',
                      hint: '1:52 或 112',
                      keyboard: const TextInputType.numberWithOptions(signed: false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _textField(
                      key: const ValueKey('mde-when'),
                      controller: _when,
                      label: '创建时间',
                      hint: '默认现在 · 可改 2026-03-05',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // —— 附件截图（缩略位横滚，已有可摘除）——
              _fieldLabel('附件截图'),
              SizedBox(
                height: 68,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < _images.length; i++)
                        Padding(
                          key: ValueKey('mde-img-$i'),
                          padding: const EdgeInsets.only(right: 8),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(
                                  File(_images[i]),
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                    width: 60,
                                    height: 60,
                                    color: scheme.surfaceContainerHighest,
                                    child: Icon(Icons.image_outlined,
                                        size: 18, color: scheme.onSurfaceVariant),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 0,
                                top: 0,
                                child: GestureDetector(
                                  key: ValueKey('mde-img-cut-$i'),
                                  onTap: () => setState(() => _images.removeAt(i)),
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle),
                                    child: const Icon(Icons.close,
                                        size: 12, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      InkWell(
                        key: const ValueKey('mde-img-add'),
                        borderRadius: BorderRadius.circular(10),
                        onTap: _attach,
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Icon(Icons.add, size: 20, color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _textField(
                key: const ValueKey('mde-tag'),
                controller: _tag,
                label: '标签',
                hint: '一个词，如「反复看」',
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in tags.take(8))
                      PillChip(
                        key: ValueKey('mde-tag-pick-$t'),
                        label: t,
                        onTap: () => setState(() => _tag.text = t),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              _textField(
                key: const ValueKey('mde-body'),
                controller: _body,
                label: '正文',
                hint: '写下这一刻',
                maxLines: 4,
                errorText: _bodyErr,
                onChanged: (_) {
                  if (_bodyErr != null) setState(() => _bodyErr = null);
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  // clipAuto 控粘贴钮显隐（LH-C23 铁口径①；关＝不铺，不铺假钮）。
                  if (ref.watch(mediaClipAutoProvider).valueOrNull ?? true) ...[
                    PillChip(
                      key: const ValueKey('mde-paste'),
                      label: '粘贴文本',
                      onTap: _busy ? null : _paste,
                    ),
                    const SizedBox(width: 8),
                  ],
                  // OCR 置灰不隐藏：点击给实话（手机端 title 取不到，拍板⑤）。
                  Opacity(
                    opacity: .45,
                    child: PillChip(
                      key: const ValueKey('mde-ocr'),
                      label: '识图',
                      onTap: () => AppToast.show(
                          context, '未安装识别库 · 可用「＋附件」与「粘贴文本」'),
                    ),
                  ),
                  const Spacer(),
                  PillChip(
                    key: const ValueKey('mde-to-journal'),
                    label: '→ 日记',
                    onTap: _busy ? null : () => _link(toTodo: false),
                  ),
                  const SizedBox(width: 8),
                  PillChip(
                    key: const ValueKey('mde-to-todo'),
                    label: '→ 待办',
                    onTap: _busy ? null : () => _link(toTodo: true),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      key: const ValueKey('mde-cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('mde-save'),
                      onPressed: _busy ? null : _save,
                      child: Text(_busy ? '保存中…' : '保存'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(s,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
      );

  Widget _textField({
    required Key key,
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    String? errorText,
    TextInputType? keyboard,
    ValueChanged<String>? onChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel(label),
        TextField(
          key: key,
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboard,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
            isDense: true,
            filled: true,
            fillColor: scheme.surfaceContainerHighest.withValues(alpha: .5),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: scheme.outlineVariant),
            ),
          ),
        ),
      ],
    );
  }
}

/// 条目选择（枚举对象走选择页，不循环切＝既定口径）。
class _ItemPickerSheet extends StatefulWidget {
  const _ItemPickerSheet({required this.items, this.initial});

  final List<MediaItem> items;
  final String? initial;

  @override
  State<_ItemPickerSheet> createState() => _ItemPickerSheetState();
}

class _ItemPickerSheetState extends State<_ItemPickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final list = _q.trim().isEmpty
        ? widget.items
        : widget.items
            .where((x) => x.title.contains(_q.trim()) || x.creator.contains(_q.trim()))
            .toList();
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('选条目', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('mdp-query'),
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(
              hintText: '搜标题或作者',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 320,
            child: list.isEmpty
                ? const EmptyDashRow(text: '没有匹配的条目')
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final x = list[i];
                      return ListTile(
                        key: ValueKey('mdp-item-${x.id}'),
                        dense: true,
                        leading: Icon(
                          x.id == widget.initial
                              ? Icons.check_circle_outline
                              : Icons.circle_outlined,
                          size: 16,
                          color: x.id == widget.initial ? scheme.primary : null,
                        ),
                        title: Text(x.title, style: const TextStyle(fontSize: 12.5)),
                        subtitle: Text(MediaItem.labelOf(x.kind),
                            style: const TextStyle(fontSize: 10)),
                        onTap: () => Navigator.of(context).pop(x.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ==================== 展示与解析小工具（本模块私有，别处不共享） ====================

/// 五类色标＝原型 `MTYPE_COLOR` 逐值照抄（工单 §0：实现批不另调色板）。
Color mediaNoteTypeColor(String type) => switch (type) {
      MediaNote.kScene => const Color(0xFFDC2626),
      MediaNote.kLine => const Color(0xFFF59E0B),
      MediaNote.kLyric => const Color(0xFF059669),
      MediaNote.kShot => const Color(0xFF6366F1),
      MediaNote.kLong => const Color(0xFF94A3B8),
      _ => const Color(0xFF94A3B8),
    };

/// 时间点读数：存的分钟 → `1:52`（无点＝空串，卡片那行整段缺席而不是补 0:00）。
String mediaNoteAtTx(int? atMin) {
  if (atMin == null) return '';
  final h = atMin ~/ 60, m = atMin % 60;
  return h == 0 ? '$m 分' : '$h:${m.toString().padLeft(2, '0')}';
}

/// 时间点输入 → 分钟（支持 `1:52:14`／`1:52`／`112`；看不懂＝null 不落值，不猜）。
///
/// **出端与反解必须同式**（批5 常驻例抓到）：`mediaNoteAtTx(112)` 出 `1:52`，
/// 所以 `1:52` 必须解回 112 分钟——原先写成 `h * 60 + m ~/ 60`（把分钟又除了一次 60），
/// 表现＝从计时页带进来的时间点一保存变成 1 小时整，且用户重开表单看到 `1:00`。
int? mediaNoteParseAt(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  // 「59 分」这种读数由 [mediaNoteAtTx] 自己产出（计时页预填就走这一式）——
  // 出端能写出来的，反解必须能吃回去，否则保存时时间点会静默丢失。
  final body = t.endsWith('分') ? t.substring(0, t.length - 1).trim() : t;
  final parts = body.split(':');
  if (parts.length == 1) return int.tryParse(parts.first);
  if (parts.length == 2) {
    final h = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }
  if (parts.length == 3) {
    final h = int.tryParse(parts[0]),
        m = int.tryParse(parts[1]),
        s = int.tryParse(parts[2]);
    if (h == null || m == null || s == null) return null;
    return h * 60 + (m * 60 + s) ~/ 60;
  }
  return null;
}

/// 创建时间输入 → 毫秒；**越界值自己卡**（`DateTime.tryParse` 会把 2026-13-99 归一成
/// 2027-04-09，那种「看着像错却存进去了」的读数比存不下更糟）。
int? mediaNoteParseWhen(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(t);
  if (m == null) return null;
  final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  final dt = DateTime(y, mo, d);
  if (dt.month != mo || dt.day != d) return null; // 2 月 30 日这类归一
  return dt.millisecondsSinceEpoch;
}
