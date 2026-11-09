import 'dart:convert' show base64Decode;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_page.dart';

import 'helpers.dart';

// 真机反馈 R14 修复钉桩（2026-09-29 adb 走查）：
//  ① R14-3 内部定位串（epub/2/x/y）不再外露在正文底栏与进度弹层；
//  ② R14-5 本书操作弹层四个钮改走 GoRouter 通道（原 Navigator.pushNamed 在
//     「页面挂在 ShellRoute 分支 Navigator 里」的真实拓扑下必然断言失败）。
//     日志页实证：NavigatorState._routeNamed assertion
//     「no route on initial route '/read/book/1'」。

final _png = Uint8List.fromList(base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
));

EpubPara _p(String t) => EpubPara(kind: EpubParaKind.text, text: t);

EpubDoc _doc() => EpubDoc(
      format: 'EPUB3',
      title: 'R14 书',
      author: '甲',
      toc: const [],
      chapters: [
        EpubChapter(
          href: 'c1',
          title: '第一章',
          paras: List.generate(18, (i) => _p('第$i段正文素材，用于把这一页填满。')),
        ),
      ],
      imageCount: 1,
      totalChars: 18 * 18,
      images: const {},
    );

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ReadRepository repo;
  late SharedPreferences prefs;
  final doc = _doc();

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

  Future<void> addBook(String id) => repo.addBook(Book(
        id: id,
        title: 'R14 书',
        local: true,
        epub: const EpubRef(fmt: 'EPUB3', size: 10, path: 'mem'),
        createdAt: 1,
        updatedAt: 1,
      ));

  /// 复刻生产拓扑：阅读器在 ShellRoute 分支 Navigator 内，
  /// 详情/统计路由挂在**根** Navigator 上（与 app_router 的 *_routes 平级挂载一致）。
  Widget wrap(String bookId) {
    final router = GoRouter(
      initialLocation: '/read',
      routes: [
        ShellRoute(
          builder: (_, __, child) => Scaffold(body: child),
          routes: [
            GoRoute(
              path: '/read',
              builder: (_, _) => ReaderPage(bookId: bookId),
            ),
          ],
        ),
        GoRoute(
          path: '/read/book/:id',
          builder: (_, st) => const Text('STUB-DETAIL'),
        ),
        GoRoute(
          path: '/read/stat',
          builder: (_, _) => const Text('STUB-STAT'),
        ),
        GoRoute(
          path: '/read/log/:id',
          builder: (_, _) => const Text('STUB-LOG'),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        readRepositoryProvider.overrideWithValue(repo),
        sharedPreferencesProvider.overrideWithValue(prefs),
        epubDocLoaderProvider.overrideWithValue((_) async => doc),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> step(WidgetTester t, {int ms = 200, int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await t.pump(Duration(milliseconds: ms));
    }
  }

  /// 进书并常驻顶/底栏（中区空白点按）。
  Future<void> openReader(WidgetTester t, String id) async {
    await useSurface(t, const Size(420, 780));
    await addBook(id);
    await t.pumpWidget(wrap(id));
    await step(t, times: 4);
    await t.tapAt(const Offset(210, 645));
    await step(t);
    expect(find.byKey(const ValueKey('br-bottom')), findsOneWidget);
  }

  testWidgets('R14-3 · 正文底栏不再显示内部定位串', (t) async {
    await openReader(t, 'r1');
    expect(find.textContaining('epub/2/'), findsNothing);
    final lbl = t.widget<Text>(find.byKey(const ValueKey('brPgLbl'))).data!;
    expect(lbl, contains('页'));
  });

  testWidgets('R14-3 · 进度弹层不再显示内部定位串', (t) async {
    await openReader(t, 'r2');
    await t.tap(find.byKey(const ValueKey('brBtnProg')));
    await step(t, times: 3);
    expect(find.byKey(const ValueKey('sheetBrProg')), findsOneWidget);
    expect(find.textContaining('epub/2/'), findsNothing);
    expect(find.byKey(const ValueKey('brProgCfi')), findsNothing);
    // 收场：点遮罩关闭，避免残留弹层吞掉后续命中。
    await t.tapAt(const Offset(210, 60));
    await step(t, times: 4);
  });

  testWidgets('R14-5 · 进度弹层「阅读明细」走 GoRouter 通道', (t) async {
    await openReader(t, 'r5');
    await t.tap(find.byKey(const ValueKey('brBtnProg')));
    await step(t, times: 3);
    await t.tap(find.text('阅读明细'));
    await step(t, times: 6);
    expect(find.text('STUB-LOG'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('R14-5 · 本书操作弹层「详情」走 GoRouter 通道', (t) async {
    await openReader(t, 'r3');
    await t.tap(find.byKey(const ValueKey('brBtnMore')));
    await step(t, times: 4);
    expect(find.text('本书操作'), findsOneWidget);
    await t.tap(find.text('详情'));
    await step(t, times: 6);
    expect(find.text('STUB-DETAIL'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('R14-5 · 本书操作弹层「统计」走 GoRouter 通道', (t) async {
    await openReader(t, 'r4');
    await t.tap(find.byKey(const ValueKey('brBtnMore')));
    await step(t, times: 4);
    await t.tap(find.text('统计'));
    await step(t, times: 6);
    expect(find.text('STUB-STAT'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
