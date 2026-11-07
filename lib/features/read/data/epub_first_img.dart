import 'dart:io';

import 'package:path/path.dart' as p;

import 'epub_doc.dart';

/// R14-4 A 档回落：把 EPUB 正文第一张图落盘为「封面衍生件」
/// （`docs/book_covers/epub_<bookId>-fi.<ext>`，路径写入 books.first_img·DB v32）。
///
/// 生成时机＝导入提交与整本预载完成；幂等：衍生文件仍在则直接复用。
/// 生命周期与包内封面衍生件一致：单书清缓存一并回收（[EpubCacheService.clear]），
/// 源文件恢复重预载后再生；记录本身与书摘/计时/进度无关，绝不动用户数据。
class EpubFirstImg {
  const EpubFirstImg._();

  /// 返回衍生文件路径；正文取不到图 / 字节为空 → null。
  static Future<String?> ensure({
    required String docsPath,
    required String bookId,
    required EpubDoc doc,
    String? existing,
  }) async {
    if (existing != null && existing.isNotEmpty && await File(existing).exists()) {
      return existing;
    }
    final src = doc.firstBodyImageSrc();
    if (src == null) return null;
    final bytes = doc.imageBytes(src);
    if (bytes == null || bytes.isEmpty) return null;
    final dir = p.join(docsPath, 'book_covers');
    await Directory(dir).create(recursive: true);
    final f = File(p.join(dir, 'epub_$bookId-fi.${ext(src)}'));
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }

  /// 与 epub_import._coverExt 同口径的扩展名归一。
  static String ext(String name) {
    final e = name.split('.').last.toLowerCase();
    return const {'jpg', 'jpeg', 'png', 'gif', 'webp'}.contains(e) ? e : 'jpg';
  }
}
