import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/dashboard/presentation/dashboard_page.dart';
import 'package:lifeharness/features/health/data/health_repository.dart';
import 'package:lifeharness/features/health/domain/health_calc.dart';
import 'package:lifeharness/features/health/domain/health_drug.dart';
import 'package:lifeharness/features/health/domain/health_models.dart';
import 'package:lifeharness/features/health/presentation/health_body_page.dart';
import 'package:lifeharness/features/health/presentation/health_exercise_page.dart';
import 'package:lifeharness/features/health/presentation/health_home_page.dart';
import 'package:lifeharness/features/health/presentation/health_med_card.dart';
import 'package:lifeharness/features/health/presentation/health_providers.dart';
import 'package:lifeharness/features/health/presentation/health_routes.dart';
import 'package:lifeharness/shared/widgets/ui_kit.dart';

import 'helpers.dart';

/// 健康批2 · B2 工作台骨架（原型 `index-health.html#p-health`）＋主页宫格入口。
///
/// 四条判定（工单执行面板第 3 项＋计划 §五.1）：
/// · 达标度分母**只吃当日目标**（写死 8 杯就会把 2/4 杯读成 25%，环上会少 10 分）；
/// · 运动是**门槛制**不是比例（刀1 靶：摘掉 `exerciseMin>=10` 这条，本文件红）；
/// · 无记录日出**空槽「—」＋虚线行**，不画 0 杯假数据；
/// · 宫格那枚去灰位后必须走 **push**（`_stackRoutes` 漏加 `/health` → go 把它变成栈底，
///   返回键直接退 app——本仓白屏同源坑）。
///
/// 独立文件（全 app/大页 pump 拆文件口径）；日期一律相对固定钟 `now` 构造。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 19, 10, 30);
  late Database db;
  late HealthRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = HealthRepository(db);
  });

  tearDown(() => db.close());

  /// 工作台 pump：建库＋固定钟＋prefs 档位，路由用模块真实注册表（栈页入口按 push）。
  /// `clock` 只在计时用例里给（能往前走的假钟），其余用例吃冻住的 `now`。
  Future<(ProviderContainer, GoRouter)> pumpHealth(
    WidgetTester tester, {
    Map<String, Object> prefsValues = const {},
    DateTime Function()? clock,
  }) async {
    await useSurface(tester, const Size(420, 1500));
    SharedPreferences.setMockInitialValues(prefsValues);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      healthRepositoryProvider.overrideWithValue(repo),
      healthClockProvider.overrideWithValue(clock ?? () => now),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(initialLocation: '/root', routes: [
      GoRoute(
        path: '/root',
        builder: (_, _) => const Scaffold(body: SizedBox.shrink()),
      ),
      ...healthPageRoutes(),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle5(tester);
    router.push('/health');
    await settle5(tester);
    return (container, router);
  }

  /// 达标度算例的公共底：目标 4 杯（默认 8 杯要被显式改掉才验得出「分母取当日目标」）。
  Future<void> seedTwoOfFour({int exMinutes = 0}) async {
    final dk = dayKey(now);
    await repo.bumpCups(1, dk, 2); // 2/4 杯
    await repo.saveSleep(SleepRecord(
      profileId: 1,
      date: dk,
      bedTime: '23:00',
      wakeTime: '07:00',
      durationMin: 480, // 写入侧按起止算＝480 分，正好吃满 8h 目标
    ));
    if (exMinutes > 0) {
      await repo.addExercise(ExerciseRecord(
        profileId: 1,
        date: dk,
        type: '步行',
        durationMin: exMinutes,
      ));
    }
  }

  const waterPrefs = {'health.water_goal': 4, 'health.sleep_goal': 8};

  Finder heroRing() => find.byKey(const ValueKey('health-hero-ring'));

  /// 挂在读数 Text 上的键（运动卡三行回显都直取，别用 textContaining 数出现次数）。
  String keyTx(WidgetTester t, String key) =>
      (t.widget<Text>(find.byKey(ValueKey(key)))).data ?? '';

  testWidgets('综合达标＝喝水40＋睡眠35＋运动25，分母一律取当日目标（2/4＋480/480＝55%）',
      (tester) async {
    await seedTwoOfFour();
    await pumpHealth(tester, prefsValues: waterPrefs);
    // 40×(2/4)＋35×(480/480)＋25×0 ＝ 20＋35＋0；分母若写死 8 杯会读成 45%。
    expect(find.descendant(of: heroRing(), matching: find.text('55%')), findsOneWidget);
    expect(find.text('45%'), findsNothing);
  });

  testWidgets('目标改档当场跟着变：8 杯档下同一份数据读成 45%', (tester) async {
    await seedTwoOfFour();
    await pumpHealth(tester,
        prefsValues: {'health.water_goal': 8, 'health.sleep_goal': 8});
    expect(find.descendant(of: heroRing(), matching: find.text('45%')), findsOneWidget);
  });

  testWidgets('运动门槛制：8 分钟记 0 分，补到 10 分钟当场记满分 25 分', (tester) async {
    await seedTwoOfFour(exMinutes: 8);
    final (container, _) = await pumpHealth(tester, prefsValues: waterPrefs);
    expect(find.descendant(of: heroRing(), matching: find.text('55%')), findsOneWidget,
        reason: '8 分钟未达门槛＝运动分量 0 分，仍是 20＋35');
    expect(find.text('63%'), findsNothing, reason: '按比例算才会出 63%（20＋35＋25×8/10）');

    await repo.addExercise(ExerciseRecord(
      profileId: 1,
      date: dayKey(now),
      type: '瑜伽',
      durationMin: 2,
    ));
    container.read(healthTickProvider.notifier).state++;
    await settle5(tester);
    expect(find.descendant(of: heroRing(), matching: find.text('80%')), findsOneWidget,
        reason: '累计 10 分钟达门槛＝20＋35＋25');
  });

  testWidgets('无喝水记录日＝空槽「—」＋虚线行，不画 0 杯假数据', (tester) async {
    await pumpHealth(tester, prefsValues: waterPrefs);
    final card = find.byKey(const ValueKey('health-card-water'));
    expect(card, findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('—')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.byType(EmptyDashRow)), findsOneWidget);
    expect(find.text('0 杯'), findsNothing);
    // hero 的喝水数据位同口径：没记就是「—」。
    final cell = find.byKey(const ValueKey('health-cell-water'));
    expect(find.descendant(of: cell, matching: find.text('—')), findsOneWidget);
    // 近 14 天概览不许给无数据日补数（不出现任何达标数字格）。
    expect(find.byKey(const ValueKey('health-heat-cell-2026-09-19')), findsNothing);
  });

  testWidgets('有记录的日＝热力格出当日达标数，无记录的日留空槽', (tester) async {
    await seedTwoOfFour();
    await pumpHealth(tester, prefsValues: waterPrefs);
    final cell = find.byKey(const ValueKey('health-heat-cell-2026-09-19'));
    expect(cell, findsOneWidget);
    expect(find.descendant(of: cell, matching: find.text('55')), findsOneWidget);
    expect(find.byKey(const ValueKey('health-heat-cell-2026-09-10')), findsNothing);
  });

  testWidgets('四枚数据位齐（批4 点亮运动位）＋直达行七枚；用药枚随批 5 点亮，趋势/设置仍不铺',
      (tester) async {
    await seedTwoOfFour();
    final (_, router) = await pumpHealth(tester, prefsValues: waterPrefs);
    expect(find.byKey(const ValueKey('health-cell-water')), findsOneWidget);
    expect(find.byKey(const ValueKey('health-cell-sleep')), findsOneWidget);
    // 体重位：这条种子没写身体数据 → 读数出「—」，但整格必须在（落点屏已经就绪）。
    final weight = find.byKey(const ValueKey('health-cell-weight'));
    expect(find.descendant(of: weight, matching: find.text('—')), findsOneWidget);
    expect(find.descendant(of: weight, matching: find.text('最近体重')), findsOneWidget);
    // 运动位（批4）：今日没记同样出「—」，不补 0（补 0 会被读成「练了但没记」）。
    final ex = find.byKey(HealthHomePage.kCellEx);
    expect(ex, findsOneWidget);
    expect(find.descendant(of: ex, matching: find.text('—')), findsOneWidget);
    expect(find.descendant(of: ex, matching: find.text('今日运动 · 分钟')), findsOneWidget);

    // 直达行只铺真落地的屏（批 4 运动／批 3 身体数据／睡眠／批 5 用药／批 3.5a 症状／批 3.5b 报告＋目标）；
    // 趋势／设置的落点屏在批 6，没就绪就不出现——禁铺假入口。
    expect(find.byKey(const ValueKey('health-entry-all')), findsOneWidget);
    for (final id in ['ex', 'body', 'sleep', 'med', 'symptom', 'report', 'goals']) {
      expect(find.byKey(ValueKey('health-entry-$id')), findsOneWidget);
    }
    for (final id in ['trend', 'settings']) {
      expect(find.byKey(ValueKey('health-entry-$id')), findsNothing);
    }

    await tester.tap(weight);
    await settle5(tester);
    expect(find.byKey(HealthBodyPage.kCells), findsOneWidget,
        reason: '体重位直达＝批 3 真落地的身体数据屏，不是空路由');
    expect(find.byKey(const ValueKey('hex-add')), findsNothing, reason: '别把两屏叠在栈上');

    router.pop();  // 需要拿返回值
    await settle5(tester);
    await tester.tap(ex);
    await settle5(tester);
    expect(find.byKey(HealthExercisePage.kCells), findsOneWidget,
        reason: '运动位直达＝批 4 真落地的运动记录屏');
    expect(find.text('运动记录'), findsOneWidget);
    await drainLogTimer(tester);
  });

  testWidgets('运动卡两处读数同源：今日分钟＝流水求和，周次数按 ≥10 分钟门槛（与流水「次数」两套口径）',
      (tester) async {
    final dk = dayKey(now);
    await repo.addExercise(ExerciseRecord(profileId: 1, date: dk, type: '步行', durationMin: 8));
    await repo.addExercise(
        ExerciseRecord(profileId: 1, date: dk, type: '跑步', distanceKm: 1.5, durationMin: 12));
    await pumpHealth(tester, prefsValues: waterPrefs);
    final card = find.byKey(HealthHomePage.kCardEx);
    expect(card, findsOneWidget);
    await tester.ensureVisible(card);
    expect(keyTx(tester, 'health-ex-today'), '今日 20 分钟', reason: '8＋12：同一天两条都算进今日');
    expect(keyTx(tester, 'health-ex-week'), '本周 1/3 次 · ≥10 分钟计一次',
        reason: '流水里是 2 条，但 8 分钟那条不够门槛——两处口径不同、各自算各自的');
    expect(find.descendant(of: find.byKey(HealthHomePage.kCellEx), matching: find.text('20')),
        findsOneWidget, reason: 'hero 数据位与运动卡吃同一份 today 快照，不许一处 20 一处 12');
  });

  testWidgets('快速算配速：边填边回显，点一下当场入账并清空输入（不留「算了没存」的落差）',
      (tester) async {
    await seedTwoOfFour();
    await pumpHealth(tester, prefsValues: waterPrefs);
    final card = find.byKey(HealthHomePage.kCardEx);
    await tester.ensureVisible(card);
    expect(keyTx(tester, 'health-ex-out'), '', reason: '没填就没有配速，不印「—」凑一行');
    expect(keyTx(tester, 'health-ex-today'), '未记录');

    // 缺项＝只出提示条，不写一条 0 分钟记录。
    await tester.enterText(find.byKey(const ValueKey('health-ex-km')), '4');
    await tester.tap(find.byKey(const ValueKey('health-ex-calc')));
    await settle5(tester);
    expect(find.text('请填距离与时长'), findsOneWidget);
    expect(await repo.exerciseRange(1, dayKey(now), dayKey(now)), isEmpty);
    await clearToasts(tester);

    await tester.enterText(find.byKey(const ValueKey('health-ex-min')), '20');
    await settle5(tester);
    expect(keyTx(tester, 'health-ex-out'), '均配速 5′00″ /km',
        reason: '20 分 ÷4 km＝300 秒/公里；回显跟着输入走，不是按下才现');

    await tester.tap(find.byKey(const ValueKey('health-ex-calc')));
    await settle5(tester);
    expect(find.text('已存 · 均配速 5′00″ /km · 210 kcal'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('health-ex-km'))).controller!.text, '');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('health-ex-min'))).controller!.text, '');
    expect(keyTx(tester, 'health-ex-today'), '今日 20 分钟');
    expect(keyTx(tester, 'health-ex-week'), '本周 1/3 次 · ≥10 分钟计一次');
    // 落库的是「跑步」＋公制 4 km＋MET 估的 210 kcal（来源手动）。
    final stored = (await repo.exerciseRange(1, dayKey(now), dayKey(now))).single;
    expect(stored.type, '跑步');
    expect(stored.distanceKm, 4.0);
    expect(stored.paceSec, 300);
    expect(stored.kcal, 210);
    expect(stored.source, '手动');
    await clearToasts(tester);
  });

  testWidgets('计时两态：按下才起表，再按＝收表并把分钟数带进弹层（来源预置「计时」）',
      (tester) async {
    var elapsedSec = 0;
    DateTime tick() => now.add(Duration(seconds: elapsedSec));
    await pumpHealth(tester, prefsValues: waterPrefs, clock: tick);
    await tester.ensureVisible(find.byKey(HealthHomePage.kCardEx));

    await tester.tap(find.byKey(const ValueKey('health-ex-timer')));
    await tester.pump();
    expect(find.text('0:00 中'), findsOneWidget, reason: '按钮本身当读数，不另摆一行数字');

    elapsedSec = 65;
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1:05 中'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('health-ex-timer')));
    await settle5(tester);
    expect(find.text('记录运动'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('hx-min'))).controller!.text, '1',
        reason: '65 秒折 1 分钟（跑不满 1 分钟也记 1，否则进不了流水也进不了周次数）');
    expect(find.byKey(const ValueKey('hx-src-计时')), findsOneWidget);
    // 收表在开弹层之前：弹层里取消也不该让计时在后台继续跑。
    await tester.tap(find.byKey(const ValueKey('hx-cancel')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('hx-save')), findsNothing);
    expect(find.text('开始计时'), findsOneWidget);
    expect(await repo.exerciseRange(1, dayKey(now), dayKey(now)), isEmpty,
        reason: '取消＝什么都不写');
  });

  /// 用药卡（批5）在长页中段：点 chip／「管理 ›」之前先滚进视口，否则坐标算到屏幕外。
  Future<void> tapCard(WidgetTester t, Key k) async {
    final f = find.byKey(k);
    await t.ensureVisible(f);
    await settle5(t);
    await t.tap(f);
    await settle5(t);
  }

  Future<int> addDrug(String name, List<String> times) =>
      repo.addDrug(DrugPlan(profileId: 1, name: name, times: times));

  testWidgets('用药卡空态：读数出「—」不铺 0/0，空态句直达建档屏（卡／屏同一句域层原话）',
      (tester) async {
    await pumpHealth(tester, prefsValues: waterPrefs);
    final card = find.byKey(HealthHomePage.kCardMed);
    expect(card, findsOneWidget);
    await tester.ensureVisible(find.byKey(HealthMedCard.kPlan));
    expect(keyTx(tester, 'health-med-plan'), '—', reason: '一支档案都没建≠一次没吃');
    expect(find.descendant(of: card, matching: find.text(medChipEmptyTx)), findsOneWidget);
    expect(find.byKey(HealthMedCard.kChips), findsNothing, reason: '没槽位就不铺空 Wrap');

    await tapCard(tester, HealthMedCard.kManage);
    expect(find.byKey(const ValueKey('hmed-empty')), findsOneWidget,
        reason: '「管理 ›」直达批 5 落地屏，不是假入口');
  });

  testWidgets('卡内 chip 点一下就打卡：读数与写库同帧，再点撤销；提示条吃原型原话', (tester) async {
    final id = await addDrug('钙片', ['08:00', '20:00']);
    await pumpHealth(tester, prefsValues: waterPrefs);
    await tester.ensureVisible(find.byKey(HealthMedCard.kChips));
    expect(keyTx(tester, 'health-med-plan'), '0/2 次 · 今日');
    expect(find.byKey(ValueKey('health-med-chip-$id-08:00')), findsOneWidget);
    expect(find.text('08:00 钙片 · 待服'), findsOneWidget, reason: 'chip 文案与卡内时刻行同源');

    await tapCard(tester, ValueKey('health-med-chip-$id-08:00'));
    expect(keyTx(tester, 'health-med-plan'), '1/2 次 · 今日');
    expect(find.text('08:00 钙片 · 已服'), findsOneWidget);
    expect(find.text('08:00 · 钙片 打卡成功'), findsOneWidget);
    expect((await repo.drugLogs(1, dayKey(now)))[id]?['08:00'], 'taken');
    await clearToasts(tester);

    await tapCard(tester, ValueKey('health-med-chip-$id-08:00'));
    expect(keyTx(tester, 'health-med-plan'), '0/2 次 · 今日');
    expect(await repo.drugLogs(1, dayKey(now)), isEmpty, reason: '撤销＝删行');
    await clearToasts(tester);
  });

  testWidgets('chips 只铺前五枚，余下收进「+n 全部」整枚跳管理屏（原型 slice(0,5)）',
      (tester) async {
    final id = await addDrug('六次药', ['01:00', '08:00', '09:00', '10:00', '11:00', '12:00']);
    await pumpHealth(tester, prefsValues: waterPrefs);
    await tester.ensureVisible(find.byKey(HealthMedCard.kChips));
    expect(keyTx(tester, 'health-med-plan'), '0/6 次 · 今日');
    for (final t in ['01:00', '08:00', '09:00', '10:00', '11:00']) {
      expect(find.byKey(ValueKey('health-med-chip-$id-$t')), findsOneWidget);
    }
    expect(find.byKey(ValueKey('health-med-chip-$id-12:00')), findsNothing,
        reason: '第六枚不铺（屏宽下会把卡挤爆），收进「+1 全部」');
    expect(find.text('+1 全部'), findsOneWidget);

    await tapCard(tester, HealthMedCard.kMore);
    expect(find.byKey(const ValueKey('hmed-plan')), findsOneWidget);
  });

  testWidgets('宫格「健康」枚去灰位后点击进工作台，返回落回仪表盘（push 语义）',
      (tester) async {
    await useSurface(tester);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      healthRepositoryProvider.overrideWithValue(repo),
      healthClockProvider.overrideWithValue(() => now),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(initialLocation: '/', routes: [
      GoRoute(path: '/', builder: (_, _) => const DashboardPage()),
      ...healthPageRoutes(),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle5(tester);

    await tester.ensureVisible(find.text('健康'));
    await settle5(tester);
    await tester.tap(find.text('健康'));
    await settle5(tester);

    expect(find.byKey(const ValueKey('health-hero-ring')), findsOneWidget);
    expect(find.textContaining('规划'), findsNothing, reason: '灰位提示文案必须消失');
    // 栈页没进 _stackRoutes 就会走 go：/health 成栈底，canPop=false，返回键直接退 app。
    expect(router.canPop(), isTrue, reason: '宫格→工作台必须是 push');
    router.pop();
    await settle5(tester);
    expect(find.text('全部功能'), findsOneWidget, reason: '返回键应落回仪表盘');
    await drainLogTimer(tester);
  });
}
