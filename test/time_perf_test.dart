import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/router/app_router.dart';
import 'package:lifeharness/features/calendar/data/category_dao.dart';
import 'package:lifeharness/features/calendar/data/time_block_dao.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_page.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart';
import 'package:lifeharness/features/calendar/presentation/time_stats_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 批4 性能（冻结口径 F6 系）：
/// F6-1 周视图懒构建——168 格 element 只挂视口内（重活=Builder 回调不进视口外）；
/// F6-3 账本页 30s 刷新表离屏停（RouteAware：被新页盖住即停、返回即启）。
/// _pulse 无计时即停已在 grid_day_view 既有实现（F6-3①·登记不另测）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late TimeBlockDao dao;
  late CategoryDao catDao;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    dao = TimeBlockDao(db);
    catDao = CategoryDao(db);
  });
  tearDown(() async => db.close());

  testWidgets('F6-1：周视图 168 格 element 只挂视口内（<168 且 ≥1 行）',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        calViewModeProvider.overrideWith((ref) => 'week'),
        monthExpandedProvider.overrideWith((ref) => true),
        categoryDaoProvider.overrideWithValue(catDao),
        legacyEventMergeDbProvider.overrideWithValue(db),
        timeBlockDaoProvider.overrideWithValue(dao),
      ],
      child: const MaterialApp(home: CalendarPage()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // wk-cell key 覆盖 7 天×24 小时；element 只在视口内挂载 ⇒ 数量 < 168。
    final cells = find.byWidgetPredicate(
        (w) => w is InkWell && w.key is ValueKey && (w.key as ValueKey).value.toString().startsWith('wk-cell-'));
    final n = cells.evaluate().length;
    expect(n, lessThan(168),
        reason: '168 格全挂载 ⇒ 周视图懒构建失效（F6-1）');
    expect(n, greaterThanOrEqualTo(7),
        reason: '连一行都没挂 ⇒ 用例视口异常，读数不可信');
  });

  testWidgets('F6-3：账本页被新页盖住 ⇒ 30s 表停；返回 ⇒ 表重启',
      (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        categoryDaoProvider.overrideWithValue(catDao),
        timeBlockDaoProvider.overrideWithValue(dao),
        legacyEventMergeDbProvider.overrideWithValue(db),
      ],
      child: MaterialApp(
        navigatorObservers: [timeStatsRouteObserver],
        home: Builder(builder: (ctx) {
          captured = ctx;
          return const TimeStatsPage();
        }),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final state = tester.state<State>(find.byType(TimeStatsPage));
    // 动态读 debugTicker（@visibleForTesting）。
    final ticker0 =
        (state as dynamic).debugTicker as Timer?;
    expect(ticker0, isNotNull, reason: '进页面 ⇒ 刷新表应在跑');

    // 盖上新页 ⇒ didPushNext ⇒ 停表。
    final nav = Navigator.of(captured);
    nav.push(MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('cover-page'))));
    await tester.pumpAndSettle();
    final ticker1 = (state as dynamic).debugTicker as Timer?;
    expect(ticker1, isNull, reason: '离屏（被盖住）⇒ 30s 表应停（F6-3 功耗口径）');

    // 返回 ⇒ didPopNext ⇒ 重启。
    nav.pop();
    await tester.pumpAndSettle();
    final ticker2 = (state as dynamic).debugTicker as Timer?;
    expect(ticker2, isNotNull, reason: '返回页面 ⇒ 刷新表应重启');
  });
}
