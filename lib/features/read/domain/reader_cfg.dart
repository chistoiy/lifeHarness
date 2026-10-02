import 'dart:convert';
import 'dart:ui' show Color;

import '../../../core/theme/app_typography.dart' show LhFontRole, lhFontRoleOfReaderFont;

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
    this.font = 'serif', // LH-F01 拍板：正文默认族「系统默认」→「衬线」
    this.bright = false,
    this.auto = false,
    this.autoSecs = 10,
    this.lum = 100,
    this.indent = true,
    this.bgTex = '',
    this.bgImg = '',
    this.dim = 60,
    this.just = false,
    this.s2t = 'orig',
    this.indMode = 'auto',
  });

  final double fs, lh, ls, mar;

  /// day | eye | night | custom（custom 时 bg/fg 生效）。
  final String theme;

  /// page | scroll。
  final String mode;

  /// 自定义底色/字色（#rrggbb）。
  final String bg, fg;

  /// serif（**新默认**，LH-F01 拍板）| system（老用户落库的旧默认，白名单保留）| hei | mono。
  final String font;

  /// 屏幕常亮（wakelock）。
  final bool bright;

  /// 自动翻页 + 间隔秒（kBrAutos 档位）。
  final bool auto;
  final int autoSecs;

  /// 亮度遮罩百分比（30~100；100＝不遮挡，越低越暗）。
  final int lum;

  /// 首行缩进（原型 .brp text-indent:2em；关掉则段首不缩进）。
  /// R3-7 起为 [indMode] 的派生兼容位：indMode!='none' 即缩进开
  /// （旧逐书补丁/既有断言只认 indent，两键 toMap 同写保持一致）。
  final bool indent;

  /// 首行缩进三档（R3-7 · 原型 BR_IND_N）：auto 跟随原书 · 2 两全角 · none 无缩进。
  final String indMode;

  /// 两端对齐（R3-7 · 原型 brApJustTgl）。
  final bool just;

  /// 简繁（R3-7 · 原型 BR_S2T_N）：orig 跟随原书 · s 简体 · t 繁体。
  final String s2t;

  /// 轮5.1 背景纹理预设键（kBrTex：'' 无 · paper 纸纹 · kraft 牛皮 · grid 网格）。
  final String bgTex;

  /// 轮5.1 自选图片背景的**本机文件路径**（原型存 dataURL，Flutter 落私有目录存路径）。
  final String bgImg;

  /// 图片/纹理之上的白幕淡化百分比（0~90，越大越淡＝越盖白）。
  final int dim;

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

    // R3-7：indMode 三档优先；旧数据无 indMode 时由 indent 回落（false→none）。
    final im = const {'auto', '2', 'none'}.contains(m['indMode'])
        ? m['indMode'] as String
        : (m['indent'] == false ? 'none' : 'auto');
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
          : 'serif', // 缺键/脏值＝吃新默认衬线；`system` 仍在白名单里＝老用户读得回
      bright: m['bright'] == true,
      auto: m['auto'] == true,
      autoSecs: (m['autoSecs'] as num?)?.toInt() ?? 10,
      lum: ((m['lum'] as num?)?.toInt() ?? 100).clamp(30, 100),
      indent: im != 'none',
      bgTex: kBrTex.containsKey(ss('bgTex', '')) ? ss('bgTex', '') : '',
      bgImg: ss('bgImg', ''),
      dim: ((m['dim'] as num?)?.toInt() ?? 60).clamp(0, 90),
      just: m['just'] == true,
      s2t: const {'orig', 's', 't'}.contains(m['s2t']) ? m['s2t'] as String : 'orig',
      indMode: im,
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
    'indent': indMode != 'none',
    'indMode': indMode,
    'bgTex': bgTex,
    'bgImg': bgImg,
    'dim': dim,
    'just': just,
    's2t': s2t,
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
    String? indMode,
    String? bgTex,
    String? bgImg,
    int? dim,
    bool? just,
    String? s2t,
  }) {
    // indMode 为准；只传 indent 时同步换算（true 时若原为 none 回落 auto）。
    final im =
        indMode ??
        (indent == null
            ? this.indMode
            : indent
            ? (this.indMode == 'none' ? 'auto' : this.indMode)
            : 'none');
    return ReaderCfg(
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
      indent: im != 'none',
      indMode: im,
      bgTex: bgTex ?? this.bgTex,
      bgImg: bgImg ?? this.bgImg,
      dim: dim ?? this.dim,
      just: just ?? this.just,
      s2t: s2t ?? this.s2t,
    );
  }

  Color get bgColor => _parseHex(bg, const Color(0xFFFAF6EE));
  Color get textColor => _parseHex(fg, const Color(0xFF3B3630));

  /// 字族角色（LH-F01）：三值族 → CJK 回落链的映射**只此一处定义**
  /// （`core/theme/app_typography.dart`），`ReaderLayout` 也走它——
  /// 测量与渲染两边各算一份必出空页/错页。`system` 返回 null＝不指定，照旧跟随平台。
  LhFontRole? get fontRole => lhFontRoleOfReaderFont(font);
  String? get fontFamily => fontRole?.first;
  List<String>? get fontFamilyFallback => fontRole?.fallback;

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

/// 纹理背景（V1.53.2 轮5.1 · 原型 BR_TEX；''＝无，选中即回到纯色）。
/// Flutter 侧不用 CSS 渐变串，键即绘制方案（见 reader_bg.dart 的 CustomPainter）。
const kBrTex = {'': '无', 'paper': '纸纹', 'kraft': '牛皮', 'grid': '网格'};

/// 字体（原型 BR_FONTS：系统字体 · 可扩展下载控制包体积）。
const kBrFonts = {
  'system': '系统默认',
  'serif': '宋体',
  'hei': '黑体',
  'mono': '等宽',
};

/// 字体分类（R3-7 字体二级页 chips · 原型 BR_FONTS 第三元口径）：
/// 等宽/行书类归「其他」；kBrFonts 的 key 必须在此表内，缺归「其他」。
const kBrFontCats = {
  'system': '系统',
  'serif': '衬线',
  'hei': '黑体',
  'mono': '其他',
};
String brFontCat(String key) => kBrFontCats[key] ?? '其他';

/// 自动翻页间隔档位（原型 BR_AUTOS）。
const kBrAutos = [3, 5, 8, 10, 15, 20, 30, 45, 60];

/// 页边距三档文案（原型：≤12 窄 / ≥36 宽 / 其余 中）。
String brMarLabel(double mar) => mar <= 12 ? '窄' : mar >= 36 ? '宽' : '中';
