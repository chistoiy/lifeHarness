import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/read/data/isbn_enrich.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/domain/book_dict.dart';
import 'package:lifeharness/features/read/presentation/biblio/biblio_search_page.dart';
import 'package:lifeharness/features/read/presentation/shelf/book_form_page.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';

/// V1.44「添加图书先搜后加」两页冒烟（原型 p-biblioSearch / p-bookForm）。
/// 新用例独立成文件：全 app 测试拆分防 isolate 污染（helpers §铁律）。
/// 网络全部走注入假 fetcher（widget 测试禁真实异步 I/O）；豆瓣详情页返回
/// 手搓 microdata 页（形态钉在 douban_isbn_desktop.html 真页 fixture）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ReadRepository repo;
  late SharedPreferences prefs;

  setUp(() async {
    DoubanGuard.reset();
    DoubanCookie.set(null);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = ReadRepository(db);
  });
  tearDown(() => db.close());

  /// 假豆瓣详情页：microdata 形态与真页一致（v:itemreviewed / author / press
  /// / pl 行：译者·丛书·装帧·定价·字数·ISBN / og:description / author_info）。
  const detailHtml = '''
<html><head>
<meta property="og:description" content="一本用于测试的书籍简介。"/>
</head><body>
<h1 property="v:itemreviewed">测试图书</h1>
<div id="info">
<span class="pl">作者:</span> <a href="https://book.douban.com/author/1000001/">测试作者</a><br/>
<span class="pl">出版社:</span> <a href="https://book.douban.com/press/2000001/">测试出版社</a><br/>
<span class="pl">出版年:</span> 2020-6<br/>
<span class="pl">页数:</span> 288<br/>
<span class="pl">译者:</span> 某译者<br/>
<span class="pl">丛书:</span>&nbsp;<a href="https://book.douban.com/series/300/">测试丛书</a><br/>
<span class="pl">装帧:</span> 平装<br/>
<span class="pl">定价:</span> 39.00元<br/>
<span class="pl">字数:</span> 250,000<br/>
<span class="pl">ISBN:</span> 9787000000001<br/>
</div>
<span class="rating_num">8.6</span>
<div id="mainpic"><img src="https://img3.doubanio.com/test.jpg"/></div>
<div id="author_info"><div>测试作者的简介</div></div>
</body></html>
''';

  Widget boot(Widget home, List<Override> extra) => ProviderScope(
    overrides: [
      readRepositoryProvider.overrideWithValue(repo),
      sharedPreferencesProvider.overrideWithValue(prefs),
      // 封面字节假通道：saveCover 在取目录前短路（widget 测试禁真 I/O）。
      isbnBytesFetcherProvider.overrideWith((ref) => (uri) async => null),
      ...extra,
    ],
    child: MaterialApp(home: home),
  );

  IsbnPageFetcher fakeFetcher(String suggestJson) => (uri) async {
    final u = uri.toString();
    if (u.contains('subject_suggest')) return suggestJson;
    if (u.contains('/subject/')) return detailHtml;
    return null;
  };

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 120));
  }

  /// 补全/保存链夹着真 sqflite 往返与假 fetcher：混泵 runAsync 才能推进
  /// （douban_cache_form_test.pumpLookup 同法）。
  Future<void> pumpLookup(WidgetTester tester) async {
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    }
  }

  Future<void> pollUntil(WidgetTester tester, bool Function() cond) async {
    for (var i = 0; i < 30; i++) {
      bool ok = false;
      try {
        ok = cond();
      } catch (_) {
        ok = false;
      }
      if (ok) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
    }
    throw StateError('轮询超时：目标状态始终未出现');
  }

  String fieldText(WidgetTester tester, String key) => tester
      .widget<TextField>(find.byKey(ValueKey(key)))
      .controller!
      .text;

  /// F1-3：出版日期/购入日期改滚轮触发器（GestureDetector），读数取行内回显 Text。
  String dateText(WidgetTester tester, String key) => tester
      .widget<Text>(find.descendant(
          of: find.byKey(ValueKey(key)), matching: find.byType(Text)))
      .data!;

  testWidgets('① 搜索页：输入→假 fetcher 出 2 行→渲染标题与作者行；未接入源点不动（F2-14）', (tester) async {
    const twoRows =
        '[{"id":"1041482","title":"万历十五年","author_name":"[美] 黄仁宇",'
        '"year":"1997","pic":"https://img3.doubanio.com/s1800355.jpg"},'
        '{"id":"2282229","title":"我的二本学生","author_name":"黄灯",'
        '"year":"2020","pic":""}]';
    await tester.pumpWidget(
      boot(
        const BiblioSearchPage(),
        [isbnPageFetcherProvider.overrideWith((ref) => fakeFetcher(twoRows))],
      ),
    );
    await tester.pump();
    // 起手空态。
    expect(find.text('搜书名、作者或 ISBN'), findsOneWidget);
    // F2-14（LH-K36）：未接入源＝禁用第三态——常开＋置灰＋点不动（onTap 恒 null）
    // ＋固定小标「· 未接入」，不再弹「该源未接入」提示条。
    await tester.ensureVisible(find.byKey(const ValueKey('bsr-chip-晋江文学城')));
    final jjChip = tester.widget<GestureDetector>(
        find.byKey(const ValueKey('bsr-chip-晋江文学城')));
    expect(jjChip.onTap, isNull, reason: '未接入源点不动（禁用第三态）');
    expect(find.text('晋江文学城 · 未接入'), findsOneWidget, reason: '固定小标常驻');
    await tester.tap(find.byKey(const ValueKey('bsr-chip-晋江文学城')));
    await tester.pump();
    expect(find.text('该源未接入 · 本批只支持豆瓣'), findsNothing,
        reason: '禁用项点不动 ⇒ 不再借道提示条');

    await tester.enterText(find.byKey(const ValueKey('bsr-q')), '万历');
    await tester.pump(const Duration(milliseconds: 400)); // 350ms 防抖
    await settle(tester);
    expect(find.byKey(const ValueKey('bsr-row-1041482')), findsOneWidget);
    expect(find.byKey(const ValueKey('bsr-row-2282229')), findsOneWidget);
    expect(find.text('万历十五年'), findsOneWidget);
    // 次行「作者 / 年」（国别前缀已剥）；无评分显灰「未评分」。
    expect(find.text('黄仁宇 / 1997'), findsOneWidget);
    expect(find.text('未评分'), findsNWidgets(2));
    // FAB 二选一收起时只有主钮。
    expect(find.byKey(const ValueKey('bsr-fab')), findsOneWidget);
    expect(find.byKey(const ValueKey('bsr-fab-scan')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('bsr-fab')));
    await tester.pump();
    expect(find.byKey(const ValueKey('bsr-fab-scan')), findsOneWidget);
    expect(find.byKey(const ValueKey('bsr-fab-manual')), findsOneWidget);
  });

  testWidgets('② 点结果行进表单：列表字段即时预填，detailById 全字段照填只填空位', (tester) async {
    const oneRow =
        '[{"id":"9000001","title":"测试图书","author_name":"测试作者",'
        '"year":"2020","pic":""}]';
    await tester.pumpWidget(
      boot(
        const BiblioSearchPage(),
        [isbnPageFetcherProvider.overrideWith((ref) => fakeFetcher(oneRow))],
      ),
    );
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('bsr-q')), '测试图书');
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('bsr-row-9000001')));
    await settle(tester);
    // 加高视口：预填断言涉及长表单深部字段（简介/购入价格等）。
    await useSurface(tester);
    await settle(tester);

    // 标题三态：豆瓣带入＝「添加到书架」。
    expect(find.text('添加到书架'), findsOneWidget);
    // 列表已知字段即时填。
    expect(fieldText(tester, 'bf-title'), '测试图书');
    expect(fieldText(tester, 'bf-author'), '测试作者');
    // 详情全字段照填（只填空字段：出版日期留列表带来的「2020」不被覆盖）。
    await pumpLookup(tester);
    expect(dateText(tester, 'bf-pubDate'), '2020');
    expect(fieldText(tester, 'bf-translator'), '某译者');
    expect(fieldText(tester, 'bf-publisher'), '测试出版社');
    expect(fieldText(tester, 'bf-series'), '测试丛书');
    expect(fieldText(tester, 'bf-binding'), '平装');
    expect(fieldText(tester, 'bf-isbn'), '9787000000001');
    expect(fieldText(tester, 'bf-pg'), '288');
    expect(fieldText(tester, 'bf-wc'), '250000');
    // 定价→购入价格；来源默认豆瓣。
    expect(fieldText(tester, 'bf-fee'), '39.0');
    expect(
      tester.widget<DropdownButton<String>>(find.byKey(const ValueKey('bf-src'))).value,
      '豆瓣',
    );
    // 简介两框有内容默认展开。
    expect(fieldText(tester, 'bf-intro'), contains('测试的书籍简介'));
    expect(fieldText(tester, 'bf-authorNote'), contains('测试作者的简介'));
    // 豆瓣评分只读行（10 分制原样，不换算 5 星）+ 状态口径沿用 sheet。
    expect(find.text('8.6 分'), findsOneWidget);
    expect(find.text('已命中 · 自动填充'), findsOneWidget);
    // 状态默认想读。
    expect(fieldText(tester, 'bf-rp'), '');
    await clearToasts(tester);
  });

  testWidgets('③ 手动输入：空表单填书名点添加→书架出现该书（默认想读 · 总页数 300）', (tester) async {
    await tester.pumpWidget(
      boot(
        const BookFormPage(),
        [isbnPageFetcherProvider.overrideWith((ref) => (uri) async => null)],
      ),
    );
    await tester.pump();
    expect(find.text('手动录入'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('bf-title')), '被讨厌的勇气');
    await tester.tap(find.byKey(const ValueKey('bf-save')));
    await pumpLookup(tester);

    final books = await repo.allBooks();
    expect(books.length, 1);
    final b = books.single;
    expect(b.title, '被讨厌的勇气');
    expect(b.state, Book.kStateWant);
    expect(b.pages, 300);
    expect(b.readPages, 0);
    expect(find.text('《被讨厌的勇气》已加入书架 · 在「想读」分区'), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('④ 编辑态：bookById 回填全字段，保存后 updateBook 生效且新列不丢', (tester) async {
    await repo.addBook(
      Book(
        id: 'x',
        title: '万历十五年',
        author: '黄仁宇',
        publisher: '生活·读书·新知三联书店',
        state: Book.kStateReading,
        pages: 370,
        readPages: 100,
        isbn: '9787108009821',
        binding: '精装',
        wordCount: 141000,
        createdAt: 1,
        updatedAt: 1,
      ),
    );
    await tester.pumpWidget(
      boot(
        const BookFormPage(bookId: 'x'),
        [isbnPageFetcherProvider.overrideWith((ref) => (uri) async => null)],
      ),
    );
    await tester.pump();
    expect(find.text('编辑书籍信息'), findsOneWidget);
    // 加高视口：长表单懒构建，深部字段（总页码等）先进树才可读。
    await useSurface(tester);
    await settle(tester);
    // 异步回填（真 sqflite 往返）：轮询到编辑态字段就位。
    await pollUntil(tester, () => fieldText(tester, 'bf-title') == '万历十五年');
    expect(fieldText(tester, 'bf-binding'), '精装');
    expect(fieldText(tester, 'bf-wc'), '141000');
    expect(fieldText(tester, 'bf-pg'), '370');
    expect(fieldText(tester, 'bf-isbn'), '9787108009821');

    await tester.enterText(find.byKey(const ValueKey('bf-title')), '万历十五年（修订本）');
    await tester.tap(find.byKey(const ValueKey('bf-save')));
    await pumpLookup(tester);

    final b = await repo.bookById('x');
    expect(b!.title, '万历十五年（修订本）');
    expect(b.binding, '精装', reason: '整页保存不得丢 v24 新列');
    expect(b.wordCount, 141000);
    expect(b.state, Book.kStateReading, reason: '未读满不自动落已读（页码未动）');
    expect(find.text('书籍信息已保存'), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('⑤ V1.46⑧ 标签行内添加：bf-tag-add→就地输入→bf-tag-add-ok 落字典并选中；空名/重名 toast 不新增', (tester) async {
    await tester.pumpWidget(
      boot(
        const BookFormPage(),
        [isbnPageFetcherProvider.overrideWith((ref) => (uri) async => null)],
      ),
    );
    await tester.pump();
    // 标签行在「书籍管理」卡片深部，懒构建需加高视口。
    await useSurface(tester);
    await settle(tester);

    // ① 点「＋ 添加标签」→ 就地展开输入行（同页内嵌，无弹层）。
    await tester.tap(find.byKey(const ValueKey('bf-tag-add')));
    await tester.pump();
    expect(find.byKey(const ValueKey('bf-tag-name')), findsOneWidget);

    // ② 空名确认 → toast 不新增。
    await tester.tap(find.byKey(const ValueKey('bf-tag-add-ok')));
    await tester.pump();
    expect(find.text('标签名不能为空'), findsOneWidget);
    await clearToasts(tester);
    expect(await repo.dictOf(DictEntry.kTag), isEmpty);

    // ③ 输入「新标签」确认 → 字典出现且立即选中（保存后随书落 tags）。
    await tester.enterText(find.byKey(const ValueKey('bf-tag-name')), '新标签');
    await tester.tap(find.byKey(const ValueKey('bf-tag-add-ok')));
    await pumpLookup(tester);
    var dict = await repo.dictOf(DictEntry.kTag);
    expect(dict.map((e) => e.name), contains('新标签'));
    // chips 行经 readTick 刷新：新标签 chip 已入树。
    await settle(tester);
    expect(find.byKey(const ValueKey('bf-tag-新标签')), findsOneWidget);

    // ④ 重名再加点 → toast 提示不新增（字典仍 1 条）。
    await tester.tap(find.byKey(const ValueKey('bf-tag-add')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('bf-tag-name')), '新标签');
    await tester.tap(find.byKey(const ValueKey('bf-tag-add-ok')));
    await tester.pump();
    expect(find.text('标签已存在'), findsOneWidget);
    await clearToasts(tester);
    dict = await repo.dictOf(DictEntry.kTag);
    expect(dict.length, 1);

    // ⑤ 立即选中：保存书籍 → tags 含「新标签」。
    await tester.enterText(find.byKey(const ValueKey('bf-title')), '被讨厌的勇气');
    await tester.tap(find.byKey(const ValueKey('bf-save')));
    await pumpLookup(tester);
    final b = (await repo.allBooks()).single;
    expect(b.tags, contains('新标签'));
    await clearToasts(tester);
  });
}
