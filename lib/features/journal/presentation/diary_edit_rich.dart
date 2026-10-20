part of 'diary_edit_page.dart';

// 治理还债（日记改版批1 后·2026-10-19）：批2b 富文本群自 _DiaryEditPageState
// 移入同库扩展（**行为零改动·纯机械搬迁**），主文件 1262→1200 以下，清掉
// size_budget 里延宕已久的越线登记（登记项随后删除，让闸回到「超线即红」默认面）。
//
// 搬迁范围＝文档↔Delta JSON 互转 / 重建与监听 / 行内属性开关（粗体·列表·待办·引用）/
// 插图 / 导图卡片嵌入 / 光标处插文本。手法与 `note_edit_rich.dart` 同款（同库同构）。
extension _DiaryEditRich on _DiaryEditPageState {
  /* ---------- 批2b · 富文本（与笔记 rich 同构·note_edit_page 同款手法） ---------- */

  Document _richDocFromContent(String content) {
    if (content.trim().isNotEmpty) {
      try {
        final data = jsonDecode(content);
        if (data is List) return Document.fromJson(data);
      } catch (_) {}
    }
    return Document.fromJson([
      {'insert': content.isEmpty ? '\n' : '$content\n'}
    ]);
  }

  QuillController _newRich(String content) => QuillController(
      document: _richDocFromContent(content),
      selection: const TextSelection.collapsed(offset: 0))
    ..addListener(_onRichChanged);

  /// 载入回填：换文档重建控制器（旧实例摘监听后释放），不标脏。
  void _rebuildRich(String content) {
    final old = _richCtl;
    old?.removeListener(_onRichChanged);
    final c = _newRich(content);
    _lastRichJson = jsonEncode(c.document.toDelta().toJson());
    // ignore: invalid_use_of_protected_member
    setState(() => _richCtl = c);
    old?.dispose();
  }

  /// Quill 变更 → Delta JSON 比对过滤（选区变化也 notify），走既有防抖自动存草稿。
  void _onRichChanged() {
    if (!mounted) return;
    final c = _richCtl;
    if (c == null) return;
    final json = jsonEncode(c.document.toDelta().toJson());
    if (json == _lastRichJson) return;
    _lastRichJson = json;
    _onChanged(json);
  }

  void _richToggle(Attribute<dynamic> attr) {
    final c = _richCtl;
    if (c == null) return;
    final has = c.getSelectionStyle().attributes.containsKey(attr.key);
    c.formatSelection(has ? Attribute.clone(attr, null) : attr);
  }

  /// ≡ 列表：已是项目符号则还原，其余直切。
  void _richListAs(Attribute target) {
    final c = _richCtl;
    if (c == null) return;
    final cur = c.getSelectionStyle().attributes['list'];
    c.formatSelection(cur == target ? Attribute.clone(target, null) : target);
  }

  /// ☑ 键：无列表→待办(未勾)→已勾→清；其他列表型→待办。
  void _richTask() {
    final c = _richCtl;
    if (c == null) return;
    final cur = c.getSelectionStyle().attributes['list'];
    if (cur == null || cur == Attribute.ul || cur == Attribute.ol) {
      c.formatSelection(Attribute.unchecked);
    } else if (cur == Attribute.unchecked) {
      c.formatSelection(Attribute.checked);
    } else {
      c.formatSelection(Attribute.clone(Attribute.checked, null));
    }
  }

  /// 拍照/相册插图：公共链直取来源（跳过选择弹层）→ 当前选区内嵌 image embed。
  Future<void> _richImage({ImageSource? direct}) async {
    final tokens = context.tokens;
    final dest = await pickAndStoreImage(context,
        bg: tokens.card,
        fg: Theme.of(context).colorScheme.onSurface,
        direct: direct);
    if (dest == null || !mounted) return;
    final c = _richCtl;
    if (c == null) return;
    final idx = c.selection.baseOffset < 0
        ? c.document.length - 1
        : c.selection.baseOffset;
    c.replaceText(idx, 0, BlockEmbed.image(dest),
        TextSelection.collapsed(offset: idx + 1));
  }

  /// 连接点② 插导图卡片（批2 面5）：挑图 → 正文插 BlockEmbed（只存 map_id）。
  Future<void> _insertMmCard() async {
    final c = _richCtl;
    if (c == null) return;
    final mapId = await showMmCardPickSheet(context);
    if (mapId == null || !mounted) return;
    final idx =
        c.selection.baseOffset < 0 ? c.document.length - 1 : c.selection.baseOffset;
    c.replaceText(idx, 0, mmCardEmbed(mapId),
        TextSelection.collapsed(offset: idx + 1));
    c.replaceText(idx + 1, 0, '\n', TextSelection.collapsed(offset: idx + 2));
  }

  /// 概览插入正文：当前光标处逐行插入纯文本。
  void _insertAtCursor(String text) {
    final c = _richCtl;
    if (c == null) return;
    final pos = c.selection.baseOffset < 0 ? c.document.length - 1 : c.selection.baseOffset;
    c.replaceText(pos, 0, text,
        TextSelection.collapsed(offset: pos + text.length));
  }
}
