import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/book.dart';
import '../domain/book_quote.dart';
import 'book_detail.dart' show BookDetailArg;
import 'read_actions.dart';
import 'read_providers.dart';
import 'read_sheets.dart';
import 'shelf_page.dart' show showLongPressSheet;
import 'widgets/bs_cover.dart';

/// 记录页·阅读 tab = 书架工作台（原型 renderRecHub · V1.30 §3.4）。
class ReadWorkbench extends ConsumerWidget {
  const ReadWorkbench({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(workbenchProvider);
    // 读取链路上挂一次倍速开关，同步 BookSession.speedFold 静态桥（§6）。
    ref.watch(speedFoldProvider);
    final data = w.valueOrNull;
    if (data == null) return const SizedBox.shrink();
    final tokens = context.tokens;
    final running = data.running;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        // 今日阅读渐变卡：环 + 摘要 + 对最近阅读的在读书起停
        Container(
          decoration: BoxDecoration(
            gradient: tokens.gradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: tokens.accent.withValues(alpha: .2),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: CustomPaint(
                      painter: _RingPainter(
                        frac: data.goalDay == 0
                            ? 0
                            : (data.minutesToday / data.goalDay).clamp(
                                0.0,
                                1.0,
                              ),
                      ),
                      child: Center(
                        child: Text(
                          '${data.minutesToday}′',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '今日阅读 ${data.minutesToday} / ${data.goalDay} 分钟 '
                          '${data.minutesToday >= data.goalDay ? '已达成' : '· 还差 ${data.goalDay - data.minutesToday} 分钟'} · 连续 ${data.streak} 天',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '在读 ${data.reading.length} 本 · 今年读完 ${data.doneThisYear}/${data.goalBooks} 本 · 本周 ${bsFmt(data.minutesWeek)} / 目标 ${bsFmt(data.goalWeek)}',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.white.withValues(alpha: .8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    key: const ValueKey('read-timer'),
                    onTap: () => readTimerTap(ref, context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .2),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        running == null ? '计时' : '结束计时',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // 五枚纯图标入口（LH-K14：36 高·17px 线性·无文字）
              Row(
                children: [
                  _navBtn(
                    context,
                    'read-nav-shelf',
                    BsIcons.shelf,
                    '书架',
                    () => context.push('/read/shelf'),
                  ),
                  _navBtn(
                    context,
                    'read-nav-list',
                    BsIcons.list,
                    '书单',
                    () => context.push('/read/lists'),
                  ),
                  _navBtn(
                    context,
                    'read-nav-quotes',
                    BsIcons.quote,
                    '笔记库',
                    () => context.push('/read/quotes'),
                  ),
                  _navBtn(
                    context,
                    'read-nav-stat',
                    BsIcons.chart,
                    '统计',
                    () => context.push('/read/stat'),
                  ),
                  _navBtn(
                    context,
                    'read-nav-set',
                    BsIcons.cog,
                    '设置',
                    () => context.push('/read/settings'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (data.rail.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: _cardDeco(context),
            child: Center(
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  children: [
                    const TextSpan(text: '书架还是空的 · '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: GestureDetector(
                        key: const ValueKey('read-empty-add'),
                        onTap: () => showAddBookSheet(context, ref),
                        child: Text(
                          '添加一本',
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
              ),
            ),
          )
        else
          SizedBox(
            height: 203,
            child: ListView.separated(
              key: const ValueKey('read-rail'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              itemCount: data.rail.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _RailCard(book: data.rail[i]),
            ),
          ),
        const SizedBox(height: 12),
        _quotesCard(context, ref, data.quotes, data.books),
        const SizedBox(height: 12),
        _reviewCard(context, ref, data.quotesTotal, data.dueReviews),
      ],
    );
  }

  BoxDecoration _cardDeco(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
    );
  }

  Widget _navBtn(
    BuildContext context,
    String key,
    IconData icon,
    String tip,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.5),
        child: Tooltip(
          message: tip,
          child: GestureDetector(
            key: ValueKey(key),
            onTap: onTap,
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 17, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  Widget _quotesCard(
    BuildContext context,
    WidgetRef ref,
    List<BookQuote> quotes,
    List<Book> books,
  ) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '最近摘录',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          if (quotes.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '还没有摘录 · 右下角 ＋ 记第一条',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
          for (final q in quotes)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.push(
                  '/read/book/${q.bookId}',
                  extra: const BookDetailArg(tab: 'q'),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: Color(0xFF000000 | q.colorInt),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      // 原型 5600：正文（划线带「」）+「 — 书名」灰尾段整体两行截断。
                      child: RichText(
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.5,
                            color: cs.onSurface,
                          ),
                          children: [
                            TextSpan(
                              text: q.kind == BookQuote.kKindMark
                                  ? '「${q.body}」'
                                  : q.body,
                            ),
                            TextSpan(
                              text:
                                  ' — ${books.firstWhere((b) => b.id == q.bookId, orElse: () => Book(id: q.bookId, title: '—', createdAt: 0, updatedAt: 0)).title}',
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '›',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (quotes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: GestureDetector(
                onTap: () => context.push('/read/quotes'),
                child: Text(
                  '去笔记库',
                  style: TextStyle(
                    fontSize: 10,
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

  Widget _reviewCard(BuildContext context, WidgetRef ref, int total, int due) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      key: const ValueKey('read-review'),
      behavior: HitTestBehavior.opaque,
      onTap: () => showReviewSheet(context, ref),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _cardDeco(context),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                BsIcons.think,
                size: 17,
                color: Color(0xFF8B5CF6),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '摘录复习',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '共 $total 条 · 今日到期 $due 条',
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// 封面横向滑动轨道卡（LH-L07：106px 列宽·露半张暗示·按最近阅读倒序；
/// 原型 5543 oncontextmenu＝长按与书架同一 showLongPressSheet）。
class _RailCard extends ConsumerWidget {
  const _RailCard({required this.book});
  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 106,
      child: GestureDetector(
        key: ValueKey('rail-${book.id}'),
        onTap: () => context.push('/read/book/${book.id}'),
        onLongPress: () => showLongPressSheet(context, ref, book),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BsCover(book: book),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 5),
              child: Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
            ),
            BkPctBar(book: book),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.frac});
  final double frac;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 4;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = Colors.white.withValues(alpha: .26),
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -1.5708,
      6.2832 * frac,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.frac != frac;
}
