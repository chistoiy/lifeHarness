import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../shared/linkage/stats_providers.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/md_shortcut.dart';
import 'journal_providers.dart';
import 'widgets/md_view.dart';
import 'widgets/note_sheets.dart';

/// 编辑器四模式（原型 p-noteEdit · 批1b）：专注段落 / MD 源码 / 分屏 / 预览。
enum NoteEditMode { focus, src, split, view }

/// 纸色（原型 PW_PAPERS）：米纸 / 纯白 / 护眼绿 / 深夜。
const notePapers = <(Color, Color)>[
  (Color(0xFFFBF8F1), Color(0xFF403A31)),
  (Color(0xFFFFFFFF), Color(0xFF334155)),
  (Color(0xFFEDF3EA), Color(0xFF37412F)),
  (Color(0xFF1E1D1B), Color(0xFFCFC9BD)),
];

/// MD 底部主条（原型轮8 renderPwBar · pw-tool 顺序与图形）：
/// ↺↻ | H#（点开二级 H1~H6）B I S <> ❝ ≡ ☑ ▦ 🖼 🔗 ƒx ∑ —
const _mdTools = <(String, String, String)>[
  ('undo', '↺', '撤销'),
  ('redo', '↻', '重做'),
  ('h', 'H#', '标题（点开后在下方选 H1~H6）'),
  ('bold', 'B', '加粗'),
  ('ital', 'I', '斜体'),
  ('strike', 'S', '删除线'),
  ('code', '<>', '行内代码'),
  ('quote', '❝', '引用'),
  ('ul', '≡', '无序列表'),
  ('task', '☑', '待办项'),
  ('table', '▦', '表格'),
  ('img', '🖼', '图片'),
  ('link', '🔗', '链接'),
  ('math', 'ƒx', '行内公式'),
  ('mathb', '∑', '块级公式 LaTeX'),
  ('hr', '—', '分割线'),
];

/// 笔记编辑页（原型 p-noteEdit · 纯纯写作纸感）：
/// 专注段落（点段聚焦·🎯 聚焦淡出其余）· MD 源码 · 分屏 · 预览 ·
/// 14 键快捷栏（H 循环标题级）· 字号滑杆与四纸色底栏 ·
/// 900ms 自动保存（输入即存）· 字数与阅读时长 · 文件夹/置顶/plain·MD；
/// 渲染层=批1c，快照与导出=批1d。
class NoteEditPage extends ConsumerStatefulWidget {
  const NoteEditPage(
      {super.key, this.noteId, this.initialKind = 'plain', this.initialFolder = ''});

  final int? noteId;

  /// 新建时的笔记类型与归属文件夹（V1.29 FAB 三选 · 当前选中目录）。
  final String initialKind;
  final String initialFolder;

  @override
  ConsumerState<NoteEditPage> createState() => _NoteEditPageState();
}

/// /note/edit 路由参数：打开既有篇或按类型新建（V1.29轮2 FAB 竖排三选）。
class NoteEditArg {
  const NoteEditArg(
      {this.noteId, this.kind = 'plain', this.folder = ''});

  final int? noteId;
  final String kind;
  final String folder;
}

class _NoteEditPageState extends ConsumerState<NoteEditPage> {
  static const _brand = Color(0xFF6366F1);

  final _titleCtl = TextEditingController();
  final _titleFocus = FocusNode();
  final _bodyCtl = TextEditingController();
  final _bodyFocus = FocusNode();
  final List<TextEditingController> _paras = [];
  final List<FocusNode> _paraNodes = [];

  Note? _existing;
  String _folder = '';
  bool _pinned = false;
  String _kind = 'plain';
  bool _dirty = false;
  bool _saved = false;
  Timer? _debounce;

  // 版本快照（批1d · 原型 sheetSnapshot）：停输 30s / 每 +500 字自动留存。
  Timer? _snapIdle;
  String _lastSnapText = '';
  int _snapBaseWords = 0;

  NoteEditMode _mode = NoteEditMode.focus;
  int _paperIdx = 0;
  double _font = 15;
  bool _focusOn = false;
  int _curPara = 0;

  // V1.29批B · 富文本（原型 pwRichBar）：kind=rich 时正文=Quill Delta JSON，
  // 编辑即 WYSIWYG，_bodyCtl 仍是持久层单一真源（监听里同步 JSON 文本）。
  QuillController? _richCtl;
  String _lastRichJson = '';
  final _richFocus = FocusNode();
  final _richScroll = ScrollController();

  // V1.29轮8 · 底部快捷栏：二级行展开态（''/h/tt/lay）与 MD 工具级撤销栈。
  String _pwSub = '';
  final List<({String text, int caret})> _mdUndo = [];
  final List<({String text, int caret})> _mdRedo = [];

  // 轮8③：编辑页左右滑动=按当前排序+筛选切上/下一篇（原型 pwSwipe）。
  // Listener 旁路追踪（不参与竞技场·不与文本选择/滚动互斥），一次按下只触发一回。
  Offset? _swDown;
  bool _swFired = false;
  bool _swiping = false;

  bool get _hasTextFocus =>
      _bodyFocus.hasFocus ||
      _richFocus.hasFocus ||
      _titleFocus.hasFocus ||
      _paraNodes.any((f) => f.hasFocus);

  bool get _isRich => _kind == 'rich';

