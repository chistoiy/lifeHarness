// R14-6 专项：选区工具条不透明底衬 + 让位三规则 + 手柄放大（工单=原型
// index-bookshelf.html brSelBarPlace/brHandlePlace，2026-09-30 确认）。
// 让位口径与原型一致：sel 顶/底＝首/末段**整段元素**矩形（el0/el1 getBoundingClientRect），
// 不是句级 Range；本文件数字钉在 420×780 + Ahem 实测（探针 2026-10-01）：
//   顶栏 61 · 底栏 74 · 页0 段0..4（段2＝349..413）· 页1 段5..8（拉丁长段 72.5..477.5 · 段8 629.5..693.5）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_page.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_sel_layer.dart';

import 'helpers.dart';

const _lorem = '这是划词实测正文素材，默认字号下约两到三行。';
EpubPara _p(String t) => EpubPara(kind: EpubParaKind.text, text: t);

EpubDoc _doc() => EpubDoc(
  format: 'EPUB3',
  title: '划词书',
  author: '甲',
  toc: const [],
  chapters: [
    EpubChapter(
      href: 'c1',
      title: '第一章',
      paras: [
        const EpubPara(kind: EpubParaKind.heading, text: '第一章', headingLevel: 1),
        _p('第一段。$_lorem'),
        _p('锚定效应贯穿全书。$_lorem'),
        _p('三之0。$_lorem'),
        _p('三之1。$_lorem'),
        _p(
          'This rather long English sentence exists to prove the Latin '
          'fallback: when a paragraph carries no CJK punctuation at all the '
          'selection still snaps to word boundaries instead of swallowing '
          'the entire block of text wholesale.',
        ),
        ...List.generate(10, (i) => _p('一之$i。$_lorem')),
      ],
    ),
    EpubChapter(
      href: 'c2',
      title: '第二章',
      paras: [
        const EpubPara(kind: EpubParaKind.heading, text: '第二章', headingLevel: 1),
        ...List.generate(20, (i) => _p('二之$i。$_lorem')),
      ],
    ),
  ],
  imageCount: 0,
  totalChars: 4000,
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
    await repo.addBook(Book(
      id: id,
      title: '划词书',
      local: true,
      epub: const EpubRef(fmt: 'EPUB3', size: 10, path: 'mem'),
      createdAt: 1,
      updatedAt: 1,
    ));
    await t.pumpWidget(ProviderScope(
      overrides: [
        readRepositoryProvider.overrideWithValue(repo),
        sharedPreferencesProvider.overrideWithValue(prefs),
        epubDocLoaderProvider.overrideWithValue((_) async => _doc()),
      ],
      child: MaterialApp(home: ReaderPage(bookId: id)),
    ));
    await step(t, times: 4);
  }

  // 右缘翻页定式（reader_ui_test flipR：正文 22..398 外；220ms 动画双泵收尾）。
  Future<void> flipR(WidgetTester t) async {
    await t.tapAt(const Offset(412, 390));
    await step(t, ms: 300, times: 2);
  }

  Rect barRect(WidgetTester t) =>
      t.getRect(find.byKey(const ValueKey('brSelBar')));

  /// 指向三角计数（原型 ::after；flip＝朝上）。
  int triCount(WidgetTester t, {required bool up}) => find
      .byWidgetPredicate((w) =>
          w is CustomPaint &&
          w.painter is BrTriPainter &&
          (w.painter as BrTriPainter).up == up)
      .evaluate()
      .length;

  // 尾端手柄拖到目标段下沿（reader_select_test dragHandle 同款）。
  Future<void> dragTail(WidgetTester t, String para) async {
    final hr = t.getRect(find.byKey(const ValueKey('brHEnd')));
    final pr = t.getRect(find.byKey(ValueKey(para)));
    await t.dragFrom(
      Offset(hr.center.dx, hr.center.dy),
      Offset(
        pr.left + pr.width * .5 - hr.center.dx,
        pr.bottom - 1 - hr.center.dy,
      ),
    );
    await step(t);
  }

  group('R14-6 · 让位三规则（原型 brSelBarPlace）', () {
    testWidgets('① 首选上贴：条在选区上方 · 白卡底衬描边投影 · 箭头朝下 · 手柄 31×48', (t) async {
      await openReader(t, 'p1');
      final r = t.getRect(find.byKey(const ValueKey('brpTap-0-2')));
      await t.longPressAt(Offset(r.left + 12, r.top + 5));
      await step(t);
      // 建选区即展开 chrome（顶栏实测 61 → cT=69；下方空间充足 → 上贴）。
      expect(
        t.getRect(find.byKey(const ValueKey('brTopBox'))).height,
        closeTo(61, 1.5),
      );
      final bar = barRect(t);
      // 条顶 = 选区顶(段框+1) − 8 − kBrSelBarH（原型 tAbove 口径）。
      expect(bar.top, closeTo(r.top + 1 - 8 - kBrSelBarH, 2));
      // 核心承诺：工具条行不压选区行；条高≈基准 42（三角另占 7px 在条下）。
      expect(bar.bottom, lessThan(r.top));
      expect(bar.bottom - bar.top, closeTo(kBrSelBarH, 2));
      // 上贴型＝朝下箭头单枚，无朝上。
      expect(triCount(t, up: false), 1);
      expect(triCount(t, up: true), 0);
      // 不透明卡片底衬（旧版为半透明深色 0xE60F172A · 本批翻案）。
      final dec = t
              .widget<Container>(find.byKey(const ValueKey('brSelBar')))
              .decoration!
          as BoxDecoration;
      expect(dec.color, const Color(0xFFFFFFFF));
      expect((dec.border! as Border).top.color, const Color(0xFFF1F5F9));
      expect(dec.borderRadius, BorderRadius.circular(16));
      final sh = dec.boxShadow!.single;
      expect(sh.color, const Color(0x470F172A));
      expect(sh.blurRadius, 24);
      expect(sh.offset, const Offset(0, 8));
      // 芯片图标/文字＝slate-700（浅底皮肤 fg）。
      expect(
        t
            .widget<Icon>(
              find.descendant(
                of: find.byKey(const ValueKey('brSelCopy')),
                matching: find.byType(Icon),
              ),
            )
            .color,
        const Color(0xFF334155),
      );
      // 首尾手柄：命中 31×48 · 茎 2.5×18 · 圆钮 15×15（旧 11/2×15 本批放大）。
      for (final k in ['brHStart', 'brHEnd']) {
        final hr = t.getRect(find.byKey(ValueKey(k)));
        expect(hr.width, closeTo(31, .5), reason: k);
        expect(hr.height, closeTo(48, .5), reason: k);
        final boxes = find.descendant(
          of: find.byKey(ValueKey(k)),
          matching: find.byType(Container),
        );
        expect(t.getSize(boxes.first), const Size(2.5, 18), reason: '$k 茎');
        expect(t.getSize(boxes.last), const Size(15, 15), reason: '$k 钮');
      }
      // 上贴型色环挂条上方 6px（bottom 锚）。
      await t.tap(find.byKey(const ValueKey('brSelHl')));
      await step(t);
      final pop = t.getRect(find.byKey(const ValueKey('brColorPop')));
      expect(pop.bottom, closeTo(bar.top - 6, 2));
      expect(find.byKey(const ValueKey('brDelHl')), findsOne);
      // 段空隙点按收选区（不误切 chrome）。
      await t.tapAt(Offset(210, r.bottom + 5));
      await step(t);
      expect(find.byKey(const ValueKey('brSelBar')), findsNothing);
    });

    testWidgets('② 上方放不下 → 下压 flip：条压选区底边之下 · 箭头翻上', (t) async {
      await openReader(t, 'p2');
      await flipR(t); // 页2 首段贴顶（拉丁长段 72.5..477.5）。
      final r = t.getRect(find.byKey(const ValueKey('brpTap-0-5')));
      // 前提钉死：上贴位会撞顶栏（tAbove<cT），下方空间充足 → 必走 flip。
      expect(r.top + 1 - 8 - kBrSelBarH, lessThan(69));
      expect(r.bottom - 1 + 8 + kBrSelBarH, lessThanOrEqualTo(780 - 82));
      await t.longPressAt(Offset(r.left + 12, r.top + 5));
      await step(t);
      final bar = barRect(t);
      // flip：条顶＝选区底(段框−1)+8（原型 tBelow）；与选区行零重叠。
      expect(bar.top, closeTo(r.bottom - 1 + 8, 2));
      expect(bar.top, greaterThan(r.bottom));
      expect(triCount(t, up: true), 1);
      expect(triCount(t, up: false), 0);
      // flip 色环改挂条下 8px（原型 brColorShow flip 分支）。
      await t.tap(find.byKey(const ValueKey('brSelHl')));
      await step(t);
      final pop = t.getRect(find.byKey(const ValueKey('brColorPop')));
      expect(pop.top, closeTo(bar.top + kBrSelBarH + 8, 3));
      await t.tapAt(Offset(210, r.bottom + 4)); // 段5/段6 空隙
      await step(t);
      expect(find.byKey(const ValueKey('brSelBar')), findsNothing);
    });

    testWidgets('③ 下方也放不下 → pinned 贴底栏上方 · 箭头仍朝下', (t) async {
      await openReader(t, 'p3');
      await flipR(t); // 页2 末段（629.5..693.5）贴底。
      final r = t.getRect(find.byKey(const ValueKey('brpTap-0-8')));
      await t.longPressAt(Offset(r.left + 12, r.top + 5));
      await step(t);
      final bo = t.getRect(find.byKey(const ValueKey('brBottomBox'))).height;
      final bar = barRect(t);
      // 前提钉死：下压位会撞底栏（tBelow+42 > 780−cB）→ 必走 pinned。
      expect(r.bottom - 1 + 8 + kBrSelBarH, greaterThan(780 - (bo + 8)));
      // pinned：条顶＝height−cB−barH（656 实测）；条底不压底栏（706）。
      expect(bar.top, closeTo(780 - (bo + 8) - kBrSelBarH, 2));
      expect(bar.bottom, lessThanOrEqualTo(780 - bo));
      expect(triCount(t, up: false), 1); // pinned 仍朝下（原型无 flip 类）
      expect(triCount(t, up: true), 0);
    });

    testWidgets('④ 手柄跨段扩选后仍锚首段上方上贴（p0 顶为准 · 不随拖拽换位）', (t) async {
      await openReader(t, 'p4');
      final r3 = t.getRect(find.byKey(const ValueKey('brpTap-0-3')));
      await t.longPressAt(Offset(r3.left + 12, r3.top + 5));
      await step(t);
      final bar0 = barRect(t);
      await dragTail(t, 'brpTap-0-4');
      final bar1 = barRect(t);
      // 选区吃到段4（底 557）后 roomAbove 仍成立 → 条位只锚 p0 顶，两次一致。
      expect(bar1.top, closeTo(r3.top + 1 - 8 - kBrSelBarH, 2));
      expect(bar1.top, bar0.top);
      expect(bar1.bottom, lessThan(r3.top)); // 扩选后依旧不压选区首行
    });
  });

  group('R14-6 · 皮肤', () {
    test('brSelSkinOf 与 brBarOf 同亮度线：浅底白卡深字 · 深底深卡浅字', () {
      final lite = brSelSkinOf(const Color(0xFFF8FAFC));
      expect(lite.card, const Color(0xFFFFFFFF));
      expect(lite.border, const Color(0xFFF1F5F9));
      expect(lite.fg, const Color(0xFF334155));
      final dark = brSelSkinOf(const Color(0xFF1E293B));
      expect(dark.card, const Color(0xFF0F172A));
      expect(dark.border, const Color(0xFF1E293B));
      expect(dark.fg, const Color(0xFFCBD5E1));
    });

    test('让位常量与原型量纲一致（barH 基准 42）', () {
      expect(kBrSelBarH, 42);
    });
  });
}
