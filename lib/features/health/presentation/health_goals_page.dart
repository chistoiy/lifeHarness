import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/lh_wheel.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/health_repository.dart';
import '../data/health_settings.dart';
import '../domain/health_goal.dart';
import '../domain/health_models.dart';
import 'health_goal_row.dart';
import 'health_providers.dart';

/// 健康目标（原型 `p-goalsH` · 路由 `/health/goals` · 批3）。
///
/// 三条口径写在最近处：
/// · **目标变更即时生效，历史数据不追改**（原型 hero 副注）：改档位只动「今天起的分母」，
///   落库的历史读数一律不重算——达标度环、睡眠柱着色当场跟着变，昨天的记录仍是昨天那条；
/// · 存储分治＝喝水/睡眠/入睡线/每周运动走 `HealthSettings`（与工作台「每日目标」卡同一键），
///   目标体重与腰/臀/颈走 `health_goal`（按档案，跨档案不聚合）；
/// · 围度读数＝「最近实测 / 目标」，两侧都可能空（两个「—」并出来），**不拿档表中点冒充目标**。
class HealthGoalsPage extends ConsumerStatefulWidget {
  const HealthGoalsPage({super.key});

  static const Key kRing = ValueKey('hg-ring');
  static const Key kRows = ValueKey('hg-rows');
  static const Key kGirths = ValueKey('hg-girths');

  @override
  ConsumerState<HealthGoalsPage> createState() => _HealthGoalsPageState();
}

class _HealthGoalsPageState extends ConsumerState<HealthGoalsPage> {
  /// 围度三枚中当前展开滚轮的那一枚（null＝都收起）。一次只开一枚，避免三排滚轮把屏挤满。
  String? _openGirth;

  /// 「最近一次真读到」的目标／身体数据，按档案钉住（`_cachePid` 变了就作废）。
  ///
  /// 为什么要缓存而不是 `valueOrNull ?? 空`：滚轮的 `initialIndex` 是从这份读数算的，
  /// 而 `healthGoalsProvider` 在 `tick++` 后会先进 loading（那几帧读数为空）——
  /// 空读数把 `initialIndex` 打回档表首档，`LHWheel.didUpdateWidget` 于是 jumpToItem(0)，
  /// 并把这一跳当**用户改动**报回 `_setDbGoal`：刚存下的 57 被档表最小值 55 盖掉，
  /// 且每次回写再触发一轮 loading（批3 目标页测试里 pumpAndSettle 挂死抓到的就是这条环）。
  /// 换档案时缓存清零：不许把上一个档案的目标/围度闪进新档案（跨档案不聚合）。
  int? _cachePid;
  Map<String, double> _goals = const {};
  List<BodyRecord> _bodies = const [];

  /// 刚写出去、provider 还没读回来的档位（乐观覆盖）。
  ///
  /// 缓存救不了第一档：档案本来就没设目标时，「最近一次读到的」就是**空表**——
  /// 写 47.0 之后进 loading 那几帧，读数仍按空表算，滚轮被带回首档 45.0，
  /// 于是「首档」当成用户改动写回库里，来回摆（批3 目标页诊断：`initialIndex` 逐帧 0/4 交替）。
  /// 这一层把「用户刚选的」钉住，等 provider 读到同值才放手。
  final Map<String, double> _pending = {};

  void _settleCache(int pid, AsyncValue<Map<String, double>> g,
      AsyncValue<List<BodyRecord>> b) {
    if (_cachePid != pid) {
      _cachePid = pid;
      _goals = const {};
      _bodies = const [];
      _openGirth = null;
      _pending.clear();
    }
    if (g.hasValue) {
      _goals = g.value!;
      // 读回了用户刚写的那一档才销账；仍是旧值（写库与刷新抢跑）就继续钉着。
      _pending.removeWhere((k, v) => _goals[k] == v);
    }
    if (b.hasValue) _bodies = b.value!;
  }

  /// 目标读数＝库里的 ＋ 用户刚写还没回来的。
  Map<String, double> get _shownGoals => {..._goals, ..._pending};

