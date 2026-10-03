import 'dart:ui' show Color;

import 'css_named_colors.dart';

/// 原书样式翻译器（批三实现批·刀1／V1.59 轮4②「完整档 CSS 解析」）。
///
/// 定位（`docs/阅读器排版路线说明-20261003.md`）：**一层 CSS 属性翻译器，不是排版引擎**——
/// 断行/测量/绘制一直是 Flutter 文本引擎在做，这里只把包里声明的原书排版意图
/// （`<link>` 样式表 + `<style>` 块 + 内联 `style=`）翻成 [EpubStyle] 喂给既有管线。
///
/// 三条硬口径（预研 §5.4 拍板，两条有机器闸）：
/// 1. **通用性红线**：只按 **CSS 声明语义** 处理，本文件内**禁止任何「class 名 → 样式」
///    字面量映射**（`.note`→绿 一旦写死，换一本 class 名不同的精编本书就全线失效）。
///    闸＝`test/architecture_test.dart` R9（白名单外字面量即红）；画像 §5.1 那张表是
///    证据不是依据，不许抄进代码。
/// 2. **裁剪判据按声明**：段内一个区间只要带白名单属性就进 runs（[EpubStyle.hasSemantics]），
///    不看它叫什么 class。
/// 3. **不支持的关键声明不许静默降级**：竖排/多栏/浮动/表格/RTL 记结构性丢弃，白名单内
///    但 Flutter 文本模型表达不了的（行内 padding、`background-image` 平铺线、
///    `-webkit-text-combine`）记近似降级——都进 [EpubUnsupportedSink]，上层落日志 +
///    该书外观页给提示行（刀3）。
///
/// 属性白名单（§5.4 逐字）：`color` / `background-color` / `font-size` / `font-weight` /
/// `font-style` / `text-indent` / `margin-*`（含 `-webkit-margin-start|end|before|after`、
/// `margin-inline-*`、`margin-block-*`）/ `text-align` / `border*` / `-webkit-text-combine`；
/// 另加 `line-height` / `text-decoration` / `background-image`（轮4② 完整档的相邻必需项）。
/// `@media`、`@font-face` 等 at-rule 整块跳过（本项目不随包字体，LH-F01 已拍板）。
///
/// 方向口径：本翻译器恒按**横排从左起**解释 logical 边（`margin-inline-start`→左、
/// `-webkit-margin-start`→左）。竖排属结构性丢弃（§5.4 拍板①），逻辑向与物理向重合；
/// `direction: rtl` 同样记结构性丢弃，不静默。

/// 字号比合理区间（预研 §2.4）：pt/px 换算后超界**视同缺失**，不钳到边界值。
const double kEpubRatioMin = 0.6;
const double kEpubRatioMax = 2.5;

/// em/rem/% 这类相对单位的宽松安全区——比 pt/px 宽：「3rem 的首章大字」是真实排版意图，
/// 而 48px 多是标注用的脏值。
const double kEpubRelativeLo = 0.2;
const double kEpubRelativeHi = 4.0;

/// rem/px 的换算基准（1rem＝16px）。rem 语义＝相对根字号＝我们的「用户基准字号」，
/// 所以 1rem 恒等于基准，不随段内 em 链缩放（预研 §5.2.3 钉死的换算口径）。
const double _kRootEmPx = 16.0;

/// 一条声明里能表达的全部原书排版意图（null＝该属性没声明，跟随用户主题）。
///
/// 单位口径：字号/行距是**比值**（相对用户基准字号、主题行距），缩进/边距/线宽是
/// **em 倍数**（相对所在段字号）——都不带绝对像素，用户调字号滑杆时原书比例照旧生效。
class EpubStyle {
  const EpubStyle({
    this.color,
    this.backgroundColor,
    this.fontRatio,
    this.weight,
    this.italic = false,
    this.lineRatio,
    this.indentEm,
    this.align,
    this.marginLeftEm,
    this.marginRightEm,
    this.marginTopEm,
    this.marginBottomEm,
    this.borderLeft,
    this.borderRight,
    this.borderTop,
    this.borderBottom,
    this.underline = false,
    this.overline = false,
    this.lineThrough = false,
    this.lineColor,
    this.deco,
  });

  /// 字色 / 底色（`.ji` 标签块是白字灰底，两者都要管，预研 §5.2.5）。
  final Color? color;
  final Color? backgroundColor;

  /// 字号比（0.75＝注的小字）、字重（100~900）、斜体。
  final double? fontRatio;
  final int? weight;
  final bool italic;

  /// 行距比——段级消费。
  final double? lineRatio;

  /// 首行缩进（em）与对齐——段级消费。
  final double? indentEm;
  final String? align;

  /// 四边外边距（em）——段级消费；夹注的左右缩进（`-webkit-margin-start`）走这里。
  final double? marginLeftEm, marginRightEm, marginTopEm, marginBottomEm;

  /// 四边描边（专名线 `.name{border-left:.12em solid}`／框线 `.name1{border:.1em solid}`）。
  final EpubBorder? borderLeft, borderRight, borderTop, borderBottom;

  /// 文本线（`text-decoration`；`background-image` 平铺装饰线的通用落点也在这里）。
  final bool underline, overline, lineThrough;

  /// 线的颜色（`text-decoration-color`；边线缺色＝跟字色）。
  final Color? lineColor;

  /// 线的形态（`text-decoration-style`；`background-image` 平铺装饰线回落成 wavy＝
  /// 原型 `?r32=st1` 的示意形态）。边线自己的形态在 [EpubBorder.style] 上，渲染处优先取它。
  final String? deco;

