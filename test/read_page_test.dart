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
          path: '/read/mgr', builder: (_, _) => const BookMgrPage()),
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

    testWidgets('R-6 管理批量移已读：计数·目标卡·时间线同帧同步', (tester) async {
      await seed5();
      await tester.pumpWidget(page(const ShelfPage()));
      await settle(tester);
      await useSurface(tester);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-manage')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-item-a')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-item-b')));
      await settle(tester);
      expect(find.text('已选 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bat-已读')));
      await settle(tester);
      await clearToasts(tester);
      await waitFinder(tester, find.textContaining('3 / 50 本'));

      // 计数：已读 3 · 在读 0；目标卡 3/50
      expect(find.text('在读 0'), findsOneWidget);
      expect(find.text('已读 3'), findsOneWidget);
      // 数据层：批量移已读补满进度与 ended_at
      final a = (await repo.allBooks()).firstWhere((b) => b.id == 'a');
      expect(a.readPages, a.pages);
      expect(a.endedAt, isNotNull);
      // 时间线视图同步出现「读完《书A》」
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const ValueKey('sh-view')));
        await settle(tester);
      }
      await waitFinder(tester, find.text('读完《书A》'));
      expect(find.text('读完《书B》'), findsOneWidget);
    });

    testWidgets('R-7 ⇅ 面板：切排序维度行出现并可回默认', (tester) async {
      await seed5();
      await tester.pumpWidget(page(const ShelfPage()));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-panel')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('panel-dim-author')));
      await settle(tester);
      // 维度值行出现（作者各异 → 5 组）
      expect(find.text('回到默认'), findsOneWidget);
      expect(find.textContaining('· 1 本'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('sh-dim-reset')));
      await settle(tester);
      expect(find.text('回到默认'), findsNothing);
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
      // 页内开始 → 计时中 → 页内结束
      await tester.tap(find.byKey(const ValueKey('rt-toggle')));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.text('计时中'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rt-toggle')));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
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
      // 进度芯片 → 记进度弹层（按页方式改到 70）
      await tester.tap(find.byKey(const ValueKey('bd-pct-chip')));
      await settle(tester);
      expect(find.textContaining('记进度 · 《书A》'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('pgf-value')), '70');
      await settle(tester);
      await tester.tap(find.text('保存'));
      await settle(tester);
      final nb = (await repo.allBooks()).firstWhere((x) => x.id == 'a');
      expect(nb.readPages, 70);
      await clearToasts(tester);
      // 累计时长芯片 → 计时明细：补记一次后次数 +1 且流水同增
      await tester.tap(find.byKey(const ValueKey('bd-min-chip')));
      await settle(tester);
      expect(find.textContaining('计时明细'), findsOneWidget);
      final sessBefore = (await repo.allSessions()).length;
      await tester.tap(find.byKey(const ValueKey('sess-add')));
      await settle(tester);
      expect((await repo.allSessions()).length, sessBefore + 1);
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
}

/// 摘录 kind 常量别名（避免与 domain import 冲突的最小断言面）。
class BookQuoteKind {
  static const mark = '划线';
}
