import 'dart:convert' show base64Decode;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/reader_page.dart';

import 'helpers.dart';

// V1.50 批2 · 阅读主屏与目录抽屉（分页双模式/进度条/命中导航/位置记忆/
// 插图弹层/尾页标已读）。独立文件；EpubDoc 直构免 zip，IO 全走 loader override。

final _png = Uint8List.fromList(base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
));

EpubPara _p(String t) => EpubPara(kind: EpubParaKind.text, text: t);

const _lorem = '这是分页实测正文素材，默认字号下约两到三行。';

EpubDoc _docOf(List<EpubChapter> chs) => EpubDoc(
  format: 'EPUB3',
  title: '主屏书',
  author: '甲',
  toc: const [],
  chapters: chs,
  imageCount: 1,
  totalChars: chs.fold(0, (s, c) => s + c.charCount),
  images: {'img/px.png': _png},
);

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

  Future<Book> addBook(String id) => repo.addBook(Book(
    id: id,
    title: '主屏书',
    local: true,
    epub: const EpubRef(fmt: 'EPUB3', size: 10, path: 'mem'),
    createdAt: 1,
    updatedAt: 1,
  ));

  Widget wrap(Widget home, EpubDoc doc) => ProviderScope(
    overrides: [
      readRepositoryProvider.overrideWithValue(repo),
      sharedPreferencesProvider.overrideWithValue(prefs),
      epubDocLoaderProvider.overrideWithValue((_) async => doc),
    ],
    child: MaterialApp(home: home),
  );

  Future<void> step(WidgetTester t, {int ms = 200, int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await t.pump(Duration(milliseconds: ms));
    }
  }

  // 视口 420×780：热区 y∈[117,663]；(210,645) 为中区空白文字位，
  // (412,645)/(8,645) 为右/左翻页条（避开 22..398 的正文/插图宽度）。
  Future<void> centerTap(WidgetTester t) => t.tapAt(const Offset(210, 645));
  Future<void> flipR(WidgetTester t) => t.tapAt(const Offset(412, 350));
  Future<void> flipL(WidgetTester t) => t.tapAt(const Offset(8, 350));

  Future<void> openReader(WidgetTester t, EpubDoc doc, String id) async {
    await useSurface(t, const Size(420, 780));
    await addBook(id);
    await t.pumpWidget(wrap(ReaderPage(bookId: id), doc));
    await step(t, times: 4);
    // 默认收起 chrome：点中区空白常驻顶/底栏（后续断言共用）。
    await centerTap(t);
    await step(t);
    expect(find.byKey(const ValueKey('br-bottom')), findsOne);
  }

  /// 底栏页码标签 → (章内页, 章页数, 全局页, 总页数)。
  (int, int, int, int) pgLbl(WidgetTester t) {
    final s = t
        .widget<Text>(find.byKey(const ValueKey('brPgLbl')))
        .data!;
    final m = RegExp(r'(\d+)/(\d+) 页 · 第 (\d+)/(\d+) 页').firstMatch(s)!;
    return (
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
    );
  }

  Future<void> showChrome(WidgetTester t) async {
    if (find.byKey(const ValueKey('br-bottom')).evaluate().isEmpty) {
      await centerTap(t);
      await step(t);
    }
  }

  group('批2-U · 翻页与外观即时重排', () {
    testWidgets('右/左热区翻页 · 页码标签同步', (t) async {
      await openReader(t, _bigDoc(), 'u1');
      expect(pgLbl(t).$1, 1); // 章内第 1 页
      expect(pgLbl(t).$3, 1); // 全局第 1 页
      // 翻页动画 220ms 后需空帧收尾，600ms 双泵保证下一次轻点可达。
      for (var i = 0; i < 2; i++) {
        await flipR(t);
        await step(t, ms: 300, times: 2);
      }
      expect(pgLbl(t).$3, 3);
      expect(pgLbl(t).$1, 3);
      await flipL(t);
      await step(t, ms: 300, times: 2);
      expect(pgLbl(t).$3, 2);
      expect(pgLbl(t).$1, 2); // 仍在第一章
    });

    testWidgets('字号滑条重排：总页数随字号变化（实算非估算 · V1.53 面板）', (t) async {
      await openReader(t, _bigDoc(), 'u2');
      await showChrome(t);
      await t.tap(find.byKey(const ValueKey('brBtnFont')));
      await step(t);
      final before = pgLbl(t).$4;
      // 点轨道右端＝字号拉满（页数增）；点左端＝缩回（页数减）。
      final sr = t.getRect(find.byKey(const ValueKey('brFsSl')));
      await t.tapAt(Offset(sr.right - 4, sr.center.dy));
      await step(t, ms: 300, times: 2);
      final after = pgLbl(t).$4;
      expect(after, greaterThan(before));
      await t.tapAt(Offset(sr.left + 4, sr.center.dy));
      await step(t, ms: 300, times: 2);
      expect(pgLbl(t).$4, lessThan(after));
    });

    testWidgets('翻页⇄滚动双模式切换（字号面板 chip）', (t) async {
      await openReader(t, _bigDoc(), 'u3');
      await showChrome(t);
      expect(find.byKey(const ValueKey('br-scroll')), findsNothing);
      await t.tap(find.byKey(const ValueKey('brBtnFont')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brPfMode')));
      await step(t, ms: 300);
      expect(find.byKey(const ValueKey('br-scroll')), findsOne);
      await t.tap(find.byKey(const ValueKey('brPfMode')));
      await step(t, ms: 300);
      expect(find.byKey(const ValueKey('br-pageflip')), findsOne);
    });

    testWidgets('尾页右翻标记已读 + toast', (t) async {
      final small = _docOf([
        EpubChapter(href: 'c1', title: '独章', paras: [_p('仅一段。$_lorem')]),
      ]);
      await openReader(t, small, 'u4');
      expect(pgLbl(t).$4, 1);
      await flipR(t);
      await step(t, times: 3);
      expect(find.textContaining('已读完最后一页'), findsOne);
      final b = await repo.bookById('u4');
      expect(b!.state, Book.kStateDone);
      await clearToasts(t);
    });
  });

  group('批2-U · 进度条与位置记忆', () {
    testWidgets('拖动进度 → 全书定位；退出重进恢复同页', (t) async {
      await openReader(t, _bigDoc(), 'u5');
      await t.tap(find.byKey(const ValueKey('brBtnProg'))); // 进度滑条在进度面板内
      await step(t);
      await t.drag(
        find.byKey(const ValueKey('brProg')),
        const Offset(260, 0),
      );
      await step(t, ms: 300, times: 2);
      final g = pgLbl(t).$3;
      final tot = pgLbl(t).$4;
      expect(g, greaterThan(tot ~/ 2));
      await step(t, ms: 300);
      // 重进：换挂载即重读 reader.pos（同库同书 → 位置回落）。
      // 不用 br-back：根路由弹出会触发 Navigator 空历史断言。
      await t.pumpWidget(const SizedBox.shrink());
      await step(t);
      await t.pumpWidget(wrap(ReaderPage(bookId: 'u5'), _bigDoc()));
      await step(t, times: 4);
      await centerTap(t); // 重进后 chrome 收起，点开读页码
      await step(t);
      expect(pgLbl(t).$3, g);
    });
  });

  group('批2-U · 目录侧边抽屉', () {
    testWidgets('开→跳二章→折叠 rail→展开', (t) async {
      await openReader(t, _bigDoc(), 'u6');
      await showChrome(t);
      await t.tap(find.byKey(const ValueKey('brBtnToc')));
      await step(t);
      expect(find.byKey(const ValueKey('brDrPanel')), findsOne);
      expect(find.byKey(const ValueKey('brDrCh-1')), findsOne);
      expect(find.byKey(const ValueKey('brDrCurBar-0')), findsOne);
      final gBefore = pgLbl(t).$3;
      await t.tap(find.byKey(const ValueKey('brDrCh-1')));
      await step(t, ms: 300);
      expect(find.byKey(const ValueKey('brDrPanel')), findsNothing); // 跳章即收
      expect(pgLbl(t).$1, 1); // 二章首页
      expect(pgLbl(t).$3, greaterThan(gBefore)); // 全局页跨入二章区段
      // 折叠成 rail 再展开
      await t.tap(find.byKey(const ValueKey('brBtnToc')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brDrCollapse')));
      await step(t);
      expect(find.byKey(const ValueKey('brDrRail')), findsOne);
      expect(find.byKey(const ValueKey('brDrPanel')), findsNothing);
      await t.tap(find.byKey(const ValueKey('brDrRail')));
      await step(t);
      expect(find.byKey(const ValueKey('brDrPanel')), findsOne);
      await t.tapAt(const Offset(380, 390)); // 面板宽 300，遮罩点在右侧
      await step(t);
      expect(find.byKey(const ValueKey('brDrPanel')), findsNothing);
    });

    testWidgets('搜本书：命中→跳原文挂上/下一处', (t) async {
      await openReader(t, _bigDoc(), 'u7');
      await showChrome(t);
      await t.tap(find.byKey(const ValueKey('brBtnToc')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brDrTabSearch')));
      await step(t);
      await t.enterText(find.byKey(const ValueKey('brDrQ')), '二之7。');
      await step(t);
      expect(find.byKey(const ValueKey('brDrHit-0')), findsOne);
      await t.tap(find.byKey(const ValueKey('brDrHit-0')));
      await step(t, ms: 300);
      expect(find.byKey(const ValueKey('brDrPanel')), findsNothing);
      await showChrome(t);
      expect(find.byKey(const ValueKey('brHitsBar')), findsOne);
      expect(find.textContaining('处匹配'), findsOne);
      await t.tap(find.byKey(const ValueKey('brHitClear')));
      await step(t);
      expect(find.byKey(const ValueKey('brHitsBar')), findsNothing);
    });
  });

  group('批2-U · 插图', () {
    testWidgets('点插图→放大弹层，可关闭', (t) async {
      await openReader(t, _bigDoc(), 'u8');
      // 插图在第一章第 3 段：先翻到含它的页（首页大概率含）。
      var guard = 0;
      while (find.byKey(const ValueKey('brImg-0-2')).evaluate().isEmpty &&
          guard < 20) {
        await flipR(t);
        await step(t, ms: 300);
        guard++;
      }
      expect(find.byKey(const ValueKey('brImg-0-2')), findsOne);
      await t.tap(find.byKey(const ValueKey('brImg-0-2')));
      await step(t, ms: 400);
      expect(find.byKey(const ValueKey('sheetBrImg')), findsOne);
      expect(find.byKey(const ValueKey('brImgSave')), findsOne);
      // 弹层底部按钮在测试视口外（viewInsets 口径），点遮罩关闭。
      await t.tapAt(const Offset(210, 50));
      await step(t, ms: 400);
      expect(find.byKey(const ValueKey('sheetBrImg')), findsNothing);
    });
  });

  group('真机修⑥ · 文档缓存回灌', () {
    testWidgets('现开的文档进 epubPreloadProvider.docs（重进不再二次解析）', (t) async {
      await useSurface(t, const Size(420, 780));
      await addBook('u9');
      final c = ProviderContainer(
        overrides: [
          readRepositoryProvider.overrideWithValue(repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
          epubDocLoaderProvider.overrideWithValue((_) async => _bigDoc()),
        ],
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: ReaderPage(bookId: 'u9')),
        ),
      );
      await step(t, times: 4);
      expect(find.byKey(const ValueKey('brPgLbl')), findsNothing); // chrome 未开
      expect(c.read(epubPreloadProvider).docs.get('u9'), isNotNull);
    });
  });
}