  bool get hasBorder =>
      borderLeft?.isLine == true ||
      borderRight?.isLine == true ||
      borderTop?.isLine == true ||
      borderBottom?.isLine == true;

  /// **进 runs 的判据**（§5.4 拍板②：按声明属性裁剪，不按 class 名）——
  /// 只有**行内文本能表达**的语义才算数；缩进/对齐/边距/行距是段级属性，
  /// 单靠它们不构成一个 span（否则整段被切成无意义的一刀）。
  bool get hasSemantics =>
      color != null ||
      backgroundColor != null ||
      fontRatio != null ||
      weight != null ||
      italic ||
      underline ||
      overline ||
      lineThrough ||
      lineColor != null ||
      hasBorder;

  /// 一条白名单声明都没有（含段级属性）。
  bool get isEmpty =>
      !hasSemantics &&
      indentEm == null &&
      align == null &&
      lineRatio == null &&
      marginLeftEm == null &&
      marginRightEm == null &&
      marginTopEm == null &&
      marginBottomEm == null;

  /// 逐字段取后者非空值（刀2 用：run 样式＝段级样式叠 span 声明）。
  EpubStyle merge(EpubStyle? other) {
    if (other == null) return this;
    return EpubStyle(
      color: other.color ?? color,
      backgroundColor: other.backgroundColor ?? backgroundColor,
      fontRatio: other.fontRatio ?? fontRatio,
      weight: other.weight ?? weight,
      italic: other.italic || italic,
      lineRatio: other.lineRatio ?? lineRatio,
      indentEm: other.indentEm ?? indentEm,
      align: other.align ?? align,
      marginLeftEm: other.marginLeftEm ?? marginLeftEm,
      marginRightEm: other.marginRightEm ?? marginRightEm,
      marginTopEm: other.marginTopEm ?? marginTopEm,
      marginBottomEm: other.marginBottomEm ?? marginBottomEm,
      borderLeft: other.borderLeft ?? borderLeft,
      borderRight: other.borderRight ?? borderRight,
      borderTop: other.borderTop ?? borderTop,
      borderBottom: other.borderBottom ?? borderBottom,
      underline: other.underline || underline,
      overline: other.overline || overline,
      lineThrough: other.lineThrough || lineThrough,
      lineColor: other.lineColor ?? lineColor,
      deco: other.deco ?? deco,
    );
  }

  /// 相等判定（刀2 两处要用）：① runs 合并——相邻同风格的文字并成一刀，少切 span；
  /// ② 快照样式表去重——通鉴全书 672k span 只有个位数种风格，字典化后段内只存下标。
  @override
  bool operator ==(Object other) =>
      other is EpubStyle &&
      other.color == color &&
      other.backgroundColor == backgroundColor &&
      other.fontRatio == fontRatio &&
      other.weight == weight &&
      other.italic == italic &&
      other.lineRatio == lineRatio &&
      other.indentEm == indentEm &&
      other.align == align &&
      other.marginLeftEm == marginLeftEm &&
      other.marginRightEm == marginRightEm &&
      other.marginTopEm == marginTopEm &&
      other.marginBottomEm == marginBottomEm &&
      other.borderLeft == borderLeft &&
      other.borderRight == borderRight &&
      other.borderTop == borderTop &&
      other.borderBottom == borderBottom &&
      other.underline == underline &&
      other.overline == overline &&
      other.lineThrough == lineThrough &&
      other.lineColor == lineColor &&
      other.deco == deco;

  // 21 个字段超过 Object.hash 的 20 参上限，走 hashAll（列表分配只发生在建样式那一刻）。
  @override
  int get hashCode => Object.hashAll(<Object?>[
    color,
    backgroundColor,
    fontRatio,
    weight,
    italic,
    lineRatio,
    indentEm,
    align,
    marginLeftEm,
    marginRightEm,
    marginTopEm,
    marginBottomEm,
    borderLeft,
    borderRight,
    borderTop,
    borderBottom,
    underline,
    overline,
    lineThrough,
    lineColor,
    deco,
  ]);
}

/// 一条边的声明（宽度按 em 或 px 给、样式、颜色；`.name{border-left:.12em solid}` 无颜色＝跟字色）。
class EpubBorder {
  const EpubBorder({this.widthEm, this.widthPx, this.style, this.color});

  /// `none`／零宽——声明存在但画不出（[isLine] 为 false，[EpubStyle.hasBorder] 不计）。
  static const EpubBorder none = EpubBorder(style: 'none');

  final double? widthEm;
  final double? widthPx;
  final String? style;
  final Color? color;

  bool get isLine =>
      style != null &&
      style != 'none' &&
      style != 'hidden' &&
      ((widthEm ?? 0) > 0 || (widthPx ?? 0) > 0);

  @override
  bool operator ==(Object other) =>
      other is EpubBorder &&
      other.widthEm == widthEm &&
      other.widthPx == widthPx &&
      other.style == style &&
      other.color == color;

  @override
  int get hashCode => Object.hash(widthEm, widthPx, style, color);
}

/// 「不支持声明」的分类（路线说明：不静默降级；可测＝用例断言标记非空且日志查得到）。
enum EpubUnsupportedKind {
  /// 结构性丢弃：Flutter 文本引擎表达不了，**不显示就等于少一整层内容**——
  /// 竖排/多栏/浮动/表格/RTL。必须落日志 + 在该书外观页给提示行。
  cssStructural,

  /// 近似降级：声明能识别，但按既有口径换成近似形态（行内 padding 不叠加、
  /// `background-image` 平铺线换成文本下划线、`-webkit-text-combine` 不压字）。
  cssFlattened,
}

/// 一条不支持/降级声明的留痕（按「属性+值」去重计数，全书级合并）。
class EpubUnsupported {
  const EpubUnsupported({
    required this.kind,
    required this.property,
    required this.value,
    required this.count,
  });

