import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/mindmap/presentation/mindmap_canvas_page.dart';

import 'package:lifeharness/features/mindmap/data/mindmap_dao.dart';

import 'mindmap_test_harness.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;

/// 思维导图批1 · 画布节点操作交互守护（工单 §4b.3 ⑥ 交互面）。
/// 全 app widget 独立文件口径：本文件只泵画布页，不与其它大页共处。
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

  Future<MindmapDao> seed(WidgetTester tester,
      {required Future<void> Function(WidgetTester) act}) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    await dao.addNode(mapId: mapId, title: '中心主题');
    await tester.pumpWidget(ProviderScope(overrides: [sharedPreferencesProvider.overrideWithValue(mmPrefs)],
      child: MaterialApp(
          home: MindmapCanvasPage(mapId: mapId, dao: dao, db: db)),
    ));
    await tester.pumpAndSettle();
    return dao;
  }

  testWidgets('编辑节点：弹层读回标题＋备注并可改写（H2）', (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    final root =
        await dao.addNode(mapId: mapId, title: '要编辑的', note: '原始备注');
    await tester.pumpWidget(ProviderScope(overrides: [sharedPreferencesProvider.overrideWithValue(mmPrefs)],
      child: MaterialApp(
          home: MindmapCanvasPage(mapId: mapId, dao: dao, db: db)),
    ));
    await tester.pumpAndSettle();
    // 选中（中心主题在 fit 后视口中央）→ 更多 → 编辑节点。
    await tapAt(tester, tester.getCenter(find.byKey(const ValueKey('mm-canvas-paint'))));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mm-bubble-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mm-menu-edit')));
    await tester.pumpAndSettle();
    // 读回断言（H2 核心：标题＋备注都回显）。
    expect(find.text('要编辑的'), findsWidgets);
    final noteField = tester.widget<TextField>(
        find.byKey(const ValueKey('mm-node-note')));
    expect(noteField.controller!.text, '原始备注');
    final titleField = tester.widget<TextField>(
        find.byKey(const ValueKey('mm-node-title')));
    expect(titleField.controller!.text, '要编辑的');
    // 改写并保存 → DAO 读回。
    await tester.enterText(
        find.byKey(const ValueKey('mm-node-title')), '改后的标题');
    await tester.enterText(
        find.byKey(const ValueKey('mm-node-note')), '改后的备注');
    await tester.tap(find.byKey(const ValueKey('mm-node-save')));
    await tester.pumpAndSettle();
    final back = await dao.nodeById(root.id!);
    expect(back!.title, '改后的标题');
    expect(back.note, '改后的备注');
  });

  testWidgets('空标题拦截（B8）：清空标题＝保存禁用＋提示行出现', (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    await dao.addNode(mapId: mapId, title: '根');
    await tester.pumpWidget(ProviderScope(overrides: [sharedPreferencesProvider.overrideWithValue(mmPrefs)],
      child: MaterialApp(
          home: MindmapCanvasPage(mapId: mapId, dao: dao, db: db)),
    ));
    await tester.pumpAndSettle();
    await tapAt(tester, tester.getCenter(find.byKey(const ValueKey('mm-canvas-paint'))));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mm-bubble-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mm-menu-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('mm-node-title')), '');
    await tester.pumpAndSettle();
    final save = tester.widget<FilledButton>(
        find.byKey(const ValueKey('mm-node-save')));
    expect(save.onPressed, isNull, reason: '空标题＝禁止保存（B8）');
    expect(find.byKey(const ValueKey('mm-node-empty-hint')), findsOneWidget);
  });

  testWidgets('点空白取消选中（B5 改口径）：贴点气泡随之消失', (tester) async {
    await seed(tester, act: (_) async {});
    final canvasCenter =
        tester.getCenter(find.byKey(const ValueKey('mm-canvas-paint')));
    // 选中：气泡在，两枚都可点。
    await tapAt(tester, canvasCenter);
    await tester.pump();
    expect(find.byKey(const ValueKey('mm-bubble-child')), findsOneWidget);
    final ink =
        tester.widget<InkWell>(find.byKey(const ValueKey('mm-bubble-more')));
    expect(ink.onTap, isNotNull);
    // 点空白（视口左上角落）＝取消选中 → 气泡整体消失（批P5：不再有常驻工具条
    // 靠置灰表达「不可用」，没选中就等于没有这组操作）。
    await tapAt(tester, const Offset(24, 90));
    await tester.pump();
    expect(find.byKey(const ValueKey('mm-bubble-more')), findsNothing,
        reason: '无选中时气泡不渲染（F1-10 的新表达）');
    expect(find.byKey(const ValueKey('mm-bubble-child')), findsNothing);
  });

  testWidgets('加根节点入口在 AppBar：经弹层生成第二根（F1-4 交互面）',
      (tester) async {
    final dao = await seed(tester, act: (_) async {});
    await tester.tap(find.byKey(const ValueKey('mm-add-root')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('mm-node-title')), '第二根');
    await tester.pump(); // onChanged→setS 重建后保存键才 enabled（初始空标题）
    await tester.tap(find.byKey(const ValueKey('mm-node-save')));
    await tester.pumpAndSettle();
    final nodes = await dao.nodesOf((await dao.listLive()).first.$1.id!);
    expect(nodes.where((n) => n.parentId == null), hasLength(2));
    // 画布节点是 CustomPaint（无 Text widget），可见性钉读屏语义层。
    expect(
        find.byWidgetPredicate((w) =>
            w is Semantics && (w.properties.label ?? '').startsWith('第二根')),
        findsOneWidget);
  });
}
