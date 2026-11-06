import 'dart:io' show File;

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
import 'package:lifeharness/features/read/domain/book_quote.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_loupe.dart'
    show ReaderLoupe;
import 'package:lifeharness/features/read/presentation/reader/reader_page.dart';
import 'package:lifeharness/shared/widgets/ui_kit.dart' show Pressable;

// 二期批6 · 阅读器手感（F6-1~F6-5）。独立文件防 isolate 污染。
//
// 这一批钉的是「按下去有没有反应」这类手感债，不再是效率：
//   F6-1 底栏/抽屉裸 GestureDetector → 按压原语（空动画 alpha:.0 是假反馈）；
//   F6-2 翻页恒「从右进」→ 按方向；
//   F6-4 滑条拖动中同步回排 → 松手才落位；
//   F6-5 划线等回库才上色 → 乐观上色＋失败回滚＋撤销。
// F6-3（放大镜降频）的验收口径是**真机帧率举证**（方案 §2.2/§B-4），本文件只钉
// 节流窗口常量与「放大镜没被这次改动弄坏」，不拿单测假装证明帧率。

const _filler =
    '这是一段用于手感实测的中文正文，长度足够在默认字号下占据两到三行，'
    '重复若干次即可稳定地把整章撑到好几页。';

EpubPara _p(String t) => EpubPara(kind: EpubParaKind.text, text: t);

/// 12 章 × 9 段：每段带唯一标记 `C{章}P{段}`（翻页/定位断言用）。
EpubDoc _doc() => EpubDoc(
  format: 'EPUB3',
  title: '手感书',
  author: '甲',
  toc: const [],
  chapters: [
    for (var c = 0; c < 12; c++)
      EpubChapter(
        href: 'c$c',
        title: '第${c + 1}章',
        paras: [
          EpubPara(
            kind: EpubParaKind.heading,
            text: '第${c + 1}章',
            headingLevel: 1,
          ),
          for (var i = 1; i <= 9; i++) _p('C${c}P$i。$_filler'),
        ],
      ),
  ],
  imageCount: 0,
  totalChars: 12 * 9 * _filler.length,
);

/// 落库慢 400ms 的仓库：用来证明「上色**不等**回库」（乐观上色）。
class _SlowRepo extends ReadRepository {
  _SlowRepo(super.db);
  @override
  Future<int?> addQuote(BookQuote q) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return super.addQuote(q);
  }
}

