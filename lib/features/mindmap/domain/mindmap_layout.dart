import 'dart:math' as math;
import 'dart:ui';

import 'mindmap_models.dart';

/// 布局引擎接口（6b 裁定：批 1 必抽，哪怕只有一个实现——
/// 不抽则批 1~4 渲染代码全要重写；**批4 已把 `radial`/`both` 两形态挂进来**）。
///
/// 引擎输出的是**自动布局基线**：节点拖拽偏移 `dx/dy` 不进引擎，
/// 渲染层拿「基线＋偏移」合成绝对位置——这样换布局类型时基线重算、
/// 偏移仍可叠加，「归位」＝清零偏移（2d 冻结口径）。
///
/// 批4 三形态同住本文件（纵向树/横向树/放射），由 `mmEngineFor(preset)`
/// 按预设挑（工厂在 `mindmap_layout_preset.dart`）。
abstract class LayoutEngine {
  /// 对一整图节点算基线。入参=整图拉平节点；返回每节点基线位置、尺寸与 side 分配。
  MmLayoutResult layout(List<MindmapNode> nodes);
}

/// 布局结果：基线位置（画布坐标，节点左上角）＋尺寸＋side 分配。
class MmLayoutResult {
  MmLayoutResult({
    required this.baseline,
    required this.sizes,
    required this.assignedSides,
    this.edgeKind = MmEdgeKind.stair,
  });

  final Map<int, Offset> baseline;
  final Map<int, Size> sizes;

  /// `side` 为空的节点由引擎分配的结果（常驻用例钉点；批 1 tree 统一右置）。
  final Map<int, String> assignedSides;

  /// 连线画法（批4）：由引擎声明、painter 只照办——横向布局套纵向阶梯
  /// 公式＝斜穿节点（6113 实锤同族坑），所以画法不许 painter 自己猜。
  final MmEdgeKind edgeKind;
}

/// 连线画法（批4 §4e.2 ⑥）。
enum MmEdgeKind {
  /// 纵向大纲：父底 → 竖折线 → 子左（批 1/2 基线，默认值）。
  stair,

  /// 横向树（`dir=right/both`）：父中心 → 子中心直线（原型 `drawEdges`
  /// 的 `horiz` 分支——父左子右与左右分列共用这一条）。
  branch,

  /// 放射（`radial`）：父中心 → 子中心直线（原型 `radial||horiz` 同分支）。
  radial,
}

/// 节点度量回调：给节点算「标题盒」尺寸。真实画布传 TextPainter 缓存版
/// （缓存键＝标题文本，改文字才重算——渲染层七条之三）；测试传固定尺寸。
typedef MmMeasure = Size Function(MindmapNode node);

/// 纵向树引擎（批 1 默认形态，C12：`tree` 在竖屏下的默认；父在上、子在下、
/// 缩进表层级）。每节点占一行、y 按遍历序单调累加 ⇒ 行与行天然不重叠
/// （深树 ≥5 层、宽树 ≥20 兄弟都只是「更多行」，fit 收纳即可，F1-2）。
///
/// 多根遍历（C6）：`parent_id IS NULL` 的根各自成树、按 `sort` 串接，
/// 互不串行叠加。折叠节点（`folded`）整枝跳过——子级不参与布局与绘制（F1-9）。
class TreeLayoutEngine implements LayoutEngine {
  TreeLayoutEngine({
    this.indent = 24,
    this.rowGap = 10,
    this.minRowH = 40,
    this.maxNodeWidth = 280,
  });

  /// 每层缩进。
  final double indent;

  /// 行间垂直空隙。
  final double rowGap;

  /// 行高下限（触点 ≥44 的下沿由节点渲染自己保证，布局只管不重叠）。
  final double minRowH;

  /// 节点标题盒最大宽（超出由画布 ellipsis 截断——截断仅视觉，数据完整，§4.6）。
  final double maxNodeWidth;

