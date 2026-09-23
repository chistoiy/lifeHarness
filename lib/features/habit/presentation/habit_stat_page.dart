import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';

import '../domain/habit.dart';
import '../domain/habit_calc.dart';
import '../domain/habit_entry.dart';
import 'habit_auto_sheets.dart';
import 'habit_providers.dart';
import 'habit_sheets.dart';
import 'widgets/habit_kit.dart';

/// 习惯全局统计页（原型 p-habitStat · 计划 §3 `/habit-stat` · 批4）。
///
/// 口径：全部由 habit_entries 真源即时聚合（§2.2 不建物化表）；
/// 日均/达成率分母走 habitEffDays 截断（口径开关 spanFromStart / rateBase）。

/// 统计范围（会话内选择；null=全部）。
final habitScopeProvider = StateProvider<List<String>?>((ref) => null);

enum HeatMode { ok, value, slot }

const kBkNames = ['凌晨', '上午', '下午', '晚上'];
const kBkRanges = ['0-5 点', '6-11 点', '12-17 点', '18-23 点'];

int _bkIdx(int hour) => hour <= 5 ? 0 : hour <= 11 ? 1 : hour <= 17 ? 2 : 3;

/// 周期 → (起, 止, 文案)。off=0 当期，off>0 往前数。
(DateTime, DateTime, String) _period(
  String dim,
  int off,
  DateTime today,
) {
  switch (dim) {
    case 'w':
      final mon = dayStart(today).subtract(Duration(days: today.weekday - 1));
      final from = mon.subtract(Duration(days: 7 * off));
      return (from, from.add(const Duration(days: 6)), off == 0 ? '本周' : '第 $off 周前');
    case 'a':
      final from = DateTime(today.year - off, 1, 1);
      return (
        from,
        DateTime(today.year - off, 12, 31),
        off == 0 ? '本年' : '${today.year - off}年',
      );
    default:
      final m = today.year * 12 + today.month - 1 - off;
      final from = DateTime(m ~/ 12, m % 12 + 1, 1);
      return (
        from,
        DateTime(m ~/ 12, m % 12 + 2, 0),
        off == 0 ? '本月' : '${from.year}年${from.month}月',
      );
  }
}

String _periodAbsTxt(String dim, int off, DateTime today) {
  final (f, _, _) = _period(dim, off, today);
  return switch (dim) {
    'w' => '${f.year} 年第 ${(f.difference(DateTime(f.year, 1, 1)).inDays / 7).floor() + 1} 周',
    'm' => '${f.year}年${f.month}月',
    _ => '${f.year}年',
  };
}

class HabitStatPage extends ConsumerStatefulWidget {
  const HabitStatPage({super.key});

  @override
  ConsumerState<HabitStatPage> createState() => _HabitStatPageState();
}

class _HabitStatPageState extends ConsumerState<HabitStatPage> {
  String _dim = 'w';
  int _off = 0;
  bool _more = false;
  bool _scopeOpen = false;
  bool _wheelOpen = false;
  HeatMode _heat = HeatMode.ok;

  void _pick(String dim) => setState(() {
    _dim = dim;
    _off = 0;
  });

