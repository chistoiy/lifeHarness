import 'dart:convert' show jsonDecode;

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
import 'package:lifeharness/features/read/domain/reader_cfg.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_bg.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_page.dart';

// V1.53 轮3 → V1.53.2 轮5.1 改版：底栏五图标+三个内嵌面板
// → 底栏三图标（目录/进度/外观）+ 正常底部弹层（原型 sheetBrProg /
// sheetBrAppearance / sheetBrMore）。独立文件防 isolate 污染。

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

  Future<void> openReader(WidgetTester t, String id, {double h = 780}) async {
    await useSurface(t, Size(420, h));
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
    await t.tapAt(Offset(210, h * .83)); // 中区唤起 chrome
    await step(t);
    expect(find.byKey(const ValueKey('br-bottom')), findsOne);
  }

  String pgLbl(WidgetTester t) =>
      t.widget<Text>(find.byKey(const ValueKey('brPgLbl'))).data ?? '';

  /// 把滑条置到某个分数位置（0＝左端 · 1＝右端）：从中心拖到目标 x。
  Future<void> slideTo(WidgetTester t, String key, double f) async {
    final r = t.getRect(find.byKey(ValueKey(key)));
    if (f <= 0.02) {
      await t.tapAt(Offset(r.left + 2, r.center.dy));
    } else {
      await t.drag(find.byKey(ValueKey(key)), Offset(r.width * (f - .5), 0));
    }
    await step(t, ms: 300, times: 2);
  }

  group('轮5.1 · 底栏三图标与弹层', () {
    testWidgets('底栏只剩 目录/进度/外观 三图标 · 顶栏补 ⋯ 更多入口', (t) async {
      await openReader(t, 'v1');
      for (final k in ['brBtnToc', 'brBtnProg', 'brBtnLook']) {
        expect(find.byKey(ValueKey(k)), findsOne, reason: k);
      }
      // 轮3 的 主题/亮度/字号 三钮已并入外观弹层。
      for (final k in ['brBtnTheme', 'brBtnBright', 'brBtnFont']) {
        expect(find.byKey(ValueKey(k)), findsNothing, reason: k);
      }
      expect(find.byKey(const ValueKey('brBtnMore')), findsOne);
    });

    testWidgets('进度弹层：统计三格 + 滑条定位 + 自动翻页一键开关', (t) async {
      await openReader(t, 'v2');
      final before = pgLbl(t);
      await t.tap(find.byKey(const ValueKey('brBtnProg')));
      await step(t, ms: 320, times: 2);
      expect(find.byKey(const ValueKey('sheetBrProg')), findsOne);
      for (final k in ['brStPct', 'brStMin', 'brStNote', 'brProg', 'brPpDetail', 'brPpAuto']) {
        expect(find.byKey(ValueKey(k)), findsOne, reason: k);
      }
      // 拖到全书末尾 → 位置变化（弹层不自动关，滑条留在新位置）。
      await slideTo(t, 'brProg', .98);
      expect(pgLbl(t), isNot(before));
      expect(find.byKey(const ValueKey('brProgHome')), findsOne);
      await t.tap(find.byKey(const ValueKey('brPpClose')));
      await step(t, ms: 320, times: 2);
      // 再开：自动翻页开关落逐书补丁。
      await t.tap(find.byKey(const ValueKey('brBtnProg')));
      await step(t, ms: 320, times: 2);
      expect(find.text('开启自动翻页'), findsOne);
      await t.tap(find.byKey(const ValueKey('brPpAuto')));
      await step(t, ms: 320, times: 2);
      final patch = jsonDecode((await repo.kv('reader.cfg.v2'))!) as Map;
      expect(patch['auto'], true);
      // 阅读器页有周期 Timer：禁 clearToasts/pumpAndSettle（会挂）。
    });

    testWidgets('进度弹层：拖离进书位置才出「回到进书位置」并可归位', (t) async {
      await openReader(t, 'v3');
      final before = pgLbl(t);
      await t.tap(find.byKey(const ValueKey('brBtnProg')));
      await step(t, ms: 320, times: 2);
      // 未离开时不给返回入口（轮5.2①：正文不悬浮，收进弹层）。
      expect(find.byKey(const ValueKey('brBackPos')), findsNothing);
      expect(find.byKey(const ValueKey('brProgHome')), findsNothing);
      await slideTo(t, 'brProg', .98);
      expect(pgLbl(t), isNot(before));
      await t.tap(find.byKey(const ValueKey('brProgHome')));
      await step(t, ms: 320, times: 2);
      expect(pgLbl(t), before);
      // 正文上不残留任何悬浮胶囊。
      expect(find.byKey(const ValueKey('brBackPos')), findsNothing);
    });

    testWidgets('外观弹层：亮度/缩进/背景/纹理一次落库', (t) async {
      await openReader(t, 'v4', h: 1400);
      await t.tap(find.byKey(const ValueKey('brBtnLook')));
      await step(t, ms: 320, times: 3);
      expect(find.byKey(const ValueKey('sheetBrAppearance')), findsOne);
      for (final k in [
        'brApPrev',
        'brApFsSlider',
        'brApLumSlider',
        'brApBgs',
        'brApHue',
        'brApLite',
        'brApTex',
        'brApDimSlider',
        'brApIndent',
        'brApSave',
      ]) {
        expect(find.byKey(ValueKey(k)), findsOne, reason: k);
      }
      // 亮度滑到左端（＝30）：草稿期只影响预览，保存后遮罩才出现。
      expect(find.byKey(const ValueKey('brLumMask')), findsNothing);
      await slideTo(t, 'brApLumSlider', 0);
      // 背景预设（第 4 块＝#f6e7d3）→ custom 底色。
      await t.tap(find.byKey(const ValueKey('brApBg-#f6e7d3')));
      await step(t);
      // 纹理：纸纹。
      await t.tap(find.byKey(const ValueKey('brApTex-paper')));
      await step(t);
      // 首行缩进关。
      await t.tap(find.byKey(const ValueKey('brApIndent')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brApSave')));
      await step(t, ms: 320, times: 3);
      final patch = jsonDecode((await repo.kv('reader.cfg.v4'))!) as Map;
      expect(patch['theme'], 'custom');
      expect(patch['bg'], '#f6e7d3');
      expect(patch['bgTex'], 'paper');
      expect(patch['indent'], false);
      expect(patch['lum'], 30);
      expect(find.byKey(const ValueKey('brLumMask')), findsOne);
    });

    testWidgets('更多弹层：阅读模式与常亮写库 · 四入口可达', (t) async {
      await openReader(t, 'v5');
      await t.tap(find.byKey(const ValueKey('brBtnMore')));
      await step(t, ms: 320, times: 3);
      expect(find.byKey(const ValueKey('sheetBrMore')), findsOne);
      for (final k in [
        'brMtToc',
        'brMtSearch',
        'brMtQuotes',
        'brMtLog',
        'brMtStat',
        'brMtDetail',
        'brMtLook',
        'brMtDel',
        'brMnBright',
      ]) {
        expect(find.byKey(ValueKey(k)), findsOne, reason: k);
      }
      await t.tap(find.byKey(const ValueKey('brMode-scroll')));
      await step(t, ms: 320, times: 3);
      final g = jsonDecode((await repo.kv('reader.cfg'))!) as Map;
      expect(g['mode'], 'scroll');
      expect(find.byKey(const ValueKey('br-scroll')), findsOne);
    });

    testWidgets('轮5.4 · 顶/底栏随主题取色（浅底不再黑条）', (t) async {
      await openReader(t, 'v6');
      BoxDecoration box(String k) =>
          t.widget<Container>(find.byKey(ValueKey(k))).decoration!
              as BoxDecoration;
      // 默认日间（浅底）：栏底＝舞台色不透明、字色深。
      // 真机反馈（2026-09-28）：顶/底栏已摘 BackdropFilter（弹层/选区时会把
      // 整页正文卷进模糊），栏底必须不透明，且页面内不再存在任何模糊层。
      final top = box('brTopBox');
      expect(top.color!.computeLuminance() > .5, isTrue);
      expect(top.color!.a, 1.0);
      expect(box('brBottomBox').color!.computeLuminance() > .5, isTrue);
      expect(find.byType(BackdropFilter), findsNothing);
      // 夜间主题：同一套取色应翻成深栏浅字。
      final dark = brBarOf(kBrThemes['night']!.$2, kBrThemes['night']!.$3);
      final light = brBarOf(kBrThemes['day']!.$2, kBrThemes['day']!.$3);
      expect(
        dark.fg.computeLuminance() > dark.bg.computeLuminance(),
        isTrue,
        reason: '深底→浅字',
      );
      expect(
        light.fg.computeLuminance() < light.bg.computeLuminance(),
        isTrue,
        reason: '浅底→深字',
      );
    });
  });

  group('轮5.4 · 阅读页挂起全局计时条', () {
    testWidgets('readerOpenProvider 计数随页面进出', (t) async {
      final container = ProviderContainer(
        overrides: [
          readRepositoryProvider.overrideWithValue(repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(readerOpenProvider), 0);
      container.read(readerOpenProvider.notifier).state++;
      expect(container.read(readerOpenProvider), 1);
      // 挂起中：即使有在跑会话也不出顶栏胶囊。
      await repo.startSession('v7');
      expect(await container.read(readTimerBarVisibleProvider.future), isFalse);
    });
  });
}

/// 顶/底栏取色（lib 内实现同源，测试侧只验数值方向）。
