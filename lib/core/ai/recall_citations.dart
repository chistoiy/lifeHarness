/// C11 · 本地召回「引用」的审阅页投影层（纯函数、零 IO、零网络）。
///
/// 上游 `local_recall.dart` 给出 [RecallHit]（短片段＋来源）；本层只做两件事：
/// ① 把命中投影成审阅页可显示的 [RecallCitation]（**只拷贝 docId/title/snippet，
///    正文全库的概念在此层被彻底丢弃＝不上传全库**）；② 生成引用段纯文本。
/// [enabled] 是「可关闭」的唯一落点：false 恒空。
library;

import 'local_recall.dart';

/// 审阅页一条引用：只带短片段与来源，不带正文全库。
class RecallCitation {
  const RecallCitation({
    required this.docId,
    required this.title,
    required this.snippet,
  });

  final String docId;
  final String title;
  final String snippet;
}

/// 召回命中 → 审阅页引用。
/// - [enabled]=false 恒空（settings KV 开关关＝审阅页零引用）；
/// - 至多 [maxCitations] 条，顺序沿用 localRecall 的分数降序；
/// - 只取 [RecallHit.snippet]，不取 body＝不上传全库。
List<RecallCitation> recallCitations(
  List<RecallHit> hits, {
  bool enabled = true,
  int maxCitations = 3,
}) {
  if (!enabled || maxCitations <= 0) return const <RecallCitation>[];
  final out = <RecallCitation>[];
  for (final h in hits) {
    if (out.length >= maxCitations) break;
    out.add(RecallCitation(
      docId: h.docId,
      title: h.title,
      snippet: h.snippet,
    ));
  }
  return List<RecallCitation>.unmodifiable(out);
}

/// 审阅页「本地引用」段纯文本：逐条「[序号] 《来源》 · 短片段」。
/// 只渲染 [RecallCitation] 的三个字段，绝无全库正文。
String formatCitationSection(List<RecallCitation> citations) {
  if (citations.isEmpty) return '';
  final sb = StringBuffer();
  for (var i = 0; i < citations.length; i++) {
    final c = citations[i];
    if (i > 0) sb.write('\n');
    sb.write('[${i + 1}] 《${c.title}》(id:${c.docId}) · ${c.snippet}');
  }
  return sb.toString();
}

/// 域层能力：把引用短片段注入 user prompt（同源、只 snippet、可关闭）。
///
/// C11b 已接入 `AiService.renderForSend` 这一**唯一渲染出口**：审阅 /
/// 实际请求 / `ai_calls` 留痕仍取同一份结果，因此「审阅所见即所发」不破。
/// 开关关或空命中时原样返回 [user]＝零行为变化。
String attachRecallToUser(
  String user,
  List<RecallHit> hits, {
  bool enabled = true,
  int snippetChars = 120,
}) {
  final cs = recallCitations(hits, enabled: enabled);
  if (cs.isEmpty) return user;
  final buf = StringBuffer(user)
    ..write('\n\n本地参考片段（仅短片段与来源，不含全文）：\n');
  for (final c in cs) {
    final s = c.snippet.length <= snippetChars
        ? c.snippet
        : c.snippet.substring(0, snippetChars);
    buf.writeln('- 《${c.title}》：$s');
  }
  return buf.toString();
}
