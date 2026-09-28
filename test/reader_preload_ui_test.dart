import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/read/data/epub_cache.dart';
import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/presentation/shelf/book_detail.dart';
import 'package:lifeharness/features/read/presentation/import/local_import_page.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_page.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/shelf/shelf_page.dart';

// V1.50 批3.5 · 预载/清缓存 UI 流回归（独立文件防 isolate 污染）。
// 真 IO 步骤（预载落盘/重拷贝/释放统计）一律包在 tester.runAsync 内。

Uint8List _miniEpubBytes({String title = '守卫书'}) {
  List<int> x(String s) => utf8.encode(s);
  final arch = Archive();
  void add(String n, String s) {
    final b = x(s);
    arch.addFile(ArchiveFile(n, b.length, b));
  }
  add('mimetype', 'application/epub+zip');
  add(
    'META-INF/container.xml',
    '<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>',
  );
  add(
    'OEBPS/content.opf',
    '''<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>$title</dc:title><dc:creator>丁九</dc:creator></metadata>
<manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/></manifest>
<spine><itemref idref="c1"/></spine></package>''',
  );
  add(
    'OEBPS/nav.xhtml',
    '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>'
        '<nav epub:type="toc"><ol><li><a href="c1.xhtml">唯一的章</a></li></ol></nav></body></html>',
  );
  add(
    'OEBPS/c1.xhtml',
    '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><body>'
        '<p>第一段守卫内容。</p><p>第二段守卫内容。</p></body></html>',
  );
  return Uint8List.fromList(ZipEncoder().encode(arch)!);
}

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ReadRepository repo;
  late SharedPreferences prefs;
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = ReadRepository(db);
    tmp = Directory.systemTemp.createTempSync('lh_b35ui');
  });
  tearDown(() async {
    await db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  EpubPreloadService fakeSvc() => EpubPreloadService(
    repo,
    docsPath: tmp.path,
    parseOverride: (path) async => EpubDoc.parse(File(path).readAsBytesSync()),
    pump: () => Future<void>.value(),
  );

  List<Override> baseOverrides() => [
    readRepositoryProvider.overrideWithValue(repo),
    sharedPreferencesProvider.overrideWithValue(prefs),
    epubPreloadProvider.overrideWith((_) => fakeSvc()),
    epubCacheServiceProvider.overrideWithValue(
      EpubCacheService(repo, docsPath: tmp.path),
    ),
    epubDocLoaderProvider.overrideWithValue(
      (path) async => EpubDoc.parse(File(path).readAsBytesSync()),
    ),
  ];

  Future<void> step(WidgetTester t, {int ms = 200, int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await t.pump(Duration(milliseconds: ms));
    }
  }

  /// 造一本带 epub 引用 的书；copy/src 文件按需实体化。
  Future<Book> seed(
    String id, {
    required String st,
    bool makeCopy = true,
    bool makeSrc = true,
    int pr = 40,
  }) async {
    final src = '${tmp.path}/src_$id.epub';
    final copy = '${tmp.path}/copy_$id.epub';
    if (makeSrc) File(src).writeAsBytesSync(_miniEpubBytes(title: '守卫书$id'));
    if (makeCopy) File(copy).writeAsBytesSync(_miniEpubBytes(title: '守卫书$id'));
    return repo.addBook(
      Book(
        id: id,
        title: '守卫书$id',
        createdAt: 1,
        updatedAt: 1,
        local: true,
        state: Book.kStateReading,
        epub: EpubRef(
          fmt: 'EPUB3',
          size: 2048,
          path: copy,
          st: st,
          pr: pr,
          srcPath: src,
          srcName: 'src_$id.epub',
        ),
      ),
    );
  }

  Future<void> shelfWith(
    WidgetTester t,
    List<Override> extra,
  ) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const ShelfPage()),
      GoRoute(
        path: '/read/book/:id',
        builder: (_, s) => BookDetailPage(bookId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/read/reader/:id',
        builder: (_, s) => ReaderPage(bookId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/read/import-epub',
        builder: (_, s) =>
            Text('import:${s.uri.queryParameters['reattach'] ?? ''}'),
      ),
    ]);
    await useSurface(t);
    await t.pumpWidget(
      ProviderScope(overrides: [...baseOverrides(), ...extra], child: MaterialApp.router(routerConfig: router)),
    );
    await step(t, times: 5);
    await t.tap(find.byKey(const ValueKey('sh-chip-全部')));
    await step(t, times: 2);
  }

  group('批3.5-U · 预载守卫', () {
    testWidgets('预载书封面显进度层；点封面被守卫不进阅读器', (t) async {
      await seed('bp', st: EpubRef.stPreload, pr: 40);
      await shelfWith(t, const []);
      expect(find.byKey(const ValueKey('brCovPre-bp')), findsOne);
      expect(find.text('预载中 40%'), findsOne);
      await t.tap(find.byKey(const ValueKey('sh-item-bp')));
      await step(t, times: 2);
      expect(
        find.text('预载中 40%'),
        findsOne,
        reason: '守卫拦截后仍停留在书架',
      );
      expect(await pollText(t, '正在预载整本书 · 完成后可进入'), isTrue);
      await clearToasts(t);
    });

    testWidgets('阅读器防御页：预载书直达路由也只显守卫文案', (t) async {
      await seed('bd', st: EpubRef.stPreload);
      await useSurface(t);
      await t.pumpWidget(
        ProviderScope(
          overrides: baseOverrides(),
          child: MaterialApp(home: ReaderPage(bookId: 'bd')),
        ),
      );
      await step(t, times: 3);
      expect(find.text('正在预载整本书 · 完成后可进入'), findsOne);
    });
  });

  group('批3.5-U · 已清缓存三态', () {
    testWidgets('源文件仍在：点封面→重新载入弹层→确认后回预载', (t) async {
      await seed('cr', st: EpubRef.stCleared);
      await shelfWith(t, const []);
      expect(find.byKey(const ValueKey('brCovCleared-cr')), findsOne);
      await t.tap(find.byKey(const ValueKey('sh-item-cr')));
      await step(t, times: 2);
      expect(find.byKey(const ValueKey('brReloadOk')), findsOne);
      await t.runAsync(() async {
        await t.tap(find.byKey(const ValueKey('brReloadOk')));
        // 治理G6 悬案根治：预载服务在高负载下可超 400ms 定值（本用例曾随机挂+
        // G0 轮 database_closed 同族）→ 有界轮询直到状态回填，超时仍由下方断言判失败。
        for (var i = 0; i < 40; i++) {
          final bk = await repo.bookById('cr');
          if (bk?.epub?.state == EpubRef.stReady) break;
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      });
      await step(t, times: 3);
      final b = (await repo.bookById('cr'))!;
      expect(b.epub!.state, EpubRef.stReady, reason: '假解析秒完成 → rdy');
      expect(File(b.epub!.path).existsSync(), isTrue, reason: '副本已重拷');
      expect(
        File('${tmp.path}/epub_pag/cr.json').existsSync(),
        isTrue,
        reason: '分页表已落盘',
      );
    });

    testWidgets('源文件丢失：点封面→引导弹层→重新选择文件挂回', (t) async {
      final b = await seed('cl', st: EpubRef.stCleared, makeSrc: false);
      await shelfWith(t, const []);
      await t.tap(find.byKey(const ValueKey('sh-item-cl')));
      await step(t, times: 2);
      expect(find.text('源文件已不存在 · 《守卫书cl》'), findsOne);
      await t.tap(find.byKey(const ValueKey('brLostGo')));
      await step(t, times: 3);
      expect(find.text('import:${b.id}'), findsOne, reason: '带去重选标识');
    });

    testWidgets('详情本地卡：就绪态「清理缓存」→ 确认后文件回收记录保留', (t) async {
      await seed('cc', st: EpubRef.stReady);
      await useSurface(t);
      await t.pumpWidget(
        ProviderScope(
          overrides: baseOverrides(),
          child: MaterialApp(home: BookDetailPage(bookId: 'cc')),
        ),
      );
      await step(t, times: 4);
      // 轮5.3：整卡压成两行紧凑条，「清理缓存」收进「?」说明半屏（入口不减）。
      expect(find.byKey(const ValueKey('brDstrip')), findsOne);
      await t.tap(find.byKey(const ValueKey('brDinfo')));
      await step(t, times: 3);
      expect(find.byKey(const ValueKey('brLiClean')), findsOne);
      await t.runAsync(() async {
        await t.tap(find.byKey(const ValueKey('brLiClean')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await step(t, times: 2);
      expect(find.textContaining('清理缓存 · 《守卫书cc》'), findsOne);
      await t.runAsync(() async {
        await t.tap(find.byKey(const ValueKey('brCacheOk')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await step(t, times: 3);
      final b = (await repo.bookById('cc'))!;
      expect(b.epub!.state, EpubRef.stCleared);
      expect(File(b.epub!.path).existsSync(), isFalse, reason: '副本已回收');
      expect(b.title, '守卫书cc', reason: '记录保留');
    });

    testWidgets('挂回模式导入页：标题带 reattach 提示条', (t) async {
      final b = await seed('rb', st: EpubRef.stCleared, makeSrc: false);
      await useSurface(t);
      await t.pumpWidget(
        ProviderScope(
          overrides: baseOverrides(),
          child: MaterialApp(
            home: LocalImportPage(startStep: 2, reattachBookId: b.id),
          ),
        ),
      );
      await step(t, times: 3);
      expect(find.textContaining('正在为《守卫书rb》重新选择文件'), findsOne);
    });
  });
}
