// F-13（工单 §15 · 2026-10-07）· 同段**多条**划线的铺色回归。
// 缺陷本体：渲染层一条段落只留一条划线——旧 `_hlAt` 用单个 `hit` 变量循环覆盖
// （注释自认「多条取最后」），于是库里两条都在、页面上后一条把前一条挤掉。
// 既有 reader 用例全是「一段一条」，所以这条缺陷能活到真机——本文件专钉多条。
// 钉五条：①同段两条不重叠各自铺色 ②部分重叠→重叠区取靠后（最新）那条、
// 前者未重叠部分仍在 ③旧整段数据（无 cf 偏移）不压子串 ④删一条另一条照旧
// （`_reloadHls` 后列表重算）⑤拆到两页的段每条只与本块求交、跨块不漏铺（§3H-A）。
// 独立文件防 isolate 污染；doc 经 epubDocLoaderProvider 手搓，零真实 IO。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/domain/book_quote.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// 26 字拉丁正文：偏移可手算，铺色片段比对不含糊（cf 的 o0/o1 直接对上字母）。
const _alpha = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

/// 跨页素材：90 组 CJK（比一页高得多，必被 §3H-A 拆成多块续排）。
final _long = List.generate(90, (i) => '智伯請地於韓康子$i').join();

EpubPara _p(String t) => EpubPara(kind: EpubParaKind.text, text: t);

EpubDoc _doc(List<EpubPara> paras) => EpubDoc(
  format: 'EPUB3',
  title: '多条书',
  author: '甲',
  toc: const [],
  chapters: [
    EpubChapter(
      href: 'c1',
      title: '第一章',
      paras: [
        const EpubPara(
            kind: EpubParaKind.heading, text: '第一章', headingLevel: 1),
        ...paras,
      ],
    ),
  ],
  imageCount: 0,
  totalChars: paras.fold<int>(0, (s, p) => s + p.text.length),
);

/// 短书：pi=1 ＝ [_alpha]（①②③④ 的用段）。
EpubDoc _shortDoc() => _doc([_p(_alpha), _p('尾段不参与铺色。')]);

/// 长书：pi=1 ＝ [_long]（⑤ 的跨页用段）。
EpubDoc _longDoc() => _doc([_p(_long)]);

