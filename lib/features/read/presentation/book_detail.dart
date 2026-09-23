import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/book.dart';
import '../domain/book_quote.dart';
import '../domain/book_toc.dart';
import 'read_actions.dart';
import 'read_providers.dart';
import 'read_sheets.dart';
import 'widgets/bs_cover.dart';

/// 二级页参数（tab: c=目录 q=书摘 r=相关）。
class BookDetailArg {
  const BookDetailArg({this.tab = 'c'});
  final String tab;
}

/// 详情页 = 沉浸阅读视图（原型 p-bookDetail · §3.2 拆两屏之阅读屏）。
/// 批2 接：可点信息芯片（计时明细/记进度）、封面→书籍资料页、
/// 目录两级卡（只读 + 编辑就地微调 + 粘贴导入）、顶栏计时按 timerUI 分流。
class BookDetailPage extends ConsumerStatefulWidget {
  const BookDetailPage({
    super.key,
    required this.bookId,
    this.initialTab = 'c',
  });
  final String bookId;
  final String initialTab;

  @override
  ConsumerState<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends ConsumerState<BookDetailPage> {
  late String _tab = widget.initialTab;
  bool _tocEdit = false;
  String? _chapF; // 书摘按章节筛选（点目录节跳入）
  String _qSeg = 'all'; // 书摘 tab 分段 chips（原型 bdQSeg · 全部/划线/想法/星标）

  Map<String, ({int minutes, int times})> get agg =>
      ref.watch(workbenchProvider).valueOrNull?.agg ?? const {};

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final books = ref.watch(booksProvider).valueOrNull ?? const <Book>[];
    final b = books.where((e) => e.id == widget.bookId).firstOrNull;
    if (b == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('书籍')),
        body: const SizedBox.shrink(),
      );
    }
    final allQ =
        (ref.watch(allQuotesProvider).valueOrNull ?? const <BookQuote>[])
            .where((q) => q.bookId == b.id && q.deletedAt == null)
            .toList();
    final byChap = _chapF == null
        ? allQ
        : allQ.where((q) => (q.chapter ?? '未分章') == _chapF).toList();
    final quotes = switch (_qSeg) {
      'line' => byChap.where((q) => q.kind == BookQuote.kKindMark).toList(),
      'think' => byChap.where((q) => q.kind == BookQuote.kKindThought).toList(),
      'star' => byChap.where((q) => q.starred).toList(),
      _ => byChap,
    };
    final relGroups = _relGroups(b, books);
    final running = ref.watch(runningSessionProvider).valueOrNull;
    final onTimer = running != null && running.bookId == b.id;
    final pal = kBsCov[b.paletteIdx];

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // 沉浸头图（.bd-bg：封面色板模糊背景 + 蒙层）
                Stack(
                  children: [
                    Positioned.fill(
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [pal.$1, pal.$2],
                            ),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: .18),
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 44),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        b.title,
                                        style: const TextStyle(
                                          fontSize: 19,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                          height: 1.35,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${b.author}'
                                        '${b.translator != null && b.translator!.isNotEmpty ? ' · 译 ${b.translator}' : ''}'
                                        '${b.publisher != null && b.publisher!.isNotEmpty ? '\n${b.publisher}' : ''}',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          height: 1.5,
                                          color: Colors.white.withValues(
                                            alpha: .85,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      // 信息行（LH-K15 可点芯片：条/页/时长/进度）
                                      Row(
                                        children: [
                                          _chip(
                                            '${allQ.length} 条',
                                            BsIcons.quote,
                                            'bd-quotes-chip',
                                            () {
                                              setState(() {
                                                _tab = 'q';
                                                _chapF = null;
                                              });
                                            },
                                          ),
                                          _chip(
                                            bsPosLabel(b),
                                            BsIcons.book,
                                            'bd-pages-chip',
                                            () => showProgressSheet(
                                              context,
                                              ref,
                                              b,
                                            ),
                                          ),
                                          _chip(
                                            bsFmt(agg[b.id]?.minutes ?? 0),
                                            BsIcons.time,
                                            'bd-min-chip',
                                            () => context.push(
                                              '/read/log/${b.id}',
                                            ),
                                          ),
                                          _chip(
                                            '${b.percent}%',
                                            BsIcons.pin,
                                            'bd-pct-chip',
                                            () => showProgressSheet(
                                              context,
                                              ref,
                                              b,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  children: [
                                    BsCover(
                                      book: b,
                                      width: 92,
                                      height: 132,
                                      radius: 12,
                                      onTap: () =>
                                          context.push('/read/info/${b.id}'),
                                      onBadgeTap: () =>
                                          cycleBookState(context, ref, b),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '书籍资料',
                                      style: TextStyle(
                                        fontSize: 8.5,
                                        color: Colors.white.withValues(
                                          alpha: .75,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => context.pop(),
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                color: Colors.white,
                              ),
                            ),
                            const Spacer(),
                            // 顶栏页内动作（LH-K13：36 圆·19px 线性·无文字）
                            _hdrBtn(
                              'bd-timer',
                              BsIcons.timer,
                              onTimer,
                              () => readTimerEntry(ref, context, b),
                            ),
                            _hdrBtn('bd-more', BsIcons.more, false, () async {
                              final gone = await showBookOpsSheet(
                                context,
                                ref,
                                b,
                              );
                              if (gone == true && context.mounted) {
                                context.pop();
                              }
                            }),
                            const SizedBox(width: 10),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                // 三 tab（§3.2：目录 / 书摘 N / 相关 N＝四分组命中共 N 本）
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      _seg('seg-c', '目录', 'c', b),
                      const SizedBox(width: 8),
                      _seg('seg-q', '书摘 ${allQ.length}', 'q', b),
                      const SizedBox(width: 8),
                      _seg(
                        'seg-r',
                        '相关 ${relGroups.fold(0, (t, g) => t + g.ls.length)}',
                        'r',
                        b,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: switch (_tab) {
                    'c' => _tocTab(cs, tokens, b),
                    'q' => Column(
                      children: [
                        if (_chapF != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Text(
                                  '章节 · $_chapF',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: tokens.accent,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  key: const ValueKey('qf-clear'),
                                  onTap: () => setState(() => _chapF = null),
                                  child: Text(
                                    '清除',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: cs.onSurfaceVariant,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        // 分段 chips（原型 bdQSegChips · 点段过滤，再点回全部）
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final (k, label) in [
                                ('all', '全部 ${allQ.length}'),
                                (
                                  'line',
                                  '划线 ${allQ.where((q) => q.kind == BookQuote.kKindMark).length}',
                                ),
                                (
                                  'think',
                                  '想法 ${allQ.where((q) => q.kind == BookQuote.kKindThought).length}',
                                ),
                                ('star', '星标 ${allQ.where((q) => q.starred).length}'),
                              ])
                                GestureDetector(
                                  key: ValueKey('qseg-$k'),
                                  onTap: () => setState(
                                    () => _qSeg = _qSeg == k ? 'all' : k,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 11,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(999),
                                      color: _qSeg == k
                                          ? tokens.accent.withValues(alpha: .12)
                                          : cs.surfaceContainerHighest,
                                      border: Border.all(
                                        color: _qSeg == k
                                            ? tokens.accent
                                            : cs.outlineVariant.withValues(
                                                alpha: .4,
                                              ),
                                      ),
                                    ),
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        color: _qSeg == k
                                            ? tokens.accent
                                            : cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (quotes.isEmpty) _noQuotes(cs, tokens, b),
                        for (final q in quotes) _quoteCard(cs, q),
                      ],
                    ),
                    _ => _related(cs, tokens, b, relGroups),
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 可点信息芯片（LH-K15：虚线下划线 · 可改数值不做纯文本）。
  Widget _chip(String t, IconData ic, String key, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(right: 12),
        child: GestureDetector(
          key: ValueKey(key),
          onTap: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ic, size: 12, color: Colors.white.withValues(alpha: .85)),
              const SizedBox(width: 3),
              Text(
                t,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: .85),
                  decoration: TextDecoration.underline,
                  decorationStyle: TextDecorationStyle.dotted,
                  decorationColor: Colors.white.withValues(alpha: .6),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _hdrBtn(String key, IconData ic, bool active, VoidCallback onTap) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        key: ValueKey(key),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? Colors.white.withValues(alpha: .28)
                : Colors.black.withValues(alpha: .18),
          ),
          child: Icon(ic, size: 19, color: active ? tokens.g3 : Colors.white),
        ),
      ),
    );
  }

  Widget _seg(String key, String label, String tab, Book b) => GestureDetector(
    key: ValueKey(key),
    onTap: () => setState(() => _tab = tab),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: _tab == tab
            ? context.tokens.accent.withValues(alpha: .12)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border.all(
          color: _tab == tab ? context.tokens.accent : Colors.transparent,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: _tab == tab ? context.tokens.accent : null,
        ),
      ),
    ),
  );

  // ---- 目录卡（两级 · 只读 / 编辑就地微调 / 粘贴导入 · §3.3 §3.4） ----

  Widget _tocTab(ColorScheme cs, dynamic tokens, Book b) {
    final nodes = ref.watch(tocProvider(b.id)).valueOrNull;
    if (nodes == null) return const SizedBox(height: 60);
    final groups = tocTree(nodes, hideEmptyParts: !_tocEdit);
    final secCount = groups.fold(0, (t, g) => t + g.sections.length);
    // 每节划线角标：该书该章摘录计数（原型 renderToc 4730 q 位）
    final chapQ = <String, int>{};
    for (final q
        in (ref.watch(allQuotesProvider).valueOrNull ?? const <BookQuote>[])) {
      if (q.bookId == b.id && q.deletedAt == null && (q.chapter ?? '').isNotEmpty) {
        chapQ[q.chapter!] = (chapQ[q.chapter!] ?? 0) + 1;
      }
    }
    // 在读节＝最后一个 startPage ≤ readPages 的小节（原型 done/read 点）
    final withPage = [
      for (final g in groups)
        for (final s in g.sections)
          if (s.startPage != null) s,
    ];
    final cur = withPage.isEmpty
        ? null
        : withPage.lastWhere(
            (s) => s.startPage! <= b.readPages,
            orElse: () => withPage.first,
          );
    final curActive =
        cur != null && cur.startPage! <= b.readPages && b.isReading;
    final repo = ref.read(readRepositoryProvider);
    Future<void> act(Future<void> Function() f) async {
      await f();
      if (!mounted) return;
      ref.read(readTickProvider.notifier).state++;
      setState(() {});
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '目录 · $secCount 节',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              if (groups.isNotEmpty)
                GestureDetector(
                  key: const ValueKey('toc-edit'),
                  onTap: () => setState(() {
                    if (_tocEdit) {
                      act(() => repo.tocPrune(b.id).then((_) {}));
                    }
                    _tocEdit = !_tocEdit;
                  }),
                  child: Text(
                    _tocEdit ? '完成' : '编辑',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: tokens.accent,
                    ),
                  ),
                ),
              if (_tocEdit) const SizedBox(width: 12),
              GestureDetector(
                key: const ValueKey('toc-import'),
                onTap: () =>
                    showTocImportSheet(context, ref, b.id, bookTitle: b.title),
                child: Text(
                  '导入目录',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: tokens.accent,
                  ),
                ),
              ),
              // AI 补全（B 类占位：AI 能力未接入）
              if (!_tocEdit) ...[
                const SizedBox(width: 12),
                GestureDetector(
                  key: const ValueKey('toc-ai'),
                  onTap: () => readToast(context, 'AI 能力规划中（V1.x）'),
                  child: Text(
                    'AI 补全',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: tokens.accent,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '这本书还没有目录 · ',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  GestureDetector(
                    key: const ValueKey('toc-empty-ai'),
                    onTap: () => readToast(context, 'AI 能力规划中（V1.x）'),
                    child: Text(
                      'AI 补全',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: tokens.accent,
                      ),
                    ),
                  ),
                  Text(
                    ' 或 ',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  GestureDetector(
                    key: const ValueKey('toc-empty-import'),
                    onTap: () => showTocImportSheet(
                      context,
                      ref,
                      b.id,
                      bookTitle: b.title,
                    ),
                    child: Text(
                      '导入',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: tokens.accent,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (_tocEdit)
            for (final g in groups) ...[
              TocEditRow(
                node: g.part,
                onRename: (v) => act(() => repo.renameToc(g.part.id!, v)),
                onMove: (d) => act(() => repo.moveToc(g.part.id!, d)),
                onDelete: () => act(() => repo.deleteToc(g.part.id!)),
                onAddSection: () =>
                    act(() => repo.addTocSection(g.part.id!).then((_) {})),
              ),
              for (final s in g.sections)
                TocEditRow(
                  node: s,
                  onRename: (v) => act(() => repo.renameToc(s.id!, v)),
                  onMove: (d) => act(() => repo.moveToc(s.id!, d)),
                  onDelete: () => act(() => repo.deleteToc(s.id!)),
                ),
            ]
          else
            for (final g in groups) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        g.part.title,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    Text(
                      '${g.sections.where((s) => _tocDone(b, s, cur, curActive)).length}'
                      '/${g.sections.length}',
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              for (final s in g.sections)
                GestureDetector(
                  key: ValueKey('toc-s-${s.id}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() {
                    _chapF = s.title;
                    _tab = 'q';
                  }),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, top: 5, bottom: 5),
                    child: Row(
                      children: [
                        // 状态点（原型 toc-dot：done 绿 / 在读品牌色 / 未读灰）
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _tocDone(b, s, cur, curActive)
                                ? const Color(0xFF34D399)
                                : identical(cur, s) && curActive
                                ? tokens.accent as Color
                                : cs.surfaceContainerHighest,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: _tocDone(b, s, cur, curActive) ||
                                      (identical(cur, s) && curActive)
                                  ? cs.onSurface
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                        // 该节划线摘录数角标（原型 q 位：划线图标+N）
                        if ((chapQ[s.title] ?? 0) > 0)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Row(
                              children: [
                                Icon(
                                  BsIcons.quote,
                                  size: 10,
                                  color: tokens.accent as Color,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '${chapQ[s.title]}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: tokens.accent as Color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_tocDone(b, s, cur, curActive))
                          Icon(
                            BsIcons.check,
                            size: 12,
                            color: const Color(0xFF10B981),
                          )
                        else if (identical(cur, s) && curActive)
                          Text(
                            '在读',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: tokens.accent as Color,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          if (_tocEdit)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: GestureDetector(
                key: const ValueKey('toc-addpart'),
                onTap: () => act(() => repo.addTocPart(b.id).then((_) {})),
                child: Text(
                  '＋ 加部分',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: tokens.accent,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _noQuotes(ColorScheme cs, dynamic tokens, Book b) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 26),
    decoration: BoxDecoration(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
    ),
    child: Column(
      children: [
        Text('还没有摘录', style: TextStyle(fontSize: 12, color: cs.onSurface)),
        const SizedBox(height: 8),
        GestureDetector(
          key: const ValueKey('bd-add-quote'),
          onTap: () => showQuoteSheet(context, ref, bookId: b.id),
          child: Text(
            '记一条',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: tokens.accent as Color,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _quoteCard(ColorScheme cs, BookQuote q) => GestureDetector(
    key: ValueKey('bd-q-${q.id}'),
    behavior: HitTestBehavior.opaque,
    // §3.4：摘录卡 → 摘录操作弹层（收藏/编辑/转日记/转待办/转笔记/复制/删除）。
    onTap: () => showQuoteOpsSheet(context, ref, q),
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3.5,
            height: q.body.length > 40 ? 60 : 34,
            decoration: BoxDecoration(
              color: Color(0xFF000000 | q.colorInt),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  q.kind == BookQuote.kKindMark ? '「${q.body}」' : q.body,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.55,
                    color: cs.onSurface,
                  ),
                ),
                if (q.thought != null && q.thought!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      q.thought!,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        fontStyle: FontStyle.italic,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Row(
                    children: [
                      Expanded(child: _qMeta(cs, q)),
                      // 只在已收藏时显示小星（§3.3 卡片平铺动作清空）。
                      if (q.starred)
                        const Icon(
                          Icons.star_rounded,
                          size: 14,
                          color: Color(0xFFF59E0B),
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
  );

  Widget _qMeta(ColorScheme cs, BookQuote q) {
    final d = DateTime.fromMillisecondsSinceEpoch(q.createdAt);
    return Text(
      [
        if ((q.chapter ?? '').isNotEmpty) q.chapter!,
        if (q.page != null) '${q.page} 页',
        '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      ].join(' · '),
      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
    );
  }

  /// 目录节划线状态（原型 renderToc：done 绿点勾 / read 品牌点+「在读」）。
  bool _tocDone(Book b, TocNode s, TocNode? cur, bool curActive) {
    if (s.startPage == null) return false;
    if (b.state == Book.kStateDone) return true;
    if (b.pages <= 0) return false;
    return s.startPage! <= b.readPages && !(identical(s, cur) && curActive);
  }

  /// 相关推荐四分组（原型 bsRelGroups 4720）：同作者/同系列/同标签/同出版社，
  /// 各取 6 本，空组丢弃。
  List<({String lbl, List<Book> ls})> _relGroups(Book b, List<Book> all) {
    final pool = all.where((x) => !x.isDeleted && x.id != b.id).toList();
    final gs = <({String lbl, List<Book> ls})>[
      (
        lbl: '同作者 ${b.author}',
        ls: pool.where((x) => x.author == b.author).take(6).toList(),
      ),
      if ((b.series ?? '').isNotEmpty)
        (
          lbl: '同系列 ${b.series}',
          ls: pool.where((x) => (x.series ?? '') == b.series).take(6).toList(),
        ),
      (
        lbl: '同标签',
        ls: pool
            .where((x) => x.tags.any((t) => b.tags.contains(t)))
            .take(6)
            .toList(),
      ),
      if ((b.publisher ?? '').isNotEmpty && b.publisher != '—')
        (
          lbl: '同出版社',
          ls: pool
                  .where(
                    (x) =>
                        (x.publisher ?? '').isNotEmpty &&
                        x.publisher == b.publisher,
                  )
                  .take(6)
                  .toList(),
        ),
    ];
    return gs.where((g) => g.ls.isNotEmpty).toList();
  }

  Widget _related(
    ColorScheme cs,
    dynamic tokens,
    Book b,
    List<({String lbl, List<Book> ls})> groups,
  ) {
    if (groups.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 26),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
        ),
        child: Text(
          '还没有同作者 / 同系列 / 同标签的书',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
      );
    }
    final qCount = <String, int>{};
    for (final q
        in (ref.watch(allQuotesProvider).valueOrNull ?? const <BookQuote>[])) {
      if (q.deletedAt == null) qCount[q.bookId] = (qCount[q.bookId] ?? 0) + 1;
    }
    return Column(
      children: [
        for (final g in groups)
          Container(
            key: ValueKey('relgrp-${g.lbl}'),
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: .4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${g.lbl} · ${g.ls.length} 本',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                for (final x in g.ls)
                  GestureDetector(
                    key: ValueKey('rel-${x.id}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => context.push('/read/book/${x.id}'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          BsCover(
                            book: x,
                            width: 28,
                            height: 40,
                            radius: 5,
                            showAuthor: false,
                            showBadge: false,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  x.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '${x.author} · ${x.state} · ${qCount[x.id] ?? 0} 条摘录',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: cs.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
