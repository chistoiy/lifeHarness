import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart' show LhFontRole, lhFontRoleOfReaderFont;
import '../../data/epub_css.dart';
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
    this.orig = true,
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
    orig: c.orig,
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

  /// **跟随原书样式**（批三刀3，§5.4 拍板③）：开＝把 EPUB 自带 CSS 的声明叠在
  /// 用户主题之上，关＝一条都不读。它改变上屏排版 → 与 indMode/s2t 同口径进
  /// `PagStore.fingerprint`（漏进去＝切了开关不重排＝真机假生效）。
  final bool orig;

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

  /// 上下让出 chrome 呼吸区（原型 padding mar+40 / mar+46；常数与上屏侧同源，
  /// 见 [kBrChromeTopPad]）；高度另减顶部安全区，见 [brStageHeight]。
  double get contentH =>
      (height - mar - kBrChromeTopPad - mar - kBrChromeBottomPad).clamp(
        120.0,
        10000.0,
      );

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
    bool? orig,
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
    orig: orig ?? this.orig,
    indent: indent ?? this.indent,
    indMode: indMode ?? this.indMode,
    s2t: s2t ?? this.s2t,
  );
}

/// 舞台可视高＝视口高 − **顶部安全区**（工单 §3H-A 候选1）。
/// 阅读主屏的 `LayoutBuilder` 挂在 SafeArea **外**（热区/选区层要全屏坐标），
/// 正文舞台挂在 SafeArea **内**，所以两个高度不相等：装箱若吃视口高，
/// 每一页都多塞一个状态栏（真机 ea028260＝44.67px ≈ 大半行），
/// 页底最后一行被裁一半就是这么来的（2026-10-04 探针实测）。
/// 预载侧**必须走同一个函数**：两边算法不同＝分页指纹分叉＝预载白排。
double brStageHeight(BuildContext context, {required double viewportH}) =>
    viewportH - MediaQuery.paddingOf(context).top;

/// 段首缩进 2em（原型 .brp text-indent:2em；两个全角空格的实测宽度恰为 2em）。
const String kParaIndent = '\u3000\u3000';

/// **段外距的唯一口径**（工单 §3H-A 候选1/3 对账，2026-10-04）：
/// 这些数字上屏侧（`reader_stage._para` 的 Padding）与测量侧
/// （[EpubPager.paraHeight] / [EpubPager.pieceHeight]）**必须吃同一份常量**。
/// 此前两边各写一份字面量（测量给正文加 7、上屏实际吃掉 10；标题 14 对 30；
/// 引文 18 对 14），全书 34% 的页因此绘制高度＞可用高＝页底裁字。
const double kBrPadWrapV = 1.0, // wrap 容器上下各 1（划线/选区底色的呼吸）
    kBrPadWrapH = 2.0, // wrap 容器左右各 2（**会挤断行宽度**，测量必须扣）
    kBrPadTextBottom = 8.0, // 正文段底空隙（＝装箱的段间距，同一个数）
    kBrPadHeadTop = 16.0,
    kBrPadHeadBottom = 12.0,
    kBrPadQuoteBottom = 12.0,
    kBrPadImageBottom = 14.0,
    kBrQuoteLeft = 11.0, // 引文块左边距
    kBrQuoteBarW = 3.0, // 引文块竖线宽
    kBrImageBoxH = 190.0, // 插图固定块高（真图高按宽高比浮动，属已知挂账）
    kBrChromeTopPad = 40.0, // 页容器上让位（顶栏呼吸区，装箱同源）
    kBrChromeBottomPad = 46.0; // 页容器下让位（底栏呼吸区，装箱同源）

/// 引文块吃掉的有效行宽＝左边距＋竖线（测量宽度同源，见 [paraMeasureW]）。
const double kBrQuoteIndent = kBrQuoteLeft + kBrQuoteBarW;

/// 一段在上屏时除文字本体之外**额外占掉**的竖向空间。
double paraOuter(EpubParaKind k) => switch (k) {
  EpubParaKind.text => kBrPadWrapV * 2 + kBrPadTextBottom,
  EpubParaKind.heading => kBrPadWrapV * 2 + kBrPadHeadTop + kBrPadHeadBottom,
  EpubParaKind.quote => kBrPadWrapV * 2 + kBrPadQuoteBottom,
  // 插图分支不套 wrap（reader_stage 的 image case 直接是 Padding）
  EpubParaKind.image => kBrPadImageBottom,
};