  final EpubUnsupportedKind kind;
  final String property;
  final String value;
  final int count;

  /// 归一化判定键（[describe] 与用例都取它，避免值写法多样把断言搞脆）。
  String get key => switch (property) {
        'writing-mode' || '-webkit-writing-mode' => 'writing-mode',
        'column-count' || 'columns' || 'column-width' => 'column-count',
        'float' || 'clear' => 'float',
        'direction' => 'direction',
        'display' => 'display',
        'background' || 'background-image' => 'background-image',
        'padding' ||
        'padding-left' ||
        'padding-right' ||
        'padding-top' ||
        'padding-bottom' ||
        'padding-inline-start' ||
        'padding-inline-end' ||
        '-webkit-padding-start' ||
        '-webkit-padding-end' =>
          'padding',
        _ => property,
      };

  /// 给人看的一行（外观提示条与日志共用；禁 emoji）。
  String describe() {
    final t = switch (key) {
      'writing-mode' => '竖排直排',
      'column-count' => '多栏排版',
      'float' => '图文浮动',
      'display' => '表格排版',
      'direction' => '从右向左书写',
      'padding' => '行内留白',
      'background-image' => '图片装饰线',
      '-webkit-text-combine' => '数字压缩排布',
      'letter-spacing' => '字距微调',
      'word-spacing' => '词距微调',
      _ => property,
    };
    return kind == EpubUnsupportedKind.cssStructural
        ? '$t（当前按横排单栏显示）'
        : '$t（已按近似样式显示）';
  }
}

/// 不支持声明收集器（null＝不采集）。刀2 在逐章抽取时挂一份、按书合并落盘。
class EpubUnsupportedSink {
  final Map<String, ({EpubUnsupportedKind k, String p, String v, int n})> _m = {};

  int get length => _m.length;

  void add(EpubUnsupportedKind kind, String property, String value) {
    final key = '${kind.index}|$property|${value.toLowerCase()}';
    final hit = _m[key];
    _m[key] = (k: kind, p: property, v: value, n: (hit?.n ?? 0) + 1);
  }

  List<EpubUnsupported> toList() => [
    for (final e in _m.values)
      EpubUnsupported(kind: e.k, property: e.p, value: e.v, count: e.n),
  ];
}

// ---------- 值解析（认不了＝null，绝不抛；脏数据清单见预研 §2 与 §5.2） ----------

/// CSS 颜色 → [Color]。`transparent`/`currentColor`/`inherit` 与认不了的值＝ null（跟随主题）。
/// 通鉴样包**零个 `#rrggbb`**、颜色全是命名色（预研 §5.2.2）→ 命名色表是硬需求。
Color? cssColor(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty ||
      s == 'transparent' ||
      s == 'currentcolor' ||
      s == 'inherit' ||
      s == 'initial' ||
      s == 'unset') {
    return null;
  }
  if (s.startsWith('#')) {
    final h = s.substring(1);
    final v = int.tryParse(h, radix: 16);
    if (v == null) return null;
    if (h.length == 3) {
      final r = (v >> 8) & 0xF, g = (v >> 4) & 0xF, b = v & 0xF;
      return Color(0xFF000000 | (r * 17 << 16) | (g * 17 << 8) | b * 17);
    }
    if (h.length == 4) {
      final r = (v >> 12) & 0xF, g = (v >> 8) & 0xF, b = (v >> 4) & 0xF, a = v & 0xF;
      return Color((a * 17 << 24) | (r * 17 << 16) | (g * 17 << 8) | b * 17);
    }
    if (h.length == 6) return Color(0xFF000000 | v);
    // rrggbbaa → aarrggbb（Flutter Color 的字节序）。
    if (h.length == 8) return Color(((v & 0xFF) << 24) | (v >> 8));
    return null;
  }
  if (s.startsWith('rgb') || s.startsWith('hsl')) {
    final open = s.indexOf('(');
    if (open < 0) return null;
    final nums = RegExp(r'(\d*\.?\d+)(%)?').allMatches(s.substring(open + 1));
    final parts = <double>[];
    final pct = <bool>[];
    for (final m in nums) {
      final n = double.tryParse(m.group(1)!);
      if (n == null) continue;
      parts.add(n);
      pct.add(m.group(2) != null);
    }
    if (parts.length < 3) return null;
    double comp(int i, double max) =>
        pct[i] ? parts[i] / 100 * max : parts[i];
    final a = parts.length > 3
        ? (pct[3] ? parts[3] / 100 : parts[3]).clamp(0.0, 1.0)
        : 1.0;
    if (s.startsWith('hsl')) {
      // hsl → rgb（Flutter Color 没有 HSV 工厂；色相/饱和/亮度按 CSS 口径换算）。
      return Color((a * 255).round() << 24 |
          _hslToRgb(comp(0, 360), comp(1, 100) / 100, comp(2, 100) / 100));
    }
    int ch8(int i) => comp(i, 255).round().clamp(0, 255);
    return Color.fromARGB((a * 255).round(), ch8(0), ch8(1), ch8(2));
  }
  final named = kEpubCssNamedColors[s];
  return named == null ? null : Color(named);
}

/// HSL → 0xRRGGBB（h 度数，s/l 0~1；CSS 现代写法口径）。
int _hslToRgb(double h, double sa, double li) {
  final hue = ((h % 360) + 360) % 360;
  final a = sa * (li <= 0.5 ? li : 1 - li);
  double channel(double n) {
    final k = (n + hue / 30.0) % 12.0;
    var m = k - 2;
    if (12 - k < m) m = 12 - k;
    if (1 < m) m = 1;
    if (-1 > m) m = -1;
    return li - a * m;
  }

  int ch8(double v) => (v * 255).round().clamp(0, 255);
  return ch8(channel(0)) << 16 | ch8(channel(8)) << 8 | ch8(channel(4));
}

