/// 树关系纯函数（批P 连接器 · 2026-10-19）。
///
/// 本模块的树关系**只有 `parentId` 一个入口**（冻结方案 2c）：新建根必然游离、
/// md 平铺必然孤立——而「把 B 挂到 A 下」这个动作此前在画布上根本不存在。
/// 批P 补齐挂接/摘除后，下面这组判定成了三处共用的一份口径：
/// · 画布连接态（哪些节点可点、哪些置灰）；
/// · 绘制层（层级分级、聚焦降噪）；
/// · 树内导航（收起整枝的「保留集」）。
///
/// **纯函数、不碰 DAO**——成环这种「错了就毁数据」的判定必须能脱离界面单测。
library;

import 'mindmap_models.dart';

/// id → 深度（根＝0）。父引用指向不存在的节点（孤儿行）按根处理，不丢节点。
Map<int, int> mmDepths(List<MindmapNode> nodes) {
  final byId = <int, MindmapNode>{};
  for (final n in nodes) {
    if (n.id != null) byId[n.id!] = n;
  }
  final depths = <int, int>{};
  for (final n in byId.values) {
    // 沿父链上溯；遇到已算过的祖先直接借用（避免 O(n²) 全量重算）。
    final chain = <int>[];
    int? cur = n.id;
    var base = -1;
    while (cur != null) {
      final known = depths[cur];
      if (known != null) {
        base = known;
        break;
      }
      if (!chain.contains(cur)) chain.add(cur);
      final p = byId[cur]?.parentId;
      // 父不存在（孤儿）＝这一层当根，base 记 -1。
      cur = (p == null || !byId.containsKey(p)) ? null : p;
    }
    // chain 是**自底向上**收集的（[自己, 父, 祖父…]）：赋值必须倒着走，
    // 否则最深的拿最小深度、根拿最大深度（守护见 mindmap_connect_test）。
    var d = base;
    for (final id in chain.reversed) {
      d += 1;
      depths[id] = d;
    }
  }
  return depths;
}

/// 祖先链（不含自己，自近及远）。
List<int> mmAncestorChain(List<MindmapNode> nodes, int id) {
  final byId = <int, MindmapNode>{};
  for (final n in nodes) {
    if (n.id != null) byId[n.id!] = n;
  }
  final out = <int>[];
  int? cur = byId[id]?.parentId;
  while (cur != null && byId.containsKey(cur) && !out.contains(cur)) {
    out.add(cur);
    cur = byId[cur]!.parentId;
  }
  return out;
}

/// 子树（含自己）。
Set<int> mmSubtreeOf(List<MindmapNode> nodes, int id) {
  final children = <int, List<int>>{};
  for (final n in nodes) {
    final p = n.parentId;
    if (p != null && n.id != null) children.putIfAbsent(p, () => []).add(n.id!);
  }
  final out = <int>{};
  final stack = <int>[id];
  while (stack.isNotEmpty) {
    final cur = stack.removeLast();
    if (!out.add(cur)) continue;
    stack.addAll(children[cur] ?? const <int>[]);
  }
  return out;
}

/// 一枝＝自己 ＋ 全部祖先 ＋ 全部后代。
///
/// 两处消费：L5 聚焦态（同枝不降噪，读得出「我在哪一枝」）与
/// 「收起整枝」（保留集＝这一枝，**祖先链必须留**，否则根一折＝整屏空）。
Set<int> mmBranchOf(List<MindmapNode> nodes, int id) {
  final out = <int>{id, ...mmAncestorChain(nodes, id), ...mmSubtreeOf(nodes, id)};
  return out;
}

/// 把 [child] 挂到 [parent] 下会不会成环。
///
/// 会成环的两种：自己挂自己、挂到自己的后代下（后代跟着一起搬过去＝闭环）。
bool mmWouldCycle(
  List<MindmapNode> nodes, {
  required int child,
  required int parent,
}) {
  if (child == parent) return true;
  return mmSubtreeOf(nodes, child).contains(parent);
}

/// 连接校验：`null`＝可以连；否则返回**给人看的一句话**（画布直接 toast）。
///
/// 文案口径同原型：不出现「不可撤销」这类承诺，只说事实。
String? mmConnectBlockReason(
  List<MindmapNode> nodes, {
  required int child,
  required int parent,
}) {
  if (child == parent) return '不能连到节点自己';
  if (mmWouldCycle(nodes, child: child, parent: parent)) {
    return '不能挂到自己的子节点下（会成环）';
  }
  final sameParent = nodes.any(
      (n) => n.id == child && n.parentId == parent);
  if (sameParent) return '它已经挂在这个节点下了';
  return null;
}

/// 层级档（绘制分级用）：0 根 / 1 一级 / 2 二级 / 3 三级及更深。
int mmTierOf(int depth) => depth <= 0 ? 0 : (depth >= 3 ? 3 : depth);