/// 该型段落在上屏时**真正能用到的行宽**（＝舞台内容宽扣掉容器内边距与引文缩进）。
/// 测量按整幅宽、上屏被内边距吃掉 4px，实测通鉴因此多折 1911 行（§3H-A 候选3）。
double paraMeasureW(ReaderLayout l, EpubParaKind k) =>
    (l.contentW -
            kBrPadWrapH * 2 -
            (k == EpubParaKind.quote ? kBrQuoteIndent : 0))
        .clamp(40.0, 10000.0);

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

/// 原书色与**当前底色**的对比下限（预研 §3 调和规则：不达标先同色相调明度，
/// 再不行回落主题正文色；数值取 WCAG AA 正文 4.5）。
const double kOrigContrastMin = 4.5;

/// 同色相调明度的允许区间。超出就把原书色推成极端色了——
/// 宁回落主题正文色，也不画一个刺眼的假分层。
const double _kOrigLightLo = 0.15, _kOrigLightHi = 0.90;

/// WCAG 相对亮度（调和判据与用例共用同一算法，免得两边各测各的）。
/// 注意 [Color.r]/[Color.g]/[Color.b] 在 Flutter 3.32+ 是 **0~1 的 double**，不再除 255。
double _origLum(Color c) {
  double lin(double v) =>
      v <= 0.03928 ? v / 12.92 : _pow((v + 0.055) / 1.055, 2.4);
  return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
}

double _pow(double x, double e) => math.pow(x, e).toDouble();

double _origContrast(Color a, Color b) {
  final x = _origLum(a), y = _origLum(b);
  return ((x > y ? x : y) + 0.05) / ((x > y ? y : x) + 0.05);
}

/// **深色调和**（§5.4 拍板④／预研 §3）：原书色在 [bg] 上读不出来时，
/// 先保色相调明度（HSL 的 L——饱和度不动，但 L 推向两端时彩度自然回落，
/// 这正是通鉴 `color:navy` 在黑底上要变的东西），调不到 [kOrigContrastMin]
/// 就回落主题正文色 [fallback]（例如灰字压灰底，怎么调都糊）。
/// [bg] 为 null＝测量路径，不参与调和（色不影响度量）。
Color _origFgOn(Color fg, Color? bg, Color? fallback) {
  if (bg == null) return fg;
  if (_origContrast(fg, bg) >= kOrigContrastMin) return fg;
  final hsl = HSLColor.fromColor(fg);
  final up = _origLum(bg) <= 0.5; // 暗底往上提亮，亮底往下压暗
  for (var i = 1; i <= 40; i++) {
    final l = up
        ? hsl.lightness + i * 0.02
        : hsl.lightness - i * 0.02;
    if (l < _kOrigLightLo || l > _kOrigLightHi) break;
    final c = hsl.withLightness(l).toColor();
    if (_origContrast(c, bg) >= kOrigContrastMin) {
      return c.withValues(alpha: fg.a);
    }
  }
  return fallback ?? fg;
}

/// CSS 字重（100~900）→ Flutter 字重；认不了的值当没声明（调用方判空）。
FontWeight? _origWeight(int? w) => switch (w) {
  null => null,
  _ => FontWeight.values[((w / 100).round() - 1).clamp(0, 7)],
};

/// `text-decoration-style` / `border-*-style` → Flutter 线的形态。
/// 认不了的形态（`groove`/`inset` 这类要四个边的）回落实线——**能画成线**优先于画不出来。
TextDecorationStyle? _origDecoStyle(String? s) => switch (s) {
  null => null,
  'solid' => TextDecorationStyle.solid,
  'double' => TextDecorationStyle.double,
  'dotted' => TextDecorationStyle.dotted,
  'dashed' || 'dash' => TextDecorationStyle.dashed,
  'wavy' => TextDecorationStyle.wavy,
  _ => TextDecorationStyle.solid,
};

/// [EpubStyle] 有没有声明「线」（文本线或边线任一）。段级/区间级合并判定都取它。
bool _origDeclaresLine(EpubStyle st) =>
    st.underline ||
    st.overline ||
    st.lineThrough ||
    st.hasBorder ||
    st.lineColor != null ||
    st.deco != null;

