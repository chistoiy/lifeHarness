// 工单 §3H 真机反馈轮2 的常驻回归（页底不裁字 ＋ 行距拉平）。
// 钉五件事：
//  ① 装箱用的可视高＝舞台真实高（视口高减顶部安全区，SafeArea 不再虚增一个状态栏）；
//  ② 测量与上屏同源（同一段的 pieceHeight 必须等于它上屏后的真实块高）；
//  ③ 比一页还高的段按行**跨页续排**：每块都装得下、拼起来＝整段、一个字不丢不重；
//  ④ 混字号段落逐行行盒等高（行距拉平），且外观「行距」滑杆真的改变段高；
//  ⑤ 落盘分页表载荷形状变了 → tableVersion 必须升（旧表整体失效，不许拿旧页画新书）。
// 独立文件防 isolate 污染；doc 经 epubDocLoaderProvider 直接手搓。
@TestOn('windows')
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/read/data/epub_cache.dart';
import 'package:lifeharness/features/read/data/epub_css.dart' show EpubStyle;
import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_page.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_pager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// 顶 inset 与真机同量级（ea028260＝134px/3.0＝44.67 逻辑）。
const _vpW = 400.0, _vpH = 320.0, _topPx = 134.0, _dpr = 3.0;

EpubPara _text(String t) => EpubPara(kind: EpubParaKind.text, text: t);

/// 一段 900 字的正文：在 320 高的视口里远超一页（contentH≈125），必须被拆开。
final _longPara = _text(List.generate(90, (i) => '智伯請地於韓康子$i').join());

EpubDoc _doc(List<EpubPara> paras) => EpubDoc(
  format: 'EPUB3',
  title: '复验书',
  author: '司馬光',
  toc: const [],
  chapters: [EpubChapter(href: 'c1', title: '卷一', paras: paras)],
  imageCount: 0,
  totalChars: paras.fold<int>(0, (s, p) => s + p.text.length),
);

