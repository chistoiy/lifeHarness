import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:lifeharness/features/read/data/epub_import.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/presentation/open_with.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_pager.dart'
    show ReaderLayout;
import 'package:lifeharness/features/read/presentation/shelf/shelf_page.dart';

// V1.53.4⑥ 系统「打开方式」EPUB→导入 · 独立文件（全 app 级 pump 拆分铁律）。
// 通道走 TestDefaultBinaryMessenger mock，doc/导入/预载全 fake，FakeAsync 下
// 不触真磁盘（既有踩坑：测禁真异步 I/O）。

Uint8List _miniEpubBytes({String title = '打开测试书', String author = '丁一'}) {
  ArchiveFile f(String n, List<int> b) => ArchiveFile(n, b.length, b);
  List<int> x(String s) => utf8.encode(s);
  final arch = Archive();
  for (final e in <(String, List<int>)>[
    ('mimetype', x('application/epub+zip')),
    (
      'META-INF/container.xml',
      x(
        '<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>',
      ),
    ),
    (
      'OEBPS/content.opf',
      x(
        '''<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>$title</dc:title><dc:creator>$author</dc:creator></metadata>
<manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/></manifest>
<spine><itemref idref="c1"/></spine></package>''',
      ),
    ),
    (
      'OEBPS/nav.xhtml',
      x(
        '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>'
        '<nav epub:type="toc"><ol><li><a href="c1.xhtml">唯一的章</a></li></ol></nav></body></html>',
      ),
    ),
    (
      'OEBPS/c1.xhtml',
      x(
        '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><body>'
        '<p>第一段内容，用于打开方式链路。</p><p>第二段内容。</p></body></html>',
      ),
    ),
  ]) {
    arch.addFile(f(e.$1, e.$2));
  }
  return Uint8List.fromList(ZipEncoder().encode(arch)!);
}

class _FakeImport extends EpubImportService {
  _FakeImport(super.repo);

  Book? dup;
  Book? commitResult;
  bool committed = false;
  EpubMetaDraft? lastDraft;

  @override
  Future<Book?> findDup(EpubDoc d) async => dup;

  @override
  Future<Book> commit({
    required EpubPick pick,
    required EpubDoc doc,
    required EpubMetaDraft draft,
    bool tagLocal = true,
    Book? mergeInto,
  }) async {
    committed = true;
    lastDraft = draft;
    return commitResult ??
        await repo.addBook(
          Book(
            id: '',
            title: draft.title,
            author: draft.author,
            local: true,
            createdAt: 1,
            updatedAt: 1,
          ),
        );
  }
}

class _NoopPreload extends EpubPreloadService {
  _NoopPreload(super.repo);
  final started = <String>[];

