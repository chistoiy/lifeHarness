import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/presentation/reader_pager.dart';

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
      final flat = wide.expand((e) => e).toList();
      expect(flat, List.generate(paras.length, (i) => i), reason: '段落不重不漏且有序');
      final narrow = EpubPager.layoutChapter(paras, _l(w: 260, h: 480));
      expect(narrow.length, greaterThan(wide.length));
    });

    test('空章回落一张空页（渲染层不越界）', () {
      final pages = EpubPager.layoutChapter(const [], _l());
      expect(pages, [<int>[]]);
    });

    test('超高单段独占一页且不丢段', () {
      final giant = _p(_lorem * 30);
      final paras = [_p('前段'), giant, _p('后段')];
      final pages = EpubPager.layoutChapter(paras, _l(h: 300));
      expect(pages.expand((e) => e).length, 3);
      expect(pages.any((pg) => pg.length == 1 && pg[0] == 1), isTrue);
    });
  });

  group('批2-P · BookPagination', () {
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

    test('字号↑ → 总页数↑（真实重排非估算）', () {
      final small = BookPagination.of(doc, _l(fs: 16));
      final big = BookPagination.of(doc, _l(fs: 28));
      expect(big.total, greaterThan(small.total));
      expect(small.chapterPages(0), greaterThan(1));
    });

    test('gPos/gPosTo 全书往返一致（跨章）', () {
      final pag = BookPagination.of(doc, _l());
      for (var g = 0; g < pag.total; g++) {
        final p = pag.gPosTo(g);
        expect(pag.gPos(p.ci, p.pg), g);
      }
      // 第二章首页的全局位置 = 第一章页数。
      expect(pag.gPosTo(pag.chapterPages(0)).ci, 1);
      expect(pag.gPosTo(pag.chapterPages(0)).pg, 0);
    });

    test('pct 单调且夹 0~100；末页为 100% 前置页递增', () {
      final pag = BookPagination.of(doc, _l());
      expect(pag.pct(0, 0), 0);
      expect(
        pag.pct(1, pag.chapterPages(1) - 1),
        greaterThan(pag.pct(0, 0)),
      );
      for (final p in [
        (0, 0),
        (0, 1),
        (1, 0),
      ]) {
        final v = pag.pct(p.$1, p.$2);
        expect(v, inInclusiveRange(0, 100));
      }
    });

    test('pageOfPara 与装箱表一致；越界段回落末页', () {
      final pag = BookPagination.of(doc, _l());
      final pages = pag.perChapter[0];
      expect(pag.pageOfPara(0, pages[1][0]), 1);
      expect(pag.pageOfPara(0, 9999), pages.length - 1);
    });
  });
}