/// 混字号段：正文大字里夹一段 0.75× 小字（通鉴夹注的形态）。
final _mixedDoc = _doc([
  const EpubPara(
    kind: EpubParaKind.text,
    text: '大字正文甲乙丙丁戊己庚辛壬癸子丑寅卯辰巳午未申酉戌亥天地玄黄宇宙洪荒日月盈昃',
    runs: [
      EpubStyleRun(
        start: 10,
        end: 26,
        style: EpubStyle(fontRatio: .75, color: Color(0xFF006400)),
      ),
    ],
  ),
]);

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  const l = ReaderLayout(width: _vpW, height: _vpH - _topPx / _dpr, font: 'serif');

  group('① 可视高口径', () {
    test('contentH 用的就是减掉顶安全区的高', () {
      // 装箱如果吃视口高，每页多塞 44.67px＝大半行（真机页底裁字的第一个根因）。
      expect(l.contentH, (_vpH - _topPx / _dpr - 22 - 40 - 22 - 46).toDouble());
      expect(
        ReaderLayout(width: 400, height: 900).contentH,
        greaterThan(l.contentH + _topPx / _dpr - .01),
      );
    });
  });

  group('②③ 超长段跨页续排', () {
    test('拆块：每块装得下·拼起来＝整段·不重不漏', () {
      final tab = EpubPager.layoutChapter([_longPara], l);
      expect(tab.length, greaterThan(1), reason: '900 字段在 125px 页高里必须拆开');
      final pieces = [for (final pg in tab) ...pg];
      expect(pieces.every((b) => b.pi == 0), isTrue);
      // 每块高度不超过可视高（＝不许再出现 RenderFlex 溢出）。
      for (final b in pieces) {
        expect(
          EpubPager.pieceHeight(_longPara, l, b.from, b.to),
          lessThanOrEqualTo(l.contentH + .01),
          reason: '块[${b.from},${b.to}) 仍超页高＝切点算错',
        );
      }
      // 首尾相接、覆盖整段（一个字符不丢、不重复）。
      expect(pieces.first.from, 0);
      expect(pieces.last.to, _longPara.text.length);
      for (var i = 1; i < pieces.length; i++) {
        expect(pieces[i].from, pieces[i - 1].to);
      }
      final joined =
          pieces.map((b) => _longPara.text.substring(b.from, b.to)).join();
      expect(joined, _longPara.text);
    });

    test('整段装得下时不拆（块＝0..段长，与旧行为逐字节一致）', () {
      final short = _text('短段。');
      final tab = EpubPager.layoutChapter([short], l);
      expect(tab.length, 1);
      expect(tab[0], [PagPiece(0, 0, short.text.length)]);
    });

    test('测量宽扣掉容器内边距（正文 -4 · 引文再 -14）', () {
      // 直接钉常数：上屏侧 wrap 横向 padding 与引文缩进一旦改动而测量侧没跟，
      // 行数就会两边不一致（真书实测多折 1911 行＝页底被挤出去的元凶之一）。
      expect(paraMeasureW(l, EpubParaKind.text), l.contentW - kBrPadWrapH * 2);
      expect(
        paraMeasureW(l, EpubParaKind.quote),
        l.contentW - kBrPadWrapH * 2 - kBrQuoteIndent,
      );
      expect(kBrQuoteLeft + kBrQuoteBarW, kBrQuoteIndent);
      expect(paraOuter(EpubParaKind.heading),
          kBrPadWrapV * 2 + kBrPadHeadTop + kBrPadHeadBottom);
    });

    test('paraSpan 的块区间与整段拼接同字（测量渲染同一张表）', () {
      final whole = paraSpan(_longPara, l.base).toPlainText();
      final head = paraSpan(_longPara, l.base, to: 300).toPlainText();
      final tail = paraSpan(_longPara, l.base, from: 300).toPlainText();
      expect(head + tail, whole);
      // 缩进前缀只在首块（否则续排页凭空多两个全角空格）。
      expect(head.startsWith(kParaIndent), isTrue);
      expect(tail.startsWith(kParaIndent), isFalse);
    });

    testWidgets('上屏真高＝pieceHeight（两边同源，改一处字面量必红）', (t) async {
      final repo = await _repo();
      final prefs = await _prefs();
      await _openPage(t, repo, prefs, _doc([_longPara]), 'fit1', pg: 0);
      final b = EpubPager.layoutChapter([_longPara], l)[0][0];
      final box = t.renderObject(find.byKey(ValueKey(
          'brp-0-${b.pi}${b.from == 0 ? '' : '-${b.from}'}'))) as RenderBox;
      expect(
        box.size.height,
        closeTo(EpubPager.pieceHeight(_longPara, l, b.from, b.to), .6),
        reason: '上屏块高与装箱用的块高不一致＝页底迟早裁字',
      );
    });

    testWidgets('渲染后不裁字：首块不被顶出容器·末块下沿不越过容器', (t) async {
      final repo = await _repo();
      final prefs = await _prefs();
      await _openPage(t, repo, prefs, _doc([_longPara]), 'fit2', pg: 0);
      // 页容器（带 padding 的 Container）扣掉自身内边距＝文字真正能占的矩形。
      final pageRect = t.getRect(find.byKey(const ValueKey('page-0-0')));
      final inner = Rect.fromLTRB(
        pageRect.left + 22,
        pageRect.top + 22 + kBrChromeTopPad,
        pageRect.right - 22,
        pageRect.bottom - 22 - kBrChromeBottomPad,
      );
      // 页内每一块都必须落在内框里＝没有块被顶出容器（裁字的直接判据）。
      for (final b in EpubPager.layoutChapter([_longPara], l)[0]) {
        final r = t.getRect(
          find.byKey(ValueKey('brp-0-0${b.from == 0 ? '' : '-${b.from}'}')),
        );
        expect(r.top, greaterThanOrEqualTo(inner.top - .6),
            reason: '块[${b.from}) 顶出容器');
        expect(r.bottom, lessThanOrEqualTo(inner.bottom + .6),
            reason: '块[${b.from},${b.to}) 底出容器＝页底裁字');
      }
      expect(t.takeException(), isNull);
    });
  });

  group('④ 行距拉平', () {
    test('混字号段逐行行盒等高（判定吃段级∪runs，样本非空）', () {
      final p = _mixedDoc.chapters[0].paras[0];
      // 档位数＝段级字号 ∪ 各 run 字号。此前只数 runs 会让「段级大字＋一个小字 run」
      // 被当成单一档直接 continue，用例空跑＝假绿（记忆教训：去重要数出现次数）。
      final sizes = <double>{
        paraFont(p, l.base, orig: true).fontSize ?? l.fs,
        for (final s2 in paraRunStyles(p, l.base, orig: true))
          s2.style.fontSize ?? l.fs,
      };
      expect(sizes.length, greaterThan(1), reason: '夹具没造出混字号＝这条白写');
      expect(paraMaxFont(p, l.base, orig: true), closeTo(l.fs, .01));
      final tp = TextPainter(
        text: paraSpan(p, l.base, orig: true),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: paraMeasureW(l, p.kind));
      final hs = {for (final m in tp.computeLineMetrics()) m.height};
      expect(hs.length, 1, reason: '同一段里大小字行高交替＝用户说的「显示不均匀」');
      expect(hs.first, closeTo(l.fs * l.lh, .5));
      // 小字档的倍数被反算放大（行盒＝最大字号×用户倍数）
      final small = paraRunStyles(p, l.base, orig: true)
          .firstWhere((x) => (x.style.fontSize ?? l.fs) < l.fs - .01)
          .style;
      expect(
        small.height! * small.fontSize!,
        closeTo(l.fs * l.lh, .5),
      );
    });

    test('原书 line-height 不再覆盖用户行距（滑杆必须动得了段高）', () {
      final p = EpubPara(
        kind: EpubParaKind.text,
        text: '通鉴形态：段级声明了很紧的行距的书。',
        style: const EpubStyle(lineRatio: 1.0, fontRatio: .6),
      );
      const tight = ReaderLayout(width: _vpW, height: _vpH, lh: 1.2, orig: true);
      const loose = ReaderLayout(width: _vpW, height: _vpH, lh: 2.0, orig: true);
      expect(
        EpubPager.paraHeight(p, loose),
        greaterThan(EpubPager.paraHeight(p, tight)),
        reason: '行距滑杆被原书声明盖住＝这本书里滑杆完全失效',
      );
      // 上屏样式里也不许再出现原书那个 1.0 倍数。
      expect(
        paraStyle(p, loose.base, orig: true).height,
        loose.lh,
      );
    });

    testWidgets('标题档：测量与上屏同字号（1.25× 不再只在上屏侧）', (t) async {
      final head = const EpubPara(
        kind: EpubParaKind.heading,
        text: '卷第一 周纪一',
      );
      final doc = _doc([head, _text('正文段。')]);
      final repo = await _repo();
      final prefs = await _prefs();
      await _openPage(t, repo, prefs, doc, 'fit3', pg: 0);
      expect(
        paraStyle(head, l.base).fontSize,
        l.fs * 1.25,
        reason: '标题字号档必须进测量，否则每条标题少算 1/4 行高',
      );
      // 上屏侧吃同一个数（不再两边各写一份）。
      final w = t.widget<Text>(
        find
            .descendant(
                of: find.byKey(const ValueKey('brpTap-0-0')),
                matching: find.byType(Text))
            .first,
      );
      // 标题走 Text(data)＋style（不是 rich），同源就体现在这个 style 上。
      final st = w.textSpan?.style ?? w.style!;
      expect(st.fontSize, l.fs * 1.25);
      expect(st.fontWeight, FontWeight.w800);
    });
  });

  group('⑤ 落盘表版本闸', () {
    test('块载荷形状变了 → tableVersion 已升', () {
      // v5＝页载荷从「段下标」升成「块（段＋区间）」；不升版＝旧表继续命中＝按旧页画新字。
      expect(PagStore.tableVersion, 5);
      final fp = PagStore.fingerprint(l);
      expect(fp, contains('${_vpW.round()}x${(_vpH - _topPx / _dpr).round()}'),
          reason: '视口口径变了要反映在指纹里（旧表自动不命中）');
    });

    test('块编解码往返（2 元组＝段首起，3 元组＝续排块）', () {
      for (final b in [PagPiece(3, 0, 88), PagPiece(3, 88, 900)]) {
        expect(PagPiece.decode(b.encode()), b);
      }
    });
  });
}

