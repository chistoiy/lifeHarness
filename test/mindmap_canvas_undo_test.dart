import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/mindmap/presentation/mindmap_canvas_page.dart';

import 'package:lifeharness/features/mindmap/data/mindmap_dao.dart';

import 'mindmap_test_harness.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;

/// 批2 F4-1 · 画布撤销/重做接线守护（工单 §4c.3 ① UI 面）。
/// 全 app widget 独立文件口径：本文件只泵画布页。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late dynamic db;
  late SharedPreferences mmPrefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mmPrefs = await SharedPreferences.getInstance();
    db = await openMmDb();
  });
  tearDown(() async {
    await (db as CloseableDb).close();
  });

  testWidgets('加根→撤销＝节点退场；重做＝按快照复原（栈 UI 闭环）',
      (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    await dao.addNode(mapId: mapId, title: '中心主题');
    await tester.pumpWidget(ProviderScope(overrides: [sharedPreferencesProvider.overrideWithValue(mmPrefs)],
      child: MaterialApp(
          home: MindmapCanvasPage(mapId: mapId, dao: dao, db: db)),
    ));
    await tester.pumpAndSettle();

    // 加一枚根节点。
    await tester.tap(find.byKey(const ValueKey('mm-add-root')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('mm-node-title')), '第二根');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mm-node-save')));
    await tester.pumpAndSettle();
    final mapIdOf = (await dao.listLive()).first.$1.id!;
    expect((await dao.nodesOf(mapIdOf)).length, 2);
    expect(tester.widget<IconButton>(
            find.byKey(const ValueKey('mm-undo-btn')))
        .onPressed, isNotNull, reason: '有可撤销步＝撤销钮可用');

    // 撤销：第二根退场（连带语义下当前无子级＝只退自身）。
    await tester.tap(find.byKey(const ValueKey('mm-undo-btn')));
    await tester.pumpAndSettle();
    expect((await dao.nodesOf(mapIdOf)).length, 1);
    expect((await dao.nodesOf(mapIdOf)).first.title, '中心主题');

    // 重做：按快照复原（显式 id 整行重插）。
    expect(tester.widget<IconButton>(
            find.byKey(const ValueKey('mm-redo-btn')))
        .onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('mm-redo-btn')));
    await tester.pumpAndSettle();
    final after = await dao.nodesOf(mapIdOf);
    expect(after.length, 2);
    expect(after.map((n) => n.title), containsAll(['中心主题', '第二根']));
  });

  testWidgets('编辑→撤销＝标题回写旧值（editNode 快照通道）', (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    await dao.addNode(mapId: mapId, title: '原名');
    await tester.pumpWidget(ProviderScope(overrides: [sharedPreferencesProvider.overrideWithValue(mmPrefs)],
      child: MaterialApp(
          home: MindmapCanvasPage(mapId: mapId, dao: dao, db: db)),
    ));
    await tester.pumpAndSettle();

    // 选中 → 更多 → 编辑节点 → 改名保存。
    await tapAt(tester,
        tester.getCenter(find.byKey(const ValueKey('mm-canvas-paint'))));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mm-tool-more')));
    await tester.pumpAndSettle();
    // 批P：节点菜单加到 12 项，600 高的测试视口里末项在折叠线外 ⇒ 先滚进来。
    await tester.ensureVisible(find.byKey(const ValueKey('mm-menu-edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mm-menu-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('mm-node-title')), '新名');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mm-node-save')));
    await tester.pumpAndSettle();
    final id = (await dao.nodesOf(mapId)).first.id!;
    expect((await dao.nodeById(id))!.title, '新名');

    // 撤销：回旧值。
    await tester.tap(find.byKey(const ValueKey('mm-undo-btn')));
    await tester.pumpAndSettle();
    expect((await dao.nodeById(id))!.title, '原名');
  });

  testWidgets('删节点（连带子级）→撤销＝整树复原带原 id', (tester) async {
    final dao = mindmapOf(db);
    final mapId = await dao.createMap('图');
    final root = await dao.addNode(mapId: mapId, title: '根');
    final child = await dao.addNode(mapId: mapId, parentId: root.id, title: '子');
    await tester.pumpWidget(ProviderScope(overrides: [sharedPreferencesProvider.overrideWithValue(mmPrefs)],
      child: MaterialApp(
          home: MindmapCanvasPage(mapId: mapId, dao: dao, db: db)),
    ));
    await tester.pumpAndSettle();

    // 选中根（fit 后内容垂直居中：两行总高 ~100，第一行在视口中心上方 ~25px）
    // → 更多 → 删除节点 → 确认（文案含连带子级数由 delete_safety 件担）。
    final c = tester.getCenter(find.byKey(const ValueKey('mm-canvas-paint')));
    await tapAt(tester, c - const Offset(0, 30));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mm-tool-more')));
    await tester.pumpAndSettle();
    // 批P：节点菜单加到 12 项，600 高的测试视口里末项在折叠线外 ⇒ 先滚进来。
    await tester.ensureVisible(find.byKey(const ValueKey('mm-menu-del')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mm-menu-del')));
    await tester.pumpAndSettle();
    // lhConfirm 确认钮（confirm_dialog 的 d-confirm-ok 键）。
    await tester.tap(find.byKey(const ValueKey('d-confirm-ok')));
    await tester.pumpAndSettle();
    expect(await dao.nodesOf(mapId), isEmpty);

    // 撤销：整树带原 id 复原。
    await tester.tap(find.byKey(const ValueKey('mm-undo-btn')));
    await tester.pumpAndSettle();
    final restored = await dao.nodesOf(mapId);
    expect(restored.length, 2);
    expect(restored.map((n) => n.id), containsAll([root.id, child.id]));
    expect(restored.firstWhere((n) => n.id == child.id).parentId, root.id);
  });
}

MindmapDao mindmapOf(dynamic db) => MindmapDao(db as CloseableDb);
