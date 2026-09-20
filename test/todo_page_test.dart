import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_page.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late TodoRepository repo;
  late EventBus bus;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    bus = EventBus();
    repo = TodoRepository(TodoDao(db), bus);
  });

  tearDown(() async {
    await db.close();
    await bus.dispose();
  });

  Widget app() => ProviderScope(
        overrides: [todoRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: TodoPage()),
      );

  testWidgets('引导式两问 100% 落象限：重要+紧急 → Q1（原型单表单式）', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add).last); // FAB
    await tester.pumpAndSettle();
    expect(find.text('新建待办'), findsOneWidget);
    expect(find.text('引导式判象限（推荐）'), findsOneWidget);

    // 两张问卡各点一次 = 是
    await tester.tap(find.text('这件事重要吗？'));
    await tester.pump();
    await tester.tap(find.text('这件事紧急吗？'));
    await tester.pump();
    expect(find.text('是 ✓'), findsNWidgets(2));

    await tester.enterText(find.byType(TextField).first, '救火任务');
    await tester.tap(find.text('存入四象限'));
    await tester.pumpAndSettle();

    final saved = await repo.list();
    expect(saved.single.title, '救火任务');
    expect(saved.single.quadrant, Quadrant.q1);
    expect(find.text('已存入「重要且紧急」象限 ✓'), findsOneWidget);
  });

  testWidgets('勾选完成 → L2 联动 toast，任务划线保留', (tester) async {
    final t = await repo.add(Todo(title: '待办A', quadrant: Quadrant.q2));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // 原型 .chk 圆形勾选（key='chk-<id>'）
    await tester.tap(find.byKey(ValueKey('chk-${t.id}')));
    await tester.pumpAndSettle();

    final saved = await repo.list();
    expect(saved.single.done, isTrue);
    expect(find.text('完成 ✓ 已计入今日小结（联动 L2）'), findsOneWidget);
    expect(find.text('待办A'), findsOneWidget); // 全部筛选下沉底保留
  });

  testWidgets('四象限视图：提示条/格内计数/逾期图标', (tester) async {
    final now = DateTime.now();
    await repo.add(Todo(title: '逾期任务', quadrant: Quadrant.q1, dueAt: now.subtract(const Duration(hours: 2))));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('⏰ 1'), findsOneWidget); // AppBar 角标

    await tester.tap(find.text('四象限'));
    await tester.pumpAndSettle();
    expect(find.text('💡 长按卡片可拖到其他象限'), findsOneWidget);
    expect(find.text('重要且紧急'), findsOneWidget);
    expect(find.text('立即做 · 1 待办'), findsOneWidget);
    expect(find.text('逾期任务'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('详情弹层改判象限并持久化（原型 sheetTask q-move 即点即存）',
      (tester) async {
    final t = await repo.add(Todo(title: '改判任务', quadrant: Quadrant.q4));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('改判任务'));
    await tester.pumpAndSettle();
    // 原型 q-move 四短钮：立即做/计划做/委托/淘汰
    expect(find.text('委托'), findsOneWidget);
    expect(find.text('淘汰'), findsOneWidget);

    await tester.tap(find.text('委托'));
    await tester.pumpAndSettle();

    final list = await repo.list();
    expect(list.first.quadrant, Quadrant.q3);
    expect(t.id, isNotNull);
    expect(find.text('已改判为「紧急不重要」（拖拽同样可用）'), findsOneWidget);
  });
}
