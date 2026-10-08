import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers.dart' show sharedPreferencesProvider;
import '../data/health_repository.dart';
import '../data/health_settings.dart';
import '../domain/health_calc.dart';
import '../domain/health_drug.dart';
import '../domain/health_models.dart';
import '../domain/health_report.dart' show ReportBundle;
import '../domain/health_symptom.dart' show symNamesWith;
import '../domain/health_trend.dart';
import '../domain/health_vital.dart';

/// 健康模块 providers（仿 items/care：写库后 tick++ 全量重取快照）。
/// UI 尚未接（批2 起），但数据面出口先定下来，避免各屏各读各的。

final healthRepositoryProvider = Provider<HealthRepository>(
    (ref) => HealthRepository(AppDatabase.instance.db));

final healthSettingsProvider =
    Provider<HealthSettings>((ref) => HealthSettings(ref.watch(sharedPreferencesProvider)));

/// 时间源缝：测试固定「今天」，日期窗口/漏服判定都按单一 now 实算（禁写死日期）。
final healthClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final healthTickProvider = StateProvider<int>((ref) => 0);
void healthTouch(WidgetRef ref) => ref.read(healthTickProvider.notifier).state++;
void healthTouchRef(Ref ref) => ref.read(healthTickProvider.notifier).state++;

/// 当前档案（切换即整模块重取；跨档案一律不聚合）。
final activeHealthProfileProvider = StateProvider<int>(
    (ref) => ref.watch(healthSettingsProvider).activeProfileId());

final healthProfilesProvider = FutureProvider<List<HealthProfile>>((ref) {
  ref.watch(healthTickProvider);
  return ref.watch(healthRepositoryProvider).profiles(includeArchived: true);
});

/// 工作台体征条（原型 `hpStrip`）：五类各取最近一条，缺的类留 null（UI 出「—」，不补 0）。
final healthVitalStripProvider = FutureProvider<Map<String, HealthVital?>>((ref) {
  ref.watch(healthTickProvider);
  final pid = ref.watch(activeHealthProfileProvider);
  return ref
      .watch(healthRepositoryProvider)
      .latestVitals(pid, dayKey(ref.watch(healthClockProvider)()));
});

final healthTodayProvider = FutureProvider<HealthToday>((ref) {
  ref.watch(healthTickProvider);
  final pid = ref.watch(activeHealthProfileProvider);
  final now = ref.watch(healthClockProvider)();
  return ref.watch(healthRepositoryProvider).today(pid, dayKey(now));
});

final healthGoalsProvider = FutureProvider<Map<String, double>>((ref) {
  ref.watch(healthTickProvider);
  return ref
      .watch(healthRepositoryProvider)
      .goals(ref.watch(activeHealthProfileProvider));
});

/// 身体数据全历史（date 升序）。30/90/365 窗口切片与三统计都在 `domain/health_body.dart` 里算——
/// 一次取数喂四数据位/曲线/三统计/流水四处，免得两处读数各看各的窗口。
final healthBodyProvider = FutureProvider<List<BodyRecord>>((ref) {
  ref.watch(healthTickProvider);
  final pid = ref.watch(activeHealthProfileProvider);
  return ref
      .watch(healthRepositoryProvider)
      .bodyRange(pid, '0000-01-01', dayKey(ref.watch(healthClockProvider)()));
});

/// 运动流水（批4 · 升序）：一次取全量喂四数据位/类型过滤/流水/配速趋势四处——
/// 本周与本月只是 `exWindow` 的两种切片，别为两个 seg 各开一路查询（两处读数会错位）。
final healthExerciseProvider = FutureProvider<List<ExerciseRecord>>((ref) {
  ref.watch(healthTickProvider);
  final pid = ref.watch(activeHealthProfileProvider);
  return ref
      .watch(healthRepositoryProvider)
      .exerciseRange(pid, '0000-01-01', dayKey(ref.watch(healthClockProvider)()));
});

/// 工作台达成度环：目标分母一律取设置值（§五.1），不设「读不到就按 8 杯」的隐式回落——
/// 设置项本身有默认值，这里只吃 HealthSettings 的读数。
final healthTodayScoreProvider = Provider<double>((ref) {
  final today = ref.watch(healthTodayProvider).valueOrNull;
  if (today == null) return 0;
  final st = ref.watch(healthSettingsProvider);
  return today.score(
    waterGoalCups: st.waterGoal().toDouble(),
    sleepGoalHours: st.sleepGoalHours().toDouble(),
  );
});