  @override
  MmLayoutResult layout(List<MindmapNode> nodes) {
    final baseline = <int, Offset>{};
    final sizes = <int, Size>{};
    final sides = <int, String>{};
    final idSet = {for (final n in nodes) if (n.id != null) n.id!: n};

    // 兄弟表（按 sort 升序）＋根集合。
    final children = <int, List<MindmapNode>>{};
    final roots = <MindmapNode>[];
    for (final n in nodes) {
      sides[n.id!] = n.side ?? 'r';
      if (n.parentId != null && idSet.containsKey(n.parentId)) {
        children.putIfAbsent(n.parentId!, () => []).add(n);
      } else {
        roots.add(n); // parentId 空，或父引用悬空（脏数据兜底＝当根，不让节点消失）
      }
    }
    for (final list in children.values) {
      list.sort((a, b) => a.sort.compareTo(b.sort));
    }
    roots.sort((a, b) => a.sort.compareTo(b.sort));

    var cursor = 0.0;
    void visit(MindmapNode n, int depth, Size size) {
      final h = math.max(minRowH, size.height);
      baseline[n.id!] = Offset(depth * indent, cursor);
      sizes[n.id!] = size;
      cursor += h + rowGap;
      // 折叠＝整枝跳过：子级不进布局（F1-9），连线收缩由画布按「被跳过」处理。
      if (n.folded) return;
      for (final c in children[n.id!] ?? const <MindmapNode>[]) {
        visit(c, depth + 1, sizes[c.id!] = measure(c));
      }
    }

    for (final r in roots) {
      visit(r, 0, measure(r));
    }
    return MmLayoutResult(
        baseline: baseline, sizes: sizes, assignedSides: sides);
  }

  /// 度量回调（引擎构造时注入；默认给固定尺寸——纯 Dart 测试可零 Flutter 依赖跑）。
  MmMeasure measure = _defaultMeasure;

  static Size _defaultMeasure(MindmapNode n) => const Size(120, 36);
}

// ==================== 批4 F4-8 · 横向树（tree × dir right/both） ====================

/// 横向树引擎（批4 · 冻结方案 §2.6 的 `dir` 维度）：父左子右，[both] 时
/// 子节点按数量均分父节点左右两侧、**奇数右侧多一个**（§2.6 原话）。
///
/// 逐字照原型 `posTree(box, both)`：父**垂直居中于整块子树**（`subH` 递归求
/// 子树高后对半）、列宽＝全图最宽节点＋`colGap`、多根各自成块串接（块间
/// `rootGap`）。折叠整枝跳过（F1-9，口径同纵向树）。
///
/// **不读节点 `side`**：`side` 为空时按索引均分（`assignedSides` 输出分配结果）；
/// 非空的 `side` 优先采用——这样用户手动分侧（或上一轮 `both` 写回的 `side`）
/// 在换预设后仍守在原侧。两侧分配规则：先按显式 `side` 分组，剩余空位按
/// 索引补（右侧优先补满，再补左侧），保证「奇数右侧多一个」。
class HorizontalTreeEngine implements LayoutEngine {
  HorizontalTreeEngine({
    this.both = false,
    this.colGap = 46,
    this.rowGap = 10,
    this.rootGap = 70,
    this.minColWidth = 90,
    MmMeasure? measure,
  }) : measure = measure ?? _defaultMeasure;

  /// `dir` 维度：`true`＝子节点均分父左右两侧（奇数右侧多一个）、
  /// `false`＝全部向右延伸（父左子右）。
  final bool both;

  /// 相邻两列（父列右缘到子列左缘）的水平间距。
  final double colGap;

  /// 同侧相邻两子块的垂直间距。
  final double rowGap;

  /// 多根各自成块时的块间距。
  final double rootGap;

  /// 列宽下限（避免极短标题算出过窄的列）。
  final double minColWidth;

  /// 度量回调（构造时注入；默认给固定尺寸——纯 Dart 测试可零 Flutter 依赖跑）。
  MmMeasure measure;

