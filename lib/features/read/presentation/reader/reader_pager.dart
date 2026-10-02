import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart' show LhFontRole, lhFontRoleOfReaderFont;
import '../../data/epub_doc.dart';
import '../../domain/reader_cfg.dart';
import '../../domain/s2t_map.dart';

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
    this.font = 'serif', // 与 ReaderCfg 新默认同值（LH-F01）；生产恒走 ReaderLayout.of
    this.indent = true,
    this.indMode = 'auto',
    this.s2t = kS2TOrig,
  });

  /// 外观配置 → 分页布局（阅读主屏与整本预载**共用一条通道**：两处算法不同
  /// 会让预载表与实读表指纹对不上，等于白排一遍）。
  factory ReaderLayout.of(
    ReaderCfg c, {
    required double width,
    required double height,
  }) => ReaderLayout(
    width: width,
    height: height,
    fs: c.fs,
    lh: c.lh,
    ls: c.ls,
    mar: c.mar,
    font: c.font,
    // 以 indMode 为准换算 indent：ReaderCfg 的 const 构造不互推这两键（只有
    // fromMap/copyWith 会），直接吃 c.indent 会让「indMode:none + indent:true」
    // 这种手搓配置在分页与上屏两边各说各话。
    indent: c.indMode != 'none',
    indMode: c.indMode,
    s2t: c.s2t,
  );

  /// 舞台可视宽高（翻页模式内容盒）。
  final double width, height;
  final double fs, lh, ls, mar;
  final String font;

  /// 首行缩进开关（V1.53 轮3 字号面板；影响测量与渲染，必须进分页指纹）。
  final bool indent;

  /// 首行缩进三档（R3-2 ③ · 配置面 R3-7 交付）：auto 跟随原书 · 2 强制两全角 ·
  /// none 无缩进。它改变**每段的显示文本** → 必须进分页指纹，否则真机假生效。
  final String indMode;

  /// 简繁三档（R3-6 · 配置面批1 交付）：orig 跟随原书 · s 简体 · t 繁体。
  /// 它改的是**上屏文本内容**（逐字等长换字），与 indMode 同口径进分页指纹：
  /// 汉字同字号近等宽，但异体字在不同字族下度量会差（回退字体尤甚），
  /// 漏进指纹的代价是「切了繁简不重排＝真机假生效」，进指纹的代价只是一次重排。
  final String s2t;

  double get contentW => (width - mar * 2).clamp(80.0, 10000.0);

  /// 上下让出 chrome 呼吸区（原型 padding mar+40 / mar+46）。
  double get contentH => (height - mar - 40 - mar - 46).clamp(120.0, 10000.0);

  /// 字族角色（LH-F01）：与 `ReaderCfg.fontRole` 调**同一个函数**，
  /// 泛族串（'serif'/'sans-serif'）已换成与原型同串的中文字体链。
  LhFontRole? get fontRole => lhFontRoleOfReaderFont(font);
  String? get fontFamily => fontRole?.first;
  List<String>? get fontFamilyFallback => fontRole?.fallback;

  TextStyle get base => TextStyle(
    fontSize: fs,
    height: lh,
    letterSpacing: ls,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
  );

  ReaderLayout copyWith({
    double? fs,
    double? lh,
    double? ls,
    double? mar,
    String? font,
    bool? indent,
    String? indMode,
    String? s2t,
  }) => ReaderLayout(
    width: width,
    height: height,
    fs: fs ?? this.fs,
    lh: lh ?? this.lh,
    ls: ls ?? this.ls,
    mar: mar ?? this.mar,
    font: font ?? this.font,
    indent: indent ?? this.indent,
    indMode: indMode ?? this.indMode,
    s2t: s2t ?? this.s2t,
  );
}

/// 段首缩进 2em（原型 .brp text-indent:2em；两个全角空格的实测宽度恰为 2em）。
const String kParaIndent = '\u3000\u3000';

/// ① 注释/脚注体缩放与压暗系数（原型 .brp-fn font-size:.8em;opacity:.72）。
const double kAnnotationFsFactor = .8;
const double kAnnotationAlpha = .72;

/// ③ 该段是否加**我们的**两全角缩进——按段判定，不一刀切：
/// none 无缩进 · 2 强制两全角 · auto 跟随原书（书自带缩进的段不再叠加，
/// 这正是《資治通鑑》双重缩进的止血点）。判定源＝解析层 EpubPara.ownIndent。
bool paraIndented(EpubPara p, String indMode) =>
    p.kind == EpubParaKind.text &&
    switch (indMode) {
      'none' => false,
      '2' => true,
      _ => !p.ownIndent,
    };

