/// 布局预设（批4 F4-8 · 冻结方案 §2.6 `预设 = struct × dir × 容器比例`）。
///
/// **4 形态＝两个正交维度**：`struct(tree/radial) × dir(right/both)`，
/// 默认 `tree/right`。第三维 `ratio(portrait/landscape)` 是**容器比例**：
/// `landscape`＝横向布局预览——App 内**不转屏**（C13：不接全局
/// `Orientation`、不改 `app.dart`），只把画布按横向比例重排。
///
/// 预设表逐字照抄原型 `LAY_PRESETS`（键/标题/副标一字不改）——UI 铁律
/// 「先原型后实现」，改这里就得先改原型。
///
/// **存储走 prefs、每图一套、直读 `sharedPreferencesProvider`**（同批3
/// `MmStyleStore`）：单 key `lh.mm_layouts` 装 `mapId→presetKey` 的 JSON map。
/// **不走 `SettingsRepository`**（那是全局单例设置通道，且加设置项须四处
/// 同步）；预算是「每图一套」，塞进全局设置模型会污染语义。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'mindmap_layout.dart';
import 'mindmap_models.dart';

// ==================== 预设值对象 ====================

/// 布局预设值对象（`struct × dir × ratio` 三元组）。
///
/// 用**字符串档位**而非枚举——与节点 `side` 列、批3 样式档位同一口径
/// （存语义 key 不存计算结果；换实现/加档位不迁数据）。
class MmLayoutPreset {
  const MmLayoutPreset({
    required this.struct,
    required this.dir,
    required this.ratio,
  });

  /// 纵向树（父在上、子在下、缩进表层级）。
  static const String sTree = 'tree';

  /// 放射（根居中、子级按角度铺同心圆）。
  static const String sRadial = 'radial';

  /// 只向右延伸。
  static const String dRight = 'right';

  /// 左右双向（子节点均分两侧、奇数右侧多一个）。
  static const String dBoth = 'both';

  /// 竖屏友好。
  static const String rPortrait = 'portrait';

  /// 横向布局预览（App 内不转屏）。
  static const String rLandscape = 'landscape';

  /// 默认＝纵向树＋向右＋竖屏（C12：竖屏可读性最好）。
  static const MmLayoutPreset defaults =
      MmLayoutPreset(struct: sTree, dir: dRight, ratio: rPortrait);

  final String struct;
  final String dir;
  final String ratio;

  /// 预设键（三段以 `/` 连接，**即持久化与传参的形态**，照原型 `k`）。
  String get key => '$struct/$dir/$ratio';

  bool get isRadial => struct == sRadial;
  bool get isBoth => dir == dBoth;
  bool get isLandscape => ratio == rLandscape;

  MmLayoutPreset copyWith({String? struct, String? dir, String? ratio}) =>
      MmLayoutPreset(
        struct: struct ?? this.struct,
        dir: dir ?? this.dir,
        ratio: ratio ?? this.ratio,
      );

  /// 按预设挑引擎（工厂口径：预设是唯一入口，页面不许自己 if）。
  ///
  /// 注意 **`ratio` 不参与挑引擎**：横向预览不是第四套算法，而是
  /// 「`tree` ＋ 横向列排」——由 `landscape` 强制 `dir` 走横向树（原型
  /// `layout()` 里 `VIEW.ratio==='landscape'` 与 `dir==='both'` 共用
  /// `posTree` 那一条分支）。
  LayoutEngine engine({MmMeasure? measure}) {
    if (struct == sRadial) {
      return RadialEngine(both: dir == dBoth, measure: measure);
    }
    final useBoth = dir == dBoth || ratio == rLandscape;
    return HorizontalTreeEngine(both: useBoth, measure: measure);
  }

  /// 解析预设键（`tree/right/portrait`）。**不认识的档位逐段回落默认**
  /// ——用户数据/prefs 损坏不许炸页面（与 `MmStyleStore.load` 同口径）。
  static MmLayoutPreset parse(String? raw) {
    if (raw == null || raw.isEmpty) return defaults;
    final parts = raw.split('/');
    if (parts.length != 3) return defaults;
    return MmLayoutPreset(
      struct: parts[0] == sRadial ? sRadial : sTree,
      dir: parts[1] == dBoth ? dBoth : dRight,
      ratio: parts[2] == rLandscape ? rLandscape : rPortrait,
    );
  }

