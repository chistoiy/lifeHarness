/// 思维导图样式层（批3 F4-7 · 冻结方案 §2 样式层 · 原型 `sheetMm-style`）。
///
/// 两条产品拍板（工单 §4d.0，本件即规格）：
/// · **档位存语义 key，绘制时经令牌解析成实际色**——禁存色值。换肤/深浅色
///   切换后样式仍跟随（原型副标承诺「自动跟随 4 套主题与深浅色」）。
/// · **prefs 单 key `lh.mm_styles` 装 `mapId→style` 的 JSON map**＝每图一套
///   （原型 `style` 挂在 `cur` 上，新建图各自 `Object.assign({},DEFAULT_STYLE)`）。
///   刻意**不走 `SettingsRepository`**：那是全局单例设置通道，「每图一套」
///   塞进去会污染全局设置模型——照 `read_settings_page.dart` 等先例直读
///   `sharedPreferencesProvider`。
///
/// 「默认」档＝**回落令牌原值**：解析不出就返回 `null` 让调用方用现值，
/// 于是**未设样式的图零视觉变化**（用例②逐值钉这条）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一张图的样式档（值对象，六字段皆语义 key 或数值，**零色值**）。
class MmStyle {
  const MmStyle({
    this.text = kTextDefault,
    this.size = kSizeMd,
    this.bg = kBgPaper,
    this.line = kLineDefault,
    this.lineW = 1.6,
    this.canvas = kCanvasDots,
  });

  /// 文字色：`default` 默认 / `accent` 主题 / `muted` 弱化 / `warn` 警示。
  final String text;

  /// 字号档：`sm` 小 / `md` 中 / `lg` 大。
  final String size;

  /// 节点底色：`paper` 纸 / `soft` 浅主题 / `deep` 深主题。
  final String bg;

  /// 连线色：`default` 默认 / `accent` 主题 / `muted` 弱化。
  final String line;

  /// 连线粗细：0.8~4.0，步进 0.4。
  final double lineW;

  /// 画布背景：`dots` 网点 / `plain` 纯色 / `tint` 主题浅 / `deep` 主题深。
  final String canvas;

  static const String kTextDefault = 'default';
  static const String kTextAccent = 'accent';
  static const String kTextMuted = 'muted';
  static const String kTextWarn = 'warn';

  static const String kSizeSm = 'sm';
  static const String kSizeMd = 'md';
  static const String kSizeLg = 'lg';

  static const String kBgPaper = 'paper';
  static const String kBgSoft = 'soft';
  static const String kBgDeep = 'deep';

  static const String kLineDefault = 'default';
  static const String kLineAccent = 'accent';
  static const String kLineMuted = 'muted';

  static const String kCanvasDots = 'dots';
  static const String kCanvasPlain = 'plain';
  static const String kCanvasTint = 'tint';
  static const String kCanvasDeep = 'deep';

  /// 档位取值域（照抄原型 `STYLE_DEFS`，逐字不增不减；弹层按钮由此生成）。
  static const Map<String, List<String>> levelDomain = {
    'text': [kTextDefault, kTextAccent, kTextMuted, kTextWarn],
    'size': [kSizeSm, kSizeMd, kSizeLg],
    'bg': [kBgPaper, kBgSoft, kBgDeep],
    'line': [kLineDefault, kLineAccent, kLineMuted],
    'canvas': [kCanvasDots, kCanvasPlain, kCanvasTint, kCanvasDeep],
  };

  /// 中文标签（原型 `STYLE_DEFS` 第二列）。
  /// 键＝`kind:level`（`default`/`accent`/`muted` 在 text 与 line 两域同名，
  /// 单层键会撞车——const map 撞键是编译错，这里按 `kind:level` 消歧）。
  static const Map<String, String> labels = {
    'text:$kTextDefault': '默认',
    'text:$kTextAccent': '主题',
    'text:$kTextMuted': '弱化',
    'text:$kTextWarn': '警示',
    'size:$kSizeSm': '小',
    'size:$kSizeMd': '中',
    'size:$kSizeLg': '大',
    'bg:$kBgPaper': '纸',
    'bg:$kBgSoft': '浅主题',
    'bg:$kBgDeep': '深主题',
    'line:$kLineDefault': '默认',
    'line:$kLineAccent': '主题',
    'line:$kLineMuted': '弱化',
    'canvas:$kCanvasDots': '网点',
    'canvas:$kCanvasPlain': '纯色',
    'canvas:$kCanvasTint': '主题浅',
    'canvas:$kCanvasDeep': '主题深',
  };

  /// 取某域某档的中文标签（未登记回落档位原串）。
  static String label(String kind, String level) =>
      labels['$kind:$level'] ?? level;

