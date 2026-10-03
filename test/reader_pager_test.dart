import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_pager.dart';

// V1.50 批2 · 分页引擎（TextPainter 实测：字号/视口变化即时重排页数；
// 全局页往返；百分比与段→页映射）。独立文件防 isolate 污染。

EpubPara _p(String t) => EpubPara(kind: EpubParaKind.text, text: t);

EpubDoc _doc(List<EpubChapter> chapters) => EpubDoc(
  format: 'EPUB3',
  title: '分页书',
  author: '甲',
  toc: const [],
  chapters: chapters,
  imageCount: 0,
  totalChars: chapters.fold(0, (s, c) => s + c.charCount),
);

const _lorem =
    '这是一段用于分页实测的中文正文，长度足够在默认字号下占据两到三行，'
    '重复若干次即可稳定地撑满一页。';

ReaderLayout _l({double w = 400, double h = 700, double fs = 19}) =>
    ReaderLayout(width: w, height: h, fs: fs);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('批2-P · EpubPager 实测', () {
    test('paraHeight：字号越大段越高；插图固定 190', () {
      final p = _p(_lorem * 3);
      final small = EpubPager.paraHeight(p, _l(fs: 16));
      final big = EpubPager.paraHeight(p, _l(fs: 24));
      expect(big, greaterThan(small));
      expect(
        EpubPager.paraHeight(
          const EpubPara(kind: EpubParaKind.image, imgSrc: 'a.jpg'),
          _l(),
        ),
        190,
      );
    });

    test('layoutChapter：装箱完整有序；窄视口页数更多', () {
      final paras = List<EpubPara>.generate(60, (i) => _p('第$i段。$_lorem'));
      final wide = EpubPager.layoutChapter(paras, _l(w: 500, h: 900));
      final flat = [for (final pg in wide) for (final b in pg) b.pi];
      expect(flat, List.generate(paras.length, (i) => i), reason: '段落不重不漏且有序');
      final narrow = EpubPager.layoutChapter(paras, _l(w: 260, h: 480));
      expect(narrow.length, greaterThan(wide.length));
    });

    test('空章回落一张空页（渲染层不越界）', () {
      final pages = EpubPager.layoutChapter(const [], _l());
      expect(pages, <PagPage>[<PagPiece>[]]);
    });

    test('§3H-A 超高单段按行续排：每块装得下·拼起来不丢段', () {
      final giant = _p(_lorem * 30);
      final paras = [_p('前段'), giant, _p('后段')];
      final l = _l(h: 300);
      final pages = EpubPager.layoutChapter(paras, l);
      expect(pages.length, greaterThan(3), reason: '超高段没拆开＝页底继续裁字');
      final blocks = [for (final pg in pages) for (final b in pg) b]
          .where((b) => b.pi == 1)
          .toList();
      expect(blocks.length, greaterThan(1));
      for (final b in blocks) {
        expect(
          EpubPager.pieceHeight(paras[b.pi], l, b.from, b.to),
          lessThanOrEqualTo(l.contentH + .01),
        );
      }
      expect(
        blocks.map((b) => paras[1].text.substring(b.from, b.to)).join(),
        paras[1].text,
        reason: '续排丢字/重字',
      );
      final all = [for (final pg in pages) for (final b in pg) b.pi];
      expect(all.first, 0);
      expect(all.last, 2);
    });
  });

  group('轮4 · BookPagination（惰性表 + 字符权重）', () {
    final doc = _doc([
      EpubChapter(
        href: 'c1',
        title: '一章',
        paras: List.generate(40, (i) => _p('一之$i。$_lorem')),
      ),
      EpubChapter(
        href: 'c2',
        title: '二章',
        paras: List.generate(30, (i) => _p('二之$i。$_lorem')),
      ),
    ]);

    test('frac 沿阅读序单调；跨章按字符权重（未排版章也计权）', () {
      final pag = BookPagination.of(doc, _l());
      expect(pag.totalChars, doc.chapters.fold(0, (s, c) => s + c.charCount));
      final seq = <({int ci, int pg})>[];
      for (var ci = 0; ci < 2; ci++) {
        for (var pg = 0; pg < pag.chapterPages(ci); pg++) {
          seq.add((ci: ci, pg: pg));
        }
      }
      for (var i = 1; i < seq.length; i++) {
        expect(
          pag.frac(seq[i].ci, seq[i].pg),
          greaterThan(pag.frac(seq[i - 1].ci, seq[i - 1].pg)),
        );
      }
      expect(pag.frac(1, pag.chapterPages(1) - 1), closeTo(1.0, 1e-9));
      // 未排版章：占位 1 页，frac 仍按字符权重推进。
      final lazy = BookPagination.lazy([for (final c in doc.chapters) c.charCount]);
      expect(lazy.laidOut(0), isFalse);
      expect(lazy.chapterPages(0), 1);
      expect(lazy.frac(1, 0), greaterThan(lazy.frac(0, 0)));
    });

    test('fracTo 与 frac 往返（±1 页容差，章内需 ensure 后重夹）', () {
      final pag = BookPagination.of(doc, _l());
      for (var i = 0; i < 2; i++) {
        for (var pg = 0; pg < pag.chapterPages(i); pg++) {
          final t = pag.fracTo(pag.frac(i, pg));
          // 章内允许 ±1 页插值差；跨章错位 ≤1 章（章边界取整）。
          expect((t.ci - i).abs(), lessThanOrEqualTo(1));
          if (t.ci == i) expect((t.pg - pg).abs(), lessThanOrEqualTo(1));
        }
      }
      expect(pag.fracTo(0).ci, 0);
      expect(pag.fracTo(1.0), (ci: 1, pg: pag.chapterPages(1) - 1));
    });

    test('pct 夹 0~100 且随进度递增；末页 100%', () {
      final pag = BookPagination.of(doc, _l());
      expect(pag.pct(1, pag.chapterPages(1) - 1), 100);
      expect(
        pag.pct(1, pag.chapterPages(1) - 1),
        greaterThan(pag.pct(0, 0)),
      );
      expect(pag.pct(0, 0), inInclusiveRange(0, 100));
    });

    test('estTotal/gPosEst：约 1500 字/页估算，全局页随进度单调', () {
      final pag = BookPagination.of(doc, _l());
      expect(pag.estTotal, (pag.totalChars / 1500).ceil());
      final a = pag.gPosEst(0, 0);
      final b = pag.gPosEst(0, pag.chapterPages(0) - 1);
      final c = pag.gPosEst(1, pag.chapterPages(1) - 1);
      expect(a, lessThan(b));
      expect(b, lessThanOrEqualTo(c));
      expect(c, lessThanOrEqualTo(pag.estTotal));
    });

    test('pageOfPara 与装箱表一致；未排版章回落 0、越界段末页', () {
      final pag = BookPagination.of(doc, _l());
      final pages = pag.pages[0]!;
      expect(pag.pageOfPara(0, pages[1][0].pi), 1);
      expect(pag.pageOfPara(0, 9999), pages.length - 1);
      final lazy = BookPagination.lazy([2, 2]);
      expect(lazy.pageOfPara(0, 1), 0);
    });
  });
}