  @override
  Future<void> preload(Book b, ReaderLayout layout) async {
    started.add(b.id);
  }
}

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ReadRepository repo;
  late SharedPreferences prefs;
  const channel = MethodChannel('lh/intents');
  String? channelReturn;
  late _FakeImport fake;
  late _NoopPreload preloadSvc;
  bool loaderThrows = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = ReadRepository(db);
    fake = _FakeImport(repo);
    preloadSvc = _NoopPreload(repo);
    channelReturn = null;
    loaderThrows = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => channelReturn);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    brOpenFileSize = (path) => Future.value(0);
    await db.close();
  });

  // 装配：根导航 + 两条路由（HOME 与 /read/shelf），Consumer 捕获 ref。
  WidgetRef? capRef;
  late GlobalKey<NavigatorState> nav;
  Future<void> pumpApp(WidgetTester t) async {
    await useSurface(t);
    nav = GlobalKey<NavigatorState>();
    final router = GoRouter(
      navigatorKey: nav,
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Consumer(
            builder: (ctx, ref, _) {
              capRef = ref;
              return const Scaffold(body: Center(child: Text('HOME')));
            },
          ),
        ),
        GoRoute(
          path: '/read/shelf',
          builder: (_, _) => const ShelfPage(),
        ),
      ],
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          readRepositoryProvider.overrideWithValue(repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
          epubImportServiceProvider.overrideWithValue(fake),
          epubPreloadProvider.overrideWith((_) => preloadSvc),
          epubDocLoaderProvider.overrideWithValue((path) async {
            if (loaderThrows) {
              throw const EpubFormatException(
                'DRM 加密书籍不支持 · 请购买无 DRM 版本',
              );
            }
            return EpubDoc.parse(_miniEpubBytes());
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    brOpenFileSize = (path) async => 2048;
  }

  Future<void> deliver(WidgetTester t, String? value) async {
    channelReturn = value;
    unawaited(brOpenConsumeOnce(nav.currentContext!, capRef!));
    await t.pump();
    await t.pump(const Duration(milliseconds: 80));
  }

  group('⑥ 打开方式接收链', () {
    testWidgets('无待处理（null）：不打扰，仅通道被取一次', (t) async {
      await pumpApp(t);
      await deliver(t, null);
      expect(find.text('HOME'), findsOne);
      expect(find.byKey(const ValueKey('br-open-info')), findsNothing);
      await settle5(t);
    });

    testWidgets('非 EPUB（空串）：toast「只支持 EPUB」', (t) async {
      await pumpApp(t);
      await deliver(t, '');
      expect(await pollText(t, '只支持 EPUB'), isTrue);
      await clearToasts(t);
      await settle5(t);
    });

    testWidgets('解析失败（DRM）：toast 异常原因', (t) async {
      loaderThrows = true;
      await pumpApp(t);
      await deliver(t, '/cache/lh_open/打开测试书.epub');
      expect(
        await pollText(t, 'DRM 加密书籍不支持 · 请购买无 DRM 版本'),
        isTrue,
      );
      expect(find.byKey(const ValueKey('br-open-info')), findsNothing);
      await clearToasts(t);
      await settle5(t);
    });
  });

  group('⑥ 两态弹层（原型 sheetBrOpen 钉死）', () {
    testWidgets('未导入＝导入确认态：文案/信息卡/按钮齐 · 取消留在原页', (t) async {
      await pumpApp(t);
      await deliver(t, '/cache/lh_open/打开测试书.epub');
      expect(
        find.byKey(const ValueKey('br-open-sheet-导入这本书？')),
        findsOne,
      );
      expect(find.text('打开方式'), findsOne);
      expect(find.text('打开测试书（丁一）· 2 KB'), findsOne);
      expect(
        find.text('打开测试书.epub · 元数据从 EPUB 自动读取'),
        findsOne,
      );
      expect(find.text('加入书架 · 预载'), findsOne);
      expect(
        find.text('导入后可在核对页修改书名与作者 · 源文件保留原位'),
        findsOne,
      );
      await t.tap(find.byKey(const ValueKey('br-open-cancel')));
      await settle5(t);
      expect(find.text('HOME'), findsOne);
      expect(fake.committed, isFalse);
    });

    testWidgets('未导入 · 确认→commit→跳书架→定位高亮成功', (t) async {
      await pumpApp(t);
      await deliver(t, '/cache/lh_open/打开测试书.epub');
      await t.tap(find.byKey(const ValueKey('br-open-confirm')));
      expect(await pollText(t, '已在书架定位《打开测试书》', times: 40, ms: 60), isTrue);
      expect(fake.committed, isTrue);
      expect(fake.lastDraft?.title, '打开测试书');
      expect(preloadSvc.started, hasLength(1)); // 预载已挂起
      expect(find.text('书架'), findsOne); // 落在书架页
      await clearToasts(t);
      await t.pump(const Duration(seconds: 2)); // 1.6s 描边环自然结束
      await settle5(t);
    });

    testWidgets('已导入态：书名/状态+前往定位 → 书架命中闪烁', (t) async {
      final existing = await repo.addBook(
        Book(
          id: 'bk1',
          title: '打开测试书',
          author: '丁一',
          state: Book.kStateReading,
          pages: 200,
          readPages: 50,
          createdAt: 1,
          updatedAt: 1,
        ),
      );
      fake.dup = existing;
      await pumpApp(t);
      await deliver(t, '/cache/lh_open/打开测试书.epub');
      expect(
        find.byKey(const ValueKey('br-open-sheet-这本书已在书架')),
        findsOne,
      );
      final info = find.byKey(const ValueKey('br-open-info'));
      final texts = t
          .widgetList<Text>(find.descendant(of: info, matching: find.byType(Text)))
          .map((x) => x.data ?? '')
          .join('｜');
      expect(texts, contains('在读'));
      expect(texts, contains('来自文件：打开测试书.epub'));
      expect(find.text('前往书架定位'), findsOne);
      expect(find.text('同一本书不再重复入库 · 书摘与进度沿用书架记录'), findsOne);
      await t.tap(find.byKey(const ValueKey('br-open-confirm')));
      expect(await pollText(t, '已在书架定位《打开测试书》', times: 40, ms: 60), isTrue);
      expect(fake.committed, isFalse); // 已导入不再入库
      await clearToasts(t);
      await t.pump(const Duration(seconds: 2));
      await settle5(t);
    });

    testWidgets('导入成功但书架找不到（不在当前视图）：兜底 toast', (t) async {
      fake.commitResult = Book(
        id: 'gone',
        title: '打开测试书',
        author: '丁一',
        local: true,
        createdAt: 1,
        updatedAt: 1,
      );
      await pumpApp(t);
      await deliver(t, '/cache/lh_open/打开测试书.epub');
      await t.tap(find.byKey(const ValueKey('br-open-confirm')));
      expect(
        await pollText(t, '未在当前视图找到该书', times: 40, ms: 60),
        isTrue,
      );
      await clearToasts(t);
      await settle5(t);
    });
  });
}
