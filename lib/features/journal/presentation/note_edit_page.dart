import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../shared/linkage/stats_providers.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/md_shortcut.dart';
import 'journal_providers.dart';
import 'note_paper.dart';
import '../../../shared/widgets/image_attach.dart';
import 'widgets/md_view.dart';
import 'widgets/note_sheets.dart';

part 'note_edit_focus.dart';
part 'note_edit_rich.dart';

/// 编辑器模式（原型 p-noteEdit · V1.29轮9e 去分屏 · 轮9o 写作=默认态）：
/// 专注段落 / MD 源码 / 预览。
enum NoteEditMode { focus, src, view }

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

/// 品牌色（治理G7d③前置：原为 _NoteEditPageState 的 static const）。
/// 提到库级是因为扩展成员不会解析宿主类的静态名，而富文本/布局两群都要用它；
/// 值与引用写法（裸 `_brand`）一字未改。
const _brand = Color(0xFF6366F1);

class _NoteEditPageState extends ConsumerState<NoteEditPage> {

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
  // V1.29轮9n：纸色按笔记独立（''=默认米纸 · 'p<i>'=预置 · 'h<hue>'=色条自定义）。
  String _paper = '';
  double _font = 15;
  // 轮9j补正2：聚焦=纸面默认开（当前段高亮·其余淡出），⋯ 内可关。
  bool _focusOn = true;
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