/// 原书声明 → Flutter 文本样式（批三刀3 的唯一翻译口）。
///
/// 口径：**只改 [st] 声明过的字段**，其余原样保留 [base]——一条声明都没有时
/// 返回同一个对象（`same`），这样「零原书声明的书」在测量与渲染两边都不会变样。
/// 字号比 [EpubStyle.fontRatio] 乘的是**用户基准字号**（[ratioBase]，默认取 base 的字号；
/// 标题档已经自己乘过 1.25×，调用时把 ratioBase 传成基准字号，免得二次叠加）。
///
/// **能力边界（路线说明 §五.2，产品 2026-10-04 拍板）**：Flutter 文本模型没有内联盒，
/// 画不出四边框——`border-left/right/bottom` 一律落成**下划线**、`border-top` 落**上划线**，
/// 这条近似已经由抽取器记进 `EpubDoc.unsupported` 并在该书外观页提示（不静默）。
TextStyle applyOrigStyle(
  TextStyle base,
  EpubStyle? st, {
  Color? pageBg,
  double? ratioBase,
}) {
  if (st == null || st.isEmpty) return base;
  var s = base;
  // 底色声明一起判（`.ji` 白字灰底禁直接压黑底）：有底色块时，字色的对比按**块**算。
  var bg = pageBg;
  if (st.backgroundColor != null) {
    s = s.copyWith(backgroundColor: st.backgroundColor);
    bg = st.backgroundColor;
  }
  if (st.color != null) {
    s = s.copyWith(color: _origFgOn(st.color!, bg, s.color));
  }
  if (st.fontRatio != null) {
    s = s.copyWith(fontSize: (ratioBase ?? base.fontSize ?? 19) * st.fontRatio!);
  }
  if (st.weight != null) {
    final w = _origWeight(st.weight);
    if (w != null) s = s.copyWith(fontWeight: w);
  }
  if (st.italic) s = s.copyWith(fontStyle: FontStyle.italic);
  // 原书 `line-height` **不再覆盖行距**（工单 §3H-B 拍板，2026-10-04 产品选「行距拉平」）：
  // 通鉴全书 36064/36065 段声明了 line-height，一旦照吃，外观里的「行距」滑杆
  // 对这本书就彻底失效（实测滑杆不动、字号滑杆照动）——行距归属定为「用户优先」。
  // 声明本身仍由抽取层保留（EpubStyle.lineRatio 是画像证据），消费面在此止住。
  if (!_origDeclaresLine(st)) return s;
  // 边线→文本线的通用映射（上面的能力边界）；形态取** contributing 边线**自己的，
  // 缺省回落段级 deco（书名线的 gif 平铺线在刀2 已通用回落成 wavy）。
  final under = st.underline ||
      st.borderLeft?.isLine == true ||
      st.borderRight?.isLine == true ||
      st.borderBottom?.isLine == true;
  final over = st.overline || st.borderTop?.isLine == true;
  final decos = <TextDecoration>[
    if (under) TextDecoration.underline,
    if (over) TextDecoration.overline,
    if (st.lineThrough) TextDecoration.lineThrough,
  ];
  if (decos.isEmpty) return s;
  final border = st.borderLeft ??
      st.borderRight ??
      st.borderBottom ??
      st.borderTop;
  final fs = s.fontSize ?? base.fontSize ?? 19;
  final widthPx = border?.widthEm != null
      ? border!.widthEm! * fs
      : border?.widthPx;
  return s.copyWith(
    decoration: TextDecoration.combine(decos),
    // 边色缺省＝跟字色（通鉴 `.name` 就是这个形态）。
    decorationColor: st.lineColor ?? border?.color ?? s.color,
    decorationStyle: _origDecoStyle(border?.style ?? st.deco),
    decorationThickness: widthPx == null
        ? null
        : (widthPx / (fs * 0.05)).clamp(0.5, 4.0),
  );
}

/// 把原书声明逐字段叠在 [stop] 上：**声明过的**用 [declared]，没声明的原样保留。
/// （不能直接 `copyWith` 整个 [declared]——它的未声明字段带的是 base 值，
/// 会把止血口径算好的注释体小字/压暗悄悄盖掉。）
TextStyle _origOnto(TextStyle stop, TextStyle declared, EpubStyle st) {
  var s = stop;
  if (st.color != null) s = s.copyWith(color: declared.color);
  if (st.backgroundColor != null) {
    s = s.copyWith(backgroundColor: declared.backgroundColor);
  }
  if (st.fontRatio != null) s = s.copyWith(fontSize: declared.fontSize);
  if (st.weight != null) s = s.copyWith(fontWeight: declared.fontWeight);
  if (st.italic) s = s.copyWith(fontStyle: declared.fontStyle);
  // lineRatio 同 applyOrigStyle：行距归用户滑杆（§3H-B 拍板），原书声明只留数据不上屏。
  if (_origDeclaresLine(st)) {
    s = s.copyWith(
      decoration: declared.decoration,
      decorationColor: declared.decorationColor,
      decorationStyle: declared.decorationStyle,
      decorationThickness: declared.decorationThickness,
    );
  }
  return s;
}

