import 'package:flutter/material.dart';

/// 主题元信息（对应 theme.json 的 meta 字段）。
class ThemeMeta {
  const ThemeMeta({
    required this.name,
    this.ver = '1.0',
    this.author = '',
    this.license = '',
  });

  final String name;
  final String ver;
  final String author;
  final String license;
}

/// 设计令牌（设计令牌配置文件解析结果）。
///
/// 与原型 `prototype/themes/*.json` 同构：`tokens` 为亮态、`dark` 为深态覆盖。
/// 正式版运行时由 [ThemeRepository] 从 `assets/themes/` 载入，实现热加载换肤。
class ThemeTokens {
  const ThemeTokens({
    required this.id,
    required this.meta,
    required this.forceDark,
    required this.accent,
    required this.accentLight,
    required this.g1,
    required this.g2,
    required this.g3,
    required this.page,
    required this.card,
    required this.cardBorder,
    required this.cardRadius,
    required this.cardShadow,
    required this.navBg,
    required this.navBorder,
    required this.text1,
    required this.text2,
    required this.ink,
    this.appFont,
  });

  final String id;
  final ThemeMeta meta;

  /// 强制深色（如赛博朋克）——选中该主题时忽略用户浅色设置。
  final bool forceDark;

  final Color accent;
  final Color accentLight;

  /// 渐变三停点（hero 卡 / 按钮 / 进度条）。
  final Color g1;
  final Color g2;
  final Color g3;

  final Color page;
  final Color card;
  final Color cardBorder;
  final double cardRadius;
  final List<BoxShadow> cardShadow;
  final Color navBg;
  final Color navBorder;

  /// 文本主色（原型 `--text1`）：标题与默认正文。
  final Color text1;

  /// 文本次色（原型 `--text2`）：说明行、次要小字、占位。
  final Color text2;

  /// 墨色（原型 `--ink`）：卡片正文 / 长文引文（比 text1 更深，用于有底色的卡面）。
  final Color ink;

  /// 可选全局字体族提示（复古/衬线主题用）。骨架阶段仅记录，不强制注入字体文件。
  final String? appFont;

