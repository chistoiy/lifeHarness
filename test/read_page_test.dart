import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/domain/book_list.dart';
import 'package:lifeharness/features/read/domain/book_quote.dart';
import 'package:lifeharness/features/read/domain/book_dict.dart';
import 'package:lifeharness/features/read/presentation/book_detail.dart';
import 'package:lifeharness/features/read/presentation/quotes_lib_page.dart';
import 'package:lifeharness/features/read/presentation/read_lists_page.dart';
import 'package:lifeharness/features/read/presentation/read_stat_page.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/book_info_page.dart';
import 'package:lifeharness/features/read/presentation/book_mgr_page.dart';
import 'package:lifeharness/features/read/presentation/read_import_page.dart';
import 'package:lifeharness/features/read/presentation/read_settings_page.dart';
import 'package:lifeharness/features/read/presentation/read_tab.dart';
import 'package:lifeharness/features/read/presentation/read_timer_page.dart';
import 'package:lifeharness/features/read/presentation/shelf_page.dart';

/// M1批3 · 阅读工作台与书架 widget 测试（独立文件防 isolate 污染）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ReadRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = ReadRepository(db);
  });
  tearDown(() => db.close());

  final now = DateTime.now();
  int ms(int daysAgo) => now.millisecondsSinceEpoch - daysAgo * 86400000;

  Book bk(String id, String t, String st,
          {int pages = 100, int rp = 0, int? last}) =>
      Book(
          id: id,
          title: t,
          author: '作者$t',
          state: st,
          pages: pages,
          readPages: rp,
          lastReadAt: last ?? ms(1),
          createdAt: ms(30),
          updatedAt: last ?? ms(1));

  Widget page(Widget home) => ProviderScope(
        overrides: [readRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Directionality(textDirection: TextDirection.ltr, child: home),
        ),
      );

  /// 带 /read/* 路由的壳（工作台 context.push 需要）。
  Widget routed(Widget root) {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => root),
      GoRoute(
          path: '/read/shelf', builder: (_, _) => const ShelfPage()),
      GoRoute(
          path: '/read/book/:id',
          builder: (_, s) => BookDetailPage(
              bookId: s.pathParameters['id']!,
              initialTab: (s.extra as BookDetailArg?)?.tab ?? 'c')),
      GoRoute(
          path: '/read/info/:id',
          builder: (_, s) => BookInfoPage(bookId: s.pathParameters['id']!)),
      GoRoute(
          path: '/read/timer/:id',
          builder: (_, s) => ReadTimerPage(bookId: s.pathParameters['id']!)),
      GoRoute(
          path: '/read/quotes',
          builder: (_, s) => QuotesLibPage(bookId: s.extra as String?)),
      GoRoute(
          path: '/read/stat',
          builder: (_, _) => const ReadStatPage()),
      GoRoute(
          path: '/read/lists',
          builder: (_, _) => const BookListsPage()),
      GoRoute(
          path: '/read/list/:id',
          builder: (_, s) =>
              BookListDetailPage(listId: int.parse(s.pathParameters['id']!))),
      GoRoute(
          path: '/read/import',
          builder: (_, _) => const ReadImportPage()),
      GoRoute(
          path: '/read/settings',
          builder: (_, _) => const ReadSettingsPage()),
      GoRoute(
          path: '/read/mgr',
          builder: (_, s) => BookMgrPage(
              kind: s.uri.queryParameters['kind'] ?? 'source')),
    ]);
    return ProviderScope(
      overrides: [readRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(
          routerConfig: router,
          builder: (_, child) => Scaffold(body: child)),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 120));
  }

  /// workbench 聚合含多轮 sqflite 往返，假异步下泵帧不确定完成 → runAsync 轮询。
  Future<void> waitFinder(WidgetTester tester, Finder f,
      {int times = 15}) async {
    for (var i = 0; i < times; i++) {
      if (f.evaluate().isNotEmpty) return;
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }
    expect(f, findsOneWidget);
  }

  group('批3-3 工作台', () {
    testWidgets('R-1 空态 → 添加一本 → 轨卡与在读数出现', (tester) async {
      await tester.pumpWidget(routed(const ReadWorkbench()));
      await settle(tester);
      expect(find.byKey(const ValueKey('read-empty-add')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('read-empty-add')));
      await settle(tester);
      expect(find.text('新书上架'), findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('bkf-title')), '思考，快与慢');
      await tester.tap(find.byKey(const ValueKey('bkf-save')));
      await settle(tester);
      await clearToasts(tester);

      expect(find.text('思考，快与慢'), findsWidgets); // 轨卡 + toast 前文本
      expect(find.textContaining('在读 1 本'), findsOneWidget);
    });

    testWidgets('R-2 今日卡计时钮：无在读书提示 · 有在读书起停', (tester) async {
      await tester.pumpWidget(routed(const ReadWorkbench()));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('read-timer')));
      await settle(tester);
      expect(find.text('书架上暂时没有在读的书'), findsOneWidget);
      await clearToasts(tester);

      await repo.addBook(bk('r', '原子习惯', Book.kStateReading));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('read-timer')));
      await settle(tester);
      expect(find.textContaining('已为《原子习惯》开始计时'), findsOneWidget);
      await clearToasts(tester);
      expect(find.text('结束计时'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('read-timer')));
      await settle(tester);
      expect(find.textContaining('已结束计时'), findsOneWidget);
      await clearToasts(tester);
      expect(find.text('计时'), findsOneWidget);
      expect(await repo.runningSession(), isNull);
    });

    testWidgets('R-3 最近摘录空态与复习卡存在', (tester) async {
      await tester.pumpWidget(routed(const ReadWorkbench()));
      await settle(tester);
      expect(find.text('最近摘录'), findsOneWidget);
      expect(find.text('还没有摘录 · 右下角 ＋ 记第一条'), findsOneWidget);
      expect(find.text('摘录复习'), findsOneWidget);
      expect(find.textContaining('共 0 条'), findsOneWidget);
    });
  });

  group('批3-4 书架', () {
    Future<void> seed5() async {
      await repo.addBook(bk('a', '书A', Book.kStateReading, rp: 50, last: ms(1)));
      await repo.addBook(bk('b', '书B', Book.kStateReading, rp: 10, last: ms(2)));
      await repo.addBook(bk('c', '书C', Book.kStateWant, last: ms(3)));
      await repo.addBook(bk('d', '书D', Book.kStateDone, last: ms(4))
          .copyWith(endedAt: ms(4)));
      await repo.addBook(bk('e', '书E', Book.kStateDropped, last: ms(5)));
    }

    testWidgets('R-4 五本 → 四分区计数与网格 5 卡', (tester) async {
      await seed5();
      await tester.pumpWidget(page(const ShelfPage()));
      await settle(tester);
      await useSurface(tester);
      await settle(tester);
      // openTab 原型默认「在读」→ 进书架先点「全部」再看五卡（批A 保真）。
      await tester.tap(find.byKey(const ValueKey('sh-chip-全部')));
      await settle(tester);
      expect(find.text('在读 2'), findsOneWidget);
      expect(find.text('想读 1'), findsOneWidget);
      expect(find.text('已读 1'), findsOneWidget);
      expect(find.text('弃读 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('sh-item-a')), findsOneWidget);
      expect(find.text('5 本 · 全部'), findsOneWidget);
    });

    testWidgets('R-5 视图钮循环 5 态无异常', (tester) async {
      await seed5();
      await tester.pumpWidget(page(const ShelfPage()));
      await settle(tester);
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(const ValueKey('sh-view')));
        await settle(tester);
        expect(tester.takeException(), isNull, reason: '第 $i 次切换');
      }
      // 回到 wall（第5次点击从 rows → wall）
      expect(find.byKey(const ValueKey('sh-grid-3-')), findsOneWidget);
    });

    testWidgets('R-6 批量浮动条移分区（循环到下一分区）：计数·目标卡·时间线同帧同步',
        (tester) async {
      await seed5();
      await tester.pumpWidget(page(const ShelfPage()));
      await settle(tester);
      await useSurface(tester);
      await settle(tester);
      // 同上：默认落「在读」，先回「全部」再批量（批A 保真）。
      await tester.tap(find.byKey(const ValueKey('sh-chip-全部')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-manage')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-item-a')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-item-b')));
      await settle(tester);
      expect(find.text('已选 2 本'), findsOneWidget);
      // 原型 shBatchMove：首本当前分区（在读）→ 循环到下一分区（想读）
      await tester.tap(find.byKey(const ValueKey('bat-move')));
      await settle(tester);
      expect(find.text('已将 2 本移入「想读」'), findsOneWidget);
      await clearToasts(tester);
      expect(find.text('在读 0'), findsOneWidget);
      expect(find.text('想读 3'), findsOneWidget);
      // 再循环一次：想读 → 已读（数据层补满进度与 ended_at）
      await tester.tap(find.byKey(const ValueKey('sh-manage')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-item-a')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-item-b')));
      await settle(tester);
      expect(find.text('已选 2 本'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bat-move')));
      await settle(tester);
      await clearToasts(tester);
      await waitFinder(tester, find.textContaining('3 / 50 本'));
      expect(find.text('已读 3'), findsOneWidget);
      final a = (await repo.allBooks()).firstWhere((b) => b.id == 'a');
      expect(a.readPages, a.pages);
      expect(a.endedAt, isNotNull);
      // 时间线视图（墙→墙4→列表→书脊→时间线，第 4 次点）同步出现「读完《书A》」
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const ValueKey('sh-view')));
        await settle(tester);
      }
      await waitFinder(tester, find.textContaining('读完《书A》'));
      expect(find.textContaining('读完《书B》'), findsOneWidget);
    });

    testWidgets('R-6b 批量浮动条：加标签落库 · 删除＝软删 30 天文案', (tester) async {
      await seed5();
      await repo.addQuote(BookQuote(
        bookId: 'a',
        kind: BookQuote.kKindMark,
        body: '先有一条摘录',
        createdAt: ms(2),
        updatedAt: ms(2),
      ));
      await tester.pumpWidget(page(const ShelfPage()));
      await settle(tester);
      await useSurface(tester);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-chip-全部')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-manage')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-item-a')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('bat-tag')));
      await settle(tester);
      await tester.enterText(
          find.byKey(const ValueKey('bat-tag-new')), '方法论');
      await tester.tap(find.byKey(const ValueKey('bat-tag-ok')));
      await settle(tester);
      await waitFinder(tester, find.text('已为 1 本加上 #方法论'));
      final tagged = (await repo.allBooks()).firstWhere((b) => b.id == 'a');
      expect(tagged.tags, contains('方法论'));
      expect(await repo.quoteTags(), contains('方法论'));
      await clearToasts(tester);
      // 批量删除：软删 + 原型 4627 逐字文案（笔记与时长保留 30 天可恢复）
      await tester.tap(find.byKey(const ValueKey('sh-manage')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-item-a')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-item-b')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('bat-del')));
      await settle(tester);
      await waitFinder(
          tester, find.text('已移出书架 2 本（笔记与时长保留 30 天可恢复）'));
      final left = (await repo.allBooks());
      expect(left.firstWhere((b) => b.id == 'a').isDeleted, isTrue);
      expect(left.firstWhere((b) => b.id == 'b').isDeleted, isTrue);
      // 摘录与计时不随书删除（软删语义）
      expect(await repo.allQuotes(), hasLength(1));
    });

    testWidgets('R-6c 批量浮动条「取消」退出多选且不写库', (tester) async {
      await seed5();
      await tester.pumpWidget(page(const ShelfPage()));
      await settle(tester);
      await useSurface(tester);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-chip-全部')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-manage')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-item-a')));
      await settle(tester);
      expect(find.byKey(const ValueKey('bat-bar')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bat-cancel')));
      await settle(tester);
      expect(find.byKey(const ValueKey('bat-bar')), findsNothing);
      final a = (await repo.allBooks()).firstWhere((b) => b.id == 'a');
      expect(a.state, Book.kStateReading);
    });

    testWidgets('R-7 ⇅ 面板「书架排序与筛选」：6 行竖排钮 · 清空筛选', (tester) async {
      await seed5();
      await tester.pumpWidget(page(const ShelfPage()));
      await settle(tester);
      await useSurface(tester);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-panel')));
      await settle(tester);
      expect(find.text('书架排序与筛选'), findsOneWidget);
      // 原型 2339-2347：排序＝6 行全宽按钮
      for (final (k, _) in kShelfSorts) {
        expect(find.byKey(ValueKey('panel-sort-$k')), findsOneWidget,
            reason: '排序项 $k');
      }
      await tester.ensureVisible(find.byKey(const ValueKey('panel-dim-author')));
      await tester.tap(find.byKey(const ValueKey('panel-dim-author')));
      await settle(tester);
      // 选中态：排序钮带 ✓（当前 recent 选中）
      expect(find.text('书名（拼音）'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('panel-done')));
      await tester.tap(find.byKey(const ValueKey('panel-done')));
      await settle(tester);
      // 维度值行：值 chips 带「N 本」计数（原型 5389-5396）
      expect(find.text('作者书A 1 本'), findsOneWidget);
      expect(find.text('作者书E 1 本'), findsOneWidget);
      // 清空筛选＝kw/维度/分区/排序全回默认
      await tester.tap(find.byKey(const ValueKey('sh-panel')));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('panel-reset')));
      await tester.tap(find.byKey(const ValueKey('panel-reset')));
      await settle(tester);
      await clearToasts(tester);
      await tester.tap(find.byKey(const ValueKey('panel-done')));
      await settle(tester);
      expect(find.text('作者书A 1 本'), findsNothing);
      expect(find.text('5 本 · 全部'), findsOneWidget);
    });

    testWidgets('R-7b 维度行「管理作者」跳 /read/mgr?kind=author', (tester) async {
      await seed5();
      await tester.pumpWidget(routed(const ShelfPage()));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-panel')));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('panel-dim-author')));
      await tester.tap(find.byKey(const ValueKey('panel-dim-author')));
      await tester.tap(find.byKey(const ValueKey('panel-done')));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('sh-dim-mgr-author')));
      await tester.tap(find.byKey(const ValueKey('sh-dim-mgr-author')));
      await settle(tester);
      expect(find.text('书架资料'), findsOneWidget);
      // 默认 tab 跟随 kind 参数
      expect(find.byKey(const ValueKey('bkm-add-inp-author')), findsOneWidget);
    });

    testWidgets('R-7c 搜索：placeholder 与命中摘录原文/标签', (tester) async {
      await repo.addBook(bk('s1', '稀缺书', Book.kStateReading, last: ms(1))
          .copyWith(tags: const ['稀缺标签']));
      await repo.addBook(bk('s2', '另一本', Book.kStateReading, last: ms(1)));
      await repo.addQuote(BookQuote(
        bookId: 's1',
        kind: BookQuote.kKindMark,
        body: '只有摘录里出现的句子',
        createdAt: ms(2),
        updatedAt: ms(2),
      ));
      await tester.pumpWidget(page(const ShelfPage()));
      await settle(tester);
      await useSurface(tester);
      await settle(tester);
      // openTab 默认「在读」→ 先回「全部」（底行统计断言需要）。
      await tester.tap(find.byKey(const ValueKey('sh-chip-全部')));
      await settle(tester);
      expect(find.text('搜索书名 / 作者 / 标签 / 摘录'), findsOneWidget);
      // 命中摘录：书名/作者都不含该串
      await tester.enterText(find.byKey(const ValueKey('sh-kw')), '出现的句子');
      await waitFinder(tester, find.text('1 本 · 全部'));
      expect(find.byKey(const ValueKey('sh-item-s1')), findsOneWidget);
      // 命中标签
      await tester.enterText(find.byKey(const ValueKey('sh-kw')), '稀缺标签');
      await waitFinder(tester, find.text('1 本 · 全部'));
      expect(find.byKey(const ValueKey('sh-item-s2')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('sh-kw')), '无此内容');
      await settle(tester);
      expect(find.textContaining('没有符合条件的书'), findsOneWidget);
    });

    testWidgets('R-7d 目标卡：剩天/预计达成/白进度条 · 编号格阵与年度书单',
        (tester) async {
      final y = DateTime.now().year;
      final done1 = bk('g1', '今年第一本', Book.kStateDone, last: ms(3))
          .copyWith(endedAt: DateTime(y, 3, 5).millisecondsSinceEpoch);
      final done2 = bk('g2', '今年第二本', Book.kStateDone, last: ms(2))
          .copyWith(endedAt: DateTime(y, 5, 9).millisecondsSinceEpoch);
      await repo.addBook(done1);
      await repo.addBook(done2);
      await repo.addBook(bk('g3', '还在读', Book.kStateReading));
      await tester.pumpWidget(routed(const ShelfPage()));
      await settle(tester);
      await useSurface(tester);
      await settle(tester);
      await waitFinder(tester, find.textContaining('读完 2 / 50 本'));
      final now = DateTime.now();
      final daysLeft =
          DateTime(y, 12, 31).difference(DateTime(now.year, now.month, now.day)).inDays + 1;
      // 原型 826：剩 N 天 · 节奏刚好（预计 MM-DD 达成）
      expect(find.textContaining('剩 $daysLeft 天 · 节奏刚好（预计 '), findsOneWidget);
      // 白色进度条（LinearProgressIndicator 值 = 2/50）
      final bar = tester.widget<LinearProgressIndicator>(
          find.byKey(const ValueKey('sh-goal-bar')));
      expect(bar.value, closeTo(2 / 50, 1e-9));
      // 编号格阵：min(goal,40) 格，前两格点亮、第三格为占位灰格
      await tester.tap(find.byKey(const ValueKey('sh-yearbox-toggle')));
      await settle(tester);
      expect(find.byKey(const ValueKey('sh-yencell-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('sh-yencell-39')), findsOneWidget);
      expect(find.byKey(const ValueKey('sh-yencell-40')), findsNothing);
      // 点亮格跳该书详情（原型 blDetailYear → 详情）
      final router = GoRouter.of(
          tester.element(find.byKey(const ValueKey('sh-yencell-0'))));
      await tester.tap(find.byKey(const ValueKey('sh-yencell-0')));
      await settle(tester);
      expect(find.text('今年第一本'), findsWidgets);
      router.pop();
      await settle(tester);
      // 无年度单 → 「年度书单」触发生成并进入
      await tester.tap(find.byKey(const ValueKey('sh-year-list')));
      await settle(tester);
      await clearToasts(tester);
      final l = await repo.findAutoYear(y);
      expect(l, isNotNull);
      expect((await repo.listMembers(l!)).map((b) => b.id), ['g1', 'g2']);
    });

    testWidgets('R-7e 视图循环序＝墙3→墙4→列表→书脊→时间线（原型 4545）',
        (tester) async {
      await seed5();
      await tester.pumpWidget(page(const ShelfPage()));
      await settle(tester);
      await useSurface(tester);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-chip-全部')));
      await settle(tester);
      expect(find.byKey(const ValueKey('sh-grid-3-')), findsOneWidget);
      final expectView = <String, Finder>{
        'wall4': find.byKey(const ValueKey('sh-grid-4-')),
        'rows': find.byKey(const ValueKey('sh-row-timer-a')),
        'spine': find.text('书脊高度＝总页数 · 白点＝在读 · 点书脊看详情，长按进多选'),
        'time': find.textContaining('读完《书D》'),
      };
      for (final key in ['wall4', 'rows', 'spine', 'time']) {
        await tester.tap(find.byKey(const ValueKey('sh-view')));
        await settle(tester);
        await clearToasts(tester);
        expect(expectView[key], findsOneWidget, reason: '切到 $key 视图');
      }
      await tester.tap(find.byKey(const ValueKey('sh-view')));
      await settle(tester);
      expect(find.byKey(const ValueKey('sh-grid-3-')), findsOneWidget);
    });

    testWidgets('R-7f 长按菜单尾行「查看书籍详情」· 工作台轨卡同弹层',
        (tester) async {
      await seed5();
      await tester.pumpWidget(routed(const ReadWorkbench()));
      await settle(tester);
      await waitFinder(tester, find.byKey(const ValueKey('rail-a')));
      await tester.longPress(find.byKey(const ValueKey('rail-a')));
      await settle(tester);
      expect(find.byKey(const ValueKey('lp-quote')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('lp-detail')));
      await settle(tester);
      expect(find.byKey(const ValueKey('seg-c')), findsOneWidget);
    });

    testWidgets('R-7g 时间线：读完+购书/评分/会话/摘录四类事件·日头·尾行',
        (tester) async {
      await repo.addBook(Book(
          id: 't1',
          title: '书T',
          author: '作者T',
          state: Book.kStateDone,
          pages: 300,
          readPages: 300,
          startedAt: ms(5),
          endedAt: ms(2),
          lastReadAt: ms(2),
          rating: 9,
          fee: 59,
          finalNote: '双系统理论的结构性梳理',
          createdAt: ms(30),
          updatedAt: ms(2)));
      await repo.addQuote(BookQuote(
          bookId: 't1',
          kind: BookQuote.kKindMark,
          body: '你并没有 rise to the level of your goals，你只是 fall to the level of your systems 而已啊真的很长',
          createdAt: ms(2),
          updatedAt: ms(2)));
      await repo.addManualSession(
          bookId: 't1',
          day: DateTime.now().subtract(const Duration(days: 1)),
          minutes: 40,
          fromPage: 12,
          toPage: 30);
      await tester.pumpWidget(page(const ShelfPage()));
      await settle(tester);
      await useSurface(tester);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-chip-全部')));
      await settle(tester);
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const ValueKey('sh-view')));
        await settle(tester);
      }
      await clearToasts(tester);
      // 原型 bsEvents 文案：读完·页数·购书 ¥ / 评了 N 分：总结 / 读了 N 分钟·P起→P止 / 划线「原文46字」。
      expect(
          find.textContaining('读完《书T》· 300 页 · 购书 ¥59'), findsOneWidget);
      expect(find.textContaining('评了 9 分：双系统理论的结构性梳理'), findsOneWidget);
      expect(find.textContaining('读了 40 分钟 · P12→30'), findsOneWidget);
      expect(find.textContaining('「你并没有 rise'), findsOneWidget);
      // 书名·作者副行 + 日头计数 + 尾行说明（原型 shTimeline）。
      expect(find.text('书T · 作者T'), findsWidgets);
      expect(find.textContaining(' 条'), findsWidgets);
      expect(find.textContaining('范围可在阅读设置里调'), findsOneWidget);
    });

    testWidgets('R-8 长按菜单 → 记摘录落库并回显最近摘录', (tester) async {
      await seed5();
      await tester.pumpWidget(routed(const ShelfPage()));
      await settle(tester);
      await tester.longPress(find.byKey(const ValueKey('sh-item-a')));
      await settle(tester);
      expect(find.byKey(const ValueKey('lp-timer')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('lp-quote')));
      await settle(tester);
      expect(find.textContaining('新增摘录 · 《书A》'), findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('qef-body')), '系统1慢，需要刻意练习');
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('qef-save')));
      await tester.tap(find.byKey(const ValueKey('qef-save')));
      await settle(tester);
      expect(find.text('已记录这条摘录'), findsOneWidget);
      await clearToasts(tester);
      final qs = await repo.allQuotes();
      expect(qs.single.body, '系统1慢，需要刻意练习');
      expect(qs.single.kind, BookQuoteKind.mark);
    });

    testWidgets('R-9 详情页：可点芯片 + 顶栏计时全屏形态跳计时页', (tester) async {
      await repo.setKv('read.autoAsk', 'false'); // 结束不弹记进度，专注路由断言
      await seed5();
      await tester.pumpWidget(routed(const ShelfPage()));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-item-a')));
      await settle(tester);
      expect(find.byKey(const ValueKey('seg-c')), findsOneWidget);
      expect(find.byKey(const ValueKey('bd-min-chip')), findsOneWidget);
      expect(find.byKey(const ValueKey('bd-pct-chip')), findsOneWidget);
      // 顶栏计时（默认全屏形态）→ 跳 /read/timer/:id（周期 Timer 页不能用 settle）
      await tester.tap(find.byKey(const ValueKey('bd-timer')));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.byKey(const ValueKey('rt-toggle')), findsOneWidget);
      // 顶栏标题 + 大数字恒 HH:MM:SS + 未开始态（原型 rtFmt/rtState）
      expect(find.text('阅读计时'), findsOneWidget);
      expect(find.text('00:00:00'), findsOneWidget);
      expect(find.text('未开始'), findsOneWidget);
      // 页内开始 → 计时中 → 页内结束
      await tester.tap(find.byKey(const ValueKey('rt-toggle')));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.textContaining('计时中 · 结束后可直接记进度'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rt-toggle')));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      // 结算 toast 逐字（原型 rtToggle 5028：计时结束 · 本次 N 分钟）
      expect(find.textContaining('计时结束 · 本次'), findsOneWidget);
      await clearToasts(tester);
      // 胶囊形态：原地起停 + toast（页内返回先回详情页）
      await repo.setKv('read.timerUI', '顶部胶囊');
      await tester.tap(find.byKey(const ValueKey('rt-back')));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('bd-timer')));
      await settle(tester);
      expect(find.textContaining('已为《书A》开始计时'), findsOneWidget);
      await clearToasts(tester);
      final sess = await repo.allSessions();
      expect(sess.where((x) => x.running), hasLength(1));
      await tester.tap(find.byKey(const ValueKey('bd-timer')));
      await settle(tester);
      expect(find.textContaining('已结束计时'), findsOneWidget);
      await clearToasts(tester);
    });

    testWidgets('R-10 记进度四方式真实回写 + 计时明细差量', (tester) async {
      await seed5();
      await tester.pumpWidget(routed(const ShelfPage()));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-item-a')));
      await settle(tester);
      // 进度芯片 → 记进度弹层（原型 sheetProgress：标题+上下文行+从→到双输入）
      await tester.tap(find.byKey(const ValueKey('bd-pct-chip')));
      await settle(tester);
      expect(find.text('记录阅读进度'), findsOneWidget);
      expect(
          find.textContaining('本次未计时 · 手动补记 · 《书A》'), findsOneWidget);
      expect(find.byKey(const ValueKey('pgf-to')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('pgf-value')), '70');
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('pgf-save')));
      await tester.tap(find.byKey(const ValueKey('pgf-save')));
      await settle(tester);
      final nb = (await repo.allBooks()).firstWhere((x) => x.id == 'a');
      expect(nb.readPages, 70);
      // 保存富 toast（原型 bsSaveProgress：rp/pg 页（p%）· 本次 · 已入时间账本 L4）
      expect(
          find.textContaining('已记录《书A》70/100 页（70%）· 本次 0 分钟'),
          findsOneWidget);
      expect(find.textContaining('已入时间账本 L4'), findsOneWidget);
      await clearToasts(tester);
      // 累计时长芯片 → 计时明细：补记一次后次数 +1 且流水同增
      await tester.tap(find.byKey(const ValueKey('bd-min-chip')));
      await settle(tester);
      expect(find.text('《书A》· 计时明细'), findsOneWidget);
      final sessBefore = (await repo.allSessions()).length;
      await tester.ensureVisible(find.byKey(const ValueKey('sess-add')));
      await tester.tap(find.byKey(const ValueKey('sess-add')));
      await settle(tester);
      expect((await repo.allSessions()).length, sessBefore + 1);
      // 汇总行「N 次 · 共 X · 均 M 分钟/次」+ 补记 toast 逐字（原型 5779/5802）
      expect(find.textContaining('均 20 分钟/次'), findsOneWidget);
      expect(find.text('已补记一次 · 可直接改日期与时长'), findsOneWidget);
      final blocks = await db.query('time_blocks',
          where: 'cat_id = ?', whereArgs: [DbSchema.catReadingId]);
      expect(blocks, hasLength(1)); // 补记也入 L4（分类=阅读）
      expect(blocks.single['category'], '阅读');
      await tester.tap(find.byIcon(Icons.remove_circle_outline_rounded).first);
      await settle(tester);
      expect((await repo.allSessions()).length, sessBefore);
      expect(
          await db.query('time_blocks',
              where: 'cat_id = ?', whereArgs: [DbSchema.catReadingId]),
          isEmpty);
      await clearToasts(tester);
    });

    testWidgets('R-11 目录：粘贴导入实时解析 + 只读渲染 + 编辑态', (tester) async {
      await seed5();
      await tester.pumpWidget(routed(const ShelfPage()));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-item-a')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('toc-import')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('toe-text')),
          '第一部\n  甲\n  乙\n第二部\n  丙');
      await settle(tester);
      expect(find.text('2 个部分 · 3 节'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('toe-ok')));
      await settle(tester);
      expect(find.text('甲'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('toc-edit')));
      await settle(tester);
      expect(find.byKey(const ValueKey('toc-addpart')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('toc-edit'))); // 完成（自动 prune）
      await settle(tester);
      expect((await repo.tocOf('a')).where((n) => n.isPart).length, 2);
      await clearToasts(tester);
    });

    testWidgets('R-12 资料页：数据卡下钻 + 总结覆写', (tester) async {
      await seed5();
      await repo.addManualSession(
          bookId: 'a', day: DateTime.now(), minutes: 30, toPage: 10);
      await tester.pumpWidget(routed(const ShelfPage()));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-item-a')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('cover-a')));
      await settle(tester);
      expect(find.text('书籍资料'), findsWidgets);
      // 累计阅读卡 → 计时明细
      await tester.tap(find.byKey(const ValueKey('bi-min')));
      await settle(tester);
      expect(find.textContaining('计时明细'), findsOneWidget);
      await tester.tapAt(const Offset(12, 40)); // 点遮罩收起弹层
      await settle(tester);
      // 总结编辑落 sum_* 覆写（长列表卡先滚到手）
      await tester.ensureVisible(find.byKey(const ValueKey('sum-edit')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sum-edit')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('sum-q')), '金句一');
      await tester.ensureVisible(find.byKey(const ValueKey('sum-save')));
      await tester.tap(find.byKey(const ValueKey('sum-save')));
      await settle(tester);
      final nb = (await repo.allBooks()).firstWhere((x) => x.id == 'a');
      expect(nb.sumQuote, '金句一');
      await clearToasts(tester);
    });
  });

  group('批3-5 摘录与笔记库', () {
    int countByPrefix(WidgetTester tester, String prefix) =>
        find
            .byWidgetPredicate((w) =>
                w.key is ValueKey<String> &&
                (w.key as ValueKey<String>).value.startsWith(prefix))
            .evaluate()
            .length;

    Future<void> seedQuotes() async {
      await repo.addBook(bk('qa', '书甲', Book.kStateReading, rp: 40, last: ms(0)));
      await repo.addBook(bk('qb', '书乙', Book.kStateWant, last: ms(5)));
      for (var i = 0; i < 18; i++) {
        await repo.addQuote(BookQuote(
          bookId: i.isEven ? 'qa' : 'qb',
          kind: BookQuote.kKindMark,
          body: '摘录句子$i',
          tag: i % 3 == 0 ? '重点' : '共鸣',
          chapter: i % 2 == 0 ? '第一章' : null,
          starred: i < 3,
          createdAt: ms(i),
          updatedAt: ms(i),
        ));
      }
    }

    testWidgets('R-13 笔记库：18 条四视图计数一致 · 标星/搜索筛选', (tester) async {
      await seedQuotes();
      await tester.pumpWidget(page(const QuotesLibPage()));
      await settle(tester);
      await useSurface(tester);
      await settle(tester);
      await waitFinder(tester, find.byKey(const ValueKey('ql-view')));
      // 三统计：15 划线 · 3 感想？全部为划线 → 摘录 18 感想 0 覆盖 2
      expect(find.text('摘录'), findsOneWidget);
      expect(find.text('感想'), findsOneWidget);
      expect(find.text('覆盖'), findsOneWidget);
      expect(countByPrefix(tester, 'ql-q-'), 18, reason: '卡片视图');
      // 循环 行 → 按章节 → 图片墙，四视图计数一致
      await tester.tap(find.byKey(const ValueKey('ql-view')));
      await settle(tester);
      expect(countByPrefix(tester, 'qlr-'), 18, reason: '行视图');
      await tester.tap(find.byKey(const ValueKey('ql-view')));
      await settle(tester);
      expect(countByPrefix(tester, 'ql-q-'), 18, reason: '按章节分组内仍是卡');
      expect(countByPrefix(tester, 'qlg-'), 2, reason: '甲·第一章 / 乙·未分章');
      await tester.tap(find.byKey(const ValueKey('ql-view')));
      await settle(tester);
      expect(countByPrefix(tester, 'qli-'), 18, reason: '图片墙（无图回退全量）');
      // 标星范围筛选
      await tester.tap(find.byKey(const ValueKey('ql-view'))); // img → card
      await settle(tester);
      await tester.tap(find.text('标星'));
      await settle(tester);
      expect(countByPrefix(tester, 'ql-q-'), 3);
      // 搜索
      await tester.tap(find.text('全部书'));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('ql-kw')), '句子1');
      await settle(tester);
      expect(countByPrefix(tester, 'ql-q-'), 9); // 句子1 + 句子10..17
    });

    testWidgets('R-14 摘录表单：标签/查重提示/OCR 降级/→日记 →待办 落库',
        (tester) async {
      await repo.addBook(bk('qa', '书甲', Book.kStateReading, rp: 40, last: ms(0)));
      await tester.pumpWidget(page(const QuotesLibPage()));
      await settle(tester);
      await waitFinder(tester, find.byKey(const ValueKey('ql-add')));

      // 新建一条：原文 + 颜色分类 + 新标签
      await tester.tap(find.byKey(const ValueKey('ql-add')));
      await settle(tester);
      expect(find.textContaining('新增摘录 · 《书甲》'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('qef-body')), '标签链路句');
      await tester.ensureVisible(find.byKey(const ValueKey('qef-tag-重点')));
      await tester.tap(find.byKey(const ValueKey('qef-tag-重点')));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('qef-tag-new')));
      await tester.enterText(find.byKey(const ValueKey('qef-tag-new')), '方法论');
      await tester.ensureVisible(find.byKey(const ValueKey('qef-tag-add')));
      await tester.tap(find.byKey(const ValueKey('qef-tag-add')));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('qef-save')));
      await tester.tap(find.byKey(const ValueKey('qef-save')));
      await settle(tester);
      await clearToasts(tester);
      final saved = (await repo.allQuotes()).single;
      expect(saved.tag, '重点');
      expect(saved.tags, ['方法论']);
      expect((await repo.quoteTags()), contains('方法论'));

      // 重复内容：查重提示、不阻塞、不重复入账
      await tester.tap(find.byKey(const ValueKey('ql-add')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('qef-body')), '标签链路句');
      await tester.ensureVisible(find.byKey(const ValueKey('qef-save')));
      await tester.tap(find.byKey(const ValueKey('qef-save')));
      await settle(tester);
      expect(find.text('这条摘录已存在 · 未重复入账'), findsOneWidget);
      // 识图降级：仅提示，弹层不关不崩
      await tester.tap(find.byKey(const ValueKey('qef-ocr')));
      await settle(tester);
      expect(find.text('未接入识图引擎 · 请用「读剪贴板」或手动粘贴'), findsOneWidget);
      await clearToasts(tester);

      // 表单底部快捷分流：改内容后 → 插今日日记 / 生成待办
      await tester.enterText(find.byKey(const ValueKey('qef-body')), '分流句甲');
      await tester.ensureVisible(find.byKey(const ValueKey('qef-diary')));
      await tester.tap(find.byKey(const ValueKey('qef-diary')));
      await settle(tester);
      await clearToasts(tester);
      final j = await db.query('journal_entries');
      expect(j, hasLength(1));
      expect(j.single['content'], contains('分流句甲'));
      expect(await repo.allQuotes(), hasLength(2));

      await tester.tap(find.byKey(const ValueKey('ql-add')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('qef-body')), '分流句乙');
      await tester.ensureVisible(find.byKey(const ValueKey('qef-todo')));
      await tester.tap(find.byKey(const ValueKey('qef-todo')));
      await settle(tester);
      await clearToasts(tester);
      final t = await db.query('todos');
      expect(t, hasLength(1));
      expect(t.single['quadrant'], 2);
      expect(t.single['due_at'], isNull);
    });

    testWidgets('R-15 工作台复习卡（到期优先·翻面·档位推进）与摘录操作弹层',
        (tester) async {
      await repo.addBook(bk('qa', '书甲', Book.kStateReading, last: ms(0)));
      await repo.addQuote(BookQuote(
        bookId: 'qa',
        kind: BookQuote.kKindMark,
        body: '复习句',
        thought: '我的想法',
        createdAt: ms(2),
        updatedAt: ms(2),
      )); // next = created+1d = 昨天 → 今日到期
      await tester.pumpWidget(routed(const ReadWorkbench()));
      await waitFinder(tester, find.byKey(const ValueKey('read-review')));
      expect(find.text('共 1 条 · 今日到期 1 条'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('read-review')));
      await settle(tester);
      await waitFinder(tester, find.byKey(const ValueKey('rv-card')));
      expect(find.text('「复习句」'), findsNWidgets(2)); // 工作台最近摘录同款
      expect(find.text('1 / 1'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rv-card')));
      await settle(tester);
      expect(find.text('我的想法'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rv-know')));
      await settle(tester);
      await clearToasts(tester);
      // 记得 → 档位 0→1，队空后弹层收起
      final r = await repo.reviewOf((await repo.allQuotes()).single.id!);
      expect(r!.stage, 1);
      expect(r.nextAt! > DateTime.now().millisecondsSinceEpoch, isTrue);

      // 笔记库入口 + 摘录卡 → 操作弹层（收藏）
      await tester.tap(find.byKey(const ValueKey('read-nav-quotes')));
      await settle(tester);
      await waitFinder(tester, find.byKey(const ValueKey('ql-view')));
      await tester.tap(find.byKey(const ValueKey('ql-q-1')));
      await settle(tester);
      expect(find.text('划线操作'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('qo-star')));
      await settle(tester);
      await clearToasts(tester);
      expect((await repo.allQuotes()).single.starred, isTrue);
    });
  });

  group('批3-6 统计与书单', () {
    testWidgets('R-16 三本标已读 → 年度书单/读完宫格/目标卡三处同帧一致',
        (tester) async {
      await repo.addBook(bk('x1', '书一', Book.kStateReading));
      await repo.addBook(bk('x2', '书二', Book.kStateReading));
      await repo.addBook(bk('x3', '书三', Book.kStateReading));
      final y = DateTime.now().year;
      final list = await repo.addList(
          BookList(name: '$y 年度书单', createdAt: 0, updatedAt: 0),
          autoYear: y);
      for (final id in ['x1', 'x2', 'x3']) {
        await repo.setBookState(id, Book.kStateDone);
      }
      await tester.pumpWidget(routed(const BookListsPage()));
      await settle(tester);
      await waitFinder(
          tester, find.byKey(ValueKey('bl-item-${list.id}')));
      // 1) 书单卡成员数
      expect(find.text('3 本'), findsOneWidget);
      // 2) 详情页成员行（年度单不放「选书」与「移出」）
      await tester.tap(find.byKey(ValueKey('bl-item-${list.id}')));
      await settle(tester);
      expect(find.byKey(const ValueKey('blm-x1')), findsOneWidget);
      expect(find.byKey(const ValueKey('blm-x3')), findsOneWidget);
      expect(find.byKey(const ValueKey('bld-pick')), findsNothing);
      expect(find.byKey(const ValueKey('blm-rm-x1')), findsNothing);
      // 3) 统计页目标卡：今年读完 3 / 50
      final ctx = tester.element(find.byKey(const ValueKey('blm-x3')));
      GoRouter.of(ctx).go('/read/stat');
      await settle(tester);
      await waitFinder(tester, find.byKey(const ValueKey('rs-ctl')));
      await useSurface(tester);
      await settle(tester);
      // 3) 目标卡五路（读完宫格同帧 = 同一 tick）
      final goalRow = find.byKey(const ValueKey('rs-goal-今年读完'));
      await waitFinder(tester, goalRow);
      expect(goalRow, findsOneWidget);
      expect(find.text('3 / 50 本'), findsOneWidget);
    });

    testWidgets('R-17 统计页：热力 365 格 · 度量切换 · 购书支出卡联动流水',
        (tester) async {
      await repo.addBook(
          bk('f1', '付费书', Book.kStateReading, rp: 20).copyWith(fee: 59));
      final b = (await repo.allBooks()).single;
      await repo.addManualSession(
          day: DateTime.now(),
          bookId: b.id,
          minutes: 45,
          fromPage: 0,
          toPage: 20);
      await tester.pumpWidget(routed(const ReadStatPage()));
      await settle(tester);
      await waitFinder(tester, find.byKey(const ValueKey('rs-ctl')));
      await useSurface(tester);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('rs-ctl')));
      await settle(tester);
      expect(find.byKey(const ValueKey('rs-panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('rs-heat-364')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rs-met-day')));
      await settle(tester);
      expect(find.textContaining('是否读够'), findsWidgets);
      expect(find.byKey(const ValueKey('rs-fee')), findsOneWidget);
      expect(find.textContaining('¥59'), findsOneWidget);
      final rows = await db.query('finance_txns');
      expect(rows, hasLength(1));
    });

    testWidgets('R-18 手动建单 → 详情移出 → 书保留', (tester) async {
      await repo.addBook(bk('m1', '甲书', Book.kStateReading));
      await repo.addBook(bk('m2', '乙书', Book.kStateReading));
      await tester.pumpWidget(routed(const BookListsPage()));
      await settle(tester);
      await waitFinder(tester, find.byKey(const ValueKey('bl-new-manual')));
      await tester.tap(find.byKey(const ValueKey('bl-new-manual')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('blf-name')), '主题单');
      await tester.ensureVisible(find.byKey(const ValueKey('blf-pick-m1')));
      await tester.tap(find.byKey(const ValueKey('blf-pick-m1')));
      await tester.ensureVisible(find.byKey(const ValueKey('blf-pick-m2')));
      await tester.tap(find.byKey(const ValueKey('blf-pick-m2')));
      await tester.tap(find.text('保存'));
      await settle(tester);
      await clearToasts(tester);
      expect(find.text('主题单'), findsWidgets);
      expect(find.text('2 本'), findsOneWidget);
      // 进详情移出甲书：成员 1 · 书保留
      await tester.tap(find.text('主题单'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('blm-rm-m1')));
      await settle(tester);
      await clearToasts(tester);
      expect(find.byKey(const ValueKey('blm-m1')), findsNothing);
      expect(find.byKey(const ValueKey('blm-m2')), findsOneWidget);
      expect((await repo.allBooks()), hasLength(2));
    });
  });

  group('批3-8 导入 / 设置 / 资料', () {
    testWidgets('R-19 导入向导：示例解析 → 整批入账 → 二次全重复钮禁用 → 撤销本批',
        (tester) async {
      await tester.pumpWidget(routed(const ReadImportPage()));
      await settle(tester);
      await waitFinder(tester, find.byKey(const ValueKey('imp-ch-kindle')));
      await useSurface(tester);
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('imp-sample')));
      await tester.tap(find.byKey(const ValueKey('imp-sample')));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('imp-parse')));
      await tester.tap(find.byKey(const ValueKey('imp-parse')));
      await settle(tester);
      expect(find.textContaining('3 条 · 重复 0 条'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('imp-run')));
      await tester.tap(find.byKey(const ValueKey('imp-run')));
      await settle(tester);
      await clearToasts(tester);
      expect(await repo.quoteCount(), 3);
      expect((await repo.allBooks()).length, 3);
      // 二次解析：全部已存在 → 导入钮禁用
      await tester.ensureVisible(find.byKey(const ValueKey('imp-parse')));
      await tester.tap(find.byKey(const ValueKey('imp-parse')));
      await settle(tester);
      expect(find.textContaining('3 条 · 重复 3 条'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('imp-run')))
            .onPressed,
        isNull,
      );
      // 撤销本批：摘录退、书保留
      await tester.ensureVisible(find.byKey(const ValueKey('imp-undo')));
      await tester.tap(find.byKey(const ValueKey('imp-undo')));
      await settle(tester);
      await clearToasts(tester);
      expect(await repo.quoteCount(), 0);
      expect((await repo.allBooks()).length, 3);
    });

    testWidgets('R-20 设置：wallCols=5 书架跟随 · 长按菜单编辑器项生效',
        (tester) async {
      await repo.addBook(bk('w1', '墙书', Book.kStateReading, last: ms(0)));
      await tester.pumpWidget(routed(const ReadSettingsPage()));
      await settle(tester);
      await waitFinder(tester, find.byKey(const ValueKey('set-wallCols-5')));
      await tester.ensureVisible(find.byKey(const ValueKey('set-wallCols-5')));
      await tester.tap(find.byKey(const ValueKey('set-wallCols-5')));
      await settle(tester);
      await clearToasts(tester);
      expect(await repo.kv('read.wallCols'), '5');
      await tester.ensureVisible(find.byKey(const ValueKey('set-tab-1')));
      await tester.tap(find.byKey(const ValueKey('set-tab-1')));
      await settle(tester);
      await tester.ensureVisible(
          find.byKey(const ValueKey('set-longPress-edit')));
      await tester.tap(find.byKey(const ValueKey('set-longPress-edit')));
      await settle(tester);
      await waitFinder(
          tester, find.byKey(const ValueKey('lpset-add-标记读完')));
      await tester.tap(find.byKey(const ValueKey('lpset-add-标记读完')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('lpset-save')));
      await settle(tester);
      await clearToasts(tester);
      expect(await repo.kv('read.longPress'), contains('标记读完'));
      // 书架跟随：5 列封面墙 + 长按菜单出现「标记读完」并可点读完
      await tester.pumpWidget(routed(const ShelfPage()));
      await settle(tester);
      await useSurface(tester);
      await settle(tester);
      expect(find.byKey(const ValueKey('sh-grid-5-')), findsOneWidget);
      await tester.longPress(find.byKey(const ValueKey('sh-item-w1')));
      await settle(tester);
      expect(find.byKey(const ValueKey('lp-timer')), findsOneWidget);
      expect(find.byKey(const ValueKey('lp-done')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('lp-done')));
      await settle(tester);
      await clearToasts(tester);
      final w1 = (await repo.allBooks()).firstWhere((b) => b.id == 'w1');
      expect(w1.state, Book.kStateDone);
    });

    testWidgets('R-21 书架资料：新增来源 · 改名回写 books · 删除引用守卫',
        (tester) async {
      await repo.dictAdd(DictEntry.kSource, '得到');
      await repo.addBook(
          bk('m9', '甲书', Book.kStateReading, last: ms(0))
              .copyWith(source: '得到'));
      await tester.pumpWidget(routed(const BookMgrPage()));
      await settle(tester);
      final entries = await repo.dictOf('source');
      final de = entries.firstWhere((e) => e.name == '得到');
      await waitFinder(tester, find.byKey(ValueKey('bkm-row-${de.id}')));
      await tester.enterText(
          find.byKey(const ValueKey('bkm-add-inp-source')), '手贴');
      await tester.tap(find.byKey(const ValueKey('bkm-add-source')));
      await settle(tester);
      await clearToasts(tester);
      final afterAdd = await repo.dictOf('source');
      expect(afterAdd.map((e) => e.name), contains('手贴'));
      // 改名 → 事务回写 books.source
      await tester.tap(find.byKey(ValueKey('bkm-rename-${de.id}')));
      await settle(tester);
      await tester.enterText(
          find.byKey(ValueKey('bkm-rn-inp-${de.id}')), '得到APP');
      await tester.tap(find.byKey(ValueKey('bkm-rn-ok-${de.id}')));
      await settle(tester);
      await clearToasts(tester);
      final m9 = (await repo.allBooks()).firstWhere((b) => b.id == 'm9');
      expect(m9.source, '得到APP');
      // 删除守卫：仍有 1 本在用
      await tester.tap(find.byKey(ValueKey('bkm-del-${de.id}')));
      await settle(tester);
      expect(find.textContaining('还有 1 本在用'), findsOneWidget);
      await clearToasts(tester);
      final names = (await repo.dictOf('source')).map((e) => e.name);
      expect(names, contains('得到APP'));
    });
  });

  group('批C 保真 · 详情/档案/计时', () {
    testWidgets('R-22 相关推荐四分组：同作者/同系列/同标签/同出版社 组卡与行 meta',
        (tester) async {
      Book rb(String id, String t,
              {String a = '独作者',
              String? pub,
              String? series,
              List<String> tags = const []}) =>
          Book(
              id: id,
              title: t,
              author: a,
              publisher: pub,
              series: series,
              tags: tags,
              state: Book.kStateReading,
              pages: 100,
              createdAt: ms(30),
              updatedAt: ms(1));
      await repo.addBook(rb('r1', '主书',
          a: '张三', pub: '甲社', series: '宇宙系列', tags: const ['科幻']));
      await repo.addBook(rb('r2', '同作者书', a: '张三', pub: '乙社'));
      await repo.addBook(rb('r3', '同系列书', pub: '丙社', series: '宇宙系列'));
      await repo.addBook(rb('r4', '同标签书', pub: '丙社', tags: const ['科幻']));
      await repo.addBook(rb('r5', '同出版社书', pub: '甲社'));
      await repo.addBook(rb('r6', '无关书', pub: '丁社'));
      await repo.addQuote(BookQuote(
          bookId: 'r2',
          kind: BookQuote.kKindMark,
          body: '一句',
          createdAt: ms(1),
          updatedAt: ms(1)));
      await tester.pumpWidget(routed(BookDetailPage(bookId: 'r1', initialTab: 'r')));
      await settle(tester);
      await useSurface(tester);
      await settle(tester);
      // 组标题＝「同作者 {名} · N 本」样式；同标签/同出版社原型只到类名（4738）
      expect(find.text('同作者 张三 · 1 本'), findsOneWidget);
      expect(find.text('同系列 宇宙系列 · 1 本'), findsOneWidget);
      expect(find.text('同标签 · 1 本'), findsOneWidget);
      expect(find.text('同出版社 · 1 本'), findsOneWidget);
      expect(find.text('无关书'), findsNothing);
      // 组内行 meta＝作者 · 状态 · N 条摘录
      expect(find.text('张三 · 在读 · 1 条摘录'), findsOneWidget);
      // 相关 seg 计数＝四组命中共 4 本
      expect(find.text('相关 4'), findsOneWidget);
    });

    testWidgets('R-22b 相关推荐空态文案保留', (tester) async {
      await repo.addBook(Book(
          id: 'z1',
          title: '孤本',
          author: '独作者',
          publisher: '独社',
          state: Book.kStateWant,
          createdAt: ms(30),
          updatedAt: ms(1)));
      await tester.pumpWidget(routed(BookDetailPage(bookId: 'z1', initialTab: 'r')));
      await settle(tester);
      expect(find.text('还没有同作者 / 同系列 / 同标签的书'), findsOneWidget);
    });

    testWidgets('R-23 计时页 rtFoot：今日进度条 + 连续天数 + 三钮', (tester) async {
      await repo.addBook(bk('t', '计时书', Book.kStateReading, rp: 40));
      await repo.addManualSession(
          bookId: 't', day: DateTime.now(), minutes: 12, fromPage: 0, toPage: 40);
      await tester.pumpWidget(routed(const ReadTimerPage(bookId: 't')));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await useSurface(tester);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      // 副标题＝作者 · 状态 · p%（原型 renderReadTimer 5018）
      expect(find.text('作者计时书 · 在读 · 40%'), findsOneWidget);
      // rtFoot 今日/连续（原型 5023）
      expect(find.byKey(const ValueKey('rt-foot')), findsOneWidget);
      expect(find.text('今日'), findsOneWidget);
      expect(find.text('12 / 30 分钟'), findsOneWidget);
      expect(find.text('连续 1 天'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
          find.byKey(const ValueKey('rt-today-bar')));
      expect(bar.value, closeTo(12 / 30, 1e-9));
      // 三钮（原型 5025-5026）
      expect(find.text('记摘录'), findsOneWidget);
      expect(find.text('记进度'), findsOneWidget);
      expect(find.text('书籍详情'), findsOneWidget);
      // 书籍详情跳现有路由
      await tester.ensureVisible(find.byKey(const ValueKey('rtf-detail')));
      await tester.tap(find.byKey(const ValueKey('rtf-detail')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.byKey(const ValueKey('seg-c')), findsOneWidget);
    });

    testWidgets('R-23b 计时页收起：在跑时 rtClose toast 回胶囊继续', (tester) async {
      await repo.addBook(bk('t2', '胶囊书', Book.kStateReading));
      await tester.pumpWidget(routed(const ShelfPage()));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-item-t2')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('bd-timer')));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.tap(find.byKey(const ValueKey('rt-toggle')));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.tap(find.byKey(const ValueKey('rt-collapse')));
      await settle(tester);
      expect(
          find.textContaining('计时未结束 · 回到页面顶部胶囊继续显示'), findsOneWidget);
      await clearToasts(tester);
      // 页面已收起回详情页
      expect(find.byKey(const ValueKey('seg-c')), findsOneWidget);
    });

    testWidgets('R-24 进度口径四态：详情页 chip 统一（位置/有声/章节/页）',
        (tester) async {
      await repo.addBook(bk('p1', '位置书', Book.kStateReading, rp: 60)
          .copyWith(
              progressWay: Book.kWayPos,
              format: Book.kFormatEbook,
              totalLoc: 5000,
              readLoc: 1200));
      await repo.addBook(bk('p2', '有声书', Book.kStateReading)
          .copyWith(
              progressWay: Book.kWayMin, format: Book.kFormatAudio));
      await repo.addBook(
          bk('p3', '章节书', Book.kStateReading).copyWith(progressWay: Book.kWayChap));
      await repo.addBook(bk('p4', '纸书页', Book.kStateReading, rp: 30));
      // pos → 「x/tot 位置」
      await tester.pumpWidget(routed(BookDetailPage(bookId: 'p1')));
      await settle(tester);
      expect(find.text('1200 / 5000 位置'), findsWidgets);
      // min → 「p% · 有声」
      await tester.pumpWidget(routed(BookDetailPage(bookId: 'p2')));
      await settle(tester);
      expect(find.text('0% · 有声'), findsWidgets);
      // chap → 「按章节」
      await tester.pumpWidget(routed(BookDetailPage(bookId: 'p3')));
      await settle(tester);
      expect(find.text('按章节'), findsWidgets);
      // else → 「rp/pages 页」
      await tester.pumpWidget(routed(BookDetailPage(bookId: 'p4')));
      await settle(tester);
      expect(find.text('30 / 100 页'), findsWidgets);
    });

    testWidgets('R-25 档案页：四卡顺序与速度 · 星级 · 合并 chip 与购书 fee',
        (tester) async {
      await repo.addBook(bk('a', '书A', Book.kStateReading, rp: 50)
          .copyWith(rating: 4.5, fee: 39, format: Book.kFormatEbook,
              progressWay: Book.kWayPage));
      await repo.addManualSession(
          bookId: 'a', day: DateTime.now(), minutes: 30, toPage: 50);
      await tester.pumpWidget(routed(const BookInfoPage(bookId: 'a')));
      await settle(tester);
      await useSurface(tester);
      await settle(tester);
      // 四格顺序与内容＝[摘录/感想, 累计阅读, 计时次数, 分钟/页]（原型 5664-5668）
      expect(find.text('摘录/感想'), findsOneWidget);
      expect(find.text('累计阅读'), findsOneWidget);
      expect(find.text('计时次数'), findsOneWidget);
      expect(find.text('分钟/页'), findsOneWidget);
      // 第4卡速度口径：30 分钟 / 50 页 → 0.6
      expect(find.text('0.6'), findsOneWidget);
      // 页头星级 + 数值
      expect(find.text('4.5'), findsOneWidget);
      // 合并 chip「fmt · 进度口径」+ 购书 ¥fee
      expect(find.text('电子书 · 50 / 100 页'), findsOneWidget);
      expect(find.text('购书 ¥39'), findsOneWidget);
      // 进度行标题与进度方式名
      expect(find.text('阅读进度'), findsOneWidget);
      expect(find.text('页数'), findsWidgets);
    });

    testWidgets('R-26 目录节数标题 + 划线角标 + AI 补全占位 + 书摘分段 chips',
        (tester) async {
      await repo.addBook(bk('a', '书A', Book.kStateReading, rp: 50));
      await repo.addQuote(BookQuote(
          bookId: 'a',
          kind: BookQuote.kKindMark,
          body: '甲章句一',
          chapter: '甲',
          createdAt: ms(1),
          updatedAt: ms(1)));
      await repo.addQuote(BookQuote(
          bookId: 'a',
          kind: BookQuote.kKindMark,
          body: '甲章句二',
          chapter: '甲',
          createdAt: ms(1),
          updatedAt: ms(1)));
      await tester.pumpWidget(routed(const ShelfPage()));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-item-a')));
      await settle(tester);
      await useSurface(tester);
      await settle(tester);
      // 导入目录 → 3 节（原型「目录 · N 节」）
      await tester.tap(find.byKey(const ValueKey('toc-import')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('toe-text')),
          '第一部\n  甲\n  乙\n第二部\n  丙');
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('toe-ok')));
      await settle(tester);
      expect(find.text('目录 · 3 节'), findsOneWidget);
      // 节行右侧＝该书该章摘录数划线角标（甲 2 条）
      expect(find.text('2'), findsWidgets);
      // AI 补全＝B 类占位 toast
      await tester.ensureVisible(find.byKey(const ValueKey('toc-ai')));
      await tester.tap(find.byKey(const ValueKey('toc-ai')));
      await settle(tester);
      expect(find.text('AI 能力规划中（V1.x）'), findsOneWidget);
      await clearToasts(tester);
      // 书摘 tab 分段 chips：全部/划线/想法/星标（原型 bdQSegChips 5468）
      await tester.ensureVisible(find.byKey(const ValueKey('seg-q')));
      await tester.tap(find.byKey(const ValueKey('seg-q')));
      await settle(tester);
      expect(find.byKey(const ValueKey('qseg-all')), findsOneWidget);
      expect(find.text('划线 2'), findsOneWidget);
      expect(find.text('想法 0'), findsOneWidget);
      expect(find.text('星标 0'), findsOneWidget);
      // 点「星标」→ 空列表；再点回全部（划线卡带「」引号）
      await tester.ensureVisible(find.byKey(const ValueKey('qseg-star')));
      await tester.tap(find.byKey(const ValueKey('qseg-star')));
      await settle(tester);
      expect(find.text('「甲章句一」'), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('qseg-star')));
      await tester.tap(find.byKey(const ValueKey('qseg-star')));
      await settle(tester);
      expect(find.text('「甲章句一」'), findsOneWidget);
    });
  });
}

/// 摘录 kind 常量别名（避免与 domain import 冲突的最小断言面）。
class BookQuoteKind {
  static const mark = '划线';
}
