/// C12 · 纯 Dart 文本格式解析（TXT / FB2）与最小 EPUB 生成。
///
/// 三条口径写在最近处：
/// · **零新依赖**：UTF-8 走 `dart:convert`，GBK 走仓内既有 `enough_convert`（账单 CSV 同款），
///   容器生成走仓内既有 `archive`；不引任何第三方阅读内核；
/// · **不假装支持**：MOBI / AZW3 / PDF / DRM 等无纯 Dart 内核的格式只登记到
///   [kUnsupportedReadFormats] 并在导入页显式列「不支持」，绝不静默降级成乱码或空书；
/// · **解码失败给明确提示**：UTF-8 严格失败 → GBK 兜底 → 仍失败则容错读取并附
///   [TextDecodeResult.warning]（UI 原样展示），不抛异常、不吞提示。
///
/// TXT/FB2 解析产物 [TextBookDraft] 经 [buildEpubBytes] 转成最小 EPUB 3 容器，
/// 再走既有 EPUB 导入/预载/阅读链路——不是「建个空书假装能读」。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:enough_convert/gbk.dart';

// ==================== 不支持格式清单（导入页显式展示） ====================

/// 一种本轮不支持的阅读文件格式（原因写清，供导入页原样展示）。
class UnsupportedReadFormat {
  const UnsupportedReadFormat(this.ext, this.name, this.reason);

  /// 小写扩展名（`epub` 的 DRM 档单独用 `drm` 标识）。
  final String ext;
  final String name;
  final String reason;
}

/// C13 口径：不静默降级、不假装支持。清单顺序＝导入页展示顺序。
const List<UnsupportedReadFormat> kUnsupportedReadFormats = <UnsupportedReadFormat>[
  UnsupportedReadFormat(
    'mobi',
    'MOBI',
    '亚马逊私有容器（PalmDOC/HUFF-CDIC），无纯 Dart 解析内核',
  ),
  UnsupportedReadFormat(
    'azw3',
    'AZW3',
    'KF8 私有容器，同上；请先转 EPUB',
  ),
  UnsupportedReadFormat(
    'pdf',
    'PDF',
    '版式固定流 + 中文字体子集，需独立渲染内核（本项目未接）',
  ),
  UnsupportedReadFormat(
    'drm',
    'DRM 加密书',
    'EPUB/PDF 加密需解密密钥，本应用不提供解密',
  ),
  UnsupportedReadFormat(
    'chm',
    'CHM',
    '微软帮助容器（LZX 压缩），无纯 Dart 解包器',
  ),
  UnsupportedReadFormat(
    'djvu',
    'DjVu',
    '位图分块编码，需专用解码器',
  ),
];

/// 文件名 → 本轮支持的文本格式（`TXT` / `FB2`）；其它返回 null。
String? plainBookFormatOf(String fileName) {
  final n = fileName.trim().toLowerCase();
  if (n.endsWith('.txt')) return 'TXT';
  if (n.endsWith('.fb2')) return 'FB2';
  return null;
}

/// 文件名是否落在「显式不支持」清单（用于导入页提示，不做任何解析尝试）。
bool isUnsupportedReadFile(String fileName) {
  final n = fileName.trim().toLowerCase();
  for (final f in kUnsupportedReadFormats) {
    if (n.endsWith('.${f.ext}')) return true;
  }
  return false;
}

// ==================== 字节解码（UTF-8 / GBK / 降级） ====================

/// 解码结果：文本 + 实际编码 + 降级提示（null＝无损解码）。
class TextDecodeResult {
  const TextDecodeResult({
    required this.text,
    required this.encoding,
    this.warning,
  });

  final String text;

  /// `utf-8` · `utf-8-bom` · `utf-16le` · `utf-16be` · `gbk` · `unknown`。
  final String encoding;

  /// 非 null 时 UI 必须原样展示（不吞、不改写成「成功」）。
  final String? warning;

  bool get ok => warning == null;
}