/// 落库必失败的仓库：用来证明「失败回滚＋提示」（B-5）。
class _FailRepo extends ReadRepository {
  _FailRepo(super.db);
  @override
  Future<int?> addQuote(BookQuote q) async =>
      throw Exception('磁盘写入失败');
}

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
    await repo.addBook(
      Book(
        id: 's1',
        title: '手感书',
        local: true,
        epub: const EpubRef(fmt: 'EPUB3', size: 10, path: 'mem'),
        createdAt: 1,
        updatedAt: 1,
      ),
    );
  });
  tearDown(() => db.close());

  Future<void> step(WidgetTester t, {int ms = 200, int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await t.pump(Duration(milliseconds: ms));
    }
  }

  Future<void> mount(WidgetTester t, {ReadRepository? use, double h = 780}) async {
    await useSurface(t, Size(420, h));
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          readRepositoryProvider.overrideWithValue(use ?? repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
          epubDocLoaderProvider.overrideWithValue((_) async => _doc()),
          epubPreloadProvider.overrideWith((_) => EpubPreloadService(repo)),
        ],
        child: const MaterialApp(home: ReaderPage(bookId: 's1')),
      ),
    );
    await step(t, times: 4);
  }

  /// 唤起 chrome（点中央区）。
  Future<void> showChrome(WidgetTester t, {double h = 780}) async {
    await t.tapAt(Offset(210, h * .83));
    await step(t);
    expect(find.byKey(const ValueKey('br-bottom')), findsOne);
  }

  String pgLbl(WidgetTester t) =>
      t.widget<Text>(find.byKey(const ValueKey('brPgLbl'))).data ?? '';

  /// 段内带底色 span 的文本（与 reader_select_test 同一验表面：根样式无背景）。
  List<String> paintedTexts(WidgetTester t, String key) {
    final rt = t.widget<RichText>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(RichText),
      ),
    );
    final out = <String>[];
    void walk(InlineSpan s) {
      if (s is! TextSpan) return;
      if (s.style?.backgroundColor != null && (s.text?.isNotEmpty ?? false)) {
        out.add(s.text!);
      }
      for (final c in s.children ?? const <InlineSpan>[]) {
        walk(c);
      }
    }

    walk(rt.text);
    return out;
  }

  /// 段内带底色 span 的**颜色**。只看「有没有底色」会把**选区的浅底**也算进去
  /// （选区在场时同一段本来就有底色）——那正是「断言从实现反推」的坑：摘掉乐观
  /// 上色后用例照样绿。所以按色标值断言，不能只判非空。
  List<Color> paintedColors(WidgetTester t, String key) {
    final rt = t.widget<RichText>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(RichText),
      ),
    );
    final out = <Color>[];
    void walk(InlineSpan s) {
      if (s is! TextSpan) return;
      final bg = s.style?.backgroundColor;
      if (bg != null && (s.text?.isNotEmpty ?? false)) out.add(bg);
      for (final c in s.children ?? const <InlineSpan>[]) {
        walk(c);
      }
    }

    walk(rt.text);
    return out;
  }

  /// 划线上屏色＝色标 × .27（与渲染层 `hlBg` 同式），用来把「划线底色」与
  /// 「选区浅底」区分开。
  Color hlBgOf(String tag) => Color(
    0xFF000000 | (BookQuote.hexToInt(BookQuote.colorHex[tag]) ?? 0xFDE047),
  ).withValues(alpha: .27);

  Finder pressableOf(String key) => find.ancestor(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(Pressable),
  );

  group('F6-1 · 底栏与抽屉换按压原语', () {
    testWidgets('底栏三钮都在 Pressable 里，按下即缩放 .96（不是空动画）', (t) async {
      await mount(t);
      await showChrome(t);
      for (final k in ['brBtnToc', 'brBtnProg', 'brBtnLook']) {
        expect(pressableOf(k), findsOne, reason: '$k 必须包在按压原语里');
      }
      // 按下 → 该钮子树里的 AnimatedScale 收到 .96；抬起 → 复位 1。
      final c = t.getRect(find.byKey(const ValueKey('brBtnProg'))).center;
      final g = await t.startGesture(c);
      await t.pump();
      double scaleOf(String k) => t
          .widget<AnimatedScale>(find.descendant(
            of: pressableOf(k),
            matching: find.byType(AnimatedScale),
          ))
          .scale;
      expect(scaleOf('brBtnProg'), .96, reason: '按下必须有缩放＝真反馈');
      expect(scaleOf('brBtnToc'), 1, reason: '没按的那个不许跟着缩');
      await g.up();
      await step(t);
      expect(scaleOf('brBtnProg'), 1, reason: '抬起要复位');
    });

    testWidgets('目录抽屉可点行走同一原语，两文件零裸 GestureDetector', (t) async {
      await mount(t);
      await showChrome(t);
      await t.tap(find.byKey(const ValueKey('brBtnToc')));
      await step(t, ms: 320, times: 2);
      expect(find.byKey(const ValueKey('brDrPanel')), findsOne);
      expect(pressableOf('brDrCh-0'), findsOne, reason: '章行必须包在按压原语里');
      expect(pressableOf('brDrFoldAll'), findsOne, reason: '全部折叠也必须包');
      // 源码闸：两文件不许再有裸 GestureDetector 构造（F6-1 守护扫描）。
      for (final f in [
        'lib/features/read/presentation/reader/reader_chrome.dart',
        'lib/features/read/presentation/reader/reader_toc_drawer.dart',
      ]) {
        final src = File(f).readAsStringSync();
        expect(
          src.contains('GestureDetector('),
          isFalse,
          reason: '$f 里还有裸 GestureDetector（回退＝手感又变回没反馈）',
        );
      }
    });
  });

  group('F6-2 · 翻页按方向', () {
    testWidgets('前进从右侧进、回翻从左侧进（旧实现两边都从右进）', (t) async {
      await mount(t);
      // 前进：page-0-0 → page-0-1
      await t.tapAt(Offset(390, 400));
      await t.pump();
      await t.pump(const Duration(milliseconds: 30));
      final fwdMid = t.getTopLeft(find.byKey(const ValueKey('page-0-1'))).dx;
      await step(t, ms: 400, times: 2);
      final fwdEnd = t.getTopLeft(find.byKey(const ValueKey('page-0-1'))).dx;
      expect(
        fwdMid,
        greaterThan(fwdEnd + 1),
        reason: '前进时新页应当还在落脚点右侧（从右滑入）',
      );

      // 回翻：page-0-1 → page-0-0
      await t.tapAt(Offset(30, 400));
      await t.pump();
      await t.pump(const Duration(milliseconds: 30));
      final backMid = t.getTopLeft(find.byKey(const ValueKey('page-0-0'))).dx;
      await step(t, ms: 400, times: 2);
      final backEnd = t.getTopLeft(find.byKey(const ValueKey('page-0-0'))).dx;
      expect(
        backMid,
        lessThan(backEnd - 1),
        reason: '回翻时新页应当还在落脚点左侧（从左滑入）＝按方向',
      );
    });
  });

  group('F6-3 · 放大镜降频（口径＝真机帧率，此处只钉窗口）', () {
    testWidgets('节流窗口 60ms（回退成每指针事件抓帧即红）', (t) async {
      expect(kBrLoupeThrottleMs, 60);
      // 放大镜仍挂在手柄拖动上：长按选词 → 手柄在 → 拖手柄后放大镜出来（功能未劣化）。
      await mount(t);
      await t.longPress(find.byKey(const ValueKey('brpTap-0-1')));
      await step(t);
      expect(find.byKey(const ValueKey('brSelBar')), findsOne);
      expect(find.byKey(const ValueKey('brHStart')), findsOne);
      final r = t.getRect(find.byKey(const ValueKey('brHStart')));
      final g = await t.startGesture(r.center);
      await t.pump();
      // 越过 kTouchSlop 才算拖（12px 不动＝pan 还没开始，与节流无关）。
      await g.moveBy(const Offset(0, -40));
      await t.pump();
      await g.moveBy(const Offset(0, -40));
      // 等过一节流窗口：拖尾那一帧要补齐（不补＝手指停住后放大镜还是旧位置）。
      await t.pump(const Duration(milliseconds: 90));
      expect(find.byType(ReaderLoupe), findsOne,
          reason: '拖手柄要出放大镜（节流不许把放大镜整个吞掉）');
      await g.up();
      await step(t);
    });
  });

  group('F6-4 · seek 节流', () {
    testWidgets('拖动中只更滑条不回排，松手才落位', (t) async {
      await mount(t);
      await showChrome(t);
      await t.tap(find.byKey(const ValueKey('brBtnProg')));
      await step(t, ms: 320, times: 2);
      expect(find.byKey(const ValueKey('sheetBrProg')), findsOne);
      final before = pgLbl(t);
      final r = t.getRect(find.byKey(const ValueKey('brProg')));
      final g = await t.startGesture(Offset(r.left + 24, r.center.dy));
      await g.moveTo(Offset(r.left + r.width * .8, r.center.dy));
      await t.pump();
      await t.pump(const Duration(milliseconds: 60));
      expect(
        pgLbl(t),
        before,
        reason: '拖动中就回排了（旧行为：每个 onChanged 都 layoutChapter＋写库）',
      );
      await g.up();
      await step(t, ms: 320, times: 3);
      expect(pgLbl(t), isNot(before), reason: '松手必须落位');
    });
  });

  group('F6-5 · 划线乐观上色与撤销', () {
    testWidgets('先上色后落库：回库未完成时底色已在，撤销删掉那条书摘', (t) async {
      final slow = _SlowRepo(db);
      await mount(t, use: slow);
      await t.longPress(find.byKey(const ValueKey('brpTap-0-1')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brSelHl')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brColor-重点')));
      // 只走两帧（远小于 400ms 落库延迟）：此时不允许「已落库」，但必须已上色。
      await t.pump();
      await t.pump(const Duration(milliseconds: 60));
      expect(
        paintedColors(t, 'brp-0-1'),
        contains(hlBgOf('重点')),
        reason: '乐观上色：还在落库路上就该有**划线底色**'
            '（判非空会被选区浅底糊过去；旧实现要等 _reloadHls 回来）',
      );
      expect(
        await slow.quotesOf('s1'),
        isEmpty,
        reason: '这两帧里确实还没落库（否则本用例证明不了「不等回库」）',
      );
      await step(t, ms: 500, times: 2);
      expect(await slow.quotesOf('s1'), hasLength(1));
      expect(find.text('撤销'), findsOne, reason: '落库后要给撤销窗口（F6-5）');
      await t.tap(find.text('撤销'));
      await step(t, ms: 400, times: 2);
      expect(await slow.quotesOf('s1'), isEmpty, reason: '撤销＝删这条划线书摘');
      expect(paintedTexts(t, 'brp-0-1'), isEmpty, reason: '撤销后底色要跟着退');
    });

    testWidgets('落库失败：回滚底色并提示（不留假色块）', (t) async {
      final fail = _FailRepo(db);
      await mount(t, use: fail);
      await t.longPress(find.byKey(const ValueKey('brpTap-0-1')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brSelHl')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brColor-重点')));
      await step(t, ms: 400, times: 2);
      expect(find.textContaining('划线保存失败'), findsOne, reason: '失败必须出声');
      expect(
        paintedTexts(t, 'brp-0-1'),
        isEmpty,
        reason: '落库失败回滚：不许在正文留一条假划线',
      );
    });
  });
}
