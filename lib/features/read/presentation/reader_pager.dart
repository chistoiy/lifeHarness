import 'package:flutter/material.dart';

import '../data/epub_doc.dart';

/// 阅读排版参数（V1.50 批2 · 原型 BR_DEF 同源默认：fs19/lh1.62/ls0.4/mar22）。
@immutable
class ReaderLayout {
  const ReaderLayout({
    required this.width,
    required this.height,
    this.fs = 19,
    this.lh = 1.62,
    this.ls = 0.4,
    this.mar = 22,
    this.font = 'system',
  });

  /// 舞台可视宽高（翻页模式内容盒）。
  final double width, height;
  final double fs, lh, ls, mar;
  final String font;

  double get contentW => (width - mar * 2).clamp(80.0, 10000.0);

  /// 上下让出 chrome 呼吸区（原型 padding mar+40 / mar+46）。
  double get contentH => (height - mar - 40 - mar - 46).clamp(120.0, 10000.0);

  TextStyle get base => TextStyle(
    fontSize: fs,
    height: lh,
    letterSpacing: ls,
  );

  ReaderLayout copyWith({double? fs, double? lh, double? ls, double? mar}) =>
      ReaderLayout(
        width: width,
        height: height,
        fs: fs ?? this.fs,
        lh: lh ?? this.lh,
        ls: ls ?? this.ls,
        mar: mar ?? this.mar,
        font: font,
      );
}

/// 段首缩进 2em（原型 .brp text-indent:2em；两个全角空格的实测宽度恰为 2em）。
const String kParaIndent = '\u3000\u3000';

String paraDisplayText(EpubPara p) =>
    p.kind == EpubParaKind.text ? '$kParaIndent${p.text}' : p.text;

/// 分页引擎：TextPainter 真实测量（字号/行距/字距/边距变化 → 页数即时重排），
/// 非字符数估算（V1.50 硬约束「分页引擎实算」）。
class EpubPager {
  const EpubPager._();

  /// 单段块高（含原型间距口径：标题 +14 · 引文 +18 · 正文 +7 · 插图固定 190）。
  static double paraHeight(EpubPara p, ReaderLayout l) {
    if (p.kind == EpubParaKind.image) return 190;
    final tp = TextPainter(
      text: TextSpan(text: paraDisplayText(p), style: l.base),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: l.contentW);
    final gap = p.kind == EpubParaKind.heading
        ? 14.0
        : p.kind == EpubParaKind.quote
        ? 18.0
        : 7.0;
    return tp.height + gap;
  }

  /// 一章 → 页列表（页内段落下标），贪心装箱：段间 8，超高换页（同原型）。
  static List<List<int>> layoutChapter(List<EpubPara> paras, ReaderLayout l) {
    // 空章（纯封面/版权页可能无段）：给一张空页，渲染层零段落，不越界。
    if (paras.isEmpty) return const <List<int>>[<int>[]];
    final pages = <List<int>>[];
    var cur = <int>[];
    var h = 0.0;
    for (var i = 0; i < paras.length; i++) {
      final x = paraHeight(paras[i], l);
      final add = cur.isEmpty ? 0.0 : 8.0;
      if (h + add + x > l.contentH && cur.isNotEmpty) {
        pages.add(cur);
        cur = <int>[];
        h = 0;
      } else if (cur.isNotEmpty) {
        h += add;
      }
      cur.add(i);
      h += x;
    }
    if (cur.isNotEmpty) pages.add(cur);
    return pages;
  }
}

/// 全书分页表：章 → 页 → 段。全局页位置（进度条/百分比）以它换算。
class BookPagination {
  BookPagination.of(EpubDoc doc, ReaderLayout l)
    : perChapter = [for (final c in doc.chapters) EpubPager.layoutChapter(c.paras, l)];

  /// 从落盘表直接构造（批3.5 分页表命中＝秒进，不再实算）。
  BookPagination.fromTable(this.perChapter);

  final List<List<List<int>>> perChapter;

  int chapterPages(int ci) => perChapter[ci].length;

  int get total => perChapter.fold(0, (s, c) => s + c.length);

  /// (章,章内页) → 全书全局页。
  int gPos(int ci, int pg) {
    var g = 0;
    for (var i = 0; i < ci && i < perChapter.length; i++) {
      g += perChapter[i].length;
    }
    return g + pg;
  }

  /// 全书全局页 → (章, 章内页)。
  ({int ci, int pg}) gPosTo(int g) {
    var left = g;
    for (var i = 0; i < perChapter.length; i++) {
      final n = perChapter[i].length;
      if (left < n) return (ci: i, pg: left);
      left -= n;
    }
    final last = perChapter.length - 1;
    return (ci: last, pg: (perChapter[last].length - 1).clamp(0, 1 << 30));
  }

  /// 当前视图百分比（原型 brLivePct：全局页/总页 四舍五入夹 0~100）。
  int pct(int ci, int pg) =>
      (gPos(ci, pg) / total * 100).round().clamp(0, 100);

  /// 段落 pi 在该章的页号（检索命中跳转用）。
  int pageOfPara(int ci, int pi) {
    final pages = perChapter[ci];
    for (var p = 0; p < pages.length; p++) {
      if (pages[p].contains(pi)) return p;
    }
    return (pages.length - 1).clamp(0, 1 << 30);
  }
}