/// 段正文的**上屏文本**（不含缩进前缀）＝原文过简繁转换器。
/// R3-6 单点通道：所有渲染与测量都从这里取字，一处转换一处画＝必错位；
/// 转换器逐字等长，所以原文偏移（选区/划线/链接命中/书摘切片）在这里仍然成立。
String paraBody(EpubPara p, String s2t) => S2t.convert(p.text, s2t);

/// 段上屏文本（含缩进前缀）。[indMode] 为 R3-7 三档口径；只给 [indent] 时按
/// 旧两档语义换算（true＝auto／false＝none），既有调用方零改动。
String paraDisplayText(
  EpubPara p, {
  bool indent = true,
  String? indMode,
  String s2t = kS2TOrig,
}) => paraIndented(p, indMode ?? (indent ? 'auto' : 'none'))
    ? '$kParaIndent${paraBody(p, s2t)}'
    : paraBody(p, s2t);

/// ① 注释体段落样式（正文色 + 小一号）。**测量与渲染共用同一函数**：只在分页
/// 器里缩字号、上屏不缩，就会「按小字算页、按大字画页」溢出/空页。
/// 正文与引文两类都算注释体；标题另有字号档（1.25×）不参与。
TextStyle paraStyle(EpubPara p, TextStyle base) {
  if (!p.annotation ||
      p.kind == EpubParaKind.heading ||
      p.kind == EpubParaKind.image) {
    return base;
  }
  return base.copyWith(
    fontSize: (base.fontSize ?? 19) * kAnnotationFsFactor,
    // base.color 为空（测量用的裸样式）时只缩字号，不凭空造色。
    color: base.color?.withValues(alpha: kAnnotationAlpha),
  );
}

/// ④ 外链（href 带 scheme 或跨章）＝链接色 + 下划线（原 accent 口径）。
TextStyle linkAccentStyle(TextStyle base) => base.copyWith(
  color: const Color(0xFF6366F1),
  decoration: TextDecoration.underline,
  decorationColor: const Color(0xFF6366F1).withValues(alpha: .7),
);

/// ④ 站内锚点＝正文色 + 下划线（原型 .br-link 只加下划线、颜色继承正文）。
TextStyle linkAnchorStyle(TextStyle base) => base.copyWith(
  decoration: TextDecoration.underline,
  decorationColor: (base.color ?? const Color(0xFF000000)).withValues(
    alpha: .55,
  ),
);

/// ① 段内注释/脚注引用（`<a epub:type="noteref">` 之类）＝正文色 + 小一号
/// （原型 .br-supn：color:inherit;font-size:.72em）——绝不套链接绿。
TextStyle noteRefStyle(TextStyle base) => base.copyWith(
  fontSize: (base.fontSize ?? 19) * kAnnotationFsFactor,
);

/// ④① 一个链接该用哪种样式（外链/站内锚点/注释引用的判定入口收在模型层
/// EpubLink.usesLinkColor，UI 只做分派）。
TextStyle linkStyleFor(TextStyle base, EpubLink l) => l.annotation
    ? noteRefStyle(base)
    : l.usesLinkColor
    ? linkAccentStyle(base)
    : linkAnchorStyle(base);

/// 分页引擎：TextPainter 真实测量（字号/行距/字距/边距变化 → 页数即时重排），
/// 非字符数估算（V1.50 硬约束「分页引擎实算」）。
class EpubPager {
  const EpubPager._();

  /// 单段块高（含原型间距口径：标题 +14 · 引文 +18 · 正文 +7 · 插图固定 190）。
  static double paraHeight(EpubPara p, ReaderLayout l) {
    if (p.kind == EpubParaKind.image) return 190;
    final tp = TextPainter(
      text: TextSpan(
        text: paraDisplayText(
          p,
          indent: l.indent,
          indMode: l.indMode,
          s2t: l.s2t,
        ),
        style: paraStyle(p, l.base),
      ),
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
    pages = List<List<List<int>>?>.filled(w.length, null);
    cum = List.filled(w.length + 1, 0);
    for (var i = 0; i < w.length; i++) {
      cum[i + 1] = cum[i] + w[i];
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
