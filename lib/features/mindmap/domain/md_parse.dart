/// md 大纲 → 导图初稿解析（连接点④，冻结方案 B2/B3 全按本档口径）。
///
/// **三通道冲突优先级（B3）**：标题层级（#~######）> 缩进（≥2 空格/1 tab 每级）
/// > 空行（分段）。**同文档只取一条主通道，不叠加**——既有标题又有缩进的文档
/// 按标题通道走、缩进信号忽略（常驻用例钉这条优先序，防「三层实现互相矛盾」）。
///
/// **规模上限（B2）**：单次解析节点上限 2000、深度上限 20 层；
/// 超限截断并置 [MmMdParseResult.truncated]（预览弹层顶部给一行提示）。
library;

class MmMdNode {
  MmMdNode(this.title);

  final String title;
  final List<MmMdNode> children = [];
}

class MmMdParseResult {
  const MmMdParseResult({
    required this.roots,
    required this.truncated,
    this.singleLevel = false,
  });

  final List<MmMdNode> roots;
  final bool truncated;

  /// 全文只有**一层标题**（多为全 H1）：多枚并列根、且谁都没有子级。
  ///
  /// 批P P2 的判定位：这种文档按标题通道解析必然得到 N 个孤立根（用户报障
  /// 「md 生成的导图节点全孤立」）。判定放在解析层、处置放在建图层——
  /// 导出/HTML 走同一条通道时口径一致，不会两处各判一次。
  final bool singleLevel;
}

/// 单层标题判定（所有通道共用一份）：多枚根且全部没有子级。
bool mmIsSingleLevel(List<MmMdNode> roots) =>
    roots.length > 1 && roots.every((r) => r.children.isEmpty);

/// 单层标题并入中心主题：中心主题作唯一根，原并列项全部挂其下。
///
/// 返回新列表（不改入参）；[centerTitle] 为空回落「中心主题」。
List<MmMdNode> mmMdJoinUnderCenter(
    List<MmMdNode> roots, String centerTitle) {
  final center =
      MmMdNode(centerTitle.trim().isEmpty ? '中心主题' : centerTitle.trim());
  center.children.addAll(roots);
  return <MmMdNode>[center];
}

/// 节点硬上限（B2；达上限后解析停、`truncated`＝true）。
const int mmMdMaxNodes = 2000;

/// 深度硬上限（B2；第 20 层以下的子树截断）。
const int mmMdMaxDepth = 20;

final RegExp _headingRe = RegExp(r'^(#{1,6})\s+(.*)$');
final RegExp _indentRe = RegExp(r'^([ \t]+)(\S.*)$');

MmMdParseResult parseMdOutline(String src) {
  final lines = src.replaceAll('\r\n', '\n').split('\n');
  // ── 主通道判定（B3 优先序，一次扫描定音）──
  var hasHeading = false;
  var hasIndent = false;
  for (final raw in lines) {
    if (_headingRe.hasMatch(raw.trimRight())) {
      hasHeading = true;
      break; // 标题最高优先，命中即定
    }
    if (!hasIndent && _indentRe.firstMatch(raw.trimRight()) != null) {
      hasIndent = true;
    }
  }

  var truncated = false;
  var count = 0;

  /// 入栈挂父；跳级归最近祖先（`###` 出现在 `#` 后＝二级缺失，
  /// 按最近可见祖先降层挂靠，不允许「父空挂空」丢节点）。
  MmMdNode? push(List<MmMdNode?> stack, List<MmMdNode> roots, int depth0,
      String title) {
    var depth = depth0;
    while (depth > 0 && (depth - 1 >= stack.length || stack[depth - 1] == null)) {
      depth--;
    }
    if (count >= mmMdMaxNodes || depth > mmMdMaxDepth) {
      truncated = true;
      return null;
    }
    final n = MmMdNode(title);
    count++;
    // 层级回升必清栈：'# 二' 后再遇 '###'，陈旧的更深父链不清就会挂错祖先。
    if (stack.length > depth) stack.length = depth;
    (depth == 0 ? roots : stack[depth - 1]!.children).add(n);
    if (stack.length <= depth) stack.length = depth + 1;
    stack[depth] = n;
    return n;
  }

  if (hasHeading) {
    // ── 标题通道：# 级定深度；非标题行忽略（不叠加）。层级相对首枚标题归一。
    final stack = <MmMdNode?>[];
    final roots = <MmMdNode>[];
    var baseLevel = -1;
    for (final raw in lines) {
      final m = _headingRe.firstMatch(raw.trimRight());
      if (m == null) continue;
      final level = m.group(1)!.length;
      if (baseLevel < 0) baseLevel = level;
      final node = push(stack, roots, level - baseLevel,
          (m.group(2) ?? '').trim());
      if (node == null) break; // 截断即停
    }
    return MmMdParseResult(
        roots: roots, truncated: truncated, singleLevel: mmIsSingleLevel(roots));
  }

  if (hasIndent) {
    // ── 缩进通道：每 2 空格/1 tab 一级；无缩进行＝根层。空行不产生节点。
    final stack = <MmMdNode?>[];
    final roots = <MmMdNode>[];
    var baseIndent = -1;
    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) continue;
      final m = _indentRe.firstMatch(line);
      final indentCols = m == null
          ? 0
          : m.group(1)!.replaceAll('\t', '  ').length; // tab 记 2 列
      if (baseIndent < 0) baseIndent = indentCols;
      final depth = ((indentCols - baseIndent) / 2).floor();
      final node = push(stack, roots, depth < 0 ? 0 : depth,
          m?.group(2) ?? line);
      if (node == null) break;
    }
    return MmMdParseResult(
        roots: roots, truncated: truncated, singleLevel: mmIsSingleLevel(roots));
  }

  // ── 空行通道：空行分段，每段一个节点（段内多行以空格合并为一条标题），平铺根层。
  final roots = <MmMdNode>[];
  final stack = <MmMdNode?>[];
  final seg = <String>[];
  void flush() {
    if (seg.isEmpty) return;
    push(stack, roots, 0, seg.join(' '));
    seg.clear();
  }

  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) {
      flush();
      continue;
    }
    seg.add(line);
  }
  flush();
  return MmMdParseResult(
      roots: roots, truncated: truncated, singleLevel: mmIsSingleLevel(roots));
}

/// 把解析树转成「父 id → 子标题列表」可直接建节点的扁平序（先序遍历）。
/// 返回 (title, depth) 序列，建图侧按 depth 弹栈挂父。
List<(String, int)> flattenMdTree(List<MmMdNode> roots) {
  final out = <(String, int)>[];
  void walk(MmMdNode n, int depth) {
    out.add((n.title, depth));
    for (final c in n.children) {
      walk(c, depth + 1);
    }
  }

  for (final r in roots) {
    walk(r, 0);
  }
  return out;
}
