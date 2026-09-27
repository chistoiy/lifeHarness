import 'dart:io';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/book.dart';
import '../domain/book_toc.dart';
import 'epub_doc.dart';
import 'read_repository.dart';

/// 一次系统文件选择的结果（SAF 语义：只拿到被选文件本体）。
class EpubPick {
  const EpubPick({required this.name, required this.size, required this.path});

  /// 展示用文件名（含 .epub 后缀）。
  final String name;

  /// 字节数（0＝未知）。
  final int size;

  /// 可读临时路径（Android content uri 已由 file_picker 落缓存）。
  final String path;
}

/// 大文件提示阈值（原型「大文件：解析与分页预计算可能需要 1-2 分钟」口径）。
const kEpubBigFileBytes = 80 * 1024 * 1024;

/// 默认选文件：Android 13+ 经系统选择器（SAF），无需所有文件访问权限。
Future<EpubPick?> defaultPickEpub() async {
  final r = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['epub'],
    withData: false,
  );
  final f = r?.files.firstOrNull;
  if (f == null || f.path == null) return null;
  return EpubPick(name: f.name, size: f.size, path: f.path!);
}

/// 向导第 4 步可改的元信息草稿（EPUB metadata 预填）。
class EpubMetaDraft {
  const EpubMetaDraft({
    required this.title,
    required this.author,
    this.publisher,
    this.pubDate,
    this.intro,
  });

  final String title;
  final String author;
  final String? publisher;

  /// 出版日期原样（yyyy / yyyy-MM）。
  final String? pubDate;
  final String? intro;

  static EpubMetaDraft from(EpubDoc d) => EpubMetaDraft(
    title: d.title,
    author: d.author,
    publisher: d.publisher,
    pubDate: d.pubDate,
    intro: d.description,
  );
}

/// 本地 EPUB 导入服务（V1.50 批1 · 数据口径③）。
///
/// 落盘口径：**源文件保留原位，应用复制一份私有副本**到 `docs/epubs/<bookId>.epub`
/// （SAF 一次性读取授权下的最稳形态；「连源文件删除」删的是该副本 + 提示自删原件）；
/// 封面落 `docs/book_covers/epub_<bookId>.<ext>`（与 isbn 封面同目录不同名）；
/// 目录写既有 book_toc_nodes（与书摘章节下拉同源）。不新建任何表。
class EpubImportService {
  EpubImportService(
    this.repo, {
    this.pickHook,
    Directory? docsOverride,
  }) : _docsOverride = docsOverride;

  final ReadRepository repo;

  /// 测试注入点（同 BackupService.pickFileHook 惯例）：替换系统选择器。
  final Future<EpubPick?> Function()? pickHook;

  final Directory? _docsOverride;

  Future<EpubPick?> pick() => (pickHook ?? defaultPickEpub)();

  /// 读文件并解析；坏包/DRM 抛 [EpubFormatException]。
  /// 批3.5：走懒归档 openFile——大图文包解析不再整包进内存；
  /// 元数据/封面/目录抽取完立即释放句柄（不长期锁源文件，Windows 语义同理）。
  Future<EpubDoc> loadDoc(EpubPick pick) async {
    final doc = await EpubDoc.openFile(pick.path);
    doc.lazy?.dispose();
    return doc;
  }

  /// 同书重复守卫：先 ISBN 无从谈（本地包无 ISBN 时归一书名+作者），
  /// 命中走合并（书摘/计时/进度共用一条记录）。
  Future<Book?> findDup(EpubDoc doc) =>
      repo.findBookFor(title: doc.title, author: doc.author);

  /// 预估总页数（核对步展示 + books.pages 预填；批2 分页引擎实算后不改此值，
  /// 阅读内部页数体系与 books.pages 解耦，进度按百分比折算写回 read_pages）。
  static int estPages(EpubDoc d) => (d.totalChars / 600).ceil().clamp(1, 1 << 30);

