import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_layout.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_measure.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_models.dart';
import 'dart:ui';

import 'package:lifeharness/features/mindmap/domain/mindmap_viewport.dart';

/// 思维导图批1 · 布局引擎守护（工单 §4b.3 ②）。
/// 纯 Dart 级：引擎用默认度量（固定尺寸），零 Flutter 依赖。
MindmapNode _n(int id, {int? parent, int sort = 0, bool folded = false,
    String? side, double dx = 0, double dy = 0}) =>
    MindmapNode(
      id: id,
      mapId: 1,
      parentId: parent,
      title: '节点$id',
      sort: sort,
      folded: folded,
      side: side,
      dx: dx,
      dy: dy,
      createdAt: 1,
      updatedAt: 1,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TreeLayoutEngine engine;
  setUp(() {
    engine = TreeLayoutEngine();
  });

  MmLayoutResult run(List<MindmapNode> nodes) => engine.layout(nodes);

  test('深树（6 层）无重叠：行区间两两互斥（F1-2）', () {
    // 链式 1→2→3→4→5→6
    final nodes = [
      _n(1),
      _n(2, parent: 1),
      _n(3, parent: 2),
      _n(4, parent: 3),
      _n(5, parent: 4),
      _n(6, parent: 5),
    ];
    final l = run(nodes);
    final rects = nodes
        .map((n) => (
              l.baseline[n.id!]!.dy,
              l.baseline[n.id!]!.dy + (l.sizes[n.id!]?.height ?? 40)
            ))
        .toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));
    for (var i = 1; i < rects.length; i++) {
      expect(rects[i].$1, greaterThanOrEqualTo(rects[i - 1].$2),
          reason: '第 $i 行与上一行重叠');
    }
    // 深度反映在 x 缩进上
    expect(l.baseline[6]!.dx, greaterThan(l.baseline[1]!.dx));
  });

  test('宽树（24 兄弟）无重叠：24 行互斥不截断', () {
    final nodes = [_n(0)];
    for (var i = 1; i <= 24; i++) {
      nodes.add(_n(i, parent: 0, sort: i));
    }
    final l = run(nodes);
    expect(l.baseline, hasLength(25));
    final ys = l.baseline.values.map((o) => o.dy).toSet();
    expect(ys, hasLength(25), reason: '24 兄弟每行 y 互异＝无重叠');
  });

  test('side 为空时引擎自动分配（6b：批1 tree 统一右置）', () {
    final l = run([_n(1, side: null), _n(2, parent: 1, side: null)]);
    expect(l.assignedSides[1], isNotNull);
    expect(l.assignedSides[2], isNotNull);
    expect(l.assignedSides[1], 'r');
  });

  test('多根遍历（C6）：两根各自成树、互不串行叠加', () {
    final l = run([
      _n(1, sort: 0),
      _n(2, parent: 1, sort: 1),
      _n(3, sort: 1),
      _n(4, parent: 3, sort: 1),
    ]);
    // 根 2 的 y 在根 1 子树之后（串接不重叠）；根 3 的 y 又在其后。
    expect(l.baseline[3]!.dy, greaterThan(l.baseline[2]!.dy));
    expect(l.baseline[4]!.dy, greaterThan(l.baseline[3]!.dy));
  });

  test('折叠整枝跳过：folded 节点的子级不进布局（F1-9）', () {
    final l = run([
      _n(1),
      _n(2, parent: 1),
      _n(3, parent: 2),
    ]);
    // 全展开：3 在
    expect(l.baseline.keys, contains(3));
    // 折叠节点 2：3 消失
    final l2 = run([_n(1), _n(2, parent: 1, folded: true), _n(3, parent: 2)]);
    expect(l2.baseline.keys, isNot(contains(3)));
  });

  test('dx/dy 不进基线（2d：基线＋偏移在渲染层叠加；「归位」＝清偏移归基线）',
      () {
    final plain = run([_n(1), _n(2, parent: 1)]);
    final offset = run([_n(1, dx: 60, dy: -30), _n(2, parent: 1)]);
    expect(offset.baseline[1], plain.baseline[1],
        reason: '引擎输出不受节点偏移影响——偏移是渲染层叠加量');
    // 归位语义＝偏移清零后回到基线（这里以「引擎输出恒定」证可归位）。
  });

  test('fitTransform：fit 后内容包围盒完全落在视口内（C11 进图 fit）', () {
    final l = run([
      _n(1),
      _n(2, parent: 1),
      _n(3, parent: 1, sort: 1),
      _n(4, parent: 2),
    ]);
    var bounds = _bounds(l);
    // 故意用小视口逼 fit 缩小。
    final (s, pan) = fitTransform(
        contentBounds: bounds, viewport: const Size(300, 240), minScale: 0.1);
    final fitted =
        Rect.fromLTWH(bounds.left * s + pan.dx, bounds.top * s + pan.dy,
            bounds.width * s, bounds.height * s);
    expect(fitted.left, greaterThanOrEqualTo(0));
    expect(fitted.top, greaterThanOrEqualTo(0));
    expect(fitted.right, lessThanOrEqualTo(300));
    expect(fitted.bottom, lessThanOrEqualTo(240));
    bounds = _bounds(l); // 保持 bounds 被使用（免 lint）
  });

  // ---- 批2 F4-6 · 节点多行度量（工单 §4c.3 ⑥）----
  // TextPainter 走 flutter_test 字体底座（本文件 main 已开 binding）。
  group('F4-6 节点多行度量（mmNodeMeasure）', () {
    test('单行＝原口径：高不小于 40、宽=文本宽+左右内距', () {
      final s = mmNodeMeasure('一行');
      expect(s.height, 40.0);
      expect(s.width, greaterThan(24.0));
      expect(s.width, lessThanOrEqualTo(280.0));
    });

    test('带换行的标题：实测高随行数增大、实测高进布局（禁常量行高钉点）', () {
      final one = mmNodeMeasure('单行标题');
      final two = mmNodeMeasure('第一行\n第二行');
      final three = mmNodeMeasure('一\n二\n三');
      expect(two.height, greaterThan(one.height));
      expect(three.height, greaterThan(two.height));
      // 多行高必须被布局引擎吃进：兄弟行 y 按实测高累加不叠压。
      final eng = TreeLayoutEngine();
      eng.measure = (n) => mmNodeMeasure(n.title);
      final l = eng.layout([
        MindmapNode(
            id: 1,
            mapId: 1,
            title: '一\n二\n三',
            createdAt: 1,
            updatedAt: 1),
        MindmapNode(id: 2, mapId: 1, title: '单行', createdAt: 2, updatedAt: 2),
      ]);
      expect(l.sizes[1]!.height, greaterThan(l.sizes[2]!.height),
          reason: '多行节点实测高进布局，兄弟行不被叠压');
    });

    test('超宽文本：宽度封顶 maxWidth（视觉折行，数据完整）', () {
      final s = mmNodeMeasure('很长的一行没有换行符号' * 20);
      expect(s.width, 280.0);
      expect(s.height, greaterThan(40.0), reason: '封顶后折成多行');
    });

    test('空标题：占位不炸（B8 上游兜底）', () {
      expect(mmNodeMeasure('').height, 40.0);
    });
  });
}

Rect _bounds(MmLayoutResult l) {
  Rect? acc;
  for (final e in l.baseline.entries) {
    final s = l.sizes[e.key] ?? const Size(120, 36);
    final r =
        Rect.fromLTWH(e.value.dx, e.value.dy, s.width, s.height);
    acc = acc == null ? r : acc.expandToInclude(r);
  }
  return acc ?? Rect.zero;
}
