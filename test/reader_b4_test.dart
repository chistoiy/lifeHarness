import 'dart:convert' show base64Decode, jsonDecode;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/read/data/epub_cache.dart';
import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/presentation/book_detail.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/read_settings_page.dart';
import 'package:lifeharness/features/read/presentation/reader_page.dart';
import 'package:lifeharness/features/read/presentation/reader_pager.dart';

// V1.50 批4 · 外观草稿制面板/逐书记忆/自动翻页/常亮/删除两口径/设置组。
// 独立文件防 isolate 污染；文件 IO 断言包 runAsync；周期 Timer 页禁 pumpAndSettle。

final _png = Uint8List.fromList(base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
));

EpubPara _p(String t) => EpubPara(kind: EpubParaKind.text, text: t);

const _lorem = '这是分页实测正文素材，默认字号下约两到三行。';

EpubDoc _docOf(List<EpubChapter> chs) => EpubDoc(
  format: 'EPUB3',
  title: '批4书',
  author: '甲',
  toc: const [],
  chapters: chs,
  imageCount: 1,
  totalChars: chs.fold(0, (s, c) => s + c.charCount),
  images: {'img/px.png': _png},
);

// 与 reader_ui_test 同构素材：(210,645) 为中区空白文字位（chrome 唤起点）。
EpubDoc _bigDoc() => _docOf([
  EpubChapter(
    href: 'c1',
    title: '第一章',
    paras: [
      const EpubPara(kind: EpubParaKind.heading, text: '第一章', headingLevel: 1),
      _p('第一段。$_lorem'),
      const EpubPara(
        kind: EpubParaKind.image,
        imgSrc: 'img/px.png',
        alt: '测试插图',
      ),
      ...List.generate(27, (i) => _p('一之$i。$_lorem')),
    ],
  ),
  EpubChapter(
    href: 'c2',
    title: '第二章',
    paras: [
      const EpubPara(kind: EpubParaKind.heading, text: '第二章', headingLevel: 1),
      ...List.generate(24, (i) => _p('二之$i。$_lorem')),
    ],
  ),
]);

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
    tmp = Directory.systemTemp.createTempSync('lh_b4');
  });
  tearDown(() async {
    await db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  // 注意：阅读器线 override **不带 docsPath**——FakeAsync 下 loadPag 真文件 IO
  // 永不返回（既有踩坑）；删除线的 removePag 走 runAsync 才允许真 IO。
  List<Override> baseOverrides({String? docs}) => [
    readRepositoryProvider.overrideWithValue(repo),
    sharedPreferencesProvider.overrideWithValue(prefs),
    epubDocLoaderProvider.overrideWithValue((_) async => _bigDoc()),
    epubPreloadProvider.overrideWith(
      (_) => EpubPreloadService(repo, docsPath: docs),
    ),
  ];

  Future<void> step(WidgetTester t, {int ms = 200, int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await t.pump(Duration(milliseconds: ms));
    }
  }

  Future<Book> addBook(String id, {String? srcPath}) => repo.addBook(
    Book(
      id: id,
      title: '批4书$id',
      local: true,
      epub: EpubRef(
        fmt: 'EPUB3',
        size: 10,
        path: '${tmp.path}/copy_$id.epub',
        srcPath: srcPath ?? '${tmp.path}/src_$id.epub',
        srcName: 'src_$id.epub',
      ),
      createdAt: 1,
      updatedAt: 1,
    ),
  );

  Future<void> openReader(WidgetTester t, String id) async {
    await useSurface(t, const Size(420, 780));
    await addBook(id);
    await t.pumpWidget(
      ProviderScope(
        overrides: baseOverrides(),
        child: MaterialApp(home: ReaderPage(bookId: id)),
      ),
    );
    await step(t, times: 4);
    await t.tapAt(const Offset(210, 645)); // 中区唤起 chrome
    await step(t);
    expect(find.byKey(const ValueKey('br-bottom')), findsOne);
  }

  String pgLbl(WidgetTester t) =>
      t.widget<Text>(find.byKey(const ValueKey('brPgLbl'))).data ?? '';

  group('批4-A · 外观草稿制面板', () {
    testWidgets('外观钮开面板；滑字号→保存应用写逐书补丁并即时生效', (t) async {
      await openReader(t, 'b1');
      await t.tap(find.byKey(const ValueKey('brBtnAp')));
      await step(t, times: 2);
      expect(find.byKey(const ValueKey('sheetBrAppearance')), findsOne);
      expect(find.byKey(const ValueKey('brApPrev')), findsOne);
      // 字号滑到最大：点轨道右端（divisions 16 → 29/30 均达标）。
      final sliderRect = t.getRect(find.byKey(const ValueKey('brApFsSlider')));
      await t.tapAt(Offset(sliderRect.right - 6, sliderRect.center.dy));
      await step(t);
      expect(
        t.widget<Text>(find.byKey(const ValueKey('brApFsV'))).data,
        anyOf('29', '30'),
      );
      await t.tap(find.byKey(const ValueKey('brApSave')));
      await step(t, times: 2);
      final patch = jsonDecode((await repo.kv('reader.cfg.b1'))!);
      expect((patch as Map)['fs'], greaterThan(24));
      expect(await pollText(t, '本书外观已保存 · 逐书独立记忆'), isTrue);
      // 阅读器页有周期 Timer，禁 clearToasts/pumpAndSettle（会永动挂死）。
    });

    testWidgets('取消＝丢弃草稿，不落逐书键', (t) async {
      await openReader(t, 'b2');
      await t.tap(find.byKey(const ValueKey('brBtnAp')));
      await step(t, times: 2);
      final rect = t.getRect(find.byKey(const ValueKey('brApLhSlider')));
      await t.tapAt(Offset(rect.left + 6, rect.center.dy));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brApCancel')));
      await step(t, times: 2);
      expect(await repo.kv('reader.cfg.b2'), isNull);
    });

    testWidgets('A± 写逐书补丁；主题循环写全局（原型 brFsNudge/brThemeCycle）', (t) async {
      await openReader(t, 'b3');
      await t.tap(find.byKey(const ValueKey('brBtnA+')));
      await step(t, times: 2);
      final patch =
          jsonDecode((await repo.kv('reader.cfg.b3'))!) as Map;
      expect(patch['fs'], 20);
      await t.tap(find.byKey(const ValueKey('brBtnTheme')));
      await step(t, times: 2);
      final g = jsonDecode((await repo.kv('reader.cfg'))!) as Map;
      expect(g['theme'], 'eye');
    });

    testWidgets('自动翻页：开关弹间隔滚轮→保存后按秒推进页码', (t) async {
      await openReader(t, 'b4');
      final before = pgLbl(t);
      await t.tap(find.byKey(const ValueKey('brBtnAp')));
      await step(t, times: 2);
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('brApAuto')),
        150,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('sheetBrAppearance')),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      await step(t);
      await t.tap(find.byKey(const ValueKey('brApAuto')));
      await step(t, times: 2);
      expect(find.byKey(const ValueKey('sheetBrAutoPage')), findsOne);
      expect(find.byKey(const ValueKey('wBrAuto')), findsOne);
      await t.tap(find.byKey(const ValueKey('brAutoOk'))); // 默认 10 秒
      await step(t);
      await t.tap(find.byKey(const ValueKey('brApSave')));
      await step(t, times: 2);
      // 周期 10s：推进 10.2s 应翻一页（FakeAsync 小步 pump，不 settle）。
      await t.pump(const Duration(seconds: 10, milliseconds: 200));
      expect(pgLbl(t), isNot(before));
      expect(pgLbl(t), contains('/'));
    });

    testWidgets('设置组 read.brBright=true → 面板常亮开关预开', (t) async {
      await repo.setKv('read.brBright', 'true');
      await openReader(t, 'b5');
      await t.tap(find.byKey(const ValueKey('brBtnAp')));
      await step(t, times: 2);
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('brApBright')),
        150,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('sheetBrAppearance')),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      await step(t);
      expect(
        t.widget<SwitchListTile>(find.byKey(const ValueKey('brApBright'))).value,
        isTrue,
      );
    });
  });

  group('批4-D · 删除本地书两口径', () {
    Future<void> openDetail(WidgetTester t, String id) async {
      await useSurface(t);
      await t.pumpWidget(
        ProviderScope(
          // 详情页不触 loadPag，此线允许注入 docsPath（removePag 走 runAsync）。
          overrides: baseOverrides(docs: tmp.path),
          child: MaterialApp(home: BookDetailPage(bookId: id)),
        ),
      );
      await step(t, times: 4);
    }

    testWidgets('仅清除阅读数据：逐书键与分页表回收·副本与书摘计时保留', (t) async {
      final b = await addBook('d1');
      File(b.epub!.path).writeAsBytesSync([1, 2, 3]);
      await repo.setKv('reader.pos.d1', '{"ci":1,"pg":2}');
      await repo.setKv('reader.cfg.d1', '{"fs":22}');
      // FakeAsync 下真文件写会永挂（既有踩坑）：分页表预置走 runAsync。
      await t.runAsync(
        () => PagStore.save(
          tmp.path,
          'd1',
          PagStore.fingerprint(const ReaderLayout(width: 420, height: 780)),
          BookPagination.fromTable([
            [
              [0],
            ],
          ]),
        ),
      );
      await openDetail(t, 'd1');
      expect(find.byKey(const ValueKey('br-d-del')), findsOne);
      await t.runAsync(() async {
        await t.tap(find.byKey(const ValueKey('br-d-del')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await step(t, times: 2);
      expect(find.byKey(const ValueKey('brDelOpt-cache')), findsOne);
      expect(find.byKey(const ValueKey('brDelOpt-src')), findsOne);
      await t.runAsync(() async {
        await t.tap(find.byKey(const ValueKey('brDelOk')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await step(t, times: 3);
      final after = (await repo.bookById('d1'))!;
      expect(after.local, isFalse);
      expect(after.epub, isNull);
      expect(after.title, '批4书d1', reason: '书籍行与记录保留');
      expect(await repo.kv('reader.pos.d1'), isNull);
      expect(await repo.kv('reader.cfg.d1'), isNull);
      expect(File(b.epub!.path).existsSync(), isTrue, reason: 'cache 口径不删副本');
    });

    testWidgets('连源文件删除：私有副本与源文件本体回收', (t) async {
      final b = await addBook('d2');
      File(b.epub!.path).writeAsBytesSync([1, 2, 3]);
      File(b.epub!.srcPath!).writeAsBytesSync([4, 5, 6]);
      await openDetail(t, 'd2');
      await t.runAsync(() async {
        await t.tap(find.byKey(const ValueKey('br-d-del')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await step(t, times: 2);
      await t.tap(find.byKey(const ValueKey('brDelOpt-src')));
      await step(t);
      await t.runAsync(() async {
        await t.tap(find.byKey(const ValueKey('brDelOk')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await step(t, times: 3);
      expect(File(b.epub!.path).existsSync(), isFalse);
      expect(File(b.epub!.srcPath!).existsSync(), isFalse);
      expect((await repo.bookById('d2'))!.epub, isNull);
    });
  });

  group('真机修 · 划词工具条收起（2026-09-28 反馈③）', () {
    testWidgets('点段落弹工具条；再点同段收起', (t) async {
      await useSurface(t, const Size(420, 780));
      await addBook('b6');
      await t.pumpWidget(
        ProviderScope(
          overrides: baseOverrides(),
          child: MaterialApp(home: ReaderPage(bookId: 'b6')),
        ),
      );
      await step(t, times: 4);
      final para = find.byKey(const ValueKey('brpTap-0-1'));
      await t.tap(para);
      await step(t);
      expect(find.byKey(const ValueKey('brSelBar')), findsOne);
      await t.tap(para);
      await step(t);
      expect(find.byKey(const ValueKey('brSelBar')), findsNothing);
    });
  });

  group('批4-S · 阅读设置本地阅读器组', () {
    testWidgets('分组渲染四行；brLink chip 与 brBright 开关落键', (t) async {
      await useSurface(t);
      await t.pumpWidget(
        ProviderScope(
          overrides: baseOverrides(),
          child: MaterialApp(home: const ReadSettingsPage()),
        ),
      );
      await step(t, times: 3);
      // 定位到最后一组（本地阅读器）＝第 6 个分组 tab。
      await t.tap(find.byKey(const ValueKey('set-tab-5')));
      await step(t, times: 2);
      expect(find.byKey(const ValueKey('set-card-本地阅读器')), findsOne);
      expect(find.text('导入本地 EPUB'), findsOne);
      expect(find.byKey(const ValueKey('set-brSync-t')), findsOne);
      expect(find.byKey(const ValueKey('set-brBright-t')), findsOne);
      // brBright 默认关（原型 BR_DEF.bright=false）。
      expect(
        t.widget<Switch>(find.byKey(const ValueKey('set-brBright-t'))).value,
        isFalse,
      );
      await t.tap(find.byKey(const ValueKey('set-brLink-禁止')));
      await step(t, times: 2);
      expect(await repo.kv('read.brLink'), '禁止');
      await t.tap(find.byKey(const ValueKey('set-brBright-t')));
      await step(t, times: 2);
      expect(await repo.kv('read.brBright'), 'true');
    });
  });
}
