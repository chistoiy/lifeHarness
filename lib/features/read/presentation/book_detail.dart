import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/book.dart';
import '../domain/book_quote.dart';
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
/// 资料页 / 目录导入 / 计时明细在批2 接；本批 = 头图 + 三分区角标 + 书摘/相关真实列表。
class BookDetailPage extends ConsumerStatefulWidget {
  const BookDetailPage({super.key, required this.bookId, this.initialTab = 'c'});
  final String bookId;
  final String initialTab;

  @override
  ConsumerState<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends ConsumerState<BookDetailPage> {
  late String _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final books = ref.watch(booksProvider).valueOrNull ?? const <Book>[];
    final b = books.where((e) => e.id == widget.bookId).firstOrNull;
    if (b == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('书籍')),
          body: const SizedBox.shrink());
    }
    final quotes = (ref.watch(allQuotesProvider).valueOrNull ??
            const <BookQuote>[])
        .where((q) => q.bookId == b.id)
        .toList();
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
                                  colors: [pal.$1, pal.$2])),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                    Positioned.fill(
                        child: ColoredBox(
                            color: Colors.black.withValues(alpha: .18))),
                    SafeArea(
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(20, 0, 16, 16),
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
                                      Text(b.title,
                                          style: const TextStyle(
                                              fontSize: 19,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.white,
                                              height: 1.35)),
                                      const SizedBox(height: 6),
                                      Text(
                                          '${b.author}'
                                          '${b.translator != null && b.translator!.isNotEmpty ? ' · 译 ${b.translator}' : ''}'
                                          '${b.publisher != null && b.publisher!.isNotEmpty ? '\n${b.publisher}' : ''}',
                                          style: TextStyle(
                                              fontSize: 11.5,
                                              height: 1.5,
                                              color: Colors.white
                                                  .withValues(alpha: .85))),
                                      const SizedBox(height: 8),
                      // 信息行（LH-K15 可点芯片在批2 接计时明细/记进度弹层）
                                      Row(children: [
                                        _info('${quotes.length} 条',
                                            BsIcons.quote),
                                        _info(
                                            b.progressWay == Book.kWayPos
                                                ? '${(b.readLoc ?? 0).round()} 位置'
                                                : '${b.readPages} 页',
                                            BsIcons.book),
                                        _info(
                                            bsFmt((agg[b.id]?.minutes ?? 0)),
                                            BsIcons.time),
                                        _info('${b.percent}%', BsIcons.pin),
                                      ]),
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
                                        onBadgeTap: () =>
                                            cycleBookState(context, ref, b)),
                                    const SizedBox(height: 4),
                                    Text('书籍资料',
                                        style: TextStyle(
                                            fontSize: 8.5,
                                            color: Colors.white
                                                .withValues(alpha: .75))),
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
                                icon: const Icon(Icons.arrow_back_rounded,
                                    color: Colors.white)),
                            const Spacer(),
                            // 顶栏页内动作（LH-K13：36 圆·19px 线性·无文字）
                            _hdrBtn('bd-timer', BsIcons.timer, onTimer, () =>
                                readTimerTap(ref, context, target: b)),
                            _hdrBtn('bd-more', BsIcons.more, false, () async {
                              final gone =
                                  await showBookOpsSheet(context, ref, b);
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
                // 三 tab（§3.2：目录 / 书摘 N / 相关 N）
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      _seg('seg-c', '目录', 'c', b),
                      const SizedBox(width: 8),
                      _seg('seg-q', '书摘 ${quotes.length}', 'q', b),
                      const SizedBox(width: 8),
                      _seg('seg-r', '相关 ${_relOf(b, books).length}', 'r', b),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: switch (_tab) {
                    'c' => _tocEmpty(cs),
                    'q' => quotes.isEmpty
                        ? _noQuotes(cs, tokens)
                        : Column(
                            children: [
                              for (final q in quotes) _quoteCard(cs, q),
                            ],
                          ),
                    _ => _related(cs, tokens, b, books),
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Map<String, ({int minutes, int times})> get agg =>
      ref.watch(workbenchProvider).valueOrNull?.agg ?? const {};

  Widget _info(String t, IconData ic) => Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ic, size: 12, color: Colors.white.withValues(alpha: .85)),
            const SizedBox(width: 3),
            Text(t,
                style: TextStyle(
                    fontSize: 11, color: Colors.white.withValues(alpha: .85))),
          ],
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
                  : Colors.black.withValues(alpha: .18)),
          child: Icon(ic,
              size: 19, color: active ? tokens.g3 : Colors.white),
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
                color: _tab == tab ? context.tokens.accent : Colors.transparent),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _tab == tab ? context.tokens.accent : null)),
        ),
      );

  Widget _tocEmpty(ColorScheme cs) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 26),
        decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: .4))),
        child: Column(children: [
          Text('还没有目录', style: TextStyle(fontSize: 12, color: cs.onSurface)),
          const SizedBox(height: 4),
          Text('导入目录后可按章节记摘录',
              style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant)),
        ]),
      );

  Widget _noQuotes(ColorScheme cs, dynamic tokens) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 26),
        decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: .4))),
        child: Column(children: [
          Text('还没有摘录', style: TextStyle(fontSize: 12, color: cs.onSurface)),
          const SizedBox(height: 8),
          GestureDetector(
            key: const ValueKey('bd-add-quote'),
            onTap: () => showQuoteSheet(context, ref, bookId: widget.bookId),
            child: Text('记一条',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: tokens.accent as Color)),
          ),
        ]),
      );

  Widget _quoteCard(ColorScheme cs, BookQuote q) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: .4))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
                width: 3.5,
                height: q.body.length > 40 ? 60 : 34,
                decoration: BoxDecoration(
                    color: Color(0xFF000000 | q.colorInt),
                    borderRadius: BorderRadius.circular(2))),
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
                          color: cs.onSurface)),
                  if (q.thought != null && q.thought!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(q.thought!,
                          style: TextStyle(
                              fontSize: 11.5,
                              height: 1.5,
                              fontStyle: FontStyle.italic,
                              color: cs.onSurfaceVariant)),
                    ),
                ],
              ),
            ),
          ],
        ),
      );

  List<Book> _relOf(Book b, List<Book> all) => all
      .where((x) =>
          !x.isDeleted &&
          x.id != b.id &&
          (x.author == b.author ||
              x.tags.any((t) => b.tags.contains(t)) ||
              (b.series != null && x.series == b.series)))
      .toList();

  Widget _related(ColorScheme cs, dynamic tokens, Book b, List<Book> all) {
    final rel = _relOf(b, all);
    if (rel.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 26),
        decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: .4))),
        child: Text('还没有同作者 / 同系列 / 同标签的书',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      );
    }
    return Column(
      children: [
        for (final x in rel)
          GestureDetector(
            key: ValueKey('rel-${x.id}'),
            onTap: () => context.push('/read/book/${x.id}'),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: .4))),
              child: Row(
                children: [
                  BsCover(
                      book: x,
                      width: 28,
                      height: 40,
                      radius: 5,
                      showAuthor: false,
                      showBadge: false),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(x.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800)),
                        Text('${x.author} · ${x.state}',
                            style: TextStyle(
                                fontSize: 10, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 16, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
