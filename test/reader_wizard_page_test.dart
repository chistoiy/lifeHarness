import 'dart:convert';
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
import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/data/epub_import.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/presentation/local_import_page.dart';
import 'package:lifeharness/features/read/presentation/reader_page.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/shelf_page.dart';
import 'package:lifeharness/features/read/presentation/widgets/bs_cover.dart';

// V1.50 批1 · 阅读器 UI 流（导入向导四步 / DRM 拒绝 / 本地角标 / 点封面分流 /
// 阅读主屏自动计时）。独立文件；文件 IO 全部走 fake service/loader，
// 禁在 FakeAsync 下触真磁盘（既有踩坑记录）。

Uint8List _miniEpubBytes({String title = '导入测试书'}) {
  ArchiveFile f(String n, List<int> b) => ArchiveFile(n, b.length, b);
  List<int> x(String s) => utf8.encode(s);
  final arch = Archive();
  for (final e in <(String, List<int>)>[
    ('mimetype', x('application/epub+zip')),
    (
      'META-INF/container.xml',
      x('<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
              '<rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>'),
    ),
    (
      'OEBPS/content.opf',
      x('''<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>$title</dc:title><dc:creator>丙一</dc:creator></metadata>
<manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/></manifest>
<spine><itemref idref="c1"/></spine></package>'''),
    ),
    (
      'OEBPS/nav.xhtml',
      x('<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>'
              '<nav epub:type="toc"><ol><li><a href="c1.xhtml">唯一的章</a></li></ol></nav></body></html>'),
    ),
    (
      'OEBPS/c1.xhtml',
      x('<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><body>'
              '<p>第一段内容，用于导入链路。</p><p>第二段内容。</p></body></html>'),
    ),
  ]) {
    arch.addFile(f(e.$1, e.$2));
  }
  return Uint8List.fromList(ZipEncoder().encode(arch)!);
}

/// 内存版导入服务：pick/loadDoc/findDup/commit 全 fake，落库断言交数据测。
class _FakeImport extends EpubImportService {
  _FakeImport(
    ReadRepository repo, {
    EpubPick? pickResult,
    this.dup,
    this.drm = false,
  }) : _pickResult = pickResult ??
            const EpubPick(name: '导入测试书.epub', size: 2048, path: 'mem'),
       super(repo);

  final EpubPick _pickResult;
  EpubDoc? doc;
  Book? dup;
  bool drm;

  EpubMetaDraft? lastDraft;
  bool? lastTagLocal;
  Book? mergedInto;

  @override
  Future<EpubPick?> pick() async => _pickResult;

