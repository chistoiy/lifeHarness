import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/calendar/data/category_dao.dart';
import 'package:lifeharness/features/calendar/data/time_block_dao.dart';
import 'package:lifeharness/features/calendar/domain/event_repository.dart';
import 'package:lifeharness/features/calendar/domain/week_align.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_page.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/time_env.dart';

/// F2-5/C6（时间模块批1 · 冻结口径）周视图=自然周（周日起算），与账本『w』档同源：
/// ① 任意锚日的 7 天窗=周日→周六（不再 ±3 滚动窗）；
/// ② 跨周边界（含跨月/跨年）两处（周视图 weekStartOf / 账本 weekly 口径）结果一致。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  test('周三锚日 ⇒ 周日 9/20 起、周六 9/26 止（7 天）', () {
    final days = naturalWeek(DateTime(2026, 9, 23)); // 2026-09-23 = 周三
    expect(days, hasLength(7));
    expect(days.first.weekday, DateTime.sunday);
    expect(days.first, DateTime(2026, 9, 20));
    expect(days.last, DateTime(2026, 9, 26));
    expect(days[3], DateTime(2026, 9, 23)); // 锚日在窗内
  });

  test('周日锚日 ⇒ 本身即起点（C6 主判据：周日起算）', () {
    final days = naturalWeek(DateTime(2026, 9, 20)); // 周日
    expect(days.first, DateTime(2026, 9, 20));
    expect(days.last, DateTime(2026, 9, 26));
  });

  test('跨周边界（10/1 周四）⇒ 回到 9/27 周日（跨月表达）', () {
    final days = naturalWeek(DateTime(2026, 10, 1));
    expect(days.first, DateTime(2026, 9, 27));
    expect(days.last, DateTime(2026, 10, 3));
  });

  test('跨周边界（1/1 周四）⇒ 回到上年 12/28 周日（跨年表达）', () {
    final days = naturalWeek(DateTime(2026, 1, 1));
    expect(days.first, DateTime(2025, 12, 28));
    expect(days.last, DateTime(2026, 1, 3));
  });

  test('周视图与账本同源：weekStartOf 与账本『w』档 from 口径逐点一致', () {
    // 账本口径（time_stats_page _periodFor 'w'）= from: weekday%7 回退 · to: from+6。
    for (final d in [
      DateTime(2026, 9, 19),
      DateTime(2026, 9, 20),
      DateTime(2026, 9, 23),
      DateTime(2026, 10, 1),
      DateTime(2026, 1, 1),
    ]) {
      final a = DateTime(d.year, d.month, d.day);
      final ledgerFrom = DateTime(a.year, a.month, a.day - (a.weekday % 7)); // 账本旧公式
      expect(weekStartOf(d), ledgerFrom, reason: '$d 两处周起点必须一致');
      final days = naturalWeek(d);
      expect(days.last.difference(days.first).inDays, 6);
    }
  });

  testWidgets('周视图 UI：锚日 9/23 时头部窗=9/20-9/26（自然周而非 ±3 窗 9/20-9/26 同型但锚 9/25 即分辨）',
      (tester) async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    addTearDown(db.close);
    // 锚 9/25（周五）：±3 旧窗=9/22-9/28；自然周=9/20-9/26 —— 两口径可分辨。
    await tester.pumpWidget(ProviderScope(
      overrides: [
        calSelectedProvider.overrideWith((ref) => DateTime(2026, 9, 25)),
        calViewModeProvider.overrideWith((ref) => 'week'),
        monthExpandedProvider.overrideWith((ref) => true),
        timeBlockDaoProvider.overrideWithValue(TimeBlockDao(db)),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
        eventRepositoryProvider.overrideWithValue(
            EventRepository(await eventsDaoOf(db), busForTest())),
      ],
      child: const MaterialApp(home: CalendarPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('9/20 - 9/26'), findsOneWidget);
    expect(find.textContaining('9/22 - 9/28'), findsNothing);
  });
}