/// 文本字节解码：BOM → 严格 UTF-8 → GBK → 容错降级。
///
/// GBK 几乎接受任意字节对（同账单 CSV 的实测结论），所以**必须先试 UTF-8**；
/// 两次都失败才容错解码并附明确提示，保证「不崩」但也不冒充解码成功。
TextDecodeResult decodeBookBytes(List<int> bytes) {
  if (bytes.isEmpty) {
    return const TextDecodeResult(
      text: '',
      encoding: 'utf-8',
      warning: '文件为空（0 字节），没有可解析的正文',
    );
  }
  final b = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
    try {
      return TextDecodeResult(
        text: utf8.decode(b.sublist(3)),
        encoding: 'utf-8-bom',
      );
    } catch (_) {
      // catch-ok: 带 BOM 却非合法 UTF-8 的坏文件，继续走 GBK/降级（纯本地、无副作用）。
    }
  }
  if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) {
    return TextDecodeResult(
      text: _utf16(b.sublist(2), little: true),
      encoding: 'utf-16le',
    );
  }
  if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
    return TextDecodeResult(
      text: _utf16(b.sublist(2), little: false),
      encoding: 'utf-16be',
    );
  }

  try {
    return TextDecodeResult(text: utf8.decode(b), encoding: 'utf-8');
  } catch (_) {
    // catch-ok: 中文 TXT 常见 GBK，UTF-8 严格失败属预期分支（纯本地、无副作用）。
  }

  try {
    final text = gbk.decode(b);
    if (!text.contains('\uFFFD')) {
      return TextDecodeResult(text: text, encoding: 'gbk');
    }
    return TextDecodeResult(
      text: text,
      encoding: 'gbk',
      warning: '按 GBK 解码成功但含无法映射的字符（可能混有其它编码），请核对正文',
    );
  } catch (_) {
    // catch-ok: GBK 也解不出时走容错降级并明确提示（不抛、不静默）。
  }

  return TextDecodeResult(
    text: utf8.decode(b, allowMalformed: true),
    encoding: 'unknown',
    warning: '无法识别文本编码（UTF-8 与 GBK 均解码失败）· 已容错读取，可能含乱码；'
        '请用记事本另存为 UTF-8 后重试',
  );
}

String _utf16(List<int> b, {required bool little}) {
  final units = <int>[];
  for (var i = 0; i + 1 < b.length; i += 2) {
    units.add(little ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1]);
  }
  return String.fromCharCodes(units);
}

// ==================== 解析产物 ====================

/// 一章：标题 + 正文（段落以 `\n` 分隔，未做 HTML 化）。
class TextChapter {
  const TextChapter({required this.title, required this.text});

  final String title;
  final String text;

  int get charCount => text.length;
}

/// TXT / FB2 解析草稿（导入页预览与 EPUB 生成的共同输入）。
class TextBookDraft {
  const TextBookDraft({
    required this.title,
    this.author = '',
    required this.chapters,
    this.format = 'TXT',
    this.fileName = '',
    this.encoding = 'utf-8',
    this.warnings = const [],
  });

  final String title;
  final String author;
  final List<TextChapter> chapters;

  /// `TXT` / `FB2`（来源格式，写进书籍简介便于回溯）。
  final String format;
  final String fileName;
  final String encoding;

  /// 解码/解析降级提示（空＝无损）。
  final List<String> warnings;

  int get charCount {
    var n = 0;
    for (final c in chapters) {
      n += c.charCount;
    }
    return n;
  }

  bool get isEmpty => charCount == 0;

  /// 目录摘要（预览卡最多展示前 6 章，其余折叠成「等 N 章」）。
  String get chapterSummary {
    if (chapters.isEmpty) return '无章节';
    final head = chapters.take(6).map((c) => c.title).join(' · ');
    return chapters.length <= 6 ? head : '$head … 等 ${chapters.length} 章';
  }
}

// ==================== TXT 解析 ====================

/// 章节行：`第X章/节/回/卷/部/篇` 或 `Chapter N`（整行匹配、排除句子标点）。
final RegExp _txtChapterRe = RegExp(
  r'^\s*(?:第[0-9零一二三四五六七八九十百千万两]{1,8}[章节回卷部篇]'
  r'(?:[\s　:：·、.\-—]+[^\n。！？；]{0,30})?'
  r'|(?:Chapter|CHAPTER)\s+[0-9IVXLCDM]{1,6}'
  r'(?:[\s:：.\-—]+[^\n。！？；]{0,40})?)\s*$',
  multiLine: true,
);

final RegExp _txtTitleRe = RegExp(
  r'^\s*(?:书名|标题|Title)\s*[:：]\s*(.+)$',
  multiLine: true,
  caseSensitive: false,
);
final RegExp _txtAuthorRe = RegExp(
  r'^\s*(?:作者|Author)\s*[:：]\s*(.+)$',
  multiLine: true,
  caseSensitive: false,
);