/// 长度 → em 倍数（相对本段字号；rem 相对根字号＝基准，两者在单层模型里同值）。
/// 认不了的单位（`vh`/`cm`/`calc(...)`）＝ null（预研 §5.2.1「见到不认识就跳过而不是报错」）。
double? cssLengthInEm(String raw) {
  final s = raw.trim().toLowerCase();
  final m = RegExp(r'^([+-]?\d*\.?\d+)([a-z%]*)$').firstMatch(s);
  if (m == null) return null;
  final n = double.tryParse(m.group(1)!);
  if (n == null) return null;
  return switch (m.group(2)!) {
    'em' || 'rem' || '' => n,
    '%' => n / 100,
    'px' => n / _kRootEmPx,
    'pt' => n * 96 / 72 / _kRootEmPx,
    'pc' => n * 16 / _kRootEmPx,
    _ => null,
  };
}

/// font-size → 字号比。em/rem/% 走宽松区；px/pt/pc 换算后超
/// [kEpubRatioMin, kEpubRatioMax] **视同缺失**（预研 §2.4 原文口径）。
double? cssFontRatio(String raw) {
  final s = raw.trim().toLowerCase();
  switch (s) {
    case 'xx-small':
      return 0.6;
    case 'x-small':
      return 0.67;
    case 'small':
      return 0.83;
    case 'medium':
      return 1.0;
    case 'large':
      return 1.2;
    case 'x-large':
      return 1.5;
    case 'xx-large':
      return 2.0;
    case 'smaller':
      return 0.8;
    case 'larger':
      return 1.25;
  }
  final e = cssLengthInEm(s);
  if (e == null || e <= 0) return null;
  final abs = RegExp(r'(px|pt|pc)$').hasMatch(s);
  if (abs && (e < kEpubRatioMin || e > kEpubRatioMax)) return null;
  // 无单位非零值（`font-size:12`）在 CSS 里本就非法。
  if (RegExp(r'^[+-]?\d*\.?\d+$').hasMatch(s)) return null;
  return (e < kEpubRelativeLo || e > kEpubRelativeHi) ? null : e;
}

/// line-height → 行距比（无单位数字／百分比／长度都认，超界＝缺失）。
double? cssLineRatio(String raw) {
  final s = raw.trim().toLowerCase();
  if (s == 'normal' || s.isEmpty) return null;
  final plain = double.tryParse(s);
  if (plain != null) return (plain >= 0.8 && plain <= 3.0) ? plain : null;
  final e = cssLengthInEm(s);
  if (e == null || e <= 0) return null;
  return (e >= 0.8 && e <= 3.0) ? e : null;
}

/// font-weight → 100~900；`blod` 这类拼写错误＝ null，同规则其余声明照用（预研 §2.2）。
int? cssFontWeight(String raw) {
  final s = raw.trim().toLowerCase();
  switch (s) {
    case 'normal':
      return 400;
    case 'bold':
    case 'bolder':
      return 700;
    case 'lighter':
      return 300;
  }
  final n = double.tryParse(s);
  if (n == null || n < 1 || n > 1000) return null;
  return (n / 100).round().clamp(1, 9) * 100;
}

/// text-align → left/center/right/justify（`start`/`match-parent` 按横排左起归一 left）。
String? cssTextAlign(String raw) {
  final s = raw.trim().toLowerCase();
  return switch (s) {
    'left' || 'start' || 'match-parent' || '-webkit-left' => 'left',
    'right' || 'end' || '-webkit-right' => 'right',
    'center' || '-webkit-center' => 'center',
    'justify' || '-webkit-justify' => 'justify',
    _ => null,
  };
}

/// `text-decoration` / `text-decoration-line` → 三种线。
({bool underline, bool overline, bool through}) cssDecorations(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty || s == 'none' || s == 'inherit') {
    return (underline: false, overline: false, through: false);
  }
  return (
    underline: s.contains('underline'),
    overline: s.contains('overline'),
    through: s.contains('line-through') || s.contains('through'),
  );
}

// ---------- 声明解析（简写就地展开成长写法；白名单外只记账不消费） ----------

typedef _Decl = ({String v, bool imp});

/// 一条声明：剥 `!important` 后缀并判定；`inherit`/`initial`/`unset` 与空值＝ null。
_Decl? _declOf(String value) {
  final s = value.trim();
  if (s.isEmpty || s == 'inherit' || s == 'initial' || s == 'unset') return null;
  final bang = s.indexOf('!');
  if (bang < 0) return (v: s, imp: false);
  return (v: s.substring(0, bang).trim(), imp: s.substring(bang + 1).contains('important'));
}

/// 声明文本 → 展开后的长写法表（`out` 保插入序；[sink] 非 null 时顺带记不支持项）。
Map<String, _Decl> _parseDeclarations(String body, EpubUnsupportedSink? sink) {
  final out = <String, _Decl>{};
  for (final seg in body.split(';')) {
    final s = seg.trim();
    if (s.isEmpty) continue; // 预研 §2.1：`style=";color:black;"` 以分号起头
    final c = s.indexOf(':');
    if (c <= 0) continue;
    final d = _declOf(s.substring(c + 1));
    if (d == null) continue;
    _put(s.substring(0, c).trim().toLowerCase(), d, out, sink);
  }
  return out;
}

