import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/book.dart';
import '../../domain/shelf_query.dart' show sessionAggByBook, quoteCountByBook;
import '../shelf/read_lists_page.dart' show openYearBooklist;
import '../read_providers.dart';
import '../read_sheets.dart';
import 'read_stat_widgets.dart';
import 'read_stat_heat_card.dart';

/// 阅读统计（原型 p-readstat · §3.4：年×月钻取 + 度量/构成切换 + 四卡 +
/// 热力图 + 月度柱 + 构成环 + 时段 + 均速 + 购书支出/完读书字数 + 目标五路）。
class ReadStatPage extends ConsumerStatefulWidget {
  const ReadStatPage({super.key});

  @override
  ConsumerState<ReadStatPage> createState() => _ReadStatPageState();
}

/// 年度聚合数据（一次取齐）。
class StatData {
  const StatData({
    required this.year,
    required this.dayMinutes,
    required this.dayQuotes,
    required this.hours,
    required this.books,
    required this.minutesByBook,
    required this.quotesByBook,
    required this.speed,
    required this.fee,
    required this.paid,
    required this.words,
    required this.rdMin,
    required this.doneYear,
    required this.quotesYear,
    required this.readingNow,
  });

  final int year;
  final Map<DateTime, int> dayMinutes;
  final Map<DateTime, int> dayQuotes;
  final List<int> hours;

  /// 构成分布数据源：藏书与每本累计分钟（按维度现场聚合）。
  final List<Book> books;
  final Map<String, int> minutesByBook;

  /// ⑦ 按书累计时长段的行内摘录数（在库行口径，与笔记库计数同源）。
  final Map<String, int> quotesByBook;

  /// 均速榜：(书名, 分/页)。
  final List<({String title, double minPerPage})> speed;
  final double fee;
  final int paid;
  final int words;
  final int rdMin;
  final int doneYear;
  final int quotesYear;
  final int readingNow;
}

final _statProvider = FutureProvider.family<StatData, int>((ref, year) async {
  ref.watch(readTickProvider);
  final repo = ref.watch(readRepositoryProvider);
  final log = await repo.dayLogYear(year);
  final quotes = await repo.dayQuotesYear(year);
  final hours = await repo.hourHistogram(year);
  final books = (await repo.allBooks()).where((b) => !b.isDeleted).toList();
  final sessions = await repo.allSessions();
  final agg = sessionAggByBook(sessions);
  final quotesByBook = quoteCountByBook(await repo.allQuotes());
  final speed = [
    for (final b in books)
      if (b.readPages > 0 && (agg[b.id]?.minutes ?? 0) > 0)
        (title: b.title, minPerPage: agg[b.id]!.minutes / b.readPages),
  ]..sort((a, b) => a.minPerPage.compareTo(b.minPerPage));
  final fee = await repo.feeTotals();
  final words = await repo.doneWords();
  return StatData(
    year: year,
    dayMinutes: {for (final d in log) d.day: d.minutes},
    dayQuotes: quotes,
    hours: hours,
    books: books,
    minutesByBook: {for (final b in books) b.id: agg[b.id]?.minutes ?? 0},
    quotesByBook: quotesByBook,
    speed: speed.take(5).toList(),
    fee: fee.fee,
    paid: fee.paid,
    words: words.words,
    rdMin: words.rdMin,
    doneYear: books
        .where(
          (b) =>
              b.state == Book.kStateDone &&
              b.endedAt != null &&
              DateTime.fromMillisecondsSinceEpoch(b.endedAt!).year == year,
        )
        .length,
    quotesYear: quotes.values.fold<int>(0, (t, v) => t + v),
    readingNow: books.where((b) => b.state == Book.kStateReading).length,
  );
});

class _ReadStatPageState extends ConsumerState<ReadStatPage> {
  static const _pal = [
    Color(0xFF6366F1),
    Color(0xFF2DD4BF),
    Color(0xFFF59E0B),
    Color(0xFFFB7185),
    Color(0xFF8B5CF6),
    Color(0xFF0EA5E9),
  ];
  late int _year = DateTime.now().year;
  int _month = 0; // 0＝全年
  String _metric = 'min'; // min / q / day
  String _dim = 'tag'; // tag/src/st/grp/rate（原型 rsDim）
  bool _ctlOpen = false;

