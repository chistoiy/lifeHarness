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

  testWidgets('引导式两问 100% 落象限：重要+紧急 → Q1', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('引导式录入'));
    await tester.pumpAndSettle();

    // 两问：重要 → 紧急
    await tester.tap(find.text('重要'));
    await tester.pump();
    await tester.tap(find.text('紧急'));
    await tester.pump();
    expect(find.text('已落入：重要且紧急'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '救火任务');
    await tester.tap(find.text('添加任务'));
    await tester.pumpAndSettle();

    final saved = await repo.list();
    expect(saved.single.title, '救火任务');
    expect(saved.single.quadrant, Quadrant.q1);
    expect(find.text('救火任务'), findsOneWidget);
  });

  testWidgets('勾选完成后沉底并可撤销', (tester) async {
    await repo.add(Todo(title: '待办A', quadrant: Quadrant.q2));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    final saved = await repo.list();
    expect(saved.single.done, isTrue);
    expect(find.text('已完成 (1)'), findsOneWidget);
  });

  testWidgets('四象限视图切换与逾期图标渲染', (tester) async {
    final now = DateTime.now();
    await repo.add(Todo(title: '逾期任务', quadrant: Quadrant.q1, dueAt: now.subtract(const Duration(hours: 2))));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('逾期 1'), findsOneWidget); // AppBar 角标

    await tester.tap(find.text('四象限'));
    await tester.pumpAndSettle();
    expect(find.text('重要且紧急'), findsOneWidget);
    expect(find.text('逾期任务'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });
}
