import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/settings/settings_repository.dart';
import 'package:lifeharness/features/calendar/data/category_dao.dart';
import 'package:lifeharness/features/calendar/data/time_block_dao.dart';
import 'package:lifeharness/features/calendar/domain/time_block.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_page.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart';
import 'package:lifeharness/features/calendar/presentation/time_stats_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// F4-3（时间模块批3 · 冻结口径 P1-8）：
/// 各取数点分「空」与「取数失败」两态——失败显错误卡＋重试入口；
/// 成功空列表不显错误卡（两态不混）。账本页同样区分。
///
/// 失败源用可切换闭包 override（fail=true 抛错＝库锁/磁盘异常模拟），
/// 点重试 → invalidate 重取 → 失败源解除后回归数据态＝重试通路真验。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    prefs = await SharedPreferences.getInstance();
  });
  tearDown(() async => db.close());

  List<Override> baseOverrides({required String viewMode}) => [
        calViewModeProvider.overrideWith((ref) => viewMode),
        monthExpandedProvider.overrideWith((ref) => true),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
        legacyEventMergeDbProvider.overrideWithValue(db),
        timeBlockDaoProvider.overrideWithValue(TimeBlockDao(db)),
        settingsRepositoryProvider.overrideWithValue(SettingsRepository(prefs)),
      ];

  testWidgets('轴视图：取数失败显错误卡＋重试；点重试后失败解除即回归数据态',
      (tester) async {
    var fail = true;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...baseOverrides(viewMode: 'axis'),
        dayBlocksProvider.overrideWith((ref, day) async {
          if (fail) throw Exception('db down');
          return <TimeBlock>[];
        }),
      ],
      child: const MaterialApp(home: CalendarPage()),
    ));
    await settle5(tester);

    expect(find.text('取数失败'), findsOneWidget);
    expect(find.byKey(const ValueKey('time-retry')), findsOneWidget);

    fail = false;
    await tester.tap(find.byKey(const ValueKey('time-retry')));
    await settle5(tester);
    expect(find.text('取数失败'), findsNothing);
  });

  testWidgets('空态与失败两态分离：成功取到空列表不显错误卡', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...baseOverrides(viewMode: 'axis'),
        dayBlocksProvider
            .overrideWith((ref, day) async => <TimeBlock>[]),
      ],
      child: const MaterialApp(home: CalendarPage()),
    ));
    await settle5(tester);

    expect(find.text('取数失败'), findsNothing);
    expect(find.byKey(const ValueKey('time-retry')), findsNothing);
  });

  testWidgets('账本页：取数失败显错误卡＋重试，同样区分两态', (tester) async {
    var fail = true;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
        timeBlockDaoProvider.overrideWithValue(TimeBlockDao(db)),
        blocksInRangeProvider.overrideWith((ref, r) async {
          if (fail) throw Exception('db down');
          return <TimeBlock>[];
        }),
      ],
      child: const MaterialApp(home: TimeStatsPage()),
    ));
    await settle5(tester);

    expect(find.text('取数失败'), findsOneWidget);
    expect(find.byKey(const ValueKey('time-retry')), findsOneWidget);

    fail = false;
    await tester.tap(find.byKey(const ValueKey('time-retry')));
    await settle5(tester);
    expect(find.text('取数失败'), findsNothing);
  });
}
