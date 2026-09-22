/// 两级目录节点（book_toc_nodes 表 · 计划 §2.2）与粘贴文本解析（§3.3 目录导入）。
///
/// 口径：level 1=部分（parent_id NULL）、2=小节；idx 同级序；
/// 人工增删改后置 [confirmed]=1；删除小节**不删摘录**，其下摘录 chapter 置空回落未分章。
class TocNode {
  const TocNode({
    this.id,
    required this.bookId,
    this.parentId,
    required this.level,
    this.idx = 0,
    required this.title,
    this.startPage,
    this.startLoc,
    this.aiGenerated = false,
    this.confirmed = false,
  });

  static const kLevelPart = 1;
  static const kLevelSection = 2;

  final int? id;
  final String bookId;
  final int? parentId;
  final int level;
  final int idx;
  final String title;
  final int? startPage;
  final double? startLoc;
  final bool aiGenerated;
  final bool confirmed;

  bool get isPart => level == kLevelPart;

  static TocNode fromRow(Map<String, Object?> r) => TocNode(
    id: r['id'] as int?,
    bookId: r['book_id'] as String,
    parentId: r['parent_id'] as int?,
    level: (r['level'] as int?) ?? kLevelSection,
    idx: (r['idx'] as int?) ?? 0,
    title: r['title'] as String,
    startPage: r['start_page'] as int?,
    startLoc: (r['start_loc'] as num?)?.toDouble(),
    aiGenerated: ((r['ai_generated'] as int?) ?? 0) == 1,
    confirmed: ((r['confirmed'] as int?) ?? 0) == 1,
  );

  Map<String, Object?> toRow() => {
    if (id != null) 'id': id,
    'book_id': bookId,
    'parent_id': parentId,
    'level': level,
    'idx': idx,
    'title': title,
    'start_page': startPage,
    'start_loc': startLoc,
    'ai_generated': aiGenerated ? 1 : 0,
    'confirmed': confirmed ? 1 : 0,
  };
}

/// 部分 + 其小节（渲染与测试共用的树形视图）。
typedef TocPartGroup = ({TocNode part, List<TocNode> sections});

/// 平铺节点 → 按 idx 排序的两级树。[hideEmptyParts] 只读态不渲染空部分（§3.3 治理）。
List<TocPartGroup> tocTree(List<TocNode> nodes, {bool hideEmptyParts = true}) {
  final parts = nodes.where((n) => n.isPart).toList()
    ..sort((a, b) => a.idx.compareTo(b.idx));
  final secs = nodes.where((n) => !n.isPart).toList()
    ..sort((a, b) => a.idx.compareTo(b.idx));
  final out = <TocPartGroup>[];
  for (final p in parts) {
    final children = secs
        .where((s) => s.parentId == p.id)
        .toList(growable: false);
    if (children.isEmpty && hideEmptyParts) continue;
    out.add((part: p, sections: children));
  }
  // 孤儿小节（父级被删）回落「未分章」伪部分，不丢数据。
  final orphans = secs.where((s) => !parts.any((p) => p.id == s.parentId));
  if (orphans.isNotEmpty && !hideEmptyParts) {
    final pseudo = TocNode(
      bookId: secs.first.bookId,
      level: TocNode.kLevelPart,
      title: '',
    );
    out.add((part: pseudo, sections: orphans.toList()));
  }
  return out;
}

/// 解析结果的一个部分。
class ParsedTocPart {
  ParsedTocPart(this.title);
  final String title;
  final List<String> sections = [];
}

final _cnPart = RegExp(
  r'^第\s*[0-9〇零一二两三四五六七八九十百千]+\s*[部篇卷](?:[\s　]|$|[、：:])',
  caseSensitive: false,
);
final _enPart = RegExp(
  r'^(part|buch|teil)\s+[ivxlcdm0-9]+',
  caseSensitive: false,
);
final _romanLine = RegExp(r'^[ⅠⅡⅢⅣⅤⅥⅦⅧⅨⅩⅪⅫIVXLCDM]+[\.、:：]?\s*$');

/// 粘贴文本实时解析（计划 §3.3 目录导入）：
/// `第X部/篇/卷`、`Part N`、纯罗马数字行 ＝ 部分；
/// 行首缩进两格以上或 `1.2` 编号 ＝ 小节；其余也归当前部分的小节。
/// 首个部分前出现小节 → 挂到未命名部分（title=''）。
List<ParsedTocPart> parseTocText(String text) {
  final out = <ParsedTocPart>[];
  ParsedTocPart? cur;
  for (final raw in text.split('\n')) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) continue;
    final t = line.trim();
    final indented = raw.startsWith('  ') || raw.startsWith('　');
    final isPart =
        !indented &&
        (_cnPart.hasMatch(t) || _enPart.hasMatch(t) || _romanLine.hasMatch(t));
    if (isPart) {
      cur = ParsedTocPart(t);
      out.add(cur);
    } else {
      cur ??= ParsedTocPart('');
      if (!out.contains(cur)) out.add(cur);
      cur.sections.add(t);
    }
  }
  return out;
}
