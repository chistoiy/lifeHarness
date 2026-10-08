import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/load_error_state.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/health_repository.dart';
import '../data/health_settings.dart';
import '../domain/health_body.dart';
import '../domain/health_calc.dart';
import '../domain/health_ex.dart';
import '../domain/health_models.dart';
import '../domain/health_vital.dart';
import 'health_goal_row.dart';
import 'health_providers.dart';
import 'health_sheets.dart';

/// 健康工作台（原型 `prototype/index-health.html#p-health` · 路由 `/health`）。
///
/// 段序照原型：hero（达成度环＋数据位）→ 喝水卡／睡眠卡 → 近 14 天达标概览 → 最近记录。
/// 三条本版口径（就写在离代码最近的地方）：
/// · **达标度分母只吃 `HealthSettings` 读数**（计划 §五.1，与 `health_providers.dart` 里那条注释同源），
///   UI 里不许出现写死的 8 杯/8 小时；
/// · **直达行与 hero 数据位只渲染落点屏已存在的枚**（批4 起：四枚数据位＋运动/身体数据/睡眠/目标四枚直达）；
///   用药·趋势·设置入口随批 5/6 逐枚点亮，缺落点就整格不出现，不铺点不动的假入口
///   （AGENTS「禁铺假入口」）；键名留在 `HealthHomePage` 里随批启用，不另起第二个名字；
/// · 无记录＝空槽「—」＋虚线行，任何一格都不许拿 0 当读数（原型演示数据不照抄）。
class HealthHomePage extends ConsumerWidget {
  const HealthHomePage({super.key});

  static const Key kHeroRing = ValueKey('health-hero-ring');
  static const Key kCellWater = ValueKey('health-cell-water');
  static const Key kCellSleep = ValueKey('health-cell-sleep');
  static const Key kCardWater = ValueKey('health-card-water');
  static const Key kCardSleep = ValueKey('health-card-sleep');

  /// 预留位（落点屏没就绪就不渲染）：运动位＝批 4；直达行的用药/趋势/设置＝批 5/6。
  static const Key kCellEx = ValueKey('health-cell-ex');
  static const Key kCardEx = ValueKey('health-card-ex');
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
  final _exKm = TextEditingController();
  final _exMin = TextEditingController();

  /// 计时器两态：`_timerStart == null`＝未跑。Ticker 只在点「开始计时」后挂上，
  /// 页面 dispose 必收（常驻周期 Timer 会把 pumpAndSettle 的测试拖挂）。
  Timer? _ticker;
  int? _timerStart;
  int _elapsedSec = 0;

  @override
  void dispose() {
    _ticker?.cancel();
    _exKm.dispose();
    _exMin.dispose();
    super.dispose();
  }

  void _startTimer() {
    setState(() {
      _timerStart = ref.read(healthClockProvider)().millisecondsSinceEpoch;
      _elapsedSec = 0;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final start = _timerStart;
      if (start == null) return;
      setState(() => _elapsedSec =
          (ref.read(healthClockProvider)().millisecondsSinceEpoch - start) ~/ 1000);
    });
  }

