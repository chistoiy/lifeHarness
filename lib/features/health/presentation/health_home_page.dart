import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/load_error_state.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/health_repository.dart';
import '../data/health_settings.dart';
import '../domain/health_calc.dart';
import 'health_providers.dart';

/// 健康工作台（原型 `prototype/index-health.html#p-health` · 路由 `/health`）。
///
/// 段序照原型：hero（达成度环＋数据位）→ 喝水卡／睡眠卡 → 近 14 天达标概览 → 最近记录。
/// 三条本版口径（就写在离代码最近的地方）：
/// · **达标度分母只吃 `HealthSettings` 读数**（计划 §五.1，与 `health_providers.dart` 里那条注释同源），
///   UI 里不许出现写死的 8 杯/8 小时；
/// · **运动位·体重位与七枚直达行整格不渲染**——落点屏在批 3/批 4，现在铺出来就是点不动的假入口
///   （AGENTS「禁铺假入口」）；键名留在这里，随批启用，不另起第二个名字；
/// · 无记录＝空槽「—」＋虚线行，任何一格都不许拿 0 当读数（原型演示数据不照抄）。
class HealthHomePage extends ConsumerWidget {
  const HealthHomePage({super.key});

  static const Key kHeroRing = ValueKey('health-hero-ring');
  static const Key kCellWater = ValueKey('health-cell-water');
  static const Key kCellSleep = ValueKey('health-cell-sleep');
  static const Key kCardWater = ValueKey('health-card-water');
  static const Key kCardSleep = ValueKey('health-card-sleep');

  /// 预留位（本版不渲染）：运动＝批 4、身体数据＝批 3、直达行＝随各自屏落地。
  static const Key kCellEx = ValueKey('health-cell-ex');
  static const Key kCellWeight = ValueKey('health-cell-weight');
  static const Key kEntryAll = ValueKey('health-entry-all');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(healthTodayProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('健康')),
      body: today.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => LoadErrorBanner(
          title: '今天这几项没加载出来',
          error: e,
          onRetry: () => ref.invalidate(healthTodayProvider),
        ),
        data: (t) => _HealthHub(today: t),
      ),
    );
  }
}

/// 近 14 天单日切片（概览热力格与最近记录流水共用一次取数，免两处读数错位）。
class _HealthDay {
  const _HealthDay({
    required this.date,
    required this.cups,
    required this.exerciseMin,
    this.sleepMin,
    this.bedTime,
  });

  final String date;
  final int cups;
  final int exerciseMin;
  final int? sleepMin;
  final String? bedTime;

  bool get hasData => cups > 0 || sleepMin != null || exerciseMin > 0;

  int score({required double waterGoalCups, required double sleepGoalMin}) => dailyScore(
        cups: cups,
        waterGoalCups: waterGoalCups,
        sleepMin: sleepMin ?? 0,
        sleepGoalMin: sleepGoalMin,
        exerciseMin: exerciseMin,
      ).round();
}

/// 一次取 14 天（档案过滤沿用仓储的 `profile_id=?` 口径，切档案随 tick 重取）。
final _hubProvider = FutureProvider<List<_HealthDay>>((ref) async {
  ref.watch(healthTickProvider);
  final pid = ref.watch(activeHealthProfileProvider);
  final now = ref.watch(healthClockProvider)();
  final repo = ref.watch(healthRepositoryProvider);
  final from = dayKey(now.subtract(const Duration(days: 13)));
  final to = dayKey(now);
  final water = await repo.waterRange(pid, from, to);
  final sleeps = await repo.sleepRange(pid, from, to);
  final exs = await repo.exerciseRange(pid, from, to);
  final cupsBy = {for (final w in water) w.date: w.cups};
  final sleepBy = {for (final s in sleeps) s.date: s};
  final exBy = <String, int>{};
  for (final e in exs) {
    exBy[e.date] = (exBy[e.date] ?? 0) + e.durationMin;
  }
  final out = <_HealthDay>[];
  for (var back = 13; back >= 0; back--) {
    final d = dayKey(now.subtract(Duration(days: back)));
    final s = sleepBy[d];
    out.add(_HealthDay(
      date: d,
      cups: cupsBy[d] ?? 0,
      exerciseMin: exBy[d] ?? 0,
      sleepMin: s?.durationMin,
      bedTime: s?.bedTime,
    ));
  }
  return out;
});

/// hero＋两卡＋概览＋流水的排布（有状态只为拿住两张卡的 GlobalKey：
/// 数据位点击分流＝滚到对应卡；批 4 起睡眠位改跳 `/health/sleep`，此处再换分派）。
class _HealthHub extends ConsumerStatefulWidget {
  const _HealthHub({required this.today});

  final HealthToday today;

  @override
  ConsumerState<_HealthHub> createState() => _HealthHubState();
}

class _HealthHubState extends ConsumerState<_HealthHub> {
  final _waterCardKey = GlobalKey();
  final _sleepCardKey = GlobalKey();