  Color get _bg => notePapers[_paperIdx].$1;
  Color get _fg => notePapers[_paperIdx].$2;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onGlobalKey);
    _kind = widget.initialKind;
    _folder = widget.initialFolder;
    _resetParas('');
    _richCtl = _newRich('');
    _load();
  }

  Future<void> _load() async {
    if (widget.noteId == null) return;
    final n = await ref.read(noteDaoProvider).byId(widget.noteId!);
    if (n == null || !mounted) return;
    setState(() {
      _existing = n;
      _titleCtl.text = n.title;
      _bodyCtl.text = n.content;
      _folder = n.folder ?? '';
      _pinned = n.pinned;
      _kind = n.kind;
      _snapBaseWords = n.wordCount;
      _resetParas(n.content);
    });
    if (_kind == 'rich') _rebuildRich(n.content);
    // 断点续写（草稿提醒）：最近快照比当前稿更完整时提示可从 🕘 恢复。
    final snaps = await ref.read(noteDaoProvider).snapshotsOf(n.id!);
    if (snaps.isEmpty || !mounted) return;
    final latest = Note.richToPlain((snaps.first['content'] as String?) ?? '');
    final gain = latest.replaceAll(RegExp(r'\s'), '').length -
        Note.richToPlain(n.content).replaceAll(RegExp(r'\s'), '').length;
    if (gain > 0 && latest != Note.richToPlain(n.content)) {
      AppToast.show(context, '🕘 有比当前更完整的快照（+$gain 字）· 可从版本快照恢复');
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onGlobalKey);
    _debounce?.cancel();
    _snapIdle?.cancel();
    _titleCtl.dispose();
    _titleFocus.dispose();
    _bodyCtl.dispose();
    _bodyFocus.dispose();
    _richCtl?.removeListener(_onRichChanged);
    _richCtl?.dispose();
    _richFocus.dispose();
    _richScroll.dispose();
    for (final c in _paras) {
      c.dispose();
    }
    for (final f in _paraNodes) {
      f.dispose();
    }
    super.dispose();
  }

  // ---------- 专注模式：段落即编辑（原型 pwBody 段击聚焦 · pw-focus 淡出） ----------

  void _disposeLater(List<Object> disposable) {
    if (disposable.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final d in disposable) {
        if (d is TextEditingController) d.dispose();
        if (d is FocusNode) d.dispose();
        if (d is QuillController) d.dispose();
      }
    });
  }

  FocusNode _newParaNode() {
    late final FocusNode node;
    node = FocusNode()
      ..addListener(() {
        if (!node.hasFocus) return;
        final idx = _paraNodes.indexOf(node);
        if (idx != -1 && idx != _curPara) setState(() => _curPara = idx);
      });
    return node;
  }

  // V1.29轮1①：专注模式段首退格=并入上一段。EditableText 内部 Shortcuts
  // 会先吞掉冒泡的退格键，故用 HardwareKeyboard 全局前置拦截。
  bool _onGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    // 轮8③：桌面 ←/→ 切上/下一篇（有输入焦点时归光标移动，不拦截）。
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (_hasTextFocus) return false;
      _switchNote(event.logicalKey == LogicalKeyboardKey.arrowRight ? 1 : -1);
      return true;
    }
    if (_isRich) return false; // 富文本段落结构由 Quill 自管
    if (_mode != NoteEditMode.focus || !mounted) return false;
    if (event.logicalKey != LogicalKeyboardKey.backspace) return false;
    final i = _curPara;
    if (i <= 0 || i >= _paras.length) return false;
    final ctl = _paras[i];
    final s = ctl.selection;
    if (!s.isCollapsed || s.start != 0) return false;
    if (!_paraNodes[i].hasFocus) return false;
    final prev = _paras[i - 1];
    final at = prev.text.length;
    prev.value = TextEditingValue(
        text: prev.text + ctl.text,
        selection: TextSelection.collapsed(offset: at));
    final old = <Object>[_paras[i], _paraNodes[i]];
    _paras.removeAt(i);
    _paraNodes.removeAt(i);
    _disposeLater(old);
    setState(() => _curPara = i - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _paraNodes[_curPara].requestFocus();
    });
    _flushParas();
    return true;
  }

  void _resetParas(String text) {
    final stale = <Object>[..._paras, ..._paraNodes];
    _paras
      ..clear()
      ..addAll((text.isEmpty ? [''] : text.split('\n\n'))
          .map((s) => TextEditingController(text: s)));
    _paraNodes
      ..clear()
      ..addAll(List.generate(_paras.length, (_) => _newParaNode()));
    _curPara = math.min(_curPara, _paras.length - 1);
    _disposeLater(stale);
  }

  /// 段落全文 → _bodyCtl（单一真源·自动保存与持久层都读它）。
  /// 文本无变化时整体跳过：避免打开即切篇等无编辑场景误标脏、
  /// 重写 updated_at 导致列表顺序被悄悄打乱（轮8③）。
  void _flushParas() {
    final joined = _paras.map((c) => c.text).join('\n\n');
    if (_bodyCtl.text == joined) return;
    _bodyCtl.value = TextEditingValue(
        text: joined,
        selection: TextSelection.collapsed(offset: joined.length));
    _onChanged(joined);
  }

  void _paraChanged(int i, String v) {
    if (v.contains('\n\n')) {
      final segs = v.split('\n\n');
      final fresh = [
        for (final s in segs)
          (TextEditingController(text: s), _newParaNode())
      ];
      final old = <Object>[_paras[i], _paraNodes[i]];
      _paras.replaceRange(i, i + 1, fresh.map((e) => e.$1));
      _paraNodes.replaceRange(i, i + 1, fresh.map((e) => e.$2));
      _disposeLater(old);
      _curPara = i + segs.length - 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _paraNodes[_curPara].requestFocus();
      });
    }
    _flushParas();
  }

  Widget _paraField(int i) {
    final dimmed = _focusOn && _curPara != i;
    final isCur = _curPara == i;
    return TextField(
      key: ValueKey('note-para-$i'),
      controller: _paras[i],
      focusNode: _paraNodes[i],
      maxLines: null,
      minLines: 1,
      keyboardType: TextInputType.multiline,
      style: TextStyle(
          fontSize: _font,
          color: _fg.withValues(alpha: dimmed ? .22 : 1),
          height: 2.15,
          letterSpacing: .3),
      decoration: InputDecoration(
        border: InputBorder.none,
        isDense: true,
        filled: isCur,
        fillColor: _fg.withValues(alpha: .07),
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        hintText: i == 0 ? '写下第一个字…（自动保存，不怕丢稿）' : null,
        hintStyle: TextStyle(color: _fg.withValues(alpha: .4), letterSpacing: .3),
      ),
      onChanged: (v) => _paraChanged(i, v),
    );
  }

  // ---------- V1.29批B · 富文本（原型 pwRichBar · flutter_quill WYSIWYG） ----------

  /// content → Quill 文档：优先按 Delta JSON 解析；非 JSON（旧占位/纯文本
  /// 切过来）容错包成单段纯文本。
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

  /// 换文档（载入/快照恢复/类型切入）：重建控制器并同步 _bodyCtl 单一真源。
  void _rebuildRich(String content) {
    final old = _richCtl;
    old?.removeListener(_onRichChanged);
    final c = _newRich(content);
    _lastRichJson = jsonEncode(c.document.toDelta().toJson());
    if (_bodyCtl.text != content) {
      _bodyCtl.value = TextEditingValue(
          text: content,
          selection: TextSelection.collapsed(offset: content.length));
    }
    setState(() => _richCtl = c);
    if (old != null) _disposeLater([old]);
  }

  /// Quill 变更 → Delta JSON 写回 _bodyCtl 并走既有自动保存链路。
  /// 控制器选区变化也会 notify，用 JSON 比对过滤，避免空触发。
  void _onRichChanged() {
    if (!mounted) return;
    final c = _richCtl;
    if (c == null) return;
    final json = jsonEncode(c.document.toDelta().toJson());
    if (json == _lastRichJson) return;
    _lastRichJson = json;
    if (_bodyCtl.text != json) {
      _bodyCtl.value = TextEditingValue(
          text: json,
          selection: TextSelection.collapsed(offset: json.length));
    }
    _onChanged(json);
  }

  void _richToggle(Attribute<dynamic> attr) {
    final c = _richCtl;
    if (c == null) return;
    final has = c.getSelectionStyle().attributes.containsKey(attr.key);
    c.formatSelection(has ? Attribute.clone(attr, null) : attr);
  }

  /// tt 二级（原型 pwRichHead）：N 还原正文 / H1~H3 直选标题级。
  void _richSetHeader(int level) {
    final c = _richCtl;
    if (c == null) return;
    if (level == 0) {
      c.formatSelection(Attribute.clone(Attribute.h1, null));
    } else {
      c.formatSelection([Attribute.h1, Attribute.h2, Attribute.h3][level - 1]);
    }
  }

  /// lay 二级（原型 pwRich）：ol/ul/居中 在「已是该型」时还原，其余直切。
  void _richListAs(Attribute target) {
    final c = _richCtl;
    if (c == null) return;
    final cur = c.getSelectionStyle().attributes['list'];
    c.formatSelection(cur == target ? Attribute.clone(target, null) : target);
  }

  void _richCenter() {
    final c = _richCtl;
    if (c == null) return;
    const attr = Attribute.centerAlignment;
    final has = c.getSelectionStyle().attributes.containsKey(attr.key);
    c.formatSelection(has ? Attribute.clone(attr, null) : attr);
  }

  /// 🔗 链接：底部轻输入框 → LinkAttribute 作用于选区。
  Future<void> _richLink() async {
    final c = _richCtl;
    if (c == null) return;
    final urlCtl = TextEditingController();
    final url = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _bg,
      isScrollControlled: true,
      builder: (bc) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, MediaQuery.of(bc).viewInsets.bottom + 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('note-link-input'),
                controller: urlCtl,
                autofocus: true,
                keyboardType: TextInputType.url,
                style: TextStyle(fontSize: 13.5, color: _fg),
                decoration: InputDecoration(
                  labelText: 'https://…',
                  labelStyle: TextStyle(color: _fg.withValues(alpha: .55)),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: _fg.withValues(alpha: .3))),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: _brand)),
                ),
              ),
            ),
            TextButton(
              key: const ValueKey('note-link-ok'),
              onPressed: () => Navigator.of(bc).pop(urlCtl.text.trim()),
              child: const Text('确定', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
    urlCtl.dispose();
    if (url == null || url.isEmpty || !mounted) return;
    c.formatSelection(LinkAttribute(url));
    AppToast.show(context, '🔗 已添加链接');
  }

  /// Aa 字号：滑杆弹层（与底栏字号滑杆同一状态源）。
  Future<void> _openFontSheet() async {
    setState(() => _pwSub = '');
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _bg,
      builder: (bc) => SafeArea(
        child: StatefulBuilder(
          builder: (bc, setSheet) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Row(
              children: [
                Text('字号',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: _fg)),
                Expanded(
                  child: Slider(
                    key: const ValueKey('note-font-sheet'),
                    value: _font,
                    min: 13,
                    max: 19,
                    divisions: 6,
                    activeColor: _brand,
                    inactiveColor: _fg.withValues(alpha: .2),
                    onChanged: (v) {
                      setSheet(() {});
                      setState(() => _font = v);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// ☑ 键：无列表→待办(未勾)→已勾→清；其他列表型→待办。
  void _richTask() {
    final c = _richCtl;
    if (c == null) return;
    final cur = c.getSelectionStyle().attributes['list'];
    if (cur == null) {
      c.formatSelection(Attribute.unchecked);
    } else if (cur == Attribute.unchecked) {
      c.formatSelection(Attribute.checked);
    } else if (cur == Attribute.checked) {
      c.formatSelection(Attribute.clone(Attribute.checked, null));
    } else {
      c.formatSelection(Attribute.unchecked);
    }
  }

  /// 🖼 插图共享链（原型 sheetImgSrc）：相册/拍照弹层 → 拷贝应用目录 →
  /// 返回落盘路径（任一步取消/失败=null）。rich 嵌 Delta，plain 插 MD 语法。
  Future<String?> _pickImage() async {
    final src = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _bg,
      builder: (bc) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('img-gallery'),
              title: Text('🖼 从相册选择',
                  style: TextStyle(fontSize: 13.5, color: _fg)),
              onTap: () => Navigator.of(bc).pop('gallery'),
            ),
            ListTile(
              key: const ValueKey('img-camera'),
              title: Text('📷 拍照',
                  style: TextStyle(fontSize: 13.5, color: _fg)),
              onTap: () => Navigator.of(bc).pop('camera'),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (src == null || !mounted) return null;
    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
          source: src == 'camera' ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 1600,
          imageQuality: 88);
    } catch (e) {
      if (mounted) AppToast.show(context, '📷 相机/相册暂不可用');
      return null;
    }
    if (picked == null || !mounted) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final outDir = Directory(p.join(dir.path, 'note_images'));
      if (!await outDir.exists()) await outDir.create(recursive: true);
      final dot = picked.path.lastIndexOf('.');
      final ext = dot > 0 ? picked.path.substring(dot + 1).toLowerCase() : 'jpg';
      final dest = p.join(
          outDir.path, '${DateTime.now().millisecondsSinceEpoch}.$ext');
      await File(picked.path).copy(dest);
      return mounted ? dest : null;
    } catch (_) {
      if (mounted) AppToast.show(context, '插图失败 · 请重试');
      return null;
    }
  }

  /// rich 插图：Delta image 嵌入当前选区处。
  /// 不引 flutter_quill_extensions（其 super_native_extensions 原生链在本机
  /// 网络受限环境构建风险大），渲染由本页 _NoteImageEmbedBuilder 承担。
  Future<void> _richImage() async {
    final dest = await _pickImage();
    if (dest == null || !mounted) return;
    final c = _richCtl;
    if (c == null) return;
    final idx = c.selection.baseOffset < 0
        ? c.document.length - 1
        : c.selection.baseOffset;
    c.replaceText(idx, 0, BlockEmbed.image(dest),
        TextSelection.collapsed(offset: idx + 1));
    AppToast.show(context, '🖼 已插入图片');
  }

  /// 轮8①：纯文本「＋」附件卡 → 走同一插图链 → 当前段尾插 MD 图片语法。
  Future<void> _plainAttach() async {
    final dest = await _pickImage();
    if (dest == null || !mounted) return;
    final i = _curPara.clamp(0, _paras.length - 1);
    final ctl = _paras[i];
    final text =
        '${ctl.text}${ctl.text.isEmpty || ctl.text.endsWith('\n') ? '' : '\n'}![🖼]($dest)';
    ctl.value = TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
    _flushParas();
    AppToast.show(context, '🖼 已插入图片');
  }

  /// 纸感样式：正文/三级标题/列表/引用/占位符随 _fg 与字号滑杆。
  DefaultStyles _richStyles() {
    const hs = HorizontalSpacing(0, 0);
    TextStyle t(double size, {Color? color, FontWeight? w, FontStyle? f}) =>
        TextStyle(
            fontSize: size,
            color: color ?? _fg,
            height: 2.0,
            letterSpacing: .3,
            fontWeight: w,
            fontStyle: f);
    return DefaultStyles(
      color: _fg,
      paragraph:
          DefaultTextBlockStyle(t(_font), hs, const VerticalSpacing(6, 0), const VerticalSpacing(0, 0), null),
      h1: DefaultTextBlockStyle(
          t(_font + 9, w: FontWeight.w900), hs, const VerticalSpacing(10, 2), const VerticalSpacing(0, 0), null),
      h2: DefaultTextBlockStyle(
          t(_font + 6, w: FontWeight.w900), hs, const VerticalSpacing(8, 2), const VerticalSpacing(0, 0), null),
      h3: DefaultTextBlockStyle(
          t(_font + 3, w: FontWeight.w800), hs, const VerticalSpacing(6, 2), const VerticalSpacing(0, 0), null),
      lists: DefaultListBlockStyle(t(_font), hs,
          const VerticalSpacing(6, 0), const VerticalSpacing(0, 0), null, null),
      quote: DefaultTextBlockStyle(
          t(_font, color: _fg.withValues(alpha: .65), f: FontStyle.italic),
          hs,
          const VerticalSpacing(6, 0),
          const VerticalSpacing(0, 0),
          null),
      placeHolder: DefaultTextBlockStyle(
          t(_font, color: _fg.withValues(alpha: .4)),
          hs,
          const VerticalSpacing(6, 0),
          const VerticalSpacing(0, 0),
          null),
    );
  }

  Widget _titleField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: TextField(
        key: const ValueKey('note-title'),
        controller: _titleCtl,
        focusNode: _titleFocus,
        onChanged: _onChanged,
        style: TextStyle(
            fontSize: _font + 6,
            fontWeight: FontWeight.w900,
            color: _fg,
            height: 1.5),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: '标题',
          hintStyle: TextStyle(
              color: _fg.withValues(alpha: .35), fontWeight: FontWeight.w300),
        ),
      ),
    );
  }

  Widget _richEditor() {
    return Column(
      children: [
        _titleField(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Divider(color: _fg.withValues(alpha: .1), height: 20),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: QuillEditor(
              key: const ValueKey('note-rich-editor'),
              controller: _richCtl!,
              focusNode: _richFocus,
              scrollController: _richScroll,
              config: QuillEditorConfig(
                placeholder: '写下第一个字…（自动保存，不怕丢稿）',
                padding: EdgeInsets.zero,
                expands: true,
                customStyles: _richStyles(),
                embedBuilders: const [_NoteImageEmbedBuilder()],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 底部快捷栏通用按钮（原型 pw-tool 30×28 · 纯符号，中文只进悬停提示）。
  Widget _pwBtn(String key, String glyph, VoidCallback onTap, String tip,
      {FontWeight w = FontWeight.w800,
      FontStyle? f,
      TextDecoration? d,
      String? fontFamily}) {
    return Tooltip(
      message: tip,
      child: GestureDetector(
        key: ValueKey(key),
        onTap: onTap,
        child: Container(
          width: 30,
          height: 28,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center,
          child: Text(glyph,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: w,
                  fontStyle: f,
                  fontFamily: fontFamily,
                  decoration: d,
                  color: _fg.withValues(alpha: .75))),
        ),
      ),
    );
  }

  Widget _pwSep() => Container(
      width: 1,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: _fg.withValues(alpha: .25));

  /// 轮8②⑥：主条+二级行整体贴底（拇指热区）；plain 无条（＋附件卡承担插图）。
  Widget _toolBarArea() {
    final rich = _isRich;
    if (!rich && _kind != 'md') return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: _fg.withValues(alpha: .12))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pwSub.isNotEmpty) _pwSubRow(rich),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: rich
                  ? [
                      _pwBtn('note-rich-undo', '↺', () => _richCtl?.undo(), '撤销'),
                      _pwBtn('note-rich-redo', '↻', () => _richCtl?.redo(), '重做'),
                      _pwSep(),
                      _pwBtn('note-rich-tt', 'Tt',
                          () => setState(
                              () => _pwSub = _pwSub == 'tt' ? '' : 'tt'),
                          '字号·标题（点开二级）'),
                      _pwBtn('note-rich-lay', '≡',
                          () => setState(
                              () => _pwSub = _pwSub == 'lay' ? '' : 'lay'),
                          '排版（点开二级）'),
                      _pwBtn('note-rich-bold', 'B',
                          () => _richToggle(Attribute.bold), '加粗'),
                      _pwBtn('note-rich-ital', 'I',
                          () => _richToggle(Attribute.italic), '斜体',
                          f: FontStyle.italic),
                      _pwBtn('note-rich-under', 'U',
                          () => _richToggle(Attribute.underline), '下划线',
                          d: TextDecoration.underline),
                      _pwBtn('note-rich-strike', 'S',
                          () => _richToggle(Attribute.strikeThrough), '删除线',
                          d: TextDecoration.lineThrough),
                      _pwBtn('note-rich-code', '<>',
                          () => _richToggle(Attribute.inlineCode), '行内代码',
                          fontFamily: 'monospace'),
                      _pwBtn('note-rich-quote', '❝',
                          () => _richToggle(Attribute.blockQuote), '引用'),
                      _pwBtn('note-rich-task', '☑', _richTask, '待办行'),
                      _pwBtn('note-rich-table', '▦',
                          () => AppToast.show(context, '表格 · 富文本版即将开放'),
                          '表格'),
                      _pwBtn('note-rich-link', '🔗', _richLink, '链接',
                          w: FontWeight.w400),
                      _pwBtn('note-rich-img', '🖼', _richImage, '插图',
                          w: FontWeight.w400),
                    ]
                  : [
                      for (final (k, glyph, tip) in _mdTools) ...[
                        if (k == 'h') _pwSep(),
                        _mdToolBtn(k, glyph, tip),
                      ],
                    ],
            ),
          ),
        ],
      ),
    );
  }

  /// 二级行（原型 pwSubRow）：纯符号 pw-tool 同款；滑到尾部自动收起。
  Widget _pwSubRow(bool rich) {
    final items = <Widget>[
      if (_pwSub == 'h' && !rich)
        for (var lv = 1; lv <= 6; lv++)
          _pwBtn('note-h-$lv', 'H$lv', () => _mdSetHeading(lv), 'H$lv'),
      if (_pwSub == 'tt' && rich) ...[
        _pwBtn('note-rich-tt-plain', 'N', () => _richSetHeader(0), '正文'),
        _pwBtn('note-rich-tt-h1', 'H1', () => _richSetHeader(1), 'H1'),
        _pwBtn('note-rich-tt-h2', 'H2', () => _richSetHeader(2), 'H2'),
        _pwBtn('note-rich-tt-h3', 'H3', () => _richSetHeader(3), 'H3'),
        _pwBtn('note-rich-tt-font', 'Aa', _openFontSheet, '字号滑杆',
            f: FontStyle.italic),
      ],
      if (_pwSub == 'lay' && rich) ...[
        _pwBtn('note-rich-lay-ol', '1.', () => _richListAs(Attribute.ol),
            '有序列表'),
        _pwBtn('note-rich-lay-ul', '•', () => _richListAs(Attribute.ul),
            '无序列表'),
        _pwBtn('note-rich-lay-task', '☑', _richTask, '任务行'),
        _pwBtn('note-rich-lay-center', '↔', _richCenter, '居中'),
        _pwBtn('note-rich-lay-indent', '⇥', () => _richCtl?.indentSelection(true),
            '缩进'),
        _pwBtn('note-rich-lay-outdent', '⇤',
            () => _richCtl?.indentSelection(false), '取消缩进'),
      ],
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (n) {
        if (n.metrics.axis == Axis.horizontal &&
            n.metrics.maxScrollExtent > 0 &&
            n.metrics.pixels >= n.metrics.maxScrollExtent - 6) {
          setState(() => _pwSub = '');
          AppToast.show(context, '已收起二级栏');
        }
        return false;
      },
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(10, 3, 10, 1),
        child: Row(
          children: [
            ...items,
            _pwBtn('note-sub-close', '✕', () => setState(() => _pwSub = ''),
                '收起'),
          ],
        ),
      ),
    );
  }

  // ---------- 模式 / 快捷栏 / 纸感 ----------

  void _setMode(NoteEditMode m) {
    if (m == _mode) return;
    if (_mode == NoteEditMode.focus) _flushParas();
    setState(() {
      _mode = m;
      if (m == NoteEditMode.focus) _resetParas(_bodyCtl.text);
    });
    if (m != NoteEditMode.focus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _mode != NoteEditMode.focus) _bodyFocus.requestFocus();
      });
    }
  }

  void _tool(String k) {
    if (_mode == NoteEditMode.focus) {
      AppToast.show(context, '当前为专注模式 · 切 ⌨️源码 或 🔀分屏 后可用 MD 快捷栏');
      return;
    }
    _mdPushUndo();
    final sel = _bodyCtl.selection;
    final r = applyMdShortcut(
        k, _bodyCtl.text, sel.isValid ? sel.start : _bodyCtl.text.length,
        sel.isValid ? sel.end : _bodyCtl.text.length);
    _bodyCtl.value = TextEditingValue(
        text: r.text, selection: TextSelection.collapsed(offset: r.caret));
    _onChanged(r.text);
    _bodyFocus.requestFocus();
    AppToast.show(context, r.label);
  }

  /// 底部 MD 主条路由：h 开二级行，↺↻ 走工具级撤销栈，其余即插语法。
  void _mdBarTap(String k) {
    if (k == 'h') {
      setState(() => _pwSub = _pwSub == 'h' ? '' : 'h');
      return;
    }
    if (k == 'undo') return _mdUndoStep();
    if (k == 'redo') return _mdRedoStep();
    _tool(k);
  }

  void _mdPushUndo() {
    final s = _bodyCtl.selection;
    _mdUndo.add((
      text: _bodyCtl.text,
      caret: s.isValid ? s.start : _bodyCtl.text.length
    ));
    if (_mdUndo.length > 60) _mdUndo.removeAt(0);
    _mdRedo.clear();
  }

  void _mdApply(({String text, int caret}) r) {
    _bodyCtl.value = TextEditingValue(
        text: r.text, selection: TextSelection.collapsed(offset: r.caret));
    _onChanged(r.text);
    _bodyFocus.requestFocus();
  }

  void _mdUndoStep() {
    if (_mode == NoteEditMode.focus) {
      AppToast.show(context, '当前为专注模式 · 切 ⌨️源码 或 🔀分屏 后可用 MD 快捷栏');
      return;
    }
    if (_mdUndo.isEmpty) {
      AppToast.show(context, '已无更早的快捷操作');
      return;
    }
    final s = _bodyCtl.selection;
    _mdRedo.add((
      text: _bodyCtl.text,
      caret: s.isValid ? s.start : _bodyCtl.text.length
    ));
    _mdApply(_mdUndo.removeLast());
  }

  void _mdRedoStep() {
    if (_mode == NoteEditMode.focus) {
      AppToast.show(context, '当前为专注模式 · 切 ⌨️源码 或 🔀分屏 后可用 MD 快捷栏');
      return;
    }
    if (_mdRedo.isEmpty) {
      AppToast.show(context, '已无更晚的快捷操作');
      return;
    }
    final s = _bodyCtl.selection;
    _mdUndo.add((
      text: _bodyCtl.text,
      caret: s.isValid ? s.start : _bodyCtl.text.length
    ));
    _mdApply(_mdRedo.removeLast());
  }

  /// 二级行 H1~H6 直选（原型 pwMdHead）：光标行行首 # 数置为 lv。
  void _mdSetHeading(int lv) {
    if (_mode == NoteEditMode.focus) {
      AppToast.show(context, '当前为专注模式 · 切 ⌨️源码 或 🔀分屏 后可用 MD 快捷栏');
      return;
    }
    _mdPushUndo();
    final text = _bodyCtl.text;
    final sel = _bodyCtl.selection;
    final start = sel.isValid ? sel.start : text.length;
    final ls = text.lastIndexOf('\n', start - 1) + 1;
    var ne = text.indexOf('\n', ls);
    if (ne == -1) ne = text.length;
    final rest = text.substring(ls, ne).replaceFirst(RegExp(r'^#{1,6}\s?'), '');
    final nl = '${'#' * lv} $rest';
    _mdApply((text: text.substring(0, ls) + nl + text.substring(ne), caret: ls + nl.length));
    AppToast.show(context, '标题级别：h$lv');
  }

  /// 🕘 快照弹层（经 ⋯ 菜单进入）：恢复=按记录管理设置替换正文或新增副本。
  void _openSnap() => showSnapshotSheet(context, ref, _existing, _bg, _fg,
      currentBody: _bodyCtl.text,
      onReplace: (content) {
        if (_isRich) {
          _rebuildRich(content);
          _onChanged(content);
          return;
        }
        setState(() {
          _resetParas(content);
        });
        _flushParas();
      });

  void _toggleFocus() {    if (_mode != NoteEditMode.focus) {
      AppToast.show(context, '🎯 聚焦在「🖊 专注」模式下可用');
      return;
    }
    setState(() => _focusOn = !_focusOn);
    AppToast.show(
        context, _focusOn ? '聚焦模式：当前段高亮，其余段落淡出' : '已关闭聚焦模式');
  }

  // ---------- 保存 ----------

  void _onChanged(String _) {
    setState(() {
      _dirty = true;
      _saved = false;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 900), _autoSave);
    _snapIdle?.cancel();
    _snapIdle = Timer(const Duration(seconds: 30), () => _maybeSnap(idle: true));
  }

  /// 停输 30s 或每 +500 字 → 自动留存快照（恢复为副本，不动当前稿）。
  Future<void> _maybeSnap({required bool idle}) async {
    final text = _bodyCtl.text;
    final words = text.replaceAll(RegExp(r'\s'), '').length;
    if (text.trim().isEmpty || text == _lastSnapText) return;
    if (!idle && words - _snapBaseWords < 500) return;
    if (_existing == null && _dirty) await _persist();
    final id = _existing?.id;
    if (id == null) return;
    await ref.read(noteDaoProvider).snapshot(id, text);
    _lastSnapText = text;
    _snapBaseWords = words;
  }

  Future<Note> _persist() async {
    final now = DateTime.now();
    final dao = ref.read(noteDaoProvider);
    final saved = await dao.save(_existing != null
        ? _existing!.copyWith(
            title: _titleCtl.text.trim(),
            content: _bodyCtl.text,
            kind: _kind,
            folder: _folder.isEmpty ? null : _folder,
            pinned: _pinned,
            updatedAt: now)
        : Note(
            title: _titleCtl.text.trim(),
            content: _bodyCtl.text,
            kind: _kind,
            folder: _folder.isEmpty ? null : _folder,
            pinned: _pinned,
            createdAt: now,
            updatedAt: now));
    _existing = saved;
    _dirty = false;
    ref.invalidate(notesProvider);
    ref.invalidate(noteFoldersProvider);
    return saved;
  }

  Future<void> _autoSave() async {
    if (!_dirty || !mounted) return;
    await _persist();
    if (!mounted) return;
    setState(() => _saved = true);
    await _maybeSnap(idle: false); // 每 +500 字里程碑留存
  }

  Future<void> _saveAndExit() async {
    _debounce?.cancel();
    _snapIdle?.cancel();
    if (_mode == NoteEditMode.focus) _flushParas();
    if (_dirty) await _persist();
    final n = await _syncTodoLines();
    if (!mounted) return;
    if (n > 0) AppToast.show(context, '已保存 ✓ · ☑ 待办已同步（$n 条）');
    Navigator.of(context).pop();
  }

  // ---------- 轮8③ · 左右滑动/←→ 按当前排序+筛选切换笔记 ----------

  /// 原型 pwSwipe：dx>70 且 |dx|>2|dy| 才认横向滑动（纵向留给滚动）。
  void _onSwipeDown(PointerDownEvent e) {
    _swDown = e.position;
    _swFired = false;
  }

  void _onSwipeMove(PointerMoveEvent e) {
    final down = _swDown;
    if (_swFired || down == null) return;
    final d = e.position - down;
    if (d.dx.abs() > 70 && d.dx.abs() > 2 * d.dy.abs()) {
      _swFired = true;
      _switchNote(d.dx < 0 ? 1 : -1);
    }
  }

  /// 切换前先把当前稿落库（输入即存不丢稿），再按列表序进邻篇。
  Future<void> _switchNote(int dir) async {
    if (_swiping) return;
    _swiping = true;
    try {
      _debounce?.cancel();
      _snapIdle?.cancel();
      if (_mode == NoteEditMode.focus) _flushParas();
      if (_dirty) await _persist();
      if (!mounted) return;
      final f = ref.read(noteFilterProvider);
      final dao = ref.read(noteDaoProvider);
      final list = f.folder == kNoteTrash
          ? await dao.trash()
          : await dao.list(
              folder: f.folder.isEmpty ? null : f.folder, sort: f.sort);
      if (!mounted) return;
      if (list.isEmpty) {
        AppToast.show(context, '当前筛选下暂无笔记');
        return;
      }
      final i = list.indexWhere((n) => n.id == _existing?.id);
      final j = i + dir;
      if (i >= 0 && j < 0) {
        AppToast.show(context, '已是第一篇');
        return;
      }
      if (j >= list.length) {
        AppToast.show(context, '已是最后一篇');
        return;
      }
      final target = list[j < 0 ? 0 : j];
      await _loadNote(target);
      if (!mounted) return;
      final title =
          target.title.trim().isEmpty ? '未命名笔记' : target.title.trim();
      AppToast.show(
          context, '⇄ 已切换 ${j + 1}/${list.length} · $title');
    } finally {
      _swiping = false;
    }
  }

  /// 就地换稿载入（不重开路由）：标题/正文/kind/文件夹/置顶全部跟随。
  Future<void> _loadNote(Note n) async {
    setState(() {
      _existing = n;
      _titleCtl.text = n.title;
      _bodyCtl.text = n.content;
      _folder = n.folder ?? '';
      _pinned = n.pinned;
      _kind = n.kind;
      _dirty = false;
      _saved = true;
      _pwSub = '';
      _mdUndo.clear();
      _mdRedo.clear();
      _lastSnapText = '';
      _snapBaseWords = n.wordCount;
      _resetParas(n.content);
    });
    if (n.kind == 'rich') _rebuildRich(n.content);
  }

  int get _words {
    final body = _isRich
        ? Note.richToPlain(_bodyCtl.text)
        : Note.stripMdImages(_bodyCtl.text);
    final t = '${_titleCtl.text}$body'.replaceAll(RegExp(r'\s'), '');
    return t.length;
  }

  String get _countText {
    final w = _words;
    if (w == 0) return '开始写吧';
    return '$w 字 · 约 ${math.max(1, (w / 300).round())} 分钟';
  }

  Future<void> _pickFolder() async {
    final folders = ref.read(noteFoldersProvider).valueOrNull ?? const [];
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (bc) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in ['（无分类）', ...folders])
              ListTile(
                title: Text(f),
                onTap: () => Navigator.of(bc).pop(f == '（无分类）' ? '' : f),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _folder = picked;
        _dirty = true;
      });
      _autoSave();
    }
  }

  // ---------- 布局 ----------

  Widget _modeBtn(NoteEditMode m, String label) {
    final on = _mode == m;
    return GestureDetector(
      key: ValueKey('note-mode-${m.name}'),
      onTap: () => _setMode(m),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: on ? _fg.withValues(alpha: .12) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: _fg.withValues(alpha: on ? 1 : .55))),
      ),
    );
  }

  Widget _mdToolBtn(String k, String glyph, String tip) {
    return Tooltip(
      message: tip,
      child: GestureDetector(
        key: ValueKey('note-md-$k'),
        onTap: () => _mdBarTap(k),
        child: Container(
          width: 30,
          height: 28,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center,
          child: Text(glyph,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  fontStyle: k == 'ital' || k == 'math' || k == 'mathb'
                      ? FontStyle.italic
                      : FontStyle.normal,
                  decoration: k == 'strike' ? TextDecoration.lineThrough : null,
                  color: _fg.withValues(alpha: .75),
                  fontFamily: k == 'math' || k == 'mathb' ? 'Georgia' : null)),
        ),
      ),
    );
  }

  Widget _srcEditor() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      child: TextField(
        key: const ValueKey('note-body'),
        controller: _bodyCtl,
        focusNode: _bodyFocus,
        onChanged: _onChanged,
        maxLines: null,
        minLines: 14,
        keyboardType: TextInputType.multiline,
        style: TextStyle(
            fontSize: 12.5,
            height: 1.9,
            letterSpacing: .2,
            fontFamily: 'monospace',
            color: _fg),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: 'Markdown 源码 · 支持标题/粗斜删/列表/待办/表格/公式…',
          hintStyle: TextStyle(color: _fg.withValues(alpha: .4)),
        ),
      ),
    );
  }

  /// 渲染预览（批1c · MdView：GFM + flutter_math_fork 公式）。
  Widget _preview({double fontSize = 14}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MdView(
            key: const ValueKey('md-view'),
            source: _bodyCtl.text,
            fg: _fg,
            fontSize: fontSize,
            onToggleTask: _toggleTask,
          ),
        ],
      ),
    );
  }

  /// ☑ 勾选回写源码第 idx 个任务行；勾上即联动 L3 完成同名待办。
  void _toggleTask(int idx, bool check) {
    final text = _bodyCtl.text;
    var i = -1;
    final out = text.replaceAllMapped(
        RegExp(r'^(\s*[-*]\s+)\[( |x|X)\]', multiLine: true), (m) {
      i++;
      return i == idx ? '${m[1]!}[${check ? 'x' : ' '}]' : m[0]!;
    });
    if (i < idx) return;
    _bodyCtl.value = TextEditingValue(
        text: out, selection: TextSelection.collapsed(offset: out.length));
    _onChanged(out);
    if (check) {
      final title = RegExp(r'^\s*[-*]\s+\[[xX]\]\s+(.+)$', multiLine: true)
          .allMatches(out)
          .map((m) => m[1]!.trim())
          .elementAtOrNull(idx);
      _completeTodo(title);
    } else {
      AppToast.show(context, '已取消勾选 ☐');
    }
  }

  /// L3 联动：勾选的待办行 → 完成同名未完成待办（与日记 ☐ 同构）。
  Future<void> _completeTodo(String? title) async {
    if (title == null || title.isEmpty) return;
    final repo = ref.read(todoRepositoryProvider);
    final match = (await repo.list())
        .where((t) => t.title == title && !t.done)
        .firstOrNull;
    if (!mounted) return;
    if (match == null) {
      AppToast.show(context, '已勾选 ☑ · 保存后同步至待办');
      return;
    }
    await repo.toggleDone(match);
    ref.invalidate(todosProvider);
    if (mounted) {
      AppToast.show(context, '已勾选 ☑ · 待办「$title」已完成');
    }
  }

  /// L3：源码中未勾选的 - [ ] 行 → 新待办（按标题去重，默认「重要不紧急」）。
  Future<int> _syncTodoLines() async {
    final titles = RegExp(r'^\s*[-*]\s+\[ \]\s+(.+)$', multiLine: true)
        .allMatches(_bodyCtl.text)
        .map((m) => m[1]!.trim())
        .toSet();
    if (titles.isEmpty) return 0;
    final repo = ref.read(todoRepositoryProvider);
    final existing = (await repo.list()).map((t) => t.title).toSet();
    var created = 0;
    for (final t in titles) {
      if (existing.contains(t)) continue;
      await repo.add(Todo(title: t, quadrant: Quadrant.q2, tag: '笔记'));
      created++;
    }
    if (created > 0) ref.invalidate(todosProvider);
    return created;
  }

  Widget _bodyArea() {
    if (_isRich) return _richEditor();
    switch (_mode) {
      case NoteEditMode.focus:
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          children: [
            TextField(
              key: const ValueKey('note-title'),
              controller: _titleCtl,
              focusNode: _titleFocus,
              onChanged: _onChanged,
              style: TextStyle(
                  fontSize: _font + 6,
                  fontWeight: FontWeight.w900,
                  color: _fg,
                  height: 1.5),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: '标题',
                hintStyle: TextStyle(
                    color: _fg.withValues(alpha: .35),
                    fontWeight: FontWeight.w300),
              ),
            ),
            Divider(color: _fg.withValues(alpha: .1), height: 28),
            for (var i = 0; i < _paras.length; i++) _paraField(i),
            // 轮8①（原型 pwAttach）：纯文本正文尾部「＋」附件卡 → 插图入当前段。
            if (_kind == 'plain')
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  key: const ValueKey('note-attach'),
                  onTap: _plainAttach,
                  child: Container(
                    width: 96,
                    height: 96,
                    margin: const EdgeInsets.only(top: 16),
                    decoration: BoxDecoration(
                      color: _fg.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: Text('＋',
                        style: TextStyle(
                            fontSize: 26,
                            color: _fg.withValues(alpha: .6))),
                  ),
                ),
              ),
          ],
        );
      case NoteEditMode.src:
        return SingleChildScrollView(child: _srcEditor());
      case NoteEditMode.split:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: SingleChildScrollView(child: _srcEditor())),
            Container(
                width: 1,
                color: _fg.withValues(alpha: .12),
                margin: const EdgeInsets.symmetric(vertical: 10)),
            Expanded(child: _preview(fontSize: 13)),
          ],
        );
      case NoteEditMode.view:
        return _preview(fontSize: _font);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _saveAndExit();
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 12, 0),
                child: Row(
                  children: [
                    IconButton(
                      key: const ValueKey('note-back'),
                      onPressed: _saveAndExit,
                      icon: Icon(Icons.keyboard_arrow_left,
                          size: 26, color: _fg),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _titleCtl.text.trim().isEmpty
                                ? '未命名笔记'
                                : _titleCtl.text.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: _fg),
                          ),
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 250),
                            opacity: _saved ? 1 : .55,
                            child: Text(
                              _saved ? '自动保存 ✓ 刚刚 · 输入即存' : '编辑中…',
                              style: TextStyle(fontSize: 10, color: _fg),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // V1.29轮2②：头部只剩 ‹ + ⋯（🕘 快照并入 ⋯ 菜单）
                    IconButton(
                      key: const ValueKey('note-export'),
                      tooltip: '选项',
                      onPressed: () => showExportSheet(
                          context,
                          _titleCtl.text.trim(),
                          _isRich
                              ? Note.richToPlain(_bodyCtl.text)
                              : _bodyCtl.text,
                          _bg,
                          _fg,
                          onSnap: _openSnap),
                      icon: Icon(Icons.more_horiz, color: _fg),
                    ),
                  ],
                ),
              ),
              // 轮8②⑥：顶部只留四模式行（rich 无模式概念整行隐藏）；
              // MD/富文本快捷条全部移到底部 _toolBarArea()。
              if (!_isRich)
                Container(
                  decoration: BoxDecoration(
                    color: _bg,
                    border: Border(bottom: BorderSide(color: _fg.withValues(alpha: .1))),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    child: Row(
                      children: [
                        _modeBtn(NoteEditMode.focus, '🖊 专注'),
                        _modeBtn(NoteEditMode.src, '⌨️ MD源码'),
                        _modeBtn(NoteEditMode.split, '🔀 分屏'),
                        _modeBtn(NoteEditMode.view, '👁 预览'),
                      ],
                    ),
                  ),
                ),
              Expanded(
                // 轮8③： Listener 旁路追踪横滑（文本选择与滚动不受影响）。
                child: Listener(
                  key: const ValueKey('note-swipe'),
                  onPointerDown: _onSwipeDown,
                  onPointerMove: _onSwipeMove,
                  child: _bodyArea(),
                ),
              ),
              _toolBarArea(),
              Container(
                decoration: BoxDecoration(
                  color: _bg,
                  border: Border(top: BorderSide(color: _fg.withValues(alpha: .12))),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text('字号',
                            style: TextStyle(
                                fontSize: 11,
                                color: _fg.withValues(alpha: .45))),
                        SizedBox(
                          width: 64,
                          height: 24,
                          child: Slider(
                            key: const ValueKey('note-font'),
                            value: _font,
                            min: 13,
                            max: 19,
                            divisions: 6,
                            activeColor: _brand,
                            inactiveColor: _fg.withValues(alpha: .2),
                            onChanged: (v) => setState(() => _font = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('纸色',
                            style: TextStyle(
                                fontSize: 11,
                                color: _fg.withValues(alpha: .45))),
                        const SizedBox(width: 6),
                        for (var i = 0; i < notePapers.length; i++)
                          GestureDetector(
                            key: ValueKey('note-paper-$i'),
                            onTap: () => setState(() => _paperIdx = i),
                            child: Container(
                              width: 20,
                              height: 20,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: notePapers[i].$1,
                                border: Border.all(
                                    color: i == _paperIdx
                                        ? _brand
                                        : _fg.withValues(alpha: .3),
                                    width: 1.5),
                              ),
                            ),
                          ),
                        const Spacer(),
                        Text(_countText,
                            style: TextStyle(
                                fontSize: 11,
                                color: _fg.withValues(alpha: .55))),
                        const SizedBox(width: 8),
                        GestureDetector(
                          key: const ValueKey('note-focus'),
                          onTap: _toggleFocus,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: _focusOn
                                  ? _brand.withValues(alpha: .18)
                                  : Colors.transparent,
                            ),
                            child: Text('🎯 聚焦',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color:
                                        _focusOn ? _brand : _fg.withValues(alpha: .8))),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          GestureDetector(
                            key: const ValueKey('note-folder'),
                            onTap: _pickFolder,
                            child: Text('📁 ${_folder.isEmpty ? '无分类' : _folder} ▾',
                                style: TextStyle(
                                    fontSize: 11.5, color: _fg)),
                          ),
                          const SizedBox(width: 14),
                          GestureDetector(
                            key: const ValueKey('note-pin'),
                            onTap: () {
                              setState(() {
                                _pinned = !_pinned;
                                _dirty = true;
                              });
                              _autoSave();
                            },
                            child: Text(_pinned ? '📌 已置顶' : '📌 置顶',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: _pinned
                                        ? _fg
                                        : _fg.withValues(alpha: .5))),
                          ),
                          const SizedBox(width: 14),
                          GestureDetector(
                            key: const ValueKey('note-kind'),
                            // V1.29批B：三态循环 纯文本→MD→富文本（原型 pwSetType）
                            onTap: () {
                              final old = _kind;
                              final next = old == 'plain'
                                  ? 'md'
                                  : old == 'md'
                                      ? 'rich'
                                      : 'plain';
                              var text = _bodyCtl.text;
                              if (old == 'rich') {
                                text = Note.richToPlain(text);
                              }
                              setState(() {
                                _kind = next;
                                _dirty = true;
                                _pwSub = '';
                              });
                              if (next == 'rich') {
                                _rebuildRich(text);
                              } else {
                                if (_bodyCtl.text != text) {
                                  _bodyCtl.value = TextEditingValue(
                                      text: text,
                                      selection: TextSelection.collapsed(
                                          offset: text.length));
                                }
                                _resetParas(text);
                                _flushParas();
                              }
                              _autoSave();
                            },
                            child: Text(
                                _kind == 'md'
                                    ? '⌨️ MD'
                                    : _kind == 'rich'
                                        ? '📝 富文本'
                                        : '🖊 纯文本',
                                style:
                                    TextStyle(fontSize: 11.5, color: _fg)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 本地图片嵌入渲染（image_picker 拷贝后的应用目录文件路径）。
class _NoteImageEmbedBuilder extends EmbedBuilder {
  const _NoteImageEmbedBuilder();

  @override
  String get key => BlockEmbed.imageType;

  @override
  String toPlainText(Embed node) => '🖼';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final path = embedContext.node.value.data as String? ?? '';
    final width = MediaQuery.sizeOf(context).width - 40;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(path),
          width: width,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            width: width,
            height: 90,
            alignment: Alignment.center,
            color: const Color(0x11000000),
            child: const Text('🖼 图片已丢失',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ),
        ),
      ),
    );
  }
}
