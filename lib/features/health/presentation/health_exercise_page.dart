import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/health_calc.dart';
import '../domain/health_ex.dart';
import '../domain/health_models.dart';
import 'health_providers.dart';
import 'health_sheets.dart';

/// 运动记录（原型 `p-exLog` · 路由 `/health/exercise` · 批4）。
///
/// 五条口径写在最近处：
/// · 本周/本月＝7/30 天窗口（与体征页同一算法），**一次取数**喂四数据位／过滤／流水／趋势四处；
/// · 四数据位跟着「窗口∩类型过滤」走（原型 `hRenderExLog` 就是拿过滤后的 list 求和），
///   所以点了「骑行」之后次数/时长/距离/kcal 四枚会一起换档，不是只换流水；
/// · 「次数」＝窗口内条数，工作台周目标那枚「次数」＝**≥10 分钟**的有效次数（§五.9），
///   两处口径不同、各自算各自的，不许互相顶替；
/// · 配速趋势只取距离类最近 12 条，不足 2 条出空态（不拿一条点连成「趋势」）；
/// · 单位只影响展示（§五.10）：距离读数与配速后缀跟着 `kmUnit()` 走，存储恒公制。
class HealthExercisePage extends ConsumerStatefulWidget {
  const HealthExercisePage({super.key});

  static const Key kCells = ValueKey('hex-cells');
  static const Key kList = ValueKey('hex-list');
  static const Key kTrend = ValueKey('hex-trend');

  @override
  ConsumerState<HealthExercisePage> createState() => _HealthExercisePageState();
}

class _HealthExercisePageState extends ConsumerState<HealthExercisePage> {
  int _days = 7;
  String _filter = exAllFilter;

