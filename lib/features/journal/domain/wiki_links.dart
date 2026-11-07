/// `[[笔记标题]]` 双向链接的解析与渲染（竞品补全清单 C02 · 批1 子批 A）。
///
/// 纯 Dart：不碰 DB、不碰 Widget。源文件始终是标准 Markdown 纯文本，
/// 链接只在**渲染层**投影出来，故导入导出无损（与笔记 MD 四模式口径一致）。
/// 复用导图挂笔记的既有范式：标题实时跟随、删除显示占位，不静默吞掉引用。
/// MD 渲染接线（`MdView` inline）与反链面板属子批 B，须过原型门。
library;

/// 一处 `[[...]]` 引用：`start`/`end` 是原文中的字符区间（含方括号）。
class WikiRef {
  const WikiRef({required this.title, required this.start, required this.end});
  final String title;
  final int start;
  final int end;
}

final _reWiki = RegExp(r'\[\[([^\[\]\n]+)\]\]');

/// 提取全部引用（跳过空标题）。不误伤普通链接 `[文字](url)` 与图片 `![图](x)`：
/// 这两者都不含连续两个左方括号。
List<WikiRef> parseWikiLinks(String source) => _reWiki
    .allMatches(source)
    .where((m) => (m.group(1) ?? '').trim().isNotEmpty)
    .map((m) => WikiRef(
          title: m.group(1)!.trim(),
          start: m.start,
          end: m.end,
        ))
    .toList();

const String kMissingNoteLabel = '（已删除的笔记）';

/// 渲染成标准 Markdown：能解析的变 `[标题](lh://note/<id>)`，解析不到的
/// 只留占位文本（**不生成死链**）。[resolve] 返回笔记 id，null＝已删除/不存在。
String renderWikiLinks(
  String source, {
  required String? Function(String title) resolve,
  String missing = kMissingNoteLabel,
}) {
  final refs = parseWikiLinks(source);
  if (refs.isEmpty) return source;
  final buf = StringBuffer();
  var cursor = 0;
  for (final r in refs) {
    buf.write(source.substring(cursor, r.start));
    final id = resolve(r.title);
    buf.write(id == null ? missing : '[${r.title}](lh://note/$id)');
    cursor = r.end;
  }
  buf.write(source.substring(cursor));
  return buf.toString();
}

/// 笔记改名时批量跟随：只替换 `[[旧标题]]` 内的标题，正文里同名的普通词不动。
String renameWikiLinks(String source, String oldTitle, String newTitle) {
  if (oldTitle.isEmpty || oldTitle == newTitle) return source;
  return source.replaceAllMapped(_reWiki, (m) {
    final t = (m.group(1) ?? '').trim();
    return t == oldTitle ? '[[$newTitle]]' : m[0]!;
  });
}
