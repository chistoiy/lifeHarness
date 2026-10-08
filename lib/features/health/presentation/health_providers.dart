import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers.dart' show sharedPreferencesProvider;
import '../data/health_repository.dart';
import '../data/health_settings.dart';
import '../domain/health_calc.dart';
import '../domain/health_models.dart';
import '../domain/health_symptom.dart' show symNamesWith;
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
