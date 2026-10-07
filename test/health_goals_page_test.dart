import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/health/data/health_repository.dart';
import 'package:lifeharness/features/health/data/health_settings.dart';
import 'package:lifeharness/features/health/domain/health_calc.dart';
import 'package:lifeharness/features/health/domain/health_goal.dart';
import 'package:lifeharness/features/health/domain/health_models.dart';
import 'package:lifeharness/features/health/presentation/health_providers.dart';
import 'package:lifeharness/features/health/presentation/health_routes.dart';
import 'package:lifeharness/shared/widgets/lh_wheel.dart';

import 'helpers.dart';

/// 健康批3 · 健康目标屏（原型 `index-health.html#p-goalsH` ＋ `hRenderGoals`/`hGoalPick`/`hGoalsReset`）。
///
/// 五条判定（工单执行面板第 3 项）：
/// · 环＝**今日四项达标** `n/4`：喝水达杯数／睡眠达时长／**当日有 ≥10 分钟的运动**／用药计划全部已服
///   （刀3 靶：门槛写成 `>0` 就变 4/4，而副行照旧说「运动 1 次」＝两处各算各的）；
/// · **存储分治**：喝水／睡眠／每周运动／入睡线走 prefs（与工作台「每日目标」卡同一键），
///   目标体重／腰／臀／颈走 `health_goal`（按档案，跨档案不聚合）；
/// · 滚轮**就地内嵌**（LH-K39）：点行→本行下方展开，选到哪档当场写，无弹层、无保存钮；
/// · **目标变更即时生效、历史数据不追改**：改档位只动今天的分母，库里的历史读数一行不重算；
/// · 围度读数＝「最近实测 / 目标」，两侧都可能空＝两个「—」，不拿档表中点冒充目标。
///
/// 独立文件（大页 pump 拆文件口径）；日期一律相对固定钟 `now` 构造。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 19, 10, 30);
  late Database db;
  late HealthRepository repo;
  late SharedPreferences prefs;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = HealthRepository(db);
  });

  tearDown(() => db.close());

  final dk = dayKey(now);

  Future<ProviderContainer> pumpGoals(WidgetTester tester,
      {Map<String, Object> prefsValues = const {}}) async {
    await useSurface(tester, const Size(420, 2200));
    SharedPreferences.setMockInitialValues(prefsValues);
    prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      healthRepositoryProvider.overrideWithValue(repo),
      healthClockProvider.overrideWithValue(() => now),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(initialLocation: '/root', routes: [
      GoRoute(path: '/root', builder: (_, _) => const Scaffold(body: SizedBox.shrink())),
      ...healthPageRoutes(),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle5(tester);
    router.push('/health/goals');
    await settle5(tester);
    return container;
  }

  String keyText(WidgetTester t, String key) =>
      t.widget<Text>(find.byKey(ValueKey(key))).data ?? '';

  /// 目标行读数＝行内最后一个 Text（行首＝标签＋口径注，右端才是档位读数）。
  String rowRead(WidgetTester t, String key) => t
      .widgetList<Text>(
          find.descendant(of: find.byKey(ValueKey('hg-row-$key')), matching: find.byType(Text)))
      .last
      .data ?? '';

  /// 围度瓦片读数＝瓦片内第一个 Text（其后是项目名与「设目标/收起」）。
  String girthRead(WidgetTester t, String key) => t
      .widgetList<Text>(find.descendant(
          of: find.byKey(ValueKey('hg-girth-$key')), matching: find.byType(Text)))
      .first
      .data ?? '';

  /// 滚轮拖 n 档（正值＝往后一档＝数值变大）；目标行与围度瓦片的 itemExtent 都是 30。
  Future<void> spin(WidgetTester t, Key wheelKey, int steps) async {
    await t.drag(find.byKey(wheelKey), Offset(0, -30.0 * steps));
    await t.pump();
    await settle5(t);
  }

  Future<void> openRow(WidgetTester t, String key) async {
    await t.ensureVisible(find.byKey(ValueKey('hg-row-$key')));
    await t.tap(find.byKey(ValueKey('hg-row-$key')));
    await settle5(t);
  }

  Future<void> openGirth(WidgetTester t, String key) async {
    await t.ensureVisible(find.byKey(ValueKey('hg-girth-$key')));
    await t.tap(find.byKey(ValueKey('hg-girth-$key')));
    await settle5(t);
  }

  /// 写了 prefs／库之后让整模块重取（页面只 watch tick）。
  void touch(ProviderContainer c) => c.read(healthTickProvider.notifier).state++;

  testWidgets('环＝今日四项达标：5 分钟那一场记进「运动 1 次」但不计达标（刀3 靶）', (tester) async {
    await repo.bumpCups(1, dk, 8); // 喝水 8/8 达标
    await repo.saveSleep(SleepRecord(
        profileId: 1, date: dk, bedTime: '23:00', wakeTime: '07:00', durationMin: 0)); // 480 分达标
    await repo.addExercise(
        ExerciseRecord(profileId: 1, date: dk, type: '步行', durationMin: 5));
    final id = await repo.saveDrug(
        const DrugPlan(profileId: 1, name: '钙片', times: ['08:00', '20:00']));
    for (final time in ['08:00', '20:00']) {
      await repo.logDrug(DrugLog(
          profileId: 1, drugId: id, date: dk, time: time, state: 'taken'));
    }
    await pumpGoals(tester);

    expect(keyText(tester, 'hg-ring-tx'), '3/4',
        reason: '喝水／睡眠／用药三项达标；5 分钟没到 10 分钟门槛，运动不计');
    expect(keyText(tester, 'hg-sum'), contains('运动 1 次'),
        reason: '副行按「场次」如实说 1 次——环与副行不同源才说明门槛真的在环这一侧');
    expect(keyText(tester, 'hg-sum'), contains('用药 2/2 服'));
  });

  testWidgets('当日有 ≥10 分钟＝第四项达标；没排用药计划时第四项永不达标（不虚报满环）',
      (tester) async {
    await repo.bumpCups(1, dk, 8);
    await repo.saveSleep(SleepRecord(
        profileId: 1, date: dk, bedTime: '23:00', wakeTime: '07:00', durationMin: 0));
    await repo.addExercise(
        ExerciseRecord(profileId: 1, date: dk, type: '力量', durationMin: 45));
    final container = await pumpGoals(tester);
    expect(keyText(tester, 'hg-ring-tx'), '3/4', reason: 'plannedSlots=0 ⇒ 用药项不达标');

    final id = await repo.saveDrug(
        const DrugPlan(profileId: 1, name: '降压药', times: ['08:00']));
    await repo.logDrug(
        DrugLog(profileId: 1, drugId: id, date: dk, time: '08:00', state: 'taken'));
    touch(container);
    await settle5(tester);
    expect(keyText(tester, 'hg-ring-tx'), '4/4');
  });

  testWidgets('空白今日＝0/4 且副行不编读数；未排用药说「未排」而不是 0/0 服', (tester) async {
    await pumpGoals(tester);
    expect(keyText(tester, 'hg-ring-tx'), '0/4');
    expect(
        keyText(tester, 'hg-sum'),
        '喝水 0/8 · 睡眠 —/8h · 运动 0 次 · 用药 0/未排',
        reason: '睡眠没记录＝「—」；用药没排计划＝「未排」');
  });

  testWidgets('喝水目标就地改档：滚轮在本行下方展开（无弹层无保存钮），环跟着分母走',
      (tester) async {
    await repo.bumpCups(1, dk, 3);
    await pumpGoals(tester);
    expect(keyText(tester, 'hg-ring-tx'), '0/4', reason: '3 杯 < 默认 8 杯档');

    await openRow(tester, 'water');
    expect(find.byKey(const ValueKey('hg-wheel-water')), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(Dialog), findsNothing, reason: '两段式弹层是既定禁令');
    expect(find.text('保存'), findsNothing, reason: '选到哪档当场生效');

    await spin(tester, const ValueKey('hg-wheel-water'), -5); // 8 杯档 → 3 杯档
    expect(rowRead(tester, 'water'), '3 杯');
    expect(prefs.getInt(HealthSettings.kWaterGoal), 3, reason: 'prefs 作用域＝写 HealthSettings 那四键');
    expect(keyText(tester, 'hg-ring-tx'), '1/4', reason: '分母降到 3 杯，今天当场达标');
    expect(keyText(tester, 'hg-sum'), contains('喝水 3/3'));
  });

  testWidgets('改睡眠目标只动今天的分母：历史那 6 小时一行都不重算', (tester) async {
    await repo.saveSleep(SleepRecord(
        profileId: 1, date: dk, bedTime: '23:30', wakeTime: '05:30', durationMin: 0)); // 360 分
    await pumpGoals(tester);
    expect(keyText(tester, 'hg-ring-tx'), '0/4', reason: '360 分 < 默认 8 小时档');

    await openRow(tester, 'sleep');
    await spin(tester, const ValueKey('hg-wheel-sleep'), -2); // 8 小时档 → 6 小时档
    expect(rowRead(tester, 'sleep'), '6 小时');
    expect(keyText(tester, 'hg-ring-tx'), '1/4');

    final rows = await repo.sleepRange(1, '2026-09-01', '2026-09-30');
    expect(rows.single.durationMin, 360, reason: '历史数据不追改：改档位不动库里那条读数');
  });

  testWidgets('目标体重＝DB 作用域（按档案）：本档案写库，另一档案不受影响', (tester) async {
    final other = await repo.saveProfile(const HealthProfile(id: 0, name: '妈妈', rel: '母'));
    await pumpGoals(tester);
    expect(rowRead(tester, 'weight_goal'), '— kg', reason: '没设目标就出「—」，不拿档表中点当现值');

    await openRow(tester, 'weight_goal');
    await spin(tester, const ValueKey('hg-wheel-weight_goal'), 4); // 首档 45.0 → 47.0
    expect(rowRead(tester, 'weight_goal'), '47.0 kg');
    expect((await repo.goals(1))[GoalKeys.weightGoal], 47.0);
    expect(await repo.goals(other), isEmpty, reason: '跨档案不聚合：另一档案的目标不跟着变');
    expect(prefs.getInt(HealthSettings.kWaterGoal), isNull,
        reason: 'DB 作用域的键不写进 prefs（双源就是从这里长出来的）');
  });

  testWidgets('入睡线 15 分钟一档就地改：23:30 → 22:30 当场落 prefs 并重读', (tester) async {
    await pumpGoals(tester);
    expect(rowRead(tester, 'bed_line'), '23:30');
    await openRow(tester, 'bed_line');
    expect(bedLineLabels.length, 96, reason: '24 小时 × 15 分钟＝96 档，首位不是「—」');
    await spin(tester, const ValueKey('hg-wheel-bed_line'), -4); // 回退四档
    expect(rowRead(tester, 'bed_line'), '22:30');
    expect(prefs.getString(HealthSettings.kBedLine), '22:30');
  });

  testWidgets('围度读数＝「最近实测 / 目标」：两侧都空＝两个「—」，就地展开只开一枚', (tester) async {
    final container = await pumpGoals(tester);
    for (final s in goalGirthSpecs) {
      expect(girthRead(tester, s.key), '— / —', reason: '没实测也没目标＝不编数');
    }

    await openGirth(tester, 'waist_goal');
    expect(find.byKey(const ValueKey('hg-girth-wheel')), findsOneWidget);
    expect(find.byType(LHWheel), findsOneWidget, reason: '一次只开一枚，三排滚轮会把屏挤满');
    await spin(tester, const ValueKey('hg-girth-wheel'), 2); // 首档 55 → 57
    expect((await repo.goals(1))[GoalKeys.waistGoal], 57.0);
    expect(girthRead(tester, 'waist_goal'), '— / 57');

    await repo.saveBody(BodyRecord(profileId: 1, date: dk, waistCm: 76));
    touch(container);
    await settle5(tester);
    expect(girthRead(tester, 'waist_goal'), '76 / 57', reason: '「最近实测」跟着身体数据走');
  });

  testWidgets('恢复默认＝八项一次落回并当场重读（prefs 四键＋DB 四键）', (tester) async {
    await repo.saveBody(BodyRecord(profileId: 1, date: dk, waistCm: 76));
    final container = await pumpGoals(tester);
    final st = HealthSettings(prefs);
    await st.setWaterGoal(5);
    await st.setSleepGoal(6);
    await st.setWeekExGoal(4);
    await st.setBedLine('22:00');
    await repo.setGoal(1, GoalKeys.weightGoal, 70);
    await repo.setGoal(1, GoalKeys.waistGoal, 100);
    touch(container);
    await settle5(tester);
    expect(rowRead(tester, 'water'), '5 杯', reason: '先做出脏态，恢复才有对照');
    expect(rowRead(tester, 'weight_goal'), '70.0 kg');

    await tester.ensureVisible(find.byKey(const ValueKey('hg-reset')));
    await tester.tap(find.byKey(const ValueKey('hg-reset')));
    expect(
        await pollText(tester,
            '已恢复默认目标 · 喝水 8 杯 / 睡眠 8h / 23:30 前 / 运动 3 次·周 / 体重 65kg'),
        isTrue);
    await settle5(tester);

    expect(st.waterGoal(), goalDefaults['water']!.round());
    expect(st.sleepGoalHours(), goalDefaults['sleep']!.round());
    expect(st.weekExGoal(), goalDefaults['week_ex']!.round());
    expect(st.bedLine(), bedLineDefault);
    expect(rowRead(tester, 'water'), '8 杯');
    expect(rowRead(tester, 'sleep'), '8 小时');
    expect(rowRead(tester, 'week_ex'), '3 次');
    expect(rowRead(tester, 'bed_line'), '23:30');
    expect(rowRead(tester, 'weight_goal'), '65.0 kg');

    final g = await repo.goals(1);
    expect(g[GoalKeys.weightGoal], goalDefaults['weight_goal']);
    expect(g[GoalKeys.waistGoal], goalDefaults['waist_goal']);
    expect(g[GoalKeys.hipGoal], goalDefaults['hip_goal']);
    expect(g[GoalKeys.neckGoal], goalDefaults['neck_goal']);
    expect(girthRead(tester, 'waist_goal'), '76 / 76', reason: '实测 76 已在，目标落回 76');
    await clearToasts(tester);
  });
}