/// 属性名归一（webkit/logical 前缀 → 物理边）＋白名单闸＋简写展开。
void _put(String prop, _Decl d, Map<String, _Decl> out, EpubUnsupportedSink? sink) {
  final v = d.v;
  String? k;
  switch (prop) {
    case 'color':
    case 'fill':
    case 'stroke':
      k = 'color';
    case 'background-color':
      k = 'background-color';
    case 'font-size':
      k = 'font-size';
    case 'font-weight':
      k = 'font-weight';
    case 'font-style':
      k = 'font-style';
    case 'line-height':
      k = 'line-height';
    case 'text-indent':
      k = 'text-indent';
    case 'text-align':
      k = 'text-align';
    case 'text-decoration':
    case 'text-decoration-line':
      k = 'text-decoration';
    case 'text-decoration-color':
      k = 'text-decoration-color';
    case 'text-decoration-style':
      k = 'text-decoration-style';
    // —— 边距：物理 + logical + webkit 三路归一（预研 §5.2.4：只认 margin-left 会丢夹注层级缩进）
    case 'margin-left':
    case 'margin-inline-start':
    case '-webkit-margin-start':
      k = 'margin-left';
    case 'margin-right':
    case 'margin-inline-end':
    case '-webkit-margin-end':
      k = 'margin-right';
    case 'margin-top':
    case 'margin-block-start':
    case '-webkit-margin-before':
      k = 'margin-top';
    case 'margin-bottom':
    case 'margin-block-end':
    case '-webkit-margin-after':
      k = 'margin-bottom';
    case 'margin':
      _expandBox(v, out, d.imp);
      return;
    // —— 描边：单边简写（专名线走这里，§5.4 拍板②）
    case 'border-left':
      _expandBorder('left', v, out, d.imp);
      return;
    case 'border-right':
      _expandBorder('right', v, out, d.imp);
      return;
    case 'border-top':
      _expandBorder('top', v, out, d.imp);
      return;
    case 'border-bottom':
      _expandBorder('bottom', v, out, d.imp);
      return;
    case 'border':
      _expandBorder('all', v, out, d.imp);
      return;
    case 'border-inline-start':
      k = 'border-left';
    case 'border-inline-end':
      k = 'border-right';
    case 'border-block-start':
      k = 'border-top';
    case 'border-block-end':
      k = 'border-bottom';
    case '-webkit-border-start':
      k = 'border-left';
    case '-webkit-border-end':
      k = 'border-right';
    case '-webkit-border-before':
      k = 'border-top';
    case '-webkit-border-after':
      k = 'border-bottom';
    case 'border-width':
    case 'border-style':
    case 'border-color':
    case 'border-left-width':
    case 'border-left-style':
    case 'border-left-color':
    case 'border-right-width':
    case 'border-right-style':
    case 'border-right-color':
    case 'border-top-width':
    case 'border-top-style':
    case 'border-top-color':
    case 'border-bottom-width':
    case 'border-bottom-style':
    case 'border-bottom-color':
      k = prop;
    case 'background':
      // 背景简写：有图＝装饰线降级（下面按 url 判定），没图取颜色段。
      if (v.contains('url(')) {
        sink?.add(EpubUnsupportedKind.cssFlattened, 'background-image', v);
        k = 'background-image';
      } else {
        k = 'background-color';
      }
    case 'background-image':
      sink?.add(EpubUnsupportedKind.cssFlattened, prop, v);
      k = 'background-image';
    case 'background-repeat':
    case 'background-position':
    case 'background-size':
      k = prop; // 与 background-image 同族：认下来，消费处一并处理
    case '-webkit-text-combine':
      sink?.add(EpubUnsupportedKind.cssFlattened, prop, v);
      return;
    case 'writing-mode':
    case '-webkit-writing-mode':
      if (!v.toLowerCase().contains('vertical')) return;
      sink?.add(EpubUnsupportedKind.cssStructural, 'writing-mode', v);
      k = 'writing-mode';
    case 'direction':
      if (v.toLowerCase() == 'rtl') {
        sink?.add(EpubUnsupportedKind.cssStructural, prop, v);
      }
      return;
    case 'column-count':
    case 'columns':
    case 'column-width':
      sink?.add(EpubUnsupportedKind.cssStructural, prop, v);
      return;
    case 'float':
    case 'clear':
      if (v.toLowerCase() != 'none') {
        sink?.add(EpubUnsupportedKind.cssStructural, prop, v);
      }
      return;
    case 'display':
      if (v.toLowerCase().startsWith('table')) {
        sink?.add(EpubUnsupportedKind.cssStructural, prop, v);
      }
      return;
    case 'padding':
    case 'padding-left':
    case 'padding-right':
    case 'padding-top':
    case 'padding-bottom':
    case 'padding-inline-start':
    case 'padding-inline-end':
    case '-webkit-padding-start':
    case '-webkit-padding-end':
      sink?.add(EpubUnsupportedKind.cssFlattened, prop, v);
      return;
    case 'letter-spacing':
    case 'word-spacing':
      sink?.add(EpubUnsupportedKind.cssFlattened, prop, v);
      return;
    default:
      return; // 白名单外（font-family/height/width/text-transform…）不参与排版
  }
  _write(out, k, d);
}

/// 「缺才填」＋`!important` 覆盖普通值——同级后写不覆盖先写由 [EpubStyleSheet.resolve]
/// 的降序遍历保证。
void _write(Map<String, _Decl> out, String key, _Decl d) {
  final cur = out[key];
  if (cur == null || (d.imp && !cur.imp)) out[key] = d;
}