  static Size _defaultMeasure(MindmapNode n) => const Size(120, 36);

  @override
  MmLayoutResult layout(List<MindmapNode> nodes) {
    final baseline = <int, Offset>{};
    final sizes = <int, Size>{};
    final sides = <int, String>{};
    final tree = MmTreeIndex.of(nodes); // 兄弟表/根集合/可见枝，批4 三引擎共用
    final measured = <int, Size>{
      for (final n in nodes)
        if (n.id != null) n.id!: measure(n),
    };
    for (final n in nodes) {
      if (n.id != null) sizes[n.id!] = measured[n.id!]!;
    }
    // 列宽＝全图最宽节点＋间距（原型 maxW 起 90 下限）。
    var maxW = minColWidth;
    for (final s in measured.values) {
      if (s.width > maxW) maxW = s.width;
    }
    final colW = maxW + colGap;

    // 子树高（含自身下限）＝递归量，父据此垂直居中。
    final subH = <int, double>{};
    double heightOf(int id) {
      final cached = subH[id];
      if (cached != null) return cached;
      final kids = tree.visibleChildren(id);
      var h = measured[id]!.height;
      if (kids.isNotEmpty) {
        var sum = 0.0;
        for (var i = 0; i < kids.length; i++) {
          sum += heightOf(kids[i].id!) + (i > 0 ? rowGap : 0);
        }
        if (sum > h) h = sum;
      }
      subH[id] = h;
      return h;
    }

    void place(int id, double x, double top, int dir) {
      final kids = tree.visibleChildren(id);
      final h = heightOf(id);
      final size = measured[id]!;
      // dir<0（左置）：父的**右缘**对齐传入的 x，即左上角 = x − 宽。
      baseline[id] = Offset(dir < 0 ? x - size.width : x,
          top + (h - size.height) / 2);
      var sy = top;
      for (final k in kids) {
        if (sy > top) sy += rowGap;
        place(k.id!, x + dir * colW, sy, dir);
        sy += heightOf(k.id!);
      }
    }

    var y = 0.0;
    for (final r in tree.roots) {
      final kids = tree.visibleChildren(r.id!);
      if (!both || kids.isEmpty) {
        place(r.id!, 0, y, 1);
      } else {
        // 均分：右侧 ceil(n/2)、左侧余下（奇数右侧多一个）。
        final split = MmTreeIndex.splitSides(kids);
        for (final side in ['r', 'l']) {
          for (final k in split[side] ?? const <MindmapNode>[]) {
            sides[k.id!] = side;
          }
        }
        final blk = heightOf(r.id!);
        baseline[r.id!] =
            Offset(0, y + (blk - measured[r.id!]!.height) / 2);
        var ry = y, ly = y;
        for (final k in split['r'] ?? const <MindmapNode>[]) {
          if (ry > y) ry += rowGap;
          place(k.id!, colW, ry, 1);
          ry += heightOf(k.id!);
        }
        for (final k in split['l'] ?? const <MindmapNode>[]) {
          if (ly > y) ly += rowGap;
          place(k.id!, 0, ly, -1);
          ly += heightOf(k.id!);
        }
      }
      y += heightOf(r.id!) + rootGap;
    }
    // 未显式分侧的节点：单侧布局恒右（与纵向树口径一致）。
    for (final n in nodes) {
      if (n.id != null) sides.putIfAbsent(n.id!, () => n.side ?? 'r');
    }
    return MmLayoutResult(
      baseline: mmNormalize(baseline),
      sizes: sizes,
      assignedSides: sides,
      edgeKind: MmEdgeKind.branch,
    );
  }
}

// ==================== 批4 F4-8 · 放射（radial × dir right/both） ====================