/// 标题段的字号档：原书声明了字号比就以原书为准（§5.4 拍板「完全按原书展示」），
/// 没声明走我们自己的 1.25×。**测量与上屏都从这里取**——此前上屏自建 1.25×、
/// 测量按基准字号量，每条标题少算约 1/4 行高（工单 §3H-A 对账新收的一条）。
double headingFontRatio(EpubPara p, bool orig) =>
    orig && p.style?.fontRatio != null ? p.style!.fontRatio! : 1.25;

/// ① 注释体段落样式（正文色 + 小一号）；[orig] 开时**原书声明优先**、
/// 未声明的属性仍走止血口径（§5.4 拍板：`.comment` 蓝＋1rem 压过 R3-2①）。
/// **测量与渲染共用同一函数**：只在分页器里缩字号、上屏不缩，
/// 就会「按小字算页、按大字画页」溢出/空页。
/// 正文与引文两类都算注释体；标题走 [headingFontRatio] 的字号档＋加粗，不参与注释体。
TextStyle paraStyle(
  EpubPara p,
  TextStyle base, {
  bool orig = false,
  Color? pageBg,
}) =>
    _flattenLineHeight(
      paraFont(p, base, orig: orig, pageBg: pageBg),
      base,
      p,
      orig,
    );

/// 段落**字面**样式（字号档/注释体/原书声明都叠完，但**不做行高归一**）。
/// 拆出来是给 [paraMaxFont] 用——归一要先知道全段最大字号，而最大字号不能吃归一后的值。
TextStyle paraFont(
  EpubPara p,
  TextStyle base, {
  bool orig = false,
  Color? pageBg,
}) {
  // 标题档（§3H-A 收口）：字号档与字重都进测量——字重会影响西文与数字的字宽。
  final head = p.kind == EpubParaKind.heading
      ? base.copyWith(
          fontSize: (base.fontSize ?? 19) * headingFontRatio(p, orig),
          fontWeight: FontWeight.w800,
        )
      : base;
  final stop = !p.annotation ||
          p.kind == EpubParaKind.heading ||
          p.kind == EpubParaKind.image
      ? head
      : head.copyWith(
          fontSize: (head.fontSize ?? 19) * kAnnotationFsFactor,
          // base.color 为空（测量用的裸样式）时只缩字号，不凭空造色。
          color: head.color?.withValues(alpha: kAnnotationAlpha),
        );
  // 注意：这里**不做行高归一**——paraMaxFont→paraFont→归一 会互相递归炸栈，
  // 归一只在 paraStyle 出口做一次（§3H-B）。
  final st = p.style;
  if (!orig || st == null || st.isEmpty) return stop;
  return _origOnto(stop, applyOrigStyle(base, st, pageBg: pageBg), st);
}

/// **行距拉平**（工单 §3H-B 拍板，2026-10-04 产品选路）。
/// Flutter 与浏览器一样：行盒取**该行最大字号**乘各自倍数——通鉴 82% 的段落内部混着
/// 19px 正文与 14.3px 夹注，同一段里 29px／21px 交替（样包实测：抽样 310 个混字号段
/// 有 233 段行高不齐），这就是用户说的「显示不均匀」。
/// 口径＝**本段每一行的行盒都等于「本段最大字号 × 用户行距倍数」**：把每个字档的
/// `height` 反算成 `maxFs × lh ÷ 本档字号`，行盒自然齐平。
/// 不用 `StrutStyle.forceStrutHeight`：真书实测拉不平（混字号行的行盒仍按内容取大值）。
/// 行距倍数只认外观滑杆（原书 `line-height` 不再覆盖，见 [applyOrigStyle] 内注释）。
double paraMaxFont(EpubPara p, TextStyle base, {bool orig = false}) {
  var m = paraFont(p, base, orig: orig).fontSize ?? base.fontSize ?? 19;
  if (!orig) return m;
  final st = p.style;
  if (st?.fontRatio != null) {
    final f = (base.fontSize ?? 19) * st!.fontRatio!;
    if (f > m) m = f;
  }
  for (final r in p.runs) {
    if (r.style.fontRatio == null) continue;
    final f = (base.fontSize ?? 19) * r.style.fontRatio!;
    if (f > m) m = f;
  }
  return m;
}

