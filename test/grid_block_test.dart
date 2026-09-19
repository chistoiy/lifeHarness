import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/features/calendar/data/event_dao.dart';
import 'package:lifeharness/features/calendar/data/time_block_dao.dart';
import 'package:lifeharness/features/calendar/domain/cal_event.dart';
import 'package:lifeharness/features/calendar/domain/event_repository.dart';
import 'package:lifeharness/features/calendar/domain/time_block.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_page.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart';
import 'package:lifeharness/features/calendar/presentation/widgets/grid_day_view.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late TimeBlockDao dao;
  late EventRepository repo;
  late EventBus bus;
  final day = DateTime(2026, 9, 19);

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    dao = TimeBlockDao(db);
    bus = EventBus();
    repo = EventRepository(EventDao(db), bus, tbDao: dao);
  });

  tearDown(() async {
    await db.close();
    await bus.dispose();
  });

  group('TimeBlockDao', () {
    test('insert / listByDay / remove', () async {
      await dao.insert(TimeBlock(day: day, startMin: 540, endMin: 585, category: BlockCat.work, note: '晨间规划'));
      await dao.insert(TimeBlock(day: day, startMin: 1170, endMin: 1230, category: BlockCat.sport));
      await dao.insert(TimeBlock(day: day.add(const Duration(days: 1)), startMin: 600, endMin: 660));
      final list = await dao.listByDay(day);
      expect(list, hasLength(2));
      expect(list.first.startMin, 540); // start 升序
      expect(list.first.category, BlockCat.work);
      await dao.remove(list.first.id!);
      expect(await dao.listByDay(day), hasLength(1));
    });

    test('removeOverlapping 只删手动标记，不动 event 回填块', () async {
      await dao.insert(TimeBlock(day: day, startMin: 540, endMin: 600));
      await dao.insert(TimeBlock(day: day, startMin: 700, endMin: 760, source: 'event'));
      await dao.removeOverlapping(day, 500, 800);
      final left = await dao.listByDay(day);
      expect(left, hasLength(1));
      expect(left.single.source, 'event');
    });
  });

  test('v2→v3 迁移：time_blocks 建表且旧表数据保留', () async {
    final mem = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    // 构造最小 v2 世界：todos（已含 tag 列）+ 一条数据，无 time_blocks。
    await mem.execute('''
      CREATE TABLE ${DbSchema.tTodos} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, note TEXT,
        quadrant INTEGER NOT NULL DEFAULT 4, due_at INTEGER, remind_at INTEGER,
        done INTEGER NOT NULL DEFAULT 0, priority INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0, tag TEXT,
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
      )
    ''');
    final now = DateTime.now().millisecondsSinceEpoch;
    await mem.insert(DbSchema.tTodos, {'title': '旧任务', 'tag': 'x', 'created_at': now, 'updated_at': now});

    for (final sql in DbSchema.migrations[2]!) {
      await mem.execute(sql);
    }
    final tables = (await mem.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
        .map((r) => r['name'] as String).toSet();
    expect(tables, contains(DbSchema.tTimeBlocks));
    expect(await mem.query(DbSchema.tTodos), hasLength(1)); // 旧数据未动
    await mem.close();
  });

  test('endActive 回填 L4 时间块（source=event，覆盖同区间 mark）', () async {
    await dao.insert(TimeBlock(day: DateTime.now(), startMin: 0, endMin: 1440, category: BlockCat.fun, note: '占位'));
    await repo.startNow(CalEvent(title: '写周报', start: DateTime.now().subtract(const Duration(minutes: 30))));
    // startNow 强制 start=now，改为直接改库模拟 30 分钟前开始。
    await db.update(DbSchema.tEvents,
        {'start_at': DateTime.now().subtract(const Duration(minutes: 30)).millisecondsSinceEpoch},
        where: 'status = ?', whereArgs: [EventStatus.active.index]);
    final ended = await repo.endActive();
    expect(ended, isNotNull);
    final blocks = await dao.listByDay(DateTime.now());
    final eventBlock = blocks.where((b) => b.source == 'event').toList();
    expect(eventBlock, hasLength(1));
    expect(eventBlock.single.note, '写周报');
    expect(eventBlock.single.category, BlockCat.work);
    // 同区间全天占位 mark 被覆盖删除。
    expect(blocks.where((b) => b.source == 'mark'), isEmpty);
  });

  Widget app() => ProviderScope(
        overrides: [
          eventRepositoryProvider.overrideWithValue(repo),
          timeBlockDaoProvider.overrideWithValue(dao),
        ],
        child: const MaterialApp(home: CalendarPage()),
      );

  testWidgets('日视图子模式：切格子显示滑选提示与粒度下拉', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('时间轴'), findsOneWidget);
    await tester.tap(find.text('格子·时间块'));
    await tester.pumpAndSettle();
    expect(find.textContaining('拖动滑选 · 1 格 = 15 分钟'), findsOneWidget);
    expect(find.text('粒度'), findsOneWidget);

    // 切粒度 60 分钟 → 提示与格数变化（总面积固定）。
    await tester.tap(find.text('15 分钟'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('60 分钟').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('1 格 = 60 分钟'), findsOneWidget);
  });

  testWidgets('按住拖选多格 → 标记面板 → 确认写入时间块', (tester) async {
    // 独立挂载格子视图（排除外层折叠/滚动布局干扰，专注手势链路）。
    final container = ProviderContainer(overrides: [
      eventRepositoryProvider.overrideWithValue(repo),
      timeBlockDaoProvider.overrideWithValue(dao),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: GridDayView(day: DateTime.now()))),
    ));
    await tester.pumpAndSettle();

    final gridRect = tester.getRect(find.byType(GridView));
    final gesture = await tester.startGesture(Offset(gridRect.left + 10, gridRect.center.dy));
    await tester.pump();
    await gesture.moveBy(const Offset(110, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(110, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('标记时间块'), findsOneWidget);
    await tester.tap(find.text('学习'));
    await tester.pump();
    await tester.tap(find.text('确认标记'));
    await tester.pumpAndSettle();

    final blocks = await dao.listByDay(DateTime.now());
    expect(blocks, hasLength(1));
    expect(blocks.single.category, BlockCat.study);
    expect(blocks.single.endMin - blocks.single.startMin, greaterThan(15)); // 至少跨2格
  });
}