/// 色标 → 铺色（渲染层口径＝色值 27% 透明，期望值按源码现算，不写死）。
Color _bg(String tag) =>
    Color(0xFF000000 | (BookQuote.hexToInt(BookQuote.colorHex[tag]) ?? 0))
        .withValues(alpha: .27);

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

  Widget wrap(Widget home, EpubDoc doc) => ProviderScope(
    overrides: [
      readRepositoryProvider.overrideWithValue(repo),
      sharedPreferencesProvider.overrideWithValue(prefs),
      epubDocLoaderProvider.overrideWithValue((_) async => doc),
    ],
    child: MaterialApp(home: home),
  );

  Future<void> openReader(WidgetTester t, EpubDoc doc, String id) async {
    await useSurface(t, const Size(420, 780));
    await repo.addBook(Book(
      id: id,
      title: '多条书',
      local: true,
      epub: const EpubRef(fmt: 'EPUB3', size: 10, path: 'mem'),
      createdAt: 1,
      updatedAt: 1,
    ));
    await t.pumpWidget(wrap(ReaderPage(bookId: id), doc));
    await step(t, times: 4);
    // 中区空白点一下常驻顶/底栏（与 reader_ui_test 同法；翻页热区靠右缘）。
    await t.tapAt(const Offset(210, 645));
    await step(t);
    expect(find.byKey(const ValueKey('br-bottom')), findsOne);
  }

  /// 重开阅读器（逼 `_reloadHls` 重算列表）——④ 的「删一条后另一条照旧」走这条链。
  Future<void> reopenReader(WidgetTester t, EpubDoc doc, String id) async {
    await t.pumpWidget(wrap(const SizedBox.shrink(), doc));
    await step(t);
    await t.pumpWidget(wrap(ReaderPage(bookId: id), doc));
    await step(t, times: 4);
  }

  Future<void> flipR(WidgetTester t) async {
    await t.tapAt(const Offset(412, 350));
    await step(t, ms: 300, times: 2);
  }

  /// 指定块（默认首块 `brp-0-1`）里**带底色**的 span 片段（原文坐标，不含缩进前缀）。
  List<({String t, Color c})> painted(WidgetTester t, {String key = 'brp-0-1'}) {
    final rt = t.widget<RichText>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(RichText),
      ),
    );
    final out = <({String t, Color c})>[];
    void walk(InlineSpan s) {
      if (s is! TextSpan) return;
      final bg = s.style?.backgroundColor;
      if (bg != null && (s.text?.isNotEmpty ?? false)) {
        out.add((t: s.text!, c: bg));
      }
      for (final c in s.children ?? const <InlineSpan>[]) {
        walk(c);
      }
    }
    walk(rt.text);
    return out;
  }

  /// 当前屏上所有该色的铺色片段（⑤ 跨页用：同一块的续排块键带 from 后缀，按色收集）。
  String paintedJoin(WidgetTester t, Color col) {
    final out = StringBuffer();
    for (final rt in t.widgetList<RichText>(find.byType(RichText))) {
      void walk(InlineSpan s) {
        if (s is TextSpan) {
          if (s.style?.backgroundColor == col && (s.text?.isNotEmpty ?? false)) {
            out.write(s.text);
          }
          for (final c in s.children ?? const <InlineSpan>[]) {
            walk(c);
          }
        }
      }
      walk(rt.text);
    }
    return out.toString();
  }

  /// 段 wrap Container 的底色（整段口径才非 null）。
  Color? containerColor(WidgetTester t, {String tapKey = 'brpTap-0-1'}) {
    final box = t.widget<Container>(
      find
          .descendant(
            of: find.byKey(ValueKey(tapKey)),
            matching: find.byType(Container),
          )
          .first,
    );
    return (box.decoration as BoxDecoration?)?.color;
  }

  /// 精确划线落库（ci=0/pi=1，偏移＝原文坐标；rid 唯一，createdAt 决定新旧序）。
  Future<int?> seedHl(
    String bookId, {
    required int a,
    required int b,
    required String tag,
    required int at,
  }) =>
      repo.addQuote(
        BookQuote(
          bookId: bookId,
          kind: BookQuote.kKindMark,
          tag: tag,
          body: a == 0 && b >= _alpha.length ? _alpha : _alpha.substring(a, b),
          chapter: '第一章',
          page: 1,
          cf: QuoteCf(c: 0, p0: 1, p1: 1, o0: a, o1: b),
          rid: 'r$at',
          origin: '阅读器',
          createdAt: at,
          updatedAt: at,
        ),
      );

  group('F-13 · 同段多条划线的铺色', () {
    testWidgets('①同段两条不重叠 → 两段各自铺色（旧实现第二条挤掉第一条）',
        (t) async {
      await seedHl('f1', a: 2, b: 8, tag: BookQuote.kTagKey, at: 1000);
      await seedHl('f1', a: 12, b: 20, tag: BookQuote.kTagReso, at: 2000);
      await openReader(t, _shortDoc(), 'f1');
      final colA = _bg(BookQuote.kTagKey), colB = _bg(BookQuote.kTagReso);
      final ps = painted(t);
      expect(ps.where((e) => e.c == colA).map((e) => e.t).join(),
          _alpha.substring(2, 8),
          reason: '先划的那条必须照旧在（F-13 现象＝它被后一条挤掉）');
      expect(ps.where((e) => e.c == colB).map((e) => e.t).join(),
          _alpha.substring(12, 20),
          reason: '后划的那条也必须铺色');
      expect(containerColor(t), isNull, reason: '两条都是精确区间，不许整段涂');
    });

    testWidgets('②同段两条部分重叠 → 重叠区取靠后者色，前者未重叠部分仍在',
        (t) async {
      await seedHl('f2', a: 2, b: 10, tag: BookQuote.kTagKey, at: 1000);
      await seedHl('f2', a: 6, b: 14, tag: BookQuote.kTagReso, at: 2000);
      await openReader(t, _shortDoc(), 'f2');
      final colA = _bg(BookQuote.kTagKey), colB = _bg(BookQuote.kTagReso);
      final ps = painted(t);
      // 三段：前专属（A 色）／重叠区（B 色＝较新）／后专属（B 色）。
      expect(ps.where((e) => e.c == colA).map((e) => e.t).join(),
          _alpha.substring(2, 6),
          reason: 'A 只该剩未重叠的前四字，重叠区归 B');
      expect(ps.where((e) => e.c == colB).map((e) => e.t).join(),
          _alpha.substring(6, 14),
          reason: 'B 吃满自己的区间（含重叠区）');
      expect(
        ps.where((e) => e.c != colA && e.c != colB).map((e) => e.t).join(),
        isEmpty,
        reason: '除这两条的色外不该有别的底色',
      );
    });

    testWidgets('③一条整段（无 cf 偏移的旧数据）＋一条子串 → 子串不被整段压住',
        (t) async {
      await repo.addQuote(
        BookQuote(
          bookId: 'f3',
          kind: BookQuote.kKindMark,
          tag: BookQuote.kTagAct,
          body: _alpha,
          chapter: '第一章',
          page: 1,
          // 旧行＝cf 只有章段区间，无 o0/o1（isPrecise false）。
          cf: QuoteCf(c: 0, p0: 1, p1: 1),
          rid: 'r1000',
          origin: '阅读器',
          createdAt: 1000,
          updatedAt: 1000,
        ),
      );
      await seedHl('f3', a: 4, b: 10, tag: BookQuote.kTagReso, at: 2000);
      await openReader(t, _shortDoc(), 'f3');
      final colB = _bg(BookQuote.kTagReso);
      expect(painted(t).where((e) => e.c == colB).map((e) => e.t).join(),
          _alpha.substring(4, 10),
          reason: '子串必须按 span 精确铺');
      expect(containerColor(t), isNull,
          reason: '段内已有精确区间 → 旧整段那条不再整段涂（F-13 步骤3）');
      expect(painted(t).where((e) => e.c != colB), isEmpty,
          reason: '旧整段行不该在别处再铺一层色');
    });

    testWidgets('④删除其中一条 → 另一条照旧渲染（重开列表重算）', (t) async {
      final idA =
          await seedHl('f4', a: 2, b: 8, tag: BookQuote.kTagKey, at: 1000);
      await seedHl('f4', a: 12, b: 20, tag: BookQuote.kTagReso, at: 2000);
      await openReader(t, _shortDoc(), 'f4');
      final colA = _bg(BookQuote.kTagKey), colB = _bg(BookQuote.kTagReso);
      expect(painted(t).where((e) => e.c == colA), isNotEmpty);
      // 数据层软删 A（＝回收站语义，阅读器侧 `_hlQuotes` 过滤 deletedAt）
      await repo.softDeleteQuote(idA!);
      await reopenReader(t, _shortDoc(), 'f4');
      final ps = painted(t);
      expect(ps.where((e) => e.c == colA), isEmpty, reason: '删掉的那条不许再铺色');
      expect(ps.where((e) => e.c == colB).map((e) => e.t).join(),
          _alpha.substring(12, 20),
          reason: '另一条必须照旧在');
    });

    testWidgets('⑥长按选区在场时，段内已有划线不许就地消失（F-14 真机反馈）',
        (t) async {
      await seedHl('f6', a: 2, b: 8, tag: BookQuote.kTagKey, at: 1000);
      await seedHl('f6', a: 12, b: 20, tag: BookQuote.kTagReso, at: 2000);
      await openReader(t, _shortDoc(), 'f6');
      final colA = _bg(BookQuote.kTagKey), colB = _bg(BookQuote.kTagReso);
      expect(painted(t).where((e) => e.c == colA), isNotEmpty, reason: '进屏时两条都在');
      expect(painted(t).where((e) => e.c == colB), isNotEmpty);
      // 长按段中（选字档＝命中单字）→ 选区在场，产品图1 的现场。
      final r = t.getRect(find.byKey(const ValueKey('brpTap-0-1')));
      await t.longPressAt(Offset(r.left + r.width * .5, r.top + r.height * .5));
      await step(t);
      expect(find.byKey(const ValueKey('brSelBar')), findsOne,
          reason: '前提＝选区浮条已出（选区在场）');
      final ps = painted(t);
      expect(ps.where((e) => e.c == colA).map((e) => e.t).join(),
          isNotEmpty,
          reason: '长按期间先划的那条必须照旧铺着（F-14＝它当时整段消失）');
      expect(ps.where((e) => e.c == colB).map((e) => e.t).join(),
          isNotEmpty,
          reason: '长按期间后划的那条也必须照旧铺着');
      expect(
        ps.where((e) => e.c == const Color(0x4D6366F1)).map((e) => e.t).join(),
        isNotEmpty,
        reason: '选区那一截仍要吃选区色（划线不许把选区盖掉）');
      await clearToasts(t);
    });

    testWidgets('⑤同段两条被拆到两页 → 每条只与本块求交，跨块不漏铺（§3H-A）',
        (t) async {
      // A 跨页（前块铺一头、后块铺另一头）；B 落在更靠后的那一页。
      const a0 = 50, a1 = 800, b0 = 850, b1 = 880;
      Future<void> seed(int a, int b, int at) async {
        await repo.addQuote(
          BookQuote(
            bookId: 'f5',
            kind: BookQuote.kKindMark,
            tag: BookQuote.kTagReso,
            body: _long.substring(a, b),
            chapter: '第一章',
            page: 1,
            cf: QuoteCf(c: 0, p0: 1, p1: 1, o0: a, o1: b),
            rid: 'r$at',
            origin: '阅读器',
            createdAt: at,
            updatedAt: at,
          ),
        );
      }
      await seed(a0, a1, 1000);
      await seed(b0, b1, 2000);
      await openReader(t, _longDoc(), 'f5');
      final col = _bg(BookQuote.kTagReso);
      final expected = _long.substring(a0, a1) + _long.substring(b0, b1);
      final pages = <String>[];
      var got = '';
      for (var i = 0; i < 12 && got.length < expected.length; i++) {
        final snap = paintedJoin(t, col);
        if (snap.isNotEmpty) {
          pages.add(snap);
          got += snap;
        }
        if (got.length >= expected.length) break;
        await flipR(t);
      }
      expect(got.length, lessThanOrEqualTo(expected.length),
          reason: '本块外的区间不许越界多铺（每块只吃与本块的交集）');
      expect(pages.length, greaterThan(1),
          reason: '前提＝该段确实被拆到多页，否则本例钉不到跨块求交');
      expect(got, expected,
          reason: '跨页的每一块都得铺到自己那一段交集，不重复不遗漏');
    });
    testWidgets('⑦删划线只删与选区相交的那条，不同段连坐（F-15 真机反馈）',
        (t) async {
      // A＝段首 4 字；B＝第 11 字起到末尾。两条同段不重叠。
      await seedHl('f7', a: 0, b: 4, tag: BookQuote.kTagKey, at: 1000);
      await seedHl('f7', a: 10, b: 26, tag: BookQuote.kTagReso, at: 2000);
      await openReader(t, _shortDoc(), 'f7');
      final colA = _bg(BookQuote.kTagKey), colB = _bg(BookQuote.kTagReso);
      expect(painted(t).where((e) => e.c == colA), isNotEmpty);
      expect(painted(t).where((e) => e.c == colB), isNotEmpty);

      Future<void> pressHead() async {
        final r = t.getRect(find.byKey(const ValueKey('brpTap-0-1')));
        await t.longPressAt(Offset(r.left + 12, r.top + 5));
        await step(t);
        expect(find.byKey(const ValueKey('brSelBar')), findsOne);
        await t.tap(find.byKey(const ValueKey('brSelHl')));
        await step(t);
        await t.tap(find.byKey(const ValueKey('brDelHl')));
        await step(t, ms: 300);
        // F2-11（LH-S31）：删划线先过统一二次确认（取消左 · 玫红右）；
        // 「没有划线可删」时不弹确认（_delHl 直接提示），故按需点确认。
        if (find.byKey(const ValueKey('d-confirm-ok')).evaluate().isNotEmpty) {
          await t.tap(find.byKey(const ValueKey('d-confirm-ok')));
          await step(t, ms: 300);
        }
      }

      // (a) 选区落在 A 那一截 → 只删 A，B 必须在库也在屏。
      await pressHead();
      expect(find.textContaining('已删除划线'), findsOne);
      await clearToasts(t);
      var qs = await repo.quotesOf('f7');
      expect(qs, hasLength(1), reason: '只该删掉与选区相交的那条（F-15＝两条一起没了）');
      expect(qs.single.tag, BookQuote.kTagReso, reason: '留下的必须是 B');
      final ps = painted(t);
      expect(ps.where((e) => e.c == colA), isEmpty, reason: 'A 已删，不该再铺色');
      expect(ps.where((e) => e.c == colB).map((e) => e.t).join(),
          _alpha.substring(10, 26), reason: 'B 必须整条照旧在');

      // (b) 选区落在没有划线的字上 → 一条都不许删。
      await pressHead();
      expect(find.textContaining('此处没有划线可删'), findsOne);
      await clearToasts(t);
      qs = await repo.quotesOf('f7');
      expect(qs, hasLength(1), reason: '不相交就不许连坐');
      expect(painted(t).where((e) => e.c == colB), isNotEmpty);
    });
  });
}
