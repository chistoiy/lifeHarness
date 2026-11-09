/// C08b · 「可打印 HTML」纯序列化层（零新依赖、零网络、纯 Dart）。
///
/// 背景：C08 的 PDF 出口在「零依赖 + 无内嵌中文字体」下做不出真 `.pdf` 字节。
/// 本轮不做假承诺，改出**可打印 HTML**：用户在系统浏览器/打印面板里选
/// 「另存为 PDF」即得 PDF（字体由系统中文栈提供，不缺字）。
///
/// 本文件只产 String，不碰 IO/平台通道；落盘见 `export_save.dart`。
/// 安全：用户文本一律先 [printableHtmlEscape] 再拼标签——正文里的
/// `<script>` 只会变成可见字符，不会变成标签。
library;

/// 导出入口文案（唯一源；**不许**写成「已导出 PDF」）。
const String kPrintableHtmlExportHint = '可打印 HTML · 系统打印可另存为 PDF';

/// 屏上提示（`@media print` 隐藏）：告诉用户 PDF 从哪来。
const String kPrintableHtmlPrintTip = '在浏览器中按 Ctrl/⌘+P，选择「另存为 PDF」即可得到 PDF。';

/// HTML 文本转义（& < > " '）；中文原样保留。
String printableHtmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

/// 正文里的行内代码占位符边界（先挖走再还原，避免 `**` 被代码内容干扰）。
const String _phStart = '\u0001';
const String _phEnd = '\u0002';

final RegExp _codeSpanRe = RegExp(r'`([^`\n]+)`');
final RegExp _boldRe = RegExp(r'\*\*([^*\n]+)\*\*');
final RegExp _linkRe = RegExp(r'\[([^\]\n]+)\]\(([^)\s]+)\)');
final RegExp _headingRe = RegExp(r'^(#{1,6})\s+(.*)$');
final RegExp _bulletRe = RegExp(r'^\s*[-*+]\s+(.*)$');
final RegExp _orderedRe = RegExp(r'^\s*\d+[.)]\s+(.*)$');
final RegExp _placeholderRe = RegExp('$_phStart(\\d+)$_phEnd');

/// 行内标记：转义 → 行内代码/粗体/安全链接 → 换行变 `<br>`。
/// 链接只放行 http(s)/mailto/# 四种前缀，其余原样当文字（不造可点协议）。
String _inline(String raw) {
  var s = printableHtmlEscape(raw);
  final codes = <String>[];
  s = s.replaceAllMapped(_codeSpanRe, (m) {
    codes.add(m.group(1)!);
    return '$_phStart${codes.length - 1}$_phEnd';
  });
  s = s.replaceAllMapped(_boldRe, (m) => '<strong>${m.group(1)}</strong>');
  s = s.replaceAllMapped(_linkRe, (m) {
    final text = m.group(1)!;
    final url = m.group(2)!;
    final ok = url.startsWith('http://') ||
        url.startsWith('https://') ||
        url.startsWith('mailto:') ||
        url.startsWith('#');
    return ok ? '<a href="$url">$text</a>' : m.group(0)!;
  });
  s = s.replaceAllMapped(
      _placeholderRe, (m) => '<code>${codes[int.parse(m.group(1)!)]}</code>');
  return s.replaceAll('\n', '<br>');
}

