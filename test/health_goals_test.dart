import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/health/data/health_repository.dart';
import 'package:lifeharness/features/health/domain/health_calc.dart';
import 'package:lifeharness/features/health/domain/health_models.dart';
import 'package:lifeharness/features/health/presentation/health_home_page.dart';
import 'package:lifeharness/features/health/presentation/health_providers.dart';
import 'package:lifeharness/features/health/presentation/health_routes.dart';

import 'helpers.dart';

/// 健康批2 · B3 喝水连点/撤销 ＋ 真机 6090 反馈补的「每日目标」卡（工作台内就地滚轮）。
///
/// 三条判定：
/// · 目标此前**只有数据层写口**（setWaterGoal/setSleepGoal 零 UI 调用）＝改不了；
///   本文件把「点行→本行下方展开滚轮→选到哪档当场写 prefs 并让环/卡同帧重算」钉住；
/// · 滚轮**就地内嵌**，不许出现「点击→弹层→再操作」两段式（本文件断言无 BottomSheet/Dialog）；
/// · 喝水 +1／撤销走仓储 bumpCups 差量，0 杯时撤销置灰（不是点击无反应）。
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

  Future<ProviderContainer> pumpHealth(
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
    return container;
  }

  Finder waterCard() => find.byKey(HealthHomePage.kCardWater);
  Finder heroRing() => find.byKey(const ValueKey('health-hero-ring'));

  testWidgets('喝水 +1 连点两次落库；撤销退一杯；0 杯时撤销置灰（不是点了没反应）', (tester) async {
    await pumpHealth(tester,
        prefsValues: const {'health.water_goal': 8, 'health.sleep_goal': 8});
    final dk = dayKey(now);

    // 空态：无记录＝「—」＋虚线行，撤销按钮置灰
    expect(find.descendant(of: waterCard(), matching: find.text('—')), findsOneWidget);
    expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('health-water-undo')))
            .onPressed,
        isNull,
        reason: '0 杯没有可退的，必须看得出是灰的');

    await tester.tap(find.byKey(const ValueKey('health-water-plus')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('health-water-plus')));
    await settle5(tester);

    expect(await repo.cupsOf(1, dk), 2, reason: '连点两次＝差量写两格');
    expect(find.descendant(of: waterCard(), matching: find.text('2 杯')), findsOneWidget);
    expect(find.descendant(of: waterCard(), matching: find.text('500 ml')), findsOneWidget,
        reason: '杯数×默认 250ml＝跟着变');

    await tester.tap(find.byKey(const ValueKey('health-water-undo')));
    await settle5(tester);
    expect(await repo.cupsOf(1, dk), 1);
    expect(find.descendant(of: waterCard(), matching: find.text('250 ml')), findsOneWidget);

    expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('health-water-undo')))
            .onPressed,
        isNotNull);
  });

  testWidgets('目标卡＝点行就地展开滚轮（无弹层、无保存按钮），再点行首收起；档位与达标分母同源',
      (tester) async {
    // 2/4 杯 ＋ 8h 睡眠＝40×0.5＋35＝55%：分母必须吃目标卡那一档（写死 8 杯会读成 45%）。
    final dk = dayKey(now);
    await repo.bumpCups(1, dk, 2);
    await repo.saveSleep(SleepRecord(
      profileId: 1,
      date: dk,
      bedTime: '23:00',
      wakeTime: '07:00',
      durationMin: 480,
    ));
    await pumpHealth(tester,
        prefsValues: const {'health.water_goal': 4, 'health.sleep_goal': 8});

    expect(find.text('4 杯'), findsOneWidget, reason: '目标行按档位回显，不是写死 8 杯');
    expect(find.descendant(of: heroRing(), matching: find.text('55%')), findsOneWidget);
    expect(find.descendant(of: heroRing(), matching: find.text('45%')), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('health-goal-water')));
    await tester.tap(find.byKey(const ValueKey('health-goal-water')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('health-goal-water-wheel')), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(Dialog), findsNothing,
        reason: '两段式弹层是既定禁令：滚轮必须在行下方就地展开');
    expect(find.text('保存'), findsNothing, reason: '选到哪档当场生效，不设保存钮');

    // 再点行首收起（选完不自动收＝连改顺手，收起只由行首控制）
    await tester.tap(find.byKey(const ValueKey('health-goal-water')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('health-goal-water-wheel')), findsNothing);
  });

  testWidgets('睡眠档位读数取设置档：7 小时档下 6 小时那晚读成 86 分而非满格', (tester) async {
    final dk = dayKey(now);
    await repo.saveSleep(SleepRecord(
      profileId: 1,
      date: dk,
      bedTime: '23:30',
      wakeTime: '05:30',
      durationMin: 360, // 6 小时
    ));
    await pumpHealth(tester,
        prefsValues: const {'health.water_goal': 8, 'health.sleep_goal': 7});

    expect(find.text('7 小时'), findsOneWidget, reason: '目标行按设置档回显（不是写死 8 小时）');
    expect(find.text('8 小时'), findsNothing);
    // 分母取当日目标的算术已由 health_home_test 钉死（45%/55%/80%），本处不重复算分。
  });

  test('目标卡写链源码守护：选档当场 setWaterGoal/setSleepGoal 并 invalidate 设置与今日读数', () {
    final src = File('lib/features/health/presentation/health_home_page.dart').readAsStringSync();
    expect(src, contains('setWaterGoal(water)'), reason: '喝水目标必须有真写口（此前零 UI 调用）');
    expect(src, contains('setSleepGoal(sleepHours)'));
    expect(src, contains('ref.invalidate(healthSettingsProvider)'),
        reason: '写完要重取设置，否则行首读数停在旧档');
    expect(src, contains('ref.invalidate(healthTodayProvider)'),
        reason: '今日读数（环/卡/热力）必须同帧重算');
    expect(src, contains('HealthGoalRow'), reason: '两行共用同一就地展开件');
  });

  testWidgets('喝水卡加号只有一枚（图标或文字，不叠成双加号）；两钮同高不折行', (tester) async {
    await repo.bumpCups(1, dayKey(now), 3);
    await pumpHealth(tester,
        prefsValues: const {'health.water_goal': 8, 'health.sleep_goal': 8});

    final plus = find.byKey(const ValueKey('health-water-plus'));
    expect(find.descendant(of: plus, matching: find.textContaining('杯')), findsOneWidget);
    final marks = find.descendant(of: waterCard(), matching: find.byIcon(Icons.add)).evaluate().length +
        find.descendant(of: waterCard(), matching: find.textContaining('＋')).evaluate().length +
        find.descendant(of: waterCard(), matching: find.textContaining('+')).evaluate().length;
    expect(marks, 1, reason: '加号只许一枚：图标或文字二选一，叠用＝真机 6090 拍到的双加号缺陷');

    expect(tester.takeException(), isNull, reason: '窄卡内两枚按钮不得溢出');
    final h = tester.getRect(plus).height;
    expect(tester.getRect(find.byKey(const ValueKey('health-water-undo'))).height, h,
        reason: '两钮同高＝都没折行');
    expect(h, lessThan(60));
  });
}