  Color get _bg => paperBg(_paper);
  Color get _fg => paperFg(_paper);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onGlobalKey);
    _kind = widget.initialKind;
    _folder = widget.initialFolder;
    _resetParas('');
    _richCtl = _newRich('');
    _load();
    // 轮9d：新建笔记=纸面直接闪光标（原型 newNote 无灰盒输入·无教学 hint）。
    if (widget.noteId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_isRich) {
          _richFocus.requestFocus();
        } else {
          _paraNodes.first.requestFocus();
        }
      });
    }
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
      _paper = n.paper;
      _snapBaseWords = n.wordCount;
      _resetParas(n.content);
      _syncBodyAfterReset();
    });
    if (_kind == 'rich') _rebuildRich(n.content);
    // 断点续写（草稿提醒）：最近快照比当前稿更完整时提示可从 🕘 恢复。
    final snaps = await ref.read(noteDaoProvider).snapshotsOf(n.id!);
    if (snaps.isEmpty || !mounted) return;
    final latest = Note.richToPlain((snaps.first['content'] as String?) ?? '');
    final gain = latest.replaceAll(RegExp(r'\s'), '').length -
        Note.richToPlain(n.content).replaceAll(RegExp(r'\s'), '').length;
    if (gain > 0 && latest != Note.richToPlain(n.content)) {
      AppToast.show(context, '有比当前更完整的快照（+$gain 字）· 可从版本快照恢复');
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
      AppToast.show(context, '当前为写作视图 · 切源码后可用 MD 快捷栏');
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
      AppToast.show(context, '当前为写作视图 · 切源码后可用 MD 快捷栏');
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
      AppToast.show(context, '当前为写作视图 · 切源码后可用 MD 快捷栏');
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
      AppToast.show(context, '当前为写作视图 · 切源码后可用 MD 快捷栏');
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

  /// 轮9j补正2：聚焦开关（⋯ 内）·纸面默认开·纯文本/MD/富文本通用不再限模式。
  void _toggleFocus() {
    setState(() => _focusOn = !_focusOn);
    AppToast.show(context,
        _focusOn ? '聚焦开：当前段高亮，其余淡出' : '聚焦关：全部段落正常显示');
  }

  /// 轮9j：类型经 ⋯ 三 chip 直选（原型 pwSetType·替代旧三态循环钮）。
  void _setKind(String next) {
    if (next == _kind) return;
    final old = _kind;
    var text = _bodyCtl.text;
    if (old == 'rich') {
      text = Note.richToPlain(text);
    }
    setState(() {
      _kind = next;
      _dirty = true;
      _pwSub = '';
      // 模式行=MD 专属：切离 MD 回专注段落形态。
      if (next != 'md') _mode = NoteEditMode.focus;
    });
    if (next == 'rich') {
      _rebuildRich(text);
    } else {
      if (_bodyCtl.text != text) {
        _bodyCtl.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length));
      }
      _resetParas(text);
      _flushParas();
    }
    _autoSave();
  }

  /// ⋯ 笔记选项弹层（原型 sheetNoteKit · 轮9 汇总：字号/纸色/聚焦/行号/
  /// 文件夹/快照/类型全部收进这里，底部状态条移除）。
  void _openKit() {
    showNoteKitSheet(
      context,
      ref,
      kind: _kind,
      font: _font,
      paper: _paper,
      focusOn: _focusOn,
      folder: _folder,
      countText: _countText,
      onKind: _setKind,
      onFont: (v) => setState(() => _font = v),
      onPaper: (v) {
        setState(() {
          _paper = v;
          _dirty = true;
        });
        _autoSave();
      },
      onFocus: _toggleFocus,
      onFolder: (v) {
        setState(() {
          _folder = v;
          _dirty = true;
        });
        _autoSave();
      },
      onSnap: _openSnap,
      onShare: () => showNoteShareSheet(
          context,
          _titleCtl.text.trim(),
          _isRich ? Note.richToPlain(_bodyCtl.text) : _bodyCtl.text,
          _bg,
          _fg),
    );
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
            paper: _paper,
            updatedAt: now)
        : Note(
            title: _titleCtl.text.trim(),
            content: _bodyCtl.text,
            kind: _kind,
            folder: _folder.isEmpty ? null : _folder,
            pinned: _pinned,
            paper: _paper,
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
  // 轮10-2：滑动改为可选能力（lh.note_swipe·记录管理·默认关）；←→ 键仅桌面不受限。

  /// 原型 pwSwipe：dx>70 且 |dx|>2|dy| 才认横向滑动（纵向留给滚动）。
  void _onSwipeDown(PointerDownEvent e) {
    if (!ref.read(settingsControllerProvider).noteSwipe) {
      _swDown = null;
      return;
    }
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
              folder: f.folder.isEmpty ? null : f.folder,
              sort: f.sort,
              asc: f.asc);
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
      _paper = n.paper;
      _dirty = false;
      _saved = true;
      _pwSub = '';
      _mode = NoteEditMode.focus;
      _mdUndo.clear();
      _mdRedo.clear();
      _lastSnapText = '';
      _snapBaseWords = n.wordCount;
      _resetParas(n.content);
      _syncBodyAfterReset();
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

  // ---------- 布局 ----------

  /// 顶行模式图标钮（原型 pw-mode-btn · 轮9h/9o）：源码/预览两态·再点当前项回落写作。
  Widget _modeBtn(String keyName, IconData icon, String tip, bool on,
      VoidCallback onTap) {
    return IconButton(
      key: ValueKey(keyName),
      tooltip: tip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      icon: Icon(icon,
          size: 20,
          color: on ? _brand : _fg.withValues(alpha: .55)),
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
        decoration: const InputDecoration(
          border: InputBorder.none,
        ),
      ),
    );
  }

  /// 渲染预览（批1c · MdView：GFM + flutter_math_fork 公式；
  /// 轮9k：LaTeX 渲染由记录管理开关门控·默认关=公式按原文显示）。
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
            enableLatex: ref.watch(settingsControllerProvider).noteLatex,
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
    // 模式行=MD 文档专属；纯文本恒为专注段落形态（原型 pwModes 仅 md 渲染）。
    final m = _kind == 'md' ? _mode : NoteEditMode.focus;
    // 轮9p：行号仅纯文本 + 设置位开启时呈现段左序号。
    final showLn = _kind == 'plain' &&
        ref.watch(settingsControllerProvider).notePlainLineNum;
    switch (m) {
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
              decoration: const InputDecoration(
                border: InputBorder.none,
              ),
            ),
            Divider(color: _fg.withValues(alpha: .1), height: 28),
            for (var i = 0; i < _paras.length; i++)
              _paraField(i, lineNum: showLn),
            // 轮8①（原型 pwAttach）：纯文本正文尾部「＋」附件卡 → 插独立图片段。
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
            // 轮11-1（=轮10-4 真因）：默认 center + 视口横向 shrink-wrap 会让
            // 短行（如标题）整体居中、看似「左右留白太多」→ 强制撑满宽度。
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    // 轮9h/9o：MD 顶行=写作（默认·无钮）+ 源码/预览纯图标·
                    // 再点当前激活项回落写作视图；段落聚焦归 ⋯ 开关。
                    if (_kind == 'md') ...[
                      _modeBtn('note-mode-src', Icons.code, 'MD 源码',
                          _mode == NoteEditMode.src, () => _setMode(
                              _mode == NoteEditMode.src
                                  ? NoteEditMode.focus
                                  : NoteEditMode.src)),
                      const SizedBox(width: 2),
                      _modeBtn('note-mode-view', Icons.visibility_outlined,
                          '预览', _mode == NoteEditMode.view, () => _setMode(
                              _mode == NoteEditMode.view
                                  ? NoteEditMode.focus
                                  : NoteEditMode.view)),
                      const SizedBox(width: 6),
                    ],
                    // 轮9j/9r：⋯ =「笔记选项」sheetNoteKit（字号/纸色/聚焦/
                    // 行号/文件夹/快照/类型全部在此·底部状态条移除）。
                    IconButton(
                      key: const ValueKey('note-export'),
                      tooltip: '选项',
                      onPressed: _openKit,
                      icon: Icon(Icons.more_horiz, color: _fg),
                    ),
                  ],
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
            ],
          ),
        ),
      ),
    );
  }
}
