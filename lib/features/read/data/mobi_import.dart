/// MOBI（PalmDOC 旧格式）→ [TextBookDraft]（纯 Dart、零新依赖）。
///
/// 链路：PDB 记录表 → record 0 的 MOBI 头/EXTH → 文本记录
/// （compression=1 原样 / 2 走 PalmDOC LZ77）→ UTF-8/GBK 解码 →
/// HTML 片段抽正文与章节（复用 [splitHtmlIntoChapters]）。
///
/// 显式拒绝（不静默降级）：DRM 加密、HUFF/CDIC 压缩、结构损坏。
library;

import 'ebook_exception.dart';
import 'ebook_html.dart';
import 'palmdoc.dart';
import 'text_import.dart';

/// MOBI 文件全量字节 → 文本草稿。
///
/// 坏包/DRM/不支持压缩抛 [EbookFormatException]（UI 原样展示 reason）；
/// 正文为空时不抛，返回带 warning 的空草稿（导入按钮会禁用）。
TextBookDraft parseMobiDraft(List<int> bytes, {String? fileName}) {
  if (bytes.isEmpty) {
    throw const EbookFormatException('文件为空（0 字节），没有可解析的 MOBI 内容');
  }

  final pdb = PdbFile.parse(bytes);
  if (pdb.recordCount < 2) {
    throw const EbookFormatException('MOBI 没有正文记录（文件损坏）');
  }

  final header = MobiHeader.parse(pdb.record(0));

  if (header.hasDrm) {
    throw EbookFormatException(
      'MOBI 文件已加密（DRM 类型 ${header.encryptionType}），本应用不提供解密；'
      '请先移除 DRM 或转成 EPUB 后重试',
    );
  }

  final compression = header.compression;
  if (compression != 1 && compression != 2) {
    throw EbookFormatException(
      'MOBI 使用 HUFF/CDIC 压缩（类型 $compression），零依赖下无法解压；'
      '请先转成 EPUB 后重试',
    );
  }

  final textRecords = header.textRecordCount > 0
      ? header.textRecordCount
      : pdb.recordCount - 1;
  final buf = <int>[];
  for (var i = 1; i <= textRecords && i < pdb.recordCount; i++) {
    final rec = pdb.record(i);
    if (rec.isEmpty) continue;
    if (compression == 2) {
      buf.addAll(palmdocDecompress(rec));
    } else {
      buf.addAll(rec);
    }
  }
  if (buf.isEmpty) {
    throw const EbookFormatException('MOBI 正文记录为空（文件损坏）');
  }

  final truncated = header.textLength > 0 && header.textLength <= buf.length
      ? buf.sublist(0, header.textLength)
      : buf;
  var decoded = decodeBookBytes(truncated);
  // textLength 截断可能切在多字节字符中间：UTF-8/GBK 都失败时退回完整缓冲再试。
  if (decoded.encoding == 'unknown' && truncated.length != buf.length) {
    final retry = decodeBookBytes(buf);
    if (retry.encoding != 'unknown') decoded = retry;
  }

  final title = _firstNonEmpty([
    header.exthString(503),
    header.fullName,
    _stem(fileName),
    pdb.name,
    '未命名 MOBI',
  ])!;
  final author = header.exthString(100) ?? '';

  final chapters = splitHtmlIntoChapters(decoded.text);
  final warnings = <String>[
    if (decoded.warning != null) decoded.warning!,
    if (chapters.isEmpty) 'MOBI 未解析出正文（文件可能损坏或为不支持的变体）',
  ];

  return TextBookDraft(
    title: title,
    author: author,
    chapters: chapters,
    format: 'MOBI',
    fileName: fileName ?? '',
    encoding: decoded.encoding,
    warnings: List<String>.unmodifiable(warnings),
  );
}

String? _firstNonEmpty(List<String?> values) {
  for (final v in values) {
    final s = (v ?? '').trim();
    if (s.isNotEmpty) return s;
  }
  return null;
}

String? _stem(String? fileName) {
  final n = (fileName ?? '').trim();
  if (n.isEmpty) return null;
  final base = n.replaceAll('\\', '/').split('/').last;
  final dot = base.lastIndexOf('.');
  final stem = dot > 0 ? base.substring(0, dot) : base;
  return stem.trim().isEmpty ? null : stem.trim();
}
