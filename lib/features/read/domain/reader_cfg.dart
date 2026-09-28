import 'dart:convert';
import 'dart:ui' show Color;

/// 阅读外观配置（V1.50 批4 · 原型 lh_reader_bs_v1 的 brCfg/brBooksCfg 口径）。
///
/// 存储两档：kv `reader.cfg` ＝ 全局默认（完整对象）；
/// kv `reader.cfg.<bookId>` ＝ 本书覆盖补丁（只存被改键，原型 A± 只写 fs）。
/// 生效值 = merge(全局, 补丁)。外观面板草稿制：取消丢弃、保存应用按作用域落库。
class ReaderCfg {
  const ReaderCfg({
    this.fs = 19,
    this.lh = 1.62,
    this.ls = 0.4,
    this.mar = 22,
    this.theme = 'day',
    this.mode = 'page',
    this.bg = '#faf6ee',
    this.fg = '#3b3630',
    this.font = 'system',
    this.bright = false,
    this.auto = false,
    this.autoSecs = 10,
    this.lum = 100,
    this.indent = true,
  });

  final double fs, lh, ls, mar;

  /// day | eye | night | custom（custom 时 bg/fg 生效）。
  final String theme;

  /// page | scroll。
  final String mode;

  /// 自定义底色/字色（#rrggbb）。
  final String bg, fg;

  /// system | serif | hei | mono。
  final String font;

  /// 屏幕常亮（wakelock）。
  final bool bright;

  /// 自动翻页 + 间隔秒（kBrAutos 档位）。
  final bool auto;
  final int autoSecs;

  /// 亮度遮罩百分比（30~100；100＝不遮挡，越低越暗）。
  final int lum;

  /// 首行缩进（原型 .brp text-indent:2em；关掉则段首不缩进）。
  final bool indent;

  static const defaults = ReaderCfg();

  factory ReaderCfg.decode(String? raw) {
    try {
      final v = raw == null ? null : jsonDecode(raw);
      if (v is! Map) return defaults;
      return ReaderCfg.fromMap(v.cast<Object?, Object?>());
    } catch (_) {
      return defaults;
    }
  }

  factory ReaderCfg.fromMap(Map<Object?, Object?> m) {
    double dd(String k, double f) => (m[k] as num?)?.toDouble() ?? f;
    String ss(String k, String f) {
      final v = m[k]?.toString();
      return v == null || v.isEmpty ? f : v;
    }

    return ReaderCfg(
      fs: dd('fs', 19).clamp(14, 30).toDouble(),
      lh: dd('lh', 1.62).clamp(1.3, 2.4).toDouble(),
      ls: dd('ls', 0.4).clamp(0, 3).toDouble(),
      mar: dd('mar', 22).clamp(8, 40).toDouble(),
      theme: const {'day', 'eye', 'night', 'custom'}.contains(m['theme'])
          ? m['theme'] as String
          : 'day',
      mode: m['mode'] == 'scroll' ? 'scroll' : 'page',
      bg: _hexOr(ss('bg', '#faf6ee'), '#faf6ee'),
      fg: _hexOr(ss('fg', '#3b3630'), '#3b3630'),
      font: const {'system', 'serif', 'hei', 'mono'}.contains(m['font'])
          ? m['font'] as String
          : 'system',
      bright: m['bright'] == true,
      auto: m['auto'] == true,
      autoSecs: (m['autoSecs'] as num?)?.toInt() ?? 10,
      lum: ((m['lum'] as num?)?.toInt() ?? 100).clamp(30, 100),
      indent: m['indent'] != false,
    );
  }

  /// 全局 + 本书补丁 → 生效值。
  static ReaderCfg mergePatch(ReaderCfg base, Map<String, dynamic> patch) =>
      ReaderCfg.fromMap({...base.toMap(), ...patch});

  Map<String, dynamic> toMap() => {
    'fs': fs,
    'lh': lh,
    'ls': ls,
    'mar': mar,
    'theme': theme,
    'mode': mode,
    'bg': bg,
    'fg': fg,
    'font': font,
    'bright': bright,
    'auto': auto,
    'autoSecs': autoSecs,
    'lum': lum,
    'indent': indent,
  };

  String encode() => jsonEncode(toMap());

  ReaderCfg copyWith({
    double? fs,
    double? lh,
    double? ls,
    double? mar,
    String? theme,
    String? mode,
    String? bg,
    String? fg,
    String? font,
    bool? bright,
    bool? auto,
    int? autoSecs,
    int? lum,
    bool? indent,
  }) => ReaderCfg(
    fs: fs ?? this.fs,
    lh: lh ?? this.lh,
    ls: ls ?? this.ls,
    mar: mar ?? this.mar,
    theme: theme ?? this.theme,
    mode: mode ?? this.mode,
    bg: bg ?? this.bg,
    fg: fg ?? this.fg,
    font: font ?? this.font,
    bright: bright ?? this.bright,
    auto: auto ?? this.auto,
    autoSecs: autoSecs ?? this.autoSecs,
    lum: lum ?? this.lum,
    indent: indent ?? this.indent,
  );

  Color get bgColor => _parseHex(bg, const Color(0xFFFAF6EE));
  Color get textColor => _parseHex(fg, const Color(0xFF3B3630));

  /// Flutter 泛族字体映射（Android 内置族名；系统默认＝不指定）。
  String? get fontFamily => switch (font) {
    'serif' => 'serif',
    'hei' => 'sans-serif',
    'mono' => 'monospace',
    _ => null,
  };

  static String _hexOr(String v, String def) =>
      RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v) ? v.toLowerCase() : def;

  static Color _parseHex(String v, Color def) {
    final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(v);
    if (m == null) return def;
    return Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
  }
}

/// 内置主题（原型 BR_THEMES 三色卡；自定义走 bg/fg）。
const kBrThemes = {
  'day': ('日间', Color(0xFFFAF6EE), Color(0xFF3B3630)),
  'eye': ('护眼', Color(0xFFCFE6CF), Color(0xFF2F4A33)),
  'night': ('夜间', Color(0xFF101317), Color(0xFF9AA4B0)),
};
const kBrThemeOrder = ['day', 'eye', 'night'];

/// 背景预设（V1.53 轮3 参考图2「背景」5 缩略图；选中即 custom 底色）。
const kBrBgs = ['#faf6ee', '#f5edda', '#f2f3f5', '#f6e7d3', '#dfe8f4'];

/// 字体（原型 BR_FONTS：系统字体 · 可扩展下载控制包体积）。
const kBrFonts = {
  'system': '系统默认',
  'serif': '宋体',
  'hei': '黑体',
  'mono': '等宽',
};

/// 自动翻页间隔档位（原型 BR_AUTOS）。
const kBrAutos = [3, 5, 8, 10, 15, 20, 30, 45, 60];

/// 页边距三档文案（原型：≤12 窄 / ≥36 宽 / 其余 中）。
String brMarLabel(double mar) => mar <= 12 ? '窄' : mar >= 36 ? '宽' : '中';