  /// 默认档位（＝原型 `DEFAULT_STYLE`）。
  static const MmStyle defaults =
      MmStyle(text: kTextDefault, size: kSizeMd, bg: kBgPaper, line: kLineDefault, lineW: 1.6, canvas: kCanvasDots);

  double get fontSize => size == kSizeSm
      ? 12.0
      : size == kSizeLg
          ? 16.0
          : 13.5; // md 对齐 painter 批2 基线 13.5（原型 13px 是 CSS 近似值）

  MmStyle copyWith({
    String? text,
    String? size,
    String? bg,
    String? line,
    double? lineW,
    String? canvas,
  }) =>
      MmStyle(
        text: text ?? this.text,
        size: size ?? this.size,
        bg: bg ?? this.bg,
        line: line ?? this.line,
        lineW: lineW ?? this.lineW,
        canvas: canvas ?? this.canvas,
      );

  Map<String, dynamic> toJson() => {
        'text': text,
        'size': size,
        'bg': bg,
        'line': line,
        'lineW': lineW,
        'canvas': canvas,
      };

  /// 反序列化**逐字段**兜底：任一字段类型不符/越界/未知档位 ⇒ 该字段回落
  /// 默认（其余字段照用）。存量 JSON 缺字段、损坏 JSON 都走这里。
  factory MmStyle.fromJson(Map<String, dynamic>? j) {
    if (j == null) return defaults;
    String pick(String kind, String field, String fallback) {
      final v = j[field];
      final ok = v is String && (levelDomain[kind] ?? const []).contains(v);
      return ok ? v : fallback;
    }

    final w = j['lineW'];
    return MmStyle(
      text: pick('text', 'text', kTextDefault),
      size: pick('size', 'size', kSizeMd),
      bg: pick('bg', 'bg', kBgPaper),
      line: pick('line', 'line', kLineDefault),
      lineW: (w is num && w >= 0.8 && w <= 4.0) ? w.toDouble() : 1.6,
      canvas: pick('canvas', 'canvas', kCanvasDots),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MmStyle &&
      other.text == text &&
      other.size == size &&
      other.bg == bg &&
      other.line == line &&
      other.lineW == lineW &&
      other.canvas == canvas;

  @override
  int get hashCode => Object.hash(text, size, bg, line, lineW, canvas);

  @override
  String toString() => 'MmStyle(${toJson()})';
}

// ======================== 档位 → 令牌解析 ========================

/// 文字色解析：`default` 档返回 **null**（回落调用方现值）；其余档经
/// `ColorScheme`（由设计令牌派生）解析成实际色——深浅主题自动不同。
Color? mmResolveTextColor(String level, ColorScheme cs) => switch (level) {
      MmStyle.kTextAccent => cs.primary,
      MmStyle.kTextMuted => cs.onSurfaceVariant,
      MmStyle.kTextWarn => cs.error,
      _ => null,
    };

/// 连线色解析：`default` 档返回 null（回落）。
Color? mmResolveLineColor(String level, ColorScheme cs) => switch (level) {
      MmStyle.kLineAccent => cs.primary,
      MmStyle.kLineMuted => cs.outlineVariant,
      _ => null,
    };

/// 节点底色解析：`paper` 档返回 null（回落调用方现值）；soft/deep 由
/// 主题色按原型比例（8% / 18%）混出——派生色一律 alphaBlend，**不写
/// `Color(0x…)` 字面量**（色值棘轮零增长）。
Color? mmResolveNodeBg(String level, ColorScheme cs) => switch (level) {
      MmStyle.kBgSoft =>
        Color.alphaBlend(cs.primary.withValues(alpha: .08), cs.surfaceContainerHighest),
      MmStyle.kBgDeep =>
        Color.alphaBlend(cs.primary.withValues(alpha: .18), cs.surfaceContainerHighest),
      _ => null,
    };

/// 画布底色解析：`dots` 档返回 null（＝基线底色＋画网点）；plain 取卡片色，
/// tint/deep 由主题色按原型比例（6% / 14%）混出。
Color? mmResolveCanvasBg(String level, ColorScheme cs) => switch (level) {
      MmStyle.kCanvasPlain => cs.surface,
      MmStyle.kCanvasTint => Color.alphaBlend(cs.primary.withValues(alpha: .06), cs.surface),
      MmStyle.kCanvasDeep => Color.alphaBlend(cs.primary.withValues(alpha: .14), cs.surface),
      _ => null,
    };

/// 网点是否绘制：`dots` 档画，其余档（纯色/主题浅/主题深）**不画**——
/// 对应原型 `cv.style.background` 覆盖掉网点底纹。
bool mmCanvasDots(String level) => level == MmStyle.kCanvasDots;

/// 画布绘制面的一份**完整**样式入参（画布与 PNG 导出共用同一份 → 导出即所见）。
///
/// 基线值取自批2 painter 调用点（未设样式 ⇒ 逐值相等，用例②钉）。
class MmPaintStyle {
  const MmPaintStyle({
    required this.bg,
    required this.grid,
    required this.nodeBg,
    required this.nodeBorder,
    required this.nodeText,
    required this.edge,
    required this.accent,
    required this.accentSoft,
    required this.lineW,
    required this.fontSize,
    required this.dots,
  });

  /// 未设样式的基线（批2 原样）。
  factory MmPaintStyle.baseline(ColorScheme cs) => MmPaintStyle(
        bg: cs.surface,
        grid: cs.onSurface.withValues(alpha: .06),
        nodeBg: cs.surfaceContainerHighest,
        nodeBorder: cs.outlineVariant,
        nodeText: cs.onSurface,
        edge: cs.outline,
        accent: cs.primary,
        accentSoft: cs.primary.withValues(alpha: .14),
        lineW: 1.2,
        fontSize: 13.5,
        dots: true,
      );

  final Color bg, grid, nodeBg, nodeBorder, nodeText, edge, accent, accentSoft;
  final double lineW;

  /// 节点标题基准字号（painter 与度量同源，painter 再乘缩放）。
  final double fontSize;

  /// 是否画网点底纹。
  final bool dots;

  /// 应用一张图的档位（`style == null` ＝未设样式 ⇒ 返回基线本身）。
  factory MmPaintStyle.of(MmStyle? style, ColorScheme cs) {
    final base = MmPaintStyle.baseline(cs);
    if (style == null) return base;
    return MmPaintStyle(
      bg: mmResolveCanvasBg(style.canvas, cs) ?? base.bg,
      grid: base.grid,
      nodeBg: mmResolveNodeBg(style.bg, cs) ?? base.nodeBg,
      nodeBorder: base.nodeBorder,
      nodeText: mmResolveTextColor(style.text, cs) ?? base.nodeText,
      edge: mmResolveLineColor(style.line, cs) ?? base.edge,
      accent: base.accent,
      accentSoft: base.accentSoft,
      lineW: style.lineW,
      fontSize: style.fontSize,
      dots: mmCanvasDots(style.canvas),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MmPaintStyle &&
      other.bg == bg &&
      other.grid == grid &&
      other.nodeBg == nodeBg &&
      other.nodeBorder == nodeBorder &&
      other.nodeText == nodeText &&
      other.edge == edge &&
      other.accent == accent &&
      other.accentSoft == accentSoft &&
      other.lineW == lineW &&
      other.fontSize == fontSize &&
      other.dots == dots;

  @override
  int get hashCode =>
      Object.hash(bg, grid, nodeBg, nodeBorder, nodeText, edge, accent, accentSoft, lineW, fontSize, dots);
}

// ======================== prefs 存取（每图一套） ========================

/// 样式存储（批3 §4d.0 拍板①）：单 key `lh.mm_styles` 装 `mapId→style` 的
/// JSON map。**不碰 `SettingsRepository`**（那是全局单例设置通道）。
class MmStyleStore {
  const MmStyleStore(this.prefs);

  final SharedPreferences prefs;

  static const String key = 'lh.mm_styles';

  /// 读一张图的样式：**未设过返回 null**（＝未设样式，走基线绘制面）；
  /// 损坏 JSON / 类型不符一律返回 null 而非抛（用户数据不可炸页面）。
  MmStyle? load(int mapId) {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      // catch-ok: prefs 里的样式 JSON 是本模块自己写的，损坏只可能来自外部改
      // 文件/旧版残留——按「未设样式」回落（走基线绘制面），不炸页面。
      return null;
    }
    if (decoded is! Map) return null;
    final one = decoded[mapId.toString()];
    if (one is! Map) return null;
    return MmStyle.fromJson(Map<String, dynamic>.from(one));
  }

  /// 存一张图的样式（只改自己那一格，其余图原样保留——每图一套的隔离点）。
  Future<void> save(int mapId, MmStyle style) async {
    final all = _readAll();
    all[mapId.toString()] = style.toJson();
    await prefs.setString(key, jsonEncode(all));
  }

  /// 恢复某图默认（删该格；删到空则整 key 清掉）。
  Future<void> reset(int mapId) async {
    final all = _readAll();
    all.remove(mapId.toString());
    if (all.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, jsonEncode(all));
  }

  Map<String, dynamic> _readAll() {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      // 损坏 JSON 当空表：下一笔 save 会覆盖成合法值，不抛。
      // catch-ok: 同 load()——用户数据损坏走回落而非中断。
    }
    return <String, dynamic>{};
  }
}