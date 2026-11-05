/// 笔记 md → 导图大纲（笔记编辑页「导图」视图的解析层）。
///
/// **口径**（与 `mindmap/domain/md_parse.dart` 的差别就在这一条，别合并）：
/// · 那个解析器是「md 大纲 → 新导图初稿」，三通道**只取一条**（有标题就忽略列表）；
///   笔记的正文主体恰恰是 `- ` 列表，照它走只会得到一排孤立标题。
/// · 本档**标题与列表同时吃**：标题（#~######）定主干层级，列表项挂到当前标题下，
///   缩进每 2 空格再深一层。这是「把一篇笔记当结构看」的读法，不是「导入成导图」。
/// · 层级相对**首个标题**归一（文档从 `##` 起也算第一级），跳级归最近祖先。
/// · 普通段落也入图（挂在当前标题下）——导图要覆盖全文，只画标题会漏掉正文信息；
///   代码围栏整块跳过（代码行不是结构）。
/// · 全篇既无标题也无列表时按空行分段兜底，每段一枚节点：空白 md 也有东西可看。
library;

/// 导图节点（纯标题树，无持久化身份——每次进视图现算）。
class NoteOutlineNode {
  NoteOutlineNode(this.title);

  final String title;
  final List<NoteOutlineNode> children = [];

  /// 子树节点数（含自身）。
  int get count => 1 + children.fold<int>(0, (s, c) => s + c.count);
}

/// 节点硬上限：超过即停（导图视图是只读概览，600 枚已远超一屏可读量）。
const int kNoteOutlineMaxNodes = 600;

/// 深度硬上限：第 10 层以下截断（再深在图上也只剩一根线，读不出层级）。
const int kNoteOutlineMaxDepth = 10;

final RegExp _headingRe = RegExp(r'^(#{1,6})\s+(.+)$');
final RegExp _bulletRe = RegExp(r'^([ \t]*)(?:[-*+]|\d+[.)])\s+(.+)$');
final RegExp _fenceRe = RegExp(r'^\s*(```|~~~)');
final RegExp _linkRe = RegExp(r'!?\[([^\]]*)\]\([^)]*\)');
final RegExp _markRe = RegExp(r'\*\*|__|~~|\*|`');

/// 行内 md 标记剥离：节点标题只留文字（`**加粗**`、`[文字](链接)`、反引号）。
///
/// 只剥**行内**标记——`#` 由调用方在解析时已取走；这里再兜一层行首 `#`，
/// 防「列表项里写 `- ## 小标题`」这种手写残留。
String stripNoteInlineMd(String s) {
  var t = s.replaceAllMapped(_linkRe, (m) => m[1] ?? '');
  t = t.replaceAll(_markRe, '');
  t = t.replaceAll(RegExp(r'^#{1,6}\s*'), '');
  return t.trim();
}

/// 解析入口。[rootTitle] 是导图中心主题（笔记标题；空则「未命名笔记」）。
NoteOutlineNode parseNoteOutline(String src, {String rootTitle = ''}) {
  final rootTitleText = rootTitle.trim();
  final root =
      NoteOutlineNode(rootTitleText.isEmpty ? '未命名笔记' : rootTitleText);
  final lines = src.replaceAll('\r\n', '\n').split('\n');

  /// `stack[i]` ＝深度 i 的最近节点；深度 0 恒为根。
  final stack = <NoteOutlineNode>[root];
  var baseLevel = 0;
  var headingDepth = 0;
  var count = 0;
  var sawStructure = false;
  var inFence = false;

  /// 挂到深度 [depth] 的父下；返回新节点（标题为空/超限＝null）。
  NoteOutlineNode? push(int depth, String rawTitle) {
    final title = stripNoteInlineMd(rawTitle);
    if (title.isEmpty) return null;
    if (count >= kNoteOutlineMaxNodes) return null;
    var d = depth < 1 ? 1 : depth;
    if (d > kNoteOutlineMaxDepth) d = kNoteOutlineMaxDepth;
    if (d > stack.length) d = stack.length; // 跳级归最近祖先，不凭空造父
    final node = NoteOutlineNode(title);
    stack[d - 1].children.add(node);
    stack.length = d;
    stack.add(node);
    count++;
    return node;
  }

  for (final raw in lines) {
    final line = raw.trimRight();
    if (_fenceRe.hasMatch(line)) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    if (line.trim().isEmpty) continue;

    final h = _headingRe.firstMatch(line);
    if (h != null) {
      final lv = h.group(1)!.length;
      if (baseLevel == 0) baseLevel = lv;
      final node = push(lv - baseLevel + 1, h.group(2)!);
      if (node != null) {
        headingDepth = lv - baseLevel + 1;
        sawStructure = true;
      }
      continue;
    }

    final b = _bulletRe.firstMatch(line);
    if (b != null) {
      final indent = b.group(1)!.replaceAll('\t', '  ').length;
      if (push(headingDepth + 1 + indent ~/ 2, b.group(2)!) != null) {
        sawStructure = true;
      }
      continue;
    }

    // 引用行剥掉 `>` 前缀后按段落处理（引用块里的层级不另立口径）。
    final body = line.trim().replaceFirst(RegExp(r'^>\s?'), '');
    if (body.isEmpty) continue;
    if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(body)) continue; // 分割线
    if (RegExp(r'^\|').hasMatch(body)) continue; // 表格行：列宽信息在图上无意义
    push(headingDepth + 1, body);
  }

  // 兜底：全篇没有任何结构标记（纯段落）时按空行分段，每段一枚节点。
  // 上面「段落也入图」已经把每行都变成节点了，这里只处理「一行都没进去」的极端。
  if (!sawStructure && root.children.isEmpty) {
    for (final seg in src.split(RegExp(r'\n\s*\n'))) {
      final t = seg.trim();
      if (t.isEmpty) continue;
      push(1, t.split('\n').first);
    }
  }
  return root;
}
