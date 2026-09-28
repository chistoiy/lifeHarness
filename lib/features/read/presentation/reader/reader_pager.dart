import 'package:flutter/material.dart';

import '../../data/epub_doc.dart';

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
    this.indent = true,
  });

  /// 舞台可视宽高（翻页模式内容盒）。
  final double width, height;
  final double fs, lh, ls, mar;
  final String font;

  /// 首行缩进开关（V1.53 轮3 字号面板；影响测量与渲染，必须进分页指纹）。
  final bool indent;

  double get contentW => (width - mar * 2).clamp(80.0, 10000.0);

  /// 上下让出 chrome 呼吸区（原型 padding mar+40 / mar+46）。
  double get contentH => (height - mar - 40 - mar - 46).clamp(120.0, 10000.0);

  /// 泛族字体（与 ReaderCfg.fontFamily 同映射；测量与渲染必须一致）。
  String? get fontFamily => switch (font) {
    'serif' => 'serif',
    'hei' => 'sans-serif',
    'mono' => 'monospace',
    _ => null,
  };

  TextStyle get base => TextStyle(
    fontSize: fs,
    height: lh,
    letterSpacing: ls,
    fontFamily: fontFamily,
  );

  ReaderLayout copyWith({
    double? fs,
    double? lh,
    double? ls,
    double? mar,
    String? font,
    bool? indent,
  }) => ReaderLayout(
    width: width,
    height: height,
    fs: fs ?? this.fs,
    lh: lh ?? this.lh,
    ls: ls ?? this.ls,
    mar: mar ?? this.mar,
    font: font ?? this.font,
    indent: indent ?? this.indent,
  );
}

/// 段首缩进 2em（原型 .brp text-indent:2em；两个全角空格的实测宽度恰为 2em）。
const String kParaIndent = '\u3000\u3000';

String paraDisplayText(EpubPara p, {bool indent = true}) =>
    p.kind == EpubParaKind.text && indent ? '$kParaIndent${p.text}' : p.text;

/// 分页引擎：TextPainter 真实测量（字号/行距/字距/边距变化 → 页数即时重排），
/// 非字符数估算（V1.50 硬约束「分页引擎实算」）。
class EpubPager {
  const EpubPager._();

  /// 单段块高（含原型间距口径：标题 +14 · 引文 +18 · 正文 +7 · 插图固定 190）。
  static double paraHeight(EpubPara p, ReaderLayout l) {
    if (p.kind == EpubParaKind.image) return 190;
    final tp = TextPainter(
      text: TextSpan(text: paraDisplayText(p, indent: l.indent), style: l.base),
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
/// 全书分页表（V1.53.1 轮4 · foliate-js 模型）：**按章懒排**，未排章节为 null；
/// 进度不再依赖全书页数——按章字符数加权插值（progress.js 的 SectionProgress 口径），
/// 2409 章合集打开/滑动/编辑书摘都不需要后台整本排版（真机卡顿根因）。
class BookPagination {
  BookPagination.lazy(List<int> charWeights)
    : w = List.unmodifiable(charWeights) {
    pages = List<List<List<int>>?>.filled(this.w.length, null);
    cum = List.filled(this.w.length + 1, 0);
    for (var i = 0; i < this.w.length; i++) {
      cum[i + 1] = cum[i] + this.w[i];
    }
  }

  /// 整本实算（测试/小书一次性路径）。
  factory BookPagination.of(EpubDoc doc, ReaderLayout l) {
    final p = BookPagination.lazy([
      for (final c in doc.chapters) c.charCount,
    ]);
    for (var i = 0; i < doc.chapters.length; i++) {
      p.pages[i] = EpubPager.layoutChapter(doc.chapters[i].paras, l);
    }
    return p;
  }

  /// 从落盘表直接构造（批3.5 分页表命中＝秒进；允许部分章为 null）。
  factory BookPagination.fromTable(
    List<int> charWeights,
    List<List<List<int>>?> pages,
  ) {
    final p = BookPagination.lazy(charWeights);
    for (var i = 0; i < pages.length && i < p.pages.length; i++) {
      p.pages[i] = pages[i];
    }
    return p;
  }

  /// 每章字符数（进度权重）。
  final List<int> w;
  /// 章 → 页 → 段下标；null＝该章未排版（按需实算后回填）。
  late final List<List<List<int>>?> pages;
  /// cum[i]＝前 i 章字符数前缀和。
  late final List<int> cum;

  int get chapterCount => w.length;
  int get totalChars => cum.isEmpty ? 0 : cum.last;

  bool laidOut(int ci) =>
      ci >= 0 && ci < pages.length && pages[ci] != null;
  void setChapter(int ci, List<List<int>> pg) => pages[ci] = pg;

  /// 章内页数（未排版章按 1 页占位，仅影响章内插值不影响章间权重）。
  int chapterPages(int ci) => pages[ci]?.length ?? 1;

  /// 进度 0~1：(前缀字符 + 章内按页插值) / 全书字符。
  double frac(int ci, int pg) {
    final tot = totalChars;
    if (tot <= 0) return 0;
    final c = ci.clamp(0, chapterCount - 1);
    final inCh = w[c] * ((pg + 1) / chapterPages(c));
    return ((cum[c] + inCh) / tot).clamp(0.0, 1.0);
  }

  int pct(int ci, int pg) => (frac(ci, pg) * 100).round().clamp(0, 100);

  /// 进度 0~1 → (章, 章内页)；落章后如该章未排版，调用方需 ensure 后重夹。
  ({int ci, int pg}) fracTo(double f) {
    final tot = totalChars;
    if (tot <= 0 || chapterCount == 0) return (ci: 0, pg: 0);
    final target = (f * tot).round().clamp(0, tot);
    var ci = 0;
    while (ci < chapterCount - 1 && cum[ci + 1] <= target) {
      ci++;
    }
    final wc = w[ci] == 0 ? 1 : w[ci];
    final within = (target - cum[ci]) / wc;
    final n = chapterPages(ci);
    return (ci: ci, pg: (within * n).round().clamp(0, n - 1));
  }

  /// 估算全书页数（foliate 口径：约 1500 字/页）——仅供「约第 X/Y 页」展示与书摘页码。
  int get estTotal => (totalChars / 1500).ceil().clamp(1, 1 << 30);
  int gPosEst(int ci, int pg) => (estTotal * frac(ci, pg)).round();

  /// 段落 pi 在该章的页号（检索命中跳转用；调用方须先 ensure 该章）。
  int pageOfPara(int ci, int pi) {
    final list = pages[ci];
    if (list == null) return 0;
    for (var p = 0; p < list.length; p++) {
      if (list[p].contains(pi)) return p;
    }
    return (list.length - 1).clamp(0, 1 << 30);
  }
}
