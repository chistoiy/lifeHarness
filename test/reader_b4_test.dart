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
import 'package:lifeharness/features/read/presentation/shelf/book_detail.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/read_settings_page.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_page.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_pager.dart';

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

  // 轮5.1：外观面板入口＝底栏第三个图标（主题/亮度/字号三面板已并入）。
  Future<void> openAp(WidgetTester t) async {
    await t.tap(find.byKey(const ValueKey('brBtnLook')));
    await step(t, times: 3);
  }

  /// 面板内滚到某个键（DraggableScrollableSheet 里的 ListView）。
  Future<void> apScrollTo(WidgetTester t, String key) => t.scrollUntilVisible(
    find.byKey(ValueKey(key)),
    150,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey('sheetBrAppearance')),
          matching: find.byType(Scrollable),
        )
        .last,
  );

  group('批4-A · 外观草稿制面板', () {
    testWidgets('外观钮开面板；滑字号→保存应用写逐书补丁并即时生效', (t) async {
      await openReader(t, 'b1');
      await openAp(t);
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
      await openAp(t);
      // R3-7：行距滑杆已收进三列分段（行距·紧）。
      await t.tap(find.byKey(const ValueKey('brApSeg-lh-s')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brApCancel')));
      await step(t, times: 2);
      expect(await repo.kv('reader.cfg.b2'), isNull);
    });

    testWidgets('字号+主题一起存：本书专属进补丁 · 全部书籍进全局', (t) async {
      await openReader(t, 'b3');
      await openAp(t);
      await t.drag(
        find.byKey(const ValueKey('brApFsSlider')),
        const Offset(60, 0),
      );
      await step(t);
      // R3-7：主题收进「纸色主题」二级页（同一弹层内部页面栈）。
      Future<void> pickTheme(String key) async {
        await t.tap(find.byKey(const ValueKey('brApSubBtn-theme')));
        await step(t);
        await t.tap(find.byKey(ValueKey(key)));
        await step(t);
        await t.tap(find.byKey(const ValueKey('brApSubDone')));
        await step(t);
      }

      await pickTheme('brApTheme-eye');
      await t.tap(find.byKey(const ValueKey('brApSave')));
      await step(t, times: 2);
      final patch = jsonDecode((await repo.kv('reader.cfg.b3'))!) as Map;
      expect((patch['fs'] as num) > 19, isTrue);
      expect(patch['theme'], 'eye');
      // 作用域切「全部书籍」（行尾「仅当前书籍」开关关掉）→ 夜间：写全局 reader.cfg。
      // （先等保存提示条退场，它盖在底栏上会吃掉 brBtnLook 的命中。）
      await step(t, ms: 1200, times: 4);
      await openAp(t);
      await t.tap(find.byKey(const ValueKey('brApScopeTgl')));
      await pickTheme('brApTheme-night');
      await t.tap(find.byKey(const ValueKey('brApSave')));
      await step(t, times: 2);
      final g = jsonDecode((await repo.kv('reader.cfg'))!) as Map;
      expect(g['theme'], 'night');
    });

    testWidgets('自动翻页：开关弹间隔滚轮→保存后按秒推进页码', (t) async {
      await openReader(t, 'b4');
      final before = pgLbl(t);
      await openAp(t);
      await apScrollTo(t, 'brApAuto');
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
      await openAp(t);
      await apScrollTo(t, 'brApBright');
      await step(t);
      expect(
        t.widget<SwitchListTile>(find.byKey(const ValueKey('brApBright'))).value,
        isTrue,
      );
    });
  });

  group('R3-7 · 单层主面板与二级页（微信读书式）', () {
    testWidgets('主面板布局：预览/字号行/三分段/六入口卡/开关行/亮度同屏在场', (t) async {
      await openReader(t, 'r1');
      await openAp(t);
      for (final k in [
        'brApPrev',
        'brApFs',
        'brApFsSlider',
        'brApScopeTgl',
        'brApSeg-mar',
        'brApSeg-lh',
        'brApSeg-ls',
        'brApSubBtn-font',
        'brApSubBtn-ind',
        'brApSubBtn-turn',
        'brApSubBtn-theme',
        'brApSubBtn-bg',
        'brApSubBtn-s2t',
      ]) {
        expect(find.byKey(ValueKey(k)), findsOne, reason: k);
      }
      // 旧滑杆/开关布局已收进分段与二级页。
      for (final k in ['brApLhSlider', 'brApLsSlider', 'brApMarSlider', 'brApIndent']) {
        expect(find.byKey(ValueKey(k)), findsNothing, reason: k);
      }
      // 默认值就近命中档位：mar=22→中（选中 pill 描边 1.6）。
      expect(
        (t
                .widget<Container>(
                  find.descendant(
                    of: find.byKey(const ValueKey('brApSeg-mar-m')),
                    matching: find.byType(Container),
                  ),
                )
                .decoration!
                as BoxDecoration)
            .border!
            .top
            .width,
        1.6,
      );
      // 批三刀4 在「两端对齐」下加了「跟随原书样式」开关行（＋不支持项提示行），
      // 面板变长：开关行四件仍在原位，亮度滑杆落到懒建 ListView 的视口外，
      // 要滚到才在场——不是布局丢了，是主面板本就滚动（原型 sheetBrAppearance 同）。
      for (final k in ['brApJust', 'brApOrig', 'brApBright', 'brApAuto']) {
        expect(find.byKey(ValueKey(k)), findsOne, reason: k);
      }
      await apScrollTo(t, 'brApLumSlider');
      for (final k in ['brApLumSlider', 'brApSave']) {
        expect(find.byKey(ValueKey(k)), findsOne, reason: k);
      }
    });

    testWidgets('字体二级页：分类 chips 过滤→选衬线组字卡→回主页回显→保存落 font', (t) async {
      await openReader(t, 'r2');
      await openAp(t);
      await t.tap(find.byKey(const ValueKey('brApSubBtn-font')));
      await step(t);
      expect(find.byKey(const ValueKey('brApFontCats')), findsOne);
      expect(find.text('字体样式'), findsOne);
      // 全部分类下 4 张字卡在场；点「衬线」只剩宋体一张。
      expect(find.byKey(const ValueKey('brApFont-serif')), findsOne);
      expect(find.byKey(const ValueKey('brApFont-hei')), findsOne);
      await t.tap(find.byKey(const ValueKey('brApFontCat-衬线')));
      await step(t);
      expect(find.byKey(const ValueKey('brApFont-serif')), findsOne);
      expect(find.byKey(const ValueKey('brApFont-hei')), findsNothing);
      await t.tap(find.byKey(const ValueKey('brApFont-serif')));
      await step(t);
      // 子页副标题即时同步。
      expect(
        t.widget<Text>(find.byKey(const ValueKey('brApSubSub'))).data,
        '当前选择 · 宋体',
      );
      await t.tap(find.byKey(const ValueKey('brApSub-back')));
      await step(t);
      // 主页入口卡回显。
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('brApSubBtn-font')),
          matching: find.byKey(const ValueKey('brApFontLbl')),
        ),
        findsOne,
      );
      expect(
        t.widget<Text>(find.byKey(const ValueKey('brApFontLbl'))).data,
        '宋体',
      );
      await t.tap(find.byKey(const ValueKey('brApSave')));
      await step(t, times: 2);
      final patch = jsonDecode((await repo.kv('reader.cfg.r2'))!) as Map;
      expect(patch['font'], 'serif');
    });

    testWidgets('首行缩进二级页：无缩进→保存 patch 同写 indent=false 与 indMode=none', (t) async {
      await openReader(t, 'r3');
      await openAp(t);
      await t.tap(find.byKey(const ValueKey('brApSubBtn-ind')));
      await step(t);
      for (final k in ['brApIndent-auto', 'brApIndent-2', 'brApIndent-none']) {
        expect(find.byKey(ValueKey(k)), findsOne, reason: k);
      }
      await t.tap(find.byKey(const ValueKey('brApIndent-none')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brApSubDone')));
      await step(t);
      expect(
        t.widget<Text>(find.byKey(const ValueKey('brApIndLbl'))).data,
        '无缩进',
      );
      await t.tap(find.byKey(const ValueKey('brApSave')));
      await step(t, times: 2);
      final patch = jsonDecode((await repo.kv('reader.cfg.r3'))!) as Map;
      expect(patch['indent'], false);
      expect(patch['indMode'], 'none');
    });

    testWidgets('简繁二级页：选繁体→保存落 s2t=t · 翻页/字距分段落原数值字段', (t) async {
      await openReader(t, 'r4');
      await openAp(t);
      await t.tap(find.byKey(const ValueKey('brApSubBtn-s2t')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brApS2T-t')));
      await step(t);
      expect(
        t.widget<Text>(find.byKey(const ValueKey('brApSubSub'))).data,
        '当前选择 · 繁体',
      );
      await t.tap(find.byKey(const ValueKey('brApSubDone')));
      await step(t);
      // 分段仍写原数值字段：字距·疏＝1，翻页方式二级页 scroll。
      await t.tap(find.byKey(const ValueKey('brApSeg-ls-l')));
      await t.tap(find.byKey(const ValueKey('brApSubBtn-turn')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brApTurn-scroll')));
      await step(t);
      expect(
        t.widget<Text>(find.byKey(const ValueKey('brApSubSub'))).data,
        '当前选择 · 滚动',
      );
      await t.tap(find.byKey(const ValueKey('brApSubDone')));
      await step(t);
      expect(
        t.widget<Text>(find.byKey(const ValueKey('brApTurnLbl'))).data,
        '滚动',
      );
      await t.tap(find.byKey(const ValueKey('brApSave')));
      await step(t, times: 2);
      final patch = jsonDecode((await repo.kv('reader.cfg.r4'))!) as Map;
      expect(patch['s2t'], 't');
      expect(patch['ls'], 1);
      expect(patch['mode'], 'scroll');
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
          BookPagination.fromTable([7], <List<List<int>>?>[
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

  group('真机修 · 划词工具条收起（2026-09-28 反馈③ · V1.53 轮3 长按化）', () {
    testWidgets('长按段落弹工具条；点按同段收起', (t) async {
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
      await t.longPress(para);
      await step(t);
      expect(find.byKey(const ValueKey('brSelBar')), findsOne);
      // 点按（含段落上）冒泡到 body 分派：有选区先清选区，工具条收起。
      await t.tap(para);
      await step(t);
      expect(find.byKey(const ValueKey('brSelBar')), findsNothing);
      // 点按不再划词：无选区时同一点按改为收放 chrome。
      await t.tap(para);
      await step(t);
      expect(find.byKey(const ValueKey('brSelBar')), findsNothing);
    });
  });

  group('轮5.3 · 详情页本地文件紧凑条', () {
    Future<void> openDetail(WidgetTester t, String id) async {
      await useSurface(t);
      await t.pumpWidget(
        ProviderScope(
          overrides: baseOverrides(docs: tmp.path),
          child: MaterialApp(home: BookDetailPage(bookId: id)),
        ),
      );
      await step(t, times: 4);
    }

    testWidgets('整卡→两行紧凑条（?/打开/检索/删除）· ? 弹说明', (t) async {
      await addBook('e1');
      await openDetail(t, 'e1');
      // 旧底部整卡已删，紧凑条接管四个入口。
      expect(find.byKey(const ValueKey('br-dcard')), findsNothing);
      expect(find.byKey(const ValueKey('brDstrip')), findsOne);
      for (final k in ['brDinfo', 'br-d-open', 'br-d-search', 'br-d-del']) {
        expect(find.byKey(ValueKey(k)), findsOne, reason: k);
      }
      final txt = find
          .descendant(
            of: find.byKey(const ValueKey('brDstrip')),
            matching: find.byType(Text),
          )
          .evaluate()
          .map((e) => (e.widget as Text).data ?? '')
          .join(' ');
      expect(txt, contains('EPUB'));
      expect(txt, contains('无 DRM'));
      expect(txt, contains('进度'));
      expect(txt, contains('划线'));
      await t.tap(find.byKey(const ValueKey('brDinfo')));
      await step(t, times: 3);
      expect(find.byKey(const ValueKey('sheetBrLocalInfo')), findsOne);
      for (final k in [
        'brLiFmt',
        'brLiPath',
        'brLiMeta',
        'brLiPos',
        'brLiClean',
      ]) {
        expect(find.byKey(ValueKey(k)), findsOne, reason: k);
      }
      await t.tap(find.byKey(const ValueKey('brLiOk')));
      await step(t, times: 3);
      expect(find.byKey(const ValueKey('sheetBrLocalInfo')), findsNothing);
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