  @override
  Future<EpubDoc> loadDoc(EpubPick p) async {
    if (drm) {
      throw const EpubFormatException('DRM 加密书籍不支持 · 请购买无 DRM 版本');
    }
    return doc ?? EpubDoc.parse(_miniEpubBytes());
  }

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
    lastDraft = draft;
    lastTagLocal = tagLocal;
    mergedInto = mergeInto;
    return Book(
      id: 'fake1',
      title: draft.title,
      local: true,
      createdAt: 1,
      updatedAt: 1,
    );
  }
}

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ReadRepository repo;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = ReadRepository(db);
  });
  tearDown(() => db.close());

  Widget wrap(Widget home, {List<Override> extra = const []}) =>
      ProviderScope(
        overrides: [
          readRepositoryProvider.overrideWithValue(repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...extra,
        ],
        child: MaterialApp(home: home),
      );

  Future<void> step(WidgetTester t, {int ms = 200, int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await t.pump(Duration(milliseconds: ms));
    }
  }

  group('批1-W · 导入向导', () {
    testWidgets('四步全链：授权→选文件→解析五任务→核对→落库 pop', (t) async {
      await useSurface(t);
      final fake = _FakeImport(repo);
      await t.pumpWidget(wrap(const LocalImportPage(), extra: [
        epubImportServiceProvider.overrideWithValue(fake),
      ]));
      // 步1 授权
      expect(find.text('Android 13+ · 无需「所有文件访问」'), findsOne);
      await t.tap(find.byKey(const ValueKey('br-imp1-go')));
      await step(t);
      // 步2 选文件
      expect(find.byKey(const ValueKey('br-imp2-pick')), findsOne);
      await t.tap(find.byKey(const ValueKey('br-imp2-pick')));
      await step(t, times: 3);
      // 解析即完成时步3一闪而过：允许已直达步4。
      if (find.byKey(const ValueKey('br-imp4')).evaluate().isEmpty) {
        expect(find.byKey(const ValueKey('br-imp3')), findsOne);
        await step(t, ms: 300, times: 3);
      }
      // 步4 核对：元数据预填 + 解析摘要 + 保存
      expect(find.byKey(const ValueKey('br-imp4')), findsOne);
      expect(find.text('导入测试书'), findsWidgets);
      expect(find.byKey(const ValueKey('br-dup')), findsNothing);
      final sum = t
          .widget<Text>(find.byKey(const ValueKey('brMetaSum')))
          .data;
      expect(sum, contains('共 1 章'));
      expect(find.text('加入书架 · 开始阅读'), findsOne);
      await t.tap(find.byKey(const ValueKey('brSaveBtn')));
      await step(t);
      expect(fake.lastTagLocal, isTrue);
      expect(fake.lastDraft?.title, '导入测试书');
      expect(fake.mergedInto, isNull);
    });

    testWidgets('DRM 解析失败：错误卡 + 返回重选', (t) async {
      await useSurface(t);
      final fake = _FakeImport(repo, drm: true);
      await t.pumpWidget(wrap(const LocalImportPage(), extra: [
        epubImportServiceProvider.overrideWithValue(fake),
      ]));
      await t.tap(find.byKey(const ValueKey('br-imp1-go')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('br-imp2-pick')));
      await step(t, ms: 200, times: 8);
      expect(find.byKey(const ValueKey('br-imp-err')), findsOne);
      expect(find.textContaining('DRM 加密书籍不支持'), findsWidgets);
      await t.tap(find.byKey(const ValueKey('br-imp-retry')));
      await step(t);
      expect(find.byKey(const ValueKey('br-imp2')), findsOne);
    });

    testWidgets('同书命中：amber 合并提示 + 按钮改文案', (t) async {
      await useSurface(t);
      final existing = await repo.addBook(Book(
        id: 'dup1',
        title: '导入测试书',
        author: '丙一',
        createdAt: 1,
        updatedAt: 1,
      ));
      final fake = _FakeImport(repo, dup: existing);
      await t.pumpWidget(wrap(const LocalImportPage(), extra: [
        epubImportServiceProvider.overrideWithValue(fake),
      ]));
      await t.tap(find.byKey(const ValueKey('br-imp1-go')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('br-imp2-pick')));
      await step(t, ms: 200, times: 8);
      expect(find.byKey(const ValueKey('br-dup')), findsOne);
      expect(find.text('合并到已有记录 · 附本地文件'), findsOne);
      await t.tap(find.byKey(const ValueKey('brSaveBtn')));
      await step(t);
      expect(fake.mergedInto?.id, 'dup1');
    });
  });

  group('批1-W · 角标与分流', () {
    Book bk(String id, {bool local = false}) => Book(
          id: id,
          title: '书$id',
          createdAt: 1,
          updatedAt: 1,
          local: local,
        );

    testWidgets('BsCover：本地书右下「本地」角标，非本地不渲染', (t) async {
      await t.pumpWidget(wrap(Center(child: BsCover(book: bk('l1', local: true)))));
      expect(find.byKey(const ValueKey('br-local-badge')), findsOne);
      await t.pumpWidget(wrap(Center(child: BsCover(book: bk('n1')))));
      expect(find.byKey(const ValueKey('br-local-badge')), findsNothing);
    });

    testWidgets('书架点本地书封面→阅读器路由；非本地→详情', (t) async {
      await repo.addBook(bk('l1', local: true));
      await repo.addBook(bk('n1'));
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const ShelfPage()),
        GoRoute(
          path: '/read/book/:id',
          builder: (_, s) => Text('detail-${s.pathParameters['id']}'),
        ),
        GoRoute(
          path: '/read/reader/:id',
          builder: (_, s) => Text('reader-${s.pathParameters['id']}'),
        ),
      ]);
      await useSurface(t);
      await t.pumpWidget(ProviderScope(overrides: [
        readRepositoryProvider.overrideWithValue(repo),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ], child: MaterialApp.router(routerConfig: router)));
      await step(t, times: 5);
      // 书架默认「在读」分区，先切「全部」再断言条目。
      await t.tap(find.byKey(const ValueKey('sh-chip-全部')));
      await step(t, times: 2);
      await t.tap(find.byKey(const ValueKey('sh-item-l1')));
      await step(t, times: 4);
      expect(find.text('reader-l1'), findsOne);
      // 返回再点非本地书（等 pop 动画走完）
      router.pop();
      await step(t, ms: 300, times: 4);
      await t.tap(find.byKey(const ValueKey('sh-item-n1')));
      await step(t, times: 4);
      expect(find.text('detail-n1'), findsOne);
    });
  });

  group('批1-W · 阅读主屏（批2 形态：默认翻页模式）', () {
    testWidgets('进入自动起计时 · 退出结算结束会话', (t) async {
      await useSurface(t);
      final book = await repo.addBook(Book(
        id: 'r1',
        title: '阅读器书',
        local: true,
        epub: const EpubRef(fmt: 'EPUB3', size: 10, path: 'mem'),
        createdAt: 1,
        updatedAt: 1,
      ));
      final doc = EpubDoc.parse(_miniEpubBytes(title: '阅读器书'));
      await t.pumpWidget(wrap(
        ReaderPage(bookId: book.id),
        extra: [
          epubDocLoaderProvider.overrideWithValue((_) async => doc),
        ],
      ));
      await step(t, times: 4);
      // 正文出现（分页引擎实测渲染 · Text.rich 需 findRichText）。
      expect(find.textContaining('第一段内容', findRichText: true), findsOne);
      // 自动计时：running 会话存在
      expect(await repo.runningSession(), isNotNull);
      // 中央热区切换 chrome + 计时 chip 走秒（点正文列外空白，
      // 热区已置于 stage 之下，文字段落区域由正文优先命中）。
      await t.tapAt(const Offset(400, 500));
      await step(t);
      expect(find.byKey(const ValueKey('br-top')), findsOne);
      expect(find.byKey(const ValueKey('br-sess-chip')), findsOne);
      await step(t, ms: 1100, times: 2);
      expect(find.byKey(const ValueKey('br-sess-chip')), findsOne);
      await t.tap(find.byKey(const ValueKey('br-back')));
      await step(t, times: 3);
      expect(await repo.runningSession(), isNull);
      final agg = (await repo.sessionsOf('r1'));
      expect(agg, hasLength(1));
    });
  });
}
