import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/read/data/isbn_enrich.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/presentation/book_info_page.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';

/// 豆瓣防封批（2026-09-26 拍板）· 表单缓存命中询问链：
/// 首次联网命中→自动落缓存；二次输入同码→「本地已有缓存」+「用缓存 /
/// 仍联网查询」；用缓存一发网络都不发；取图直接吃已落盘封面。
/// V1.44 起 bi-edit 改道整页表单 BookFormPage（键 bf-*，无 GoRouter 壳时
/// openBookForm 退 Navigator push），本测随迁只换键名不改语义。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ReadRepository repo;

  setUp(() async {
    DoubanGuard.reset();
    DoubanCookie.set(null);
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = ReadRepository(db);
  });
  tearDown(() => db.close());

  Widget boot(List<Override> extra) => ProviderScope(
    overrides: [readRepositoryProvider.overrideWithValue(repo), ...extra],
    child: const MaterialApp(home: BookInfoPage(bookId: 'x')),
  );

  Future<void> seedBook() => repo.addBook(
    Book(
      id: 'x',
      title: '万历十五年',
      author: '黄仁宇',
      state: Book.kStateReading,
      pages: 320,
      readPages: 40,
      isbn: '9787108009821',
      createdAt: 1,
      updatedAt: 1,
    ),
  );

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 120));
  }

  Future<void> waitFinder(WidgetTester tester, Finder f,
      {int times = 15}) async {
    for (var i = 0; i < times; i++) {
      if (f.evaluate().isNotEmpty) return;
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
    }
    throw StateError('等待超时：目标元素始终未出现（times=$times）');
  }

  Future<void> openEdit(WidgetTester tester) async {
    await waitFinder(tester, find.byKey(const ValueKey('bi-edit')));
    await tester.tap(find.byKey(const ValueKey('bi-edit')));
    await settle(tester);
    expect(find.text('编辑书籍信息'), findsOneWidget);
  }

  String status(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('bf-isbn-status')))
      .data!;

  /// 补全链里夹着真 sqflite 往返（缓存行读写）：假异步下必须混入真实
  /// 事件循环才能推进（waitFinder 同法），100ms 一步把 520ms 防抖也跨过。
  Future<void> pumpLookup(WidgetTester tester) async {
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    }
  }

  Future<void> retypeIsbn(WidgetTester tester, String v) async {
    await tester.enterText(find.byKey(const ValueKey('bf-isbn')), '');
    await pumpLookup(tester);
    await tester.enterText(find.byKey(const ValueKey('bf-isbn')), v);
    await pumpLookup(tester);
  }

  /// 「用缓存」钮先 await doubanCacheRow（真 sqflite 往返）再回填：
  /// 假异步下单步 pump 泵不动，runAsync 轮询到状态行到位（waitFinder 同法）。
  Future<void> waitStatus(WidgetTester tester, String text) async {
    for (var i = 0; i < 15; i++) {
      if (find.text(text).evaluate().isNotEmpty) return;
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
    }
      expect(find.text(text), findsOneWidget);
  }

  String desktop() =>
      File('test/fixtures/douban_isbn_desktop.html').readAsStringSync();

  testWidgets('首次联网命中自动落缓存；二次同码先问；用缓存不再发请求', (tester) async {
    await repo.setKv('read.isbnFill', '抓豆瓣数据');
    await seedBook();
    var net = 0;
    await tester.pumpWidget(boot([
      isbnPageFetcherProvider.overrideWith((ref) => (uri) async {
        net++;
        return uri.toString().contains('subject_suggest') ? '[]' : desktop();
      }),
      // 封面字节也走假通道：widget 测试禁真实 I/O（固定返回取不到图）。
      isbnBytesFetcherProvider.overrideWith((ref) => (uri) async => null),
    ]));
    await settle(tester);
    await openEdit(tester);
    // 整页表单询问行（bf-cache-*）默认视口装不下 → 拉高视口。
    await useSurface(tester);
    await settle(tester);

    await retypeIsbn(tester, '9787108009821');
    expect(status(tester), contains('已命中'));
    expect(net, 1);
    expect(await repo.doubanCacheCount(), 1, reason: '联网命中必须落缓存');

    // 同码再查：不发请求，先问「用缓存 / 仍联网」。
    await retypeIsbn(tester, '9787108009821');
    expect(status(tester), '本地已有缓存');
    expect(net, 1, reason: '命中缓存不得先发网络请求');
    expect(find.byKey(const ValueKey('bf-cache-ask')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('bf-cache-use')));
    // 用缓存＝零网络，但 doubanCacheRow 是真 sqflite 往返 → runAsync 轮询。
    await waitStatus(tester, '缓存命中 · 已填充');
    expect(status(tester), '缓存命中 · 已填充');
    expect(net, 1, reason: '用缓存这条路径零网络');
    expect(find.byKey(const ValueKey('bf-cache-ask')), findsNothing);

    // 「仍联网查询」：显式重查并刷新缓存行。
    await retypeIsbn(tester, '9787108009821');
    expect(find.byKey(const ValueKey('bf-cache-ask')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bf-cache-net')));
    await pumpLookup(tester);
    expect(status(tester), contains('已命中'));
    expect(net, 2);

    // 手动清理后不再询问。
    await repo.doubanCacheClear();
    expect(await repo.doubanCacheCount(), 0);
    await retypeIsbn(tester, '9787108009821');
    expect(find.byKey(const ValueKey('bf-cache-ask')), findsNothing);
    expect(net, 3);
    await clearToasts(tester);
  });

  testWidgets('熔断生效期表单文案：豆瓣访问受限 · 稍后再试', (tester) async {
    await repo.setKv('read.isbnFill', '抓豆瓣数据');
    await seedBook();
    await tester.pumpWidget(boot([
      isbnPageFetcherProvider.overrideWith((ref) => (uri) async =>
          '<html><head><title>禁止访问</title></head></html>'),
      isbnBytesFetcherProvider.overrideWith((ref) => (uri) async => null),
    ]));
    await settle(tester);
    await openEdit(tester);
    await retypeIsbn(tester, '9787108009821');
    expect(status(tester), '豆瓣访问受限 · 稍后再试');
    // 受限不留缓存行。
    expect(await repo.doubanCacheCount(), 0);
    await clearToasts(tester);
  });
}
