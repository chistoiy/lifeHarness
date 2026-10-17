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
import 'package:lifeharness/features/health/presentation/health_providers.dart';
import 'package:lifeharness/features/health/presentation/health_routes.dart';

import 'helpers.dart';

/// 健康批2 · B4 睡眠记录屏（`/health/sleep`）＋真机 6090 反馈「FAB 不该再让人二选一」。
///
/// 三条判定：
/// · 本屏只做睡眠一件事，FAB **直达**睡眠录入弹层（旧「记一笔→喝水/睡眠二选一」整件已摘，
///   屏上不许再出现「喝水」字样）；
/// · 录入弹层的时间/时长/质量＝就地内嵌滚轮（无两段式弹层）；
/// · 列表与柱状图读数从库取，按日期一行，进屏与写后都重取（设置当场生效同口径）。
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

  Future<ProviderContainer> pumpSleep(WidgetTester tester) async {
    await useSurface(tester, const Size(420, 1500));
    SharedPreferences.setMockInitialValues({});
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
    router.push('/health/sleep');
    await settle5(tester);
    return container;
  }

  testWidgets('空屏＝只有睡眠一件事；FAB 直达录入，屏上不出现「喝水」二选一', (tester) async {
    await pumpSleep(tester);

    expect(find.byKey(const ValueKey('hsl-fab')), findsOneWidget);
    expect(find.text('记一晚'), findsOneWidget);
    expect(find.textContaining('喝水'), findsNothing,
        reason: '「记一笔→喝水/睡眠」二选一已整件摘除，本屏只出睡眠');
    expect(find.text('记一笔'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('hsl-fab')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('hs-duration')), findsOneWidget);
    expect(find.byKey(const ValueKey('hs-ontime')), findsOneWidget);
    expect(find.byKey(const ValueKey('hs-quality')), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget,
        reason: '一步直达录入弹层（弹层内滚轮就地选，不再起第二层）');
  });

  testWidgets('有记录日＝柱状格＋列表行各一行，读数取自库（不是演示数据）', (tester) async {
    final dk = dayKey(now);
    await repo.saveSleep(SleepRecord(
      profileId: 1,
      date: dk,
      bedTime: '23:30',
      wakeTime: '06:30',
      durationMin: 420,
      quality: '一般',
    ));
    await pumpSleep(tester);

    expect(find.byKey(ValueKey('hsl-row-$dk')), findsOneWidget);
    expect(find.byKey(const ValueKey("hsl-bars")), findsOneWidget);
    expect(find.text('7 小时'), findsWidgets);
    expect(find.text('8 小时'), findsNothing, reason: '不照抄原型演示的 8 小时');
  });

  testWidgets('点列表行＝就地打开同一弹层回填该晚（编辑而非新建）', (tester) async {
    final dk = dayKey(now);
    await repo.saveSleep(SleepRecord(
      profileId: 1,
      date: dk,
      bedTime: '23:00',
      wakeTime: '07:00',
      durationMin: 480,
      quality: '好',
    ));
    await pumpSleep(tester);

    await tester.tap(find.byKey(ValueKey('hsl-row-$dk')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('hs-save')), findsOneWidget);
    expect(find.byKey(const ValueKey('hs-delete')), findsOneWidget,
        reason: '编辑既有记录才有删除位；新建态不该出现');
  });
}