/// 正文 → 块级 HTML（段落 / 标题 / 引用 / 列表 / 围栏代码块）。
///
/// 刻意只做「够用的一层」：不引 Markdown 包、不猜复杂嵌套；
/// 认不出的行按普通段落处理（宁可少样式，不可吞字）。
String printableHtmlBody(String body) {
  final lines = body.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final out = StringBuffer();
  final para = <String>[];
  final quote = <String>[];
  final list = <String>[];
  final code = <String>[];
  var inFence = false;

  void flushPara() {
    if (para.isEmpty) return;
    out.writeln('    <p>${_inline(para.join('\n'))}</p>');
    para.clear();
  }

  void flushQuote() {
    if (quote.isEmpty) return;
    out.writeln('    <blockquote><p>${_inline(quote.join('\n'))}</p></blockquote>');
    quote.clear();
  }

  void flushList() {
    if (list.isEmpty) return;
    out.writeln('    <ul>');
    for (final item in list) {
      out.writeln('      <li>${_inline(item)}</li>');
    }
    out.writeln('    </ul>');
    list.clear();
  }

  void flushAll() {
    flushPara();
    flushQuote();
    flushList();
  }

  for (final line in lines) {
    final trimmed = line.trimRight();
    // 围栏代码块：内容只转义，不解析任何行内标记。
    if (trimmed.trimLeft().startsWith('```')) {
      if (inFence) {
        out.writeln('    <pre><code>${printableHtmlEscape(code.join('\n'))}</code></pre>');
        code.clear();
        inFence = false;
      } else {
        flushAll();
        inFence = true;
      }
      continue;
    }
    if (inFence) {
      code.add(line);
      continue;
    }
    if (trimmed.trim().isEmpty) {
      flushAll();
      continue;
    }
    final heading = _headingRe.firstMatch(trimmed.trim());
    if (heading != null) {
      flushAll();
      final level = heading.group(1)!.length.clamp(2, 6); // 标题已被 h1 占用
      out.writeln('    <h$level>${_inline(heading.group(2)!.trim())}</h$level>');
      continue;
    }
    if (trimmed.trimLeft().startsWith('>')) {
      flushPara();
      flushList();
      quote.add(trimmed.trimLeft().replaceFirst(RegExp(r'^>\s?'), ''));
      continue;
    }
    final bullet = _bulletRe.firstMatch(trimmed);
    final ordered = _orderedRe.firstMatch(trimmed);
    if (bullet != null || ordered != null) {
      flushPara();
      flushQuote();
      list.add((bullet ?? ordered)!.group(1)!.trim());
      continue;
    }
    flushQuote();
    flushList();
    para.add(trimmed);
  }
  // 未闭合的围栏：按代码块收尾，别把剩余正文当代码吞掉。
  if (inFence) {
    out.writeln('    <pre><code>${printableHtmlEscape(code.join('\n'))}</code></pre>');
    code.clear();
  }
  flushAll();
  return out.toString().trimRight();
}

/// A4 可打印样式（字面色值字符串；`@page size: A4` ＋ `@media print`）。
String printableHtmlStyle() => '''
    :root {
      --ink: #1f2328;
      --muted: #6b7280;
      --rule: #d8dee4;
      --quote-bg: #f4f6f8;
      --code-bg: #f6f8fa;
      --accent: #2f6f4f;
      --paper: #ffffff;
    }
    * { box-sizing: border-box; }
    html, body { margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Hiragino Sans GB",
        "Microsoft YaHei", "Noto Sans CJK SC", "Source Han Sans SC", "WenQuanYi Micro Hei",
        "Heiti SC", sans-serif;
      color: var(--ink);
      font-size: 11.5pt;
      line-height: 1.75;
      -webkit-font-smoothing: antialiased;
      text-rendering: optimizeLegibility;
    }
    .page { max-width: 174mm; margin: 0 auto; padding: 12mm 0; }
    .doc-head { border-bottom: 1px solid var(--rule); padding-bottom: 5mm; margin-bottom: 7mm; }
    .doc-title { margin: 0; font-size: 20pt; line-height: 1.35; font-weight: 800; letter-spacing: .01em; }
    .doc-sub { margin: 2mm 0 0; color: var(--muted); font-size: 10pt; }
    .doc-meta { margin: 1.5mm 0 0; color: var(--muted); font-size: 9pt; }
    .doc-body > *:first-child { margin-top: 0; }
    .doc-body p { margin: 0 0 3.2mm; text-align: justify; word-break: break-word; }
    .doc-body h2, .doc-body h3, .doc-body h4,
    .doc-body h5, .doc-body h6 { margin: 6mm 0 2.5mm; line-height: 1.4; font-weight: 800; }
    .doc-body h2 { font-size: 15pt; }
    .doc-body h3 { font-size: 13pt; }
    .doc-body h4, .doc-body h5, .doc-body h6 { font-size: 12pt; }
    .doc-body blockquote {
      margin: 0 0 4mm; padding: 3mm 4mm;
      border-left: 3px solid var(--accent);
      background: var(--quote-bg); color: #374151;
    }
    .doc-body blockquote p { margin: 0; }
    .doc-body ul { margin: 0 0 3.2mm; padding-left: 6mm; }
    .doc-body li { margin: 0 0 1mm; }
    .doc-body pre {
      margin: 0 0 4mm; padding: 3mm 4mm;
      background: var(--code-bg); border: 1px solid var(--rule); border-radius: 2mm;
      white-space: pre-wrap; word-break: break-word;
    }
    .doc-body code {
      font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace;
      font-size: 9.5pt;
    }
    .doc-body :not(pre) > code {
      background: var(--code-bg); border-radius: 1mm; padding: 0 .8mm;
    }
    .doc-body a { color: var(--accent); text-decoration: underline; }
    .doc-foot {
      margin-top: 8mm; padding-top: 4mm;
      border-top: 1px solid var(--rule);
      color: var(--muted); font-size: 9pt;
    }
    .hint {
      max-width: 174mm; margin: 0 auto 4mm; padding: 2mm 3mm;
      background: var(--quote-bg); border: 1px dashed var(--rule); border-radius: 2mm;
      color: var(--muted); font-size: 9.5pt;
    }
    @page { size: A4; margin: 18mm 16mm; }
    @media screen {
      body { background: #eef0f3; }
      .page { background: var(--paper); padding: 14mm 16mm; box-shadow: 0 1mm 4mm rgba(0, 0, 0, .08); }
    }
    @media print {
      body { background: var(--paper); font-size: 11pt; }
      .page { max-width: none; margin: 0; padding: 0; box-shadow: none; }
      .no-print { display: none !important; }
      a { color: inherit; text-decoration: none; }
      pre, blockquote, img, table { break-inside: avoid; page-break-inside: avoid; }
      h1, h2, h3, h4 { break-after: avoid; page-break-after: avoid; }
    }
''';

