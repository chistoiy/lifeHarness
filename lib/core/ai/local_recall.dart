/// C11 · 本地关键词召回（竞品补全清单「RAG／本地知识检索」的纯函数内核）。
///
/// 刻意不引向量库、不建索引服务、不碰 IO 与网络：调用方把本地笔记/书摘
/// 映射成 [RecallDoc] 交进来，本层只按词频打分、返回「引用可见」的短片段。
/// 口径：① `enabled=false` 恒空＝可关闭；② 结果只带 snippet，不带 body
/// ＝不上传全库；③ 引用来源 docId/title 一并给出，审阅页可直接显示。
library;

/// 一篇可被召回的本地文档。
class RecallDoc {
  const RecallDoc({
    required this.id,
    required this.title,
    required this.body,
  });

  final String id;
  final String title;
  final String body;
}

/// 一条召回结果（只含短片段，不含全文）。
class RecallHit {
  const RecallHit({
    required this.docId,
    required this.title,
    required this.snippet,
    required this.score,
  });

  final String docId;
  final String title;
  final String snippet;
  final int score;
}

const Set<String> _stop = <String>{
  '的', '了', '和', '与', '是', '在', '我', '有', '就', '不', '也', '把',
  '被', '这', '那', '个', '上', '下', '中',
  'a', 'an', 'the', 'and', 'or', 'of', 'to', 'is', 'in', 'it', 'on',
};

/// 查询切词：拉丁词按 [a-z0-9]+；中文按单字＋相邻二字组；过滤停用词。
/// 纯函数，导出供守护直接下判（「空查询/纯停用词」必须给出空集）。
List<String> recallTerms(String query) {
  final q = query.toLowerCase();
  final out = <String>[];
  final seen = <String>{};
  void add(String s) {
    if (s.isEmpty || _stop.contains(s) || !seen.add(s)) return;
    out.add(s);
  }

  for (final m in RegExp(r'[a-z0-9]+').allMatches(q)) {
    final w = m.group(0)!;
    if (w.length > 1) add(w);
  }
  // 中文：单字 + 相邻二字组（无分词依赖，召回优先于精确）
  final cjk = q.replaceAll(RegExp(r'[^\u4e00-\u9fff]'), ' ').split(' ')
      .where((s) => s.isNotEmpty);
  for (final seg in cjk) {
    for (var i = 0; i < seg.length; i++) {
      add(seg[i]);
      if (i + 1 < seg.length) add(seg.substring(i, i + 2));
    }
  }
  return out;
}

/// 从 [docs] 召回至多 [maxHits] 条；同分按 docId 稳定排序。
/// [enabled] 为 false 时恒返回空列表（审阅页「关闭检索」开关的唯一落点）。
List<RecallHit> localRecall({
  required String query,
  required List<RecallDoc> docs,
  bool enabled = true,
  int maxHits = 3,
  int snippetChars = 120,
}) {
  if (!enabled) return const <RecallHit>[];
  final terms = recallTerms(query);
  if (terms.isEmpty || maxHits <= 0) return const <RecallHit>[];

  final scored = <_Scored>[];
  for (final d in docs) {
    final body = d.body.toLowerCase();
    final title = d.title.toLowerCase();
    var score = 0;
    var firstPos = -1;
    for (final t in terms) {
      final inBody = _count(body, t);
      final inTitle = _count(title, t);
      if (inBody + inTitle == 0) continue;
      score += inBody + inTitle * 2; // 标题命中权重更高
      final p = body.indexOf(t);
      if (p >= 0 && (firstPos < 0 || p < firstPos)) firstPos = p;
    }
    if (score == 0) continue;
    scored.add(_Scored(d, score, firstPos < 0 ? 0 : firstPos));
  }
  scored.sort((a, b) {
    final c = b.score.compareTo(a.score);
    return c != 0 ? c : a.doc.id.compareTo(b.doc.id);
  });
  return scored
      .take(maxHits)
      .map((s) => RecallHit(
            docId: s.doc.id,
            title: s.doc.title,
            snippet: _snippet(s.doc.body, s.pos, snippetChars),
            score: s.score,
          ))
      .toList(growable: false);
}

int _count(String hay, String needle) {
  if (needle.isEmpty) return 0;
  var n = 0;
  var i = 0;
  while ((i = hay.indexOf(needle, i)) >= 0) {
    n++;
    i += needle.length;
  }
  return n;
}

/// 以首个命中位置为中心截短片段；换行压成空格，避免注入 prompt 时破行。
/// 全文短于上限时原样返回（此时 snippet==body 属正常，不算「上传全库」）。
String _snippet(String body, int pos, int maxChars) {
  final flat = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.length <= maxChars) return flat;
  final start = (pos - maxChars ~/ 3).clamp(0, flat.length - maxChars);
  return flat.substring(start, start + maxChars);
}

class _Scored {
  const _Scored(this.doc, this.score, this.pos);
  final RecallDoc doc;
  final int score;
  final int pos;
}
