import 'dart:math' as math;
import 'dart:ui';

import 'mindmap_models.dart';

/// 布局引擎接口（6b 裁定：批 1 必抽，哪怕只有一个实现——
/// 不抽则批 1~4 渲染代码全要重写；`radial`/`both` 在批 4 挂第二/三实现）。
///
/// 引擎输出的是**自动布局基线**：节点拖拽偏移 `dx/dy` 不进引擎，
/// 渲染层拿「基线＋偏移」合成绝对位置——这样换布局类型时基线重算、
/// 偏移仍可叠加，「归位」＝清零偏移（2d 冻结口径）。
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
  });

  final Map<int, Offset> baseline;
  final Map<int, Size> sizes;

  /// `side` 为空的节点由引擎分配的结果（常驻用例钉点；批 1 tree 统一右置）。
  final Map<int, String> assignedSides;
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
