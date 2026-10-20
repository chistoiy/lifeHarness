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
part 'read_stat_page_cards.dart';

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
  /// F3-3：构成环分类色由主题 accent 派生（等距色相旋转 6 档；原固定靛蓝系色板退役）。
  List<Color> _statPal(ThemeTokens t) {
    final h = HSLColor.fromColor(t.accent);
    return [
      for (var i = 0; i < 6; i++)
        h
            .withHue((h.hue + i * 40) % 360)
            .withLightness(
              (h.lightness + (i.isEven ? 0 : .04)).clamp(0.0, 1.0),
            )
            .toColor(),
    ];
  }
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

}
