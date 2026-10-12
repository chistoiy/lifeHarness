import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/mindmap/presentation/mindmap_canvas_page.dart';

import 'mindmap_test_harness.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;

/// 思维导图批1 · 删除安全守护（工单 §4b.3 ⑤：H1/F1-11/C1）。
/// 删节点＝二次确认且文案含连带子级数、取消＝零副作用、确认＝级联；
/// 删图入口在列表侧（map_mgmt 文件），本文件钉画布侧删除交互。
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

  /// 用读屏语义层定位「根」节点的屏幕位（fit 后位置不可预知，锚点不赌坐标）。
  Future<void> tapRoot(WidgetTester tester) async {
    final sema = find.byWidgetPredicate((w) =>
        w is Semantics && (w.properties.label ?? '').startsWith('根'));
    await tapAt(tester, tester.getRect(sema).center);
  }

  testWidgets('删节点二次确认：文案列明连带子级数；取消＝零副作用', (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    final root = await dao.addNode(mapId: mapId, title: '根');
    final c1 = await dao.addNode(mapId: mapId, parentId: root.id, title: '子1');
    await dao.addNode(mapId: mapId, parentId: c1.id, title: '孙');
    await tester.pumpWidget(ProviderScope(overrides: [sharedPreferencesProvider.overrideWithValue(mmPrefs)],
      child: MaterialApp(
          home: MindmapCanvasPage(mapId: mapId, dao: dao, db: db)),
    ));
    await tester.pumpAndSettle();
    // 选中根 → 更多 → 删除节点。
    await tapRoot(tester);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mm-tool-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mm-menu-del')));
    await tester.pumpAndSettle();
    // 确认文案含总数与子级数（根+子+孙＝3 个节点、含 2 个子节点）。
    expect(find.textContaining('将删除 3 个节点'), findsOneWidget);
    expect(find.textContaining('含 2 个子节点'), findsOneWidget);
    // C1：文案不出现「可撤销」（批 1 无撤销栈，不得虚诺）。
    expect(find.textContaining('可撤销'), findsNothing);
    // 取消＝零副作用。
    await tester.tap(find.byKey(const ValueKey('d-confirm-cancel')));
    await tester.pumpAndSettle();
    expect(await dao.nodesOf(mapId), hasLength(3));
    // 画布节点是 CustomPaint（无 Text widget），可见性钉读屏语义层。
    expect(
        find.byWidgetPredicate((w) =>
            w is Semantics && (w.properties.label ?? '').startsWith('孙')),
        findsOneWidget);
    // 确认＝根及全部后代移除。
    await tester.tap(find.byKey(const ValueKey('mm-tool-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mm-menu-del')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('d-confirm-ok')));
    await tester.pumpAndSettle();
    expect(await dao.nodesOf(mapId), isEmpty);
    expect(
        find.byWidgetPredicate((w) =>
            w is Semantics && (w.properties.label ?? '').startsWith('孙')),
        findsNothing);
  });

  testWidgets('折叠后删除长枝：确认文案只数可见外全部后代（含折叠子级）',
      (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    final root = await dao.addNode(mapId: mapId, title: '根');
    final c1 = await dao.addNode(mapId: mapId, parentId: root.id, title: '子1');
    await dao.addNode(mapId: mapId, parentId: c1.id, title: '孙');
    // 折叠「子1」——孙仍在库里，删除根时连带数必须按库里算（不是按可见算）。
    await dao.updateNode(c1.copyWith(folded: true, updatedAt: 2));
    await tester.pumpWidget(ProviderScope(overrides: [sharedPreferencesProvider.overrideWithValue(mmPrefs)],
      child: MaterialApp(
          home: MindmapCanvasPage(mapId: mapId, dao: dao, db: db)),
    ));
    await tester.pumpAndSettle();
    await tapRoot(tester);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mm-tool-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mm-menu-del')));
    await tester.pumpAndSettle();
    expect(find.textContaining('将删除 3 个节点'), findsOneWidget,
        reason: '折叠子级也计入连带（数据安全优先于视觉）');
  });
}
