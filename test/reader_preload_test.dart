import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/read/data/epub_cache.dart';
import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/presentation/reader_pager.dart';

// V1.50 批3.5 · 导入预载 + 大书内存模型 + 单书清缓存（数据层回归）。
// 独立文件防 isolate 污染；纯数据测试允许真 IO（非 widget FakeAsync 环境）。
// 断言四件套：open 不解压图片 / LRU 受控 / 分页表命中秒进 / 清缓存原文件不删。

Uint8List _epubWithImages({int chapters = 3, int images = 15}) {
  List<int> x(String s) => utf8.encode(s);
  final arch = Archive();
  void add(String n, List<int> b) => arch.addFile(ArchiveFile(n, b.length, b));
  add('mimetype', x('application/epub+zip'));
  add(
    'META-INF/container.xml',
    x('<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>'),
  );
  final manifest = StringBuffer(
    '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>',
  );
  final spine = StringBuffer();
  for (var i = 0; i < chapters; i++) {
    manifest.write(
      '<item id="c$i" href="c$i.xhtml" media-type="application/xhtml+xml"/>',
    );
    spine.write('<itemref idref="c$i"/>');
    final imgs = List.generate(
      images ~/ chapters + (i < images % chapters ? 1 : 0),
      (k) => k,
    );
    for (final k in imgs) {
      manifest.write(
        '<item id="i${i}_$k" href="img${i}_$k.png" media-type="image/png"/>',
      );
      // 压缩存储以区分「读到＝真解压」；内容够长制造解压量。
      add(
        'OEBPS/img${i}_$k.png',
        List<int>.generate(2048, (b) => (b * 7 + i * 13 + k) % 256),
      );
    }
    add(
      'OEBPS/c$i.xhtml',
      x(
        '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><body>'
        '<p>第 $i 章正文段落，用于分页与预载链路验证。</p>'
        '${(imgs).map((k) => '<img src="img${i}_$k.png" alt="图$k"/>').join()}'
        '</body></html>',
      ),
    );
  }
  add(
    'OEBPS/content.opf',
    x('''<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>预载测试书</dc:title><dc:creator>丁九</dc:creator></metadata>
<manifest>$manifest</manifest>
<spine>$spine</spine></package>'''),
  );
  add(
    'OEBPS/nav.xhtml',
    x(
      '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>'
      '<nav epub:type="toc"><ol>${List.generate(chapters, (i) => '<li><a href="c$i.xhtml">第 $i 章</a></li>').join()}</ol></nav>'
      '</body></html>',
    ),
  );
  return Uint8List.fromList(ZipEncoder().encode(arch)!);
}