  /// 结束计时＝把秒数折成分钟（不足 1 分钟记 1 分钟）带进运动弹层，来源预置「计时」。
  /// 先收 Timer 再开弹层：弹层里用户改主意（取消）也不该让计时继续在后台跑。
  void _finishTimer() {
    final start = _timerStart;
    _ticker?.cancel();
    _ticker = null;
    setState(() {
      _timerStart = null;
    });
    if (start == null) return;
    final mins = exMinutesOf(_elapsedSec);
    setState(() => _elapsedSec = 0);
    showHealthExerciseSheet(context,
        presetMinutes: mins, presetSource: '计时', presetStartedAt: start);
  }

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
        _entryRow(context),
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
        _exerciseCard(context, st),
        const SizedBox(height: 12),
        _vitalStrip(context),
        const SizedBox(height: 12),
        _overview(context, hub, waterGoal, sleepGoalMin),
        const SizedBox(height: 12),
        _goalsCard(context, st),
        const SizedBox(height: 16),
        const Text('最近记录',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        ..._stream(hub),
      ],
    );
  }

  // ==================== 每日目标（就地滚轮·选到哪档当场生效） ====================

  Widget _goalsCard(BuildContext context, HealthSettings st) {
    final cups = st.waterGoal();
    final hours = st.sleepGoalHours();
    return Container(
      key: const ValueKey('health-goals'),
      decoration: context.cardDecoration,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('每日目标',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          HealthGoalRow(
            rowKey: const ValueKey('health-goal-water'),
            wheelKey: const ValueKey('health-goal-water-wheel'),
            icon: Icons.water_drop_outlined,
            label: '喝水',
            valueText: '$cups 杯',
            labels: [for (var i = 1; i <= 12; i++) '$i 杯'],
            currentIndex: (cups - 1).clamp(0, 11),
            onChanged: (i) => _saveGoal(water: i + 1),
          ),
          HealthGoalRow(
            rowKey: const ValueKey('health-goal-sleep'),
            wheelKey: const ValueKey('health-goal-sleep-wheel'),
            icon: Icons.nightlight_outlined,
            label: '睡眠',
            valueText: '$hours 小时',
            labels: [for (var i = 4; i <= 12; i++) '$i 小时'],
            currentIndex: (hours - 4).clamp(0, 8),
            onChanged: (i) => _saveGoal(sleepHours: i + 4),
          ),
        ],
      ),
    );
  }

  /// 目标写完当场生效：设置重取 → 今日读数与环／卡／热力同帧重算（不留"要重启才生效"的缝）。
  Future<void> _saveGoal({int? water, int? sleepHours}) async {
    final st = ref.read(healthSettingsProvider);
    if (water != null) await st.setWaterGoal(water);
    if (sleepHours != null) await st.setSleepGoal(sleepHours);
    if (!mounted) return;
    ref.invalidate(healthSettingsProvider);
    ref.invalidate(healthTodayProvider);
    healthTouch(ref);
  }

  // ==================== hero ====================

  Widget _hero(BuildContext context, double score, DateTime now, HealthSettings st) {
    final cups = widget.today.cups;
    final sleep = widget.today.lastNight;
    // 体重读数＝最近一次实测换算到当前单位（§五.10：存储恒 kg，只有展示跟着 kgUnit 走）。
    final kg = widget.today.kg;
    final unit = st.kgUnit();
    final kgTx = kg == null ? '—' : bodyKgTx(kg, unit);
    final exMin = widget.today.exerciseMin;
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
                    final w = (c.maxWidth - gap) / 2;
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
                        // 体重位（批3 落地）：读数＝最近一次实测（跨到昨天也算「最近」，
                        // 与身体数据页 hero 同源 `HealthToday.latestBody`），无记录出「—」。
                        SizedBox(
                          width: w,
                          child: _HeroCell(
                            k: HealthHomePage.kCellWeight,
                            value: kg == null ? '—' : '$kgTx $unit',
                            label: '最近体重',
                            onTap: () => context.push('/health/body'),
                          ),
                        ),
                        // 运动位（批4 落地）：今日分钟数＝`HealthToday.exercises` 求和，与运动卡、
                        // 概览、流水同源；无记录出「—」（不补 0，补 0 会被读成「练了但没记」）。
                        SizedBox(
                          width: w,
                          child: _HeroCell(
                            k: HealthHomePage.kCellEx,
                            value: exMin > 0 ? '$exMin' : '—',
                            label: '今日运动 · 分钟',
                            onTap: () => context.push('/health/exercise'),
                          ),
                        ),
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

  // ==================== 直达行（原型 hEntryRow · 只渲染落点已存在的枚） ====================

  /// 运动枚批4 已点亮；用药·趋势·设置三枚随批 5/6 逐枚点亮：落点屏不存在就整枚不出现，
  /// 而不是铺一排点不动的假入口（AGENTS「禁铺假入口」）。
  ///
  /// 症状/报告两枚是**对原型的偏离**：原型 `hEntryRow` 只有七枚（身体/睡眠/运动/用药/趋势/目标/设置），
  /// 症状与报告走「记一笔」八类 `sheetHAdd`——那张八类弹层本仓未实现（工单 §2 登记）。
  /// 屏已落地却没有入口等于做了一张进不去的屏，所以先挂在直达行上，八类弹层落地时这两枚再收回去。
  Widget _entryRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = <(String, IconData, String, String)>[
      ('ex', Icons.directions_run_outlined, '运动', '/health/exercise'),
      ('body', Icons.monitor_weight_outlined, '身体数据', '/health/body'),
      ('sleep', Icons.bedtime_outlined, '睡眠', '/health/sleep'),
      ('symptom', Icons.coronavirus_outlined, '症状', '/health/symptom'),
      ('report', Icons.description_outlined, '报告', '/health/report'),
      ('goals', Icons.flag_outlined, '目标', '/health/goals'),
    ];
    return Container(
      key: HealthHomePage.kEntryAll,
      decoration: context.cardDecoration,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: Row(
        children: [
          for (final (id, icon, label, route) in items)
            Expanded(
              child: InkWell(
                key: ValueKey('health-entry-$id'),
                borderRadius: BorderRadius.circular(10),
                onTap: () => context.push(route),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Column(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(icon, size: 18, color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Text(label,
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// ＋1 杯／撤销（B3）：连点**不弹确认**、当场生效（写库后 invalidate＋tick 重取），
  /// 撤销到 0 就停住——按钮进禁用帧而不是把杯数减成负数。
  Future<void> _bumpCups(int delta) async {
    final pid = ref.read(activeHealthProfileProvider);
    final day = dayKey(ref.read(healthClockProvider)());
    final repo = ref.read(healthRepositoryProvider);
    final cur = await repo.cupsOf(pid, day);
    if (cur + delta < 0) return;
    await repo.bumpCups(pid, day, delta);
    if (!mounted) return;
    ref.invalidate(healthTodayProvider);
    healthTouch(ref);
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
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('health-water-plus'),
                  onPressed: () => _bumpCups(1),
                  // 图标已是加号，标签不再重复「＋」（真机 6090 实拍出双加号并折行）
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('1 杯', maxLines: 1, softWrap: false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('health-water-undo'),
                  onPressed: cups == 0 ? null : () => _bumpCups(-1),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  child: const Text('撤销', maxLines: 1, softWrap: false),
                ),
              ),
            ],
          ),
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
              // 原型 427 行＝卡头右侧只有 mini-btn「＋ 记录」；界线时间沉进副注（slT），
              // 半宽卡里两处并排会溢出（真机口径 420vp 下 RenderFlex +19px）。
              // 流水与改记录在 `/health/sleep`（批2 第二屏），这里只给入口不给编辑面。
              TextButton(
                key: const ValueKey('health-sleep-all'),
                onPressed: () => context.push('/health/sleep'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('＋ 记录', style: TextStyle(fontSize: 11)),
              ),
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
              '目标 ${(sleepGoalMin / 60).toStringAsFixed(0)} 小时 · $line 前 · '
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

  // ==================== 运动卡（原型 hp 第四卡 · 批4） ====================

  /// 今日分钟／本周有效次数（≥10 分钟才算一次，§五.9）／快速算配速／记一笔／计时。
  /// 用药卡（原型第五卡）在批5，本行先让运动卡占满整行——落点屏没就绪的卡不铺（禁假入口）。
  Widget _exerciseCard(BuildContext context, HealthSettings st) {
    final scheme = Theme.of(context).colorScheme;
    final todayMin = widget.today.exerciseMin;
    final all = ref.watch(healthExerciseProvider).valueOrNull ?? const <ExerciseRecord>[];
    final week = exWindow(all,
        days: 7, today: dayKey(ref.watch(healthClockProvider)()));
    final sessions = exWeekSessions(week);
    final goal = st.weekExGoal();
    final running = _timerStart != null;
    final kmVal = double.tryParse(_exKm.text.trim());
    final minVal = int.tryParse(_exMin.text.trim());
    final pace = kmVal == null || minVal == null || kmVal <= 0 || minVal <= 0
        ? null
        : paceSecOf(distanceKm: kmVal, durationMin: minVal);
    final unit = ref.watch(healthSettingsProvider).kmUnit();
    return Container(
      key: HealthHomePage.kCardEx,
      decoration: context.cardDecoration,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.directions_run_outlined, size: 15, color: context.tokens.accent),
              const SizedBox(width: 4),
              const Text('运动', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton(
                key: const ValueKey('health-ex-all'),
                onPressed: () => context.push('/health/exercise'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('记录 ›', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(todayMin > 0 ? '今日 $todayMin 分钟' : '未记录',
              key: const ValueKey('health-ex-today'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text('本周 $sessions/$goal 次 · ≥10 分钟计一次',
              key: const ValueKey('health-ex-week'),
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: _quickField('距离 · $unit', 'health-ex-km', _exKm, numeric: true)),
              const SizedBox(width: 6),
              Expanded(child: _quickField('时长 · 分', 'health-ex-min', _exMin, numeric: true)),
              const SizedBox(width: 6),
              SizedBox(
                width: 66,
                child: OutlinedButton(
                  key: const ValueKey('health-ex-calc'),
                  onPressed: _quickSave,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(0, 34),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('算配速', maxLines: 1, style: TextStyle(fontSize: 10.5)),
                ),
              ),
            ],
          ),
          Text(pace == null ? '' : '均配速 ${paceLabelFor(pace, unit)} ${exDistUnitTx(unit)}',
              key: const ValueKey('health-ex-out'),
              maxLines: 1,
              style: TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w800, color: context.tokens.accent)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  key: const ValueKey('health-ex-add'),
                  onPressed: () => showHealthExerciseSheet(context),
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 36)),
                  child: const Text('记一笔', maxLines: 1, softWrap: false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('health-ex-timer'),
                  onPressed: running ? _finishTimer : _startTimer,
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 36)),
                  child: Text(running ? _timerTx(_elapsedSec) : '开始计时',
                      maxLines: 1, softWrap: false, style: const TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 计时中按钮就是计时读数（不再另摆一行数字：卡里位置有限，读数跟着动作走）。
  String _timerTx(int sec) => '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')} 中';

  Widget _quickField(String label, String key, TextEditingController c, {bool numeric = true}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            key: ValueKey('$key-label'),
            style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
        TextField(
          key: ValueKey(key),
          controller: c,
          // 填一位数就重算一次：「均配速」回显与入账吃同一对读数（点了才有变化的假联动不认）。
          onChanged: (_) => setState(() {}),
          keyboardType: numeric ? TextInputType.number : TextInputType.text,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  /// 快速算配速＝算完直接入账（原型 `sportCalc` 同形：填两值点一下即一条「跑步」记录今日入账）。
  /// 少一个入口就少一次「算了没存」的落差；要改类型/备注走弹层。
  Future<void> _quickSave() async {
    final kmVal = double.tryParse(_exKm.text.trim());
    final minVal = int.tryParse(_exMin.text.trim());
    if (kmVal == null || minVal == null || kmVal <= 0 || minVal <= 0) {
      AppToast.show(context, '请填距离与时长');
      return;
    }
    final container = ProviderScope.containerOf(context, listen: false);
    final now = container.read(healthClockProvider)();
    final rec = exDraft(
      profileId: container.read(activeHealthProfileProvider),
      date: dayKey(now),
      type: '跑步',
      mode: ExMode.pace,
      km: kmVal,
      min: minVal,
    );
    await container.read(healthRepositoryProvider).addExercise(rec);
    container.invalidate(healthTodayProvider);
    container.read(healthTickProvider.notifier).state++;
    _exKm.clear();
    _exMin.clear();
    if (!mounted) return;
    final unit = ref.read(healthSettingsProvider).kmUnit();
    AppToast.show(context,
        '已存 · 均配速 ${paceLabelFor(rec.paceSec, unit)} ${exDistUnitTx(unit)} · ${rec.kcal ?? estKcal(rec.type, rec.durationMin)} kcal');
  }

  // ==================== 体征条（原型 hpStrip · 批2.5） ====================

  /// 五枚等分＝各指标**最近一条**读数（`latestVitals` 一次取数，不分五路读数）。
  /// 三条口径：无记录出「—」不补 0；超范围只换色不作结论（§11.3.1 异常只作提示）；
  /// 点击带 `kind` 进体征屏并选中该指标——栈页一律 push（漏加就会把返回键变成退 app）。
  Widget _vitalStrip(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final strip = ref.watch(healthVitalStripProvider).valueOrNull ?? const <String, HealthVital?>{};
    return Container(
      key: const ValueKey('health-vital-strip'),
      decoration: context.cardDecoration,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: Row(
        children: [
          for (final k in vitalOrder)
            Expanded(
              child: InkWell(
                key: ValueKey('health-vital-$k'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => context.push('/health/vitals?kind=$k'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Column(
                    children: [
                      Text(vitalSpecs[k]!.name,
                          style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Text(strip[k]?.valueText ?? '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                              color: strip[k] != null && strip[k]!.flag != 'normal'
                                  ? scheme.error
                                  : context.tokens.accent)),
                    ],
                  ),
                ),
              ),
            ),
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
