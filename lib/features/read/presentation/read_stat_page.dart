import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/book.dart';
import '../domain/shelf_query.dart' show sessionAggByBook;
import 'read_providers.dart';
import 'read_sheets.dart';

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
  static const _heat = [
    Color(0xFFE2E8F0),
    Color(0xFFC7D2FE),
    Color(0xFFA5B4FC),
    Color(0xFF818CF8),
    Color(0xFF6366F1),
  ];

  late int _year = DateTime.now().year;
  int _month = 0; // 0＝全年
  String _metric = 'min'; // min / q / day
  String _dim = 'tag'; // tag/src/st/grp/rate（原型 rsDim）
  bool _ctlOpen = false;

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
      appBar: AppBar(
        title: const Text('阅读统计'),
        actions: [
          TextButton(
            key: const ValueKey('rs-ctl'),
            onPressed: () => setState(() => _ctlOpen = !_ctlOpen),
            child: Text(
              '范围 ▾',
              style: TextStyle(fontSize: 12, color: tokens.accent),
            ),
          ),
        ],
      ),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                if (_ctlOpen) _panel(cs, tokens, years, s),
                const SizedBox(height: 8),
                _fourCards(cs, s, w),
                const SizedBox(height: 12),
                _heatCard(cs, tokens, s),
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
                _speedCard(cs, tokens, s),
                const SizedBox(height: 12),
                _moneyRow(cs, tokens, s),
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

  BoxDecoration _deco(ColorScheme cs) => BoxDecoration(
    color: cs.surfaceContainerLow,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
  );

  Widget _fourCards(ColorScheme cs, StatData s, WorkbenchData? w) {
    final first = DateTime(s.year);
    final days = _month == 0
        ? List.generate(
            DateTime(s.year, 12, 31).difference(first).inDays + 1,
            (i) => first.add(Duration(days: i)),
          )
        : List.generate(
            DateTime(
              s.year,
              _month + 1 == 13 ? 1 : _month + 1,
              _month + 1 == 13 ? 1 : 1,
            ).difference(DateTime(s.year, _month)).inDays,
            (i) => DateTime(s.year, _month).add(Duration(days: i)),
          );
    final tot = days.fold<int>(0, (t, d) => t + (s.dayMinutes[d] ?? 0));
    final dayCount = days.where((d) => (s.dayMinutes[d] ?? 0) > 0).length;
    final items = [
      ('今天', '${w?.minutesToday ?? 0}′', '目标 ${w?.goalDay ?? 30}′'),
      ('本周', bsFmt(w?.minutesWeek ?? 0), '目标 ${bsFmt(w?.goalWeek ?? 210)}'),
      (
        '${s.year}${_month == 0 ? ' 全年' : ' · $_month月'}',
        bsFmt(tot),
        '$dayCount 天在读 · 摘录 ${s.quotesYear}${_month == 0 ? '' : '（全年）'} 条',
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

  Widget _heatCard(ColorScheme cs, ThemeTokens tokens, StatData s) {
    final first = DateTime(s.year);
    final n = DateTime(s.year, 12, 31).difference(first).inDays + 1;
    var mx = 1;
    for (var i = 0; i < n; i++) {
      mx = max(mx, _val(first.add(Duration(days: i)), s).round());
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _deco(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${s.year} 年阅读热力图 · ${_metName()}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Text(
                '每格＝一天',
                style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            key: const ValueKey('rs-heat'),
            // mainAxisExtent=10 + 行距 4 = 每行 14，与外层高度式一致，
            // 保证 31 行全部落在网格视口内（默认 childAspectRatio 会撑出视口导致尾行不挂载）。
            height: (n / 12).ceil() * 14,
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 12,
                mainAxisExtent: 10,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              physics: const NeverScrollableScrollPhysics(),
              itemCount: n,
              itemBuilder: (context, i) {
                final d = first.add(Duration(days: i));
                final v = _val(d, s).round();
                final lvl = v == 0
                    ? 0
                    : v > mx * .7
                    ? 4
                    : v > mx * .45
                    ? 3
                    : v > mx * .22
                    ? 2
                    : 1;
                final inM = _month == 0 || d.month == _month;
                return Container(
                  key: ValueKey('rs-heat-$i'),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: _heat[lvl].withValues(alpha: inM ? 1 : .34),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '少',
                style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
              for (final c in _heat)
                Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              const Spacer(),
              Text(
                '${(s.dayMinutes.values.fold<int>(0, (t, v) => t + v) / 60).round()} 小时在读',
                style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _monthCard(ColorScheme cs, ThemeTokens tokens, StatData s) {
    final first = DateTime(s.year);
    final byM = List<int>.filled(12, 0);
    for (var i = 0; i < 366; i++) {
      final d = first.add(Duration(days: i));
      if (d.year != s.year) break;
      byM[d.month - 1] += s.dayMinutes[d] ?? 0;
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
                '月度分布（小时）',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '${s.year}',
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
                              '${(byM[m] / 60).round()}',
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
                  painter: _DonutPainter(
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
                GestureDetector(
                  onTap: () => context.push('/read/lists'),
                  child: Text(
                    '按页数折算 · 年度书单 ›',
                    style: TextStyle(fontSize: 9.5, color: tokens.accent),
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
        '${bsFmt(w?.minutesWeek ?? 0)} / ${bsFmt(gWeek)}',
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
            '目标与预测（L7 五路）',
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
              '全年折算 ${rate.toStringAsFixed(1)} 本 → '
              '${rate >= gBooks ? '年度目标可达成' : '差 ${(gBooks - rate).toStringAsFixed(1)} 本'}',
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
                  '周报：阅读 ${bsFmt(w?.minutesWeek ?? 0)} · 新增摘录 ${w?.weekQuotes ?? 0} 条',
                ),
                child: const Text('生成周报', style: TextStyle(fontSize: 11.5)),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                key: const ValueKey('rs-goal-edit'),
                onPressed: () => showGoalSheet(context, ref),
                child: const Text('调整目标', style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.fracs, required this.colors});
  final List<double> fracs;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 6;
    final total = fracs.fold<double>(0, (t, f) => t + f);
    if (total <= 0) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..color = const Color(0xFFE2E8F0),
      );
      return;
    }
    var start = -pi / 2;
    for (var i = 0; i < fracs.length && fracs[i] > 0; i++) {
      final sweep = fracs[i] / total * 2 * pi;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..color = colors[i],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.fracs.join() != fracs.join();
}
