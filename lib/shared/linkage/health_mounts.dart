import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../features/health/presentation/health_providers.dart';

// ==================== 健康批7 · 共享面挂载 ====================
//
// 今日仪表盘「今日健康」卡（计划 §批7／收口版设计 §2.2 B8；需求清单 V1.63 增「当前血压位」；
// 原型＝`prototype/index.html#p-dashboard` 的 `#dashHealth`，与卡同一形态）。
// 架构守护 R1：`features/dashboard/**` 不得 import 健康 feature——卡体与读数装配全收在
// 本 shared/linkage 出口（与 media_mounts/read_mounts 同法），仪表盘只挂一枚 widget。
//
// 读数口径与工作台 hero **同源**，不另算一套：
// · 达成度环＝`healthTodayScoreProvider`（分母只吃 HealthSettings 目标值，§五.1）；
// · 杯数＝`HealthToday.cups`；运动分钟＝`HealthToday.exerciseMin`（与工作台运动位同一求和）；
// · 血压位＝`healthVitalStripProvider['bp']`（五类各取最近一条；**没测过出「—」，不补 0/0 假读数**——
//   与「无记录日不画假点」同一条口径）。
// 开关＝`health.show_dash_card`（批6b 已落 prefs，本批接仪表盘侧；关＝整卡不出现，不留空槽）。

/// 仪表盘侧唯一入口：一张卡。可见性判断也收在出口内。
class HealthDashCard extends ConsumerWidget {
  const HealthDashCard({super.key});

  static const kCardKey = ValueKey<String>('health-dash-card');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(healthSettingsProvider).showDashCard()) {
      return const SizedBox.shrink();
    }
    final today = ref.watch(healthTodayProvider).valueOrNull;
    if (today == null) return const SizedBox.shrink();
    final score = ref.watch(healthTodayScoreProvider);
    final bp = ref.watch(healthVitalStripProvider).valueOrNull?['bp'];
    final scheme = Theme.of(context).colorScheme;
    final accent = context.tokens.accent;

    return GestureDetector(
      key: kCardKey,
      onTap: () => context.push('/health'),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: context.cardDecoration,
        child: Row(
          children: [
            SizedBox(
              key: const ValueKey('health-dash-ring'),
              width: 56,
              height: 56,
              child: CustomPaint(
                painter: _DashRingPainter(frac: (score / 100).clamp(0.0, 1.0), accent: accent),
                child: Center(
                  child: Text('${score.toStringAsFixed(0)}%',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          color: accent)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                          child: Text('今日健康',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w800))),
                      Text(_dayLabel(ref.watch(healthClockProvider)()),
                          style: TextStyle(
                              fontSize: 10, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _Stat(
                        valueKey: const ValueKey('health-dash-water'),
                        value: today.cups > 0 ? '${today.cups}' : '—',
                        label: '喝水 · 目标 ${ref.watch(healthSettingsProvider).waterGoal()} 杯',
                      ),
                      _Stat(
                        valueKey: const ValueKey('health-dash-ex'),
                        value: today.exerciseMin > 0 ? '${today.exerciseMin}' : '—',
                        label: '运动分钟',
                      ),
                      _Stat(
                        valueKey: const ValueKey('health-dash-bp'),
                        value: bp?.valueText ?? '—',
                        label: '血压',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// 三枚数据位：大读数在上、人话标签在下（原型 `#dashHealth` 三列同形）。
/// 键挂在**读数 Text** 上（工作台同款定式：用例直取读数，别用 textContaining 数出现次数）。
class _Stat extends StatelessWidget {
  const _Stat({required this.valueKey, required this.value, required this.label});

  final Key valueKey;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              key: valueKey,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 1),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9, color: muted)),
        ],
      ),
    );
  }
}

/// 达成度环（原型 `#dashHealthRing` 的 `stroke-dasharray` 同形：12 点起顺时针按分数走）。
class _DashRingPainter extends CustomPainter {
  const _DashRingPainter({required this.frac, required this.accent});

  final double frac;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 3;
    final rect = Rect.fromCircle(center: c, radius: r);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    canvas.drawCircle(c, r, base..color = accent.withValues(alpha: .15));
    canvas.drawArc(
      rect,
      -1.5708,
      6.2832 * frac,
      false,
      base
        ..strokeCap = StrokeCap.round
        ..color = accent,
    );
  }

  @override
  bool shouldRepaint(_DashRingPainter oldDelegate) =>
      oldDelegate.frac != frac || oldDelegate.accent != accent;
}

String _dayLabel(DateTime now) => '${now.month}月${now.day}日';
