import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/presentation/import/local_import_page.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_page.dart';

import 'helpers.dart';

// R14-10 语义标签钉桩（2026-09-29 adb 走查缺陷：纯图标钮 uiautomator 读不到名，
// 既挡无障碍也挡自动化取证 walk_go）。口径：
//  ① 交互件的 Semantics label 必须能在语义树上按名命中（walk_go 按 label 找点）；
//  ② 底栏三图标原本靠子 Text 带名——此处复核曝光，不盲加；
//  ③ 带文案的自绘钮（_gradBtn/「打开阅读器」）确认合并名＝文案。

EpubPara _p(String t) => EpubPara(kind: EpubParaKind.text, text: t);

EpubDoc _doc() => EpubDoc(
      format: 'EPUB3',
      title: 'R1410 书',
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

  List<Override> baseOverrides() => [
    readRepositoryProvider.overrideWithValue(repo),
    sharedPreferencesProvider.overrideWithValue(prefs),
    epubDocLoaderProvider.overrideWithValue((_) async => doc),
  ];

  Future<void> step(WidgetTester t, {int ms = 200, int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await t.pump(Duration(milliseconds: ms));
    }
  }

  Future<Book> addBook(String id) => repo.addBook(
        Book(
          id: id,
          title: 'R1410 书',
          local: true,
          epub: const EpubRef(
            fmt: 'EPUB3',
            size: 10,
            path: 'mem',
          ),
          createdAt: 1,
          updatedAt: 1,
        ),
      );

  /// 进书并常驻顶/底栏（与 reader_r14_fix_test 同款手法）。
  Future<void> openReader(WidgetTester t, String id) async {
    await useSurface(t, const Size(420, 780));
    await addBook(id);
    await t.pumpWidget(
      ProviderScope(
        overrides: baseOverrides(),
        child: MaterialApp(home: ReaderPage(bookId: id)),
      ),
    );
    await step(t, times: 4);
    await t.tapAt(const Offset(210, 645));
    await step(t);
    expect(find.byKey(const ValueKey('br-bottom')), findsOneWidget);
  }

  /// 读某 key 交互件对外暴露的语义名（IconButton 取 Icon.semanticLabel/tooltip，
  /// GestureDetector 自绘钮优先 Icon 标签、回落子 Text 文案）。
  String semName(WidgetTester t, Key key) {
    final w = t.widget(find.byKey(key));
    if (w is IconButton) {
      final ic = w.icon;
      return ic is Icon
          ? (ic.semanticLabel ?? w.tooltip ?? '')
          : (w.tooltip ?? '');
    }
    if (w is GestureDetector) {
      // 用 byKey 定位（setState 重建后 GestureDetector.child 实例是旧对象，
      // find.byWidget 按 identical 比对会搜不到）。
      final of = find.byKey(key);
      final icons = find.descendant(
        of: of,
        matching: find.byWidgetPredicate((x) => x is Icon),
      );
      if (icons.evaluate().isNotEmpty) {
        return t.widget<Icon>(icons.first).semanticLabel ?? '';
      }
      final texts = find.descendant(
        of: of,
        matching: find.byWidgetPredicate((x) => x is Text),
      );
      return texts.evaluate().isNotEmpty
          ? t.widget<Text>(texts.first).data ?? ''
          : '';
    }
    return '';
  }

  testWidgets('R14-10 · 阅读器顶栏图标钮带语义名', (t) async {
    await openReader(t, 's1');
    for (final (k, lbl) in const [
      ('br-back', '返回'),
      ('brBtnSearch', '全书搜索'),
      ('brBtnMore', '更多操作'),
    ]) {
      // 反向对照：改回无 semanticLabel 的裸 Icon 即红。
      expect(semName(t, ValueKey(k)), lbl, reason: k);
    }
  });

  testWidgets('R14-10 · 底栏三图标复核（子 Text 即语义名·不盲加）', (t) async {
    await openReader(t, 's2');
    for (final (k, lbl) in const [
      ('brBtnToc', '目录'),
      ('brBtnProg', '进度'),
      ('brBtnLook', '外观'),
    ]) {
      // 复核结论（语义树 dump 实证）：合并节点带 [tap] 动作且 label 含文案，
      // 真机 walk_go 按 label 可命中——不补代码，仅钉桩防回归。
      expect(
        t.getSemantics(find.byKey(ValueKey(k))).label,
        contains(lbl),
        reason: k,
      );
    }
  });

  testWidgets('R14-10 · 导入页渐变钮复核（文案即语义名）', (t) async {
    await useSurface(t, const Size(420, 780));
    await t.pumpWidget(
      ProviderScope(
        overrides: baseOverrides(),
        child: const MaterialApp(home: LocalImportPage()),
      ),
    );
    await step(t, times: 3);
    expect(
      semName(t, const ValueKey('br-imp1-go')),
      '允许访问手机存储 · 选择文件',
    );
  });

  // 详情页顶栏/目录行编辑钮（bd-timer/bd-more/tc*）本轮未补：book_detail.dart 与
  // read_sheets_b2.dart 是体积棘轮登记文件（只许减不许增），纯图标钮加 label 参数
  // 必然 +2~+6 行；已列入交棒文档「待治理评审」项。
  test('R14-10 · 设置面板钮行上移/下移源码带 semanticLabel（防回归）', () {
    final src = File(
      'lib/features/read/presentation/read_settings_page.dart',
    ).readAsStringSync();
    expect(src, contains("semanticLabel: '上移 \$n'"));
    expect(src, contains("semanticLabel: '下移 \$n'"));
    // 反向对照：改回 const Icon(Icons.arrow_upward, size: 16) 裸写法即红。
    expect(src, isNot(contains('const Icon(Icons.arrow_upward, size: 16)')));
  });
}
