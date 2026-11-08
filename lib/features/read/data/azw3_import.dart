/// AZW3（KF8）→ [TextBookDraft]（纯 Dart、零新依赖）。
///
/// AZW3/KF8 是 ZIP 容器（mimetype `application/vnd.amazon.ebook`），内含
/// OPF 清单 + XHTML 正文。容器解包复用仓内既有 `archive`，OPF 复用 `xml`，
/// 正文抽取复用 [htmlChapterOf]；不引任何 Kindle 解析内核。
///
/// 显式拒绝：非 ZIP、缺 OPF、META-INF 加密声明（DRM）、无可读 XHTML。
library;

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'ebook_exception.dart';
import 'ebook_html.dart';
import 'text_import.dart';

/// AZW3 全量字节 → 文本草稿。
///
/// 坏包/DRM/结构缺失抛 [EbookFormatException]；单章解码降级写进 warnings。
TextBookDraft parseAzw3Draft(List<int> bytes, {String? fileName}) {
  if (bytes.isEmpty) {
    throw const EbookFormatException('文件为空（0 字节），没有可解析的 AZW3 内容');
  }

  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    // catch-ok: 非 ZIP 的 AZW3（旧 MOBI 伪装扩展名）必须显式拒绝，不猜测。
    throw const EbookFormatException(
      '不是有效的 AZW3/KF8（ZIP）容器，文件可能损坏或为旧 MOBI 格式',
    );
  }

  final files = <String, List<int>>{};
  for (final f in archive) {
    if (!f.isFile) continue;
    final name = f.name.replaceAll('\\', '/').replaceFirst(RegExp(r'^\./'), '');
    files[name] = _bytesOf(f);
  }
  if (files.isEmpty) {
    throw const EbookFormatException('AZW3 容器为空（没有任何文件）');
  }
  final lower = <String, String>{
    for (final k in files.keys) k.toLowerCase(): k,
  };

  List<int>? read(String path) {
    final key = files.containsKey(path)
        ? path
        : lower[path.toLowerCase()];
    return key == null ? null : files[key];
  }

  if (read('META-INF/encryption.xml') != null ||
      read('META-INF/rights.xml') != null) {
    throw const EbookFormatException(
      'AZW3 含 DRM 加密声明（META-INF/encryption.xml / rights.xml），'
      '本应用不提供解密；请先移除 DRM 后重试',
    );
  }

  final mimeBytes = read('mimetype');
  final mime = mimeBytes == null
      ? ''
      : utf8.decode(mimeBytes, allowMalformed: true).trim();
  if (mime.isNotEmpty &&
      !mime.contains('amazon.ebook') &&
      !mime.contains('epub+zip')) {
    throw EbookFormatException('AZW3 mimetype 异常（$mime），不是 KF8 容器');
  }

  final opfPath = _findOpf(files, lower, read);
  if (opfPath == null) {
    throw const EbookFormatException('AZW3 缺 OPF 内容清单（容器不完整）');
  }
  final opfRaw = utf8.decode(read(opfPath)!, allowMalformed: true);
  XmlDocument opf;
  try {
    opf = XmlDocument.parse(opfRaw);
  } catch (_) {
    // catch-ok: OPF 是 XML；坏 XML 直接拒绝，不按正则硬抠元数据。
    throw const EbookFormatException('AZW3 的 OPF 内容清单解析失败（XML 损坏）');
  }

  final opfDir = _dirName(opfPath);
  final manifest = <String, _ManifestItem>{};
  for (final el in _allLocal(opf, 'item')) {
    final id = el.getAttribute('id');
    final href = el.getAttribute('href');
    if (id == null || href == null || href.trim().isEmpty) continue;
    manifest[id] = _ManifestItem(
      href: _resolve(opfDir, href),
      type: el.getAttribute('media-type') ?? '',
      props: el.getAttribute('properties') ?? '',
    );
  }

  final spine = <String>[];
  for (final el in _allLocal(opf, 'itemref')) {
    final id = el.getAttribute('idref');
    if (id != null && id.trim().isNotEmpty) spine.add(id);
  }

  final ordered = <_ManifestItem>[];
  if (spine.isEmpty) {
    // 部分 KF8 变体没有 spine：退回 manifest 中全部 XHTML（保持文档顺序）。
    ordered.addAll(manifest.values.where(_isHtml));
  } else {
    for (final id in spine) {
      final it = manifest[id];
      if (it != null && _isHtml(it)) ordered.add(it);
    }
  }

  final warnings = <String>[];
  final chapters = <TextChapter>[];
  var encoding = 'utf-8';
  for (final it in ordered) {
    if (it.isNav) continue;
    final raw = read(it.href);
    if (raw == null || raw.isEmpty) continue;
    final dec = decodeBookBytes(raw);
    if (dec.warning != null) warnings.add('${it.href}：${dec.warning}');
    if (dec.encoding != 'utf-8' && dec.encoding != 'utf-8-bom') {
      encoding = dec.encoding;
    }
    chapters.addAll(
      splitHtmlIntoChapters(
        dec.text,
        fallbackTitle: _stem(it.href) ?? '正文',
      ),
    );
  }

  if (chapters.isEmpty) {
    throw const EbookFormatException(
      'AZW3 容器内没有可读的 XHTML 正文（可能为 DRM 加密、损坏或不支持的 KF8 变体）',
    );
  }

  final title = _firstNonEmpty([
    _metaText(opf, 'title'),
    _stem(fileName),
    '未命名 AZW3',
  ])!;
  final author = _metaText(opf, 'creator') ?? '';

  return TextBookDraft(
    title: title,
    author: author,
    chapters: List<TextChapter>.unmodifiable(chapters),
    format: 'AZW3',
    fileName: fileName ?? '',
    encoding: encoding,
    warnings: List<String>.unmodifiable(warnings),
  );
}

