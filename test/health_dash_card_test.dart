import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/dashboard/presentation/dashboard_page.dart';
import 'package:lifeharness/features/health/data/health_repository.dart';
import 'package:lifeharness/features/health/domain/health_calc.dart';
import 'package:lifeharness/features/health/domain/health_models.dart';
import 'package:lifeharness/features/health/domain/health_vital.dart';
import 'package:lifeharness/features/health/presentation/health_providers.dart';
import 'package:lifeharness/features/health/presentation/health_routes.dart';
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/domain/journal_repository.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:lifeharness/shared/linkage/health_mounts.dart';

import 'helpers.dart';

/// 健康批7 · 今日仪表盘「今日健康」卡（计划 §批7／收口版设计 §2.2 B8＋需求 V1.63 血压位）。
///
/// 四条判定：
/// · 环上读数**必须等于工作台同一个 `healthTodayScoreProvider` 的算分**（分母取当日目标：
///   2/4 杯＋480/480 睡＝55%，刀1 靶＝仪表盘侧另写一套算分或写死 8 杯 → 读出 45%/别的数）；
/// · 开关 `health.show_dash_card` 关＝**整卡不出现**（刀2 靶＝摘掉开关决策，卡照样在）；
/// · 血压位无记录出「—」不补 0（刀3 靶＝回落写成 `0/0` 或直接取收缩压）；
/// · 点卡走 **push** 直达 `/health`（栈页用 go 会清栈，返回键退 app——本仓同源坑）。
///
/// 独立文件（全 app widget 拆文件口径）；日期相对固定钟 `now` 构造。
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

  /// 仪表盘 pump：健康仓储／固定钟／prefs 三路注入，路由带健康页（点卡 push 才到得了）。
  Future<(ProviderContainer, GoRouter)> pumpDash(
    WidgetTester tester, {
    Map<String, Object> prefsValues = const {},
  }) async {
    await useSurface(tester, const Size(420, 1800));
    SharedPreferences.setMockInitialValues(prefsValues);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      healthRepositoryProvider.overrideWithValue(repo),
      healthClockProvider.overrideWithValue(() => now),
      // 仪表盘其余卡各读各的仓（待办/日记），照 dashboard_test 的既有桩法给真实仓。
      todoRepositoryProvider.overrideWithValue(
          TodoRepository(TodoDao(db), EventBus())),
      journalRepositoryProvider.overrideWithValue(JournalRepository(JournalDao(db))),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(initialLocation: '/', routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const DashboardPage(),
      ),
      ...healthPageRoutes(),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle5(tester);
    return (container, router);
  }

  /// 2/4 杯＋8h 睡（目标 4 杯/8h）＝40×0.5＋35×1＋25×0 ＝ 55 分。
  Future<void> seedTwoOfFour({int exMinutes = 0}) async {
    final dk = dayKey(now);
    await repo.bumpCups(1, dk, 2);
    await repo.saveSleep(SleepRecord(
      profileId: 1,
      date: dk,
      bedTime: '23:00',
      wakeTime: '07:00',
      durationMin: 480,
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

  const goalPrefs = {'health.water_goal': 4, 'health.sleep_goal': 8};

  String keyTx(WidgetTester t, String key) =>
      (t.widget<Text>(find.byKey(ValueKey(key)))).data ?? '';

  testWidgets('卡上环读数＝工作台同一算分（2/4 杯＋480 睡＝55%，分母写死 8 杯会读成 45%）',
      (tester) async {
    await seedTwoOfFour();
    await pumpDash(tester, prefsValues: goalPrefs);
    expect(find.byKey(HealthDashCard.kCardKey), findsOneWidget);
    final ring = find.byKey(const ValueKey('health-dash-ring'));
    expect(find.descendant(of: ring, matching: find.text('55%')), findsOneWidget);
    expect(find.text('45%'), findsNothing);
  });

  testWidgets('三枚数据位各读各的：杯数／运动分钟／血压，没记录的出「—」', (tester) async {
    await seedTwoOfFour(exMinutes: 30);
    await repo.saveVital(HealthVital(
      profileId: 1,
      date: dayKey(now),
      time: '08:00',
      kind: 'bp',
      sys: 120,
      dia: 80,
    ));
    await pumpDash(tester, prefsValues: goalPrefs);
    expect(keyTx(tester, 'health-dash-water'), '2');
    expect(keyTx(tester, 'health-dash-ex'), '30');
    expect(keyTx(tester, 'health-dash-bp'), '120/80');
  });

  testWidgets('血压没测过＝出「—」，不补 0/0 假读数', (tester) async {
    await seedTwoOfFour();
    await pumpDash(tester, prefsValues: goalPrefs);
    expect(keyTx(tester, 'health-dash-bp'), '—');
    expect(find.text('0/0'), findsNothing);
  });

  testWidgets('开关 health.show_dash_card 关掉＝整卡不出现（卡位不空挂）', (tester) async {
    await seedTwoOfFour();
    await pumpDash(tester, prefsValues: {
      ...goalPrefs,
      'health.show_dash_card': false,
    });
    expect(find.byKey(HealthDashCard.kCardKey), findsNothing);
    expect(find.text('今日健康'), findsNothing);
    expect(find.byKey(const ValueKey('health-dash-ring')), findsNothing);
  });

  testWidgets('点卡＝push 直达 /health（返回键回仪表盘，不退 app）', (tester) async {
    await seedTwoOfFour();
    final (_, router) = await pumpDash(tester, prefsValues: goalPrefs);
    await tester.tap(find.byKey(HealthDashCard.kCardKey));
    await settle5(tester);
    expect(router.routerDelegate.currentConfiguration.matches.length, greaterThan(1),
        reason: '点卡应压栈进入健康工作台');
    expect(find.text('今日概览'), findsOneWidget);
  });

  testWidgets('记一条血压后回仪表盘：卡上血压位当场跟着变（tick 重取）', (tester) async {
    await seedTwoOfFour();
    final (container, _) = await pumpDash(tester, prefsValues: goalPrefs);
    expect(keyTx(tester, 'health-dash-bp'), '—');
    await repo.saveVital(HealthVital(
      profileId: 1,
      date: dayKey(now),
      time: '09:00',
      kind: 'bp',
      sys: 118,
      dia: 76,
    ));
    container.read(healthTickProvider.notifier).state++; // 与工作台写库后同源 tick
    await settle5(tester);
    expect(keyTx(tester, 'health-dash-bp'), '118/76');
  });
}