/// 症状流水（批3.5a · 升序）：一次取全量喂发作卡/直方图/部位筛选/词云/流水五处——
/// 五块看的是同一份列表，为任何一块单开一路查询都会让读数错位。
final healthSymptomProvider = FutureProvider<List<SymptomRecord>>((ref) {
  ref.watch(healthTickProvider);
  final pid = ref.watch(activeHealthProfileProvider);
  return ref.watch(healthRepositoryProvider).symptoms(pid);
});

/// 常用症状列表＝十枚种子＋用户自定义。自定义名单写 prefs，写完 tick++ 让 chips 当场重读
/// （设置「当场生效」口径：不允许「存了但这一屏看不到，下次进屏才有」）。
final healthSymNamesProvider = Provider<List<String>>((ref) {
  ref.watch(healthTickProvider);
  return symNamesWith(ref.watch(healthSettingsProvider).symCustomNames());
});

/// 报告列表＝父行＋子表检验项**一次拼好**（批3.5b）。
/// 分两路取数会出现「报告已换档案、检验项还是上一档案的」的错位帧，所以拼装在仓储侧做完，
/// 页面只管月份筛选与折叠；统计三位与卡片角标吃的都是这同一份。
final healthReportProvider = FutureProvider<List<ReportBundle>>((ref) {
  ref.watch(healthTickProvider);
  final pid = ref.watch(activeHealthProfileProvider);
  return ref.watch(healthRepositoryProvider).reportBundles(pid);
});

/// 用药屏快照（批5）：档案＋今日打卡＋近 7 天打卡**一次取齐**。
/// 热力七格若按天开七路查询，七格就来自七份快照（翻页时会互相不一致）；
/// 今日读数与卡内时刻行也必须是同一份 `todayLogs`，否则「2/4 次」与行上的「已服用」会打脸。
final healthMedProvider = FutureProvider<MedBundle>((ref) async {
  ref.watch(healthTickProvider);
  final pid = ref.watch(activeHealthProfileProvider);
  final now = ref.watch(healthClockProvider)();
  final days = mdDaysBack(now, 7);
  final date = dayKey(now);
  final repo = ref.watch(healthRepositoryProvider);
  final drugs = await repo.drugs(pid);
  final todayLogs = await repo.drugLogs(pid, date);
  final byDay = await repo.drugLogRange(pid, days.first, days.last);
  return (drugs: drugs, todayLogs: todayLogs, byDay: byDay, days: days, date: date);
});

// ==================== 趋势与周报（批6a） ====================

/// 趋势一次取数：`range`＝7 天／30 天／12 **个月**（`trFetchDays` 把窗口按两倍取，环比吃后半段）。
/// 跨度**只进 `from` 的计算、不进 watch**：把 `now` watch 起来会让每一分钟重建整个跨度
/// （年视图 731 天重取一次库），进屏时的新鲜度由 `healthTickProvider` 与路由重建保证。
final healthTrendProvider = FutureProvider.family<List<TrDay>, int>((ref, range) {
  ref.watch(healthTickProvider);
  final pid = ref.watch(activeHealthProfileProvider);
  final now = ref.read(healthClockProvider)();
  final from = dayKey(now.subtract(Duration(days: trFetchDays(range) - 1)));
  return ref.watch(healthRepositoryProvider).trendDays(pid, from, dayKey(now));
});

/// 趋势目标读数：**只吃设置与目标表的读数**（计划 §五.1）。
/// 喝水/睡眠/周运动次数在 `HealthSettings`，目标体重在 `health_goal`——改目标后 tick++ 会带着
/// 这两路一起重算，趋势曲线目标线与周报「全达标天」当场跟（真机门②钉这条）。
final healthTrGoalsProvider = Provider<TrGoals>((ref) {
  ref.watch(healthTickProvider);
  final st = ref.watch(healthSettingsProvider);
  final goals = ref.watch(healthGoalsProvider).valueOrNull ?? const <String, double>{};
  return TrGoals(
    waterCups: st.waterGoal().toDouble(),
    sleepHours: st.sleepGoalHours().toDouble(),
    weekExGoal: st.weekExGoal(),
    bodyKg: goals['weight_goal'],
  );
});
