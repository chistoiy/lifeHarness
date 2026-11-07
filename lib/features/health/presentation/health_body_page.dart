import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/health_body.dart';
import '../domain/health_calc.dart';
import '../domain/health_goal.dart';
import '../domain/health_models.dart';
import 'health_providers.dart';
import 'health_sheets.dart';

/// 身体数据（原型 `p-body` · 路由 `/health/body` · 批3）。
///
/// 四条口径写在最近处：
/// · **30/90/365 只是窗口**，一次取数（`healthBodyProvider` 全历史升序）喂四数据位／曲线／
///   三统计／流水四处，两处读数不许错位；
/// · **无实测的日子不画点**（工单 §1：原型 `htKg()` 的趋势假值是演示数据生成器，不搬进真机）；
/// · BMI 只由「体重＋身高」算，缺任一算不出＝「—」，**不拿 170 兜底**；
/// · 单位只影响展示（§五.10）：斤档下体重读数与周变化/区间变化 ×2，**距目标恒按 kg**（原型同式）。
class HealthBodyPage extends ConsumerStatefulWidget {
  const HealthBodyPage({super.key});

  static const Key kCells = ValueKey('hb-cells');
  static const Key kCurve = ValueKey('hb-curve');
  static const Key kStats = ValueKey('hb-stats');
  static const Key kList = ValueKey('hb-list');

  @override
  ConsumerState<HealthBodyPage> createState() => _HealthBodyPageState();
}

