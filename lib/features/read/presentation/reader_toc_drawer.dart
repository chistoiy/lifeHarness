import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/epub_doc.dart';
import '../domain/book_quote.dart';
import '../domain/book_toc.dart';
import 'read_providers.dart';
import 'reader_pager.dart';

/// 抽屉状态（原型 BR_DR：tab/折叠记忆/rail/去底部）。
class TocDrawerState {
  bool searchTab = false;
  bool rail = false;
  final Set<int> folded = {};
}

/// V1.51 目录侧边抽屉（微信读书式）：左侧滑出 · 双 Tab · 分组折叠 ·
/// 当前章左竖条 + 「当前读到 · 百分比」+ 添加书签 · 起始页码列 · 划线数徽章 ·
/// 去底部/去顶部 pill · 折叠成 44px 竖排「目录」边栏 · 搜本书即时命中跳转。
class ReaderTocDrawer extends ConsumerStatefulWidget {
  const ReaderTocDrawer({
    super.key,
    required this.state,
    required this.bookId,
    required this.doc,
    required this.pager,
    required this.ci,
    required this.pg,
    required this.onGoto,
    required this.onAddBookmark,
    this.onSearchJump,
    this.onClose,
  });

  final TocDrawerState state;
  final String bookId;
  final EpubDoc doc;
  final BookPagination pager;

  /// 当前阅读位置（高亮当前章行）。
  final int ci;
  final int pg;

  /// 跳章 / 跳全书全局页。
  final void Function(int ci) onGoto;
  final void Function() onAddBookmark;

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
  List<({int ci, int pi, String text, String ch})> _hits = const [];
  bool _bot = false;
  // 轮4②：标题映射只算一次（chapterTitles 每次新分配列表，勿在 build 里重建）。
  Map<String, int>? _titleToCi;
  // 轮4②：搜本书防抖 + 分批扫（2409 章一次同步扫会冻结抽屉滚动帧）。
  Timer? _debounce;
  int _searchSeq = 0;

  static const _accent = Color(0xFF6366F1);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _centerCurrent();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _q.dispose();
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
  /// 冻结抽屉；快照章节按需物化，扫到即读段文本）。
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = widget.state;
    if (st.rail) {
      // 44px 竖排「目录」边栏：点按展开回宽版。
      return Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        child: GestureDetector(
          key: const ValueKey('brDrRail'),
          onTap: () => setState(() {
            st.rail = false;
            st.searchTab = false;
          }),
          child: Container(
            width: 44,
            color: cs.surface,
            alignment: Alignment.center,
            child: const RotatedBox(
              quarterTurns: 1,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chevron_right_rounded, size: 15, color: Color(0xFF94A3B8)),
                  SizedBox(width: 10),
                  Text(
                    '目录',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final lv = widget.doc.chapters.length;
    return Stack(
      children: [
        // 遮罩：点按收起（Escape/返回键由父层处理）。
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey('brDrScrim'),
            onTap: widget.onClose,
            child: Container(color: Colors.black.withValues(alpha: .45)),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: MediaQuery.sizeOf(context).width * .78 < 300
              ? MediaQuery.sizeOf(context).width * .78
              : 300,
          child: Container(
            key: const ValueKey('brDrPanel'),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .18),
                  blurRadius: 32,
                  offset: const Offset(12, 0),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 16, 10, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: _tab('brDrTabToc', '目录 · $lv 章', !st.searchTab, () {
                                setState(() => st.searchTab = false);
                              }),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _tab('brDrTabSearch', '搜本书', st.searchTab, () {
                                setState(() => st.searchTab = true);
                              }),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('brDrCollapse'),
                        tooltip: '折叠到边栏',
                        icon: const Icon(Icons.chevron_left_rounded, size: 17),
                        onPressed: () => setState(() => st.rail = true),
                      ),
                    ],
                  ),
                ),
                if (st.searchTab)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search_rounded, size: 14, color: Color(0xFF94A3B8)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              key: const ValueKey('brDrQ'),
                              controller: _q,
                              autofocus: true,
                              style: const TextStyle(fontSize: 12),
                              decoration: const InputDecoration(
                                hintText: '搜本书',
                                hintStyle: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                                border: InputBorder.none,
                              ),
                              onChanged: _runSearch,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  // 目录 Tab＝虚拟化 ListView（自带滚动）；搜本书 Tab 仍整块滚动。
                  child: st.searchTab
                      ? SingleChildScrollView(
                          key: const ValueKey('brDrScroll'),
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 56),
                          child: _searchList(cs),
                        )
                      : _tocList(cs),
                ),
              ],
            ),
          ),
        ),
        // 去底部/去顶部悬浮 pill（仅目录 Tab · 非 rail）。
        Positioned(
          bottom: 20,
          left: 0,
          right: 44,
          child: st.searchTab
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

  Widget _tab(String key, String label, bool on, VoidCallback onTap) {
    return GestureDetector(
      key: ValueKey(key),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? const Color(0x1F6366F1) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: on ? _accent.withValues(alpha: .35) : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: on ? _accent : const Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }

  /// 目录树：BS_TOC 同源（book_toc_nodes）；小节名命中标题即叶子章。
  /// 真机反馈（2026-09-28）：2409 章大全集整列 Column 一次构建致抽屉卡顿、
  /// 点按无响应——行描述符 + ListView.builder 虚拟化，只建可见行。
  Widget _tocList(ColorScheme cs) {
    final nodes =
        ref.watch(tocProvider(widget.bookId)).valueOrNull ?? const <TocNode>[];
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
    final groups = tocTree(nodes, hideEmptyParts: false);
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
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ),
            Text(
              '${h.count}',
              style: const TextStyle(
                fontSize: 9,
                color: Color(0xFFCBD5E1),
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
                          style: const TextStyle(
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
                            child: const Text(
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