  /// 内置兜底令牌（= 简约亮态），主题缺失或测试环境使用。
  static const ThemeTokens defaults = ThemeTokens(
    id: 'minimal',
    meta: ThemeMeta(name: '简约'),
    forceDark: false,
    accent: Color(0xFF6366F1),
    accentLight: Color(0xFF818CF8),
    g1: Color(0xFF6366F1),
    g2: Color(0xFF8B5CF6),
    g3: Color(0xFFD946EF),
    page: Color(0xFFF8FAFC),
    card: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFF1F5F9),
    cardRadius: 20,
    cardShadow: [],
    navBg: Color(0xFFFFFFFF),
    navBorder: Color(0xFFE2E8F0),
    text1: Color(0xFF0F172A),
    text2: Color(0xFF64748B),
    ink: Color(0xFF0F172A),
  );

  /// hero/按钮用渐变。
  LinearGradient get gradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [g1, g2, g3],
      );

  /// 从 theme.json 解析出的令牌 map 构建。
  ///
  /// [raw] 为合并后的令牌（深态已覆盖到亮态之上），键名带 `--` 前缀。
  /// [base] 为回落基准（简约默认），缺失令牌回落到 base（README 规则 2）。
  factory ThemeTokens.fromMap(
    String id,
    Map<String, dynamic> raw, {
    Map<String, dynamic>? base,
    bool forceDark = false,
    ThemeMeta? meta,
  }) {
    String? str(String key, {String? fallback}) {
      final v = raw[key] ?? base?[key] ?? fallback;
      return v is String ? v : null;
    }

    Color col(String key, Color fallback) =>
        parseColor(str(key) ?? '') ?? fallback;
    double num(String key, double fallback) {
      final v = str(key);
      if (v == null) return fallback;
      return parseLength(v) ?? fallback;
    }

    List<BoxShadow> shadows(String key) {
      final v = str(key);
      if (v == null) return const [];
      return parseBoxShadow(v);
    }

    return ThemeTokens(
      id: id,
      meta: meta ?? ThemeMeta(name: str('meta.name', fallback: id) ?? id),
      forceDark: forceDark,
      accent: col('--accent', const Color(0xFF6366F1)),
      accentLight: col('--accent-l', const Color(0xFF818CF8)),
      g1: col('--g1', const Color(0xFF6366F1)),
      g2: col('--g2', const Color(0xFF8B5CF6)),
      g3: col('--g3', const Color(0xFFD946EF)),
      page: col('--page', const Color(0xFFF8FAFC)),
      card: col('--card', Colors.white),
      cardBorder: col('--card-bd', const Color(0xFFF1F5F9)),
      cardRadius: num('--card-r', 20),
      cardShadow: shadows('--card-sh'),
      navBg: col('--nav-bg', Colors.white),
      navBorder: col('--nav-bd', const Color(0xFFE2E8F0)),
      text1: col('--text1', const Color(0xFF0F172A)),
      text2: col('--text2', const Color(0xFF64748B)),
      ink: col('--ink', const Color(0xFF0F172A)),
      appFont: str('--app-font', fallback: null),
    );
  }

  // ---- CSS 值解析工具（供主题与后续组件复用）----

  /// 解析 CSS 颜色：`#rgb` / `#rrggbb` / `#rrggbbaa` / `rgb(...)` / `rgba(...)` / `transparent`。
  static Color? parseColor(String input) {
    final s = input.trim().toLowerCase();
    if (s.isEmpty) return null;
    if (s == 'transparent') return Colors.transparent;
    if (s.startsWith('#')) {
      final hex = s.substring(1);
      int? val;
      if (hex.length == 3) {
        val = int.tryParse(
            '${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}', radix: 16);
        if (val == null) return null;
        return Color(0xFF000000 | val);
      }
      if (hex.length == 6 || hex.length == 8) {
        val = int.tryParse(hex, radix: 16);
        if (val == null) return null;
        if (hex.length == 6) return Color(0xFF000000 | val);
        // CSS RRGGBBAA → Flutter AARRGGBB
        final rrggbb = (val >> 8) & 0xFFFFFF;
        final aa = val & 0xFF;
        return Color((aa << 24) | rrggbb);
      }
      return null;
    }
    final rgbMatch = RegExp(r'rgba?\(([^)]+)\)').firstMatch(s);
    if (rgbMatch != null) {
      final parts =
          rgbMatch.group(1)!.split(',').map((e) => e.trim()).toList();
      if (parts.length < 3) return null;
      final r = _clampChannel(parts[0]);
      final g = _clampChannel(parts[1]);
      final b = _clampChannel(parts[2]);
      final a = parts.length >= 4 ? _clampAlpha(parts[3]) : 1.0;
      return Color.fromARGB(
        (a * 255).round().clamp(0, 255),
        r,
        g,
        b,
      );
    }
    return null;
  }

  static int _clampChannel(String v) {
    final n = double.tryParse(v.replaceAll(')', '')) ?? 0;
    return n.round().clamp(0, 255);
  }

  static double _clampAlpha(String v) {
    final n = double.tryParse(v) ?? 1;
    return n.clamp(0.0, 1.0);
  }

  /// 解析长度令牌（`20px` / `14` / `.5rem` 暂按 px 处理）为逻辑像素 double。
  static double? parseLength(String input) {
    final s = input.trim();
    final m = RegExp(r'^(-?\d*\.?\d+)').firstMatch(s);
    if (m == null) return null;
    return double.tryParse(m.group(1)!);
  }

  /// 解析 CSS box-shadow 串（支持逗号分隔多阴影，括号内逗号不切分）。
  static List<BoxShadow> parseBoxShadow(String input) {
    final segments = _splitTopLevelCommas(input);
    final result = <BoxShadow>[];
    for (final seg in segments) {
      final shadow = _parseSingleShadow(seg.trim());
      if (shadow != null) result.add(shadow);
    }
    return result;
  }

  static List<String> _splitTopLevelCommas(String s) {
    final out = <String>[];
    final buf = StringBuffer();
    var depth = 0;
    for (final ch in s.split('')) {
      if (ch == '(') depth++;
      if (ch == ')') depth--;
      if (ch == ',' && depth == 0) {
        out.add(buf.toString());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    if (buf.isNotEmpty) out.add(buf.toString());
    return out.where((e) => e.trim().isNotEmpty).toList();
  }

  static BoxShadow? _parseSingleShadow(String seg) {
    if (seg.isEmpty) return null;
    // 先摘出颜色（#hex / rgba(...) / rgb(...) / named），剩余按顺序为 offsetX offsetY blur [spread]
    final colorMatch =
        RegExp(r'(#[0-9a-fA-F]{3,8}|rgba?\([^)]*\)|transparent|white|black)')
            .firstMatch(seg);
    if (colorMatch == null) return null;
    final color = parseColor(colorMatch.group(0)!) ?? Colors.transparent;
    final rest = seg
        .replaceFirst(colorMatch.group(0)!, '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    final nums = rest.map((e) => parseLength(e)).whereType<double>().toList();
    final ox = nums.isNotEmpty ? nums[0] : 0.0;
    final oy = nums.length > 1 ? nums[1] : 0.0;
    final blur = nums.length > 2 ? nums[2] : 0.0;
    if (color == Colors.transparent && blur == 0) return null;
    return BoxShadow(
      color: color,
      offset: Offset(ox, oy),
      blurRadius: blur,
    );
  }
}