  void _step(int d) {
    final maxOff = _dim == 'w' ? 160 : _dim == 'm' ? 40 : 8;
    final o = _off - d;
    if (o < 0) {
      habitToast(context, '已是当前周期');
      return;
    }
    if (o > maxOff) {
      habitToast(context, '超出可查范围');
      return;
    }
    setState(() => _off = o);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final d = ref.watch(habitDataProvider).valueOrNull;
    if (d == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final today = dayStart(DateTime.now());
    final scope = ref.watch(habitScopeProvider);
    final book = (scope == null
            ? d.book
            : d.book.where((h) => scope.contains(h.id)).toList());
    final posBook = book.where((h) => h.isPos).toList();
    final negBook = book.where((h) => h.isNeg).toList();
    final (from, to, baseTxt) = _period(_dim, _off, today);
    final (pFrom, pTo, _) = _period(_dim, _off + 1, today);
    final (yFrom, yTo, _) = _period(
      _dim,
      _off + (_dim == 'a' ? 1 : _dim == 'm' ? 12 : 52),
      today,
    );

    // ---- 聚合（真源即时算）----
    (int cnt, int rec, double val, int days, int due) agg(
      DateTime f,
      DateTime t,
    ) {
      var cnt = 0, rec = 0, days = 0, due = 0;
      var val = 0.0;
      for (final h in posBook) {
        final e = d.of(h.id);
        cnt += habitCountOkInRange(h, e, f, t);
        final v = habitTotalValue(h, e, f, t);
        if (v != null) val += v;
        rec += e.entries
            .where(
              (x) =>
                  x.key.compareTo(dayKey(f)) >= 0 &&
                  x.key.compareTo(dayKey(t)) <= 0 &&
                  ((x.value.value ?? 0) > 0 || x.value.subValues.isNotEmpty),
            )
            .length;
        days += habitEffDays(
          h,
          periodDays: habitDueDaysInRange(h, f, t).clamp(1, 99999),
          periodStart: f,
          today: t.isAfter(today) ? today : t,
          spanFromStart: d.spanFromStart,
        );
        due += habitDueDaysInRange(h, f, t);
      }
      return (cnt, rec, val, d.spanFromStart ? days : due, due);
    }

    final A = agg(from, to);
    final P = agg(pFrom, pTo);
    final Y = agg(yFrom, yTo);
    final rate = A.$4 > 0 ? (A.$1 * 100 / A.$4).clamp(0, 100).round() : 0;
    final perDay = A.$4 > 0 ? A.$1 / A.$4 : 0.0;
    final negTrig = negBook.fold<int>(
      0,
      (a, h) =>
          a +
          d
              .of(h.id)
              .entries
              .where(
                (x) =>
                    x.key.compareTo(dayKey(from)) >= 0 &&
                    x.key.compareTo(dayKey(to)) <= 0 &&
                    !x.value.checked,
              )
              .length,
    );
    final subsTxt =
        '${book.length} 个跟踪中习惯（正向 ${posBook.length} · 负向 ${negBook.length}）'
        ' · 正向打卡 ${A.$1} 次 · 数值记录 ${A.$2} 条 · 负向触发 $negTrig 次';

    // ---- 分享长图快照（原型 hbShareRender/hbShareCopy 口径）----
    HabitShareSnapshot shareSnap() {
      String md(DateTime x) =>
          '${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
      int trig(Habit h) => d
          .of(h.id)
          .entries
          .where(
            (x) =>
                x.key.compareTo(dayKey(from)) >= 0 &&
                x.key.compareTo(dayKey(to)) <= 0 &&
                !x.value.checked,
          )
          .length;
      final top = [...posBook]
        ..sort(
          (a, b) =>
              habitCountOkInRange(b, d.of(b.id), from, to) -
              habitCountOkInRange(a, d.of(a.id), from, to),
        );
      return HabitShareSnapshot(
        title: '$baseTxt打卡报告',
        rangeTxt: '${md(from)} ~ ${md(to)} · 共 ${book.length} 个习惯',
        cnt: A.$1,
        rate: rate,
        rec: A.$2,
        pos: [
          for (final h in top.take(5))
            HabitShareRow(
              icon: h.icon,
              name: h.name,
              cnt: habitCountOkInRange(h, d.of(h.id), from, to),
              right: h.isGroup
                  ? '按子项'
                  : h.hasVal
                  ? '${HabitSubChips.n(habitTotalValue(h, d.of(h.id), from, to) ?? 0)} ${h.unit ?? ''}'.trim()
                  : '${habitRate(h, entries: d.of(h.id), from: from, to: to, spanFromStart: d.spanFromStart, rateByTotalDays: d.rateByTotalDays)}%',
            ),
        ],
        neg: [
          for (final h in negBook)
            HabitShareRow(
              icon: h.icon,
              name: h.name,
              cnt: trig(h),
              right: '守住 ${7 - d.of(h.id).entries.where((x) {
                final k = parseDay(x.key);
                return !k.isBefore(today.subtract(const Duration(days: 6))) &&
                    !k.isAfter(today) &&
                    !x.value.checked;
              }).length}/7 天',
            ),
        ],
        habitCntLines: [
          for (final h in posBook)
            '${h.name}：${habitCountOkInRange(h, d.of(h.id), from, to)} 次',
        ],
      );
    }

    String dlt(num cur, num prev, bool betterUp) {
      final diff = cur - prev;
      final p = prev == 0 ? (diff == 0 ? 0 : 100) : (diff * 100 / prev).round();
      if (p == 0) return '持平';
      final good = betterUp ? diff > 0 : diff < 0;
      return '${diff > 0 ? '+' : ''}$p%${good ? ' ↑' : ' ↓'}';
    }

    Color dltColor(String t, bool betterUp) =>
        t == '持平'
            ? scheme.onSurfaceVariant
            : (t.contains('↑') == betterUp ? HK.ok500 : HK.rose500);

    // ---- 时段样本 ----
    final bk = [0, 0, 0, 0];
    final wd = [0, 0, 0, 0, 0, 0, 0];
    var hrSum = 0, hrN = 0, bfN = 0;
    for (final h in book) {
      for (final x in d.of(h.id).entries) {
        if (x.key.compareTo(dayKey(from)) < 0 || x.key.compareTo(dayKey(to)) > 0) {
          continue;
        }
        if (!habitOkAt(h, x.value)) continue;
        final at = x.value.checkAt;
        if (at == null || at.length < 5) continue;
        final hr = int.tryParse(at.substring(0, 2)) ?? 0;
        bk[_bkIdx(hr)]++;
        wd[parseDay(x.key).weekday - 1]++;
        hrSum += hr;
        hrN++;
        if (x.value.backfilled) bfN++;
      }
    }
    final avgClock = hrN > 0
        ? '${(hrSum / hrN).floor().toString().padLeft(2, '0')}:${((hrSum / hrN % 1 * 60) / 15).round() * 15 % 60}'
        : '—';

    // ---- 热力图 17 周 ----
    const W = 17;
    final lead = today.weekday - 1;
    List<List<int?>> heatCells() {
      final cells = <List<int?>>[];
      for (var w = 0; w < W; w++) {
        final col = <int?>[];
        for (var dd = 0; dd < 7; dd++) {
          final back = lead - dd + (W - 1 - w) * 7;
          if (back < 0 || back > 140) {
            col.add(null);
            continue;
          }
          final k = dayKey(today.subtract(Duration(days: back)));
          if (_heat == HeatMode.ok) {
            col.add(
              book.where((h) => habitOkAt(h, d.of(h.id)[k])).length,
            );
          } else if (_heat == HeatMode.value) {
            var sum = 0.0, mx = 0.0;
            for (final h in book) {
              final e = d.of(h.id)[k];
              if (e == null || !habitOkAt(h, e)) continue;
              final v = e.value ?? e.subValues.values.fold<double>(0, (a, b) => a + b);
              sum += v;
              if (v > mx) mx = v;
            }
            col.add(mx <= 0 ? (sum > 0 ? 4 : 0) : min(4, (sum / mx * 4).round()));
          } else {
            final b4 = [0, 0, 0, 0];
            for (final h in book) {
              final e = d.of(h.id)[k];
              if (e == null || !habitOkAt(h, e) || e.checkAt == null) continue;
              b4[_bkIdx(int.tryParse(e.checkAt!.substring(0, 2)) ?? 0)]++;
            }
            col.add(b4.every((x) => x == 0) ? 0 : b4.indexOf(b4.reduce(max)));
          }
        }
        cells.add(col);
      }
      return cells;
    }

    final heat = heatCells();
    final wallTop =
        book.where((h) => h.best > 0).toList()
          ..sort((a, b) => b.best - a.best);
    final wall5 = wallTop.take(5).toList();

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          children: [
            const Text('习惯统计', style: TextStyle(fontSize: 16)),
            Text(
              '周 · 月 · 年 · 时段 · 热力 · 排行',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        // 原型 renderHdrActs(p-habitStat)：分享长图 + 打卡设置。
        actions: [
          IconButton(
            key: const ValueKey('hs-share'),
            tooltip: '分享长图',
            icon: Icon(HIcons.resolve('doc'), size: 20),
            onPressed: () => showHabitShareSheet(context, shareSnap()),
          ),
          IconButton(
            key: const ValueKey('hs-set'),
            tooltip: '打卡设置',
            icon: Icon(HIcons.resolve('cog'), size: 20),
            onPressed: () => context.push('/habit-set'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // 周期三档 + 口径徽标
          Row(
            children: [
              for (final (k, lab) in const [
                ('w', '本周'),
                ('m', '本月'),
                ('a', '本年'),
              ]) ...[
                if (k != 'w') const SizedBox(width: 8),
                GestureDetector(
                  key: ValueKey('hs-dim-$k'),
                  onTap: () => _pick(k),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: _dim == k
                          ? tokens.accent
                          : scheme.onSurface.withValues(alpha: .05),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      lab,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: _dim == k ? Colors.white : scheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Container(
                key: const ValueKey('hs-base'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  d.spanFromStart ? '按开始跟踪日' : '按周期天数',
                  style: TextStyle(
                    fontSize: 9,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 周期条
          Container(
            decoration: hCardDeco(context),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                _navBtn(context, Icons.chevron_left, 'hs-prev', () => _step(-1)),
                Expanded(
                  child: GestureDetector(
                    key: const ValueKey('hs-period'),
                    onTap: () => setState(() => _wheelOpen = !_wheelOpen),
                    child: Text(
                      textAlign: TextAlign.center,
                      '$baseTxt${_off == 0 ? '' : ' · ${_periodAbsTxt(_dim, _off, today)}'}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                Opacity(
                  opacity: _off == 0 ? .3 : 1,
                  child: _navBtn(context, Icons.chevron_right, 'hs-next', () => _step(1)),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _off == 0
                        ? Colors.white.withValues(alpha: .2)
                        : HK.amber500.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _off == 0 ? '当前' : '第 $_off 期前',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: _off == 0 ? scheme.onSurfaceVariant : HK.amber600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 就地内嵌滚轮
          if (_wheelOpen) _wheel(today),
          const SizedBox(height: 8),
          // 统计范围
          Container(
            decoration: hCardDeco(context),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  key: const ValueKey('hs-scope'),
                  onTap: () => setState(() => _scopeOpen = !_scopeOpen),
                  child: Row(
                    children: [
                      Text(
                        '统计范围',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          scope == null
                              ? '全部习惯'
                              : '已选 ${scope.length} 个',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Icon(
                        _scopeOpen
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
                if (_scopeOpen) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (k, lab) in const [
                        ('all', '全选'),
                        ('pos', '仅正向'),
                        ('neg', '仅负向'),
                      ])
                        GestureDetector(
                          key: ValueKey('hs-scope-$k'),
                          onTap: () => ref
                              .read(habitScopeProvider.notifier)
                              .state = k == 'all'
                              ? null
                              : d.book
                                    .where(
                                      (h) => k == 'pos' ? h.isPos : h.isNeg,
                                    )
                                    .map((h) => h.id)
                                    .toList(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.onSurface.withValues(alpha: .05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              lab,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final h in d.book)
                        GestureDetector(
                          key: ValueKey('hs-scope-h-${h.name}'),
                          onTap: () {
                            final cur =
                                (ref.read(habitScopeProvider) ??
                                        d.book.map((x) => x.id).toList())
                                    .toList();
                            setState(
                              () => cur.contains(h.id)
                                  ? cur.remove(h.id)
                                  : cur.add(h.id),
                            );
                            ref
                                .read(habitScopeProvider.notifier)
                                .state = cur.length == d.book.length
                                ? null
                                : cur;
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: (scope == null || scope.contains(h.id))
                                  ? tokens.accent
                                  : scheme.onSurface.withValues(alpha: .05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              h.name,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: (scope == null || scope.contains(h.id))
                                    ? Colors.white
                                    : scheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '未选中的习惯不参与次数、记录量与时段分析',
                    style: TextStyle(
                      fontSize: 9.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          // hero 渐变卡
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: tokens.gradient,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          RingProgress(
                            value: rate / 100,
                            size: 52,
                            stroke: 5,
                            color: Colors.white,
                            bg: Colors.white.withValues(alpha: .26),
                          ),
                          Text(
                            '$rate%',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$baseTxt总达成率',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subsTxt,
                            style: TextStyle(
                              fontSize: 10.5,
                              height: 1.5,
                              color: Colors.white.withValues(alpha: .88),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _heroCard('${A.$1}', '打卡次数'),
                    const SizedBox(width: 8),
                    _heroCard('${A.$2}', '数值记录'),
                    const SizedBox(width: 8),
                    _heroCard(
                      perDay == 0 ? '0' : perDay.toStringAsFixed(1),
                      '日均打卡',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 同期对比
          Container(
            decoration: hCardDeco(context),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _T('同期对比'),
                    Expanded(
                      child: Text(
                        textAlign: TextAlign.right,
                        _off == 0
                            ? '环比=上一期 · 同比=去年同期'
                            : '对比：${_periodAbsTxt(_dim, _off + 1, today)} / ${_periodAbsTxt(_dim, _off + (_dim == 'a' ? 1 : _dim == 'm' ? 12 : 52), today)}',
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _cmp(
                      '打卡次数',
                      '${A.$1}',
                      dlt(A.$1, P.$1, true),
                      dlt(A.$1, Y.$1, true),
                    ),
                    const SizedBox(width: 8),
                    _cmp(
                      '数值记录',
                      '${A.$2}',
                      dlt(A.$2, P.$2, true),
                      dlt(A.$2, Y.$2, true),
                    ),
                    const SizedBox(width: 8),
                    _cmp(
                      '达成率',
                      '$rate%',
                      dlt(rate, P.$4 > 0 ? (P.$1 * 100 / P.$4).round() : 0, true),
                      dlt(rate, Y.$4 > 0 ? (Y.$1 * 100 / Y.$4).round() : 0, true),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 展开更多
          GestureDetector(
            key: const ValueKey('hs-more'),
            onTap: () => setState(() => _more = !_more),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: hCardDeco(context),
              alignment: Alignment.center,
              child: Text(
                _more ? '收起更多分析' : '展开更多分析 · 时段 / 热力 / 分类 / 排行 / 组构成 / 纪录墙',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          if (_more) ...[
            const SizedBox(height: 12),
            _card(
              context,
              '打卡时段分析',
              tip: hrN == 0 ? '' : '样本 $hrN 次 · 平均 $avgClock',
              child: hrN == 0
                  ? Text(
                      '该周期还没有打卡时刻数据',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          () {
                            final top = bk.indexOf(bk.reduce(max));
                            final wmx = wd.indexOf(wd.reduce(max));
                            final wmn = wd.indexOf(wd.reduce(min));
                            return '${kBkNames[top]}最常打卡 · 平均时刻 $avgClock'
                                ' · 周${'一二三四五六日'[wmx]}最稳'
                                ' · 周${'一二三四五六日'[wmn]}最易断'
                                '${bfN > 0 ? ' · 含补记 $bfN 次' : ''}';
                          }(),
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            for (final (i, v) in bk.indexed)
                              Expanded(
                                child: Container(
                                  margin: EdgeInsets.only(right: i == 3 ? 0 : 6),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.onSurface.withValues(
                                      alpha: .05,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        '$v',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        '${kBkNames[i]} ${kBkRanges[i]}',
                                        style: TextStyle(
                                          fontSize: 8,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            _card(
              context,
              '打卡热力图',
              tip: '近 $W 周 · '
                  '${switch (_heat) {
                    HeatMode.ok => '每格为一天达成习惯数',
                    HeatMode.value => '深浅为一天记录量',
                    HeatMode.slot => '颜色为一天主要打卡时段',
                  }}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      for (final (i, lab) in const ['达成数', '记录量', '时段'].indexed)
                        Expanded(
                          child: GestureDetector(
                            key: ValueKey('hs-heat-$i'),
                            onTap: () => setState(
                              () => _heat = HeatMode.values[i],
                            ),
                            child: Container(
                              margin: EdgeInsets.only(right: i == 2 ? 0 : 6),
                              padding: const EdgeInsets.symmetric(
                                vertical: 6,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _heat.index == i
                                    ? tokens.accent
                                    : scheme.onSurface.withValues(alpha: .05),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                lab,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: _heat.index == i
                                      ? Colors.white
                                      : scheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final col in heat)
                          Padding(
                            padding: const EdgeInsets.only(right: 3),
                            child: Column(
                              children: [
                                for (final v in col)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 3),
                                    child: GestureDetector(
                                      onTap: () {},
                                      child: Container(
                                        width: 11,
                                        height: 11,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(3),
                                          color: _heatCellColor(
                                            v,
                                            scheme,
                                            tokens,
                                          ),
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
                  const SizedBox(height: 6),
                  Text(
                    _heat == HeatMode.slot
                        ? '时段：凌晨 / 上午 / 下午 / 晚上 四色'
                        : '少 ▫ ▫ ▫ ■ 多 · 含补记描边',
                    style: TextStyle(
                      fontSize: 9,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _card(
              context,
              '分类构成',
              child: Column(
                children: [
                  for (final c in d.cats)
                      () {
                        final ls = book.where((h) => h.cat == c.name).toList();
                        if (ls.isEmpty) return const SizedBox.shrink();
                        final r =
                            ls.map((h) => habitRate(h, entries: d.of(h.id), from: from, to: to, spanFromStart: d.spanFromStart, rateByTotalDays: d.rateByTotalDays)).reduce((a, b) => a + b) /
                            ls.length;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 48,
                                child: Text(
                                  c.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    minHeight: 6,
                                    value: r / 100,
                                    color: HK.rateText(r.round()),
                                    backgroundColor:
                                        scheme.onSurface.withValues(alpha: .07),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 36,
                                child: Text(
                                  '${r.round()}%',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: r >= 70 ? HK.ok500 : null,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 32,
                                child: Text(
                                  '${ls.length} 个',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }(),
                  if (book.every(
                    (h) => !d.cats.any((c) => c.name == h.cat),
                  ))
                    Text(
                      '暂无分类数据',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _card(
              context,
              '习惯排行',
              tip: '按打卡次数 · 行内含环比 · 负向不参与',
              child: Column(
                children: [
                  ...posBook.asMap().entries.map((en) {
                    final h = en.value;
                    final cnt = habitCountOkInRange(h, d.of(h.id), from, to);
                    final prev = habitCountOkInRange(h, d.of(h.id), pFrom, pTo);
                    final tot = habitTotalValue(h, d.of(h.id), from, to);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 16,
                            child: Text(
                              '${en.key + 1}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              h.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Text(
                            '$cnt 次',
                            style: TextStyle(
                              fontSize: 10,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            dlt(cnt, prev, true),
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: dltColor(dlt(cnt, prev, true), true),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 64,
                            child: Text(
                              textAlign: TextAlign.right,
                              h.isGroup
                                  ? '按子项'
                                  : h.hasVal
                                  ? '${HabitSubChips.n(tot ?? 0)} ${h.unit}'
                                  : '${habitRate(h, entries: d.of(h.id), from: from, to: to, spanFromStart: d.spanFromStart, rateByTotalDays: d.rateByTotalDays)}%',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: HK.brand,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (posBook.isEmpty)
                    Text(
                      '范围内没有正向习惯',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (book.any((h) => h.isGroup)) ...[
              const SizedBox(height: 12),
              _card(
                context,
                '组习惯构成',
                tip: '子项累计量',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final g in book.where((h) => h.isGroup)) ...[
                      Text(
                        '${g.name} · $baseTxt子项构成',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...habitSubTotals(g, d.of(g.id), from, to).entries.map((
                        x,
                      ) {
                        final s = g.subs.firstWhere((e) => e.id == x.key);
                        final mx = habitSubTotals(g, d.of(g.id), from, to)
                            .values
                            .fold<double>(1, (a, b) => b > a ? b : a);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 56,
                                child: Text(
                                  s.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    minHeight: 6,
                                    value: x.value / mx,
                                    backgroundColor:
                                        scheme.onSurface.withValues(alpha: .07),
                                  ),
                                ),
                              ),
                              Text(
                                ' ${HabitSubChips.n(x.value)} ${s.unit}',
                                style: const TextStyle(fontSize: 10.5),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            _card(
              context,
              '负向控制',
              child: Column(
                children: [
                  for (final h in negBook)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              h.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ),
                          Text(
                            '触发 ${d.of(h.id).entries.where((x) => x.key.compareTo(dayKey(from)) >= 0 && x.key.compareTo(dayKey(to)) <= 0 && !x.value.checked).length} 次',
                            style: TextStyle(
                              fontSize: 10,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 56,
                            child: Text(
                              textAlign: TextAlign.right,
                              '未做 ${d.of(h.id).entries.where((x) => x.key.compareTo(dayKey(from)) >= 0 && x.key.compareTo(dayKey(to)) <= 0 && x.value.checked).length} 天',
                              style: const TextStyle(
                                fontSize: 10,
                                color: HK.teal600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (negBook.isEmpty)
                    Text(
                      '没有负向习惯在跟踪',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _card(
              context,
              '连续纪录墙',
              child: Column(
                children: [
                  for (final h in wall5)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            HabitIconTile(
                              iconKey: h.icon,
                              neg: h.isNeg,
                              size: 24,
                              radius: 8,
                              iconSize: 13,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                h.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5),
                              ),
                            ),
                            Text(
                              '${h.best}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: HK.amber500,
                              ),
                            ),
                            Text(
                              ' 天',
                              style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _wheel(DateTime today) {
    final scheme = Theme.of(context).colorScheme;
    final years = [for (var y = today.year - 2; y <= today.year; y++) '$y'];
    return Container(
      key: const ValueKey('hs-wheel'),
      margin: const EdgeInsets.only(top: 8),
      decoration: hCardDeco(context),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _miniWheel(
            years,
            '${_period(_dim, _off, today).$1.year}',
            (v) => _wheelPick(int.parse(v), null),
          ),
          if (_dim != 'a')
            _miniWheel(
              _dim == 'm'
                  ? [for (var m = 1; m <= 12; m++) '$m月']
                  : [for (var w = 1; w <= 53; w++) '第 $w 周'],
              _dim == 'm'
                  ? '${_period(_dim, _off, today).$1.month}月'
                  : '第 ${((_period(_dim, _off, today).$1.difference(DateTime(_period(_dim, _off, today).$1.year, 1, 1)).inDays / 7).floor() + 1)} 周',
              (v) => _wheelPick(
                null,
                int.parse(v.replaceAll(RegExp(r'[^0-9]'), '')),
              ),
            ),
          const SizedBox(width: 8),
          Text(
            _dim == 'a' ? '滚动选年' : _dim == 'm' ? '滚动选年月' : '滚动选年周',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  void _wheelPick(int? year, int? sub) {
    final today = dayStart(DateTime.now());
    final curAbs = switch (_dim) {
      'a' => today.year,
      'm' => today.year * 12 + today.month - 1,
      _ => today.year * 12 + today.month - 1,
    };
    final abs = _dim == 'a'
        ? year!
        : _dim == 'm'
        ? year! * 12 + (sub! - 1)
        : curAbs; // 周维：仅按年滚轮近似回退
    if (abs > curAbs) {
      habitToast(context, '不能选到未来周期');
      return;
    }
    setState(() => _off = curAbs - abs);
  }

  Widget _miniWheel(List<String> items, String init, ValueChanged<String> onPick) {
    final ctrl = FixedExtentScrollController(
      initialItem: max(0, items.indexOf(init)),
    );
    return SizedBox(
      width: 76,
      height: 92,
      child: ListWheelScrollView.useDelegate(
        controller: ctrl,
        itemExtent: 30,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (i) => onPick(items[i]),
        childDelegate: ListWheelChildListDelegate(
          children: [
            for (final it in items)
              Center(
                child: Text(it, style: const TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  Color _heatCellColor(int? v, ColorScheme scheme, ThemeTokens tokens) {
    if (v == null) return Colors.transparent;
    if (_heat == HeatMode.slot) {
      return [
        scheme.onSurface.withValues(alpha: .06),
        const Color(0xFFC4B5FD),
        const Color(0xFF7DD3FC),
        const Color(0xFFFCD34D),
        const Color(0xFF818CF8),
      ][v];
    }
    return [
      scheme.onSurface.withValues(alpha: .06),
      HK.ok400.withValues(alpha: .25),
      HK.ok400.withValues(alpha: .40),
      HK.ok400.withValues(alpha: .60),
      HK.ok500,
    ][min(v, 4)];
  }

  Widget _navBtn(
    BuildContext context,
    IconData icon,
    String key,
    VoidCallback onTap,
  ) => GestureDetector(
    key: ValueKey(key),
    onTap: onTap,
    child: Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 16),
    ),
  );

  Widget _heroCard(String v, String lab) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            v,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          Text(
            lab,
            style: TextStyle(
              fontSize: 9.5,
              color: Colors.white.withValues(alpha: .85),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _cmp(String lab, String cur, String mom, String yoy) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: hCardDeco(context),
        child: Column(
          children: [
            Text(
              lab,
              style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant),
            ),
            Text(
              cur,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              '环比 $mom',
              style: TextStyle(
                fontSize: 9.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            Text(
              '${_dim == 'a' ? '上年' : _dim == 'm' ? '去年同月' : '去年同周'} $yoy',
              style: TextStyle(
                fontSize: 9.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(
    BuildContext context,
    String title, {
    String? tip,
    required Widget child,
  }) => Container(
    key: ValueKey('hs-card-$title'),
    decoration: hCardDeco(context),
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _T(title),
            if (tip != null && tip.isNotEmpty)
              Expanded(
                child: Text(
                  textAlign: TextAlign.right,
                  tip,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );
}

class _T extends StatelessWidget {
  const _T(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
  );
}