  /// 目标卡提醒行：read.dailyQ（默认开）+ 提醒时刻（默认 21:30）。
  bool get _remindOn =>
      (ref.watch(readKvProvider(('read.dailyQ', 'true'))).valueOrNull ??
          'true') ==
      'true';
  int get _remindMin =>
      int.tryParse(
        ref.watch(readKvProvider(('read.goalRemindMin', '1290'))).valueOrNull ??
            '1290',
      ) ??
      1290;
  static String _hhmm(int m) =>
      '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';

  double _val(DateTime d, StatData s) => switch (_metric) {
    'q' => (s.dayQuotes[d] ?? 0).toDouble(),
    'day' => (s.dayMinutes[d] ?? 0) > 0 ? 1 : 0,
    _ => (s.dayMinutes[d] ?? 0).toDouble(),
  };

  String _metName() => switch (_metric) {
    'q' => '摘录条数',
    'day' => '是否读够',
    _ => '时长（分钟）',
  };

  /// 范围内每一天（0＝全年；月＝自然月）。
  List<DateTime> _rangeDays(int year, int month) {
    if (month == 0) {
      final first = DateTime(year);
      return List.generate(
        DateTime(year, 12, 31).difference(first).inDays + 1,
        (i) => first.add(Duration(days: i)),
      );
    }
    final first = DateTime(year, month);
    final last = DateTime(year, month + 1);
    return List.generate(last.difference(first).inDays, (i) => first.add(Duration(days: i)));
  }

