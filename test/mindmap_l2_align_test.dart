import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_layout.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_models.dart';

/// 导图体检 L2 · 同级最小列宽对齐（实现轮常驻守护）。
/// 纯 Dart 级：不吃 TextPainter，量宽由用例直接注入，差异只来自布局引擎。
/// 每条用例都给「会真改变次序/宽度的输入」并同时断正档与负档，避免
/// 断言值恰好等于「被测分支压根没进」的结果造成假绿。
MindmapNode _n(int id,
        {int? parent, int sort = 0, bool folded = false, String? side}) =>
    MindmapNode(
      id: id,
      mapId: 1,
      parentId: parent,
      title: '节点$id',
      sort: sort,
      folded: folded,
      side: side,
      dx: 0,
      dy: 0,
      createdAt: 1,
      updatedAt: 1,
    );

TreeLayoutEngine _tree(Map<int, double> widths, {double maxNodeWidth = 280}) {
  final e = TreeLayoutEngine(maxNodeWidth: maxNodeWidth);
  e.measure = (n) => Size(widths[n.id!] ?? 100, 40);
  return e;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('同深度三枚不同量宽 → 拉齐到本层最宽；根层不跟着变', () {
    final l = _tree({1: 90, 2: 140, 3: 60, 4: 220}).layout([
      _n(1),
      _n(2, parent: 1, sort: 1),
      _n(3, parent: 1, sort: 2),
      _n(4, parent: 1, sort: 3),
    ]);
    // 正档：同层三枚全等且等于该层最大值（退回原始量宽会让 3 号是 60）
    expect(l.sizes[2]!.width, 220.0);
    expect(l.sizes[3]!.width, 220.0);
    expect(l.sizes[4]!.width, 220.0);
    // 负档：跨深度独立，根仍是自己的量宽
    expect(l.sizes[1]!.width, 90.0);
    // 负档：拉齐只动宽，不动高/缩进/行序
    for (final id in [1, 2, 3, 4]) {
      expect(l.sizes[id]!.height, 40.0);
    }
    expect(l.baseline[2]!.dx, 24.0);
    expect(l.baseline[3]!.dx, 24.0);
    expect(l.baseline[4]!.dy, greaterThan(l.baseline[3]!.dy));
  });

  test('跨深度各自成列（根 200／一级 260／二级 120），全图一刀切会红', () {
    final l = _tree({1: 200, 2: 60, 3: 260, 4: 80, 5: 120}).layout([
      _n(1),
      _n(2, parent: 1, sort: 1),
      _n(3, parent: 1, sort: 2),
      _n(4, parent: 1, sort: 3),
      _n(5, parent: 3, sort: 1),
    ]);
    expect(l.sizes[2]!.width, 260.0);
    expect(l.sizes[3]!.width, 260.0);
    expect(l.sizes[4]!.width, 260.0);
    expect(l.sizes[1]!.width, 200.0, reason: '根不与一级同宽');
    expect(l.sizes[5]!.width, 120.0, reason: '二级不与一级同宽');
    expect(l.sizes[1]!.width, isNot(l.sizes[2]!.width));
    expect(l.sizes[5]!.width, isNot(l.sizes[2]!.width));
  });

  test('量宽超上限时按实现侧上限钳位（400 → 280）', () {
    final l = _tree({1: 400, 2: 100, 3: 320}).layout([
      _n(1),
      _n(2, parent: 1, sort: 1),
      _n(3, parent: 1, sort: 2),
    ]);
    expect(l.sizes[1]!.width, 280.0);
    expect(l.sizes[2]!.width, 280.0);
    expect(l.sizes[3]!.width, 280.0);
    expect(l.sizes[1]!.width, lessThan(400.0), reason: '不钳上限会放回 400');
  });

  test('折叠枝的隐藏子级不参与同层分组', () {
    final l = _tree({1: 200, 2: 500, 3: 80}).layout([
      _n(1, folded: true),
      _n(2, parent: 1, sort: 1),
      _n(3, sort: 1),
    ]);
    expect(l.sizes.containsKey(2), isFalse, reason: '折叠枝整枝不进布局');
    // 若把隐藏的 500 算进 depth0 会顶到上限 280
    expect(l.sizes[1]!.width, 200.0);
    expect(l.sizes[3]!.width, 200.0);
  });

  test('多根：不同根同深度合并成一组', () {
    final l = _tree({1: 90, 2: 170, 3: 60, 4: 210}).layout([
      _n(1, sort: 1),
      _n(2, sort: 2),
      _n(3, parent: 1, sort: 1),
      _n(4, parent: 2, sort: 1),
    ]);
    expect(l.sizes[1]!.width, 170.0);
    expect(l.sizes[2]!.width, 170.0);
    expect(l.sizes[3]!.width, 210.0);
    expect(l.sizes[4]!.width, 210.0);
  });

  test('输入顺序无关：同一组节点两种顺序结果一致', () {
    final w = <int, double>{1: 90, 2: 140, 3: 60, 4: 220};
    final a = [
      _n(1),
      _n(2, parent: 1, sort: 1),
      _n(3, parent: 1, sort: 2),
      _n(4, parent: 1, sort: 3),
    ];
    final b = [a[3], a[1], a[0], a[2]];
    final la = _tree(w).layout(a);
    final lb = _tree(w).layout(b);
    for (final id in [1, 2, 3, 4]) {
      expect(lb.sizes[id]!.width, la.sizes[id]!.width);
      expect(lb.sizes[id]!.height, la.sizes[id]!.height);
    }
  });

  test('横向树与放射两形态不受拉齐影响（wide 恒空）', () {
    final nodes = [
      _n(1),
      _n(2, parent: 1, sort: 1),
      _n(3, parent: 1, sort: 2),
    ];
    final widths = <int, double>{1: 90, 2: 210, 3: 60};
    Size measure(MindmapNode n) => Size(widths[n.id!]!, 40);
    final h = HorizontalTreeEngine(measure: measure).layout(nodes);
    expect(h.sizes[1]!.width, 90.0);
    expect(h.sizes[2]!.width, 210.0);
    expect(h.sizes[3]!.width, 60.0);
    final r = RadialEngine(measure: measure).layout(nodes);
    expect(r.sizes[1]!.width, 90.0);
    expect(r.sizes[2]!.width, 210.0);
    expect(r.sizes[3]!.width, 60.0);
  });
}