  @override
  Widget build(BuildContext context) {
    ref.watch(healthTickProvider);
    final now = ref.watch(healthClockProvider)();
    final today = dayKey(now);
    final all = ref.watch(healthExerciseProvider).valueOrNull ?? const <ExerciseRecord>[];
    final win = exWindow(all, days: _days, today: today);
    final shown = exListDesc(exFiltered(win, _filter));
    final unit = ref.watch(healthSettingsProvider).kmUnit();
    final st = exStats(shown);
    final trend = exPaceTrend(all);

    return Scaffold(
      appBar: AppBar(
        title: const Text('运动记录'),
        actions: [
          IconButton(
            key: const ValueKey('hex-add'),
            tooltip: '记一笔',
            icon: const Icon(Icons.add),
            onPressed: () => showHealthExerciseSheet(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SegRow<int>(
            key: const ValueKey('hex-seg'),
            keyPrefix: 'hex-seg',
            value: _days,
            items: const [
              (id: 7, label: '本周'),
              (id: 30, label: '本月'),
            ],
            onChanged: (v) => setState(() => _days = v),
          ),
          const SizedBox(height: 12),
          _cells(context, st, unit),
          const SizedBox(height: 12),
          _filters(context, all),
          const SizedBox(height: 12),
          _stream(context, shown, unit),
          const SizedBox(height: 12),
          _trend(context, trend, unit),
        ],
      ),
    );
  }

  // ==================== 四枚数据位 ====================

  Widget _cells(BuildContext context, ({int count, int totalMin, double totalKm, int totalKcal}) st, String unit) {
    return Row(
      key: HealthExercisePage.kCells,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cell('hex-cell-count', '${st.count}', '次数'),
        _cell('hex-cell-min', '${st.totalMin}', '总时长 · 分'),
        _cell('hex-cell-km', st.totalKm <= 0 ? '0' : exKmTx(st.totalKm, unit), '总距离 · $unit'),
        _cell('hex-cell-kcal', '${st.totalKcal}', '总消耗 · kcal'),
      ],
    );
  }

  Widget _cell(String key, String value, String label) {
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
                style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  // ==================== 类型过滤（全部＋八类·点一下换档，不是循环切） ====================

  Widget _filters(BuildContext context, List<ExerciseRecord> all) {
    final has = all.map((e) => e.type).toSet();
    return SizedBox(
      key: const ValueKey('hex-filters'),
      height: 30,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final t in exFilterOptions())
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: PillChip(
                // 只有真出现过的类型带条数角标；「全部」与零条类型不写 0（写 0 会被读成「有 0 次」）。
                key: ValueKey('hex-filter-$t'),
                label: t == exAllFilter || !has.contains(t) ? t : '$t ${all.where((e) => e.type == t).length}',
                selected: t == _filter,
                onTap: () => setState(() => _filter = t),
              ),
            ),
        ],
      ),
    );
  }

  // ==================== 流水 ====================

  Widget _stream(BuildContext context, List<ExerciseRecord> list, String unit) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: context.cardDecoration,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('流水', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton(
                key: const ValueKey('hex-add-inline'),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact),
                onPressed: () => showHealthExerciseSheet(context),
                child: const Text('＋ 记一笔', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          if (list.isEmpty)
            const EmptyDashRow(text: '该区间暂无运动记录')
          else
            Column(
              key: HealthExercisePage.kList,
              children: [
                for (final r in list.take(30))
                  InkWell(
                    key: ValueKey('hex-row-${r.id}'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => showHealthExerciseSheet(context, editing: r),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        children: [
                          Icon(_typeIcon(r.type), size: 17, color: context.tokens.accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(exRowMain(r, unit),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900)),
                                const SizedBox(height: 2),
                                Text(exRowSub(r),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (exTrendPaceSec(r) != null && hasDistance(r.type))
                            Text(paceLabelFor(exTrendPaceSec(r), unit),
                                key: ValueKey('hex-pace-${r.id}'),
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: context.tokens.accent)),
                          TextButton(
                            key: ValueKey('hex-del-${r.id}'),
                            style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact),
                            onPressed: () => _delete(r),
                            child: Text('删除',
                                style: TextStyle(fontSize: 10, color: scheme.error, fontWeight: FontWeight.w700)),
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

  /// 原型 `hExIco` 的五组线性图标（跑步/步行/球类/其他共用「运动」族）——Flutter 侧取 Material
  /// 线性图标同位映射，不引第三方 SVG 资源（偏离一句已登记批4 工单 §3）。
  IconData _typeIcon(String type) => switch (type) {
        '骑行' => Icons.two_wheeler_outlined,
        '游泳' => Icons.pool_outlined,
        '力量' => Icons.fitness_center_outlined,
        '瑜伽' => Icons.self_improvement_outlined,
        '球类' => Icons.sports_basketball_outlined,
        '步行' => Icons.directions_walk_outlined,
        _ => Icons.directions_run_outlined,
      };

  Future<void> _delete(ExerciseRecord r) async {
    final ok = await lhConfirm(context, '删除 ${r.date} 的${r.type}记录？流水与统计会同步重算。');
    if (!ok || !mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    await container.read(healthRepositoryProvider).deleteExercise(r.profileId, r.id!);
    container.invalidate(healthTodayProvider);
    container.read(healthTickProvider.notifier).state++;
    if (!mounted) return; // 确认＋删库两段 await 之后才用 context 提示条
    AppToast.show(context, '已删除 · 统计与趋势已重算');
  }

  // ==================== 配速趋势 ====================

  Widget _trend(BuildContext context, List<ExerciseRecord> trend, String unit) {
    final scheme = Theme.of(context).colorScheme;
    final spread = exPaceSpread(trend);
    return Container(
      decoration: context.cardDecoration,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('配速趋势 · 仅距离类',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: scheme.onSurface)),
          const SizedBox(height: 6),
          SizedBox(
            key: HealthExercisePage.kTrend,
            height: 84,
            width: double.infinity,
            child: !exTrendEnough(trend)
                ? Center(
                    child: Text('距离类记录不足 2 次 · 暂无配速曲线',
                        key: const ValueKey('hex-trend-empty'),
                        style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                  )
                : CustomPaint(
                    painter: _PaceTrendPainter(
                      points: [
                        for (final e in trend)
                          if (exTrendPaceSec(e) != null) (e.date, exTrendPaceSec(e)!)
                      ],
                      fast: spread.fast,
                      slow: spread.slow,
                      unit: unit,
                      accent: context.tokens.accent,
                      muted: scheme.onSurfaceVariant,
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Text(exTrendEnough(trend) ? '最近 ${trend.length} 次 · 每 $unit' : '—',
              key: const ValueKey('hex-trend-note'),
              style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// 配速折线：x 按**记录序**（原型 `i*(W-20)/(len-1)`，不是按日期），y 是秒每公里；
/// 轴端标「最快/最慢」（配速越小越快，所以 min 是快的那条）。
class _PaceTrendPainter extends CustomPainter {
  _PaceTrendPainter({
    required this.points,
    required this.fast,
    required this.slow,
    required this.unit,
    required this.accent,
    required this.muted,
  });

  final List<(String date, int paceSec)> points;
  final int? fast;
  final int? slow;
  final String unit;
  final Color accent;
  final Color muted;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || fast == null || slow == null) return;
    final lo = math.max(1, fast! - 30);
    final hi = math.max(lo + 1, slow! + 30);
    double x(int i) => 10 + i * ((size.width - 20) / math.max(1, points.length - 1));
    double y(int v) => (size.height - 12) - ((v - lo) / (hi - lo)) * (size.height - 26);
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final p = Offset(x(i), y(points[i].$2));
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
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(Offset(x(i), y(points[i].$2)), 2.4, dot);
    }
    _label(canvas, '最快 ${paceLabelFor(fast, unit)}', Offset(4, 2), muted);
    _label(canvas, '最慢 ${paceLabelFor(slow, unit)}',
        Offset(size.width - 78, size.height - 12), muted);
  }

  void _label(Canvas canvas, String tx, Offset at, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: tx, style: TextStyle(fontSize: 8, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_PaceTrendPainter old) =>
      old.points != points || old.fast != fast || old.slow != slow || old.unit != unit;
}