  @override
  String toString() => key;

  @override
  bool operator ==(Object other) =>
      other is MmLayoutPreset &&
      other.struct == struct &&
      other.dir == dir &&
      other.ratio == ratio;

  @override
  int get hashCode => Object.hash(struct, dir, ratio);
}

/// 预设卡（弹层 UI 与卡片副标的数据源；照原型 `LAY_PRESETS` 四行）。
class MmLayoutCard {
  const MmLayoutCard({
    required this.preset,
    required this.title,
    required this.sub,
  });

  final MmLayoutPreset preset;

  /// 卡面主标（如「纵向树」）。
  final String title;

  /// 卡面副标（如「竖屏默认」）。
  final String sub;

  /// 卡面缩略图形态（原型 `LAY_SVG` 的分支标识：outline/hright/hboth/radial）。
  String get icon => preset.isRadial
      ? 'radial'
      : preset.isBoth
          ? 'hboth'
          : (preset.isLandscape ? 'hright' : 'outline');
}

/// 四张预设卡（**逐字照抄原型 `LAY_PRESETS`**，不增不减不换词）。
const List<MmLayoutCard> mmLayoutCards = [
  MmLayoutCard(
      preset: MmLayoutPreset(
          struct: MmLayoutPreset.sTree,
          dir: MmLayoutPreset.dRight,
          ratio: MmLayoutPreset.rPortrait),
      title: '纵向树',
      sub: '竖屏默认'),
  MmLayoutCard(
      preset: MmLayoutPreset(
          struct: MmLayoutPreset.sTree,
          dir: MmLayoutPreset.dRight,
          ratio: MmLayoutPreset.rLandscape),
      title: '横向树',
      sub: '父左子右'),
  MmLayoutCard(
      preset: MmLayoutPreset(
          struct: MmLayoutPreset.sTree,
          dir: MmLayoutPreset.dBoth,
          ratio: MmLayoutPreset.rLandscape),
      title: '双向树',
      sub: '子级分列两侧'),
  MmLayoutCard(
      preset: MmLayoutPreset(
          struct: MmLayoutPreset.sRadial,
          dir: MmLayoutPreset.dBoth,
          ratio: MmLayoutPreset.rPortrait),
      title: '放射图',
      sub: '根居中四面铺开'),
];

// ==================== prefs 存取（每图一套） ====================

/// 布局预设存储（批4）：单 key `lh.mm_layouts` 装 `mapId→presetKey`。
/// **每图一套的隔离点**＝只改自己那一格（刀2 钉这里）。
class MmLayoutStore {
  const MmLayoutStore(this.prefs);

  final SharedPreferences prefs;

  static const String key = 'lh.mm_layouts';

  /// 读一张图的预设：**未设过返回 null**（＝用 [MmLayoutPreset.defaults]，
  /// 与批3「未设样式返回 null 走基线绘制面」同款——null 有别于「显式设成默认」）。
  MmLayoutPreset? load(int mapId) {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      // catch-ok: prefs 里的布局 JSON 是本模块自己写的，损坏只可能来自外部
      // 改文件/旧版残留——按「未设」回落（走默认预设），不炸页面。
      return null;
    }
    if (decoded is! Map) return null;
    final one = decoded[mapId.toString()];
    if (one is! String) return null;
    return MmLayoutPreset.parse(one);
  }

  /// 存一张图的预设（只改自己那一格，其余图原样保留）。
  Future<void> save(int mapId, MmLayoutPreset preset) async {
    final all = _readAll();
    all[mapId.toString()] = preset.key;
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
      // catch-ok: 损坏 JSON 当空表，下一笔 save 覆盖成合法值，不抛。
    }
    return <String, dynamic>{};
  }
}

// ==================== 便捷口径 ====================

/// 按预设对整图算基线（页面/导出统一走这一条，禁各处自己 new 引擎）。
MmLayoutResult mmLayoutOf(
  MmLayoutPreset preset,
  List<MindmapNode> nodes, {
  MmMeasure? measure,
}) =>
    preset.engine(measure: measure).layout(nodes);