class _HealthBodyPageState extends ConsumerState<HealthBodyPage> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    ref.watch(healthTickProvider);
    final now = ref.watch(healthClockProvider)();
    final today = dayKey(now);
    final all = ref.watch(healthBodyProvider).valueOrNull ?? const <BodyRecord>[];
    final win = bodyWindow(all, days: _days, today: today);
    final unit = ref.watch(healthSettingsProvider).kgUnit();
    final goalKg = ref.watch(healthGoalsProvider).valueOrNull?[goalSpec('weight_goal').key];
    final pts = bodyCurve(win, days: _days, today: today);
    final height = latestHeightCm(all);
    final cur = all.isEmpty ? null : all.last;

    return Scaffold(
      appBar: AppBar(
        title: const Text('身体数据'),
        actions: [
          IconButton(
            key: const ValueKey('hb-add'),
            tooltip: '记一条',
            icon: const Icon(Icons.add),
            onPressed: () => showHealthWeightSheet(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _cells(context, cur, height, unit),
          const SizedBox(height: 12),
          Container(
            decoration: context.cardDecoration,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Expanded 是必须的：SegRow 内部是带 Expanded 的 Row，裸挂在横向 Row 下
                    // 拿到的是无界宽度，layout 直接炸（批3 首跑 widget 测试当场抓到）。
                    Expanded(
                      child: SegRow<int>(
                        key: const ValueKey('hb-seg'),
                        keyPrefix: 'hb-seg',
                        value: _days,
                        items: const [
                          (id: 30, label: '30 天'),
                          (id: 90, label: '90 天'),
                          (id: 365, label: '365 天')
                        ],
                        onChanged: (v) => setState(() => _days = v),
                      ),
                    ),
                    const SizedBox(width: 6),
                    TextButton(
                      key: const ValueKey('hb-add-inline'),
                      style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact),
                      onPressed: () => showHealthWeightSheet(context),
                      child: const Text('＋ 记录', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(
                  key: HealthBodyPage.kCurve,
                  height: 112,
                  width: double.infinity,
                  child: pts.length < 2
                      ? Center(
                          child: Text(pts.isEmpty ? '窗口内没有实测记录 · 暂无曲线' : '仅 1 条实测 · 连不成线',
                              key: const ValueKey('hb-curve-empty'),
                              style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        )
                      : CustomPaint(
                          painter: _BodyCurvePainter(
                            points: pts,
                            days: _days,
                            goalKg: goalKg,
                            lo: bodyAxisLo(pts, goalKg),
                            hi: bodyAxisHi(pts, goalKg),
                            accent: context.tokens.accent,
                            goal: Theme.of(context).colorScheme.error,
                          ),
                        ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(pts.length < 2 ? '—' : BodyField.trim(bodyAxisLo(pts, goalKg)),
                        key: const ValueKey('hb-axis-lo'),
                        style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    Text('体重 · $unit · 近 $_days 天',
                        key: const ValueKey('hb-cur-tx'),
                        style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    Text(pts.length < 2 ? '—' : BodyField.trim(bodyAxisHi(pts, goalKg)),
                        key: const ValueKey('hb-axis-hi'),
                        style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
                Text(
                  goalKg == null
                      ? '目标体重未设 · 在健康目标页设一档'
                      : '目标 ${goalKg.toStringAsFixed(1)} kg',
                  key: const ValueKey('hb-goal-tx'),
                  style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                Row(
                  key: HealthBodyPage.kStats,
                  children: [
                    _stat('周变化', bodyDeltaTx(bodyWeekChange(all), unit)),
                    _stat('区间变化', bodyDeltaTx(bodyRangeChange(win), unit)),
                    _stat('距目标', bodyGoalTx(bodyToGoal(all, goalKg))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _records(context, all, win, cur, height, unit),
        ],
      ),
    );
  }

  // ==================== 四枚数据位 ====================

  /// 原型 `bdW/bdB/bdH/bdF` 四格：体重、BMI（分级跟在标签里）、身高、体脂。
  /// 读数一律来自**最新一条实测**，缺的字段出「—」，不补 0 也不补中位档。
  Widget _cells(BuildContext context, BodyRecord? cur, double? height, String unit) {
    final scheme = Theme.of(context).colorScheme;
    final b = cur == null ? null : bodyBmi(cur, height);
    return Row(
      key: HealthBodyPage.kCells,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cell(context, 'hb-cell-kg',
            value: cur?.kg == null ? '—' : bodyKgTx(cur!.kg!, unit), label: '$unit 体重'),
        _cell(context, 'hb-cell-bmi',
            value: bodyBmiTx(b), label: 'BMI ${bodyLevelTx(b)}', labelColor: b == null ? null : _bmiColor(scheme, b)),
        _cell(context, 'hb-cell-height',
            value: height == null ? '—' : height.toStringAsFixed(0), label: 'cm 身高'),
        _cell(context, 'hb-cell-fat',
            value: cur?.fatPct == null ? '—' : BodyField.trim(cur!.fatPct!), label: '% 体脂'),
      ],
    );
  }

  Widget _cell(BuildContext context, String key,
      {required String value, required String label, Color? labelColor}) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        key: ValueKey(key),
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 9, color: labelColor ?? scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  /// BMI 分级色（原型 `bmiTag` 的四色；只用主题色，不自定义调色板）。
  Color _bmiColor(ColorScheme scheme, double b) =>
      b < 18.5 ? scheme.tertiary : (b < 24 ? context.tokens.accent : (b < 28 ? scheme.tertiary : scheme.error));

  // ==================== 三统计 ====================

  Widget _stat(String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        key: ValueKey('hb-stat-$label'),
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  // ==================== 测量记录 ====================

  Widget _records(BuildContext context, List<BodyRecord> all, List<BodyRecord> win, BodyRecord? cur,
      double? height, String unit) {
    final scheme = Theme.of(context).colorScheme;
    final desc = all.reversed.take(10).toList();
    return Container(
      decoration: context.cardDecoration,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('测量记录', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(bodyCountTx(total: all.length, days: _days, inWindow: win.length),
                  key: const ValueKey('hb-count'),
                  style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
            ],
          ),
          if (desc.isEmpty)
            const EmptyDashRow(text: '该档案暂无身体数据')
          else
            Column(
              key: HealthBodyPage.kList,
              children: [
                for (final r in desc)
                  InkWell(
                    key: ValueKey('hb-row-${r.id}'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => showHealthWeightSheet(context, editing: r),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 44,
                            child: Text(r.date.substring(5),
                                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                          ),
                          SizedBox(
                            width: 62,
                            child: Text(
                                '${r.kg == null ? '—' : r.kg!.toStringAsFixed(2)}'
                                '${r.kg == null ? '' : ' kg'}',
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.onSurface.withValues(alpha: .05),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('BMI ${bodyBmiTx(bodyBmi(r, height))}',
                                style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(bodyExtrasTx(r),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
                          ),
                          TextButton(
                            key: ValueKey('hb-del-${r.id}'),
                            style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact),
                            onPressed: () => _delete(r),
                            child: Text('删除',
                                style: TextStyle(
                                    fontSize: 10, color: scheme.error, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _delete(BodyRecord r) async {
    final ok = await lhConfirm(context, '删除 ${r.date} 的测量记录？曲线与统计会同步重算。');
    if (!ok || !mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    await container.read(healthRepositoryProvider).deleteBody(ref.read(activeHealthProfileProvider), r.id!);
    container.read(healthTickProvider.notifier).state++;
    if (!mounted) return; // 确认＋删库两段 await 之后才用 context 提示条
    AppToast.show(context, '已删除 · 曲线与 BMI 已重算');
  }
}

/// 体重曲线：x 按**日期**在窗口里的位置（不按点序），所以三条记录不会铺满 365 天窗口；
/// 目标线用虚线，落在同一套刻度里（轴端由 `bodyAxisLo/Hi` 含目标算出）。
class _BodyCurvePainter extends CustomPainter {
  _BodyCurvePainter({
    required this.points,
    required this.days,
    required this.goalKg,
    required this.lo,
    required this.hi,
    required this.accent,
    required this.goal,
  });

  final List<BodyPoint> points;
  final int days;
  final double? goalKg;
  final double lo;
  final double hi;
  final Color accent;
  final Color goal;

  @override
  void paint(Canvas canvas, Size size) {
    double x(int offset) =>
        8 + offset * ((size.width - 16) / math.max(1, days - 1));
    double y(double v) =>
        (size.height - 14) - ((v - lo) / math.max(0.0001, hi - lo)) * (size.height - 26);
    if (goalKg != null) {
      final p = Paint()
        ..color = goal.withValues(alpha: .8)
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.butt;
      final gy = y(goalKg!);
      // 3/3 虚线（原型 stroke-dasharray="3 3"）。
      for (var sx = 4.0; sx < size.width - 4; sx += 6) {
        canvas.drawLine(Offset(sx, gy), Offset(math.min(sx + 3, size.width - 4), gy), p);
      }
    }
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final p = Offset(x(points[i].dayOffset), y(points[i].kg));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = accent
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);
    final dot = Paint()..color = accent;
    for (final pt in points) {
      canvas.drawCircle(Offset(x(pt.dayOffset), y(pt.kg)), 2.4, dot);
    }
    final last = points.last;
    final tx = TextPainter(
      text: TextSpan(
          text: last.kg.toStringAsFixed(1),
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: accent)),
      textDirection: TextDirection.ltr,
    )..layout();
    tx.paint(canvas, Offset(x(last.dayOffset) - tx.width / 2, y(last.kg) - tx.height - 4));
  }

  @override
  bool shouldRepaint(_BodyCurvePainter old) =>
      old.points != points || old.days != days || old.lo != lo || old.hi != hi || old.goalKg != goalKg;
}
