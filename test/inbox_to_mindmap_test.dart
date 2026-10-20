import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/providers.dart'
    show sharedPreferencesProvider;
import 'package:lifeharness/features/inbox/data/inbox_dao.dart';
import 'package:lifeharness/features/inbox/domain/inbox_item.dart';
import 'package:lifeharness/features/inbox/presentation/inbox_providers.dart';
import 'package:lifeharness/features/inbox/presentation/inbox_page.dart';
import 'package:lifeharness/features/mindmap/data/mindmap_dao.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mindmap_test_harness.dart';

/// 收集箱第五向 · **→导图**（批P2 / 工单 §5 第 9 条 / 原型 S10）。
///
/// 口径：选目标图 → 条目文本成为该图**根节点下第一层**（挂到第一棵树的根），
/// 空图先补「中心主题」；原条目留在收集箱（`routed_to='mindmap'`），不删。
///
/// 注意：本页泵的是收集箱整页，而页面里带 AI/事件总线等既有依赖——只用
/// 最小 override（sharedPreferences）就能起来（与 `inbox_test` 同款）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late dynamic db;
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await openMmDb();
  });
  tearDown(() async {
    await (db as CloseableDb).close();
  });

  Future<void> pumpInbox(WidgetTester tester) async {
    // 两个 DAO 都必须注入**同一个 db 实例**（页面侧默认走
    // `AppDatabase.instance.db`，不 override 就是另一条内存库 ⇒ 列表恒空）。
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        inboxDaoProvider.overrideWithValue(InboxDao(db)),
        mindmapDaoProvider.overrideWithValue(MindmapDao(db)),
      ],
      child: const MaterialApp(home: InboxPage()),
    ));
    await tester.pumpAndSettle();
  }

  Future<int> seedItem(WidgetTester tester, String text) async {
    final id = await db.insert('inbox_items', InboxItem(
            rawText: text, createdAt: DateTime.now())
        .toRow());
    // 列表是 FutureProvider：插完必须让 provider 重算，否则页面还是空列表
    // （真机上插入走 _add 里那句 invalidate；测试里得自己补一次）。
    await pumpInbox(tester);
    return id;
  }

  Future<void> tapConvert(WidgetTester tester) async {
    final f = find.byKey(ValueKey('tri-→导图'));
    expect(f, findsWidgets, reason: '第五向按钮必须在条目卡上');
    await tester.ensureVisible(f.first);
    await tester.pumpAndSettle();
    await tester.tap(f.first);
    await tester.pumpAndSettle();
  }

  testWidgets('选目标图 → 条目成为该图根下第一层，原条目留在收集箱', (tester) async {
    final dao = MindmapDao(db);
    final mapId = await dao.createMap('本周复盘');
    final root = await dao.addNode(mapId: mapId, parentId: null, title: '中心主题');
    final itemId = await seedItem(tester, '试试把每天第一小时留给最难的那件事');
    await pumpInbox(tester);
    await tapConvert(tester);
    // 选图弹层：列出在册图（带节点数）。
    expect(find.byKey(ValueKey('ibk-mm-$mapId')), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('ibk-mm-$mapId')));
    await tester.pumpAndSettle();
    final nodes = await dao.nodesOf(mapId);
    final added = nodes.where((n) => n.title.startsWith('试试把每天')).toList();
    expect(added, hasLength(1), reason: '条目文本落成一枚节点');
    expect(added.first.parentId, root.id, reason: '挂在根节点下（第一层）');
    // 原条目还在收集箱未整理列表里，但打了 mindmap 分流标。
    final rows = await db.query('inbox_items', where: 'id = ?', whereArgs: [itemId]);
    expect(rows, hasLength(1), reason: '分流不删除条目');
    expect(rows.first['routed_to'], 'mindmap');
    expect(rows.first['routed_ref'], mapId);
  });

  testWidgets('空图（无任何节点）→ 先补「中心主题」再挂成第一层', (tester) async {
    final dao = MindmapDao(db);
    final mapId = await dao.createMap('空图');
    await seedItem(tester, '会议里冒出的念头');
    await pumpInbox(tester);
    await tapConvert(tester);
    await tester.tap(find.byKey(ValueKey('ibk-mm-$mapId')));
    await tester.pumpAndSettle();
    final nodes = await dao.nodesOf(mapId);
    final center = nodes.firstWhere((n) => n.title == '中心主题');
    final leaf = nodes.firstWhere((n) => n.title == '会议里冒出的念头');
    expect(center.parentId, isNull, reason: '补出来的中心主题是根');
    expect(leaf.parentId, center.id, reason: '条目挂在它下面');
  });

  testWidgets('还没有任何导图 → 给出人话提示，不建图也不动条目', (tester) async {
    final itemId = await seedItem(tester, '先别急');
    await pumpInbox(tester);
    await tapConvert(tester);
    expect(find.byKey(const ValueKey('ibk-mm-empty')), findsOneWidget);
    final rows = await db.query('inbox_items', where: 'id = ?', whereArgs: [itemId]);
    expect(rows.first['routed_to'], isNull, reason: '没选图就不分流');
  });

  testWidgets('多行条目：首行进标题，全文进备注', (tester) async {
    final dao = MindmapDao(db);
    final mapId = await dao.createMap('待办拆解');
    await dao.addNode(mapId: mapId, parentId: null, title: '中心主题');
    await seedItem(tester, '第一行是标题\n第二行是细节');
    await pumpInbox(tester);
    await tapConvert(tester);
    await tester.tap(find.byKey(ValueKey('ibk-mm-$mapId')));
    await tester.pumpAndSettle();
    final nodes = await dao.nodesOf(mapId);
    final n = nodes.firstWhere((x) => x.title == '第一行是标题');
    expect(n.note, contains('第二行是细节'), reason: '正文不丢，落在备注');
  });
}