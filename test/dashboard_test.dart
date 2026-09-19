import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/features/dashboard/presentation/dashboard_page.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('待办新增 → 仪表盘「今天有 N 个待办」联动', (tester) async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    final repo = TodoRepository(TodoDao(db), EventBus());
    final container = ProviderContainer(
        overrides: [todoRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DashboardPage())));
    await tester.pumpAndSettle();
    expect(find.text('0'), findsWidgets); // 初始 0

    // 模拟待办页添加（无到期日，走同一 add + invalidate 链路）
    await repo.add(Todo(title: '新任务', quadrant: Quadrant.q2));
    container.invalidate(todosProvider);
    await tester.pumpAndSettle();

    expect(find.text('1'), findsWidgets, reason: '待办数应从 0 变 1');
    await db.close();
  });
}