/// TXT 全文 → 草稿。空文本返回空章草稿并附提示（不臆造正文）。
///
/// [encoding] / [warnings] 由 [decodeBookBytes] 透传（粘贴路径用默认 UTF-8）。
TextBookDraft parseTxtDraft(
  String raw, {
  String? fileName,
  String encoding = 'utf-8',
  List<String> warnings = const [],
}) {
  final notes = <String>[...warnings];
  final text = raw.replaceFirst('\uFEFF', '').replaceAll('\r\n', '\n');
  if (text.trim().isEmpty) {
    notes.add('正文为空，没有可导入的章节');
    return TextBookDraft(
      title: _titleFromFileName(fileName) ?? '未命名文本',
      chapters: const [],
      fileName: fileName ?? '',
      encoding: encoding,
      warnings: List<String>.unmodifiable(notes),
    );
  }

  final lines = text.split('\n');
  // 头部元信息只在正文开头 15 行内认（正文里的「作者：」不当头部）。
  final headEnd = lines.length < 15 ? lines.length : 15;
  String? metaTitle;
  String? metaAuthor;
  final bodyLines = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (i < headEnd) {
      final tm = _txtTitleRe.firstMatch(l);
      if (tm != null && metaTitle == null) {
        metaTitle = tm.group(1)!.trim();
        continue;
      }
      final am = _txtAuthorRe.firstMatch(l);
      if (am != null && metaAuthor == null) {
        metaAuthor = am.group(1)!.trim();
        continue;
      }
    }
    bodyLines.add(l);
  }

  final body = bodyLines.join('\n');
  final headings = <RegExpMatch>[];
  for (final m in _txtChapterRe.allMatches(body)) {
    headings.add(m);
  }

  final chapters = <TextChapter>[];
  if (headings.isEmpty) {
    final t = body.trim();
    if (t.isNotEmpty) chapters.add(TextChapter(title: '正文', text: t));
  } else {
    final pre = body.substring(0, headings.first.start).trim();
    if (pre.isNotEmpty) chapters.add(TextChapter(title: '正文', text: pre));
    for (var i = 0; i < headings.length; i++) {
      final h = headings[i];
      final start = h.end;
      final end = i + 1 < headings.length ? headings[i + 1].start : body.length;
      final title = h.group(0)!.trim();
      final content = body.substring(start, end).trim();
      if (content.isEmpty) continue; // 只有标题没有正文的章节不进目录（不留空章）
      chapters.add(TextChapter(title: title, text: content));
    }
  }

  final title = metaTitle?.isNotEmpty == true
      ? metaTitle!
      : (_titleFromFileName(fileName) ??
            _firstLineTitle(bodyLines) ??
            '未命名文本');

  return TextBookDraft(
    title: title,
    author: metaAuthor ?? '',
    chapters: List<TextChapter>.unmodifiable(chapters),
    format: 'TXT',
    fileName: fileName ?? '',
    encoding: encoding,
    warnings: List<String>.unmodifiable(notes),
  );
}

String? _titleFromFileName(String? fileName) {
  final n = (fileName ?? '').trim();
  if (n.isEmpty) return null;
  final base = n.replaceAll('\\', '/').split('/').last;
  final dot = base.lastIndexOf('.');
  final stem = dot > 0 ? base.substring(0, dot) : base;
  return stem.trim().isEmpty ? null : stem.trim();
}

String? _firstLineTitle(List<String> lines) {
  for (final l in lines) {
    final s = l.trim();
    if (s.isEmpty) continue;
    if (s.length > 40) return null;
    if (_txtChapterRe.hasMatch(s)) return null;
    return s;
  }
  return null;
}

// ==================== FB2（XML）解析 ====================

final RegExp _tagRe = RegExp(
  r'<\s*(/?)\s*([A-Za-z][A-Za-z0-9:_.-]*)([^>]*)>',
  multiLine: true,
  dotAll: true,
);
final RegExp _commentRe = RegExp(r'<!--[\s\S]*?-->');
final RegExp _cdataRe = RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>');
final RegExp _declRe = RegExp(r'<\?[\s\S]*?\?>');
final RegExp _doctypeRe = RegExp(r'<!DOCTYPE[^>]*>', caseSensitive: false);
final RegExp _binaryRe = RegExp(
  r'<binary\b[\s\S]*?</binary>',
  caseSensitive: false,
);
final RegExp _entityRe = RegExp(r'&(#x?[0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]*);');

