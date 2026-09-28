import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/data/epub_import.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/domain/book_quote.dart';

// V1.50 批1 · 阅读器数据层（DB v25 四列 / 模型往返 / 导入服务落库与合并）。
// 独立文件防 isolate 污染；纯数据测试允许真 IO（非 widget FakeAsync 环境）。

Uint8List _miniEpub({String title = '导入测试书', String author = '丙一'}) {
  String enc(String s) => s;
  ArchiveFile b(String n, String c) => ArchiveFile(n, utf8.encode(c).length, utf8.encode(c));
  final files = <ArchiveFile>[
    ArchiveFile('mimetype', 'application/epub+zip'.length, utf8.encode('application/epub+zip')),
    b(
      'META-INF/container.xml',
      '<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
          '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
    ),
    b(
      'OEBPS/content.opf',
      '''<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>${enc(title)}</dc:title><dc:creator>${enc(author)}</dc:creator><dc:description>导入简介</dc:description></metadata>
<manifest>
  <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
  <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
  <item id="cov" href="cover.png" media-type="image/png" properties="cover-image"/>
</manifest>
<spine><itemref idref="c1"/></spine></package>''',
    ),
    b(
      'OEBPS/nav.xhtml',
      '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>'
          '<nav epub:type="toc"><ol><li><a href="c1.xhtml">唯一的章</a></li></ol></nav></body></html>',
    ),
    b(
      'OEBPS/c1.xhtml',
      '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><body>'
          '<p>第一段内容，用于导入链路。</p><p>第二段内容。</p></body></html>',
    ),
    ArchiveFile('OEBPS/cover.png', 4, [1, 2, 3, 4]),
  ];
  final arch = Archive();
  for (final f in files) {
    arch.addFile(f);
  }
  return Uint8List.fromList(ZipEncoder().encode(arch)!);
}