/// `margin: a b c d`（上 右 下 左；不足四值按 CSS 回落规则镜像）。
void _expandBox(String value, Map<String, _Decl> out, bool imp) {
  final parts = _splitValues(value);
  if (parts.isEmpty) return;
  final top = parts[0];
  final right = parts.length > 1 ? parts[1] : top;
  final bottom = parts.length > 2 ? parts[2] : top;
  final left = parts.length > 3 ? parts[3] : right;
  void w(String side, String v) =>
      _write(out, 'margin-$side', (v: v, imp: imp));
  w('top', top);
  w('right', right);
  w('bottom', bottom);
  w('left', left);
}

/// `border: 3px double White`／`border-left: .12em solid` → 三要素长写法。
/// 值顺序不固定（宽度/样式/颜色任意先后），按形态分派：长度→宽度、样式词→样式、
/// 其余能解出颜色的→颜色；`all` 展开到四边。
void _expandBorder(String side, String value, Map<String, _Decl> out, bool imp) {
  final parts = _splitValues(value);
  if (parts.isEmpty) return;
  final sides = side == 'all' ? const ['left', 'right', 'top', 'bottom'] : [side];
  String? w, st, col;
  for (final p in parts) {
    final lp = p.toLowerCase();
    if (_borderStyles.contains(lp)) {
      st ??= lp;
    } else if (cssLengthInEm(p) != null) {
      w ??= p;
    } else if (cssColor(p) != null) {
      col ??= p;
    }
  }
  for (final s in sides) {
    if (w != null) _write(out, 'border-$s-width', (v: w, imp: imp));
    if (st != null) _write(out, 'border-$s-style', (v: st, imp: imp));
    if (col != null) _write(out, 'border-$s-color', (v: col, imp: imp));
  }
  // `border: none` 要让对应边消失：宽度补 0（样式已是 none）。
  if (st == 'none' || st == 'hidden') {
    for (final s in sides) {
      _write(out, 'border-$s-width', (v: '0', imp: imp));
    }
  }
}

const Set<String> _borderStyles = {
  'none',
  'hidden',
  'solid',
  'double',
  'dotted',
  'dashed',
  'groove',
  'ridge',
  'inset',
  'outset',
};

/// 值切分：空白切，但括号内不切（`url(a b.gif)`、`rgb(1 2 3)`）。
List<String> _splitValues(String v) {
  final out = <String>[];
  final sb = StringBuffer();
  var depth = 0;
  void flush() {
    if (sb.isNotEmpty) out.add(sb.toString());
    sb.clear();
  }

  for (final c in v.split('')) {
    if (c == '(') depth++;
    if (c == ')') depth = depth > 0 ? depth - 1 : 0;
    if (depth == 0 && RegExp(r'\s').hasMatch(c)) {
      flush();
      continue;
    }
    sb.write(c);
  }
  flush();
  return out;
}

/// 展开后的长写法表 → [EpubStyle]（消费面；认不了的值得到 null，不影响其余字段）。
EpubStyle _buildStyle(Map<String, _Decl> d) {
  Color? c(String k) => cssColor(d[k]?.v ?? '');
  double? em(String k) => cssLengthInEm(d[k]?.v ?? '');

  /// 某边的描边：单边缺位时回落四边简写（`border-width/style/color`）。
  EpubBorder? border(String side) {
    final st = d['border-$side-style']?.v ?? d['border-style']?.v;
    final wv = d['border-$side-width']?.v ?? d['border-width']?.v;
    final col = c('border-$side-color') ?? c('border-color');
    if (st == null && wv == null && col == null) return null;
    if (st == 'none' || st == 'hidden') return EpubBorder.none;
    final low = (wv ?? '').trim().toLowerCase();
    return EpubBorder(
      widthEm: cssLengthInEm(low),
      widthPx: low.endsWith('px')
          ? double.tryParse(low.substring(0, low.length - 2))
          : null,
      style: st ?? 'solid',
      color: col,
    );
  }

  final deco = cssDecorations(d['text-decoration']?.v ?? '');
  final bg = d['background']?.v ?? d['background-image']?.v ?? '';
  final style = d['font-style']?.v.toLowerCase() ?? '';
  final ratio = cssFontRatio(d['font-size']?.v ?? '');
  final weight = cssFontWeight(d['font-weight']?.v ?? '');
  return EpubStyle(
    color: c('color'),
    backgroundColor: c('background-color'),
    // **与基准同值的不算语义**：通鉴 30,833 个正文段全是 `font-size:1rem`＋
    // `font-weight:normal`，照原样进 runs 就白拆 3 万个 span（预研 §5.3 性能口径）。
    fontRatio: ratio == 1.0 ? null : ratio,
    weight: weight == 400 ? null : weight,
    italic: style == 'italic' || style == 'oblique',
    lineRatio: cssLineRatio(d['line-height']?.v ?? ''),
    indentEm: em('text-indent'),
    align: cssTextAlign(d['text-align']?.v ?? ''),
    marginLeftEm: em('margin-left'),
    marginRightEm: em('margin-right'),
    marginTopEm: em('margin-top'),
    marginBottomEm: em('margin-bottom'),
    borderLeft: border('left'),
    borderRight: border('right'),
    borderTop: border('top'),
    borderBottom: border('bottom'),
    // 图片平铺装饰线（`.book-title` 书名线原书是 gif）在 Flutter 文本模型里的通用
    // 落点＝下划线；原型 `text-decoration: underline wavy` 已按此示意并过门（§3A①）。
    underline: deco.underline || bg.contains('url('),
    overline: deco.overline,
    lineThrough: deco.through,
    lineColor: c('text-decoration-color'),
    // 图片平铺线（书名线）没有对应文本线形态，按原型示意落 wavy；显式声明优先。
    deco: d['text-decoration-style']?.v ?? (bg.contains('url(') ? 'wavy' : null),
  );
}

