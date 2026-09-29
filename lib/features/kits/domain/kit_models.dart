/// 小工具合集 · 工具与分类登记（V1.47 模块14 · 计划 §2）。
///
/// 与原型 `prototype/index-kits.html` 的 `TOOLS` / `TOOL_CATS` 同源：
/// 13 个内置工具、9 个分类。[KitTool.key] 即 `kit_usage.tool` 列取值，也是
/// 路由 `/kits/tool/<key>` 的参数，改名等于改数据，务必与原型保持一致。
/// 图标一律 `IconData`（红线：UI 不用 emoji，原型侧已全站线性化）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

enum KitCat {
  network('网络', Icons.public),
  length('长度', Icons.straighten),
  random('随机', Icons.casino),
  color('色彩', Icons.palette_outlined),
  calc('计算', Icons.calculate_outlined),
  image('图片', Icons.image_outlined),
  encode('编码', Icons.code),
  ai('智能', Icons.smart_toy_outlined),
  demo('演示', Icons.subtitles_outlined);

  const KitCat(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// 内置工具描述符。
class KitTool {
  const KitTool({
    required this.key,
    required this.name,
    required this.cat,
    required this.icon,
    this.privacy = '本地计算 · 抓包 0 请求',
  });

  final String key;
  final String name;
  final KitCat cat;
  final IconData icon;

  /// 页脚隐私口径（原型全站统一「本地计算 · 抓包 0 请求」；网络类如实标注）。
  final String privacy;
}

/// 13 个内置工具（顺序=原型「全部工具」网格默认序）。
const List<KitTool> kKitTools = [
  // 网络两件是「模拟网络层」（交棒话术 §三.1）：页脚必须与其余本机工具的
  // 「本地计算」口径区分开，否则用户以为真发了请求。
  KitTool(
    key: 'ping',
    name: 'Ping 工具',
    cat: KitCat.network,
    icon: Icons.network_ping,
    privacy: '模拟网络层 · 不发真实请求',
  ),
  KitTool(
    key: 'speed',
    name: '网络测速',
    cat: KitCat.network,
    icon: Icons.speed,
    privacy: '模拟网络层 · 不发真实请求',
  ),
  KitTool(key: 'ruler', name: '尺子', cat: KitCat.length, icon: Icons.straighten),
  KitTool(
    key: 'dist',
    name: '测距',
    cat: KitCat.length,
    icon: Icons.route,
    privacy: '本地计算 · 地图为模拟网格 · 抓包 0 请求',
  ),
  KitTool(
    key: 'wheel',
    name: '轮盘抽签',
    cat: KitCat.random,
    icon: Icons.pie_chart_outline,
  ),
  KitTool(key: 'rand', name: '随机数', cat: KitCat.random, icon: Icons.casino),
  KitTool(key: 'pick', name: '取色盘', cat: KitCat.color, icon: Icons.colorize),
  KitTool(
    key: 'comp',
    name: '互补色方案',
    cat: KitCat.color,
    icon: Icons.format_color_fill,
  ),
  KitTool(
    key: 'datec',
    name: '日期计算',
    cat: KitCat.calc,
    icon: Icons.calculate_outlined,
  ),
  KitTool(key: 'imgz', name: '图片体积缩小', cat: KitCat.image, icon: Icons.compress),
  KitTool(key: 'b64', name: 'Base64 转换', cat: KitCat.encode, icon: Icons.code),
  KitTool(
    key: 'aiapi',
    name: 'AI API 验证',
    cat: KitCat.ai,
    icon: Icons.smart_toy_outlined,
    privacy: '按所填端点发出请求 · 其余工具零出站',
  ),
  KitTool(
    key: 'tele',
    name: '提词器',
    cat: KitCat.demo,
    icon: Icons.subtitles_outlined,
  ),
];

/// 按 key 取工具（未登记返回 null，由调用侧决定回落）。
KitTool? kitToolOf(String key) {
  for (final t in kKitTools) {
    if (t.key == key) return t;
  }
  return null;
}

/// 工具键常量（= `kKitTools` 里的 key，也是 `kit_tool_data.tool` 取值；
/// 批2 起各工具屏用它读写私有数据，改这里等于改数据，须与原型一致）。
const String kitToolKeyDatec = 'datec';
const String kitToolKeyRand = 'rand';
const String kitToolKeyWheel = 'wheel';
const String kitToolKeyPick = 'pick';
const String kitToolKeyComp = 'comp';
const String kitToolKeyPing = 'ping';
const String kitToolKeySpeed = 'speed';
const String kitToolKeyRuler = 'ruler';
const String kitToolKeyDist = 'dist';
const String kitToolKeyImgz = 'imgz';
const String kitToolKeyB64 = 'b64';
const String kitToolKeyTele = 'tele';
const String kitToolKeyAiapi = 'aiapi';

/// hero 数据位候选（原型 `KIT_METRICS` 八项；配置弹层从中选四枚）。
enum KitMetric {
  total('累计使用'),
  week('近7天'),
  today('今日'),
  fav('收藏'),
  recent('足迹工具'),
  plug('已装插件'),
  plugOn('启用插件'),
  size('插件体积');

  const KitMetric(this.label);

  final String label;

  static KitMetric fromId(String id) =>
      KitMetric.values.firstWhere((m) => m.name == id, orElse: () => total);
}

/// 默认四枚数据位（原型 `KITS.hero`：累计使用 / 近7天 / 收藏 / 已装插件）。
const List<KitMetric> kKitHeroDefault = [
  KitMetric.total,
  KitMetric.week,
  KitMetric.fav,
  KitMetric.plug,
];

/// 使用来源：内置工具与插件工具分账（统计页「插件使用」卡只取 plugin）。
const String kKitKindBuiltin = 'builtin';
const String kKitKindPlugin = 'plugin';

/// `kit_usage` 行模型（一条=一次使用；原型 `{k, ts}` 同构）。
class KitUsage {
  const KitUsage({
    required this.tool,
    required this.ts,
    this.kind = kKitKindBuiltin,
    this.id = 0,
  });

  final int id;
  final String tool;
  final int ts;
  final String kind;

  factory KitUsage.fromRow(Map<String, Object?> r) => KitUsage(
    id: (r['id'] as int?) ?? 0,
    tool: r['tool'] as String,
    ts: r['ts'] as int,
    kind: (r['kind'] as String?) ?? kKitKindBuiltin,
  );

  Map<String, Object?> toRow() => {'tool': tool, 'ts': ts, 'kind': kind};
}

/// 插件审计条目（`kit_plugin.audit` 以 JSON 数组存列）。
class KitAudit {
  const KitAudit({required this.ts, required this.text});

  final int ts;
  final String text;

  Map<String, Object?> toJson() => {'ts': ts, 'text': text};

  static KitAudit fromJson(Map<String, Object?> j) =>
      KitAudit(ts: (j['ts'] as int?) ?? 0, text: (j['text'] as String?) ?? '');
}

/// `kit_plugin` 行模型（批5 起真正写入；批0 先把契约立住）。
class KitPlugin {
  const KitPlugin({
    required this.id,
    required this.name,
    required this.ver,
    required this.installedAt,
    required this.updatedAt,
    this.src = 'local',
    this.size = 0,
    this.perms = const [],
    this.granted = const [],
    this.enabled = false,
    this.audit = const [],
  });

  final String id;
  final String name;
  final String ver;

  /// local=私有 plugins/ 目录扫描 · github=在线索引下载（批6）。
  final String src;

  /// 包体积（KB，界面按 `kitKB()` 口径可读化）。
  final int size;
  final List<String> perms;
  final List<String> granted;
  final bool enabled;
  final int installedAt;
  final int updatedAt;
  final List<KitAudit> audit;

  factory KitPlugin.fromRow(Map<String, Object?> r) => KitPlugin(
    id: r['id'] as String,
    name: r['name'] as String,
    ver: r['ver'] as String,
    src: (r['src'] as String?) ?? 'local',
    size: (r['size'] as int?) ?? 0,
    perms: _strings(r['perms']),
    granted: _strings(r['granted']),
    enabled: ((r['enabled'] as int?) ?? 0) == 1,
    installedAt: (r['installed_at'] as int?) ?? 0,
    updatedAt: (r['updated_at'] as int?) ?? 0,
    audit: _audits(r['audit']),
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'name': name,
    'ver': ver,
    'src': src,
    'size': size,
    'perms': jsonEncode(perms),
    'granted': jsonEncode(granted),
    'enabled': enabled ? 1 : 0,
    'installed_at': installedAt,
    'updated_at': updatedAt,
    'audit': jsonEncode([for (final a in audit) a.toJson()]),
  };
}

List<String> _strings(Object? raw) {
  if (raw is! String || raw.isEmpty) return const [];
  try {
    final d = jsonDecode(raw);
    return d is List ? [for (final e in d) '$e'] : const [];
  } catch (_) {
    return const [];
  }
}

List<KitAudit> _audits(Object? raw) {
  if (raw is! String || raw.isEmpty) return const [];
  try {
    final d = jsonDecode(raw);
    if (d is! List) return const [];
    return [
      for (final e in d)
        if (e is Map<String, Object?>) KitAudit.fromJson(e),
    ];
  } catch (_) {
    return const [];
  }
}