Future<ReadRepository> _repo() async {
  final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
  for (final sql in DbSchema.createStatements) {
    await db.execute(sql);
  }
  addTearDown(db.close);
  return ReadRepository(db);
}

Future<SharedPreferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

/// 进阅读主屏（视口/顶安全区按真机量级），并停在指定页。
Future<void> _openPage(
  WidgetTester t,
  ReadRepository repo,
  SharedPreferences prefs,
  EpubDoc doc,
  String id, {
  required int pg,
}) async {
  AppLog.reset();
  await repo.addBook(
    Book(
      id: id,
      title: '复验书',
      local: true,
      epub: const EpubRef(fmt: 'EPUB3', size: 10, path: 'mem'),
      createdAt: 1,
      updatedAt: 1,
    ),
  );
  await repo.setKv('reader.pos.$id', jsonEncode({'ci': 0, 'pg': pg}));
  await useSurface(t, const Size(_vpW, _vpH));
  t.view.devicePixelRatio = _dpr;
  t.view.padding = FakeViewPadding(top: _topPx);
  addTearDown(() {
    t.view.devicePixelRatio = 3.0;
    t.view.padding = FakeViewPadding();
  });
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        readRepositoryProvider.overrideWithValue(repo),
        sharedPreferencesProvider.overrideWithValue(prefs),
        epubDocLoaderProvider.overrideWithValue((_) async => doc),
      ],
      child: MaterialApp(home: ReaderPage(bookId: id)),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 220));
  }
  addTearDown(() => t.takeException());
}