TextStyle _flattenLineHeight(
  TextStyle s,
  TextStyle base,
  EpubPara p,
  bool orig,
) {
  final lh = base.height;
  if (lh == null) return s;
  final fs = s.fontSize ?? base.fontSize ?? 19;
  final maxFs = paraMaxFont(p, base, orig: orig);
  if (maxFs <= fs) return s.copyWith(height: lh);
  return s.copyWith(height: maxFs * lh / fs);
}

/// 段内一个显示区间的样式（[paraRunStyles] 的返回值）。
/// 坐标与 [EpubPara.text] 同系（折叠空白后的 UTF-16 码位），
/// 与 [EpubPara.links]／划线／书摘偏移一致；简繁转换器逐字等长，转换后仍对齐。
@immutable
class EpubRunSegment {
  const EpubRunSegment({
    required this.start,
    required this.end,
    required this.style,
  });

  final int start, end;
  final TextStyle style;
}

/// runs → 分段样式表（批三刀3 · **测量与渲染共用这张表**，预研 §3 同源红线）。
/// 无缝覆盖 `[0, text.length)`：runs 之间的空隙用段级样式填，
/// 这样 [EpubPager.paraHeight] 与 `reader_chrome._textSpan` 拿到的是同一份分段。
List<EpubRunSegment> paraRunStyles(
  EpubPara p,
  TextStyle base, {
  bool orig = false,
  Color? pageBg,
}) {
  final para = paraStyle(p, base, orig: orig, pageBg: pageBg);
  final n = p.text.length;
  if (!orig || p.runs.isEmpty) {
    return [EpubRunSegment(start: 0, end: n, style: para)];
  }
  final out = <EpubRunSegment>[];
  var cur = 0;
  void gap(int to) {
    if (to <= cur) return;
    out.add(EpubRunSegment(start: cur, end: to, style: para));
    cur = to;
  }

  for (final r in p.runs) {
    final s = r.start.clamp(0, n), e = r.end.clamp(s, n);
    if (e <= cur) continue; // runs 应有序不重叠；乱序/重叠按先到者裁
    gap(s);
    out.add(
      EpubRunSegment(
        start: s,
        end: e,
        // 区间样式也过一遍行高归一：小字档的倍数被放大到「与本段最大字号同高」，
        // 于是整段每行行盒相等（§3H-B 行距拉平）。
        style: _flattenLineHeight(
          _origOnto(para, applyOrigStyle(base, r.style, pageBg: pageBg), r.style),
          base,
          p,
          orig,
        ),
      ),
    );
    cur = e;
  }
  gap(n);
  return out;
}

