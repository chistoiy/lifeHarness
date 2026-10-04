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
// F5-2：日历展开初始值随视图档（块=折叠，其余=展开），切档重推。

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

  group('F5-2 日历展开随视图档', () {
    test('初始值：默认块视图＝折叠', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(calViewModeProvider), 'block');
      expect(c.read(monthExpandedProvider), isFalse);
    });

    testWidgets('切档重推：轴=展开、回块=折叠', (tester) async {
      await useSurface(tester, const Size(390, 900));
      final bus = EventBus();
      addTearDown(bus.dispose);
      final container = ProviderContainer(overrides: [
        eventRepositoryProvider
            .overrideWithValue(EventRepository(EventDao(db), bus)),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
        timeBlockDaoProvider.overrideWithValue(TimeBlockDao(db)),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: const CalendarPage())));
      await settle5(tester);
      expect(container.read(monthExpandedProvider), isFalse,
          reason: '块视图进屏日历默认折叠');

      await tester.tap(find.byKey(const ValueKey('cal-view-switch')));
      await settle5(tester);
      await tester.tap(find.textContaining('轴').last);
      await settle5(tester);
      expect(container.read(calViewModeProvider), 'axis');
      expect(container.read(monthExpandedProvider), isTrue,
          reason: '轴视图日历默认展开');

      await tester.tap(find.byKey(const ValueKey('cal-view-switch')));
      await settle5(tester);
      await tester.tap(find.textContaining('块').last);
      await settle5(tester);
      expect(container.read(monthExpandedProvider), isFalse,
          reason: '切回块视图重新推回折叠');
    });
  });
}
