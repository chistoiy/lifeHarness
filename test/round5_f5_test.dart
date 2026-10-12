import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/calendar/data/category_dao.dart';
import 'package:lifeharness/features/calendar/data/event_dao.dart';
import 'package:lifeharness/features/calendar/data/time_block_dao.dart';
import 'package:lifeharness/features/calendar/domain/event_repository.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_page.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/shelf/shelf_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

// 轮5 批A（F5-1/F5-2）常驻回归。
// F5-1：本地导入落架后直达书架·全部段——机制钉在书架 boot 的一次性闸：
//   armed=true（常态）→ 按 read.openTab（默认「在读」）落段；
//   armed=false（commit 置位）→ 跳过一次、停在「全部」，闸自动复位。
// F5-2：**规格随时间模块批1 C2 演进（2026-10-13）**——月历展开态改为
//   「首次默认展开 · 手动切换持久化 · 与视图档解耦」，本组用例已按新规格重写：
//   默认展开/切档不改/手动收起写盘，**不再钉「块视图默认折叠」旧口径**。

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ReadRepository repo;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = ReadRepository(db);
  });
  tearDown(() async => db.close());

  group('F5-1 书架启动分区闸', () {
    Future<ProviderContainer> bootShelf(
        WidgetTester tester, List<Override> extra) async {
      await useSurface(tester, const Size(800, 2400));
      final container = ProviderContainer(overrides: [
        readRepositoryProvider.overrideWithValue(repo),
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...extra,
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Directionality(
                textDirection: TextDirection.ltr, child: const ShelfPage()),
          )));
      await settle5(tester);
      return container;
    }

    testWidgets('常态（armed）：boot 落「在读」默认分区', (tester) async {
      final container = await bootShelf(tester, const []);
      expect(container.read(shelfUiProvider).st, '在读',
          reason: '未设 read.openTab 时原型 BS_SET 默认「在读」仍生效');
    });

    testWidgets('commit 落架（armed=false）：停在「全部」且闸一次性消费复位',
        (tester) async {
      final container = await bootShelf(tester, [
        shelfUiProvider.overrideWith((ref) => const ShelfUI()),
        shelfOpenTabArmedProvider.overrideWith((ref) => false),
      ]);
      expect(container.read(shelfUiProvider).st, isNull,
          reason: '导入落架直达全部段：boot 不得把分区扳回「在读」');
      expect(container.read(shelfOpenTabArmedProvider), isTrue,
          reason: '闸只豁免这一次，之后进书架恢复 openTab 常态');
      expect(find.text('全部'), findsWidgets);
    });
  });

  group('F5-2 月历展开态（时间模块批1 C2 冻结：默认展开·与视图档解耦）', () {
    test('默认态：无用户配置 ⇒ 展开（首次默认展开，不再随块视图折叠）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ]);
      addTearDown(c.dispose);
      expect(c.read(calViewModeProvider), 'block');
      expect(c.read(monthExpandedProvider), isTrue,
          reason: 'C2：首次进模块默认展开（旧「块视图默认折叠」口径已作废）');
    });

    testWidgets('切档解耦：切轴/切回块不改展开态；手动收起写盘且跨切档保持',
        (tester) async {
      await useSurface(tester, const Size(390, 900));
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final bus = EventBus();
      addTearDown(bus.dispose);
      final container = ProviderContainer(overrides: [
        eventRepositoryProvider
            .overrideWithValue(EventRepository(EventDao(db), bus)),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
        timeBlockDaoProvider.overrideWithValue(TimeBlockDao(db)),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: const CalendarPage())));
      await settle5(tester);
      expect(container.read(monthExpandedProvider), isTrue,
          reason: '块视图进屏也是默认展开（C2）');

      // 切轴 → 展开态不变（解耦）。
      await tester.tap(find.byKey(const ValueKey('cal-view-switch')));
      await settle5(tester);
      await tester.tap(find.textContaining('轴').last);
      await settle5(tester);
      expect(container.read(calViewModeProvider), 'axis');
      expect(container.read(monthExpandedProvider), isTrue,
          reason: '切档不改展开态（C2 解耦）');

      // 手动收起：点选中日 toggle（写盘 B9）。空页无内容可滚，拖滚不产生滚动通知，
      // 不适合做触发器；点选中日是产品口径内的手动收/展入口。
      await tester.tap(find.byKey(const ValueKey('month-sel-cell')));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await settle5(tester);
      expect(container.read(monthExpandedProvider), isFalse, reason: '点选中日收起');
      // 写盘链收尾：pump 推帧且推 FakeAsync 时钟（Future.delayed 零时长 Timer 在 FakeAsync 下无驱动者，会挂）。
      await tester.pump(const Duration(milliseconds: 1));
      expect(prefs.getBool('lh.cal_month_expanded'), isFalse,
          reason: '手动切换持久化（B9 四处同步的落盘读数）');

      // 切回块 → 仍保持收起（跨切档记住，解耦）。
      await tester.tap(find.byKey(const ValueKey('cal-view-switch')));
      await settle5(tester);
      final blkItem = find.textContaining('块').last;
      await tester.tap(blkItem);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await settle5(tester);
      expect(container.read(calViewModeProvider), 'block');
      expect(container.read(monthExpandedProvider), isFalse,
          reason: '切档不再重推展开态（C2）');
    });
  });
}
