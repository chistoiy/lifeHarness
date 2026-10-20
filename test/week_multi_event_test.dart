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

/// V1.46⑤ 日程周视图同小时多事件并排分段（weekCellSegments 纯函数 + 格子渲染）。
/// 新用例独立成文件；widget 层风格参照 test/grid_block_test.dart（无活动事件，
/// 避开脉冲动画 pumpAndSettle 陷阱）。
void main() {
  group('weekCellSegments 并排分段纯函数', () {
    test('1 个事件＝单段占满整格，无徽标', () {
      final segs = weekCellSegments(['A']);
      expect(segs, hasLength(1));
      expect(segs.single.item, 'A');
      expect(segs.single.rest, isEmpty);
      expect(segs.single.badgeText, isEmpty);
    });

    test('3 个事件＝三段并排各占一份，均无徽标', () {
      final segs = weekCellSegments(['A', 'B', 'C']);
      expect(segs.map((s) => s.item).toList(), ['A', 'B', 'C']);
      expect(segs.every((s) => s.badgeText.isEmpty), isTrue);
    });

    test('5 个事件＝前 3 段并排＋第 4 个起并入末段（末段代表第 4 项·徽标 +2）', () {
      final segs = weekCellSegments(['A', 'B', 'C', 'D', 'E']);
      expect(segs, hasLength(4));
      expect(segs.take(3).map((s) => s.item).toList(), ['A', 'B', 'C']);
      expect(segs[3].item, 'D');
      expect(segs[3].rest, ['E']);
      expect(segs[3].badgeText, '+2');
    });
  });

  group('周视图格子并排渲染', () {
    sqfliteFfiInit();
    TestWidgetsFlutterBinding.ensureInitialized();

    late Database db;
    late TimeBlockDao tbDao;
    // F2-2 后切档持久化走 settingsController ⇒ pump 须给真仓（mock prefs）。
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      tbDao = TimeBlockDao(db);
      prefs = await SharedPreferences.getInstance();
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('同小时两事件＝两段并排，各点各的开自己的编辑弹层（V1.52 统一弹层）',
        (tester) async {
      final now = DateTime.now();
      final d0 = DateTime(now.year, now.month, now.day);
      // A 覆盖 10 点整（9:00-10:30）· B 从 10 点起（10:00-10:50）→ 10 点格两段，
      // startMin 升序保证段序＝A、B。B10：种子由事件改块表（块单源）。
      await tbDao.insert(TimeBlock(
          day: d0, startMin: 9 * 60, endMin: 10 * 60 + 30,
          catName: '工作', note: '并排A'));
      await tbDao.insert(TimeBlock(
          day: d0, startMin: 10 * 60, endMin: 10 * 60 + 50,
          catName: '学习', note: '并排B'));

      await tester.pumpWidget(ProviderScope(
        overrides: [
          timeBlockDaoProvider.overrideWithValue(tbDao),
          legacyEventMergeDbProvider.overrideWithValue(db),
          categoryDaoProvider.overrideWithValue(CategoryDao(db)),
          // 批1 C2：本用例切到周视图后月历需展开，显式给（不再随档推导）。
          settingsRepositoryProvider.overrideWithValue(SettingsRepository(prefs)),
          monthExpandedProvider.overrideWith((ref) => true),
        ],
        child: const MaterialApp(home: CalendarPage()),
      ));
      await tester.pumpAndSettle();

      // 切周视图（7×24）；C6 自然周（周日起算）选中日列 di = weekday % 7。
      final di = now.weekday % 7;
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('▤ 周 · 7×24'));
      await tester.pumpAndSettle();

      expect(find.byKey(ValueKey('wk-seg-$di-10-0')), findsOneWidget);
      expect(find.byKey(ValueKey('wk-seg-$di-10-1')), findsOneWidget);

      // 点第二段（并排B 10:00-10:50）→ 开 B 的统一编辑弹层（预填 B 的起止）。
      await tester.ensureVisible(find.byKey(ValueKey('wk-seg-$di-10-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('wk-seg-$di-10-1')));
      await tester.pumpAndSettle();
      expect(find.text('编辑时间块'), findsOneWidget);
      expect(find.textContaining('10:00 → '), findsOneWidget);
      expect(find.text('保存修改'), findsOneWidget);

      // 遮罩关闭后点第一段（并排A 09:00-10:30）→ 开 A 的编辑弹层。
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(ValueKey('wk-seg-$di-10-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('wk-seg-$di-10-0')));
      await tester.pumpAndSettle();
      expect(find.textContaining('09:00 → '), findsOneWidget);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      await clearToasts(tester);
    });
  });
}