/// FB2 全文 → 草稿。坏 XML 不抛：能取多少取多少，取不到正文时给明确提示。
///
/// [encoding] / [warnings] 由 [decodeBookBytes] 透传（粘贴路径用默认 UTF-8）。
TextBookDraft parseFb2Draft(
  String xml, {
  String? fileName,
  String encoding = 'utf-8',
  List<String> warnings = const [],
}) {
  final notes = <String>[...warnings];
  var src = xml.replaceFirst('\uFEFF', '');
  if (src.trim().isEmpty) {
    notes.add('FB2 内容为空');
    return TextBookDraft(
      title: _titleFromFileName(fileName) ?? '未命名 FB2',
      chapters: const [],
      format: 'FB2',
      fileName: fileName ?? '',
      encoding: encoding,
      warnings: List<String>.unmodifiable(notes),
    );
  }

  // 注释/CDATA/声明/DOCTYPE/内嵌二进制（封面 base64）先摘掉，避免混进正文。
  src = src.replaceAll(_commentRe, '');
  src = src.replaceAllMapped(_cdataRe, (m) => xmlEscape(m.group(1)!));
  src = src.replaceAll(_declRe, '');
  src = src.replaceAll(_doctypeRe, '');
  src = src.replaceAll(_binaryRe, '');

  final titleInfo = RegExp(
    r'<title-info\b[^>]*>([\s\S]*?)</title-info>',
    caseSensitive: false,
  ).firstMatch(src)?.group(1);
  final bookTitle = _tagText(src, 'book-title');
  final author = _fb2Author(titleInfo ?? src);

  final bodyMatch = RegExp(
    r'<body\b[^>]*>([\s\S]*?)</body>',
    caseSensitive: false,
  ).firstMatch(src);
  final body = bodyMatch?.group(1);
  final chapters = body == null ? <TextChapter>[] : _fb2Sections(body);

  if (chapters.isEmpty) {
    final plain = _fb2FallbackParas(body ?? src);
    if (plain.isNotEmpty) {
      chapters.add(TextChapter(title: '正文', text: plain.join('\n')));
      notes.add('未识别到 <section> 结构，已按段落归入单章');
    } else {
      notes.add('FB2 未解析出正文（文件可能损坏或不是 FB2）');
    }
  }

  return TextBookDraft(
    title: bookTitle?.isNotEmpty == true
        ? bookTitle!
        : (_titleFromFileName(fileName) ?? '未命名 FB2'),
    author: author,
    chapters: List<TextChapter>.unmodifiable(chapters),
    format: 'FB2',
    fileName: fileName ?? '',
    encoding: encoding,
    warnings: List<String>.unmodifiable(notes),
  );
}

class _DraftChap {
  _DraftChap(this.title);
  String title;
  final List<String> paras = <String>[];
}

/// 容忍式 section 走查：维护 section 栈与 title/p 两个文本缓冲。
List<TextChapter> _fb2Sections(String body) {
  final chaps = <_DraftChap>[];
  final stack = <int>[];
  _DraftChap? cur;
  var inTitle = 0;
  var inP = 0;
  final titleBuf = StringBuffer();
  final paraBuf = StringBuffer();

  _DraftChap ensureCur() {
    if (cur != null) return cur!;
    final c = _DraftChap('');
    chaps.add(c);
    stack.add(chaps.length - 1);
    cur = c;
    return c;
  }

  void flushPara() {
    final t = _cleanText(paraBuf.toString());
    paraBuf.clear();
    if (t.isEmpty) return;
    if (inTitle > 0) {
      titleBuf.write(t);
      return;
    }
    ensureCur().paras.add(t);
  }

  var last = 0;
  for (final m in _tagRe.allMatches(body)) {
    if (m.start > last) {
      final txt = body.substring(last, m.start);
      if (txt.trim().isNotEmpty) {
        if (inTitle > 0) {
          titleBuf.write(txt);
        } else if (inP > 0) {
          paraBuf.write(txt);
        }
      }
    }
    last = m.end;

    final closing = m.group(1) == '/';
    final name = m.group(2)!.toLowerCase();

    switch (name) {
      case 'section':
        if (!closing) {
          final c = _DraftChap('');
          chaps.add(c);
          stack.add(chaps.length - 1);
          cur = c;
        } else {
          flushPara();
          if (stack.isNotEmpty) stack.removeLast();
          cur = stack.isEmpty ? null : chaps[stack.last];
        }
      case 'title':
        if (!closing) {
          inTitle++;
          titleBuf.clear();
        } else {
          inTitle = inTitle > 0 ? inTitle - 1 : 0;
          final t = _cleanText(titleBuf.toString());
          titleBuf.clear();
          if (t.isNotEmpty) {
            final c = ensureCur();
            if (c.title.isEmpty) c.title = t;
          }
        }
      case 'p':
        if (!closing) {
          inP++;
          paraBuf.clear();
        } else {
          flushPara();
          inP = inP > 0 ? inP - 1 : 0;
        }
    }
  }

  final out = <TextChapter>[];
  for (final c in chaps) {
    final text = c.paras.join('\n').trim();
    if (text.isEmpty) continue;
    out.add(TextChapter(title: c.title.isEmpty ? '正文' : c.title, text: text));
  }
  return out;
}

