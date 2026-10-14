import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/epub_doc.dart';
import '../../domain/book.dart';
import '../../domain/book_quote.dart';
import '../../domain/book_toc.dart';
import '../../../../core/theme/app_theme.dart';
import '../read_providers.dart';
import './reader_pager.dart';
import './reader_xray_panel.dart';

/// 上拉面板状态（原型 V1.54 批2 终态：BR_TOC_TAB + 搜索独占 + 折叠记忆）。
/// 轮6 起「目录侧边抽屉」升格为阅读页上拉全屏面板「目录｜X-Ray」双段：
/// rail 折叠边栏随旧形态退场（已拍板：不做独立页，也不留 44px 边栏）。
class TocDrawerState {
  /// false＝目录段 · true＝X-Ray 段（面板头三等分里的段位）。
  bool xrTab = false;

  /// 搜索独占态（点搜索伪输入进入；取消/收起回原段）。
  bool searching = false;

  final Set<int> folded = {};
}

/// 阅读页上拉全屏面板（V1.51 抽屉 → V1.54 批A 双段）：
/// 头部三态（常态三等分／搜索独占／目录段「全部折叠」行）+ 双段容器。
/// **目录段功能零回归是硬验收**：树/折叠记忆/当前读到/回到刚才在读/去底部/搜本书命中。
class ReaderTocDrawer extends ConsumerStatefulWidget {
  const ReaderTocDrawer({
    super.key,
    required this.state,
    required this.book,
    required this.doc,
    required this.pager,
    required this.ci,
    required this.pg,
    required this.onGoto,
    required this.onAddBookmark,
    required this.onXrJump,
    this.onSearchJump,
    this.onClose,
    this.backLbl,
    this.onBackJump,
  });

  final TocDrawerState state;
  final Book book;
  final EpubDoc doc;
  final BookPagination pager;

  String get bookId => book.id;

  /// 当前阅读位置（高亮当前章行；X-Ray 段「当前页/已读」判定同源）。
  final int ci;
  final int pg;

  /// 跳章 / 跳全书全局页。
  final void Function(int ci) onGoto;
  final void Function() onAddBookmark;

  /// X-Ray 出场跳转（章+段锚点；页侧现算页位并段闪烁）。
  final void Function(int ch, int para) onXrJump;

  /// 轮5.2①：跳章后的「回到刚才在读」入口只放在面板里（正文零悬浮胶囊）。
  /// [backLbl] 非空＝显示该行（来源章名）。
  final String? backLbl;
  final VoidCallback? onBackJump;

  /// 搜本书命中 → 整表+序号+关键词（页侧挂「上/下一处」并跳原文）。
  final void Function(List<({int ci, int pi, String text})> hits, int idx, String q)?
      onSearchJump;
  final VoidCallback? onClose;

  @override
  ConsumerState<ReaderTocDrawer> createState() => _ReaderTocDrawerState();
}

class _ReaderTocDrawerState extends ConsumerState<ReaderTocDrawer> {
  final _scroll = ScrollController();
  final _q = TextEditingController();
  final _searchFocus = FocusNode();
  List<({int ci, int pi, String text, String ch})> _hits = const [];
  bool _bot = false;
  // 轮4②：标题映射只算一次（chapterTitles 每次新分配列表，勿在 build 里重建）。
  Map<String, int>? _titleToCi;
  // 轮5②：分组数（「全部折叠/展开」判定用；build 内与目录行同源回填）。
  int _gcount = 1;
  // 轮4②：搜本书防抖 + 分批扫（2409 章一次同步扫会冻结面板滚动帧）。
  Timer? _debounce;
  int _searchSeq = 0;

  /// 强调色（F3-3：brand 收 `accent`）：随主题派生，切主题跟随。
  Color get _accent => context.tokens.accent;

  /// 次要小字（F3-1/F3-6）：走主题次文本令牌，深色下对比达标。
  Color get _muted => context.tokens.text2;

