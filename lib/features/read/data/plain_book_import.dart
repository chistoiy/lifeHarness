/// C12 · TXT / FB2 草稿 → 可读书籍（最小 EPUB 落盘 + books/book_toc 登记）。
///
/// 只复用既有链路：`ReadRepository.addBook/updateBook/replaceToc` 与
/// `docs/epubs/<bookId>.epub` 私有副本口径（与 EPUB 导入同目录、同预载入口）。
/// 不做任何网络请求，也不新增表/列。
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/book.dart';
import '../domain/book_toc.dart';
import 'read_repository.dart';
import 'text_import.dart';

class PlainBookImportService {
  PlainBookImportService(this.repo, {Directory? docsOverride})
      : _docsOverride = docsOverride;

  final ReadRepository repo;
  final Directory? _docsOverride;

  /// 落库：先建书记录拿 id，再写 `docs/epubs/<id>.epub`，最后补 epub 描述与目录。
  /// 任一写入失败即抛出（由调用方 toast），不留下「书在架但打不开」的半成品。
  Future<Book> commit(TextBookDraft draft, {bool tagLocal = true}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final est = (draft.charCount / 600).ceil();
    final pages = est < 1 ? 1 : est;
    final created = await repo.addBook(
      Book(
        title: draft.title.trim().isEmpty ? '未命名文本' : draft.title.trim(),
        author: draft.author.trim().isEmpty ? '佚名' : draft.author.trim(),
        format: Book.kFormatEbook,
        progressWay: Book.kWayPos,
        pages: pages,
        source: '本地文本导入',
        tags: tagLocal ? const ['本地'] : const [],
        local: true,
        intro: '由 ${draft.format} 文本本地转换 · 章节 ${draft.chapters.length} · '
            '${draft.charCount} 字',
        createdAt: now,
        updatedAt: now,
        lastReadAt: now,
      ),
    );

    final bytes = buildEpubBytes(draft, bookId: created.id);
    final dir = p.join((await _docs()).path, 'epubs');
    await Directory(dir).create(recursive: true);
    final path = p.join(dir, '${created.id}.epub');
    await File(path).writeAsBytes(bytes, flush: true);

    final withFile = created.copyWith(
      epub: EpubRef(
        fmt: 'epub',
        size: bytes.length,
        path: path,
        st: EpubRef.stReady,
        srcName: draft.fileName.isEmpty ? null : draft.fileName,
      ),
      updatedAt: now,
    );
    await repo.updateBook(withFile);

    final part = ParsedTocPart('正文');
    for (final c in draft.chapters) {
      part.sections.add(c.title);
    }
    if (part.sections.isEmpty) part.sections.add('正文');
    await repo.replaceToc(created.id, [part]);

    return (await repo.bookById(created.id)) ?? withFile;
  }

  Future<Directory> _docs() async =>
      _docsOverride ?? await getApplicationDocumentsDirectory();
}