/// 无 section 结构时：把 body 里所有 `<p>` 抽成段落（坏文件兜底，不编章节）。
/// 末尾 `<p>` 未闭合（文件被截断）也取剩余文本，别让整本书归零。
List<String> _fb2FallbackParas(String body) {
  final out = <String>[];
  final closed = RegExp(
    r'<p\b[^>]*>([\s\S]*?)</p>',
    caseSensitive: false,
  ).allMatches(body).toList();
  if (closed.isNotEmpty) {
    for (final m in closed) {
      final t = _cleanText(m.group(1) ?? '');
      if (t.isNotEmpty) out.add(t);
    }
    return out;
  }
  final open = RegExp(
    r'<p\b[^>]*>([\s\S]*)$',
    caseSensitive: false,
  ).firstMatch(body);
  if (open != null) {
    final t = _cleanText(open.group(1)!);
    if (t.isNotEmpty) out.add(t);
  }
  return out;
}

String? _tagText(String xml, String tag) {
  final m = RegExp(
    '<$tag\\b[^>]*>([\\s\\S]*?)</$tag>',
    caseSensitive: false,
  ).firstMatch(xml);
  if (m == null) return null;
  final t = _cleanText(m.group(1)!);
  return t.isEmpty ? null : t;
}

String _fb2Author(String xml) {
  final names = <String>[];
  for (final block in RegExp(
    r'<author\b[^>]*>([\s\S]*?)</author>',
    caseSensitive: false,
  ).allMatches(xml)) {
    final inner = block.group(1)!;
    final parts = <String>[];
    for (final tag in const ['first-name', 'middle-name', 'last-name', 'nickname']) {
      final t = _tagText(inner, tag);
      if (t != null) parts.add(t);
    }
    if (parts.isEmpty) continue;
    final joined = parts.every(_isCjk) ? parts.join() : parts.join(' ');
    names.add(joined);
  }
  return names.join(' / ');
}

bool _isCjk(String s) => RegExp(r'^[\u3400-\u9FFF·]+$').hasMatch(s);

/// 标签内文本归一：去标签、解实体、折空白（换行保留为段落分隔）。
String _cleanText(String raw) {
  final noTag = raw.replaceAll(RegExp(r'<[^>]*>'), ' ');
  final decoded = xmlUnescape(noTag);
  return decoded
      .replaceAll('\u00A0', ' ')
      .replaceAll(RegExp(r'[ \t\u3000]+'), ' ')
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .join('\n')
      .trim();
}

// ==================== XML 转义 ====================

/// XML 文本转义（顺序敏感：`&` 必须先转）。
///
/// 生成 EPUB 的 XHTML 时，正文里的 `<script>` / `&` 一律转义成文本，
/// 绝不让用户输入变成标签（FB2 的 `<p>` 内容同源处理）。
String xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// XML 实体反转义：只认五个预定义实体与数字实体；未知实体**原样保留**
/// （不解析 DTD、不展开外部实体＝不做 XXE）。
String xmlUnescape(String s) => s.replaceAllMapped(_entityRe, (m) {
      final e = m.group(1)!;
      if (e.startsWith('#x') || e.startsWith('#X')) {
        final v = int.tryParse(e.substring(2), radix: 16);
        return v == null || v < 0 || v > 0x10FFFF ? m.group(0)! : String.fromCharCode(v);
      }
      if (e.startsWith('#')) {
        final v = int.tryParse(e.substring(1));
        return v == null || v < 0 || v > 0x10FFFF ? m.group(0)! : String.fromCharCode(v);
      }
      return switch (e) {
        'amp' => '&',
        'lt' => '<',
        'gt' => '>',
        'quot' => '"',
        'apos' => "'",
        _ => m.group(0)!,
      };
    });

