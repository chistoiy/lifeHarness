import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_page.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:lifeharness/features/todo/presentation/todo_trash_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// V1.57 E 批 · 垃圾箱屏与待办页入口（列表/恢复/彻底删除/批量/期限同源）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late TodoDao dao;
  late EventBus bus;
  late TodoRepository repo;
  late SharedPreferences prefs;

  /// 保留期天数走真实读盘路径（记录管理·通用同源），用例可按需改桩值。
  Future<void> boot({int keepDays = 30}) async {
    SharedPreferences.setMockInitialValues({'lh.trash_keep_days': keepDays});
    prefs = await SharedPreferences.getInstance();
  }

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    dao = TodoDao(db);
    bus = EventBus();
    repo = TodoRepository(dao, bus);
    await boot();
  });

  tearDown(() async {
    await db.close();
    await bus.dispose();
  });

  Future<Todo> seedTrash({String title = '删掉的活', Quadrant q = Quadrant.q1}) async {
    final t = await repo.add(Todo(title: title, quadrant: q));
    await repo.softRemove(t);
    return t;
  }

  Widget trashApp() => ProviderScope(
        overrides: [
          todoRepositoryProvider.overrideWithValue(repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(home: const TodoTrashPage()),
      );

  /// 待办页 → 垃圾箱（入口行用 context.push，需真路由）。
  Widget todoAppWithRouter() {
    final router = GoRouter(
      initialLocation: '/todo',
      routes: [
        GoRoute(path: '/todo', builder: (_, _) => const TodoPage()),
        GoRoute(path: '/todo/trash', builder: (_, _) => const TodoTrashPage()),
      ],
    );
    return ProviderScope(
      overrides: [
        todoRepositoryProvider.overrideWithValue(repo),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('空态与期限文案（与记录管理档位同源）', (tester) async {
    await tester.pumpWidget(trashApp());
    await settle5(tester);

    expect(find.text('暂无已删除的待办'), findsOneWidget);
    expect(find.textContaining('0 项 · 删除 30 天后自动彻底删除'), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('条目行：象限点＋标题＋删于时间＋剩 N 天＋行内两钮', (tester) async {
    final t = await seedTrash(title: '写月报', q: Quadrant.q2);
    await tester.pumpWidget(trashApp());
    await settle5(tester);

    expect(find.text('写月报'), findsOneWidget);
    expect(find.textContaining('1 项 · 删除 30 天后自动彻底删除'), findsOneWidget);
    expect(find.byKey(ValueKey('tt-qdot-${t.id}')), findsOneWidget);
    expect(find.textContaining('删于 '), findsOneWidget);
    expect(find.byKey(ValueKey('tt-left-${t.id}')), findsOneWidget);
    expect(find.text('剩 30 天'), findsOneWidget);
    expect(find.text('恢复'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    // 在册清单里不再有此条（垃圾箱不进清单）。
    expect(await dao.list(), isEmpty);
    await clearToasts(tester);
  });

  testWidgets('保留期内即将到界（剩≤7 天）标红；过期显「待清理」', (tester) async {
    await boot(keepDays: 7);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(DbSchema.tTodos, {
      'title': '五天前的',
      'created_at': now,
      'updated_at': now,
      'deleted_at': now - 5 * 24 * 3600 * 1000,
    });
    await db.insert(DbSchema.tTodos, {
      'title': '早过期的',
      'created_at': now,
      'updated_at': now,
      'deleted_at': now - 9 * 24 * 3600 * 1000,
    });
    await tester.pumpWidget(trashApp());
    await settle5(tester);

    final soon = find.text('剩 2 天');
    expect(soon, findsOneWidget);
    final style = tester.widget<Text>(soon).style!;
    expect(style.color, const Color(0xFFF43F5E), reason: '≤7 天玫红加粗');
    expect(style.fontWeight, FontWeight.w800);
    expect(find.text('待清理'), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('行内恢复：提示条报原象限名 · 条目回清单（同一条目）', (tester) async {
    final t = await seedTrash(title: '救火', q: Quadrant.q1);
    await tester.pumpWidget(trashApp());
    await settle5(tester);

    await tester.tap(find.byKey(ValueKey('tt-restore-${t.id}')));
    await settle5(tester);

    expect(find.textContaining('已恢复到「重要且紧急」'), findsOneWidget);
    expect(find.text('暂无已删除的待办'), findsOneWidget);
    final back = await dao.list();
    expect(back, hasLength(1));
    expect(back.single.id, t.id);
    expect(back.single.quadrant, Quadrant.q1);
    await clearToasts(tester);
  });

  testWidgets('彻底删除：确认弹层列出条目 → 真删 + 提示条', (tester) async {
    final t = await seedTrash(title: '不可回收', q: Quadrant.q3);
    await tester.pumpWidget(trashApp());
    await settle5(tester);

    await tester.tap(find.byKey(ValueKey('tt-del-${t.id}')));
    await settle5(tester);
    expect(find.text('彻底删除'), findsNWidgets(2)); // 弹层标题 + 确认钮
    expect(find.text('共 1 条 · 删除后不可恢复'), findsOneWidget);
    expect(find.byKey(ValueKey('tp-item-${t.id}')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tp-go')));
    await settle5(tester);

    expect(find.textContaining('已彻底删除 1 条'), findsOneWidget);
    expect(await db.query(DbSchema.tTodos), isEmpty, reason: '彻底删除＝真 DELETE');
    await clearToasts(tester);
  });

  testWidgets('取消确认弹层不动数据', (tester) async {
    final t = await seedTrash(title: '留下');
    await tester.pumpWidget(trashApp());
    await settle5(tester);
    await tester.tap(find.byKey(ValueKey('tt-del-${t.id}')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('tp-cancel')));
    await settle5(tester);
    expect(await dao.trashed(), hasLength(1));
    await clearToasts(tester);
  });

  testWidgets('选择 → 全选 → 批量恢复（提示条按批量口径）', (tester) async {
    final a = await seedTrash(title: '甲', q: Quadrant.q1);
    final b = await seedTrash(title: '乙', q: Quadrant.q4);
    await tester.pumpWidget(trashApp());
    await settle5(tester);

    await tester.tap(find.byKey(const ValueKey('tt-pick')));
    await settle5(tester);
    expect(find.text('取消'), findsOneWidget); // 按钮文案自解释切换
    expect(find.byKey(ValueKey('tt-chk-${a.id}')), findsOneWidget);
    expect(find.text('恢复'), findsNothing, reason: '选择态收起行内钮，改走底栏');

    await tester.tap(find.byKey(const ValueKey('tt-all')));
    await settle5(tester);
    expect(find.text('已选 2 项'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tt-restore-batch')));
    await settle5(tester);
    expect(find.textContaining('已恢复 2 项到原象限'), findsOneWidget);
    final back = await dao.list();
    expect(back.map((t) => t.title).toSet(), {'甲', '乙'});
    expect(back.firstWhere((t) => t.id == b.id).quadrant, Quadrant.q4);
    await clearToasts(tester);
  });

  testWidgets('长按条目进多选 · 单条点选可 toggle', (tester) async {
    final a = await seedTrash(title: '长按我');
    final b = await seedTrash(title: '顺便我');
    await tester.pumpWidget(trashApp());
    await settle5(tester);

    await tester.longPress(find.byKey(ValueKey('tt-row-${a.id}')));
    await settle5(tester);
    expect(find.text('已选 1 项'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('tt-row-${b.id}')));
    await settle5(tester);
    expect(find.text('已选 2 项'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('tt-row-${b.id}')));
    await settle5(tester);
    expect(find.text('已选 1 项'), findsOneWidget);

    // 底栏 ✕ 退出多选，行内钮回来
    await tester.tap(find.byKey(const ValueKey('tt-sel-exit')));
    await settle5(tester);
    expect(find.byKey(ValueKey('tt-restore-${a.id}')), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('批量彻底删除走同一确认弹层（列出全部选中项）', (tester) async {
    final a = await seedTrash(title: '一并删1');
    final b = await seedTrash(title: '一并删2');
    await tester.pumpWidget(trashApp());
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('tt-pick')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('tt-all')));
    await settle5(tester);

    await tester.tap(find.byKey(const ValueKey('tt-purge-batch')));
    await settle5(tester);
    expect(find.text('共 2 条 · 删除后不可恢复'), findsOneWidget);
    expect(find.byKey(ValueKey('tp-item-${a.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('tp-item-${b.id}')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tp-go')));
    await settle5(tester);
    expect(find.textContaining('已彻底删除 2 条'), findsOneWidget);
    expect(await db.query(DbSchema.tTodos), isEmpty);
    await clearToasts(tester);
  });

  testWidgets('待办页底部入口行：计数＋期限同源，点击进垃圾箱', (tester) async {
    await seedTrash(title: '入口计数');
    await tester.pumpWidget(todoAppWithRouter());
    await settle5(tester);

    final entry = find.byKey(const ValueKey('todo-trash-entry'));
    expect(entry, findsOneWidget);
    expect(find.byKey(const ValueKey('todo-trash-meta')),
        findsOneWidget); // 文本随 provider 异步落定，下面按内容断言
    await tester.tap(entry);
    await settle5(tester);

    expect(find.text('删除的待办 · 保留期内可恢复'), findsOneWidget);
    expect(find.text('入口计数'), findsOneWidget);
    expect(find.textContaining('1 项 · 删除 30 天后自动彻底删除'), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('待办详情「删除」＝软删：提示条读真档位 · 入口行计数同步', (tester) async {
    final t = await repo.add(Todo(title: '删它', quadrant: Quadrant.q2));
    await tester.pumpWidget(todoAppWithRouter());
    await settle5(tester);

    await tester.tap(find.byKey(ValueKey('todo-${t.id}')));
    await settle5(tester);
    await tester.tap(find.text('🗑 删除'));
    await settle5(tester);

    expect(find.textContaining('已移入垃圾箱 · 删除 30 天后自动彻底删除'), findsOneWidget,
        reason: '文案读「记录管理」档位，不再写「规划 V1.0」');
    expect(find.byKey(ValueKey('todo-${t.id}')), findsNothing, reason: '在册清单即时消失');
    expect(find.textContaining('1 项 · 删除 30 天后自动彻底删除'), findsOneWidget,
        reason: '入口行计数与期限同源刷新');
    expect(await dao.list(), isEmpty);
    expect(await dao.trashed(), hasLength(1));
    await clearToasts(tester);
  });

  testWidgets('设置档位改 7 天 → 屏内与入口文案同步（不各写各的）', (tester) async {
    await boot(keepDays: 7);
    await seedTrash(title: '七天档');
    await tester.pumpWidget(trashApp());
    await settle5(tester);
    expect(find.textContaining('1 项 · 删除 7 天后自动彻底删除'), findsOneWidget);
    expect(find.text('剩 7 天'), findsOneWidget);
    await clearToasts(tester);
  });
}
