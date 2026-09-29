/// 小工具合集 · 色彩换算（批2 · 原型 `h2r` / `r2h` / `r2hsl` / `hsl2r` /
/// `KCC_PRESET` / `CMP_SCHEMES` / `cmpShow` 同源）。
///
/// 纯函数无副作用；HSL 采用原型口径（h 0~359、s/l 0~100 的浮点值），
/// 与 Flutter `HSLColor`（s/l 为 0~1）不同，转换处统一在本文件收口，
/// 界面侧只使用 hex 串与本文件的 [kitHsl]。
library;

import 'dart:math' as math;

/// HSL（h=0~360 开区间，s/l=0~100）。
class KitHsl {
  const KitHsl(this.h, this.s, this.l);

  final double h;
  final double s;
  final double l;

  @override
  bool operator ==(Object other) =>
      other is KitHsl && other.h == h && other.s == s && other.l == l;

  @override
  int get hashCode => Object.hash(h, s, l);

  @override
  String toString() => 'hsl(${h.round()}, ${s.round()}%, ${l.round()}%)';
}

/// RGB 分量（0~255，已四舍五入）。
class KitRgb {
  const KitRgb(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;

  @override
  bool operator ==(Object other) =>
      other is KitRgb && other.r == r && other.g == g && other.b == b;

  @override
  int get hashCode => Object.hash(r, g, b);

  @override
  String toString() => 'rgb($r, $g, $b)';
}

final RegExp _hexRe = RegExp(r'^#?([0-9a-fA-F]{6})$');
final RegExp _rgbRe = RegExp(r'rgba?\(\s*(\d+)[,\s]+(\d+)[,\s]+(\d+)', caseSensitive: false);
final RegExp _hslRe =
    RegExp(r'hsla?\(\s*([\d.]+)[,\s]+([\d.]+)%?[,\s]+([\d.]+)%?', caseSensitive: false);

/// hex → RGB（非法返回 null；`#` 可省）。
KitRgb? kitHexToRgb(String hex) {
  final m = _hexRe.firstMatch(hex.trim());
  if (m == null) return null;
  final v = int.parse(m.group(1)!, radix: 16);
  return KitRgb((v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff);
}

/// RGB → hex（小写、带 `#`；分量越界自动钳制）。
String kitRgbToHex(KitRgb c) {
  String p(int v) => v.clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${p(c.r)}${p(c.g)}${p(c.b)}';
}

/// RGB → HSL（原型 `r2hsl` 同式）。
KitHsl kitRgbToHsl(KitRgb c) {
  final r = c.r / 255, g = c.g / 255, b = c.b / 255;
  final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
  final l = (mx + mn) / 2;
  var h = 0.0, s = 0.0;
  if (mx != mn) {
    final d = mx - mn;
    s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
    if (mx == r) {
      h = (g - b) / d + (g < b ? 6 : 0);
    } else if (mx == g) {
      h = (b - r) / d + 2;
    } else {
      h = (r - g) / d + 4;
    }
    h *= 60;
  }
  return KitHsl(h, s * 100, l * 100);
}

/// HSL → RGB（原型 `hsl2r` 的 f(n)=k=(n+h/30)%12 式，色相自动取模）。
KitRgb kitHslToRgb(KitHsl c) {
  final h = ((c.h % 360) + 360) % 360;
  final s = c.s / 100, l = c.l / 100;
  double f(int n) {
    final k = (n + h / 30) % 12;
    return (l - s * math.min(l, 1 - l) * math.max(-1, math.min(k - 3, math.min(9 - k, 1)))) * 255;
  }
  return KitRgb(f(0).round(), f(8).round(), f(4).round());
}

/// hex → HSL。
KitHsl kitHexToHsl(String hex) => kitRgbToHsl(kitHexToRgb(hex) ?? const KitRgb(0, 0, 0));

/// HSL → hex。
String kitHslToHex(KitHsl c) => kitRgbToHex(kitHslToRgb(c));

/// 解析用户粘贴的色串（`#RRGGBB` / `RRGGBB` / `rgb()` / `hsl()`）→ 小写 hex；
/// 无法识别返回 null（原型 `cpkParse` / `kccParse` 同口径）。
String? kitParseColor(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final mH = _hexRe.firstMatch(s);
  if (mH != null) return '#${mH.group(1)!.toLowerCase()}';
  final mR = _rgbRe.firstMatch(s);
  if (mR != null) {
    return kitRgbToHex(
      KitRgb(
        int.parse(mR.group(1)!),
        int.parse(mR.group(2)!),
        int.parse(mR.group(3)!),
      ),
    );
  }
  final mM = _hslRe.firstMatch(s);
  if (mM != null) {
    return kitHslToHex(
      KitHsl(
        double.parse(mM.group(1)!),
        double.parse(mM.group(2)!),
        double.parse(mM.group(3)!),
      ),
    );
  }
  return null;
}

/// 选色弹层 16 枚预设色板（原型 `KCC_PRESET`，顺序即展示顺序）。
const List<String> kKitColorPresets = [
  '#ef4444', '#f97316', '#facc15', '#22c55e', '#2dd4bf', '#3b82f6',
  '#6366f1', '#a855f7', '#ec4899', '#f43f5e', '#94a3b8', '#0ea5e9',
  '#84cc16', '#f8fafc', '#1e293b', '#0f172a',
];

/// 三串展示文案（原型 `cpkShow`：HEX 大写 / `rgb(r, g, b)` / `hsl(h, s%, l%)`）。
List<String> kitColorReadouts(String hex) {
  final rgb = kitHexToRgb(hex) ?? const KitRgb(0, 0, 0);
  final hsl = kitRgbToHsl(rgb);
  return [
    hex.toUpperCase(),
    'rgb(${rgb.r}, ${rgb.g}, ${rgb.b})',
    'hsl(${hsl.h.round()}, ${hsl.s.round()}%, ${hsl.l.round()}%)',
  ];
}

/// 配色方案（原型 `CMP_SCHEMES` 一项）。
class KitScheme {
  const KitScheme(this.name, this.offsets, this.desc);

  final String name;

  /// 色相偏移（度）；第一个恒为主色 0°。
  final List<int> offsets;
  final String desc;
}

const List<KitScheme> kKitSchemes = [
  KitScheme('互补', [0, 180], '对比强 · 适合强调'),
  KitScheme('类似', [-30, 0, 30], '相邻 30° · 和谐'),
  KitScheme('三角', [0, 120, 240], '等距 120° · 活泼平衡'),
  KitScheme('分裂互补', [0, 150, 210], '互补两侧 · 低冲突高对比'),
  KitScheme('四方', [0, 90, 180, 270], '双互补 · 信息量大'),
];

/// 方案中的一色（名称 + hex + 实际色相角）。
class KitSchemeColor {
  const KitSchemeColor({
    required this.name,
    required this.hex,
    required this.deg,
  });

  final String name;
  final String hex;
  final double deg;
}

/// 按方案生成色组（原型 `cmpShow`：S +4 上限 100，L>72→52 否则 clamp(L+6, 46, 66)）。
List<KitSchemeColor> kitSchemeColors(String baseHex, KitScheme scheme) {
  final c = kitHexToHsl(baseHex);
  return [
    for (final o in scheme.offsets)
      () {
        final deg = (c.h + o + 360) % 360;
        final hex = kitHslToHex(
          KitHsl(deg, math.min(100, c.s + 4), c.l > 72 ? 52 : (c.l + 6).clamp(46, 66).toDouble()),
        );
        return KitSchemeColor(
          name: kitSchemeColorName(o, scheme),
          hex: hex,
          deg: deg,
        );
      }(),
  ];
}

/// 色名（原型 `cmpName` / `degName`：首色「主色」，二色方案叫「互补色 180°」，
/// 其余「偏移 +N°」）。
String kitSchemeColorName(int offset, KitScheme scheme) {
  if (offset == 0) return '主色';
  if (scheme.offsets.length == 2 && scheme.name == '互补') {
    return '互补色 ${offset.abs()}°';
  }
  if (scheme.offsets.length > 2) {
    return '偏移 ${offset > 0 ? '+' : ''}$offset°';
  }
  return '${scheme.name} · ${offset > 0 ? '+' : ''}$offset°';
}

/// 色串展示文案（`cpkShow` / `cpkTouch` 口径：最近取色上限 10，表头=最新）。
const int kKitRecentMax = 10;

/// 把 [hex] 推到最近取色表头（已存在则先摘除；表头同色不动）。
List<String> kitTouchRecent(List<String> recent, String hex) {
  if (recent.isEmpty) return [hex].take(kKitRecentMax).toList();
  if (recent.first == hex) return recent;
  final out = [hex, ...recent.where((c) => c != hex)];
  return out.length > kKitRecentMax ? out.sublist(0, kKitRecentMax) : out;
}

/// 从最近取色移除一枚。
List<String> kitDropRecent(List<String> recent, String hex) =>
    [for (final c in recent) if (c != hex) c];

/// 色环 6° 分段（原型 `cmpWheel`：60 段弧，饱和度下限 40、明度 44~62 收敛）。
List<String> kitWheelSegments(KitHsl base) => [
      for (var i = 0; i < 360; i += 6)
        kitHslToHex(
          KitHsl(i.toDouble(), math.max(40, base.s), base.l.clamp(44, 62).toDouble()),
        ),
    ];

/// 色环拖动取色（原型 `cmpDragTo`：atan2+90 归 0~360，保留当前 S/L 只换色相）。
String kitHueFromAngle({
  required double dx,
  required double dy,
  required KitHsl keep,
}) {
  if (dx.abs() < 2 && dy.abs() < 2) return kitHslToHex(keep);
  var ang = math.atan2(dy, dx) * 180 / math.pi + 90;
  if (ang < 0) ang += 360;
  return kitHslToHex(KitHsl(ang.roundToDouble(), keep.s, keep.l));
}