// ---------- 选择器与级联 ----------

/// 级联可匹配的最小元素视图（抽取侧由 `html.Element` 适配过来——本文件因此
/// 不依赖 html 包，可脱离解析器单测）。
class EpubElementRef {
  const EpubElementRef(this.tag, this.classes, this.id);

  final String tag;
  final Set<String> classes;
  final String? id;
}

/// 选择器的一个复合段（`div.sgc-toc-title`／`p`／`*`／`#x`）。
class EpubCompound {
  const EpubCompound({this.tag, this.id, this.classes = const []});

  final String? tag; // null＝不限标签（只写 class/id）
  final String? id;
  final List<String> classes;

  bool matches(String t, Set<String> cls, String? i) {
    if (tag != null && tag != '*' && tag != t) return false;
    if (id != null && id != i) return false;
    for (final c in classes) {
      if (!cls.contains(c)) return false;
    }
    return true;
  }
}

/// 一条选择器：复合段序列，相邻段＝后代关系（`div p`）。
/// 含不支持的组合符/属性/伪类（`>` `+` `~` `[` `(` `:` `*` `|` `%`）时
/// [supported]＝false，整条不参与级联——宁可不涂色，不可错涂。
class EpubSelector {
  const EpubSelector(this.chain, this.specificity, {this.supported = true});

  static const EpubSelector unsupported = EpubSelector([], 0, supported: false);

  final List<EpubCompound> chain;
  final int specificity;
  final bool supported;

  /// [elements]＝自内而外的元素链（下标 0＝待判定元素本身）。
  bool matches(List<EpubElementRef> elements) {
    if (!supported || chain.isEmpty) return false;
    var ci = chain.length - 1;
    for (var ei = 0; ei < elements.length && ci >= 0; ei++) {
      if (chain[ci].matches(
        elements[ei].tag,
        elements[ei].classes,
        elements[ei].id,
      )) {
        ci--;
      }
    }
    return ci < 0;
  }

  static EpubSelector parse(String src) {
    final s = src.trim();
    if (s.isEmpty) return unsupported;
    if (RegExp(r'''[>+~\[(:|,%]''').hasMatch(s)) return unsupported;
    final parts = s.split(RegExp(r'\s+'));
    final chain = <EpubCompound>[];
    var spec = 0;
    for (final raw in parts) {
      final m = RegExp(r'^([*A-Za-z][A-Za-z0-9_-]*)?((?:[#.][A-Za-z0-9_-]+)*)$').firstMatch(raw);
      if (m == null) return unsupported;
      final classes = <String>[];
      String? id;
      for (final suf in RegExp(r'[#.][\w-]+').allMatches(m.group(2) ?? '')) {
        final value = suf.group(0)!;
        if (value.startsWith('#')) {
          id ??= value.substring(1);
        } else {
          classes.add(value.substring(1));
        }
      }
      spec += (id != null ? 100 : 0) + classes.length * 10;
      final tag = m.group(1);
      if (tag != null && tag != '*') spec += 1;
      chain.add(EpubCompound(tag: tag, id: id, classes: classes));
    }
    return EpubSelector(chain, spec);
  }
}

/// 一条规则（选择器组 + 声明体）。声明与不支持项**懒解析并缓存**：
/// 672k span 逐元素级联时，同一规则只解析一次（预研 §5.3 的性能口径）。
class EpubRule {
  EpubRule._(this.selectors, this.order, this.body);

  final List<EpubSelector> selectors;

  /// 源码顺序（同特异性时后写覆盖先写）。
  final int order;
  final String body;

  late final int specificity =
      selectors.map((s) => s.specificity).fold(0, (a, b) => a > b ? a : b);

  late final Map<String, _Decl> _declarations = _parseDeclarations(body, null);

  late final List<EpubUnsupported> unsupported =
      _parseCollectUnsupported(body);

  bool get hasUnsupported => unsupported.isNotEmpty;

  bool matches(List<EpubElementRef> chain) {
    for (final s in selectors) {
      if (s.matches(chain)) return true;
    }
    return false;
  }
}

List<EpubUnsupported> _parseCollectUnsupported(String body) {
  final sink = EpubUnsupportedSink();
  _parseDeclarations(body, sink);
  return sink.toList();
}

/// 一本书（或一篇文档）的样式表：规则集 + 级联入口。
class EpubStyleSheet {
  EpubStyleSheet(this.rules);

  /// 空样式表（包里没有 CSS 时的回落；不建索引，直接返回空结果）。
  EpubStyleSheet.empty() : rules = const [];

  final List<EpubRule> rules;

  bool get isEmpty => rules.isEmpty;

  /// 解析 CSS 文本：剥注释、at-rule 整块跳过（`@media`/`@font-face`）、
  /// 逗号选择器组拆成独立规则（`p, div { … }` 两条同声明）。
  static EpubStyleSheet parse(String css, {int orderBase = 0}) {
    final src = _stripComments(css);
    final rules = <EpubRule>[];
    var i = 0, n = 0;
    while (i < src.length) {
      while (i < src.length && _isWs(src[i])) {
        i++;
      }
      if (i >= src.length) break;
      if (src[i] == '@') {
        i = _skipAtRule(src, i);
        continue;
      }
      final brace = src.indexOf('{', i);
      if (brace < 0) break;
      var depth = 1, j = brace + 1;
      while (j < src.length && depth > 0) {
        if (src[j] == '{') {
          depth++;
        } else if (src[j] == '}') {
          depth--;
        }
        j++;
      }
      final closed = depth == 0;
      final sel = src.substring(i, brace).trim();
      final body = src.substring(brace + 1, closed ? j - 1 : j);
      if (sel.isNotEmpty && !sel.startsWith('@')) {
        for (final part in sel.split(',')) {
          final s = part.trim();
          if (s.isEmpty) continue;
          rules.add(EpubRule._([EpubSelector.parse(s)], orderBase + n, body));
          n++;
        }
      }
      i = closed ? j : src.length;
    }
    return EpubStyleSheet(rules);
  }

