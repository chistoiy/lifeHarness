import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/domain/book_list.dart';
import 'package:lifeharness/features/read/presentation/shelf/read_lists_page.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/read_tab.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 真机验收轮5 bug 复现：记录·阅读 顶卡第二钮「书单」(read-nav-list)
/// 进入 /read/lists 一片空白。
void main() {
  sqfliteFfiInit();
  late ReadRepository repo;

  setUp(() async {
    databaseFactory = databaseFactoryFfiNoIsolate;
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
    );
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = ReadRepository(db);
  });
  tearDown(() async => repo.db.close());

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 120));
  }

  Future<void> waitFinder(WidgetTester tester, Finder f,
      {int times = 15}) async {
    for (var i = 0; i < times; i++) {
      if (f.evaluate().isNotEmpty) return;
      await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }
    expect(f, findsOneWidget);
  }

  testWidgets('书单入口：点顶卡 read-nav-list → 书单页有内容不空白',
      (tester) async {
    await repo.addBook(const Book(
        id: 'z1',
        title: '书A',
        author: '甲',
        state: Book.kStateReading,
        pages: 100,
        readPages: 10,
        createdAt: 1,
        updatedAt: 1));
    // 真机场景：已有手动书单（含成员）+ 年度自动书单。
    await repo.addList(
        const BookList(name: '主题单', createdAt: 0, updatedAt: 0),
        bookIds: ['z1']);
    await repo.addList(
        const BookList(name: '2026 年度书单', createdAt: 0, updatedAt: 0),
        autoYear: 2026);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const ReadWorkbench()),
      GoRoute(
          path: '/read/lists', builder: (_, _) => const BookListsPage()),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [readRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(
          routerConfig: router,
          builder: (_, child) => Scaffold(body: child)),
    ));
    await settle(tester);

    await waitFinder(tester, find.byKey(const ValueKey('read-nav-list')));
    await tester.tap(find.byKey(const ValueKey('read-nav-list')));
    await settle(tester);
    await waitFinder(tester, find.text('手动创建书单'));
    // ignore: avoid_print
    print('DBG-exc ${tester.takeException()}');
    expect(find.text('生成年度书单'), findsOneWidget);
  });
}