  /// 收起时摘要标签（原型 rsCtlLabel 5528：'2026 · 全年 · 时长 · 标签'）。
  String _ctlLabel() =>
      '$_year · ${_month == 0 ? '全年' : '$_month月'} · '
      '${switch (_metric) {
        'q' => '摘录',
        'day' => '天数',
        _ => '时长',
      }} · '
      '${switch (_dim) {
        'src' => '来源',
        'st' => '分区',
        'grp' => '分组',
        'rate' => '评分',
        _ => '标签',
      }}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final s = ref.watch(_statProvider(_year)).valueOrNull;
    final w = ref.watch(workbenchProvider).valueOrNull;
    final years = List<int>.generate(
      DateTime.now().year - 2021 + 1,
      (i) => 2021 + i,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('阅读统计')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                // 原型 889：页内 chip「范围 ▾」＋右侧灰字「点选范围与度量」。
                Row(
                  children: [
                    GestureDetector(
                      key: const ValueKey('rs-ctl'),
                      onTap: () => setState(() => _ctlOpen = !_ctlOpen),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color:
                              _ctlOpen
                                  ? tokens.accent.withValues(alpha: .12)
                                  : cs.surfaceContainerHighest,
                          border: Border.all(
                            color: _ctlOpen
                                ? tokens.accent
                                : cs.outlineVariant.withValues(alpha: .5),
                          ),
                        ),
                        child: Text(
                          '${_ctlLabel()} ▾',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color:
                                _ctlOpen ? tokens.accent : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '点选范围与度量',
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (_ctlOpen) ...[const SizedBox(height: 8), _panel(cs, tokens, years, s)],
                const SizedBox(height: 8),
                _fourCards(cs, s, w),
                const SizedBox(height: 12),
                ReadStatHeatCard(
                  key: ValueKey('rs-heat-$_year-$_month-$_metric'),
                  year: s.year,
                  month: _month,
                  scopeTag: '$_year-$_month-$_metric',
                  metricName: _metName(),
                  goalDay: w?.goalDay ?? 30,
                  valueAt: (i) =>
                      _val(DateTime(s.year).add(Duration(days: i)), s),
                  minutesAt: (d) => s.dayMinutes[d] ?? 0,
                  summary: _heatSummary(s),
                  onTapDay: (ctx, d, i) {
                    final m = s.dayMinutes[d] ?? 0;
                    final gd = w?.goalDay ?? 30;
                    readToast(
                      ctx,
                      '${d.year} 年第 ${i + 1} 天 · $m 分钟 · '
                      '摘录约 ${s.dayQuotes[d] ?? 0} 条'
                      '${m > 0 && m >= gd ? ' · 已打卡' : ''}',
                    );
                  },
                ),
                const SizedBox(height: 12),
                _monthCard(cs, tokens, s),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _donutCard(cs, tokens, s)),
                    const SizedBox(width: 10),
                    Expanded(child: _hoursCard(cs, tokens, s)),
                  ],
                ),
                const SizedBox(height: 12),
                _moneyRow(cs, tokens, s),
                const SizedBox(height: 12),
                // ⑦ 按书累计时长（工单20261001轮2）：点行复用书籍资料页
                // /read/info/:id（其「累计时长→计时明细」链现成），不另建单书统计页。
                ReadStatBooksTimeCard(
                  rows: ReadStatBookMinute.rowsOf(
                    s.books,
                    s.minutesByBook,
                    s.quotesByBook,
                  ),
                  onOpen: (id) => context.push('/read/info/$id'),
                ),
                const SizedBox(height: 12),
                _speedCard(cs, tokens, s),
                const SizedBox(height: 12),
                _goalCard(cs, tokens, s, w),
              ],
            ),
    );
  }

  Widget _panel(
    ColorScheme cs,
    ThemeTokens tokens,
    List<int> years,
    StatData s,
  ) {
    return Container(
      key: const ValueKey('rs-panel'),
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: _deco(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final y in years)
                _chip(
                  cs,
                  tokens,
                  'rs-y-$y',
                  '$y',
                  y == _year,
                  () => setState(() => _year = y),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(
                cs,
                tokens,
                'rs-m-0',
                '全年',
                _month == 0,
                () => setState(() => _month = 0),
              ),
              for (var m = 1; m <= 12; m++)
                _chip(
                  cs,
                  tokens,
                  'rs-m-$m',
                  '$m月',
                  _month == m,
                  () => setState(() => _month = m),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '度量',
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 6),
              for (final (k, t) in const [
                ('min', '时长'),
                ('q', '摘录'),
                ('day', '天数'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _chip(
                    cs,
                    tokens,
                    'rs-met-$k',
                    t,
                    _metric == k,
                    () => setState(() => _metric = k),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '构成',
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 6),
              for (final (k, t) in const [
                ('tag', '标签'),
                ('src', '来源'),
                ('st', '分区'),
                ('grp', '分组'),
                ('rate', '评分'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _chip(
                    cs,
                    tokens,
                    'rs-dim-$k',
                    t,
                    _dim == k,
                    () => setState(() => _dim = k),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(
    ColorScheme cs,
    ThemeTokens tokens,
    String key,
    String label,
    bool on,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      key: ValueKey(key),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: on
              ? tokens.accent.withValues(alpha: .12)
              : cs.surfaceContainerHighest,
          border: Border.all(
            color: on ? tokens.accent : cs.outlineVariant.withValues(alpha: .5),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: on ? tokens.accent : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  BoxDecoration _deco(ColorScheme cs) => readStatCardDeco(cs);

  Widget _fourCards(ColorScheme cs, StatData s, WorkbenchData? w) {
    final days = _rangeDays(s.year, _month);
    final tot = days.fold<int>(0, (t, d) => t + (s.dayMinutes[d] ?? 0));
    final dayCount = days.where((d) => (s.dayMinutes[d] ?? 0) > 0).length;
    final qn = days.fold<int>(0, (t, d) => t + (s.dayQuotes[d] ?? 0));
    final today = w?.minutesToday ?? 0;
    final week = w?.minutesWeek ?? 0;
    final gDay = w?.goalDay ?? 30;
    final gWeek = w?.goalWeek ?? 210;
    // 原型 4941-4944：四卡副行带「已达成 / 差 X 分钟 / 达成 N%」后缀。
    final items = [
      (
        '今天',
        bsFmt(today),
        '目标 $gDay′ · '
            '${today >= gDay ? '已达成' : '差 ${gDay - today} 分钟'}',
      ),
      (
        '本周',
        bsFmt(week),
        '目标 ${(gWeek / 60).round()}h · '
            '${week >= gWeek ? '已达成' : '达成 ${(week / gWeek * 100).round()}%'}',
      ),
      (
        '${s.year}${_month == 0 ? ' 全年' : ' · $_month月'}',
        bsFmt(tot),
        '$dayCount 天在读 · 摘录约 $qn 条',
      ),
      (
        '连续',
        '${w?.streak ?? 0} 天',
        '在读 ${s.readingNow} 本 · 今年读完 ${s.doneYear} / ${w?.goalBooks ?? 50} 本',
      ),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.6,
      children: [
        for (final (t, v, sub) in items)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: _deco(cs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  t,
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
                Text(
                  v,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// U4：热力卡右下汇总（原 `_heatCard` 内算法逐字搬出，口径＝所选范围日账分钟）。
  String _heatSummary(StatData s) {
    final range = _rangeDays(s.year, _month);
    final tot = range.fold<int>(0, (t, d) => t + (s.dayMinutes[d] ?? 0));
    final days = range.where((d) => (s.dayMinutes[d] ?? 0) > 0).length;
    return '${(tot / 60).round()} 小时 · $days 天在读';
  }

  Widget _monthCard(ColorScheme cs, ThemeTokens tokens, StatData s) {
    final first = DateTime(s.year);
    // 原型 4962-4968：度量＝摘录时柱值切「条」，其余按小时。
    final byQ = _metric == 'q';
    final byM = List<int>.filled(12, 0);
    for (var i = 0; i < 366; i++) {
      final d = first.add(Duration(days: i));
      if (d.year != s.year) break;
      byM[d.month - 1] += byQ
          ? (s.dayQuotes[d] ?? 0)
          : (s.dayMinutes[d] ?? 0);
    }
    final mx = byM.fold<int>(1, max);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _deco(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '月度分布与读完本数',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '${s.year} · ${byQ ? '条' : '小时'}',
                style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 96,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var m = 0; m < 12; m++)
                  Expanded(
                    child: GestureDetector(
                      key: ValueKey('rs-bar-$m'),
                      onTap: () =>
                          setState(() => _month = _month == m + 1 ? 0 : m + 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              byQ ? '${byM[m]}' : '${(byM[m] / 60).round()}',
                              style: TextStyle(
                                fontSize: 7.5,
                                color: _month == m + 1
                                    ? tokens.accent
                                    : cs.onSurfaceVariant,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Container(
                              height: max(3, byM[m] / mx * 70),
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(3),
                                ),
                                gradient:
                                    _month == m + 1 ||
                                        _month == 0 &&
                                            m == DateTime.now().month - 1
                                    ? LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          tokens.accent,
                                          tokens.accentLight,
                                        ],
                                      )
                                    : null,
                                color:
                                    _month == m + 1 ||
                                        _month == 0 &&
                                            m == DateTime.now().month - 1
                                    ? null
                                    : cs.surfaceContainerHighest,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (var m = 0; m < 12; m++)
                Expanded(
                  child: Text(
                    '${m + 1}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 8.5,
                      color: _month == m + 1
                          ? tokens.accent
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _dimKey(Book b) => switch (_dim) {
    'src' => b.source?.isNotEmpty == true ? b.source! : '未标注',
    'st' => b.state,
    'grp' => b.grp?.isNotEmpty == true ? b.grp! : '未分组',
    'rate' => b.rating > 0 ? '${b.rating} 分' : '未评分',
    _ => b.tags.isNotEmpty ? b.tags.first : '其他',
  };

  Widget _donutCard(ColorScheme cs, ThemeTokens tokens, StatData s) {
    final agg = <String, int>{};
    for (final b in s.books) {
      final k = _dimKey(b);
      agg[k] = (agg[k] ?? 0) + (s.minutesByBook[b.id] ?? 0);
    }
    final entries = agg.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (t, e) => t + e.value);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _deco(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${switch (_dim) {
              'src' => '来源',
              'st' => '分区',
              'grp' => '分组',
              'rate' => '评分',
              _ => '标签',
            }}占比',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 70,
                height: 70,
                child: CustomPaint(
                  painter: ReadStatDonutPainter(
                    fracs: [
                      for (final e in entries) total == 0 ? 0 : e.value / total,
                    ],
                    colors: [
                      for (var i = 0; i < entries.length; i++)
                        _pal[i % _pal.length],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, e) in entries.take(4).indexed)
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _pal[i % _pal.length],
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              e.key,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Text(
                            total == 0
                                ? '0%'
                                : '${(e.value / total * 100).round()}%',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _hoursCard(ColorScheme cs, ThemeTokens tokens, StatData s) {
    final mx = s.hours.fold<int>(1, max);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _deco(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '一天里什么时候读',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 70,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var h = 0; h < 24; h++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: .5),
                      child: Container(
                        key: ValueKey('rs-hour-$h'),
                        height: max(2, s.hours[h] / mx * 66),
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(2),
                          ),
                          color: tokens.accent.withValues(alpha: .7),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final t in const ['0', '6', '12', '18', '23'])
                Text(
                  t,
                  style: TextStyle(fontSize: 8.5, color: cs.onSurfaceVariant),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _speedCard(ColorScheme cs, ThemeTokens tokens, StatData s) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _deco(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '阅读速度分布',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '分钟 / 页',
                style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (s.speed.isEmpty)
            Text(
              '还没有计时的书',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            )
          else
            for (final (i, e) in s.speed.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  key: ValueKey('rs-speed-$i'),
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(
                        e.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          minHeight: 7,
                          value: min(1, e.minPerPage / 10),
                          backgroundColor: cs.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 62,
                      child: Text(
                        '${e.minPerPage.toStringAsFixed(1)} 分/页',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _moneyRow(ColorScheme cs, ThemeTokens tokens, StatData s) {
    final avg = s.rdMin > 0 ? (s.words / s.rdMin).round() : 0;
    return Row(
      children: [
        Expanded(
          child: Container(
            key: const ValueKey('rs-fee'),
            padding: const EdgeInsets.all(14),
            decoration: _deco(cs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '购书支出',
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
                Text(
                  '¥${s.fee.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${s.paid} 本付费 · 已自动生成记账流水（L4）',
                  style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant),
                ),
                // 原型 5501「查看账本」= navTo('p-finance')：真实跳记账主页。
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: GestureDetector(
                    key: const ValueKey('rs-fee-book'),
                    onTap: () => context.go('/ledger'),
                    child: Text(
                      '看账本',
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
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            key: const ValueKey('rs-words'),
            padding: const EdgeInsets.all(14),
            decoration: _deco(cs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '完读书籍字数',
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
                Text(
                  '${(s.words / 10000).toStringAsFixed(1)} 万',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '按页数折算 · 均速 $avg 字/分钟',
                  style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: GestureDetector(
                    key: const ValueKey('rs-words-year'),
                    onTap: () => openYearBooklist(context, ref),
                    child: Text(
                      '年度书单',
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
          ),
        ),
      ],
    );
  }

  Widget _goalCard(
    ColorScheme cs,
    ThemeTokens tokens,
    StatData s,
    WorkbenchData? w,
  ) {
    final gBooks = w?.goalBooks ?? 50;
    final gDay = w?.goalDay ?? 30;
    final gWeek = w?.goalWeek ?? 210;
    final gWeekDays = w?.goalWeekDays ?? 5;
    final gMonthQ = w?.goalMonthQuotes ?? 20;
    final doneAllY = s.year == DateTime.now().year ? s.doneYear : s.doneYear;
    final spanDays = DateTime.now().year == s.year
        ? max(1, DateTime.now().difference(DateTime(s.year)).inDays)
        : 365;
    final rate = doneAllY / spanDays * 365;
    final rows = <(String, String, double)>[
      ('今年读完', '${s.doneYear} / $gBooks 本', s.doneYear / max(1, gBooks)),
      (
        '每日时长',
        '${w?.minutesToday ?? 0} / $gDay 分钟',
        (w?.minutesToday ?? 0) / max(1, gDay),
      ),
      (
        '本周时长',
        // 原型 4987：'X.X / Y 小时'（小时一位小数）。
        '${((w?.minutesWeek ?? 0) / 60 * 10).round() / 10} / '
        '${(gWeek / 60).round()} 小时',
        (w?.minutesWeek ?? 0) / max(1, gWeek),
      ),
      (
        '每周读书',
        '${w?.weekDays ?? 0} / $gWeekDays 天',
        (w?.weekDays ?? 0) / max(1, gWeekDays),
      ),
      (
        '本月摘录',
        '${w?.monthQuotes ?? 0} / $gMonthQ 条',
        (w?.monthQuotes ?? 0) / max(1, gMonthQ),
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _deco(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '目标与预测',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          for (final (t, v, frac) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                key: ValueKey('rs-goal-$t'),
                children: [
                  SizedBox(
                    width: 68,
                    child: Text(
                      t,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        minHeight: 7,
                        value: min(1, frac),
                        backgroundColor: cs.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 118,
                    child: Text(
                      v,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              // 原型 4991：预测补「差 X 本，每周需多读 1 本」后半句。
              '全年折算 ${rate.toStringAsFixed(1)} 本 → '
              '${rate >= gBooks ? '年度目标可达成' : '差 ${(gBooks - rate).toStringAsFixed(1)} 本，每周需多读 1 本'}',
              style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              // 原型 4992：提醒时刻行（dailyQ 关＝只在周报体现）。
              _remindOn
                  ? '未达每日目标时将于 ${_hhmm(_remindMin)} 提醒（免打扰时段除外）'
                  : '当前设置为不提醒，只在周报里体现',
              style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '阅读时长自动写入时间账本「阅读」分类（L4），并计入周报与目标进度（L7）。',
              style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton(
                key: const ValueKey('rs-weekly'),
                onPressed: () => readToast(
                  context,
                  // 原型 926 逐字格式的真实数据版。
                  '周报已生成：阅读 ${bsFmt(w?.minutesWeek ?? 0)} · '
                  '新增摘录 ${w?.weekQuotes ?? 0} 条 · 已联动 L4/L7',
                ),
                child: const Text('生成周报', style: TextStyle(fontSize: 11.5)),
              ),
              const SizedBox(width: 8),
              // 轮4：补年度总结报告入口（原型 bsYearReport）。
              OutlinedButton(
                key: const ValueKey('rs-year'),
                onPressed: () => _yearReport(cs, s, w),
                child: const Text('年度总结报告', style: TextStyle(fontSize: 11.5)),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                key: const ValueKey('rs-goal-edit'),
                onPressed: () => showGoalSheet(context, ref),
                child: const Text('调整年度目标', style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 年度总结报告弹层（真实年度数据汇总 · 原型 sheetYearReport）。
  void _yearReport(ColorScheme cs, StatData s, WorkbenchData? w) {
    final top = s.minutesByBook.entries.isEmpty
        ? null
        : s.minutesByBook.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final titleOf = {for (final b in s.books) b.id: b.title};
    final lines = <String>[
      '全年阅读 ${bsFmt(s.dayMinutes.values.fold(0, (t, m) => t + m))} · '
          '今年有记录 ${s.dayMinutes.length} 天',
      '读完 ${s.doneYear} 本 · 在读 ${s.readingNow} 本 · 收录 ${s.books.length} 本',
      '新增摘录 ${s.quotesYear} 条',
      if (top != null && top.value > 0 && titleOf[top.key] != null)
        '花时间最多：《${titleOf[top.key]}》 ${bsFmt(top.value)}',
      '购书支出 ¥${s.fee.toStringAsFixed(0)} · 读完书字数 ${s.rdMin >= 10000 ? '${(s.words / 10000).toStringAsFixed(1)} 万字' : '${s.words} 字'}',
      '目标：年度 ${w?.goalBooks ?? 50} 本 · 日均 ${w?.goalDay ?? 30} 分钟（调整请回目标卡）',
    ];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bc) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${s.year} 年度总结报告',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  GestureDetector(
                    key: const ValueKey('yr-close'),
                    onTap: () => Navigator.of(bc).pop(),
                    child: Text(
                      '关闭',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < lines.length; i++)
                Padding(
                  key: ValueKey('yr-line-$i'),
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    '· ${lines[i]}',
                    style: const TextStyle(fontSize: 12, height: 1.6),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
