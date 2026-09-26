import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/read/data/isbn_enrich.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/domain/book_dict.dart';
import 'package:lifeharness/features/read/presentation/book_info_page.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';

/// 真机反馈（2026-09-26）：「添加图书时能填 ISBN，添加后再编辑就没办法改了」。
/// 旧实现里 `bkf-isbn` 只挂在「添加新书」分支，编辑分支没有这一行，
/// 于是编辑态既改不了码、也再触发不了豆瓣补全。本测钉住编辑态的完整闭环。
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

  /// 档案页首帧要等 sqflite 真往返：假异步下用 runAsync 轮询到元素出现。
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

  String fieldText(WidgetTester tester, String key) => tester
      .widget<TextField>(find.byKey(ValueKey(key)))
      .controller!
      .text;

  testWidgets('编辑态有 ISBN 行：回填现值，改后保存落库', (tester) async {
    await seedBook();
    await tester.pumpWidget(boot(const []));
    await settle(tester);
    await useSurface(tester);
    await settle(tester);
    await openEdit(tester);

    // 现值回填（旧实现：整行不存在）。
    expect(fieldText(tester, 'bkf-isbn'), '9787108009821');

    await tester.enterText(
      find.byKey(const ValueKey('bkf-isbn')),
      '9787108009822',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('bkf-save')));
    await tester.tap(find.byKey(const ValueKey('bkf-save')));
    await settle(tester);

    final b = (await repo.allBooks()).single;
    expect(b.isbn, '9787108009822', reason: '编辑态改码必须写库（旧值只能靠新建）');
    await clearToasts(tester);
  });

  testWidgets('编辑态输入 ISBN 也走豆瓣补全：未命中按成因分档提示', (tester) async {
    await repo.setKv('read.isbnFill', '抓豆瓣数据');
    await seedBook();
    var hits = 0;
    await tester.pumpWidget(
      boot([
        isbnPageFetcherProvider.overrideWith(
          (ref) => (uri) async {
            hits++;
            // 取到页面但没有书目节点＝豆瓣未收录（与「网络不通」不是一档）。
            return '<html><title>找不到</title></html>';
          },
        ),
      ]),
    );
    await settle(tester);
    await useSurface(tester);
    await settle(tester);
    await openEdit(tester);

    await tester.enterText(
      find.byKey(const ValueKey('bkf-isbn')),
      '9780000000000',
    );
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 900));
    expect(hits, 1, reason: '编辑态也要真的联网补全，而不是只存码');
    expect(find.text('豆瓣未收录 · 留空待补'), findsOneWidget);

    // 「ISBN 取图」以输入框现值为准（改完即可重取，不必先保存）。
    await tester.ensureVisible(find.byKey(const ValueKey('bkf-cov-isbn')));
    await tester.tap(find.byKey(const ValueKey('bkf-cov-isbn')));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 900));
    expect(hits, 2);
    expect(find.text('未取到封面'), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('编辑态字典联动不回归：来源/分组/出版社/标签仍在', (tester) async {
    await repo.dictAdd(DictEntry.kSource, '自购');
    await seedBook();
    await tester.pumpWidget(boot(const []));
    await settle(tester);
    await useSurface(tester);
    await settle(tester);
    await openEdit(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('bkf-publisher')));
    expect(find.byKey(const ValueKey('bkf-isbn')), findsOneWidget);
    // 扫码入口两态都有（2026-09-26 拍板：改码多是对着书脊重扫）。
    expect(find.byKey(const ValueKey('bkf-scan')), findsOneWidget);
    expect(find.byKey(const ValueKey('bkf-publisher')), findsOneWidget);
    expect(find.byKey(const ValueKey('bkf-pages')), findsOneWidget);
    expect(find.byKey(const ValueKey('bkf-pct')), findsOneWidget);
    expect(find.byKey(const ValueKey('bkf-save')), findsOneWidget);
  });
}
