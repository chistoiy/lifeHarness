import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/read/data/epub_css.dart';
import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_pager.dart';

// 二期批5 · F5-2：段级测量缓存（key 全维度）＋ 溢出段只测一次。
// 独立文件防 isolate 污染；纯引擎层，不建库不起 app。
//
// 这批的两条硬口径：
//  ① 缓存 key 漏一维＝按 A 量按 B 画＝页底裁字/空页 ⇒ 逐维断言「键必须变」；
//  ② layoutChapter 里同一块**只允许布局一次**（旧写法溢出段先 pieceHeight 再
//     cutAfterLine，同一块测两遍）⇒ 用 debugMeasureCount 直接数。

EpubPara _p(String t, {List<EpubStyleRun> runs = const []}) =>
    EpubPara(kind: EpubParaKind.text, text: t, runs: runs);

ReaderLayout _l({
  double w = 400,
  double h = 700,
  double fs = 19,
  double lh = 1.62,
  double ls = 0.4,
  String font = 'serif',
  bool orig = false,
  bool indent = false,
  String indMode = 'none',
  String s2t = 'orig',
  double mar = 22,
}) => ReaderLayout(
  width: w,
  height: h,
  fs: fs,
  lh: lh,
  ls: ls,
  font: font,
  orig: orig,
  indent: indent,
  indMode: indMode,
  s2t: s2t,
  mar: mar,
);