void main() {
  sqfliteFfiInit();

  late Database db;
  late ReadRepository repo;
  late Directory docs;
  late Directory picks;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = ReadRepository(db);
    docs = Directory.systemTemp.createTempSync('lh_docs');
    picks = Directory.systemTemp.createTempSync('lh_picks');
  });
  tearDown(() async {
    await db.close();
    docs.deleteSync(recursive: true);
    picks.deleteSync(recursive: true);
  });

  EpubImportService svc() =>
      EpubImportService(repo, docsOverride: docs);

  Future<EpubPick> pickOf(Uint8List bytes, {String name = '导入测试书.epub'}) async {
    final f = File('${picks.path}/$name')..writeAsBytesSync(bytes);
    return EpubPick(name: name, size: bytes.length, path: f.path);
  }

  final now = DateTime(2026, 9, 27).millisecondsSinceEpoch;

  group('批1-IM · DB v25', () {
    // 版本号不钉死：本用例只保证「v24→v25 的四列迁移与建库段同文双写」，
    // 后续批次（V1.53 用 v26 建 ai_calls）继续加版本时不该回头改这里（时间炸弹口径）。
    test('version>=25 · migrations[24] 四列与建库段同文双写', () {
      expect(DbSchema.version, greaterThanOrEqualTo(25));
      expect(DbSchema.migrations[24], hasLength(4));
      expect(
        DbSchema.migrations[24]!.join(';'),
        allOf(
          contains('books ADD COLUMN local'),
          contains('books ADD COLUMN epub'),
          contains('book_quotes ADD COLUMN cf'),
          contains('book_quotes ADD COLUMN rid'),
        ),
      );
    });

    test('PRAGMA：books.local/epub 与 book_quotes.cf/rid 落位', () async {
      final bc = (await db.rawQuery('PRAGMA table_info(books)'))
          .map((c) => c['name'] as String)
          .toList();
      expect(bc, containsAll(['local', 'epub']));
      final qc = (await db.rawQuery('PRAGMA table_info(book_quotes)'))
          .map((c) => c['name'] as String)
          .toList();
      expect(qc, containsAll(['cf', 'rid']));
    });
  });

  group('批1-IM · 模型往返', () {
    test('Book local/epub 存取；坏 epub JSON 回 null', () async {
      await repo.addBook(
        Book(
          id: 'x1',
          title: '本地书',
          createdAt: now,
          updatedAt: now,
          local: true,
          epub: const EpubRef(fmt: 'EPUB3', size: 1234, path: '/a/b.epub'),
        ),
      );
      final b = await repo.bookById('x1');
      expect(b!.local, isTrue);
      expect(b.epub?.fmt, 'EPUB3');
      expect(b.epub?.size, 1234);
      await db.update('books', {'epub': '{坏数据'}, where: 'id = ?', whereArgs: ['x1']);
      expect((await repo.bookById('x1'))!.epub, isNull);
    });

    test('BookQuote cf/rid 往返 · QuoteCf.covers 命中区间', () async {
      final id = await repo.addQuote(
        BookQuote(
          bookId: 'x1',
          kind: BookQuote.kKindMark,
          body: '划线',
          createdAt: now,
          updatedAt: now,
          cf: const QuoteCf(c: 2, p0: 3, p1: 5),
          rid: 'r77',
        ),
      );
      final q = await repo.quoteById(id!);
      expect(q!.rid, 'r77');
      expect(q.cf!.covers(2, 4), isTrue);
      expect(q.cf!.covers(2, 6), isFalse);
      expect(q.cf!.covers(1, 4), isFalse);
      expect(jsonDecode(q.toRow()['cf'] as String), {'c': 2, 'p0': 3, 'p1': 5});
    });
  });

  group('批1-IM · 导入服务', () {
    test('tocParts：nav 两级 → ParsedTocPart；estPages>0', () {
      final doc = EpubDoc.parse(_miniEpub());
      final parts = EpubImportService.tocParts(doc);
      expect(parts, hasLength(1));
      expect(parts.first.sections, ['唯一的章']);
      expect(EpubImportService.estPages(doc), greaterThan(0));
    });

    test('新书落库：local/标签/来源/epub 副本/封面/toc 同源目录', () async {
      final bytes = _miniEpub();
      final p = await pickOf(bytes);
      final doc = await svc().loadDoc(p);
      expect(await svc().findDup(doc), isNull);
      final b = await svc().commit(
        pick: p,
        doc: doc,
        draft: EpubMetaDraft.from(doc),
      );
      expect(b.local, isTrue);
      expect(b.source, '本地导入');
      expect(b.tags, contains('本地'));
      expect(b.state, Book.kStateWant);
      expect(b.format, Book.kFormatEbook);
      expect(b.pages, greaterThan(0));
      expect(File(b.epub!.path).existsSync(), isTrue);
      expect(b.epub!.fmt, 'EPUB3');
      expect(b.epub!.size, bytes.length);
      expect(File(b.coverPath!).existsSync(), isTrue);
      final toc = await repo.tocOf(b.id);
      expect(toc.map((t) => t.title), containsAll(['唯一的章']));
      // 合并守卫：同书再导命中已有记录
      expect((await svc().findDup(doc))?.id, b.id);
    });

    test('合并：同书二次导入挂已有记录，条目仍一条且共用书摘', () async {
      final exist = await repo.addBook(
        Book(
          id: 'e1',
          title: '导入测试书',
          author: '旧作者',
          state: Book.kStateReading,
          pages: 100,
          readPages: 40,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await repo.addQuote(
        BookQuote(
          bookId: exist.id,
          kind: BookQuote.kKindThought,
          body: '既有感想',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final p = await pickOf(_miniEpub());
      final doc = await svc().loadDoc(p);
      final dup = await svc().findDup(doc);
      expect(dup?.id, 'e1');
      final merged = await svc().commit(
        pick: p,
        doc: doc,
        draft: EpubMetaDraft.from(doc),
        mergeInto: dup,
      );
      expect(merged.id, 'e1');
      expect(merged.local, isTrue);
      expect(merged.tags, contains('本地'));
      expect(merged.state, Book.kStateReading); // 记录状态不被覆盖
      final all = await repo.allBooks();
      expect(all.where((x) => !x.isDeleted), hasLength(1));
      expect((await repo.quotesOf('e1')).length, 1); // 书摘共用
    });

    test('tagLocal 关：不打「本地」标签（来源分组仍登记）', () async {
      final p = await pickOf(_miniEpub(title: '无标签书'));
      final doc = await svc().loadDoc(p);
      final b = await svc().commit(
        pick: p,
        doc: doc,
        draft: EpubMetaDraft.from(doc),
        tagLocal: false,
      );
      expect(b.tags, isEmpty);
      expect(b.source, '本地导入');
    });

    test('deleteCopy 清私有副本', () async {
      final p = await pickOf(_miniEpub(title: '删除书'));
      final doc = await svc().loadDoc(p);
      final b = await svc().commit(pick: p, doc: doc, draft: EpubMetaDraft.from(doc));
      final path = b.epub!.path;
      expect(File(path).existsSync(), isTrue);
      await EpubImportService.deleteCopy(path);
      expect(File(path).existsSync(), isFalse);
    });
  });
}
