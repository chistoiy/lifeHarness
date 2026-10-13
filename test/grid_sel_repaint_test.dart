import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/calendar/data/category_dao.dart';
import 'package:lifeharness/features/calendar/data/time_block_dao.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart';
import 'package:lifeharness/features/calendar/presentation/widgets/grid_day_view.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';


/// F1-4（时间模块批1 · 冻结口径）块视图拖选隔离重绘：
/// 拖动全档全程，**网格 State 不整棵重建**（State.build 计数不增），
/// 只有进/出选区的格子各自重绘（格子构建计数为小增量，非全量 96 格）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late TimeBlockDao dao;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    dao = TimeBlockDao(db);
  });
  tearDown(() async => db.close());

  Future<DateTime> pumpGrid(WidgetTester tester) async {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day - 1);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        timeBlockDaoProvider.overrideWithValue(dao),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
      ],
      child: MaterialApp(home: Scaffold(body: GridDayView(day: day))),
    ));
    await tester.pumpAndSettle();
    return day;
  }

  testWidgets('拖选 3 格：State.build 计数不增 · 格子构建为小增量（非全量）',
      (tester) async {
    await pumpGrid(tester);
    final day = DateTime.now();

    GridDayView.debugStateBuilds = 0;
    GridDayView.debugCellBuilds = 0;

    final gridRect = tester.getRect(find.byType(GridView));
    final cellW = gridRect.width / 9; // 默认 15 分档：96 格 → cols=9
    final cellH = gridRect.height / 11; // rows=ceil(96/9)=11
    final start = gridRect.topLeft + Offset(cellW * 1.5, cellH * 1.5);
    final gesture = await tester.startGesture(start);
    await tester.pump();
    // 横向拖过 3 格（逐格经过，触发进/出选区通知）。
    for (var k = 1; k <= 3; k++) {
      await gesture.moveBy(Offset(cellW, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    // 网格 State 零重建（旧实现=整页 setState，拖 3 步至少 +4）。
    expect(GridDayView.debugStateBuilds, 0,
        reason: '拖选全程网格 State 不得整棵重建（F1-4）');
    // 格子构建为小增量：初始 96 格已在 pumpGrid 里计入，这里只数拖动增量。
    // 4 个格子进出选区（起点+3 步），每格 1-2 次通知 ⇒ 远小于全量 96。
    expect(GridDayView.debugCellBuilds, lessThan(96),
        reason: '只有受影响格重绘（F1-4 隔离）；整棵重建会是 96×拖动步数');
    expect(day, isNotNull); // 收口无未用告警
  });

  testWidgets('拖选后选区横幅可见且读数正确（选区功能回归护栏）', (tester) async {
    await pumpGrid(tester);

    final gridRect = tester.getRect(find.byType(GridView));
    final cellW = gridRect.width / 9;
    final cellH = gridRect.height / 11;
    final start = gridRect.topLeft + Offset(cellW * 0.5, cellH * 0.5);
    final gesture = await tester.startGesture(start);
    await tester.pump();
    await gesture.moveBy(Offset(cellW * 2, 0)); // 跨 3 格
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // 3 格 × 15 分 = 45 分钟。
    expect(find.textContaining('已选'), findsOneWidget);
    expect(find.textContaining('45 分钟'), findsOneWidget);
  });
}
