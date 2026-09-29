import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/features/calendar/data/event_dao.dart';
import 'package:lifeharness/features/calendar/data/category_dao.dart';
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
      await dao.insert(TimeBlock(day: day, startMin: 540, endMin: 585, catName: '工作', catId: 1, note: '晨间规划'));
      await dao.insert(TimeBlock(day: day, startMin: 1170, endMin: 1230, catName: '运动'));
      await dao.insert(TimeBlock(day: day.add(const Duration(days: 1)), startMin: 600, endMin: 660));
      final list = await dao.listByDay(day);
      expect(list, hasLength(2));
      expect(list.first.startMin, 540); // start 升序
      expect(list.first.catName, '工作');
      await dao.remove(list.first.id!);
      expect(await dao.listByDay(day), hasLength(1));
    });

    test('V1.27 C3 daysWithBlocks：返回月内有块的日集合（跨月不计）', () async {
      await dao.insert(TimeBlock(day: day, startMin: 540, endMin: 585, catName: '工作'));
      await dao.insert(TimeBlock(day: DateTime(2026, 9, 25), startMin: 600, endMin: 660));
      await dao.insert(TimeBlock(day: DateTime(2026, 10, 2), startMin: 600, endMin: 660));
      expect(await dao.daysWithBlocks(2026, 9), {19, 25});
      expect(await dao.daysWithBlocks(2026, 12), isEmpty); // 12月边界不炸
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

  test('markRange 拆分覆盖同步（V1.21：交叠段换分类·剩余保留·同类合并）', () async {
    await dao.markRange(day, 600, 660, catName: '睡眠');
    await dao.markRange(day, 620, 640, catName: '吃饭');
    final bs = await dao.listByDay(day);
    expect(bs.map((b) => '${b.catName}:${b.startMin}-${b.endMin}').toList(),
        ['睡眠:600-620', '吃饭:620-640', '睡眠:640-660']);
    // 相邻同类合并：再标 640-660 为吃饭 → 620-660 吃饭一段
    await dao.markRange(day, 640, 660, catName: '吃饭');
    final bs2 = await dao.listByDay(day);
    expect(bs2.map((b) => '${b.catName}:${b.startMin}-${b.endMin}').toList(),
        ['睡眠:600-620', '吃饭:620-660']);
  });

  test('endActive 回填 L4 时间块（source=event，覆盖同区间 mark）', () async {
    // 全部锚定「事件开始日」：00:00~00:30 跑时 now-30min 属于昨天，
    // 若拿今天做种/断言会跨日错位（原用例的零点窗口脆弱点）。
    final start = DateTime.now().subtract(const Duration(minutes: 30));
    await dao.insert(TimeBlock(day: start, startMin: 0, endMin: 1440, catName: '娱乐', note: '占位'));
    await repo.startNow(CalEvent(title: '写周报', start: start));
    // startNow 强制 start=now，改为直接改库模拟 30 分钟前开始。
    await db.update(DbSchema.tEvents,
        {'start_at': start.millisecondsSinceEpoch},
        where: 'status = ?', whereArgs: [EventStatus.active.index]);
    final ended = await repo.endActive();
    expect(ended, isNotNull);
    final blocks = await dao.listByDay(start);
    final eventBlock = blocks.where((b) => b.source == 'event').toList();
    expect(eventBlock, hasLength(1));
    expect(eventBlock.single.note, '写周报');
    expect(eventBlock.single.catName, '工作');
    // 同区间全天占位 mark 被覆盖删除。
    expect(blocks.where((b) => b.source == 'mark'), isEmpty);
  });

  Widget app() => ProviderScope(
        overrides: [
          eventRepositoryProvider.overrideWithValue(repo),
          timeBlockDaoProvider.overrideWithValue(dao),
          categoryDaoProvider.overrideWithValue(CategoryDao(db)),
        ],
        child: const MaterialApp(home: CalendarPage()),
      );

  testWidgets('时间页默认块视图：全天 0-24 刻度读数 + 视图菜单切轴显示事件', (tester) async {
    final now = DateTime.now();
    await repo.create(CalEvent(
        title: '产品评审',
        start: DateTime(now.year, now.month, now.day, 10),
        end: DateTime(now.year, now.month, now.day, 11)));
    // V1.27 C3：轴视图=事件+标记块同一数据源投影
    await dao.markRange(DateTime(now.year, now.month, now.day), 660, 720,
        catName: '休息', note: '午休');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // 默认块视图（V1.19 四视图，月历/周行在上方）。
    expect(find.textContaining('全天 0-24'), findsOneWidget);
    // V1.27 C6：月历不再显示「‹年 月 月›」切月行
    expect(find.textContaining('年'), findsNothing);
    // 顶栏视图菜单 → 轴视图。
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('☰ 轴 · 时间轴'));
    await tester.pumpAndSettle();
    expect(find.text('产品评审'), findsOneWidget);
    // V1.52：轴视图副行不再重复起止时间（刻度即开始时间）· 事件卡与块卡同文案
    expect(find.textContaining('点卡片修改起止/类型'), findsWidgets);
    // 块投影出现在时间轴（标题=备注/分类名）
    expect(find.textContaining('休息'), findsWidgets);
  });

  testWidgets('块视图：拖选保持选区 → 点右列分类=直接标记（免弹层）', (tester) async {
    final container = ProviderContainer(overrides: [
      eventRepositoryProvider.overrideWithValue(repo),
      timeBlockDaoProvider.overrideWithValue(dao),
      categoryDaoProvider.overrideWithValue(CategoryDao(db)),
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
    await tester.pump();

    // 不再弹标记面板，保持选区等待分类点选（V1.21）。
    expect(find.text('标记时间块'), findsNothing);
    expect(find.textContaining('点右侧分类直接标记'), findsOneWidget);
    await tester.tap(find.text('学习'));
    await tester.pumpAndSettle();

    final blocks = await dao.listByDay(DateTime.now());    expect(blocks.where((b) => b.catName == '学习'), hasLength(1));
    expect(blocks.first.endMin - blocks.first.startMin, greaterThan(15)); // 至少跨2格
  });

  testWidgets('V1.27 C4：块视图重复点击事件卡=只开详情，不扩散修改其他块', (tester) async {
    final now = DateTime.now();
    final d0 = DateTime(now.year, now.month, now.day);
    await repo.create(CalEvent(
        title: '事件A',
        start: DateTime(now.year, now.month, now.day, 9),
        end: DateTime(now.year, now.month, now.day, 10)));
    await dao.markRange(d0, 660, 720, catName: '休息');
    await dao.markRange(d0, 840, 900, catName: '工作');
    final before = (await dao.listByDay(d0))
        .map((b) => '${b.catName}:${b.startMin}-${b.endMin}')
        .toList();

    await tester.pumpWidget(UncontrolledProviderScope(
      container: ProviderContainer(overrides: [
        eventRepositoryProvider.overrideWithValue(repo),
        timeBlockDaoProvider.overrideWithValue(dao),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
      ]),
      child: MaterialApp(home: Scaffold(body: GridDayView(day: now))),
    ));
    await tester.pumpAndSettle();

    // 事件A 09:00-10:00 → 粒度15 时格 36~39，取格 37（09:15）中心点击。
    Future<void> tapEventCell() async {
      final rect = tester.getRect(find.byType(GridView));
      const gran = 15, cols = 9, gap = 3.0;
      final n = 1440 ~/ gran, rows = (n / cols).ceil();
      final cellW = (rect.width - gap * (cols - 1)) / cols;
      final cellH = (rect.height - gap * (rows - 1)) / rows;
      const i = 37;
      final c = Offset(rect.left + (i % cols) * (cellW + gap) + cellW / 2,
          rect.top + (i ~/ cols) * (cellH + gap) + cellH / 2);
      await tester.tapAt(c);
      await tester.pumpAndSettle();
    }

    await tapEventCell();
    // V1.52：点事件格=打开统一编辑弹层（不再是详情层）
    expect(find.text('编辑事件 / 时间块'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20)); // 遮罩关闭
    await tester.pumpAndSettle();

    // 第二次点击（此时无选块）→ 仍只开编辑弹层，库内块不受任何影响
    await tapEventCell();
    expect(find.text('编辑事件 / 时间块'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    final after = (await dao.listByDay(d0))
        .map((b) => '${b.catName}:${b.startMin}-${b.endMin}')
        .toList();
    expect(after, before); // 其他区域未被"事件A"改写
    expect(find.textContaining('已选'), findsNothing); // 选区不残留
  });
}
