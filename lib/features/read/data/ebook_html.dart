/// AZW3 / MOBI 共用的 HTML 片段 → 纯文本 / 章节切分（纯 Dart，零新依赖）。
///
/// 复用 [xmlUnescape] 处理数字实体与 XML 五类实体，再补一份常见 HTML 命名实体；
/// 未知实体原样保留（不猜、不展开外部实体）。章节切分只认
/// `<h1>`~`<h6>` 与 MOBI 的 `<mbp:pagebreak/>`，其余内容按段落归一。
library;

import 'text_import.dart';

final RegExp _commentRe = RegExp(r'<!--[\s\S]*?-->');
final RegExp _headRe = RegExp(
  r'<head\b[^>]*>[\s\S]*?</head\s*>',
  caseSensitive: false,
);
final RegExp _scriptRe = RegExp(
  r'<script\b[^>]*>[\s\S]*?</script\s*>',
  caseSensitive: false,
);
final RegExp _styleRe = RegExp(
  r'<style\b[^>]*>[\s\S]*?</style\s*>',
  caseSensitive: false,
);

/// 块级标签（开/闭）都当换行：MOBI6 的 `<p>` 常不闭合，开标签换行才能分段。
final RegExp _blockTagRe = RegExp(
  r'</?\s*(?:p|div|br|li|ul|ol|tr|td|th|table|h[1-6]|blockquote|section|article|'
  r'body|html|mbp:pagebreak)\b[^>]*>',
  caseSensitive: false,
);

final RegExp _headingRe = RegExp(
  r'<h([1-6])\b[^>]*>([\s\S]*?)</h\1\s*>',
  caseSensitive: false,
);
final RegExp _pageBreakRe = RegExp(
  r'</?mbp:pagebreak\b[^>]*>',
  caseSensitive: false,
);

const Map<String, String> _namedEntities = <String, String>{
  'nbsp': '\u00A0',
  'ensp': '\u2002',
  'emsp': '\u2003',
  'thinsp': '\u2009',
  'shy': '\u00AD',
  'mdash': '\u2014',
  'ndash': '\u2013',
  'hellip': '\u2026',
  'ldquo': '\u201C',
  'rdquo': '\u201D',
  'lsquo': '\u2018',
  'rsquo': '\u2019',
  'sbquo': '\u201A',
  'bdquo': '\u201E',
  'laquo': '\u00AB',
  'raquo': '\u00BB',
  'lsaquo': '\u2039',
  'rsaquo': '\u203A',
  'copy': '\u00A9',
  'reg': '\u00AE',
  'trade': '\u2122',
  'deg': '\u00B0',
  'middot': '\u00B7',
  'bull': '\u2022',
  'times': '\u00D7',
  'divide': '\u00F7',
  'plusmn': '\u00B1',
  'frac12': '\u00BD',
  'sect': '\u00A7',
  'para': '\u00B6',
  'dagger': '\u2020',
  'Dagger': '\u2021',
  'permil': '\u2030',
  'euro': '\u20AC',
  'pound': '\u00A3',
  'yen': '\u00A5',
  'cent': '\u00A2',
  'larr': '\u2190',
  'rarr': '\u2192',
  'harr': '\u2194',
  'le': '\u2264',
  'ge': '\u2265',
  'ne': '\u2260',
  'zwj': '\u200D',
  'zwnj': '\u200C',
};

final RegExp _namedEntityRe = RegExp(r'&([A-Za-z][A-Za-z0-9]{1,31});');

/// HTML 实体反转义：先走 [xmlUnescape]（数字实体 + XML 五类），再补常见命名实体。
///
/// 未知实体原样保留，避免把 `&foo;` 误吞成空串。
String htmlUnescape(String raw) {
  final base = xmlUnescape(raw);
  return base.replaceAllMapped(
    _namedEntityRe,
    (m) => _namedEntities[m.group(1)!] ?? m.group(0)!,
  );
}

/// 去掉不参与正文的节点（注释 / head / script / style）。
String _sanitizeHtml(String raw) {
  var s = raw.replaceAll(_commentRe, '');
  s = s.replaceAll(_headRe, '');
  s = s.replaceAll(_scriptRe, '');
  s = s.replaceAll(_styleRe, '');
  return s;
}

/// HTML 片段 → 归一化纯文本（段落以 `\n` 分隔）。
///
/// 折叠行内空白但保留换行；`&nbsp;` 与全角空格归一为普通空格。
String htmlFragmentText(String raw) {
  var s = _sanitizeHtml(raw).replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  s = s.replaceAll(_blockTagRe, '\n');
  s = s.replaceAll(RegExp(r'<[^>]*>'), '');
  s = htmlUnescape(s).replaceAll('\u00A0', ' ').replaceAll('\u3000', ' ');
  return s
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
      .where((l) => l.isNotEmpty)
      .join('\n')
      .trim();
}

/// 整段 HTML → 章节列表：`<h1>`~`<h6>` 与 `<mbp:pagebreak/>` 为切分点。
///
/// 无切分点时归单章；正文为空返回空列表（调用方据此提示，不臆造空章）。
List<TextChapter> splitHtmlIntoChapters(
  String html, {
  String fallbackTitle = '正文',
}) {
  final src = _sanitizeHtml(html);
  final marks = <_Mark>[];

  for (final m in _headingRe.allMatches(src)) {
    marks.add(
      _Mark(
        start: m.start,
        end: m.end,
        title: htmlFragmentText(m.group(2)!),
      ),
    );
  }
  for (final m in _pageBreakRe.allMatches(src)) {
    marks.add(_Mark(start: m.start, end: m.end));
  }
  marks.sort((a, b) => a.start.compareTo(b.start));

  final chapters = <TextChapter>[];
  var cursor = 0;
  String? nextTitle;

  void addBody(String body) {
    final text = htmlFragmentText(body);
    if (text.isEmpty) return;
    final title = nextTitle?.trim().isNotEmpty == true
        ? nextTitle!.trim()
        : _deriveTitle(text, fallbackTitle);
    chapters.add(TextChapter(title: title, text: text));
    nextTitle = null;
  }

  for (final mark in marks) {
    if (mark.start < cursor) continue;
    addBody(src.substring(cursor, mark.start));
    cursor = mark.end;
    if (mark.title != null && mark.title!.trim().isNotEmpty) {
      nextTitle = mark.title!.trim();
    } else {
      nextTitle = null;
    }
  }
  addBody(src.substring(cursor));

  return List<TextChapter>.unmodifiable(chapters);
}

String _deriveTitle(String text, String fallback) {
  final first = text.split('\n').first.trim();
  if (first.isEmpty || first.length > 40) return fallback;
  if (RegExp(r'[。！？；，,.!?;]').hasMatch(first)) return fallback;
  return first;
}

class _Mark {
  const _Mark({required this.start, required this.end, this.title});

  final int start;
  final int end;

  /// 标题标记（heading）有值；分页符为 null（只断开，不命名）。
  final String? title;
}