/// 放射引擎（批4 · 冻结方案 §2.6 的 `struct=radial`）：根居中，子级按角度
/// 铺同心圆；`both`＝整圆、`right`＝右半圆（原型 `posRadial` 同款）。
///
/// 三个刻意的口径（都照原型，勿"顺手优化"）：
/// · **圆心取「根节点中心」**——根按自身宽高居中到圆心，子级才铺在它四周
///   （若把圆心设在根的左上角，一层子级会压在根上，原型目检实锤）。
/// · **单子节点取角度中点**（`(lo+hi)/2`），多子按索引均分扇区。
/// · **递归扇区收窄**（`half = max(0.16, span/kids*0.82)`）——子级的子级
///   只在自己父的扇区里铺开，不会与兄弟枝的角度域交叉。
class RadialEngine implements LayoutEngine {
  RadialEngine({
    this.both = false,
    this.step = 150,
    this.rootGap = 70,
    MmMeasure? measure,
  }) : measure = measure ?? _defaultMeasure;

  /// `dir` 维度：`true`＝整圆四面铺开、`false`＝只铺右半圆。
  final bool both;

  /// 相邻同心圆的半径步进。
  final double step;

  /// 多根各自成圈时的纵向间距。
  final double rootGap;

  /// 度量回调（构造时注入；默认给固定尺寸）。
  MmMeasure measure;

  static Size _defaultMeasure(MindmapNode n) => const Size(120, 36);

  @override
  MmLayoutResult layout(List<MindmapNode> nodes) {
    final baseline = <int, Offset>{};
    final sizes = <int, Size>{};
    final sides = <int, String>{};
    final tree = MmTreeIndex.of(nodes);
    final measured = <int, Size>{
      for (final n in nodes)
        if (n.id != null) n.id!: measure(n),
    };
    for (final n in nodes) {
      if (n.id != null) sizes[n.id!] = measured[n.id!]!;
    }

    var centerY = 0.0;
    for (final r in tree.roots) {
      final size = measured[r.id!]!;
      // 根自身宽高居中到 (0, centerY)。
      baseline[r.id!] = Offset(-size.width / 2, centerY - size.height / 2);
      sides[r.id!] = r.side ?? 'r';

      final a0 = both ? -math.pi : -math.pi / 2;
      final a1 = both ? math.pi : math.pi / 2;

      void ring(int parentId, int depth, double lo, double hi) {
        final kids = tree.visibleChildren(parentId);
        if (kids.isEmpty) return;
        final radius = step * depth;
        for (var i = 0; i < kids.length; i++) {
          final k = kids[i];
          final span = hi - lo;
          final angle = kids.length == 1
              ? (lo + hi) / 2
              : lo + span * i / (kids.length - 1);
          final ks = measured[k.id!]!;
          final cx = math.cos(angle) * radius;
          final cy = math.sin(angle) * radius;
          baseline[k.id!] =
              Offset(cx - ks.width / 2, centerY + cy - ks.height / 2);
          // 放射按角度分侧：右半（含正上/正下轴）＝r、左半＝l，供连线分派读。
          sides[k.id!] = k.side ?? (math.cos(angle) >= 0 ? 'r' : 'l');
          final half = math.max(0.16, (span / math.max(1, kids.length)) * 0.82);
          ring(k.id!, depth + 1, angle - half, angle + half);
        }
      }

      ring(r.id!, 1, a0, a1);
      // 半径外沿＝最深可见枝的 step×深度，据此推进下一根的圆心。
      var reach = 0.0;
      void reachOf(int id, int depth) {
        if (depth * step > reach) reach = depth * step;
        for (final k in tree.visibleChildren(id)) {
          reachOf(k.id!, depth + 1);
        }
      }

      reachOf(r.id!, 0);
      centerY += measured[r.id!]!.height / 2 + reach + rootGap + measured[r.id!]!.height / 2;
    }
    return MmLayoutResult(
      baseline: mmNormalize(baseline),
      sizes: sizes,
      assignedSides: sides,
      edgeKind: MmEdgeKind.radial,
    );
  }
}

