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

/// 14 键 MD 快捷栏（原型 pw-tool 顺序与图形）。
const _mdTools = <(String, String, String)>[
  ('h', 'H', '标题'),
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
    if (_isRich) return false; // 富文本段落结构由 Quill 自管
    if (_mode != NoteEditMode.focus || !mounted) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
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
  void _flushParas() {
    final joined = _paras.map((c) => c.text).join('\n\n');
    if (_bodyCtl.text != joined) {
      _bodyCtl.value = TextEditingValue(
          text: joined,
          selection: TextSelection.collapsed(offset: joined.length));
    }
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

  /// H 键：与 MD 快捷栏同款循环 无→h1→h2→h3→无（原型 pwRich-h）。
  void _richHeading() {
    final c = _richCtl;
    if (c == null) return;
    final cur = c.getSelectionStyle().attributes['header'];
    final level = cur is HeaderAttribute ? (cur.value ?? 0) : 0;
    const steps = [Attribute.h1, Attribute.h2, Attribute.h3];
    if (level >= 3) {
      c.formatSelection(Attribute.clone(Attribute.h1, null));
    } else {
      c.formatSelection(steps[level]); // 无→h1→h2→h3
    }
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

  /// 🖼 插图（原型 pwRichBar 🖼）：相册/拍照 → 拷贝应用目录 → Delta image 嵌入。
  /// 不引 flutter_quill_extensions（其 super_native_extensions 原生链在本机
  /// 网络受限环境构建风险大），渲染由本页 _NoteImageEmbedBuilder 承担。
  Future<void> _richImage() async {
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
    if (src == null || !mounted) return;
    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
          source: src == 'camera' ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 1600,
          imageQuality: 88);
    } catch (e) {
      if (mounted) AppToast.show(context, '📷 相机/相册暂不可用');
      return;
    }
    if (picked == null || !mounted) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final outDir = Directory(p.join(dir.path, 'note_images'));
      if (!await outDir.exists()) await outDir.create(recursive: true);
      final dot = picked.path.lastIndexOf('.');
      final ext = dot > 0 ? picked.path.substring(dot + 1).toLowerCase() : 'jpg';
      final dest = p.join(
          outDir.path, '${DateTime.now().millisecondsSinceEpoch}.$ext');
      await File(picked.path).copy(dest);
      if (!mounted) return;
      final c = _richCtl;
      if (c == null) return;
      final idx = c.selection.baseOffset < 0
          ? c.document.length - 1
          : c.selection.baseOffset;
      c.replaceText(idx, 0, BlockEmbed.image(dest),
          TextSelection.collapsed(offset: idx + 1));
      AppToast.show(context, '🖼 已插入图片');
    } catch (_) {
      if (mounted) AppToast.show(context, '插图失败 · 请重试');
    }
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

  /// pwRichBar 九键（原型轮3⑥）：B I U H ≡ ☑ 🖼 ↺ ↻ · 即时生效零 MD 痕迹。
  Widget _richBar() {
    final c = _richCtl;
    Widget btn(String k, Widget glyph, VoidCallback onTap, String tip) {
      return Tooltip(
        message: tip,
        child: GestureDetector(
          key: ValueKey('note-rich-$k'),
          onTap: onTap,
          child: Container(
            width: 30,
            height: 28,
            margin: const EdgeInsets.only(right: 2),
            decoration:
                BoxDecoration(borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: glyph,
          ),
        ),
      );
    }

    Widget g(String text,
            {FontWeight w = FontWeight.w800,
            FontStyle? f,
            TextDecoration? d}) =>
        Text(text,
            style: TextStyle(
                fontSize: 13,
                fontWeight: w,
                fontStyle: f,
                decoration: d,
                color: _fg.withValues(alpha: .75)));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          btn('bold', g('B'), () => _richToggle(Attribute.bold), '加粗'),
          btn('ital', g('I', f: FontStyle.italic),
              () => _richToggle(Attribute.italic), '斜体'),
          btn('under', g('U', d: TextDecoration.underline),
              () => _richToggle(Attribute.underline), '下划线'),
          btn('h', g('H'), _richHeading, '标题（点按循环 h1→h3）'),
          btn('ul', g('≡'), () => _richToggle(Attribute.ul), '无序列表'),
          btn('task', g('☑'), _richTask, '待办勾选行'),
          btn('img', g('🖼', w: FontWeight.w400), _richImage, '插图'),
          btn('undo', g('↺'), () => c?.undo(), '撤销'),
          btn('redo', g('↻'), () => c?.redo(), '重做'),
        ],
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

  int get _words {
    final body = _isRich ? Note.richToPlain(_bodyCtl.text) : _bodyCtl.text;
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

  Widget _toolBtn(String k, String glyph, String tip) {
    return Tooltip(
      message: tip,
      child: GestureDetector(
        key: ValueKey('note-md-$k'),
        onTap: () => _tool(k),
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
                  fontWeight: k == 'ital' ? FontWeight.w800 : FontWeight.w800,
                  fontStyle: k == 'ital'
                      ? FontStyle.italic
                      : k == 'math' || k == 'mathb'
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
              Container(
                decoration: BoxDecoration(
                  color: _bg,
                  border: Border(bottom: BorderSide(color: _fg.withValues(alpha: .1))),
                ),
                child: _isRich
                    ? _richBar()
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        child: Row(
                          children: [
                            _modeBtn(NoteEditMode.focus, '🖊 专注'),
                            _modeBtn(NoteEditMode.src, '⌨️ MD源码'),
                            _modeBtn(NoteEditMode.split, '🔀 分屏'),
                            _modeBtn(NoteEditMode.view, '👁 预览'),
                            Container(
                                width: 1,
                                height: 16,
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 6),
                                color: _fg.withValues(alpha: .25)),
                            for (final (k, glyph, tip) in _mdTools)
                              _toolBtn(k, glyph, tip),
                          ],
                        ),
                      ),
              ),
              Expanded(child: _bodyArea()),
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