/// 笔记/日记正文 → 完整可打印 HTML 文档。
///
/// [showHeader]/[showFooter] 控制文档内页眉/页脚（关＝整段不输出；
/// 浏览器自带的页眉页脚由打印面板控制，HTML 管不到，这里不假称能关）。
/// [printedAt] 为空＝不写时间行（不编造时间）。
String noteToPrintableHtml({
  required String title,
  required String body,
  String subtitle = '',
  String printedAt = '',
  bool showHeader = true,
  bool showFooter = true,
  String footerNote = kPrintableHtmlExportHint,
}) {
  final safeTitle = title.trim().isEmpty ? '未命名笔记' : title.trim();
  final head = StringBuffer();
  if (showHeader) {
    head.writeln('    <header class="doc-head">');
    head.writeln('      <h1 class="doc-title">${printableHtmlEscape(safeTitle)}</h1>');
    if (subtitle.trim().isNotEmpty) {
      head.writeln('      <p class="doc-sub">${printableHtmlEscape(subtitle.trim())}</p>');
    }
    if (printedAt.trim().isNotEmpty) {
      head.writeln('      <p class="doc-meta">${printableHtmlEscape(printedAt.trim())}</p>');
    }
    head.writeln('    </header>');
  }
  final foot = StringBuffer();
  if (showFooter) {
    foot.writeln('    <footer class="doc-foot">${printableHtmlEscape(footerNote)}</footer>');
  }
  return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${printableHtmlEscape(safeTitle)}</title>
<style>
${printableHtmlStyle()}</style>
</head>
<body>
  <div class="hint no-print">${printableHtmlEscape(kPrintableHtmlPrintTip)}</div>
  <main class="page">
${head.toString().trimRight()}
    <article class="doc-body">
${printableHtmlBody(body)}
    </article>
${foot.toString().trimRight()}
  </main>
</body>
</html>
''';
}

/// 导出文件名：标题里的路径非法字符换 `-`；空标题＝未命名笔记。
String printableHtmlFileName(String title) {
  final t = (title.trim().isEmpty ? '未命名笔记' : title.trim())
      .replaceAll(RegExp(r'[/\\:*?"<>|\r\n\t]'), '-')
      .trim();
  return '${t.isEmpty ? '未命名笔记' : t}.html';
}