/// 坐标归一（批4）：把整图基线平移到**非负**并留 [pad] 边距。
///
/// 照原型 `layout()` 尾段（`minX/minY` 归零再 `+PAD`）：横向树左置子节点与
/// 放射根节点（居中到原点）算出的坐标天然为负，不归一则画布 fit 的包围盒
/// 左上为负、`_contentBounds` 与裁剪窗都要额外兜负值。**归一只动常量平移，
/// 不改相对位置**——拖拽偏移 `dx/dy` 叠加在归一后的基线上（2d 口径不变）。
Map<int, Offset> mmNormalize(Map<int, Offset> baseline, {double pad = 16}) {
  if (baseline.isEmpty) return baseline;
  var minX = double.infinity, minY = double.infinity;
  for (final p in baseline.values) {
    if (p.dx < minX) minX = p.dx;
    if (p.dy < minY) minY = p.dy;
  }
  if (minX >= pad && minY >= pad) return baseline;
  return {
    for (final e in baseline.entries) e.key: e.value + Offset(pad - minX, pad - minY),
  };
}

/// 三引擎共用的「拉平节点 → 兄弟表/根集合/可见枝」索引（批4）。
///
/// 抽出来是因为**折叠口径必须三处一致**（F1-9：折叠节点整枝不参与布局与绘制）：
/// 各引擎各写一份遍历，早晚一处漏判折叠 → 被折叠的子级在画布上凭空出现。
/// 纯 Dart、零 Flutter 依赖。
class MmTreeIndex {
  MmTreeIndex._({
    required this.children,
    required this.roots,
    required this.byId,
    required this.folded,
  });

  /// `parentId → 按 sort 升序的子节点表`。
  final Map<int, List<MindmapNode>> children;

  /// 根节点（`parent_id` 为空，或父引用悬空＝脏数据兜底当根，不让节点消失）。
  final List<MindmapNode> roots;

  final Map<int, MindmapNode> byId;

  final Set<int> folded;

  factory MmTreeIndex.of(List<MindmapNode> nodes) {
    final byId = <int, MindmapNode>{
      for (final n in nodes)
        if (n.id != null) n.id!: n,
    };
    final children = <int, List<MindmapNode>>{};
    final roots = <MindmapNode>[];
    final folded = <int>{};
    for (final n in nodes) {
      if (n.folded && n.id != null) folded.add(n.id!);
      final p = n.parentId;
      if (p != null && byId.containsKey(p)) {
        children.putIfAbsent(p, () => []).add(n);
      } else {
        roots.add(n);
      }
    }
    for (final list in children.values) {
      list.sort((a, b) => a.sort.compareTo(b.sort));
    }
    roots.sort((a, b) => a.sort.compareTo(b.sort));
    return MmTreeIndex._(
        children: children, roots: roots, byId: byId, folded: folded);
  }

  /// 可见子节点：**跳过折叠枝的后代**（`folded` 的节点自身仍可见，只有它的
  /// 子级不进布局；F1-9）。
  List<MindmapNode> visibleChildren(int id) {
    if (folded.contains(id)) return const <MindmapNode>[];
    return children[id] ?? const <MindmapNode>[];
  }

  /// 按 `side` 分组 + 空位补齐：显式 `side` 优先，剩余按索引分配，
  /// 右侧优先补满再补左侧 ⇒ **奇数时右侧多一个**（§2.6 原话）。
  ///
  /// 返回 `{'r': [...], 'l': [...]}`，两键恒存在（可能为空表）。
  static Map<String, List<MindmapNode>> splitSides(List<MindmapNode> kids) {
    final right = <MindmapNode>[];
    final left = <MindmapNode>[];
    final free = <MindmapNode>[];
    for (final k in kids) {
      if (k.side == 'l') {
        left.add(k);
      } else if (k.side == 'r') {
        right.add(k);
      } else {
        free.add(k);
      }
    }
    final wantRight = (kids.length + 1) ~/ 2; // ceil(n/2)
    for (final k in free) {
      if (right.length < wantRight) {
        right.add(k);
      } else {
        left.add(k);
      }
    }
    return {'r': right, 'l': left};
  }
}
