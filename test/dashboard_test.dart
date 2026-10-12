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

import 'helpers.dart';

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
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
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
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
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

    expect(find.text('记一条想法'), findsNothing); // 未展开
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    for (final item in ['记一条想法', '记待办', '记日记', '记一笔', '记物品']) {
      expect(find.text(item), findsOneWidget);
    }
    await db.close();
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  // UIUX批（2026-10-12）：心情回填——旧实现 _mood 是纯内存态，切栏销毁即丢；
  // 现进页从当天日记读回最新打卡（DB 里已有就不显示未选）。
  testWidgets('心情回填：当天日记已有打卡 → 进页即显示选中（无需再点）', (tester) async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    final journalRepo = JournalRepository(JournalDao(db));
    // 先落一次打卡（写进当天日记），再进页。
    await journalRepo.setMoodOfDay(DateTime.now(), 2); // 2=平静
    final repo = TodoRepository(TodoDao(db), EventBus());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      todoRepositoryProvider.overrideWithValue(repo),
      journalRepositoryProvider.overrideWithValue(journalRepo),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DashboardPage())));
    await tester.pumpAndSettle();

    // 未点任何表情，反馈文案已在 = 回填成功。
    expect(find.textContaining('已记录：平静'), findsOneWidget);
    await db.close();
    await drainLogTimer(tester);
  });

  // UIUX批（2026-10-12）：编辑态吞卡片内部点按——点「收集箱」不再跳走
  //（裸 MaterialApp 无 GoRouter，跳走必抛异常＝天然红位；修复后吞点零异常）。
  testWidgets('编排态：点卡片内容不跳转（长按拖拽保留），仍在编排模式', (tester) async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    final repo = TodoRepository(TodoDao(db), EventBus());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      todoRepositoryProvider.overrideWithValue(repo),
      journalRepositoryProvider
          .overrideWithValue(JournalRepository(JournalDao(db))),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DashboardPage())));
    await tester.pumpAndSettle();

    // 长按收集箱卡 → 进编排模式（横幅＋toast 双命中，≥1 即成）。
    await tester.longPress(find.byKey(const ValueKey('card-press-inboxBar')));
    await tester.pumpAndSettle();
    expect(find.textContaining('编排模式'), findsWidgets);

    // 编辑态点卡片内容（收集箱行）——被吞点层拦截，不得触发导航。
    await tester.tap(find.textContaining('收集箱'), warnIfMissed: true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '编辑态点卡片内容不应触发跳转');
    // 编排横幅＋进入 toast 各一条，≥1 即在编排态（textContaining 会双命中）。
    expect(find.textContaining('编排模式'), findsWidgets,
        reason: '应仍在编排模式');
    await db.close();
    await drainLogTimer(tester);
  });

  // UIUX批（2026-10-12）：FAB 菜单开态盖遮罩，点空白处收起（旧实现无遮罩
  // ＋返回键退栈＝收不掉；遮罩收起是除再点 FAB 外的第二条路径）。
  testWidgets('FAB 菜单：点遮罩空白处收起', (tester) async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    final repo = TodoRepository(TodoDao(db), EventBus());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      todoRepositoryProvider.overrideWithValue(repo),
      journalRepositoryProvider
          .overrideWithValue(JournalRepository(JournalDao(db))),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DashboardPage())));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('记一条想法'), findsOneWidget);

    // 点遮罩（屏幕中上空白处，避开 FAB 与菜单项）→ 菜单收起。
    await tester.tapAt(const Offset(60, 200));
    await tester.pumpAndSettle();
    expect(find.text('记一条想法'), findsNothing);
    await db.close();
    await drainLogTimer(tester);
  });
}
