/// C08 · 多格式导出纯序列化层（纯 Dart、禁引新依赖、零网络）。
///
/// - **SVG（导图）**：真正产出可开、中文不缺字的 SVG 1.1 文本。UTF-8 直写中文，
///   `font-family="sans-serif"` 由查看器做 CJK 字体回退（不内嵌字体＝不缺字），
///   XML 特殊字符一律转义，无外链资源、无脚本。
/// - **PDF（笔记/日记）**：纯 Dart 无法可靠内嵌 CJK 字体（禁引新依赖），故只做
///   **域层文档模型**（页 / 段 / 标题，中文原样保留）＋ JSON 序列化，明确标注
///   「UI 出口待接线」：接第三方 PDF 字体内核后由 UI 写 `.pdf` 并走既有
///   `core/platform/saf.dart` 的 `safSaveAs` 出口。
///
/// 只 import `dart:convert`；产物均为 String（字节由 UI 侧 utf8 编码后落盘）。
library;

import 'dart:convert';

/// SVG 标准命名空间（W3C 标识符，非网络请求；SVG 规范要求的 xmlns）。
const String kSvgXmlns = 'http://www.w3.org/2000/svg';

/// 一个导图节点（纯数据；id / parentId 构树，text 可含中文）。
class SvgNode {
  const SvgNode({
    required this.id,
    required this.text,
    this.parentId,
  });

  final String id;
  final String text;
  final String? parentId;
}

/// XML 文本转义（& < > " '）；中文原样保留，不缺字。
String svgEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// 导图 → SVG 1.1 文本。纯序列化：按 parentId 分层，同层按 (深度, id) 稳定
/// 排序横排；`<line>` 连父子、`<rect>` 框节点、`<text>` 直写中文。
String serializeMindmapSvg({
  required String title,
  required List<SvgNode> nodes,
  int width = 960,
  int height = 640,
}) {
  final byId = <String, SvgNode>{for (final n in nodes) n.id: n};

  // 深度：沿 parentId 上溯（防环：步数上限 + seen 集）。
  int depthOf(String id) {
    var d = 0;
    var cur = id;
    final seen = <String>{};
    while (byId[cur]?.parentId != null) {
      if (!seen.add(cur) || d > nodes.length) break;
      cur = byId[cur]!.parentId!;
      d++;
    }
    return d;
  }

  final order = <SvgNode>[...nodes]
    ..sort((a, b) {
      final c = depthOf(a.id).compareTo(depthOf(b.id));
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  final levelCount = <int, int>{};
  final xs = <String, int>{};
  final ys = <String, int>{};
  for (final n in order) {
    final d = depthOf(n.id);
    final idx = levelCount[d] ?? 0;
    levelCount[d] = idx + 1;
    xs[n.id] = 40 + idx * 210;
    ys[n.id] = 40 + d * 92;
  }

  final sb = StringBuffer();
  sb.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  sb.writeln('<svg xmlns="$kSvgXmlns" version="1.1" '
      'width="$width" height="$height" viewBox="0 0 $width $height" '
      'xml:lang="zh-CN">');
  sb.writeln('  <title>${svgEscape(title)}</title>');
  sb.writeln('  <g font-family="sans-serif" font-size="14" text-anchor="start">');
  // 连线先行、节点后画，避免线压字。
  for (final n in order) {
    final p = n.parentId;
    if (p == null || !xs.containsKey(p)) continue;
    sb.writeln('    <line x1="${xs[p]}" y1="${ys[p]}" '
        'x2="${xs[n.id]}" y2="${ys[n.id]}" stroke="gray" stroke-width="1"/>');
  }
  for (final n in order) {
    final x = xs[n.id]!;
    final y = ys[n.id]!;
    sb.writeln('    <rect x="$x" y="$y" width="180" height="36" rx="6" '
        'fill="none" stroke="gray"/>');
    sb.writeln('    <text x="${x + 8}" y="${y + 24}" fill="black">'
        '${svgEscape(n.text)}</text>');
  }
  sb.writeln('  </g>');
  sb.writeln('</svg>');
  return sb.toString();
}

// ─────────────────── PDF 域层（UI 出口待接线） ───────────────────

/// PDF 文档模型的一个文本块（标题块 heading=true）。中文原样保留。
class PdfBlock {
  const PdfBlock({required this.text, this.heading = false});

  final String text;
  final bool heading;

  Map<String, Object?> toJson() => <String, Object?>{
        'text': text,
        'heading': heading,
      };
}

/// PDF 文档模型的一页。
class PdfPage {
  const PdfPage(this.blocks);

  final List<PdfBlock> blocks;

  Map<String, Object?> toJson() => <String, Object?>{
        'blocks': <Object?>[for (final b in blocks) b.toJson()],
      };
}

/// 笔记 / 日记 PDF 的域层文档模型。**不是** `.pdf` 字节。
class PdfDocModel {
  const PdfDocModel({required this.title, required this.pages});

  final String title;
  final List<PdfPage> pages;

  Map<String, Object?> toJson() => <String, Object?>{
        'title': title,
        'pages': <Object?>[for (final p in pages) p.toJson()],
      };
}

/// 纯文本行 → 分页 PDF 文档模型（标题单独成首页块，每页 [linesPerPage] 行）。
/// 中文原样保留＝字体内核接线后按 UTF-8 渲染不缺字的前提。
PdfDocModel buildNotePdfModel({
  required String title,
  required List<String> lines,
  int linesPerPage = 32,
}) {
  final pages = <PdfPage>[];
  var buf = <PdfBlock>[PdfBlock(text: title, heading: true)];

  void flush() {
    if (buf.isEmpty) return;
    pages.add(PdfPage(List<PdfBlock>.unmodifiable(buf)));
    buf = <PdfBlock>[];
  }

  final cap = linesPerPage < 2 ? 2 : linesPerPage;
  for (final line in lines) {
    buf.add(PdfBlock(text: line));
    if (buf.length >= cap) flush();
  }
  flush();
  return PdfDocModel(title: title, pages: List<PdfPage>.unmodifiable(pages));
}

/// 序列化：JSON 域层描述（不是 .pdf 字节；UI 出口待接线）。
String serializePdfDocModel(PdfDocModel m) =>
    const JsonEncoder.withIndent('  ').convert(m.toJson());
