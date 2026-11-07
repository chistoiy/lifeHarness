import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_models.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_tree.dart';

/// 思维导图批P · 连接器树关系守护（工单 §7 P1：挂接/摘除）。
/// 纯 Dart 级（零 Flutter 依赖）——「错了就毁数据」的判定必须脱离界面单测。
MindmapNode _n(int id, {int? parent, int sort = 0}) => MindmapNode(
      id: id,
      mapId: 1,
      parentId: parent,
      title: '节点$id',
      sort: sort,
      createdAt: 1,
      updatedAt: 1,
    );

/// 挂到 parent 下（纯函数侧模拟落库后的新树，再喂给判定一遍）。
List<MindmapNode> _attach(List<MindmapNode> nodes, int child, int parent) =>
    nodes
        .map((n) => n.id == child ? n.copyWith(parentId: parent) : n)
        .toList();

void main() {
  group('深浅度与一枝集', () {
    test('多根各自成树：深度按各自父链算，孤儿按根处理', () {
      final nodes = [
        _n(1),
        _n(2, parent: 1),
        _n(3, parent: 2),
        _n(4),
        _n(9, parent: 99), // 孤儿：父不存在 ⇒ 按根
      ];
      final d = mmDepths(nodes);
      expect(d[1], 0);
      expect(d[2], 1);
      expect(d[3], 2);
      expect(d[4], 0);
      expect(d[9], 0, reason: '父引用悬空＝这一层当根，节点不丢');
    });

    test('链式乱序输入：深度仍按父链递增（ bottom-up 赋值钉）', () {
      // 列表顺序与深度无关：1→5→4→3→2 是一条五节链。
      final nodes = [
        _n(1),
        _n(5, parent: 1),
        _n(4, parent: 5),
        _n(3, parent: 4),
        _n(2, parent: 3),
      ];
      final d = mmDepths(nodes);
      expect(d[1], 0);
      expect(d[5], 1);
      expect(d[4], 2);
      expect(d[3], 3);
      expect(d[2], 4);
    });

    // 多输入顺序无关：父亲先算、孩子后算都得到同一套值（上溯沿链复用）。
    test('深度与遍历无关：乱序输入同一套值（借祖先缓存）', () {
      final a = [
        _n(1),
        _n(2, parent: 1),
        _n(3, parent: 2),
        _n(4, parent: 3),
      ];
      final b = [
        _n(4, parent: 3),
        _n(3, parent: 2),
        _n(2, parent: 1),
        _n(1),
      ];
      expect(mmDepths(a), mmDepths(b));
      expect(mmDepths(b), {1: 0, 2: 1, 3: 2, 4: 3});
    });

    test('一枝集＝自己＋祖先＋后代（收起整枝要留祖先链）', () {
      //   1
      //  ├─2
      //  │ └─4
      //  └─3
      final nodes = [_n(1), _n(2, parent: 1), _n(3, parent: 1), _n(4, parent: 2)];
      expect(mmBranchOf(nodes, 2), {2, 1, 4});
      expect(mmSubtreeOf(nodes, 2), {2, 4});
      expect(mmAncestorChain(nodes, 4), [2, 1], reason: '自近及远');
    });
  });

  group('成环判定', () {
    test('自挂自 / 挂到自己后代下 ⇒ 拒绝', () {
      final nodes = [_n(1), _n(2, parent: 1), _n(3, parent: 2)];
      expect(mmWouldCycle(nodes, child: 2, parent: 2), isTrue);
      expect(mmWouldCycle(nodes, child: 1, parent: 3), isTrue,
          reason: '把祖先挂到后代下＝闭环');
      expect(mmWouldCycle(nodes, child: 3, parent: 1), isFalse);
    });

    test('文案：自己/成环/已在目标下各有给人看的一句话', () {
      final nodes = [_n(1), _n(2, parent: 1)];
      expect(mmConnectBlockReason(nodes, child: 2, parent: 2), '不能连到节点自己');
      expect(
          mmConnectBlockReason(nodes, child: 1, parent: 2), '不能挂到自己的子节点下（会成环）');
      expect(mmConnectBlockReason(nodes, child: 2, parent: 1), '它已经挂在这个节点下了');
      expect(mmConnectBlockReason(nodes, child: 2, parent: 4), isNull);
    });

    test('挂接后仍是一棵树：成环判定在新树上同样成立', () {
      final nodes = [_n(1), _n(2), _n(3, parent: 2)];
      final after = _attach(nodes, 2, 1);
      // 2→1 之后 1 的子树含 2、3；再把 1 挂到 3 下应拒绝。
      expect(mmWouldCycle(after, child: 1, parent: 3), isTrue);
      expect(mmConnectBlockReason(after, child: 1, parent: 3), isNotNull);
    });
  });

  group('摘除回根层级', () {
    test('摘除只摘父子：节点与它自己的子级都还在', () {
      final nodes = [_n(1), _n(2, parent: 1), _n(4, parent: 2)];
      // 语义：清 parent ⇒ 节点与子级保留（画布页走 clearParent）。
      final detached = nodes
          .map((n) => n.id == 2 ? n.copyWith(clearParent: true) : n)
          .toList();
      final d = mmDepths(detached);
      expect(d[2], 0, reason: '摘除后回根层级');
      expect(d[4], 1, reason: '子级跟着走，不掉队');
      expect(mmSubtreeOf(detached, 2), {2, 4});
    });
  });

  test('挂接完成后全图只剩一个根（跨根合并的最终形态）', () {
    // 两棵独立的树 1→2 与 3→4，把 3 挂到 1 下 ⇒ 全图单根。
    final nodes = [_n(1), _n(2, parent: 1), _n(3), _n(4, parent: 3)];
    final after = _attach(nodes, 3, 1);
    final roots = after.where((n) => n.parentId == null).map((n) => n.id);
    expect(roots, [1]);
    final d = mmDepths(after);
    expect(d[3], 1);
    expect(d[4], 2, reason: '整枝跟着搬');
  });

  test('层级档：LB 口径 0 根 / 1 一级 / 2 二级 / 3 三级及更深', () {
    expect(mmTierOf(0), 0);
    expect(mmTierOf(1), 1);
    expect(mmTierOf(2), 2);
    expect(mmTierOf(3), 3);
    expect(mmTierOf(7), 3, reason: '再深也不再分档（视觉只分四级）');
  });
}
