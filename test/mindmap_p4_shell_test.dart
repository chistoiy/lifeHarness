import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/mindmap/presentation/mindmap_canvas_page.dart';
import 'package:lifeharness/features/mindmap/presentation/mindmap_sheets.dart';
import 'package:lifeharness/shared/linkage/mindmap_mounts.dart';

import 'mindmap_test_harness.dart';

/// 批P4 · 思维导图收口三件：顶栏口径、浮层让开状态栏、搜索挂载节点入口。
///
/// 本文件只泵画布页/弹层（全 app widget 测试一文件一页口径）。
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

  Future<void> pumpCanvas(
    WidgetTester tester,
    int mapId, {
    int? focusNodeId,
    double topInset = 0,
  }) async {
    final dao = mindmapDaoOf(db);
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        // 状态栏高度只能在 MaterialApp 之上盖——直接包外层会被它自己的
        // MediaQuery 覆盖掉，浮层就永远读不到 topInset。
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(padding: EdgeInsets.only(top: topInset)),
          child: child!,
        ),
        home: MindmapCanvasPage(
            mapId: mapId, focusNodeId: focusNodeId, dao: dao, db: db),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tapNode(WidgetTester tester, String title) async {
    final f = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == title);
    expect(f, findsOneWidget, reason: '画布语义层应能找到节点「$title」');
    await tapAt(tester, tester.getCenter(f));
  }

  testWidgets('画布顶栏：标题贴左、不占返回键位（对齐他模块主屏）', (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('我的导图');
    await dao.addNode(mapId: mapId, title: '中心主题');
    await pumpCanvas(tester, mapId);

    final bar = tester.widget<AppBar>(find.byType(AppBar));
    expect(bar.automaticallyImplyLeading, isFalse,
        reason: 'care/days/goals/items 主屏都这么写，画布不该是唯一例外');
    expect(find.text('我的导图'), findsOneWidget, reason: '标题仍在，只是不再被返回键顶到右边');
  });

  testWidgets('节点菜单浮层：顶边让开状态栏（6201 真机：标题行被时钟遮）', (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    await dao.addNode(mapId: mapId, title: '中心主题');
    await pumpCanvas(tester, mapId, topInset: 30);

    await tapNode(tester, '中心主题');
    await tester.tap(find.byKey(const ValueKey('mm-tool-more')));
    await tester.pumpAndSettle();

    final panel = find.byKey(const ValueKey('mm-node-menu'));
    expect(panel, findsOneWidget);
    final top = tester.getRect(panel).top;
    // 状态栏 30 ＋ 8dp 呼吸 = 下限 38；菜单撑满时正是顶到这条线。
    expect(top, greaterThanOrEqualTo(38),
        reason: '菜单不能伸进状态栏（否则标题行被时钟压住）');
  });

  testWidgets('搜索挂载节点：跨图命中节点标题，点行回传该行', (tester) async {
    final dao = mindmapDaoOf(db);
    final mapA = await dao.createMap('图甲');
    await dao.addNode(mapId: mapA, title: '深度工作');
    final mapB = await dao.createMap('图乙');
    await dao.addNode(mapId: mapB, title: '浅层工作');

    MmSearchHit? picked;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const ValueKey('open-search'),
              onPressed: () async {
                picked = await showMmSearchSheet(ctx, db: db);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('open-search')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mm-search-sheet')), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('mm-search-input')), '深度');
    await tester.pumpAndSettle();
    expect(find.text('深度工作'), findsOneWidget, reason: '甲图的节点命中');
    expect(find.text('浅层工作'), findsNothing, reason: '乙图的节点不该命中');

    await tester.tap(find.text('深度工作'));
    await tester.pumpAndSettle();
    expect(picked, isNotNull);
    expect(picked!.mapId, mapA, reason: '回传要带图 id，列表页据此跳画布');
    expect(picked!.nodeTitle, '深度工作');
  });

  testWidgets('搜索挂载节点：无命中给一句话，不留空白屏', (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    await dao.addNode(mapId: mapId, title: '中心主题');

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const ValueKey('open-search'),
              onPressed: () => showMmSearchSheet(ctx, db: db),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('open-search')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('mm-search-input')), '不存在的东西');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的挂载节点'), findsOneWidget);
  });

  testWidgets('深链定位：带 node 参数进图即选中该节点（搜索跳转落点）', (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    final root = await dao.addNode(mapId: mapId, title: '中心主题');
    final child = await dao.addNode(
        mapId: mapId, parentId: root.id, title: '被命中的节点');
    await pumpCanvas(tester, mapId, focusNodeId: child.id);

    // 选中态判据＝底部工具条可用（未选中时三枚全置灰）。
    final bind = tester.widget<InkWell>(
        find.byKey(const ValueKey('mm-tool-bind')));
    expect(bind.onTap, isNotNull, reason: '带 node 进图应已选中该节点');

    // 且被摆到视口中心附近（不是按整图 fit 的左上角）。
    final sem = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == '被命中的节点');
    final c = tester.getCenter(sem);
    expect((c.dx - 400).abs(), lessThan(120), reason: '水平居中');
    expect((c.dy - 300).abs(), lessThan(120), reason: '垂直居中');
  });
}
