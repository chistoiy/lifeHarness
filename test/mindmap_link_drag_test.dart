import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/mindmap/data/mindmap_dao.dart';
import 'package:lifeharness/features/mindmap/presentation/mindmap_canvas_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mindmap_test_harness.dart';

/// 思维导图批P2 · **右缘拖拽连接点**守护（工单 §5 第 4 条 / §12.2 第 1 条余留）。
///
/// 三坑同 `mindmap_connect_flow_test`（呼吸动画常开禁 pumpAndSettle、toast
/// 自动退场失效需 removeCurrentSnackBar、长菜单末项在折叠线外需 ensureVisible），
/// 本文件一律沿用同一套定长 pump 打法。
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

  Future<(MindmapDao, int)> pumpMap(WidgetTester tester,
      {required Future<void> Function(MindmapDao, int) seed}) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    await seed(dao, mapId);
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(mmPrefs)],
      child: MaterialApp(home: MindmapCanvasPage(mapId: mapId, dao: dao, db: db)),
    ));
    await tester.pumpAndSettle();
    return (dao, mapId);
  }

  /// 按标题取节点几何（读屏语义块与画布命中同源；精确匹配防前缀歧义）。
  Rect rectOf(WidgetTester tester, String title) {
    final f = find.byWidgetPredicate(
        (w) => w is Semantics && (w.properties.label ?? '') == title);
    expect(f, findsOneWidget, reason: '找不到「$title」的语义块');
    return tester.getRect(f);
  }

  /// 连接点在**视觉盒**右缘中点（语义块即节点盒，绘制层同坐标）。
  Offset knobOf(WidgetTester tester, String title) {
    final r = rectOf(tester, title);
    return Offset(r.right, r.center.dy);
  }

  Future<void> settleFrames(WidgetTester tester, {int frames = 30}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  String? parentTitleOf(List<dynamic> nodes, String title) {
    final n = nodes.firstWhere((x) => x.title == title);
    if (n.parentId == null) return null;
    return nodes.firstWhere((x) => x.id == n.parentId).title;
  }

  testWidgets('选中后拖右缘连接点到目标 ⇒ 挂接一步、可撤销', (tester) async {
    final (dao, mapId) = await pumpMap(tester, seed: (d, m) async {
      final a = await d.addNode(mapId: m, parentId: null, title: '甲');
      await d.addNode(mapId: m, parentId: a.id, title: '乙');
      await d.addNode(mapId: m, parentId: null, title: '丙');
    });
    // 先选中「乙」——连接点只在选中态出现（未选中时拖不出东西）。
    await tapAt(tester, rectOf(tester, '乙').center);
    await tester.pump();
    // 从连接点拖到「丙」盒心，中途逐帧推进（不能被当成单击）。
    final g = await tester.startGesture(knobOf(tester, '乙'));
    await tester.pump();
    await g.moveTo(rectOf(tester, '丙').center);
    await settleFrames(tester, frames: 6);
    await g.up();
    await settleFrames(tester, frames: 30);
    var nodes = await dao.nodesOf(mapId);
    expect(parentTitleOf(nodes, '乙'), '丙', reason: '拖到哪就挂到哪');
    // 一步可撤销：撤销回「挂在甲下」。
    await tester.tap(find.byKey(const ValueKey('mm-undo-btn')));
    await tester.pumpAndSettle();
    nodes = await dao.nodesOf(mapId);
    expect(parentTitleOf(nodes, '乙'), '甲', reason: '整次拖拽只算一步');
  });

  testWidgets('拖到空白松手 ⇒ 什么都不改（静默取消，不弹「已取消」）', (tester) async {
    final (dao, mapId) = await pumpMap(tester, seed: (d, m) async {
      final a = await d.addNode(mapId: m, parentId: null, title: '甲');
      await d.addNode(mapId: m, parentId: a.id, title: '乙');
    });
    await tapAt(tester, rectOf(tester, '乙').center);
    await tester.pump();
    final before = await dao.nodesOf(mapId);
    final g = await tester.startGesture(knobOf(tester, '乙'));
    await tester.pump();
    await g.moveTo(const Offset(30, 520)); // 画布空白区
    await settleFrames(tester, frames: 6);
    await g.up();
    await settleFrames(tester, frames: 30);
    final after = await dao.nodesOf(mapId);
    expect(parentTitleOf(after, '乙'), parentTitleOf(before, '乙'));
    expect(find.text('已取消连接'), findsNothing,
        reason: '拖错松手就散了，不为可预期操作弹提示');
  });

  testWidgets('拖到自己的子级 ⇒ 拒绝并给成环理由，树不变', (tester) async {
    final (dao, mapId) = await pumpMap(tester, seed: (d, m) async {
      final a = await d.addNode(mapId: m, parentId: null, title: '甲');
      final b = await d.addNode(mapId: m, parentId: a.id, title: '乙');
      await d.addNode(mapId: m, parentId: b.id, title: '丙');
    });
    // 起点＝甲（根，整枝含乙丙）：拖到丙＝会成环。
    await tapAt(tester, rectOf(tester, '甲').center);
    await tester.pump();
    final g = await tester.startGesture(knobOf(tester, '甲'));
    await tester.pump();
    await g.moveTo(rectOf(tester, '丙').center);
    await settleFrames(tester, frames: 6);
    await g.up();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('不能挂到自己的子节点下（会成环）'), findsOneWidget);
    final nodes = await dao.nodesOf(mapId);
    expect(parentTitleOf(nodes, '甲'), isNull, reason: '根没被挂走');
    expect(parentTitleOf(nodes, '丙'), '乙', reason: '子树原样');
  });

  testWidgets('未选中节点时连按都没得按（连接点只在选中态）', (tester) async {
    final (dao, mapId) = await pumpMap(tester, seed: (d, m) async {
      await d.addNode(mapId: m, parentId: null, title: '甲');
      await d.addNode(mapId: m, parentId: null, title: '乙');
    });
    // 不先选中，直接从「甲盒右缘」起手拖到乙：这一步只会被当成一次按下
    // （点空白取消选中 / 平移），绝不进连接态，因此不可能挂接成功。
    final r = rectOf(tester, '甲');
    final g = await tester.startGesture(Offset(r.right, r.center.dy));
    await tester.pump();
    await g.moveTo(rectOf(tester, '乙').center);
    await settleFrames(tester, frames: 6);
    await g.up();
    await settleFrames(tester, frames: 30);
    final nodes = await dao.nodesOf(mapId);
    expect(nodes.where((n) => n.parentId == null), hasLength(2),
        reason: '没进连接态就不会挂接');
  });

  testWidgets('连接点不吞节点右缘的普通点选（选中态下点盒内仍换选中）',
      (tester) async {
    final (dao, mapId) = await pumpMap(tester, seed: (d, m) async {
      final a = await d.addNode(mapId: m, parentId: null, title: '甲');
      await d.addNode(mapId: m, parentId: a.id, title: '乙');
      await d.addNode(mapId: m, parentId: null, title: '丙');
    });
    await tapAt(tester, rectOf(tester, '甲').center);
    await tester.pump();
    // 选中甲之后连接点在甲右缘；此时点丙盒心必须照常换选中（而不是起手拖线）。
    await tapAt(tester, rectOf(tester, '丙').center);
    await settleFrames(tester, frames: 10);
    final nodes = await dao.nodesOf(mapId);
    expect(nodes.where((n) => n.parentId == null), hasLength(2),
        reason: '只是换选中，没有任何挂接发生');
  });
}
