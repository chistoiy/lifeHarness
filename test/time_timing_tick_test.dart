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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// F5-3（时间模块批3 · 冻结口径 P1-10）计时条秒级刷新：
/// 有计时中块 ⇒ 轴视图「已 X 分钟」每秒刷新（Text 实例更换）；
/// 无计时中块 ⇒ 不接心跳（1s 后零重建＝功耗口径：ticker 懒启动）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late TimeBlockDao dao;
  late SharedPreferences prefs;
  final now = DateTime.now();
  final day0 = DateTime(now.year, now.month, now.day);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    dao = TimeBlockDao(db);
    prefs = await SharedPreferences.getInstance();
  });
  tearDown(() async => db.close());

  Future<void> pumpAxis(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        calViewModeProvider.overrideWith((ref) => 'axis'),
        monthExpandedProvider.overrideWith((ref) => true),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
        legacyEventMergeDbProvider.overrideWithValue(db),
        timeBlockDaoProvider.overrideWithValue(dao),
        settingsRepositoryProvider.overrideWithValue(SettingsRepository(prefs)),
      ],
      child: const MaterialApp(home: CalendarPage()),
    ));
    await settle5(tester);
  }

  testWidgets('有计时中块：轴视图「已 X 分钟」每秒刷新（Text 实例更换）',
      (tester) async {
    final start = (now.hour * 60 + now.minute - 30).clamp(0, 1439);
    await dao.startTiming(day0, start, catName: '工作');

    await pumpAxis(tester);
    final t1 = tester.widget<Text>(
        find.textContaining('计时中 · 已').first);
    expect(t1, isNotNull);

    // 推进 1 秒 ⇒ 秒级心跳触发轴视图重建 ⇒ 文案 Text 重建（实例更换）。
    await tester.pump(const Duration(seconds: 1, milliseconds: 100));
    final t2 = tester.widget<Text>(
        find.textContaining('计时中 · 已').first);
    expect(identical(t1, t2), isFalse,
        reason: '1s 后文案 Text 未重建 ⇒ F5-3 秒级心跳未生效');
  });

  testWidgets('无计时中块：不接心跳（1s 后零重建＝离屏/无计时停表）',
      (tester) async {
    await dao.insert(
        TimeBlock(day: day0, startMin: 540, endMin: 600, catName: '工作'));

    await pumpAxis(tester);
    final head = find.textContaining('· 点卡片修改起止/类型').first;
    final t1 = tester.widget<Text>(head);

    await tester.pump(const Duration(seconds: 1, milliseconds: 100));
    final t2 = tester.widget<Text>(head);
    expect(identical(t1, t2), isTrue,
        reason: '无计时中块却每秒重建 ⇒ ticker 未按功耗口径懒启动');
  });
}
