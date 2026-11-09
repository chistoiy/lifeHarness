import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_layout.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_models.dart';
import 'dart:ui';

import 'package:lifeharness/features/mindmap/domain/mindmap_viewport.dart';

/// 思维导图批1 · 画布渲染守护（工单 §4b.3 ③＋变异刀3 的钉位）。
///
/// 性能断言是**单测版代理**：只证「裁剪生效」——视口外节点不进待绘集合。
/// fps/耗时只在真机门验（1000 节点 ≤1.5s / 5000 节点 ≤5s），单测不假装能验帧率。
MindmapNode _n(int id, {int? parent, int sort = 0}) => MindmapNode(
      id: id,
      mapId: 1,
      parentId: parent,
      title: '节点$id',
      sort: sort,
      createdAt: 1,
      updatedAt: 1,
    );

void main() {
  test('1000 节点 layout() 跑通且输出齐全（构造级性能代理）', () {
    final nodes = [_n(0)];
    for (var i = 1; i < 1000; i++) {
      nodes.add(_n(i, parent: i % 7 == 1 ? null : i ~/ 2, sort: i));
    }
    final engine = TreeLayoutEngine();
    final l = engine.layout(nodes); // 不限时的跑通性断言：炸/挂即红
    expect(l.baseline, hasLength(1000));
  });

  test('可视区裁剪（变异刀3 钉位）：视口外节点不进待绘集合', () {
    // 竖长树 60 行，可视区只罩住前 10 行。
    final nodes = [_n(0)];
    for (var i = 1; i < 60; i++) {
      nodes.add(_n(i, parent: i - 1));
    }
    final l = TreeLayoutEngine().layout(nodes);
    const viewport = Size(390, 480);
    final culled = cullVisibleNodes(
      baseline: l.baseline,
      sizes: l.sizes,
      dxs: const {},
      dys: const {},
      scale: 1,
      pan: Offset.zero,
      viewport: viewport,
    );
    expect(culled.length, lessThan(nodes.length),
        reason: '裁剪生效的读数证据：待绘数 < 总数');
    expect(culled.length, greaterThanOrEqualTo(5),
        reason: '可视区内节点必须全在');
    // 无脑全量（摘掉裁剪后的行为）＝返回全部 ⇒ 用例红。
    expect(culled.toSet().length, culled.length);
  });

  test('平移后裁剪窗随动：滚到树尾只有尾部行进待绘集合', () {
    final nodes = [_n(0)];
    for (var i = 1; i < 40; i++) {
      nodes.add(_n(i, parent: i - 1));
    }
    final l = TreeLayoutEngine().layout(nodes);
    // 把视口平移到最底部（树尾；链树缩进到 39*24px，x 窗一并跟上）。
    final lastY = l.baseline[39]!.dy;
    final culled = cullVisibleNodes(
      baseline: l.baseline,
      sizes: l.sizes,
      dxs: const {},
      dys: const {},
      scale: 1,
      pan: Offset(-l.baseline[39]!.dx, -lastY + 20),
      viewport: const Size(390, 480),
    );
    expect(culled, contains(39));
    expect(culled, isNot(contains(0)), reason: '树头行已滚出视口');
  });

  test('拖拽偏移参与裁剪判定（dxs/dys 正交叠加在基线上）', () {
    final l = TreeLayoutEngine().layout([_n(1)]);
    // 基线在原点；无偏移时不入窗（窗在远处），带大 dy 后入窗。
    final noOffset = cullVisibleNodes(
      baseline: l.baseline,
      sizes: l.sizes,
      dxs: const {},
      dys: const {},
      scale: 1,
      pan: const Offset(-2000, -2000),
      viewport: const Size(100, 100),
    );
    expect(noOffset, isEmpty);
    final withOffset = cullVisibleNodes(
      baseline: l.baseline,
      sizes: l.sizes,
      dxs: const {1: 2020.0},
      dys: const {1: 2020.0},
      scale: 1,
      pan: const Offset(-2000, -2000),
      viewport: const Size(100, 100),
    );
    expect(withOffset, contains(1));
  });
}