/// 段 → **选中态**上屏 span（轮4③ 两条约定原样保留：缩进前缀恒按段级样式渲染在最前、
/// 高亮只包子串本体不吞缩进）。批三真机反馈（2026-10-04 图1→图2）：选中态也必须吃
/// [paraRunStyles] 这张分段表——否则《資治通鑑》一长按选字，整段原书绿小字塌回
/// 主题黑大字，「选一下样式就变」在用户眼里就是 bug。底色只叠在与选区相交的那截上。
/// F-14（2026-10-07 真机反馈）：[hlSpans]＝段内已入库划线的精确区间，**长按选区在场时
/// 也要照铺**——旧口径靠 Container 整段浅底兜，改成多区间后若不在这里铺，选区一按下去
/// 已有划线就地消失（用户读成「划线被选区吃掉了」）。选区带本身仍吃 [selBg]（选区优先）。
TextSpan paraSelectionSpan(
  EpubPara p,
  TextStyle base, {
  bool orig = false,
  Color? pageBg,
  String indMode = 'auto',
  String s2t = kS2TOrig,
  required int a,
  required int b,
  int from = 0,
  int? to,
  Color? selBg, // F3-3：调用方传 tokens.accent 派生值（不传＝旧巻0x4D6366F1 兼容）
  List<({int a, int b, Color c})> hlSpans = const [],
}) {
  final para = paraStyle(p, base, orig: orig, pageBg: pageBg);
  final body = paraBody(p, s2t);
  final n = body.length;
  final cutA = from.clamp(0, n), cutB = (to ?? n).clamp(cutA, n);
  final pre = cutA == 0 && paraIndented(p, indMode) ? kParaIndent : '';
  final lo = math.max(a.clamp(0, n), cutA), hi = math.min(b.clamp(0, n), cutB);
  final kids = <InlineSpan>[
    if (pre.isNotEmpty) TextSpan(text: pre, style: para),
  ];
  // F-14：把 [x0,x1) 按划线区间切开逐截铺底；重叠处取**列表靠后**那条（＝最新），
  // 与 `_textSpan` 同一口径（F-13 步骤2），不许整段抹掉前一条。
  void addHlPainted(int x0, int x1, TextStyle Function(int at) stAt) {
    var cur = x0;
    while (cur < x1) {
      Color? bg;
      var coverEnd = x1;
      for (final sp in hlSpans) {
        if (sp.a <= cur && cur < sp.b) {
          bg = sp.c;
          coverEnd = sp.b < x1 ? sp.b : x1;
        }
      }
      if (bg == null) {
        var nx = x1;
        for (final sp in hlSpans) {
          if (cur < sp.a && sp.a < nx) nx = sp.a;
        }
        if (nx <= cur) nx = x1;
        kids.add(TextSpan(text: body.substring(cur, nx), style: stAt(cur)));
        cur = nx;
      } else {
        kids.add(
          TextSpan(
            text: body.substring(cur, coverEnd),
            style: stAt(cur).copyWith(
              backgroundColor: bg.withValues(alpha: .27),
            ),
          ),
        );
        cur = coverEnd;
      }
    }
  }

  for (final seg in paraRunStyles(p, base, orig: orig, pageBg: pageBg)) {
    // 块裁剪（§3H-A 拆页）：本块只画 [cutA,cutB)，选区 [lo,hi) 已经同样夹过。
    final s0 = math.max(seg.start, cutA), s1 = math.min(seg.end, cutB);
    if (s1 <= s0) continue; // 整截在别的页上
    if (s1 <= lo || s0 >= hi) {
      addHlPainted(s0, s1, (_) => seg.style);
      continue; // 整截都在选区外：原样式照上（划线底色仍在，F-14）
    }
    if (s0 < lo) addHlPainted(s0, lo, (_) => seg.style);
    final x0 = math.max(s0, lo), x1 = math.min(s1, hi);
    if (x1 > x0) {
      kids.add(
        TextSpan(
          text: body.substring(x0, x1),
          style: seg.style.copyWith(
            backgroundColor: selBg ?? const Color(0x4D6366F1),
          ),
        ),
      );
    }
    if (s1 > hi) addHlPainted(hi, s1, (_) => seg.style);
  }
  return TextSpan(style: para, children: kids);
}

/// 段 → 上屏用的富文本 span（**测量与渲染共用的唯一出口**：[EpubPager.paraHeight]、
/// 引文块、正文事件流都从这张分段表取字取样式；两处各拼一份必分叉＝空页/错页）。
/// 缩进前缀恒按段级样式渲染在最前（轮4③ 真机口径），不参与 runs 分段。
/// [from]/[to]＝**段内字符区间**（工单 §3H-A：一段比一页还高时要跨页续排，
/// 每页只画这一段的其中一截）。坐标始终是原文坐标（与链接/划线/书摘同一系），
/// 只有 `from==0` 的那一截才带缩进前缀。
TextSpan paraSpan(
  EpubPara p,
  TextStyle base, {
  bool orig = false,
  Color? pageBg,
  String indMode = 'auto',
  String s2t = kS2TOrig,
  int from = 0,
  int? to,
}) {
  final para = paraStyle(p, base, orig: orig, pageBg: pageBg);
  final body = paraBody(p, s2t);
  final n = body.length;
  final a = from.clamp(0, n), b = (to ?? n).clamp(a, n);
  final pre = a == 0 && paraIndented(p, indMode) ? kParaIndent : '';
  return TextSpan(
    style: para,
    children: <InlineSpan>[
      if (pre.isNotEmpty) TextSpan(text: pre, style: para),
      for (final s in paraRunStyles(p, base, orig: orig, pageBg: pageBg))
        if (s.end > a && s.start < b)
          TextSpan(
            text: body.substring(
              s.start > a ? s.start : a,
              s.end < b ? s.end : b,
            ),
            style: s.style,
          ),
    ],
  );
}