void main() {
  sqfliteFfiInit();

  late Database db;
  late ReadRepository repo;
  late Directory tmp;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = ReadRepository(db);
    tmp = Directory.systemTemp.createTempSync('lh_b35');
  });
  tearDown(() async {
    await db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  String epubFile(String name, Uint8List bytes) {
    final f = File('${tmp.path}/$name');
    f.writeAsBytesSync(bytes);
    return f.path;
  }

  group('批3.5 · 懒归档与图片 LRU', () {
    test('openFile：章文本全量驻留、图片零解码', () async {
      final path = epubFile('book.epub', _epubWithImages());
      final doc = await EpubDoc.openFile(path);
      expect(doc.chapters.length, 3);
      expect(doc.imageCount, 15);
      expect(doc.lazy, isNotNull);
      expect(doc.lazy!.cachedImageCount, 0, reason: 'open 不得解压任何图片');
      // 文本条目已按需解码（含封面缺失时的元数据若干），图片不在其中。
      expect(
        doc.lazy!.decodedTotal,
        lessThan(12),
        reason: '解码只覆盖元数据+3 章文本',
      );
      doc.lazy?.dispose();
    });

    test('imageBytes 按需解码 + LRU ≤12 张双约束', () async {
      final path = epubFile('book.epub', _epubWithImages());
      final doc = await EpubDoc.openFile(path);
      final imgs = [
        for (final c in doc.chapters)
          for (final p in c.paras)
            if (p.kind == EpubParaKind.image) p.imgSrc,
      ];
      expect(imgs.length, 15);
      for (final src in imgs.take(12)) {
        expect(doc.imageBytes(src), isNotNull);
      }
      expect(doc.lazy!.cachedImageCount, 12);
      // 第 13 张进来：最早驻留的逐出。
      expect(doc.imageBytes(imgs[12]), isNotNull);
      expect(doc.lazy!.cachedImageCount, 12);
      // 重复访问不增解码计数（LRU 命中）。
      final before = doc.lazy!.decodedTotal;
      doc.imageBytes(imgs[13 - 1]);
      expect(doc.lazy!.decodedTotal, before);
      doc.lazy?.dispose();
    });

    test('parse 与 openFile 口径一致（测试路径保留）', () async {
      final path = epubFile('book.epub', _epubWithImages(chapters: 2, images: 4));
      final lazy = await EpubDoc.openFile(path);
      final mem = EpubDoc.parse(File(path).readAsBytesSync());
      expect(mem.chapters.length, lazy.chapters.length);
      expect(mem.totalChars, lazy.totalChars);
      expect(mem.images.length, 4, reason: '内存路径整表预填照旧');
      expect(lazy.images, isEmpty);
      lazy.lazy?.dispose();
    });

    test('openFileDetached：isolate 解析回主 isolate 后图片 LRU 照常', () async {
      final path = epubFile('iso.epub', _epubWithImages(chapters: 2, images: 5));
      final doc = await EpubDoc.openFileDetached(path);
      expect(doc.chapters.length, 2);
      expect(doc.totalChars, greaterThan(0));
      expect(doc.lazy, isNotNull, reason: '主 isolate 重挂懒归档句柄');
      expect(doc.lazy!.cachedImageCount, 0);
      final imgs = [
        for (final c in doc.chapters)
          for (final p in c.paras)
            if (p.kind == EpubParaKind.image) p.imgSrc,
      ];
      expect(doc.imageBytes(imgs.first), isNotNull);
      expect(doc.lazy!.cachedImageCount, 1);
      doc.lazy?.dispose();
    });
  });

  group('批3.5 · EpubRef 状态列', () {
    test('旧 JSON（无 st）读回＝就绪', () {
      final r = EpubRef.decode('{"fmt":"EPUB3","size":1,"path":"/a.epub"}');
      expect(r!.state, 'rdy');
      expect(r.cleared, isFalse);
    });
    test('新字段往返 + copyWith', () {
      final r = const EpubRef(
        fmt: 'EPUB3',
        size: 2,
        path: '/a.epub',
        st: EpubRef.stPreload,
        pr: 40,
        srcPath: '/s/a.epub',
        srcName: 'a.epub',
      );
      final back = EpubRef.decode(r.encode())!;
      expect(back.state, 'pre');
      expect(back.pr, 40);
      expect(back.srcPath, '/s/a.epub');
      expect(back.copyWith(st: EpubRef.stCleared, pr: 0).state, 'cl');
    });
  });

  group('批3.5 · 分页表落盘', () {
    ReaderLayout layout() => const ReaderLayout(width: 400, height: 800);
    // 轮4②：表带字符权重（进度加权），未排版章在表里为 null。
    BookPagination pag() => BookPagination.fromTable(
      [60, 30],
      [
        [
          [0, 1],
          [2],
        ],
        [
          [0],
        ],
      ],
    );

    test('指纹命中读回；外观变化即失效', () async {
      final fp = PagStore.fingerprint(layout());
      await PagStore.save(tmp.path, 'bk1', fp, pag());
      final hit = await PagStore.load(tmp.path, 'bk1', fp, [60, 30]);
      expect(hit, isNotNull);
      expect(hit!.totalChars, 90);
      expect(hit.chapterCount, 2);
      expect(hit.pages[0], [
        [0, 1],
        [2],
      ]);
      expect(hit.pages[1], [[0]]);
      expect(await PagStore.load(tmp.path, 'bk1', '$fp|fs22', [60, 30]), isNull);
      await PagStore.remove(tmp.path, 'bk1');
      expect(await PagStore.load(tmp.path, 'bk1', fp, [60, 30]), isNull);
    });

    test('null 章（未排版）原样往返', () async {
      final fp = PagStore.fingerprint(layout());
      final withNull = BookPagination.fromTable([10, 20], [
        [
          [0],
        ],
        null,
      ]);
      await PagStore.save(tmp.path, 'bk2', fp, withNull);
      final hit = await PagStore.load(tmp.path, 'bk2', fp, [10, 20]);
      expect(hit, isNotNull);
      expect(hit!.laidOut(0), isTrue);
      expect(hit.laidOut(1), isFalse);
      expect(hit.totalChars, 30);
      await PagStore.remove(tmp.path, 'bk2');
    });
  });

  group('批3.5 · 整本预载', () {
    Future<Book> seedBook(String id, {String? srcPath}) async => repo.addBook(
      Book(
        id: id,
        title: '预载书$id',
        createdAt: 1,
        updatedAt: 1,
        local: true,
        epub: EpubRef(
          fmt: 'EPUB3',
          size: 10,
          path: '${tmp.path}/copy_$id.epub',
          st: EpubRef.stPreload,
          srcPath: srcPath,
        ),
      ),
    );

    test('预载全程：pre→分页落盘→rdy；文档缓存秒进', () async {
      final src = epubFile('src.epub', _epubWithImages(chapters: 3, images: 4));
      File(src).copySync('${tmp.path}/copy_b1.epub');
      final b = await seedBook('b1', srcPath: src);
      final svc = EpubPreloadService(
        repo,
        docsPath: tmp.path,
        pump: () => Future<void>.value(),
      );
      const layout = ReaderLayout(width: 400, height: 800);
      await svc.preload(b, layout);
      final after = (await repo.bookById('b1'))!;
      expect(after.epub!.state, 'rdy');
      expect(svc.docs.get('b1'), isNotNull, reason: '预载完即内存驻留＝秒进');
      final tab = await svc.loadPag(
        'b1',
        layout,
        svc.docs.get('b1')?.chapterCharCounts ?? const [],
      );
      expect(tab, isNotNull);
      expect(tab!.chapterCount, greaterThanOrEqualTo(3));
      expect(svc.info('b1')?.error, isNull);
      svc.docs.clear();
    });

    test('坏包预载失败：回 rdy 不卡书架，进度带错误', () async {
      File('${tmp.path}/copy_b2.epub').writeAsBytesSync([0, 1, 2, 3]);
      final b = await seedBook('b2');
      final svc = EpubPreloadService(
        repo,
        docsPath: tmp.path,
        pump: () => Future<void>.value(),
      );
      await svc.preload(b, const ReaderLayout(width: 400, height: 800));
      final after = (await repo.bookById('b2'))!;
      expect(after.epub!.state, 'rdy', reason: '失败不锁死入口，进阅读再报错');
      expect(svc.info('b2')?.error, isNotNull);
    });
  });

  group('批3.5 · 单书清缓存三态', () {
    Future<({Book b, String src, String copy, String cover})> seed() async {
      final src = epubFile('src.epub', _epubWithImages(chapters: 1, images: 2));
      final copy = '${tmp.path}/copy_b1.epub';
      File(src).copySync(copy);
      final cover = '${tmp.path}/book_covers';
      Directory(cover).createSync();
      final coverFile = File('$cover/epub_b1.png')..writeAsBytesSync([1, 2]);
      final b = await repo.addBook(
        Book(
          id: 'b1',
          title: '清缓存书',
          createdAt: 1,
          updatedAt: 1,
          local: true,
          coverPath: coverFile.path,
          epub: EpubRef(
            fmt: 'EPUB3',
            size: 10,
            path: copy,
            srcPath: src,
            srcName: 'src.epub',
          ),
        ),
      );
      await PagStore.save(
        tmp.path,
        'b1',
        PagStore.fingerprint(const ReaderLayout(width: 400, height: 800)),
        BookPagination.fromTable([7], <List<List<int>>?>[
          [
            [0],
          ],
        ]),
      );
      return (b: b, src: src, copy: copy, cover: coverFile.path);
    }

    test('清理只回收副本/封面衍生/分页表；源文件与记录全保留', () async {
      final s = await seed();
      final svc = EpubCacheService(repo, docsPath: tmp.path);
      expect(await svc.estimateRelease(s.b), greaterThan(0));
      await svc.clear(s.b);
      expect(File(s.copy).existsSync(), isFalse);
      expect(File(s.cover).existsSync(), isFalse);
      expect(await PagStore.load(tmp.path, 'b1', 'x', const [7]), isNull);
      expect(File(s.src).existsSync(), isTrue, reason: '原文件绝不删除');
      final after = (await repo.bookById('b1'))!;
      expect(after.epub!.state, 'cl');
      expect(after.title, '清缓存书', reason: '记录保留（同一条书籍行）');
      expect(after.coverPath, isNotNull, reason: '指针保留，重挂回时复用');
    });

    test('三态分流：源在＝可重载；源删＝需重选', () async {
      final s = await seed();
      final svc = EpubCacheService(repo, docsPath: tmp.path);
      await svc.clear(s.b);
      final b = (await repo.bookById('b1'))!;
      expect(await svc.restoreKind(b), EpubRestore.reloadFromSource);
      File(s.src).deleteSync();
      expect(await svc.restoreKind(b), EpubRestore.needRepick);
      // 重新拷贝（源在时）→ 副本回到原位。
      
      final s2 = await seed();
      await svc.clear(s2.b);
      final b2 = (await repo.bookById('b1'))!;
      await svc.recopyFromSource(b2);
      expect(File(s2.copy).existsSync(), isTrue);
    });
  });

  // —— 真实 EPUB 回归（用户 2026-09-28 提供的两本下载书）——
  group('批3.5 · 真实大书回归', () {
    final home = Platform.environment['USERPROFILE'] ?? '';
    final agatha = File(
      '$home\\Downloads\\阿加莎·克里斯蒂侦探小说大全集（全85册） (阿加莎·_ (z-library.sk, 1lib.sk, z-lib.sk).epub',
    );
    final sapiens = File(
      '$home\\Downloads\\人类简史  从动物到上帝 = Sapiens A Br_ (z-library.sk, 1lib.sk, z-lib.sk).epub',
    );

    test('阿加莎大全集 26.5MB：open 零图解码 + 2409 章解析不崩', () async {
      if (!agatha.existsSync()) return; // 素材不在＝跳过（CI 无本地下载目录）
      final t0 = DateTime.now();
      final doc = await EpubDoc.openFile(agatha.path);
      final ms = DateTime.now().difference(t0).inMilliseconds;
      expect(doc.chapters.length, greaterThan(2000));
      expect(doc.imageCount, greaterThanOrEqualTo(124));
      expect(doc.lazy!.cachedImageCount, 0, reason: '百 MB 级不整包图解码');
      // 图片按需：取 20 张，LRU 驻留必须 ≤12。
      final imgs = <String>[];
      for (final c in doc.chapters) {
        for (final p in c.paras) {
          if (p.kind == EpubParaKind.image) imgs.add(p.imgSrc);
          if (imgs.length >= 20) break;
        }
        if (imgs.length >= 20) break;
      }
      for (final src in imgs) {
        expect(doc.imageBytes(src), isNotNull);
        expect(doc.lazy!.cachedImageCount, lessThanOrEqualTo(12));
      }
      doc.lazy?.dispose();
      // ignore: avoid_print
      print('B35-REAL agatha open ${ms}ms chapters=${doc.chapters.length}');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('人类简史 2.2MB：图文混排链路对照', () async {
      if (!sapiens.existsSync()) return;
      final doc = await EpubDoc.openFile(sapiens.path);
      expect(doc.chapters.length, greaterThan(10));
      expect(doc.lazy!.cachedImageCount, 0);
      doc.lazy?.dispose();
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
