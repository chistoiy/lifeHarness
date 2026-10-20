import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/health_trend.dart';
import 'health_providers.dart';
import 'health_sheets.dart';

/// 健康趋势（原型 `p-trends` · 路由 `/health/trend` · 批6a）。
///
/// 段序照原型：三档跨度 seg → 六枚指标 chips → 达标热力卡（点行出明细）→ 四数据位 →
/// 曲线卡（虚线＝目标值）→ 周报卡。四条口径写在最近处：
/// · **目标线只吃设置与目标读数**（`healthTrGoalsProvider` 单源，域层 `TrGoals.of`）——
///   原型 JS 里 `htGoal('ex')=30`、运动按分钟写死，实现按「周次数 × 单次门槛 ÷ 7」折算，
///   改「每周运动次数」后虚线当场跟（真机门②）；
/// · **缺记录日不画假点**：热力出空格（`trHeatLevel` 返 -1）、曲线跳过该点、均值只按有记录日取，
///   原型 `htWater`／`htSleepH` 那套按哈希补数的写法一条都不照抄（§五.11）；
/// · **年视图＝近 12 个月按月聚合**（旧→新），不是「今年 1~12 月」；点年视图的格只给月均，
///   并明说日明细要切「月」（`trMonthDetailTx`）；
/// · 切跨度/切指标共用同一条取数（`healthTrendProvider(range)` 按跨度缓存），chips 只换读数不换查询。
class HealthTrendPage extends ConsumerStatefulWidget {
  const HealthTrendPage({super.key});

  static const Key kSeg = ValueKey('ht-seg');
  static const Key kChips = ValueKey('ht-chips');
  static const Key kHeat = ValueKey('ht-heat');
  static const Key kDayDetail = ValueKey('ht-day-detail');
  static const Key kSlots = ValueKey('ht-slots');
  static const Key kCurve = ValueKey('ht-curve');
  static const Key kCompare = ValueKey('ht-compare');
  static const Key kReport = ValueKey('ht-report');

  @override
  ConsumerState<HealthTrendPage> createState() => _HealthTrendPageState();
}

class _HealthTrendPageState extends ConsumerState<HealthTrendPage> {
  int _range = 7;
  TrMetric _metric = TrMetric.all;

  /// 点热力格选中的键（日视图＝`yyyy-MM-dd`，年视图＝`yyyy-MM`）；null＝未选。
  String? _selKey;

  bool get _year => _range == 12;