  /// 轮5②：全部分组已折叠？（无分组时按单组「正文」计）
  bool get _allFolded =>
      _gcount > 0 && widget.state.folded.length >= _gcount;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.state.xrTab) _centerCurrent();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _q.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// 打开时把当前章行滚到中部（原型 scrollIntoView center）。
  void _centerCurrent() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(
      (widget.ci * 46 - 140)
          .toDouble()
          .clamp(0.0, _scroll.position.maxScrollExtent)
          .toDouble(),
    );
  }

  /// 轮4②：输入防抖 260ms + 每批 24 章微任务让帧（大合集一次同步全扫会
  /// 冻结面板；快照章节按需物化，扫到即读段文本）。
  void _runSearch(String q) {
    _debounce?.cancel();
    final query = q.trim();
    final seq = ++_searchSeq;
    if (query.isEmpty) {
      setState(() => _hits = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 260), () {
      var ci = 0;
      final acc = <({int ci, int pi, String text, String ch})>[];
      void step() {
        if (!mounted || seq != _searchSeq) return;
        final end = ci + 24 > widget.doc.chapters.length
            ? widget.doc.chapters.length
            : ci + 24;
        for (; ci < end && acc.length < 80; ci++) {
          final ch = widget.doc.chapters[ci];
          for (var pi = 0; pi < ch.paras.length; pi++) {
            if (ch.paras[pi].text.contains(query)) {
              acc.add((ci: ci, pi: pi, text: ch.paras[pi].text, ch: ch.title));
              if (acc.length >= 80) break;
            }
          }
        }
        if (ci < widget.doc.chapters.length && acc.length < 80) {
          scheduleMicrotask(step);
        } else {
          setState(() => _hits = acc);
        }
      }
      step();
    });
  }

  // ---------- 头部三态（xrfrag/hdr.frag 1:1） ----------

  /// 常态行：[搜本书伪输入｜目录｜X-Ray｜收起]。
  Widget _hdrRowNormal(ColorScheme cs) {
    final st = widget.state;
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            key: const ValueKey('xrSearchPill'),
            behavior: HitTestBehavior.opaque,
            onTap: _searchEnter,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, size: 13, color: _muted),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      st.xrTab ? '搜词条' : '搜本书',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _seg('xrSegToc', '目录', !st.xrTab, () => _pickSeg(false)),
        const SizedBox(width: 6),
        _seg('xrSegXr', 'X-Ray', st.xrTab, () => _pickSeg(true)),
        const SizedBox(width: 4),
        IconButton(
          key: const ValueKey('brDrClose'),
          tooltip: '收起',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.keyboard_double_arrow_down_rounded, size: 17),
          onPressed: widget.onClose,
        ),
      ],
    );
  }

  /// 搜索独占行：[输入 + ✕清空｜取消]（段感知：目录段扫正文/X-Ray 段过滤词条）。
  Widget _hdrRowSearch(ColorScheme cs) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 13, color: _muted),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const ValueKey('brDrQ'),
                    controller: _q,
                    focusNode: _searchFocus,
                    autofocus: true,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: widget.state.xrTab ? '搜词条' : '搜本书',
                      hintStyle: TextStyle(
                          fontSize: 12, color: _muted),
                      border: InputBorder.none,
                    ),
                    onChanged: (v) {
                      setState(() {});
                      if (!widget.state.xrTab) _runSearch(v);
                    },
                  ),
                ),
                if (_q.text.isNotEmpty)
                  GestureDetector(
                    key: const ValueKey('xrHdrClr'),
                    onTap: () {
                      _q.clear();
                      setState(() {
                        _hits = const [];
                      });
                    },
                    child: Icon(Icons.cancel_rounded,
                        size: 15, color: _muted),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          key: const ValueKey('xrHdrCancel'),
          behavior: HitTestBehavior.opaque,
          onTap: _searchExit,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(
              '取消',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _muted),
            ),
          ),
        ),
      ],
    );
  }

  void _searchEnter() => setState(() => widget.state.searching = true);

  void _searchExit() {
    _q.clear();
    setState(() {
      widget.state.searching = false;
      _hits = const [];
    });
  }

  void _pickSeg(bool xr) {
    if (widget.state.xrTab == xr) return;
    setState(() => widget.state.xrTab = xr);
    if (!xr) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _centerCurrent();
      });
    }
  }

  Widget _seg(String key, String label, bool on, VoidCallback onTap) {
    return GestureDetector(
      key: ValueKey(key),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: on ? const Color(0x1F6366F1) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: on ? _accent.withValues(alpha: .35) : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: on ? _accent : _muted,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = widget.state;
    final lv = widget.doc.chapters.length;
    // 分组树在本帧算好：折叠按钮的「全折叠/全展开」判定与行渲染同源。
    final nodes =
        ref.watch(tocProvider(widget.bookId)).valueOrNull ?? const <TocNode>[];
    final groups = tocTree(nodes, hideEmptyParts: false);
    _gcount = groups.isEmpty ? 1 : groups.length;
    final searching = st.searching;
    return Stack(
      children: [
        // 遮罩（面板外顶部条）：点按收起（Escape/返回键由父层处理）。
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey('brDrScrim'),
            onTap: widget.onClose,
            child: Container(color: Colors.black.withValues(alpha: .45)),
          ),
        ),
        // 上拉全屏面板：顶部留 8% 露出正文，滑入 240ms（原型 .xr-sheet>div 过渡）。
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          top: MediaQuery.sizeOf(context).height * .08,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
            builder: (_, v, child) => FractionalTranslation(
              translation: Offset(0, (1 - v) * .06),
              child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
            ),
            child: Container(
              key: const ValueKey('brDrPanel'),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .18),
                    blurRadius: 32,
                    offset: const Offset(0, -12),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
                      child: searching
                          ? _hdrRowSearch(cs)
                          : _hdrRowNormal(cs),
                    ),
                    Expanded(
                      child: st.xrTab
                          ? _xrTabBody(
                              ReaderXrayPanel(
                                book: widget.book,
                                doc: widget.doc,
                                pager: widget.pager,
                                ci: widget.ci,
                                pg: widget.pg,
                                kw: searching ? _q.text.trim() : '',
                                onJump: widget.onXrJump,
                              ),
                            )
                          : _tocBody(cs, groups, lv, searching),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------- 目录段（功能零回归：树/折叠/当前读到/回在读/去底部/搜本书） ----------

  /// 轮5.2①：跳章后的返回入口行（正文不悬浮，收进面板一行）。
  /// ①（工单20261001轮2）：目录段与 X-Ray 段共用——X-Ray 出场跳转也记 _jumpFrom，
  /// 打开任一抽屉段都应看到「回到刚才在读」。
  Widget _backRow() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
    child: GestureDetector(
      key: const ValueKey('brDrBack'),
      behavior: HitTestBehavior.opaque,
      onTap: widget.onBackJump,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: _accent.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Text(
              '‹ 回到刚才在读 ·',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _accent,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                widget.backLbl!,
                key: const ValueKey('brDrBackLbl'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: _accent,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// ①：X-Ray 段的返回行壳（无返回态时原样挂面板，不动既有布局）。
  Widget _xrTabBody(Widget panel) =>
      widget.backLbl == null || widget.onBackJump == null
          ? panel
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _backRow(),
                Expanded(child: panel),
              ],
            );

  Widget _tocBody(ColorScheme cs, List<TocPartGroup> groups, int lv, bool searching) {
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 「全部折叠」小行＝目录段内容区右上（原型 xrTocFoldRow；搜索态隐藏）。
            if (!searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 16, 2),
                child: Row(
                  children: [
                    const Spacer(),
                    GestureDetector(
                      key: const ValueKey('brDrFoldAll'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() {
                        if (_allFolded) {
                          widget.state.folded.clear();
                        } else {
                          widget.state.folded.addAll(
                            List.generate(_gcount, (i) => i),
                          );
                        }
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        child: Text(
                          _allFolded ? '全部展开' : '全部折叠',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: _muted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // 轮5.2①：跳章后的返回入口（正文不悬浮，收进面板一行）。
            if (widget.backLbl != null && widget.onBackJump != null) _backRow(),
            Expanded(
              // 目录＝虚拟化 ListView（自带滚动）；搜索独占态仍整块滚动。
              child: searching
                  ? SingleChildScrollView(
                      key: const ValueKey('brDrScroll'),
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 56),
                      child: _searchList(cs),
                    )
                  : _tocList(cs, groups),
            ),
          ],
        ),
        // 去底部/去顶部悬浮 pill（仅目录段 · 非搜索态）。
        Positioned(
          bottom: 20,
          left: 0,
          right: 0,
          child: searching
              ? const SizedBox.shrink()
              : Center(
                  child: GestureDetector(
                    key: const ValueKey('brDrPill'),
                    onTap: () {
                      if (!_scroll.hasClients) return;
                      setState(() => _bot = !_bot);
                      _scroll.animateTo(
                        _bot ? _scroll.position.maxScrollExtent : 0,
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOut,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: cs.outlineVariant),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .12),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Text(
                        _bot ? '去顶部' : '去底部',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  /// 目录树：BS_TOC 同源（book_toc_nodes）；小节名命中标题即叶子章。
  /// 真机反馈（2026-09-28）：2409 章大全集整列 Column 一次构建致面板卡顿、
  /// 点按无响应——行描述符 + ListView.builder 虚拟化，只建可见行。
  Widget _tocList(ColorScheme cs, List<TocPartGroup> groups) {
    final quotes =
        (ref.watch(allQuotesProvider).valueOrNull ?? const <BookQuote>[])
            .where((q) =>
                q.bookId == widget.bookId && q.deletedAt == null && q.cf != null)
            .length;
    final titleToCi = _titleToCi ??= <String, int>{
      // 廉价标题（快照走 ChapterMetaSource 索引，不 materialize 段落）。
      for (var i = 0; i < widget.doc.chapterTitles.length; i++)
        widget.doc.chapterTitles[i]: i,
    };
    if (groups.isEmpty && titleToCi.isEmpty) {
      return const SizedBox.shrink();
    }
    final rows = <Object>[];
    for (var gi = 0; gi < (groups.isEmpty ? 1 : groups.length); gi++) {
      final g = groups.isEmpty ? null : groups[gi];
      final secNames = g == null
          ? widget.doc.chapterTitles
          : g.sections.map((s) => s.title).toList();
      final folded = widget.state.folded.contains(gi);
      rows.add(
        _DrHdr(
          gi: gi,
          title: g?.part.title.isNotEmpty == true ? g!.part.title : '正文',
          count: secNames.length,
          folded: folded,
        ),
      );
      if (folded) continue;
      for (final name in secNames) {
        final ci = titleToCi[name];
        if (ci == null) continue;
        rows.add(_DrSec(ci: ci, name: name));
      }
    }
    return ListView.builder(
      key: const ValueKey('brTocList'),
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 56),
      itemCount: rows.length,
      itemBuilder: (_, i) =>
          rows[i] is _DrHdr ? _hdrRow(cs, rows[i] as _DrHdr) : _secRow(cs, rows[i] as _DrSec, quotes),
    );
  }

  Widget _hdrRow(ColorScheme cs, _DrHdr h) {
    return GestureDetector(
      key: ValueKey('brDrFold-${h.gi}'),
      onTap: () => setState(() {
        widget.state.folded.contains(h.gi)
            ? widget.state.folded.remove(h.gi)
            : widget.state.folded.add(h.gi);
      }),
      child: Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Row(
          children: [
            Icon(
              h.folded
                  ? Icons.keyboard_arrow_right_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 12,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                h.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: _muted,
                ),
              ),
            ),
            Text(
              '${h.count}',
              style: TextStyle(
                fontSize: 9,
                color: _muted,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _secRow(ColorScheme cs, _DrSec s, int quotes) {
    final ci = s.ci;
    final name = s.name;
    final isCur = ci == widget.ci;
    final before = ci < widget.ci;
    final chapPages = widget.pager.chapterPages(ci);
    final pct = chapPages == 0 ? 0 : ((widget.pg + 1) / chapPages * 100).round();
    return Stack(
      children: [
        if (isCur)
          Positioned(
            left: 0,
            top: 8,
            bottom: 8,
            child: Container(
              key: ValueKey('brDrCurBar-$ci'),
              width: 3,
              decoration: BoxDecoration(
                color: _accent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        GestureDetector(
          key: ValueKey('brDrCh-$ci'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            widget.onGoto(ci);
            setState(() {});
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 2, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isCur ? FontWeight.w800 : FontWeight.w600,
                          color: isCur
                              ? _accent
                              : (before ? cs.onSurfaceVariant : cs.onSurface),
                        ),
                      ),
                    ),
                    if (quotes > 0 && ci == widget.ci)
                      Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$quotes',
                          style: const TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ),
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${widget.pager.gPosEst(ci, 0) + 1}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 9,
                          color: cs.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
                if (isCur)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Text(
                          '当前读到 · $pct%',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: _accent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          key: const ValueKey('brDrBm'),
                          onTap: () {
                            widget.onAddBookmark();
                            setState(() {});
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _accent.withValues(alpha: .35),
                              ),
                            ),
                            child: Text(
                              '添加书签',
                              style: TextStyle(
                                fontSize: 9,
                                color: _accent,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _searchList(ColorScheme cs) {
    if (_q.text.trim().isEmpty) return const SizedBox.shrink();
    return Column(
      key: const ValueKey('brDrHits'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            '《${widget.doc.title}》命中 ${_hits.length} 处 · 本机检索',
            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
          ),
        ),
        if (_hits.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            alignment: Alignment.center,
            child: Text(
              '未找到「${_q.text.trim()}」',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        for (var i = 0; i < _hits.length && i < 50; i++)
          GestureDetector(
            key: ValueKey('brDrHit-$i'),
            onTap: () => widget.onSearchJump?.call(
              [
                for (final h in _hits) (ci: h.ci, pi: h.pi, text: h.text),
              ],
              i,
              _q.text.trim(),
            ),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: .5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_hits[i].ch} · ${EpubDoc.cfiPrefix}/${_hits[i].ci + 2}/${_hits[i].pi}',
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text.rich(_mark(_hits[i].text, _q.text.trim(), cs)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// 命中关键词琥珀高亮（原型 <mark>）。
  TextSpan _mark(String text, String q, ColorScheme cs) {
    if (q.isEmpty || !text.contains(q)) {
      return TextSpan(text: text, style: const TextStyle(fontSize: 12, height: 1.55));
    }
    final parts = text.split(q);
    final children = <InlineSpan>[];
    for (var i = 0; i < parts.length; i++) {
      children.add(
        TextSpan(
          text: parts[i],
          style: const TextStyle(fontSize: 12, height: 1.55),
        ),
      );
      if (i != parts.length - 1) {
        children.add(
          TextSpan(
            text: q,
            style: TextStyle(
              fontSize: 12,
              height: 1.55,
              backgroundColor: const Color(0x4DF59E0B),
            ),
          ),
        );
      }
    }
    return TextSpan(children: children);
  }
}

/// 目录虚拟化行描述符（批4 真机修）：分组头与小节行只存数据，可见才建 Widget。
class _DrHdr {
  const _DrHdr({required this.gi, required this.title, required this.count, required this.folded});
  final int gi;
  final String title;
  final int count;
  final bool folded;
}

class _DrSec {
  const _DrSec({required this.ci, required this.name});
  final int ci;
  final String name;
}