/// ④ 外链（href 带 scheme 或跨章）＝链接色 + 下划线（原 accent 口径）。
/// F3-3：[accent] 由调用方传 tokens.accent（不传＝旧固定靛蓝兼容）。
TextStyle linkAccentStyle(TextStyle base, {Color? accent}) => base.copyWith(
  color: accent ?? const Color(0xFF6366F1),
  decoration: TextDecoration.underline,
  decorationColor:
      (accent ?? const Color(0xFF6366F1)).withValues(alpha: .7),
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
TextStyle linkStyleFor(TextStyle base, EpubLink l, {Color? accent}) => l.annotation
    ? noteRefStyle(base)
    : l.usesLinkColor
    ? linkAccentStyle(base, accent: accent)
    : linkAnchorStyle(base);

/// 页内一块＝段下标 ＋ 该段**上屏的字符区间** `[from,to)`（整段＝0..段长）。
/// 工单 §3H-A：真机样包《資治通鑑》实测 **4.5% 的段落比一整页还高**（最长约 4958px＝
/// 页高的 6 倍），旧模型「放不下就整段独占一页」对它无解——独占照样溢出 345px，
/// 页底那一行就被裁一半。现在这种段按**行**切开续排到后续页。
/// 坐标一律是**原文坐标**（与链接/划线/书摘/选区同一坐标系，页坐标不许渗进库）。
@immutable
class PagPiece {
  const PagPiece(this.pi, this.from, this.to);

  final int pi, from, to;

  /// 落盘载荷：`[pi,to]`＝从段首起（绝大多数块，省一个数）；`[pi,from,to]`＝续排块。
  /// 用长度分流＝没有歧义（`from==0` 的截断块也走两元组，`to` 照实记）。
  List<int> encode() =>
      from == 0 ? <int>[pi, to] : <int>[pi, from, to];

  static PagPiece decode(List<dynamic> j) => j.length >= 3
      ? PagPiece(
          (j[0] as num).toInt(),
          (j[1] as num).toInt(),
          (j[2] as num).toInt(),
        )
      : PagPiece((j[0] as num).toInt(), 0, (j[1] as num).toInt());

  // 值相等：落盘表往返、懒排合并、用例断言都按「同一块」比对，不比对象身份。
  @override
  bool operator ==(Object other) =>
      other is PagPiece &&
      other.pi == pi &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(pi, from, to);

  @override
  String toString() => '#$pi:$from..$to';
}

typedef PagPage = List<PagPiece>;
typedef PagChapter = List<PagPage>;

/// 分页引擎：TextPainter 真实测量（字号/行距/字距/边距变化 → 页数即时重排），
/// 非字符数估算（V1.50 硬约束「分页引擎实算」）。
class EpubPager {
  const EpubPager._();

  /// 段内一块 `[from,to)` 的**上屏高度**＝文字本体 ＋ 该型段的段外距（[paraOuter]）。
  /// 批三刀3：吃 [paraRunStyles] 的分段表——em 字号进 span 之后，
  /// 「按平文本量、按 span 树画」必出空页，两边走一张表才叫同源（预研 §3 红线）。
  /// §3H-A 同源补刀：宽度按 [paraMeasureW]（扣容器内边距）、外距按 [paraOuter]、
  /// 行盒走 [_flattenLineHeight]（§3H-B 行距拉平）——**装箱、拆分、上屏三处唯一的数**。
  static double pieceHeight(EpubPara p, ReaderLayout l, int from, int to) {
    // 插图＝固定 190 估计（真图高按宽高比浮动＝§3H 已知挂账，另批处理）；
    // 数值维持旧口径，这一批不同时改两处语义。
    if (p.kind == EpubParaKind.image) return kBrImageBoxH;
    final tp = TextPainter(
      // 测量路径不传 pageBg＝原书色不参与调和（色不影响度量），
      // 但**分段表与上屏同一张**（字号比会改行高，两边必须一致）。
      text: paraSpan(
        p,
        l.base,
        orig: l.orig,
        indMode: l.indMode,
        s2t: l.s2t,
        from: from,
        to: to,
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: paraMeasureW(l, p.kind));
    return tp.height + paraOuter(p.kind);
  }

  /// 单段块高（整段）。
  static double paraHeight(EpubPara p, ReaderLayout l) =>
      pieceHeight(p, l, 0, p.text.length);

  /// 在 `[from, 段尾)` 里找**当前页剩余高 avail 放得下的最后一个行首**（原文坐标）。
  /// 按行度量累计，切点一定落在行与行之间＝两页都不裁半行。
  static int cutAfterLine(EpubPara p, ReaderLayout l, int from, double avail) {
    final n = p.text.length;
    if (from >= n) return n;
    final ind = from == 0 && paraIndented(p, l.indMode) ? kParaIndent.length : 0;
    final tp = TextPainter(
      text: paraSpan(
        p,
        l.base,
        orig: l.orig,
        indMode: l.indMode,
        s2t: l.s2t,
        from: from,
        to: n,
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: paraMeasureW(l, p.kind));
    final budget = avail - paraOuter(p.kind);
    var top = 0.0, cutDisp = 0;
    for (final m in tp.computeLineMetrics()) {
      if (top + m.height > budget) break;
      top += m.height;
      // 下一行的行首（显示坐标）；末行时取到段尾，调用方按 from 兜底推进。
      cutDisp = tp.getPositionForOffset(Offset(0, top + 0.5)).offset;
    }
    tp.dispose();
    if (cutDisp < ind) cutDisp = ind; // 绝不在缩进前缀里切
    final body = (cutDisp - ind) + from;
    return body <= from ? from + 1 : body.clamp(from + 1, n);
  }

  /// 一章 → 页列表（页内是**块**）。贪心装箱：每块自带段外距（段间空隙＝正文段的
  /// 段底 8，见 [paraOuter]，不再另加），超高换页；**换页后仍放不下的段按行切开续排**。
  static PagChapter layoutChapter(List<EpubPara> paras, ReaderLayout l) {
    // 空章（纯封面/版权页可能无段）：给一张空页，渲染层零块，不越界。
    if (paras.isEmpty) return <PagPage>[<PagPiece>[]];
    final pages = <PagPage>[];
    var cur = <PagPiece>[];
    var h = 0.0;
    void flush() {
      if (cur.isEmpty) return;
      pages.add(cur);
      cur = <PagPiece>[];
      h = 0;
    }

    for (var i = 0; i < paras.length; i++) {
      final p = paras[i];
      final n = p.text.length;
      var from = 0;
      while (true) {
        final rest = pieceHeight(p, l, from, n);
        final avail = l.contentH - h;
        if (cur.isNotEmpty && rest > avail) {
          flush(); // 先换页，再在整页高度上重试这一块
          continue;
        }
        if (rest <= avail || p.kind == EpubParaKind.image) {
          cur.add(PagPiece(i, from, n));
          h += rest;
          break;
        }
        // 空页也装不下＝这段本身超一页：切一块上本页，剩下的续排（不许裁半字）。
        final cut = cutAfterLine(p, l, from, avail);
        final end = cut > n ? n : cut;
        cur.add(PagPiece(i, from, end));
        flush();
        from = end;
        if (from >= n) break;
      }
    }
    flush();
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
    pages = List<PagChapter?>.filled(w.length, null);
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
    List<PagChapter?> pages,
  ) {
    final p = BookPagination.lazy(charWeights);
    for (var i = 0; i < pages.length && i < p.pages.length; i++) {
      p.pages[i] = pages[i];
    }
    return p;
  }

  /// 每章字符数（进度权重）。
  final List<int> w;
  /// 章 → 页 → 块（段＋段内区间）；null＝该章未排版（按需实算后回填）。
  late final List<PagChapter?> pages;
  /// cum[i]＝前 i 章字符数前缀和。
  late final List<int> cum;

  int get chapterCount => w.length;
  int get totalChars => cum.isEmpty ? 0 : cum.last;

  bool laidOut(int ci) =>
      ci >= 0 && ci < pages.length && pages[ci] != null;
  void setChapter(int ci, PagChapter pg) => pages[ci] = pg;

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
  /// 段跨页续排后**一块一页**：传 [at]（段内原文偏移）就返回覆盖该偏移的那一页，
  /// 不传＝返回首块（旧语义）。
  int pageOfPara(int ci, int pi, {int? at}) {
    final list = pages[ci];
    if (list == null) return 0;
    for (var p = 0; p < list.length; p++) {
      for (final b in list[p]) {
        if (b.pi != pi) continue;
        if (at == null) return p;
        if (at >= b.from && at < b.to) return p;
      }
    }
    return (list.length - 1).clamp(0, 1 << 30);
  }

  /// 第 pg 页里段 pi 的**块起点**（同段被切成多块时用 [at] 选其一）；找不到＝0。
  /// 命中闪底/闪烁环的键都带块起点，跳转侧必须用它定位到**真正那一块**（§3H-A）。
  int pieceStartOf(int ci, int pg, int pi, {int? at}) {
    final list = pages[ci];
    if (list == null || pg < 0 || pg >= list.length) return 0;
    for (final b in list[pg]) {
      if (b.pi != pi) continue;
      if (at == null || (at >= b.from && at < b.to)) return b.from;
    }
    return 0;
  }
}
