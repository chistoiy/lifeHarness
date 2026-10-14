import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/read/data/isbn_enrich.dart'
    show DoubanGuard, IsbnBookMeta;
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/domain/book_list.dart';
import 'package:lifeharness/features/read/presentation/biblio/biblio_search_page.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/read_settings_page.dart';
import 'package:lifeharness/features/read/presentation/shelf/read_lists_page.dart';
import 'package:lifeharness/features/read/presentation/shelf/shelf_page.dart';
import 'package:lifeharness/features/read/presentation/stats/read_log_page.dart';
import 'package:lifeharness/shared/widgets/load_error_state.dart'
    show LoadErrorBanner;
import 'package:lifeharness/shared/widgets/ui_kit.dart' show EmptyDashRow;

/// 阅读模块批2 · 状态层与反馈层常驻用例（F2-7 空态定式 / F2-8 失败态 /
/// F2-11 破坏性确认）。
///
/// 规格＝`docs/handoff/阅读模块-冻结版开发方案-20261013.md` §2.3，
/// 用例清单＝`docs/handoff/交棒话术-20261014-阅读模块批2交付链与状态层.md` §0.3。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ReadRepository repo;
  late SharedPreferences prefs;

  setUp(() async {
    DoubanGuard.reset();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = ReadRepository(db);
  });
  tearDown(() async {
    DoubanGuard.reset();
    await db.close();
  });

  Widget boot(Widget home) => ProviderScope(
        overrides: [
          readRepositoryProvider.overrideWithValue(repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(home: home),
      );

  final now = DateTime.now().millisecondsSinceEpoch;

  Book bk(String id, String t, String st) => Book(
        id: id,
        title: t,
        author: '作者$t',
        state: st,
        pages: 100,
        readPages: 0,
        lastReadAt: now,
        createdAt: now,
        updatedAt: now,
      );

  // ---- F2-7 空态定式（LH-L04）----

  testWidgets('F2-7 真·空书架：走 LH-L04 虚线补录行，不复用「筛选无果」文案', (tester) async {
    await useSurface(tester);
    await tester.pumpWidget(boot(const ShelfPage()));
    await settle5(tester);

    expect(find.byKey(const ValueKey('sh-empty-books')), findsOneWidget,
        reason: '真·空书架必须出 LH-L04 虚线补录行');
    expect(find.byType(EmptyDashRow), findsOneWidget);
    expect(find.text('还没有书 · 点这里添加第一本'), findsOneWidget);
    expect(find.textContaining('没有符合条件的书'), findsNothing,
        reason: '真·空书架不许复用「筛选无果」文案');
    expect(find.byKey(const ValueKey('sh-reset')), findsNothing,
        reason: '真·空书架没有「清空筛选」可点（无筛选在生效）');
  });

  testWidgets('F2-7 有书但筛选无果：保留「没有符合条件的书 · 清空筛选」出口', (tester) async {
    await useSurface(tester);
    await repo.addBook(bk('b1', '万历十五年', Book.kStateReading));
    await tester.pumpWidget(boot(const ShelfPage()));
    await settle5(tester);
    expect(find.byKey(const ValueKey('sh-empty-books')), findsNothing,
        reason: '有书不许出「还没有书」补录行');

    await tester.enterText(find.byKey(const ValueKey('sh-kw')), 'zzz不存在');
    await settle5(tester);
    expect(find.byKey(const ValueKey('sh-reset')), findsOneWidget,
        reason: '筛选无果走「清空筛选」出口');
    expect(find.byKey(const ValueKey('sh-empty-books')), findsNothing,
        reason: '筛选无果与真·空书架分出口（不许退化成补录行）');
  });

  testWidgets('F2-7 书单页空：走 LH-L04（还没有书单）', (tester) async {
    await useSurface(tester);
    await tester.pumpWidget(boot(const BookListsPage()));
    await settle5(tester);

    expect(find.byKey(const ValueKey('rl-lists-empty')), findsOneWidget);
    expect(find.byType(EmptyDashRow), findsOneWidget);
    expect(find.text('还没有书单'), findsOneWidget);
  });

  testWidgets('F2-7 计时记录页空：走 LH-L04（还没有计时记录）', (tester) async {
    await useSurface(tester);
    await repo.addBook(bk('b1', '万历十五年', Book.kStateReading));
    await tester.pumpWidget(boot(const ReadLogPage(bookId: 'b1')));
    await settle5(tester);

    expect(find.byKey(const ValueKey('rl-empty')), findsOneWidget);
    expect(find.byType(EmptyDashRow), findsOneWidget);
    expect(find.text('还没有计时记录 · 点右上 ＋ 补记一次'), findsOneWidget,
        reason: '真·空（全无记录）文案，与「当前范围没有记录」分家');
  });

  // ---- F2-8 失败态（LH-L15）----

  testWidgets('F2-8 书目源熔断：走 LH-L15 失败卡（标题＋原因＋重试），不再自绘一行灰字',
      (tester) async {
    DoubanGuard.trip(minutes: 30);
    await useSurface(tester);
    await tester.pumpWidget(boot(const BiblioSearchPage()));
    await settle5(tester);

    expect(find.byType(LoadErrorBanner), findsOneWidget);
    expect(find.byKey(const ValueKey('load-error-title')), findsOneWidget);
    expect(find.text('书目源暂时不可用'), findsOneWidget);
    expect(find.byKey(const ValueKey('load-error-reason')), findsOneWidget);
    expect(find.textContaining('本机数据未受影响'), findsOneWidget);
    expect(find.byKey(const ValueKey('load-error-retry')), findsOneWidget);
    expect(find.byKey(const ValueKey('load-error-detail')), findsOneWidget);
    expect(find.text('豆瓣访问受限 · 稍后再试'), findsNothing,
        reason: '熔断文案已升格进失败卡原因行，不许再自绘一行灰字');
  });

  // ---- F2-11 破坏性动作确认（LH-S31）----

  testWidgets('F2-11 清缓存先弹 LH-S31：点「取消」不执行', (tester) async {
    await repo.doubanCachePut(
      '9787108009821',
      const IsbnBookMeta(title: '万历十五年', author: '黄仁宇'),
    );
    await tester.pumpWidget(boot(const ReadSettingsPage(initialSec: 4)));
    await settle5(tester);
    expect(await repo.doubanCacheCount(), 1);

    await tester.tap(find.byKey(const ValueKey('set-dbCache-clear')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('d-confirm-ok')), findsOneWidget,
        reason: '清缓存必须先过统一二次确认');
    expect(find.byKey(const ValueKey('d-confirm-cancel')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('d-confirm-cancel')));
    await settle5(tester);
    expect(await repo.doubanCacheCount(), 1, reason: '点取消＝不执行破坏性动作');
  });

  testWidgets('F2-11 删书单先弹 LH-S31：点「取消」不执行', (tester) async {
    await useSurface(tester);
    final l = await repo.addList(
      BookList(name: '2026 想读', createdAt: now, updatedAt: now),
    );
    await tester.pumpWidget(boot(const BookListsPage()));
    await settle5(tester);
    expect(find.byKey(ValueKey('bl-del-${l.id}')), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('bl-del-${l.id}')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('d-confirm-ok')), findsOneWidget,
        reason: '删书单必须先过统一二次确认');

    await tester.tap(find.byKey(const ValueKey('d-confirm-cancel')));
    await settle5(tester);
    expect((await repo.allLists()).length, 1, reason: '点取消＝书单还在');
  });
}