class _ManifestItem {
  const _ManifestItem({
    required this.href,
    required this.type,
    required this.props,
  });

  final String href;
  final String type;
  final String props;

  bool get isNav => props.split(RegExp(r'\s+')).contains('nav');
}

bool _isHtml(_ManifestItem it) {
  final t = it.type.toLowerCase();
  if (t == 'application/xhtml+xml' || t == 'text/html') return true;
  final h = it.href.toLowerCase();
  return h.endsWith('.xhtml') || h.endsWith('.html') || h.endsWith('.htm');
}

String? _findOpf(
  Map<String, List<int>> files,
  Map<String, String> lower,
  List<int>? Function(String) read,
) {
  final container = read('META-INF/container.xml');
  if (container != null) {
    try {
      final doc = XmlDocument.parse(
        utf8.decode(container, allowMalformed: true),
      );
      for (final el in _allLocal(doc, 'rootfile')) {
        final p = el.getAttribute('full-path');
        if (p == null || p.trim().isEmpty) continue;
        final key = lower[p.toLowerCase()] ?? (files.containsKey(p) ? p : null);
        if (key != null) return key;
      }
    } catch (_) {
      // catch-ok: container.xml 坏掉时继续按 *.opf 探测，不因目录文件损坏直接失败。
    }
  }
  final candidates = files.keys
      .where((k) => k.toLowerCase().endsWith('.opf'))
      .toList()
    ..sort((a, b) {
      final ac = a.toLowerCase().endsWith('content.opf') ? 0 : 1;
      final bc = b.toLowerCase().endsWith('content.opf') ? 0 : 1;
      return ac != bc ? ac - bc : a.compareTo(b);
    });
  if (candidates.isEmpty) return null;
  return lower[candidates.first.toLowerCase()] ?? candidates.first;
}

Iterable<XmlElement> _allLocal(XmlNode node, String local) =>
    node.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == local,
    );

String? _metaText(XmlDocument doc, String local) {
  final md = _firstLocal(doc, 'metadata');
  final scope = md ?? doc;
  for (final el in _allLocal(scope, local)) {
    final t = el.innerText.trim();
    if (t.isNotEmpty) return t;
  }
  return null;
}

XmlElement? _firstLocal(XmlNode node, String local) {
  for (final e in node.descendants.whereType<XmlElement>()) {
    if (e.name.local == local) return e;
  }
  return null;
}

List<int> _bytesOf(ArchiveFile f) {
  final c = f.content;
  if (c is List<int>) return c;
  return (c as List).cast<int>();
}

String _dirName(String path) {
  final i = path.lastIndexOf('/');
  return i <= 0 ? '' : path.substring(0, i);
}

String _resolve(String baseDir, String href) {
  var h = href.split('#').first.split('?').first;
  try {
    h = Uri.decodeFull(h);
  } catch (_) {
    // catch-ok: 非法百分号编码保持原样，后续按文件名直读即可。
  }
  final parts = <String>[];
  for (final seg in (baseDir.isEmpty ? h : '$baseDir/$h').split('/')) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(seg);
  }
  return parts.join('/');
}

String? _firstNonEmpty(List<String?> values) {
  for (final v in values) {
    final s = (v ?? '').trim();
    if (s.isNotEmpty) return s;
  }
  return null;
}

String? _stem(String? path) {
  final n = (path ?? '').trim();
  if (n.isEmpty) return null;
  final base = n.replaceAll('\\', '/').split('/').last;
  final dot = base.lastIndexOf('.');
  final stem = dot > 0 ? base.substring(0, dot) : base;
  return stem.trim().isEmpty ? null : stem.trim();
}
