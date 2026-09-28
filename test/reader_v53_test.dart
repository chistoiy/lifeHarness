import 'dart:convert' show base64Decode, jsonDecode;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/read/data/epub_cache.dart';
import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/reader_page.dart';

// V1.53 轮3 · 阅读器底栏五图标 + 进度/亮度/字号三面板 + 长按选区（Flutter 侧）。
// 独立文件防 isolate 污染；FakeAsync 下不注入 docsPath（真文件 IO 会挂）。

final _png = Uint8List.fromList(base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
));

EpubPara _p(String t) => EpubPara(kind: EpubParaKind.text, text: t);

const _lorem = '这是分页实测正文素材，默认字号下约两到三行。';

EpubDoc _bigDoc() => EpubDoc(
  format: 'EPUB3',
  title: '轮3书',
  author: '甲',
  toc: const [],
  chapters: [
    EpubChapter(
      href: 'c1',
      title: '第一章',
      paras: [
        const EpubPara(
          kind: EpubParaKind.heading,
          text: '第一章',
          headingLevel: 1,
        ),
        _p('第一段。$_lorem'),
        ...List.generate(30, (i) => _p('一之$i。$_lorem')),
      ],
    ),
    EpubChapter(
      href: 'c2',
      title: '第二章',
      paras: [
        const EpubPara(
          kind: EpubParaKind.heading,
          text: '第二章',
          headingLevel: 1,
        ),
        ...List.generate(24, (i) => _p('二之$i。$_lorem')),
      ],
    ),
  ],
  imageCount: 0,
  totalChars: 4000,
  images: const {},
);

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ReadRepository repo;
  late SharedPreferences prefs;

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

  Future<void> step(WidgetTester t, {int ms = 200, int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await t.pump(Duration(milliseconds: ms));
    }
  }

  Future<void> openReader(WidgetTester t, String id) async {
    await useSurface(t, const Size(420, 780));
    await repo.addBook(
      Book(
        id: id,
        title: '轮3书',
        local: true,
        epub: const EpubRef(fmt: 'EPUB3', size: 10, path: 'mem'),
        createdAt: 1,
        updatedAt: 1,
      ),
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          readRepositoryProvider.overrideWithValue(repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
          epubDocLoaderProvider.overrideWithValue((_) async => _bigDoc()),
          epubPreloadProvider.overrideWith(
            (_) => EpubPreloadService(repo),
          ),
        ],
        child: MaterialApp(home: ReaderPage(bookId: id)),
      ),
    );
    await step(t, times: 4);
    await t.tapAt(const Offset(210, 645)); // 中区唤起 chrome
    await step(t);
    expect(find.byKey(const ValueKey('br-bottom')), findsOne);
  }

  String pgLbl(WidgetTester t) =>
      t.widget<Text>(find.byKey(const ValueKey('brPgLbl'))).data ?? '';

  group('V1.53 轮3 · 底栏五图标与面板', () {
    testWidgets('五图标就位 · 面板互斥 · 再点收起', (t) async {
      await openReader(t, 'v1');
      for (final k in ['brBtnToc', 'brBtnTheme', 'brBtnProg', 'brBtnBright', 'brBtnFont']) {
        expect(find.byKey(ValueKey(k)), findsOne, reason: k);
      }
      await t.tap(find.byKey(const ValueKey('brBtnProg')));
      await step(t);
      expect(find.byKey(const ValueKey('brPnlProg')), findsOne);
      expect(find.byKey(const ValueKey('brProg')), findsOne); // 滑条在面板内
      // 统计三格 + 阅读明细/开启自动翻页
      for (final k in ['brStPct', 'brStMin', 'brStNote', 'brPpDetail', 'brPpAuto']) {
        expect(find.byKey(ValueKey(k)), findsOne, reason: k);
      }
      await t.tap(find.byKey(const ValueKey('brBtnFont')));
      await step(t);
      expect(find.byKey(const ValueKey('brPnlProg')), findsNothing);
      expect(find.byKey(const ValueKey('brPnlFont')), findsOne);
      await t.tap(find.byKey(const ValueKey('brBtnFont')));
      await step(t);
      expect(find.byKey(const ValueKey('brPnlFont')), findsNothing);
    });

    testWidgets('亮度面板：滑到最低出遮罩 · 颜色写全局 · 背景写逐书', (t) async {
      await openReader(t, 'v2');
      await t.tap(find.byKey(const ValueKey('brBtnBright')));
      await step(t);
      expect(find.byKey(const ValueKey('brPnlBright')), findsOne);
      for (final k in ['brBt-day', 'brBt-eye', 'brBt-night', 'brBt-custom']) {
        expect(find.byKey(ValueKey(k)), findsOne, reason: k);
      }
      expect(find.byKey(const ValueKey('brBg-4')), findsOne);
      expect(find.byKey(const ValueKey('brLumMask')), findsNothing);
      // 亮度滑条点左端（＝30）→ 遮罩出现并写逐书补丁。
      final lr = t.getRect(find.byKey(const ValueKey('brLum')));
      await t.tapAt(Offset(lr.left + 4, lr.center.dy));
      await step(t);
      expect(find.byKey(const ValueKey('brLumMask')), findsOne);
      var patch = jsonDecode((await repo.kv('reader.cfg.v2'))!) as Map;
      expect(patch['lum'], lessThan(60));
      // 颜色＝夜间（写全局 reader.cfg）。
      await t.tap(find.byKey(const ValueKey('brBt-night')));
      await step(t);
      final g = jsonDecode((await repo.kv('reader.cfg'))!) as Map;
      expect(g['theme'], 'night');
      // 背景预设＝逐书 custom 底色。
      await t.tap(find.byKey(const ValueKey('brBg-3')));
      await step(t);
      patch = jsonDecode((await repo.kv('reader.cfg.v2'))!) as Map;
      expect(patch['bg'], '#f6e7d3');
      expect(patch['theme'], 'custom');
    });

    testWidgets('字号面板：首行缩进开关落逐书补丁并重排', (t) async {
      await openReader(t, 'v3');
      await t.tap(find.byKey(const ValueKey('brBtnFont')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brPfIndent')));
      await step(t, ms: 300, times: 2);
      expect(find.text('首行缩进 · 关 ›'), findsOne);
      final patch = jsonDecode((await repo.kv('reader.cfg.v3'))!) as Map;
      expect(patch['indent'], false);
      await t.tap(find.byKey(const ValueKey('brPfIndent')));
      await step(t, ms: 300, times: 2);
      expect(find.text('首行缩进 · 开 ›'), findsOne);
    });

    testWidgets('进度面板：拖离原位置出「返回原进度」胶囊并可归位', (t) async {
      await openReader(t, 'v4');
      final before = pgLbl(t);
      await t.tap(find.byKey(const ValueKey('brBtnProg')));
      await step(t);
      final sr = t.getRect(find.byKey(const ValueKey('brProg')));
      await t.tapAt(Offset(sr.right - 4, sr.center.dy)); // 拖到全书末尾
      await step(t, ms: 300, times: 2);
      expect(find.byKey(const ValueKey('brBackPos')), findsOne);
      expect(pgLbl(t), isNot(before));
      await t.tap(find.byKey(const ValueKey('brBackPos')));
      await step(t, ms: 300, times: 2);
      expect(find.byKey(const ValueKey('brBackPos')), findsNothing);
      expect(pgLbl(t), before);
    });

    testWidgets('进度面板：自动翻页一键开关写逐书补丁', (t) async {
      await openReader(t, 'v5');
      await t.tap(find.byKey(const ValueKey('brBtnProg')));
      await step(t);
      expect(find.text('开启自动翻页'), findsOne);
      await t.tap(find.byKey(const ValueKey('brPpAuto')));
      await step(t);
      final patch = jsonDecode((await repo.kv('reader.cfg.v5'))!) as Map;
      expect(patch['auto'], true);
      expect(find.text('暂停自动翻页'), findsOne);
      // 阅读器页有周期 Timer：禁 clearToasts/pumpAndSettle（会永动挂死）。
    });
  });
}
