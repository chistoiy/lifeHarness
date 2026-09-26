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
import 'package:lifeharness/features/read/domain/book_dict.dart';
import 'package:lifeharness/features/read/presentation/book_info_page.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';

/// 真机反馈（2026-09-26）：「添加图书时能填 ISBN，添加后再编辑就没办法改了」。
/// 旧弹层实现里 `bkf-isbn` 只挂在「添加新书」分支——该缺陷已由 V1.43.2 修复；
/// V1.44 起编辑入口（bi-edit）改道整页表单 BookFormPage（bf-* 键），
/// 本测随迁钉住编辑态「改码→重查→落库」闭环不回归。
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
    expect(fieldText(tester, 'bf-isbn'), '9787108009821');

    await tester.enterText(
      find.byKey(const ValueKey('bf-isbn')),
      '9787108009822',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('bf-save')));
    await tester.tap(find.byKey(const ValueKey('bf-save')));
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
            final u = uri.toString();
            // 书名兜底也走同一个注入通道：这里回空数组，让它维持「未命中」档。
            if (u.contains('subject_suggest')) return '[]';
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
      find.byKey(const ValueKey('bf-isbn')),
      '9780000000000',
    );
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 900));
    // 详情页 1 次 + suggest 空后的搜索页兜底 1 次（防封批：suggest 恒空 IP
    // 会再打 search.douban.com，见 isbn_enrich 兜底链）。
    expect(hits, 2, reason: '编辑态也要真的联网补全，而不是只存码');
    expect(find.text('豆瓣未收录 · 留空待补'), findsOneWidget);

    // 「ISBN 取图」以输入框现值为准（改完即可重取，不必先保存）。
    await tester.ensureVisible(find.byKey(const ValueKey('bf-cov-isbn')));
    await tester.tap(find.byKey(const ValueKey('bf-cov-isbn')));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 900));
    expect(hits, 4);
    expect(find.text('未取到封面'), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('ISBN 那条路断了：按书名在豆瓣反查补全，状态写清数据来源', (tester) async {
    await repo.setKv('read.isbnFill', '抓豆瓣数据');
    await seedBook();
    final desktop = File(
      'test/fixtures/douban_isbn_desktop.html',
    ).readAsStringSync();
    await tester.pumpWidget(
      boot([
        isbnPageFetcherProvider.overrideWith((ref) => (uri) async {
          final u = uri.toString();
          // /isbn/ 整页断连（真机日志：Connection closed while receiving data）。
          if (u.contains('/isbn/')) return null;
          if (u.contains('subject_suggest')) {
            return '[{"title":"万历十五年","author_name":"[美] 黄仁宇",'
                '"year":"1997","id":"1041482","pic":"https://img/x/s1800355.jpg"}]';
          }
          if (u.contains('/subject/1041482/')) return desktop;
          return null;
        }),
        // 封面字节回 null：saveCover 会在取目录前就短路返回（widget 测试里
        // path_provider 通道不应答，真等下去就是挂死）。
        isbnBytesFetcherProvider.overrideWith((ref) => (_) async => null),
      ]),
    );
    await settle(tester);
    await useSurface(tester);
    await settle(tester);
    await openEdit(tester);

    // 换一个与机上现值不同的码：enterText 写入同值不会触发 onChanged。
    await tester.enterText(
      find.byKey(const ValueKey('bf-isbn')),
      '9787108009820',
    );
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('按书名匹配 · 已填充'), findsOneWidget,
        reason: '不是 ISBN 命中就别写成「已命中」，口径要能分辨');
    // 出版社/出版日期原本空着 → 补全；书名（检索词本身）不覆盖。
    expect(fieldText(tester, 'bf-publisher'), '生活·读书·新知三联书店');
    expect(fieldText(tester, 'bf-pg'), '320');
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
    await tester.ensureVisible(find.byKey(const ValueKey('bf-publisher')));
    expect(find.byKey(const ValueKey('bf-isbn')), findsOneWidget);
    // 扫码入口两态都有（2026-09-26 拍板：改码多是对着书脊重扫）。
    expect(find.byKey(const ValueKey('bf-isbn-scan')), findsOneWidget);
    expect(find.byKey(const ValueKey('bf-publisher')), findsOneWidget);
    expect(find.byKey(const ValueKey('bf-pg')), findsOneWidget);
    // V1.44 整页新增的三行（旧弹层没有）：字数/装帧/购入日期。
    expect(find.byKey(const ValueKey('bf-wc')), findsOneWidget);
    expect(find.byKey(const ValueKey('bf-binding')), findsOneWidget);
    expect(find.byKey(const ValueKey('bf-feeDate')), findsOneWidget);
    expect(find.byKey(const ValueKey('bf-save')), findsOneWidget);
  });
}
