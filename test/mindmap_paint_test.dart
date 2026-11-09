import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_layout.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_models.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_style.dart';
import 'package:lifeharness/features/mindmap/presentation/mindmap_painter.dart';

/// 思维导图批P · 绘制层守护（工单 §7 L1/L3/L5 + P1 连接态）。
/// 只吃 painter 的**输入与画法分派**（不进光栅）——这两样是可断言的，
/// 「颜色对不对」留给四主题 CDP 深链实拍（原型轮已核）。
MindmapNode _n(int id, {int? parent}) => MindmapNode(
      id: id,
      mapId: 1,
      parentId: parent,
      title: '节点$id',
      sort: 0,
      createdAt: 1,
      updatedAt: 1,
    );

/// 画一帧不炸（任何一条 path 公式写错都会在这里抛出来，而不是到真机上白屏）。
void _paintFrame(MmCanvasPainter p) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  p.paint(canvas, const Size(400, 400));
  recorder.endRecording().dispose();
}

MmPaintStyle _style() => MmPaintStyle.of(null, const ColorScheme.light());

MmLayoutResult _layout(List<MindmapNode> nodes) => MmLayoutResult(
      baseline: {for (final n in nodes) n.id!: Offset.zero},
      sizes: {for (final n in nodes) n.id!: const Size(120, 40)},
      assignedSides: const {},
    );

MmCanvasPainter _painter(List<MindmapNode> nodes,
    {MmLayoutResult? layout,
    Set<int>? focus,
    Map<int, int>? depths,
    Set<int>? targets,
    Set<int>? blocked,
    double pulse = 0}) =>
    MmCanvasPainter(
      nodes: nodes,
      layout: layout ?? _layout(nodes),
      scale: 1,
      pan: Offset.zero,
      selectedId: null,
      nodeTitles: {for (final n in nodes) n.id!: n.title},
      mountedIds: const {},
      dxs: const {},
      dys: const {},
      style: _style(),
      depths: depths ?? {for (final n in nodes) n.id!: 0},
      focusIds: focus ?? const {},
      connectTargetIds: targets ?? const {},
      connectBlockedIds: blocked ?? const {},
      connectPulse: pulse,
    );

Rect _rectAt(MindmapNode n) => Offset((n.id! - 1) * 160.0, 0) & const Size(120, 40);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('主干判定：只有父＝根的边被标 fromRoot（L1 加粗的对象）', () {
    //   1(根)
    //  ├─2
    //  └─6(根) ── 3
    final nodes = [_n(1), _n(2, parent: 1), _n(6), _n(3, parent: 6)];
    final rs = mmEdgeRoutes(
      nodes: nodes,
      edgeKind: MmEdgeKind.stair,
      assignedSides: const {},
      rectOf: _rectAt,
    );
    final root = rs.where((r) => r.fromRoot).map((r) => r.childId).toSet();
    expect(root, {2, 3}, reason: '两条主干的子端；第三枚根没有父子边');
    expect(rs.length, 2, reason: '只有两条父子边（第三枚根单着）');
    for (final r in rs) {
      expect(r.points.length, 4, reason: 'stair 走阶梯贝塞尔，不是两点直线');
    }
  });

  test('画法分派：放射/分支仍是两点直线（套阶梯公式＝斜穿节点）', () {
    final nodes = [_n(1), _n(2, parent: 1)];
    for (final kind in [MmEdgeKind.branch, MmEdgeKind.radial]) {
      final rs = mmEdgeRoutes(
        nodes: nodes,
        edgeKind: kind,
        assignedSides: const {},
        rectOf: (n) => Offset.zero & const Size(120, 40),
      );
      expect(rs.single.isStraight, isTrue);
    }
  });

  test('第 5 层起连线几何不穿盒：stair 首末点落在父边/子边外沿', () {
    // 深链 1→2→3→4→5：最末一段（第 4 层→第 5 层）是就近原则最易穿盒的一段。
    final nodes = [
      _n(1),
      _n(2, parent: 1),
      _n(3, parent: 2),
      _n(4, parent: 3),
      _n(5, parent: 4),
    ];
    final rs = mmEdgeRoutes(
      nodes: nodes,
      edgeKind: MmEdgeKind.stair,
      assignedSides: const {},
      rectOf: _rectAt,
    );
    final last = rs.lastWhere((r) => r.childId == 5);
    final p = last.points;
    expect(p[0].dx, 160 * 3 + 120, reason: '起点＝父(4)右缘外');
    expect(p[3].dx, 160 * 4, reason: '终点＝子(5)左缘外');
    expect(p[1].dy, 20);
    expect(p[2].dy, 20);
    expect(p[1].dx, (p[0].dx + p[3].dx) / 2, reason: '中转 x 取两端中点');
  });

  test('重画判据：深度/聚焦/连接三集与相位任一变动都要重画', () {
    final nodes = [_n(1), _n(2, parent: 1)];
    // 同一批 nodes + 同一个 layout（画布侧这两者在同一次 build 里是稳定对象）
    // ⇒ 同输入不该重画；换任何一批 P 输入 ⇒ 必须重画。
    final layout = _layout(nodes);
    final a = _painter(nodes, layout: layout);
    expect(a.shouldRepaint(_painter(nodes, layout: layout)), isFalse,
        reason: '同输入不重画（画布高频重建，别把每帧都当真变化）');
    expect(a.shouldRepaint(_painter(nodes, layout: layout, focus: const {1, 2})),
        isTrue, reason: '聚焦态变化要重画');
    expect(
        a.shouldRepaint(_painter(nodes,
            layout: layout, depths: const {1: 0, 2: 1})),
        isTrue, reason: '深度变化要重画');
    expect(a.shouldRepaint(_painter(nodes, layout: layout, pulse: 0.3)), isTrue,
        reason: '呼吸相位推进要重画');
    expect(a.shouldRepaint(_painter(nodes, layout: layout, targets: const {2})),
        isTrue, reason: '连接目标集变化要重画');
    expect(
        a.shouldRepaint(
            _painter(nodes, layout: layout, blocked: const {2})),
        isTrue, reason: '置灰集变化要重画');
    _paintFrame(a);
    _paintFrame(_painter(nodes, layout: layout, focus: const {1, 2}));
  });

  test('连接态三集传入后照常出帧（置灰/呼吸双环不炸）', () {
    final nodes = [_n(1), _n(2, parent: 1), _n(3)];
    final p = _painter(nodes,
        depths: const {1: 0, 2: 1, 3: 0},
        targets: const {3},
        blocked: const {2},
        pulse: 0.4);
    _paintFrame(p);
    // 置灰/呼吸两条路径都要真画过（公式写错在这里就炸，而不是到真机上白屏）。
    expect(p.connectPulse, 0.4);
  });

  test('聚焦态收缩不同枝：画三帧不炸（saveLayer 降噪路径）', () {
    final nodes = [
      _n(1),
      _n(2, parent: 1),
      _n(3, parent: 1),
      _n(4, parent: 3),
    ];
    _paintFrame(_painter(nodes, focus: const {1, 2}));
    _paintFrame(_painter(nodes, focus: const {1, 3, 4}));
    _paintFrame(_painter(nodes));
  });
}