  @override
  Widget build(BuildContext context) {
    ref.watch(healthTickProvider);
    final now = ref.watch(healthClockProvider)();
    final goals = ref.watch(healthTrGoalsProvider);
    final days = ref.watch(healthTrendProvider(_range)).valueOrNull ?? const <TrDay>[];

    final split = trSplitDays(days, _year ? 30 : _range);
    final monthSplit = trSplitMonths(trMonthsBack(now, 24));
    final curCells = _year
        ? trMonthCells(days: days, months: monthSplit.cur, m: _metric, g: goals)
        : trDayCells(days: split.cur, m: _metric, g: goals);
    final prevCells = _year
        ? trMonthCells(days: days, months: monthSplit.prev, m: _metric, g: goals)
        : trDayCells(days: split.prev, m: _metric, g: goals);
    final vals = [for (final c in curCells) c.v];
    final scale = trScale(curCells, goals.of(_metric));
    final accent = context.tokens.accent;
    final base = trMetricColor(_metric);

    return Scaffold(
      appBar: AppBar(title: const Text('健康趋势')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SegRow<int>(
            key: HealthTrendPage.kSeg,
            keyPrefix: 'ht-seg',
            value: _range,
            items: const [
              (id: 7, label: '周'),
              (id: 30, label: '月'),
              (id: 12, label: '年'),
            ],
            onChanged: (v) => setState(() {
              _range = v;
              _selKey = null; // 换跨度后格序整段变了，选中键留在上一档会指错日
            }),
          ),
          const SizedBox(height: 12),
          _chips(),
          const SizedBox(height: 10),
          _heatCard(context, curCells, scale, base, goals),
          const SizedBox(height: 12),
          _slotRow(context, vals, goals),
          const SizedBox(height: 12),
          _curveCard(context, curCells, vals, prevCells, goals, accent),
          const SizedBox(height: 12),
          _reportCard(context),
        ],
      ),
    );
  }

  // ==================== 六枚指标 chips ====================

  Widget _chips() {
    return SizedBox(
      key: HealthTrendPage.kChips,
      height: 30,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final m in trMetricOrder)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: PillChip(
                key: ValueKey('ht-chip-${m.name}'),
                label: m.label,
                selected: m == _metric,
                onTap: () => setState(() => _metric = m),
              ),
            ),
        ],
      ),
    );
  }

  // ==================== 达标热力 ====================

  Widget _heatCard(BuildContext context, List<TrCell> cells, ({double mn, double mx}) scale,
      Color base, TrGoals goals) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: context.cardDecoration,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(trHeatTx(_metric, _range),
                    key: const ValueKey('ht-heat-tx'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              ),
              Text(trLegendTx(mn: scale.mn, mx: scale.mx, unit: _metric.unit, year: _year),
                  key: const ValueKey('ht-legend'),
                  style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          GridView.count(
            key: HealthTrendPage.kHeat,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: _year ? 6 : 7,
            mainAxisSpacing: 5,
            crossAxisSpacing: 5,
            childAspectRatio: 2.4,
            children: [
              for (final c in cells) _heatCell(context, c, scale, base),
            ],
          ),
          const SizedBox(height: 8),
          Text(_detailTx(cells, goals),
              key: HealthTrendPage.kDayDetail,
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _heatCell(BuildContext context, TrCell c, ({double mn, double mx}) scale, Color base) {
    final scheme = Theme.of(context).colorScheme;
    final lv = trHeatLevel(c.v, mn: scale.mn, mx: scale.mx);
    final on = _selKey == c.key;
    // 无数据＝空格（lv=-1），不吃 0 档色——原型给哈希补数，实现按「没记就是没记」。
    final fill = lv < 0
        ? scheme.onSurface.withValues(alpha: .05)
        : base.withValues(alpha: lv == 3 ? 1 : (lv == 2 ? .6 : .25));
    return GestureDetector(
      key: ValueKey('ht-heat-${c.key}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _selKey = c.key),
      child: Container(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(8),
          border: on ? Border.all(color: context.tokens.accent, width: 1.6) : null,
        ),
        alignment: Alignment.center,
        child: Text(c.label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: lv >= 2 ? Colors.white : scheme.onSurfaceVariant,
            )),
      ),
    );
  }

  String _detailTx(List<TrCell> cells, TrGoals goals) {
    if (_selKey == null) return '未选日期';
    if (_year) {
      final c = cells.where((e) => e.key == _selKey).firstOrNull;
      return c == null ? '未选日期' : trMonthDetailTx(c.key, c.v, _metric);
    }
    final days = ref.read(healthTrendProvider(_range)).valueOrNull ?? const <TrDay>[];
    final d = days.where((e) => e.date == _selKey).firstOrNull;
    return d == null ? '未选日期' : d.detailTx(goals);
  }

  // ==================== 四数据位 ====================

  Widget _slotRow(BuildContext context, List<double?> vals, TrGoals goals) {
    final scheme = Theme.of(context).colorScheme;
    final slots = trSlots(m: _metric, vals: vals, g: goals);
    return Row(
      key: HealthTrendPage.kSlots,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < slots.length; i++)
          Expanded(
            child: Container(
              key: ValueKey('ht-slot-$i'),
              margin: EdgeInsets.only(right: i == slots.length - 1 ? 0 : 6),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: .04),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Text(slots[i].value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text(slots[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ==================== 曲线卡 ====================

  Widget _curveCard(BuildContext context, List<TrCell> cells, List<double?> vals,
      List<TrCell> prevCells, TrGoals goals, Color accent) {
    final scheme = Theme.of(context).colorScheme;
    final goal = goals.of(_metric);
    return Container(
      decoration: context.cardDecoration,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${_metric.label}趋势 · ${_year ? '按月' : '$_range 天'}',
                    key: const ValueKey('ht-curve-tx'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              ),
              Text(goal == null ? '未设目标' : '虚线 = ${goals.goalTx(_metric)}',
                  key: const ValueKey('ht-goal-tx'),
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            key: HealthTrendPage.kCurve,
            height: 96,
            width: double.infinity,
            child: CustomPaint(
              painter: _TrendPainter(
                cells: cells,
                goal: goal,
                accent: accent,
                muted: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
              trCompareTx(cur: vals, prev: [for (final c in prevCells) c.v], m: _metric),
              key: HealthTrendPage.kCompare,
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  // ==================== 周报入口 ====================

  Widget _reportCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: HealthTrendPage.kReport,
      borderRadius: BorderRadius.circular(16),
      onTap: () => showHealthWeekReportSheet(context),
      child: Container(
        decoration: context.cardDecoration,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.assessment_outlined, size: 20, color: context.tokens.accent),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('健康周报', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900)),
                  SizedBox(height: 2),
                  Text('达成摘要 · 环比上周',
                      style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                ],
              ),
            ),
            Icon(Icons.chevron_right_outlined, size: 18, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}

/// 六指标色（原型 `HT_METRICS[k].col` 的六族）——趋势页单源，弹层不另调色板。
Color trMetricColor(TrMetric m) => switch (m) {
      TrMetric.all => const Color(0xFF34D399),
      TrMetric.water => const Color(0xFF38BDF8),
      TrMetric.sleep => const Color(0xFF818CF8),
      TrMetric.ex => const Color(0xFFFBBF24),
      TrMetric.body => const Color(0xFF10B981),
      TrMetric.drug => const Color(0xFFF43F5E),
    };

/// 趋势折线：x 按**格序**（原型 `i*(W-16)/(len-1)`），y 由 `lo..hi` 归一，
/// 上下各留 28% 余量免得贴着边；缺记录点直接跳过（折线连到下一个有记录的点，不补 0）。
class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.cells,
    required this.goal,
    required this.accent,
    required this.muted,
  });

  final List<TrCell> cells;
  final double? goal;
  final Color accent;
  final Color muted;

  @override
  void paint(Canvas canvas, Size size) {
    final vs = [for (final c in cells) c.v];
    final known = <double>[for (final v in vs) ?v, ?goal];
    if (known.isEmpty) return;
    final mx = known.reduce((a, b) => a > b ? a : b);
    final mn = [...known, 0].reduce((a, b) => a < b ? a : b);
    final pad = (mx - mn) * .28;
    final lo = math.max(0.0, mn - pad);
    final hi = math.max(lo + .0001, mx + pad);
    final n = cells.length;
    double x(int i) => 8 + i * ((size.width - 16) / math.max(1, n - 1));
    double y(double v) => (size.height - 12) - ((v - lo) / (hi - lo)) * (size.height - 26);

    if (goal != null) _dashedGoal(canvas, y(goal!), size);

    final path = Path();
    var started = false;
    for (var i = 0; i < n; i++) {
      final v = vs[i];
      if (v == null) continue; // 缺记录日不出点、也不连线经过它
      final p = Offset(x(i), y(v));
      started ? path.lineTo(p.dx, p.dy) : path.moveTo(p.dx, p.dy);
      started = true;
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = accent
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);
    final dot = Paint()..color = accent;
    for (var i = 0; i < n; i++) {
      final v = vs[i];
      if (v != null) canvas.drawCircle(Offset(x(i), y(v)), 2.2, dot);
    }
  }

  void _dashedGoal(Canvas canvas, double yy, Size size) {
    final p = Paint()
      ..color = const Color(0xFFF43F5E)
      ..strokeWidth = 1;
    for (var x0 = 4.0; x0 < size.width - 4; x0 += 6) {
      canvas.drawLine(Offset(x0, yy), Offset(math.min(x0 + 3, size.width - 4), yy), p);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.cells != cells || old.goal != goal || old.accent != accent;
}