  /// 元素链（自内而外）级联 → 最终样式；[inline]＝该元素 `style=` 属性文本。
  /// 顺序保证：**降序遍历 + 缺才填**＝高特异性先占位（同特异性按源码序后写者先占位）；
  /// `!important` 先跑一轮＝important 恒胜普通声明（与特异性无关）；
  /// 内联普通声明压过样式表普通值，但压不过样式表的 `!important`（CSS 优先级表）。
  EpubStyle resolve(List<EpubElementRef> chain, {
    String inline = '',
    EpubUnsupportedSink? sink,
  }) {
    final merged = <String, _Decl>{};
    final matched = <EpubRule>[];
    // 快筛（预研 §5.3）：只取「最右复合段的 tag/class 落在链上某处」的规则做完整匹配，
    // 85 册 85 份 CSS 的书不能逐元素全表扫。
    for (final r in _candidates(chain)) {
      if (matched.contains(r)) continue;
      if (r.matches(chain)) matched.add(r);
    }
    matched.sort((a, b) => a.specificity != b.specificity
        ? b.specificity.compareTo(a.specificity)
        : b.order.compareTo(a.order));
    for (final r in matched) {
      if (sink != null && r.hasUnsupported) {
        for (final u in r.unsupported) {
          sink.add(u.kind, u.property, u.value);
        }
      }
      for (final imp in const [true, false]) {
        for (final e in r._declarations.entries) {
          if (e.value.imp == imp) _write(merged, e.key, e.value);
        }
      }
    }
    final raw = inline.trim();
    if (raw.isNotEmpty) {
      final d = _parseDeclarations(raw, sink);
      for (final e in d.entries) {
        final cur = merged[e.key];
        // 内联普通值压过样式表普通值；样式表的 !important 压过内联普通值；
        // 内联 !important 恒胜（CSS 作者层优先级表）。
        if (cur == null || !cur.imp || e.value.imp) merged[e.key] = e.value;
      }
    }
    return _buildStyle(merged);
  }

  /// 抽取侧的廉价前置判定：这个元素**自身**（标签/class/id/内联 style）有没有可能被样式表
  /// 点到。为 false 时抽取器直接沿用父元素的解析结果——祖先的规则在解析父元素时已经进过
  /// 一轮，沿链继承下来与整链级联同值，而 672k span 里绝大多数是纯文本内联（通鉴实测只有
  /// ~15% 带语义 class），逐个解析付不起（预研 §5.3 性能口径）。
  bool mayAffect(String tag, Set<String> classes, {bool hasInline = false}) {
    if (hasInline || _index.always.isNotEmpty) return true;
    if (_index.byKey.containsKey(tag)) return true;
    for (final c in classes) {
      if (_index.byKey.containsKey(c)) return true;
    }
    return false;
  }

  Iterable<EpubRule> _candidates(List<EpubElementRef> chain) {
    final out = <EpubRule>[..._index.always];
    for (final el in chain) {
      final t = _index.byKey[el.tag];
      if (t != null) out.addAll(t);
      for (final c in el.classes) {
        final r = _index.byKey[c];
        if (r != null) out.addAll(r);
      }
    }
    return out;
  }

  /// 按**最右复合段**建索引：选择器 `div.note p` 的落点是 `p`，所以按 `p` 建桶；
  /// 最右段没有 tag 也没有 class（`*`、`*|x`）的规则进 `always` 桶，每次都参与。
  late final ({Map<String, List<EpubRule>> byKey, List<EpubRule> always}) _index =
      _buildIndex();

  ({Map<String, List<EpubRule>> byKey, List<EpubRule> always}) _buildIndex() {
    final byKey = <String, List<EpubRule>>{};
    final always = <EpubRule>[];
    for (final r in rules) {
      var bucketed = false;
      for (final s in r.selectors) {
        if (!s.supported || s.chain.isEmpty) continue;
        final last = s.chain.last;
        final keys = <String>{...last.classes, if (last.tag != null && last.tag != '*') last.tag!};
        if (keys.isEmpty) {
          always.add(r);
        } else {
          for (final k in keys) {
            (byKey[k] ??= <EpubRule>[]).add(r);
          }
        }
        bucketed = true;
      }
      if (!bucketed) always.add(r); // 整条都不支持＝保守进 always（matches 会再否掉）
    }
    return (byKey: byKey, always: always);
  }
}

bool _isWs(String c) =>
    c == ' ' || c == '\n' || c == '\r' || c == '\t' || c == '\f';

/// 注释剥离（`/* … */`，可跨行；整体换成空格保持位置感）。
String _stripComments(String s) {
  final out = StringBuffer();
  var i = 0;
  while (i < s.length) {
    if (s.startsWith('/*', i)) {
      final end = s.indexOf('*/', i + 2);
      i = end < 0 ? s.length : end + 2;
      out.write(' ');
      continue;
    }
    out.write(s[i]);
    i++;
  }
  return out.toString();
}

/// at-rule 跳过：`;` 结束（`@import`）或大括号配平结束（`@media`/`@font-face`）。
int _skipAtRule(String s, int i) {
  var depth = 0;
  for (var j = i; j < s.length; j++) {
    final c = s[j];
    if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) return j + 1;
    } else if (c == ';' && depth == 0) {
      return j + 1;
    }
  }
  return s.length;
}