const _lorem =
    '这是一段用于分页实测的中文正文，长度足够在默认字号下占据两到三行，'
    '重复若干次即可稳定地撑满一页。';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(EpubPager.debugResetMeasure);

  group('F5-2 · 段级键覆盖全部布局维度', () {
    test('换任一维度，键必须变（漏一维＝缓存串味）', () {
      final p = _p(_lorem);
      final base = EpubPager.debugPieceKey(p, _l(), 0, p.text.length);

      final variants = <String, Object>{
        // 段自身的排版输入
        '文本': EpubPager.debugPieceKey(_p('$_lorem。'), _l(), 0, p.text.length + 1),
        '段型': EpubPager.debugPieceKey(
          EpubPara(kind: EpubParaKind.heading, text: p.text, headingLevel: 1),
          _l(),
          0,
          p.text.length,
        ),
        '标题级别': EpubPager.debugPieceKey(
          EpubPara(kind: EpubParaKind.heading, text: p.text, headingLevel: 2),
          _l(),
          0,
          p.text.length,
        ),
        '注释体': EpubPager.debugPieceKey(
          EpubPara(kind: EpubParaKind.text, text: p.text, annotation: true),
          _l(),
          0,
          p.text.length,
        ),
        '原书缩进': EpubPager.debugPieceKey(
          EpubPara(kind: EpubParaKind.text, text: p.text, ownIndent: true),
          _l(),
          0,
          p.text.length,
        ),
        '段级样式': EpubPager.debugPieceKey(
          EpubPara(
            kind: EpubParaKind.text,
            text: p.text,
            style: const EpubStyle(indentEm: 2),
          ),
          _l(),
          0,
          p.text.length,
        ),
        '段内 runs': EpubPager.debugPieceKey(
          _p(
            p.text,
            runs: const [
              EpubStyleRun(start: 0, end: 2, style: EpubStyle(weight: 700)),
            ],
          ),
          _l(),
          0,
          p.text.length,
        ),
        // 布局维度
        '宽度': EpubPager.debugPieceKey(p, _l(w: 360), 0, p.text.length),
        '字号': EpubPager.debugPieceKey(p, _l(fs: 22), 0, p.text.length),
        '行距': EpubPager.debugPieceKey(p, _l(lh: 1.9), 0, p.text.length),
        '字距': EpubPager.debugPieceKey(p, _l(ls: 0.8), 0, p.text.length),
        '字族': EpubPager.debugPieceKey(p, _l(font: 'sans-serif'), 0, p.text.length),
        '跟随原书': EpubPager.debugPieceKey(p, _l(orig: true), 0, p.text.length),
        '缩进档': EpubPager.debugPieceKey(p, _l(indMode: 'auto'), 0, p.text.length),
        '简繁': EpubPager.debugPieceKey(p, _l(s2t: 's'), 0, p.text.length),
        '边距': EpubPager.debugPieceKey(p, _l(mar: 30), 0, p.text.length),
        // 块区间
        '起偏移': EpubPager.debugPieceKey(p, _l(), 1, p.text.length),
        '止偏移': EpubPager.debugPieceKey(p, _l(), 0, p.text.length - 1),
      };

      for (final e in variants.entries) {
        expect(
          e.value,
          isNot(equals(base)),
          reason: '「${e.key}」没进缓存 key：换了${e.key}仍命中旧高度＝按 A 量按 B 画',
        );
      }
      // 同一份输入必须等价（否则缓存永远不命中，等于没做）。
      expect(
        EpubPager.debugPieceKey(p, _l(), 0, p.text.length),
        equals(base),
      );
    });
  });

  group('F5-2 · 同一块只布局一次', () {
    test('重复量同一块＝命中缓存，不再布局', () {
      final p = _p(_lorem * 2);
      final l = _l();
      final h1 = EpubPager.pieceHeight(p, l, 0, p.text.length);
      expect(EpubPager.debugMeasureCount, 1);
      final h2 = EpubPager.pieceHeight(p, l, 0, p.text.length);
      expect(EpubPager.debugMeasureCount, 1, reason: '第二次必须命中缓存');
      expect(h2, h1);
      expect(EpubPager.measureCache.hits, 1);
    });

    test('溢出一页的段：每块只测一次（旧写法溢出段双测）', () {
      // 一段超长正文，必然切成多块续排。
      final p = _p(_lorem * 12);
      final l = _l(h: 300);
      final pages = EpubPager.layoutChapter([p], l);
      expect(pages.length, greaterThan(1), reason: '前提：这段确实跨页');
      final pieces = pages.fold<int>(0, (s, pg) => s + pg.length);
      expect(
        EpubPager.debugMeasureCount,
        pieces,
        reason: '块数=$pieces，布局次数=${EpubPager.debugMeasureCount}：'
            '多出来的就是「同一块测两遍」',
      );

      // 同一章再排一次（翻章重入/换页重试的真实路径）：全命中，零布局。
      final before = EpubPager.debugMeasureCount;
      final again = EpubPager.layoutChapter([p], l);
      expect(again.length, pages.length);
      expect(EpubPager.debugMeasureCount, before, reason: '第二次排序应全走缓存');
    });

    test('换字号重排不吃旧缓存（页数与块高都要变）', () {
      final p = _p(_lorem * 4);
      final small = EpubPager.layoutChapter([p], _l(fs: 16));
      final big = EpubPager.layoutChapter([p], _l(fs: 26));
      expect(
        big.length,
        greaterThan(small.length),
        reason: '字号变大页数必须变多——页数不变＝吃了旧缓存（按旧字号画新字号）',
      );
      // 每块高都必须 > 0（缓存串味最典型的表现是 0 高＝空页）。
      for (final pg in [...small, ...big]) {
        for (final b in pg) {
          expect(b.to, greaterThan(b.from));
        }
      }
    });
  });

  group('F5-2 · 缓存有界', () {
    test('超容量淘汰最久未用，容量不越界', () {
      final c = PieceMeasureCache(cap: 3);
      PieceMeasureKey k(int i) => PieceMeasureKey(['k$i', i]);
      for (var i = 0; i < 5; i++) {
        c.put(k(i), i.toDouble());
      }
      expect(c.size, 3);
      expect(c.get(k(0)), isNull, reason: '最早的已被淘汰');
      expect(c.get(k(1)), isNull);
      expect(c.get(k(4)), 4.0);
      // 命中刷新使用序：再次放入 k2 后，最久未用变成 k3。
      expect(c.get(k(2)), 2.0);
      c.put(k(9), 9.0);
      expect(c.get(k(3)), isNull, reason: 'k3 才是最久未用');
      expect(c.get(k(2)), 2.0);
    });
  });
}
