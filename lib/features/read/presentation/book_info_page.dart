import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/book.dart';
import '../domain/book_progress.dart';
import '../domain/book_quote.dart';
import '../domain/book_session.dart';
import 'read_providers.dart';
import 'read_sheets.dart';
import 'shelf_page.dart' show shelfUiProvider, ShelfUI;
import 'widgets/bs_cover.dart';

/// 书籍资料页（原型 p-bookInfo · §3.2 拆两屏之资料屏）。
/// 顶栏＝编辑信息 + 操作；数据卡可下钻；进度行可点改；总结就地可编辑；
/// 底部轨迹卡 + 回阅读视图。
class BookInfoPage extends ConsumerStatefulWidget {
  const BookInfoPage({super.key, required this.bookId});
  final String bookId;

  @override
  ConsumerState<BookInfoPage> createState() => _BookInfoPageState();
}

class _BookInfoPageState extends ConsumerState<BookInfoPage> {
  bool _sumEdit = false;
  final _sq = TextEditingController();
  final _sv = TextEditingController();
  final _sg = TextEditingController();

  @override
  void dispose() {
    _sq.dispose();
    _sv.dispose();
    _sg.dispose();
    super.dispose();
  }

  void _fillSummary(Book b) {
    _sq.text = b.sumQuote ?? '';
    _sv.text = b.sumView ?? '';
    _sg.text = b.sumGain ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final b = (ref.watch(booksProvider).valueOrNull ?? const <Book>[])
        .where((e) => e.id == widget.bookId)
        .firstOrNull;
    if (b == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('书籍资料')),
        body: const SizedBox.shrink(),
      );
    }
    final agg = ref.watch(workbenchProvider).valueOrNull?.agg[b.id];
    final quotes =
        (ref.watch(allQuotesProvider).valueOrNull ?? const <BookQuote>[])
            .where((q) => q.bookId == b.id && q.deletedAt == null)
            .toList();
    final sessions =
        ref.watch(sessionsOfProvider(b.id)).valueOrNull ??
        const <BookSession>[];
    final closedSess = sessions.where(
      (s) => s.endedAt != null && s.endedAt! >= s.startedAt,
    );
    // 自动生成口径：首条划线 / 分类聚合 / 想法计数（人工覆写走 books.sum_*）
    final autoQuote = quotes
        .where((q) => q.kind == BookQuote.kKindMark)
        .firstOrNull
        ?.body;
    final topTag = <String, int>{for (final q in quotes) q.tag: 0};
    for (final q in quotes) {
      topTag[q.tag] = (topTag[q.tag] ?? 0) + 1;
    }
    final autoView = topTag.entries.isEmpty
        ? null
        : topTag.entries.reduce((a, c) => a.value >= c.value ? a : c).key;
    final autoGain =
        '${quotes.where((q) => q.kind == BookQuote.kKindThought).length} 条想法';
    final fc = ProgressForecast.of(b);

    return Scaffold(
      appBar: AppBar(
        title: Text('书籍资料', style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(
            key: const ValueKey('bi-edit'),
            tooltip: '编辑信息',
            onPressed: () => showBookFormSheet(context, ref, editing: b),
            icon: const Icon(BsIcons.pen, size: 19),
          ),
          IconButton(
            key: const ValueKey('bi-more'),
            tooltip: '操作',
            onPressed: () => showBookOpsSheet(context, ref, b),
            icon: const Icon(BsIcons.more, size: 19),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BsCover(book: b, width: 74, height: 106, radius: 9),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        b.author,
                        if ((b.translator ?? '').isNotEmpty)
                          '译 ${b.translator}',
                        if ((b.publisher ?? '').isNotEmpty) b.publisher!,
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    // 星级评分（原型 renderBookInfo 页头 5 星 · 半分即实心）
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        key: const ValueKey('bi-rate'),
                        children: [
                          for (var i = 1; i <= 5; i++)
                            Icon(
                              b.rating >= i - .5
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 14,
                              color: b.rating >= i - .5
                                  ? const Color(0xFFF59E0B)
                                  : cs.onSurfaceVariant.withValues(alpha: .5),
                            ),
                          const SizedBox(width: 4),
                          Text(
                            b.rating > 0 ? _num(b.rating) : '未评',
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _tagChip(cs, b.state),
                        // 合并 chip（原型 bsMetaChips 4555：fmt · 进度口径）
                        _tagChip(cs, '${b.format} · ${bsPosLabel(b)}'),
                        // 购书 ¥fee（有 fee 才出）
                        if (b.fee > 0) _tagChip(cs, '购书 ¥${_num(b.fee)}'),
                        for (final t in b.tags)
                          GestureDetector(
                            key: ValueKey('bi-tag-$t'),
                            onTap: () {
                              ref.read(shelfUiProvider.notifier).state =
                                  ShelfUI(dim: 'tag', dimVal: t);
                              context.push('/read/shelf');
                            },
                            child: _tagChip(cs, '#$t'),
                          ),
                        if ((b.source ?? '').isNotEmpty)
                          GestureDetector(
                            key: ValueKey('bi-src'),
                            onTap: () {
                              ref.read(shelfUiProvider.notifier).state =
                                  ShelfUI(dim: 'src', dimVal: b.source!);
                              context.push('/read/shelf');
                            },
                            child: _tagChip(cs, b.source!),
                          ),
                        if ((b.grp ?? '').isNotEmpty) _tagChip(cs, b.grp!),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 数据卡四格（原型 renderBookInfo 5664-5668 顺序：
          // 摘录/感想 · 累计阅读 · 计时次数 · 分钟/页；后两卡可点下钻明细）
          Row(
            children: [
              _dataCard(context, null, '摘录/感想', '${quotes.length}', null),
              const SizedBox(width: 8),
              _dataCard(
                context,
                'bi-min',
                '累计阅读',
                bsFmt(agg?.minutes ?? 0),
                () => context.push('/read/log/${b.id}'),
              ),
              const SizedBox(width: 8),
              _dataCard(
                context,
                'bi-times',
                '计时次数',
                '${agg?.times ?? 0}',
                () => context.push('/read/log/${b.id}'),
              ),
              const SizedBox(width: 8),
              _dataCard(context, null, '分钟/页', _speedOf(b, agg?.minutes ?? 0), null),
            ],
          ),
          const SizedBox(height: 12),
          // 进度卡（原型 5669-5672：标题「阅读进度」+ 进度方式名 + 可点数值）
          GestureDetector(
            key: const ValueKey('bi-prog'),
            onTap: () => showProgressSheet(context, ref, b),
            child: _card(
              context,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '阅读进度',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '进度方式',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        bsWayName(b.progressWay),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          b.progressWay == Book.kWayMin
                              ? '${b.percent}% · 有声'
                              : '${bsPosLabel(b)} · ${b.percent}%',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: tokens.accent,
                            decoration: TextDecoration.underline,
                            decorationStyle: TextDecorationStyle.dotted,
                            decorationColor: tokens.accent.withValues(alpha: .5),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  BkPctBar(book: b),
                  const SizedBox(height: 4),
                  Text(
                    '均速 ${fc.pagesPerDay <= 0 ? '—' : fc.pagesPerDay.toStringAsFixed(1)} 页/天 · ${forecastLabel(fc)}',
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 档案字段
          _card(
            context,
            Column(
              children: [
                for (final (k, v) in [
                  ('ISBN', b.isbn),
                  ('出版日期', b.pubDate),
                  ('系列', b.series),
                  ('购书费', b.fee > 0 ? '¥${b.fee}' : null),
                  ('开始阅读', _d(b.startedAt)),
                  ('读完', _d(b.endedAt)),
                  ('最近阅读', _d(b.lastReadAt ?? b.updatedAt)),
                ])
                  if ((v ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 74,
                            child: Text(
                              k,
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              v!,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
          if ((b.intro ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            _card(
              context,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '简介',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    b.intro!,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.6,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          // 一页式总结（可编辑 · 恢复自动生成 · §3.3）
          _card(
            context,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '一页式总结',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      key: const ValueKey('sum-edit'),
                      onTap: () {
                        if (!_sumEdit) _fillSummary(b);
                        setState(() => _sumEdit = !_sumEdit);
                      },
                      child: Text(
                        _sumEdit ? '完成' : '编辑',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: tokens.accent,
                        ),
                      ),
                    ),
                    if (_sumEdit) ...[
                      const SizedBox(width: 12),
                      GestureDetector(
                        key: const ValueKey('sum-reset'),
                        onTap: () async {
                          await ref
                              .read(readRepositoryProvider)
                              .updateBook(
                                b.copyWith(
                                  sumQuote: '',
                                  sumView: '',
                                  sumGain: '',
                                ),
                              );
                          if (!mounted) return;
                          ref.read(readTickProvider.notifier).state++;
                          setState(() => _sumEdit = false);
                          readToast(this.context, '已恢复自动生成');
                        },
                        child: Text(
                          '恢复自动生成',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                if (_sumEdit)
                  for (final (key, ctl, label) in [
                    ('sum-q', _sq, '金句'),
                    ('sum-v', _sv, '核心观点'),
                    ('sum-g', _sg, '我的收获'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        key: ValueKey(key),
                        controller: ctl,
                        maxLines: 2,
                        style: const TextStyle(fontSize: 11.5),
                        decoration: InputDecoration(
                          labelText: label,
                          labelStyle: const TextStyle(fontSize: 11.5),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: cs.surfaceContainerHighest,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                    )
                else if (b.sumQuote?.isNotEmpty == true ||
                    b.sumView?.isNotEmpty == true ||
                    b.sumGain?.isNotEmpty == true)
                  for (final (label, v) in [
                    ('金句', b.sumQuote),
                    ('观点', b.sumView),
                    ('收获', b.sumGain),
                  ])
                    if ((v ?? '').isNotEmpty)
                      _sumRow(cs, tokens, label, v!)
                    else
                      for (final (label, v) in [
                        ('金句', autoQuote),
                        ('观点', autoView != null ? '分类集中在「$autoView」' : null),
                        ('收获', autoGain),
                      ])
                        if ((v ?? '').isNotEmpty)
                          _sumRow(cs, tokens, label, v!),
                if (_sumEdit)
                  GestureDetector(
                    key: const ValueKey('sum-save'),
                    onTap: () async {
                      await ref
                          .read(readRepositoryProvider)
                          .updateBook(
                            b.copyWith(
                              sumQuote: _sq.text.trim(),
                              sumView: _sv.text.trim(),
                              sumGain: _sg.text.trim(),
                            ),
                          );
                      if (!mounted) return;
                      ref.read(readTickProvider.notifier).state++;
                      setState(() => _sumEdit = false);
                      readToast(this.context, '总结已保存');
                    },
                    child: Text(
                      '保存总结',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: tokens.accent,
                      ),
                    ),
                  ),
                // 查看态双钮（原型 5695：导出 MD / 转存笔记·联动 L5）
                if (!_sumEdit)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        OutlinedButton(
                          key: const ValueKey('sum-export'),
                          onPressed: () async {
                            final repo = ref.read(readRepositoryProvider);
                            final txt = await repo.buildBookQuotesMd(b);
                            final dir = await getApplicationDocumentsDirectory();
                            final f = File(
                              p.join(
                                dir.path,
                                'share',
                                '《${b.title}》书摘.md',
                              ),
                            );
                            await f.parent.create(recursive: true);
                            await f.writeAsString(txt);
                            if (!mounted) return;
                            readToast(
                              this.context,
                              '已导出为 Markdown：《${b.title}》${quotes.length} 条笔记',
                            );
                          },
                          child: const Text(
                            '导出 MD',
                            style: TextStyle(fontSize: 11.5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          key: const ValueKey('sum-to-note'),
                          onPressed: () async {
                            await ref
                                .read(readRepositoryProvider)
                                .bookToNote(b);
                            if (!mounted) return;
                            ref.read(readTickProvider.notifier).state++;
                            readToast(this.context, '已存为笔记（联动 L5）');
                          },
                          child: const Text(
                            '转存笔记',
                            style: TextStyle(fontSize: 11.5),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 轨迹卡（逐日柱状 · 点顶行直跳计时明细）
          _card(
            context,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '阅读轨迹',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      key: const ValueKey('trk-detail'),
                      onTap: () => context.push('/read/log/${b.id}'),
                      child: Text(
                        '改明细',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: tokens.accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (closedSess.isEmpty)
                  Text(
                    '还没有计时记录',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  )
                else
                  SizedBox(
                    height: 56,
                    child: LayoutBuilder(
                      builder: (_, box) {
                        final byDay = <String, int>{};
                        for (final s in closedSess) {
                          final d = DateTime.fromMillisecondsSinceEpoch(
                            s.endedAt!,
                          );
                          final k = '${d.month}-${d.day}';
                          byDay[k] = (byDay[k] ?? 0) + s.billedMinutes;
                        }
                        final days = byDay.entries.toList()
                          ..sort((a, b) => a.key.compareTo(b.key));
                        final maxV = days
                            .map((e) => e.value)
                            .reduce((a, c) => a > c ? a : c);
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (final (i, e) in days.indexed)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 1.5,
                                  ),
                                  child: Tooltip(
                                    message: '${e.key} · ${e.value}′',
                                    child: Container(
                                      height:
                                          48 * (e.value / maxV).clamp(.08, 1.0),
                                      decoration: BoxDecoration(
                                        color: tokens.accent.withValues(
                                          alpha:
                                              .35 + .55 * (i.isEven ? .7 : 1),
                                        ),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: const ValueKey('bi-back'),
            onPressed: () => context.pop(),
            icon: const Icon(BsIcons.book, size: 16),
            label: const Text('回阅读视图'),
          ),
        ],
      ),
    );
  }

  static String? _d(int? ms) => ms == null
      ? null
      : () {
          final d = DateTime.fromMillisecondsSinceEpoch(ms);
          return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        }();

  /// 数值去尾（59.0 → '59'，6.5 → '6.5'·原型 bsSpeed/fee 直出观感）。
  static String _num(num v) => v % 1 == 0 ? '${v.toInt()}' : '$v';

  /// 分钟/页速度（原型 bsSpeed 4472：rp>0 → min/rp，一位小数；无数据 '—'）。
  static String _speedOf(Book b, int minutes) =>
      b.readPages > 0 && minutes > 0
      ? _num((minutes / b.readPages * 10).roundToDouble() / 10)
      : '—';

  Widget _sumRow(ColorScheme cs, dynamic tokens, String label, String v) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 40,
              child: Text(
                label,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
            Expanded(
              child: Text(
                v,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, height: 1.5),
              ),
            ),
          ],
        ),
      );

  Widget _tagChip(ColorScheme cs, String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
    decoration: BoxDecoration(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      t,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: cs.onSurfaceVariant,
      ),
    ),
  );

  Widget _dataCard(
    BuildContext context,
    String? key,
    String label,
    String v,
    VoidCallback? onTap,
  ) => Expanded(
    child: GestureDetector(
      key: key == null ? null : ValueKey(key),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: .4),
          ),
        ),
        child: Column(
          children: [
            Text(
              v,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _card(BuildContext context, Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: .4),
      ),
    ),
    child: child,
  );
}
