import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/calendar/data/category_dao.dart';
import 'package:lifeharness/features/calendar/data/time_block_dao.dart';
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
  final day = DateTime(2026, 9, 19);

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    dao = TimeBlockDao(db);
  });

  tearDown(() async {
    await db.close();
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

  // B10（2026-10-13 裁决）：原「endActive 回填 L4」用例随 events 两态流退役整段删除
  // ——两态流已由时间块计时（V1.52）取代，旧数据并入守卫见 time_legacy_merge_test。

  Widget app() => ProviderScope(
        overrides: [
          timeBlockDaoProvider.overrideWithValue(dao),
          legacyEventMergeDbProvider.overrideWithValue(db),
          categoryDaoProvider.overrideWithValue(CategoryDao(db)),
          // 批1 C2：块视图旧前提=折叠（默认展开会使格子沉到折叠线下），显式给。
          monthExpandedProvider.overrideWith((ref) => false),
        ],
        child: const MaterialApp(home: CalendarPage()),
      );

  testWidgets('时间页默认块视图：全天 0-24 刻度读数 + 视图菜单切轴显示块卡', (tester) async {
    final now = DateTime.now();
    // B10：种子由事件改块（块单源；轴卡标题=note）。
    await dao.markRange(DateTime(now.year, now.month, now.day), 600, 660,
        catName: '工作', note: '产品评审');
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
    // V1.52：轴视图副行不再重复起止时间（刻度即开始时间）
    expect(find.textContaining('点卡片修改起止/类型'), findsWidgets);
    // 块投影出现在时间轴（标题=备注/分类名）
    expect(find.textContaining('休息'), findsWidgets);
  });

  testWidgets('块视图：拖选保持选区 → 点右列分类=直接标记（免弹层）', (tester) async {
    final container = ProviderContainer(overrides: [
      timeBlockDaoProvider.overrideWithValue(dao),
      legacyEventMergeDbProvider.overrideWithValue(db),
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

  testWidgets('V1.27 C4：块视图重复点击块格=只开编辑弹层，不扩散修改其他块', (tester) async {
    final now = DateTime.now();
    final d0 = DateTime(now.year, now.month, now.day);
    await dao.markRange(d0, 540, 600, catName: '工作', note: '块A');
    await dao.markRange(d0, 660, 720, catName: '休息');
    await dao.markRange(d0, 840, 900, catName: '工作');
    final before = (await dao.listByDay(d0))
        .map((b) => '${b.catName}:${b.startMin}-${b.endMin}')
        .toList();

    await tester.pumpWidget(UncontrolledProviderScope(
      container: ProviderContainer(overrides: [
        timeBlockDaoProvider.overrideWithValue(dao),
        legacyEventMergeDbProvider.overrideWithValue(db),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
      ]),
      child: MaterialApp(home: Scaffold(body: GridDayView(day: now))),
    ));
    await tester.pumpAndSettle();

    // 块A 09:00-10:00 → 粒度15 时格 36~39，取格 37（09:15）中心点击。
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
    // V1.52：点块格=打开统一编辑弹层
    expect(find.text('编辑时间块'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20)); // 遮罩关闭
    await tester.pumpAndSettle();

    // 第二次点击（此时无选块）→ 仍只开编辑弹层，库内块不受任何影响
    await tapEventCell();
    expect(find.text('编辑时间块'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    final after = (await dao.listByDay(d0))
        .map((b) => '${b.catName}:${b.startMin}-${b.endMin}')
        .toList();
    expect(after, before); // 其他区域未被"块A"改写
    expect(find.textContaining('已选'), findsNothing); // 选区不残留
  });
}