  @override
  Widget build(BuildContext context) {
    ref.watch(healthTickProvider);
    final st = ref.watch(healthSettingsProvider);
    final pid = ref.watch(activeHealthProfileProvider);
    final goalsAsync = ref.watch(healthGoalsProvider);
    final bodiesAsync = ref.watch(healthBodyProvider);
    _settleCache(pid, goalsAsync, bodiesAsync);
    final goals = _shownGoals;
    final today = ref.watch(healthTodayProvider).valueOrNull;
    final bodies = _bodies;
    final last = bodies.isEmpty ? null : bodies.last;

    final checks = today == null
        ? const <GoalCheck>[]
        : goalTodayChecks(
            cups: today.cups,
            waterGoal: st.waterGoal().toDouble(),
            sleepMin: today.lastNight?.durationMin,
            sleepGoalHours: st.sleepGoalHours().toDouble(),
            exerciseMin: today.exercises.map((e) => e.durationMin).toList(),
            plannedSlots: today.plannedSlots,
            takenSlots: today.takenSlots,
          );
    final doneN = checks.where((c) => c.done).length;

    return Scaffold(
      appBar: AppBar(title: const Text('健康目标')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _hero(context, doneN, checks.length, today, st),
          const SizedBox(height: 12),
          Container(
            key: HealthGoalsPage.kRows,
            decoration: context.cardDecoration,
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
            child: Column(
              children: [
                for (final s in goalNumberSpecs.take(2)) _row(s, st, pid, goals),
                _bedRow(st),
                _row(goalNumberSpecs[2], st, pid, goals),
                _row(goalNumberSpecs[3], st, pid, goals),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            key: HealthGoalsPage.kGirths,
            decoration: context.cardDecoration,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('围度目标',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Text('随体重记录选填',
                        style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final s in goalGirthSpecs)
                      Expanded(
                        child: _girthTile(context, s, goals[s.key], _girthMeasured(s, last)),
                      ),
                  ],
                ),
                if (_openGirth != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: LHWheel(
                      key: const ValueKey('hg-girth-wheel'),
                      labels: goalSpec(_openGirth!).labels,
                      initialIndex:
                          goalSpec(_openGirth!).indexOf(goals[_openGirth!] ?? goalSpec(_openGirth!).lo),
                      height: 106,
                      itemExtent: 30,
                      keyPrefix: 'hg-girth-',
                      onSelect: (i) => _setDbGoal(_openGirth!, goalSpec(_openGirth!).valueAt(i)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            key: const ValueKey('hg-reset'),
            onPressed: _resetDefaults,
            child: const Text('恢复默认目标', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ==================== 今日四项达标环 ====================

  Widget _hero(BuildContext context, int doneN, int total, HealthToday? today, HealthSettings st) {
    final accent = context.tokens.accent;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent, Color.lerp(accent, Colors.black, .28)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          SizedBox(
            key: HealthGoalsPage.kRing,
            width: 56,
            height: 56,
            child: CustomPaint(
              painter: _RingPainter(frac: total == 0 ? 0 : doneN / total),
              child: Center(
                child: Text('$doneN/$total',
                    key: const ValueKey('hg-ring-tx'),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('今日目标达成',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(
                  today == null
                      ? '—'
                      : goalSummaryTx(
                          cups: today.cups,
                          waterGoal: st.waterGoal().toDouble(),
                          sleepMin: today.lastNight?.durationMin,
                          sleepGoalHours: st.sleepGoalHours().toDouble(),
                          exerciseCount: today.exercises.length,
                          plannedSlots: today.plannedSlots,
                          takenSlots: today.takenSlots,
                        ),
                  key: const ValueKey('hg-sum'),
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
                const SizedBox(height: 3),
                const Text('目标变更即时生效 · 历史数据不追改',
                    style: TextStyle(color: Colors.white70, fontSize: 9)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 五项目标行（就地滚轮，选到哪档当场写） ====================

  Widget _row(GoalSpec s, HealthSettings st, int pid, Map<String, double> goals) {
    final cur = s.scope == GoalScope.prefs ? _prefsValue(s.key, st) : goals[s.key];
    final shown = cur == null ? '${s.unsetText} ${s.unit}' : s.read(cur);
    return HealthGoalRow(
      key: ValueKey('hg-rowwrap-${s.key}'),
      rowKey: ValueKey('hg-row-${s.key}'),
      wheelKey: ValueKey('hg-wheel-${s.key}'),
      icon: Icons.flag_outlined,
      label: s.label,
      hint: s.hint,
      valueText: shown,
      labels: s.labels,
      currentIndex: s.indexOf(cur ?? s.lo),
      onChanged: (i) => s.scope == GoalScope.prefs
          ? _setPrefs(s.key, s.valueAt(i), st)
          : _setDbGoal(s.key, s.valueAt(i)),
    );
  }

  Widget _bedRow(HealthSettings st) {
    final cur = st.bedLine();
    return HealthGoalRow(
      key: const ValueKey('hg-rowwrap-bed'),
      rowKey: const ValueKey('hg-row-bed_line'),
      wheelKey: const ValueKey('hg-wheel-bed_line'),
      icon: Icons.nightlight_outlined,
      label: '按时入睡线',
      hint: '统计「入睡早于该点」的天数',
      valueText: cur,
      labels: bedLineLabels,
      currentIndex: bedLineIndex(cur),
      onChanged: (i) async {
        await st.setBedLine(bedLineAt(i));
        if (mounted) healthTouch(ref);
      },
    );
  }

  double? _prefsValue(String key, HealthSettings st) => switch (key) {
        'water' => st.waterGoal().toDouble(),
        'sleep' => st.sleepGoalHours().toDouble(),
        'week_ex' => st.weekExGoal().toDouble(),
        _ => null,
      };

  Future<void> _setPrefs(String key, double v, HealthSettings st) async {
    switch (key) {
      case 'water':
        await st.setWaterGoal(v.round());
      case 'sleep':
        await st.setSleepGoal(v.round());
      case 'week_ex':
        await st.setWeekExGoal(v.round());
    }
    if (mounted) healthTouch(ref);
  }

  Future<void> _setDbGoal(String key, double v) async {
    final pid = ref.read(activeHealthProfileProvider);
    // 先记账再写库：loading 那几帧的读数靠这笔账顶住（见 `_pending`）。
    _pending[key] = v;
    await ref.read(healthRepositoryProvider).setGoal(pid, key, v);
    if (mounted) healthTouch(ref);
  }

  double? _girthMeasured(GoalSpec s, BodyRecord? last) => switch (s.key) {
        'waist_goal' => last?.waistCm,
        'hip_goal' => last?.hipCm,
        'neck_goal' => last?.neckCm,
        _ => null,
      };

  Widget _girthTile(BuildContext context, GoalSpec s, double? goal, double? measured) {
    final scheme = Theme.of(context).colorScheme;
    final open = _openGirth == s.key;
    return Container(
      key: ValueKey('hg-girth-${s.key}'),
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _openGirth = open ? null : s.key),
        child: Column(
          children: [
            Text(girthReadTx(measured, goal),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900)),
            Text(s.label, style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
            Text(open ? '收起' : '设目标',
                style: TextStyle(
                    fontSize: 9, color: scheme.primary, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  /// 「恢复默认目标」＝八项一次落回（原型 `hGoalsReset` 一行写死那组），当场重读。
  Future<void> _resetDefaults() async {
    final st = ref.read(healthSettingsProvider);
    final pid = ref.read(activeHealthProfileProvider);
    final repo = ref.read(healthRepositoryProvider);
    await st.setWaterGoal(goalDefaults['water']!.round());
    await st.setSleepGoal(goalDefaults['sleep']!.round());
    await st.setWeekExGoal(goalDefaults['week_ex']!.round());
    await st.setBedLine(bedLineDefault);
    for (final k in ['weight_goal', 'waist_goal', 'hip_goal', 'neck_goal']) {
      await repo.setGoal(pid, k, goalDefaults[k]!);
    }
    if (!mounted) return;
    healthTouch(ref);
    AppToast.show(context, '已恢复默认目标 · 喝水 8 杯 / 睡眠 8h / 23:30 前 / 运动 3 次·周 / 体重 65kg');
  }
}

/// 达成度环（与工作台 hero 同一形态：白色弧压在 25% 透明轨道上，`n/4` 居中）。
class _RingPainter extends CustomPainter {
  _RingPainter({required this.frac});
  final double frac;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(3, 3, size.width - 6, size.height - 6);
    canvas.drawArc(rect, 0, math.pi * 2, false,
        Paint()
          ..color = Colors.white.withValues(alpha: .25)
          ..strokeWidth = 5
          ..style = PaintingStyle.stroke);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * frac.clamp(0.0, 1.0), false,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.frac != frac;
}
