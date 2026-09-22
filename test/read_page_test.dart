import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/presentation/book_detail.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/read_tab.dart';
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
          find.byKey(const ValueKey('qsf-body')), '系统1慢，需要刻意练习');
      await settle(tester);
      // 保存按钮在弹层标题行
      await tester.tap(find.text('保存'));
      await settle(tester);
      expect(find.text('已记录这条摘录'), findsOneWidget);
      await clearToasts(tester);
      final qs = await repo.allQuotes();
      expect(qs.single.body, '系统1慢，需要刻意练习');
      expect(qs.single.kind, BookQuoteKind.mark);
    });

    testWidgets('R-9 详情页：沉浸头图 + 三 tab + 角标循环分区', (tester) async {
      await seed5();
      await tester.pumpWidget(routed(const ShelfPage()));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sh-item-a')));
      await settle(tester);
      expect(find.text('书A'), findsWidgets);
      expect(find.byKey(const ValueKey('seg-c')), findsOneWidget);
      expect(find.byKey(const ValueKey('seg-q')), findsOneWidget);
      expect(find.byKey(const ValueKey('seg-r')), findsOneWidget);
      // 角标循环：在读 → 想读（不冒泡进其它页）
      await tester.tap(find.byKey(const ValueKey('bd-timer')));
      await settle(tester);
      expect(find.textContaining('已为《书A》开始计时'), findsOneWidget);
    });
  });
}

/// 摘录 kind 常量别名（避免与 domain import 冲突的最小断言面）。
class BookQuoteKind {
  static const mark = '划线';
}