// ==================== 最小 EPUB 3 容器 ====================

/// 生成最小 EPUB 3（mimetype 不压缩且排第一；一章一个 XHTML）。
///
/// 只求既有 EPUB 解析器/阅读器能正常打开：OPF 元信息 + nav 目录 + spine 章序。
/// 不写封面/字体/脚本（文本导入无这些资源）。
Uint8List buildEpubBytes(
  TextBookDraft draft, {
  String bookId = 'b0',
  DateTime? modified,
}) {
  final chapters = draft.chapters.isEmpty
      ? const <TextChapter>[TextChapter(title: '正文', text: '')]
      : draft.chapters;
  final files = <ArchiveFile>[];
  void add(String name, String content, {bool compress = true}) {
    final bytes = utf8.encode(content);
    final f = ArchiveFile(name, bytes.length, bytes);
    f.compress = compress;
    files.add(f);
  }

  add('mimetype', 'application/epub+zip', compress: false);
  add(
    'META-INF/container.xml',
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<container version="1.0" '
    'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n'
    '  <rootfiles>\n'
    '    <rootfile full-path="OEBPS/content.opf" '
    'media-type="application/oebps-package+xml"/>\n'
    '  </rootfiles>\n'
    '</container>\n',
  );

  final manifest = StringBuffer();
  final spine = StringBuffer();
  for (var i = 0; i < chapters.length; i++) {
    manifest.write(
      '    <item id="c$i" href="c$i.xhtml" '
      'media-type="application/xhtml+xml"/>\n',
    );
    spine.write('    <itemref idref="c$i"/>\n');
    add('OEBPS/c$i.xhtml', _chapterXhtml(chapters[i]));
  }
  add('OEBPS/nav.xhtml', _navXhtml(chapters));

  final creator = draft.author.trim().isEmpty
      ? ''
      : '    <dc:creator>${xmlEscape(draft.author.trim())}</dc:creator>\n';
  final stamp = (modified ?? DateTime.now()).toUtc().toIso8601String();
  add(
    'OEBPS/content.opf',
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
    'unique-identifier="bookid">\n'
    '  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">\n'
    '    <dc:identifier id="bookid">urn:uuid:lh-$bookId</dc:identifier>\n'
    '    <dc:title>${xmlEscape(draft.title)}</dc:title>\n'
    '    <dc:language>zh-CN</dc:language>\n'
    '$creator'
    '    <meta property="dcterms:modified">$stamp</meta>\n'
    '  </metadata>\n'
    '  <manifest>\n'
    '    <item id="nav" href="nav.xhtml" '
    'media-type="application/xhtml+xml" properties="nav"/>\n'
    '$manifest'
    '  </manifest>\n'
    '  <spine>\n'
    '$spine'
    '  </spine>\n'
    '</package>\n',
  );

  final archive = Archive();
  for (final f in files) {
    archive.addFile(f);
  }
  final encoded = ZipEncoder().encode(archive);
  return Uint8List.fromList(encoded ?? const <int>[]);
}

String _chapterXhtml(TextChapter c) {
  final paras = c.text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .map((l) => '    <p>${xmlEscape(l)}</p>\n')
      .join();
  return '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="zh-CN" lang="zh-CN">\n'
      '  <head><title>${xmlEscape(c.title)}</title></head>\n'
      '  <body>\n'
      '    <h1>${xmlEscape(c.title)}</h1>\n'
      '$paras'
      '  </body>\n'
      '</html>\n';
}

String _navXhtml(List<TextChapter> chapters) {
  final items = StringBuffer();
  for (var i = 0; i < chapters.length; i++) {
    items.write(
      '      <li><a href="c$i.xhtml">${xmlEscape(chapters[i].title)}</a></li>\n',
    );
  }
  return '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<html xmlns="http://www.w3.org/1999/xhtml" '
      'xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="zh-CN" lang="zh-CN">\n'
      '  <head><title>目录</title></head>\n'
      '  <body>\n'
      '    <nav epub:type="toc" id="toc">\n'
      '      <h1>目录</h1>\n'
      '      <ol>\n'
      '$items'
      '      </ol>\n'
      '    </nav>\n'
      '  </body>\n'
      '</html>\n';
}
