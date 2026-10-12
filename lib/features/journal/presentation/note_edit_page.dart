import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/platform/open_intent.dart' show noteWriteBackGuard;
import '../../../shared/linkage/stats_providers.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/md_shortcut.dart';
import '../domain/note_folder.dart' show kDefaultNoteFolder;
import 'journal_providers.dart';
import 'note_mount_write.dart';
import 'note_paper.dart';
import '../../../shared/widgets/image_attach.dart';
import 'widgets/md_view.dart';
import 'widgets/note_sheets.dart';

part 'note_edit_focus.dart';
part 'note_edit_rich.dart';
part 'note_edit_mode.dart';
part 'note_edit_save.dart';
part 'note_edit_swipe.dart';
part 'note_edit_layout.dart';

/// 编辑器模式（原型 p-noteEdit · V1.29轮9e 去分屏 · 轮9o 写作=默认态）：
/// 专注段落 / MD 源码 / 预览。
enum NoteEditMode { focus, src, view }

/// MD 底部主条（原型轮8 renderPwBar · pw-tool 顺序与图形）：
/// ↺↻ | H#（点开二级 H1~H6）B I S <> ❝ ≡ ☑ ▦ 图片 链接 ƒx ∑ —
///
/// T13 档③ 清零：`img`/`link` 两行的 glyph 位**从来不上屏**——渲染侧
/// （`note_edit_rich.dart` 的 MD 工具条）对这两个键走 `_pwIconBtn(Icons.image_outlined /
/// Icons.link)`，只有其余键才吃这里的文本。原来这两格写着表情符号，属**代码自造**
/// （原型 `renderPwBar` 的 MD 条根本没有图片/链接两枚），留着只会在扫描里当违令存量，
/// 现改留空并注明由图标件接管，别再往这里塞表情。
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
  ('img', '', '图片'),
  ('link', '', '链接'),
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
  /// 批3④（工单 §2）：无未落库改动＝已保存——打开既有篇/新建空白即此态。
  /// 原实现初值 false ⇒ 一进编辑页就显示「编辑中」，与事实不符。
  bool _saved = true;
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

  /// 批3①（工单 §2）：头部小标题「滚动浮出」——写作视图下标题仍在视口内时
  /// 头部不显示，滚出阈值后才显；源码/预览视图常显（那两个视图没有体部标题位）。
  bool _headScrolledIn = false;

  /// 头部吸顶分隔（原型 `#pwHead.pw-stuck`：滚过 4px 起出现一条下分隔）。
  bool _headStuck = false;

  bool get _headTitleShown =>
      _mode != NoteEditMode.focus || _headScrolledIn;

  /// 批3①：正文滚动 → 头部小标题显隐＋吸顶分隔（原型 `pwHeadSync`）。
  bool _onBodyScroll(ScrollNotification n) {
    if (n.depth != 0) return false; // 只管最外层正文滚动
    final st = n.metrics.pixels;
    final scrolledIn = st > 80;
    final stuck = st > 4;
    if (scrolledIn != _headScrolledIn || stuck != _headStuck) {
      // 只在跨阈值那一次重建（逐像素 setState 会拖垮滚动手感）。
      setState(() {
        _headScrolledIn = scrolledIn;
        _headStuck = stuck;
      });
    }
    return false;
  }

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
              // 批3②（工单 §2）：三段基线归一——头/体/尾内容左沿统一 20（原型 px-5），
              // 与正文（focus/src/预览 均 20）落在同一条竖轴上。
              // 批3①：滚过 4px 起头部与正文之间补一条分隔（原型 #pwHead.pw-stuck）。
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.fromLTRB(20, 6, 16, 0),
                decoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(
                          color: _headStuck
                              ? _fg.withValues(alpha: .12)
                              : Colors.transparent,
                          width: 1)),
                ),
                child: Row(
                  children: [
                    // 44×44 命中区（U6 触达下限）·图标贴左沿 ⇒ 视觉左沿 20
                    //（原 IconButton 内建居中偏移，左沿随 icon 尺寸漂移）。
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: InkWell(
                        key: const ValueKey('note-back'),
                        borderRadius: BorderRadius.circular(22),
                        onTap: _saveAndExit,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Icon(Icons.keyboard_arrow_left,
                              size: 26, color: _fg),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 批3①（工单 §2）：标题「滚动浮出」——写作视图下标题仍在
                          // 视口内时头部不显示（同一屏只出现一次标题，消掉「头与体
                          // 争同一份内容」）；标题滚出 80px 才淡入吸顶小标题。
                          // 源码/预览视图常显（这两个视图没有体部标题位）。
                          AnimatedOpacity(
                            key: const ValueKey('note-head-title'),
                            duration: const Duration(milliseconds: 180),
                            opacity: _headTitleShown ? 1 : 0,
                            child: Text(
                              _titleCtl.text.trim().isEmpty
                                  ? '未命名笔记'
                                  : _titleCtl.text.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: _fg),
                            ),
                          ),
                          // 批3④（工单 §2）：保存态降噪——删「自动保存 ✓ 刚刚 · 输入即存」
                          // 教学文案与每键明暗闪烁（原 AnimatedOpacity .55↔1），收敛成一个
                          // 安静的两态点：无改动＝已保存，改动未落库＝编辑中。
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _fg.withValues(
                                        alpha: _saved ? .38 : .18)),
                              ),
                              const SizedBox(width: 5),
                              Text(_saved ? '已保存' : '编辑中',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: _fg.withValues(alpha: .45))),
                            ],
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
                  // 批3①：头部小标题随正文滚动浮出（原型 pwHeadSync）。
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onBodyScroll,
                    // 批3⑤（工单 §2）：三视图切换＝180ms 淡入＋上移（原型 .pw-anim-in）。
                    // 富文本不参与：kind 切换时旧 Quill 件会与 _disposeLater 的
                    // 控制器回收抢时序，风险不对等。
                    child: _isRich
                        ? _bodyArea()
                        : AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeOut,
                            // 只做入场淡入、旧件立即移除（与原型一致：旧目标直接
                            // hidden，仅新目标加 .pw-anim-in）——同时规避旧件滞留
                            // 期间持有已被回收的段控制器。
                            layoutBuilder: (cur, _) =>
                                cur ?? const SizedBox.shrink(),
                            transitionBuilder: (c, a) => FadeTransition(
                              opacity: a,
                              child: SlideTransition(
                                position: Tween(
                                        begin: const Offset(0, .012),
                                        end: Offset.zero)
                                    .animate(a),
                                child: c,
                              ),
                            ),
                            child: _bodyArea(),
                          ),
                  ),
                ),
              ),
              // 批3③（工单 §2）：尾部随模式出现/收起＝180ms 高度＋淡入过渡
              //（原为瞬现瞬消，切类型时体高瞬变）。
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeOut,
                layoutBuilder: (cur, _) => cur ?? const SizedBox.shrink(),
                transitionBuilder: (c, a) => SizeTransition(
                  sizeFactor: a,
                  axisAlignment: -1,
                  child: FadeTransition(opacity: a, child: c),
                ),
                child: _toolBarArea(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
