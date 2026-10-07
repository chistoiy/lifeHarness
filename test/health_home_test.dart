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
import 'package:lifeharness/features/health/domain/health_models.dart';
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
  Future<(ProviderContainer, GoRouter)> pumpHealth(
    WidgetTester tester, {
    Map<String, Object> prefsValues = const {},
  }) async {
    await useSurface(tester, const Size(420, 1500));
    SharedPreferences.setMockInitialValues(prefsValues);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      healthRepositoryProvider.overrideWithValue(repo),
      healthClockProvider.overrideWithValue(() => now),
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

  testWidgets('运动／身体数据两格整格不渲染（批 4/批 3 未上线，不铺假入口）',
      (tester) async {
    await seedTwoOfFour();
    await pumpHealth(tester, prefsValues: waterPrefs);
    expect(find.byKey(const ValueKey('health-cell-water')), findsOneWidget);
    expect(find.byKey(const ValueKey('health-cell-sleep')), findsOneWidget);
    expect(find.byKey(const ValueKey('health-cell-ex')), findsNothing);
    expect(find.byKey(const ValueKey('health-cell-weight')), findsNothing);
    expect(find.byKey(const ValueKey('health-entry-all')), findsNothing);
    expect(find.text('身体数据'), findsNothing);
    expect(find.text('运动'), findsNothing);
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
