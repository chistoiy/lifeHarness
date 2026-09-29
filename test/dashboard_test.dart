import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/features/dashboard/presentation/dashboard_page.dart';
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/domain/journal_repository.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      todoRepositoryProvider.overrideWithValue(repo),
      // 心情打卡写今晚日记（L4），仪表盘测试需真实 journal 仓库。
      journalRepositoryProvider
          .overrideWithValue(JournalRepository(JournalDao(db))),
      // 主页卡片顺序读自 settingsControllerProvider（M0末C 编排）
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DashboardPage())));
    await tester.pumpAndSettle();
    expect(find.text('0'), findsWidgets); // 初始 0

    // 模拟待办页添加。R14-14 口径：问候卡只数「截止日＝今天」的待办，
    // 无截止日与逾期各有自己的入口，不混进这一格。
    final t = DateTime.now();
    await repo.add(Todo(
        title: '新任务',
        quadrant: Quadrant.q2,
        dueAt: DateTime(t.year, t.month, t.day, 18)));
    container.invalidate(todosProvider);
    await tester.pumpAndSettle();

    expect(find.text('1'), findsWidgets, reason: '待办数应从 0 变 1');
    await db.close();
  });

  testWidgets('心情行为原型 7 表情全量（V1.26 对齐：修 😪/😢 空位）', (tester) async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    final repo = TodoRepository(TodoDao(db), EventBus());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      todoRepositoryProvider.overrideWithValue(repo),
      // 心情打卡写今晚日记（L4），仪表盘测试需真实 journal 仓库。
      journalRepositoryProvider
          .overrideWithValue(JournalRepository(JournalDao(db))),
      // 主页卡片顺序读自 settingsControllerProvider（M0末C 编排）
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DashboardPage())));
    await tester.pumpAndSettle();

    for (final e in ['😄', '😌', '😐', '😪', '😰', '😢', '😡']) {
      expect(find.text(e), findsOneWidget, reason: '原型 moodRow 应有 7 个表情');
    }
    // 点选 → 记录反馈文案（原型 mood-on + moodTip）
    await tester.tap(find.text('😌'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已记录：平静'), findsOneWidget);
    await db.close();
  });

  testWidgets('仪表盘 FAB = 原型快捷记录菜单（5 项）', (tester) async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    final repo = TodoRepository(TodoDao(db), EventBus());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      todoRepositoryProvider.overrideWithValue(repo),
      // 心情打卡写今晚日记（L4），仪表盘测试需真实 journal 仓库。
      journalRepositoryProvider
          .overrideWithValue(JournalRepository(JournalDao(db))),
      // 主页卡片顺序读自 settingsControllerProvider（M0末C 编排）
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DashboardPage())));
    await tester.pumpAndSettle();

    expect(find.text('⚡ 记一条想法'), findsNothing); // 未展开
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    for (final item in ['⚡ 记一条想法', '✅ 记待办', '📔 记日记', '💰 记一笔', '📦 记物品']) {
      expect(find.text(item), findsOneWidget);
    }
    await db.close();
  });
}