  /// EPUB 目录 → 既有两级目录解析结构（无目录时单部分「正文」·每章一节）。
  static List<ParsedTocPart> tocParts(EpubDoc d) {
    if (d.toc.isEmpty) {
      final part = ParsedTocPart('正文');
      for (final c in d.chapters) {
        part.sections.add(c.title);
      }
      return [part];
    }
    final out = <ParsedTocPart>[];
    ParsedTocPart? cur;
    for (final t in d.toc) {
      if (t.level == 1 || cur == null) {
        cur = ParsedTocPart(t.level == 1 ? t.label : '');
        out.add(cur);
      }
      cur.sections.add(t.label);
    }
    return out;
  }

  /// 提交入库（新建或合并）。返回受影响的书记录（调用方 readTick++ 与角标渲染）。
  ///
  /// [tagLocal]＝「加入『本地』标签与来源分组」开关（原型默认开）。
  Future<Book> commit({
    required EpubPick pick,
    required EpubDoc doc,
    required EpubMetaDraft draft,
    bool tagLocal = true,
    Book? mergeInto,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (mergeInto != null) {
      // 合并：挂到已有记录，书摘/计时/进度共用一条；只补本地文件与标签。
      final path = await _copyEpub(mergeInto.id, pick.path);
      final tags = [...mergeInto.tags];
      if (tagLocal && !tags.contains('本地')) tags.add('本地');
      var updated = mergeInto.copyWith(
        local: true,
        epub: EpubRef(
          fmt: doc.format,
          size: pick.size,
          path: path,
          // 批3.5：挂回即重新预载；源文件位置留作「已清缓存→重新载入」探测。
          st: EpubRef.stPreload,
          srcPath: pick.path,
          srcName: pick.name,
        ),
        tags: tags,
      );
      if (doc.coverBytes != null && mergeInto.coverPath == null) {
        final cover = await _saveCover(mergeInto.id, doc);
        if (cover != null) {
          updated = updated.copyWith(coverPath: cover);
        }
      }
      await repo.updateBook(updated);
      return updated;
    }
    final created = await repo.addBook(
      Book(
        title: draft.title.isEmpty ? pick.name : draft.title,
        author: draft.author.isEmpty ? '佚名' : draft.author,
        publisher: draft.publisher,
        pubDate: draft.pubDate,
        intro: draft.intro,
        state: Book.kStateWant,
        format: Book.kFormatEbook,
        progressWay: Book.kWayPage,
        pages: estPages(doc),
        source: '本地导入',
        tags: tagLocal ? const ['本地'] : const [],
        local: true,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final path = await _copyEpub(created.id, pick.path);
    final withFile = created.copyWith(
      epub: EpubRef(
        fmt: doc.format,
        size: pick.size,
        path: path,
        st: EpubRef.stPreload,
        srcPath: pick.path,
        srcName: pick.name,
      ),
    );
    await repo.updateBook(withFile);
    final cover = await _saveCover(withFile.id, doc);
    if (cover != null) {
      await repo.updateBook(withFile.copyWith(coverPath: cover));
    }
    await repo.replaceToc(withFile.id, tocParts(doc));
    return (await repo.bookById(withFile.id)) ?? withFile;
  }

  /// 删除本地书时清私有副本（BrDel「连源文件删除」用 · 批4 接线）。
  static Future<void> deleteCopy(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }

  Future<String> _copyEpub(String bookId, String srcPath) async {
    final dir = p.join((await _docs()).path, 'epubs');
    await Directory(dir).create(recursive: true);
    final dst = p.join(dir, '$bookId.epub');
    await File(srcPath).copy(dst);
    return dst;
  }

  Future<String?> _saveCover(String bookId, EpubDoc doc) async {
    final bytes = doc.coverBytes;
    if (bytes == null || bytes.isEmpty) return null;
    final ext = _coverExt(doc.coverName ?? '');
    final dir = p.join((await _docs()).path, 'book_covers');
    await Directory(dir).create(recursive: true);
    final f = File(p.join(dir, 'epub_$bookId.$ext'));
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }

  static String _coverExt(String name) {
    final e = name.split('.').last.toLowerCase();
    return const {'jpg', 'jpeg', 'png', 'gif', 'webp'}.contains(e) ? e : 'jpg';
  }

  Future<Directory> _docs() async =>
      _docsOverride ?? await getApplicationDocumentsDirectory();
}