  void _gotoCard(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 220));
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(healthSettingsProvider);
    final score = ref.watch(healthTodayScoreProvider);
    final now = ref.watch(healthClockProvider)();
    final hub = ref.watch(_hubProvider);
    final waterGoal = st.waterGoal().toDouble();
    final sleepGoalMin = st.sleepGoalHours() * 60.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _hero(context, score, now, st),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _waterCard(context, st, waterGoal)),
            const SizedBox(width: 12),
            Expanded(child: _sleepCard(context, st, sleepGoalMin, hub)),
          ],
        ),
        const SizedBox(height: 12),
        _overview(context, hub, waterGoal, sleepGoalMin),
        const SizedBox(height: 16),
        const Text('最近记录',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        ..._stream(hub),
      ],
    );
  }

  // ==================== hero ====================

  Widget _hero(BuildContext context, double score, DateTime now, HealthSettings st) {
    final cups = widget.today.cups;
    final sleep = widget.today.lastNight;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: context.tokens.gradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: context.tokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('今日概览',
                  style: TextStyle(
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
              Text(_dayLabel(now),
                  style: const TextStyle(color: Colors.white70, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                key: HealthHomePage.kHeroRing,
                width: 74,
                height: 74,
                child: CustomPaint(
                  painter: _RingPainter(frac: (score / 100).clamp(0.0, 1.0)),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${score.toStringAsFixed(0)}%',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w900)),
                        const Text('综合达标',
                            style: TextStyle(color: Colors.white70, fontSize: 8)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    const gap = 8.0;
                    final w = (c.maxWidth - gap * 2) / 3;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        SizedBox(
                          width: w,
                          child: _HeroCell(
                            k: HealthHomePage.kCellWater,
                            value: cups > 0 ? '$cups 杯' : '—',
                            label: '今日喝水 · 目标 ${st.waterGoal()}',
                            onTap: () => _gotoCard(_waterCardKey),
                          ),
                        ),
                        SizedBox(
                          width: w,
                          child: _HeroCell(
                            k: HealthHomePage.kCellSleep,
                            value: sleep == null ? '—' : '${_hours(sleep.durationMin)} 小时',
                            label: '昨晚睡眠',
                            onTap: () => _gotoCard(_sleepCardKey),
                          ),
                        ),
                        // 运动位（HealthHomePage.kCellEx · 批 4）与体重位（kCellWeight · 批 3）
                        // 本版没有落点屏，整格不渲染——铺出来就是点不动的假入口。
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== 喝水卡 ====================

  Widget _waterCard(BuildContext context, HealthSettings st, double waterGoal) {
    final scheme = Theme.of(context).colorScheme;
    final cups = widget.today.cups;
    return Container(
      key: HealthHomePage.kCardWater,
      decoration: context.cardDecoration,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.water_drop_outlined, size: 15),
              const SizedBox(width: 4),
              const Text('喝水',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('目标 ${waterGoal.toStringAsFixed(0)} 杯',
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 6),
          if (cups == 0) ...[
            const Text('—', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const EmptyDashRow(text: '还没有喝水记录'),
          ] else ...[
            Text('$cups 杯',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Wrap(spacing: 3, runSpacing: 3, children: _cupChips(cups, waterGoal)),
            const SizedBox(height: 6),
            Text('${st.waterMl(cups)} ml',
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  List<Widget> _cupChips(int cups, double waterGoal) {
    final scheme = Theme.of(context).colorScheme;
    final goal = waterGoal.round();
    return [
      for (var i = 0; i < goal; i++)
        Container(
          width: 20,
          height: 16,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: i < cups ? scheme.primary : scheme.onSurface.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(5),
          ),
          child: i < cups
              ? Text('${i + 1}',
                  style: TextStyle(
                      fontSize: 8, color: scheme.onPrimary, fontWeight: FontWeight.w700))
              : null,
        ),
    ];
  }

  // ==================== 睡眠卡 ====================

  Widget _sleepCard(
      BuildContext context, HealthSettings st, double sleepGoalMin,
      AsyncValue<List<_HealthDay>> hub) {
    final scheme = Theme.of(context).colorScheme;
    final night = widget.today.lastNight;
    final line = st.bedLine();
    // 原型 slOndt＝近 7 天口径（概览热力才是 14 天），只取窗口尾 7 天计数。
    final recent = hub.valueOrNull ?? const <_HealthDay>[];
    final week = recent.length <= 7 ? recent : recent.sublist(recent.length - 7);
    final onTime = week
        .where((d) => d.bedTime != null && fellAsleepOnTime(d.bedTime!, line))
        .length;
    return Container(
      key: HealthHomePage.kCardSleep,
      decoration: context.cardDecoration,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bedtime_outlined, size: 15),
              const SizedBox(width: 4),
              const Text('睡眠',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('$line 前', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 6),
          if (night == null) ...[
            const Text('—', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const EmptyDashRow(text: '昨夜没有睡眠记录'),
          ] else ...[
            Text('${_hours(night.durationMin)} 小时',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(
              '目标 ${(sleepGoalMin / 60).toStringAsFixed(0)} 小时 · '
              '${fellAsleepOnTime(night.bedTime, line) ? '按时入睡' : '晚于界线'}',
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
            ),
            if (onTime > 0) ...[
              const SizedBox(height: 2),
              Text('近 7 天按时入睡 $onTime 天',
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            ],
          ],
        ],
      ),
    );
  }

  // ==================== 近 14 天达标概览 ====================

  Widget _overview(BuildContext context, AsyncValue<List<_HealthDay>> hub,
      double waterGoal, double sleepGoalMin) {
    if (hub.hasError) {
      return LoadErrorBanner(
        title: '近 14 天概览没加载出来',
        error: hub.error ?? StateError('未知'),
        onRetry: () => ref.invalidate(_hubProvider),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final accent = context.tokens.accent;
    // 有记录的日才算分、才落键；无记录的日留空槽（补数＝这两行会多出格子，用例盯 health-heat-cell-*）。
    final cells = <(String, int?)>[
      for (final d in hub.valueOrNull ?? const <_HealthDay>[])
        (
          d.date,
          d.hasData
              ? d.score(waterGoalCups: waterGoal, sleepGoalMin: sleepGoalMin)
              : null,
        ),
    ];
    return Container(
      decoration: context.cardDecoration,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('近 14 天达标概览',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              Row(
                children: [
                  Text('低', style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
                  const SizedBox(width: 3),
                  for (final a in const [.25, .6, 1.0])
                    Container(
                      width: 11,
                      height: 11,
                      margin: const EdgeInsets.only(right: 2),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: a),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  Text('高', style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, c) {
              const gap = 4.0;
              final w = (c.maxWidth - gap * 6) / 7;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final (date, sc) in cells)
                    SizedBox(
                      width: w,
                      height: 26,
                      child: sc == null
                          ? Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: scheme.outlineVariant),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            )
                          : KeyedSubtree(
                              key: ValueKey('health-heat-cell-$date'),
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _heatColor(accent, sc),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('$sc',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: sc >= 55
                                          ? Colors.white
                                          : scheme.onSurfaceVariant,
                                    )),
                              ),
                            ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Color _heatColor(Color accent, int score) => score >= 80
      ? accent
      : (score >= 55 ? accent.withValues(alpha: .6) : accent.withValues(alpha: .25));

  // ==================== 最近记录流水 ====================

  List<Widget> _stream(AsyncValue<List<_HealthDay>> hub) {
    final lines = <(IconData, String)>[];
    for (final d in hub.valueOrNull ?? const <_HealthDay>[]) {
      if (d.cups > 0) {
        lines.add((Icons.water_drop_outlined, '${_md(d.date)} · 喝水 ${d.cups} 杯'));
      }
      if (d.sleepMin != null) {
        lines.add((Icons.bedtime_outlined, '${_md(d.date)} · 睡眠 ${_hours(d.sleepMin!)} 小时'));
      }
      if (d.exerciseMin > 0) {
        lines.add((Icons.directions_run_outlined, '${_md(d.date)} · 运动 ${d.exerciseMin} 分钟'));
      }
      if (lines.length >= 6) break;
    }
    if (lines.isEmpty) return const [EmptyDashRow(text: '还没有健康记录')];
    final scheme = Theme.of(context).colorScheme;
    return [
      for (final (ic, text) in lines)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: context.cardDecoration,
            child: Row(
              children: [
                Icon(ic, size: 15, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
              ],
            ),
          ),
        ),
    ];
  }

  // ==================== 读数格式 ====================

  static String _hours(int min) => (min / 60).toStringAsFixed(1);

  static String _md(String dateKey) => dateKey.substring(5);

  static String _dayLabel(DateTime d) {
    const wd = ['一', '二', '三', '四', '五', '六', '日'];
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$mm-$dd 周${wd[d.weekday - 1]}';
  }
}

/// hero 数据位（原型 `.bg-white/15` 圆角小块：读数＋小字标签，点击分流到对应卡）。
class _HeroCell extends StatelessWidget {
  const _HeroCell({
    required this.k,
    required this.value,
    required this.label,
    required this.onTap,
  });

  final Key k;
  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: k,
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 8)),
          ],
        ),
      ),
    );
  }
}

/// 达成度环（原型 `heroRing` 的 `stroke-dasharray` 同形：12 点起顺时针按分数走）。
class _RingPainter extends CustomPainter {
  const _RingPainter({required this.frac});

  final double frac;

  static const Color _track = Color(0x47FFFFFF); // 白 28%（半透明白描边，不写 Colors.white）
  static const Color _fill = Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 3;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = _track,
    );
    canvas.drawArc(
      rect,
      -1.5708,
      6.2832 * frac,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = _fill,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.frac != frac;
}
