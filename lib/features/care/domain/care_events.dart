/// 事件体系注册表 + 记录展示文本生成（交接 §4；红线 6/8）。
///
/// 内置 13 类不可删、可排序；自定义事件键 `cus:名` 经「管理」任意增删改。
/// 展示文本由数据生成，不存展示串（logTitle/icOf 与原型同名函数逐案同构）。
library;

import 'care_models.dart';

/// 事件定义（原型 EVENTS 值对象；tint 存 500 级色值，UI 侧按明暗取低透明度底）。
class EvDef {
  const EvDef({
    required this.key,
    required this.name,
    required this.icon,
    this.unit,
    this.dur = false,
    this.amt = false,
    this.timer = false,
    this.sp, // dia|supp|solid|cus
    this.def,
    this.quick = const [],
    required this.tint,
  });

  final String key;
  final String name;
  final String icon;
  final String? unit;
  final bool dur;
  final bool amt;
  final bool timer;
  final String? sp;
  final int? def;
  final List<int> quick;
  final String tint;

  bool get builtin => !key.startsWith('cus:');
}

/// 内置 13 类（原型 EVENTS 同序同参）。
const Map<String, EvDef> kBuiltinEvents = {
  'nurse': EvDef(key: 'nurse', name: '母乳亲喂', icon: '🤱', unit: 'min', dur: true, timer: true, def: 15, quick: [5, 10, 15, 20, 30], tint: '#f43f5e'),
  'bmilk': EvDef(key: 'bmilk', name: '瓶喂母乳', icon: '🍼', unit: 'ml', amt: true, def: 120, quick: [60, 90, 120, 150, 180], tint: '#ec4899'),
  'formula': EvDef(key: 'formula', name: '配方奶', icon: '🥣', unit: 'ml', amt: true, def: 150, quick: [90, 120, 150, 180, 210], tint: '#f59e0b'),
  'diaper': EvDef(key: 'diaper', name: '换尿布', icon: '🚼', sp: 'dia', tint: '#f97316'),
  'sleep': EvDef(key: 'sleep', name: '睡眠', icon: '😴', unit: 'min', dur: true, timer: true, def: 60, quick: [30, 60, 90, 120], tint: '#6366f1'),
  'bath': EvDef(key: 'bath', name: '洗澡', icon: '🛁', unit: 'min', dur: true, timer: true, def: 15, quick: [10, 15, 20, 30], tint: '#0ea5e9'),
  'play': EvDef(key: 'play', name: '玩耍', icon: '🧸', unit: 'min', dur: true, timer: true, def: 15, quick: [5, 10, 15, 20, 30], tint: '#10b981'),
  'supp': EvDef(key: 'supp', name: '补剂', icon: '💊', sp: 'supp', tint: '#8b5cf6'),
  'swim': EvDef(key: 'swim', name: '游泳', icon: '🏊', unit: 'min', dur: true, timer: true, def: 20, quick: [10, 20, 30], tint: '#06b6d4'),
  'water': EvDef(key: 'water', name: '喝水', icon: '💧', unit: 'ml', amt: true, def: 30, quick: [10, 20, 30, 50, 80], tint: '#14b8a6'),
  'solids': EvDef(key: 'solids', name: '辅食', icon: '🍲', unit: 'g', sp: 'solid', amt: true, def: 40, quick: [20, 40, 60, 80, 100, 150], tint: '#84cc16'),
  'pump': EvDef(key: 'pump', name: '吸奶', icon: '🫙', unit: 'ml', amt: true, dur: true, timer: true, def: 120, quick: [30, 60, 90, 120, 150, 180], tint: '#d946ef'),
  'custom': EvDef(key: 'custom', name: '自定义', icon: '✨', sp: 'cus', tint: '#94a3b8'),
};

/// 速记区初始序（原型 EV_BASE）。
const List<String> kEventBaseKeys = [
  'nurse', 'bmilk', 'formula', 'diaper', 'sleep', 'bath',
  'play', 'supp', 'swim', 'water', 'solids', 'pump', 'custom',
];

/// 自定义事件图标池（原型 EV_ICONS；含两个占位空格位已由相邻真实图标替代）。
const List<String> kEvIconPool = [
  '✨', '🫧', '📷', '🍼', '🧴', '💆', '⚽', '📚', '🛒', '🎵', '🌞', '🧦',
];

/// 量滚轮取值范围 [起, 止, 步]（原型 AMT_RANGE）。
const Map<String, List<int>> kAmtRange = {
  'min': [5, 180, 5],
  'ml': [5, 300, 5],
  'g': [1, 500, 1],
  '°C': [36, 42, 1],
  '次': [1, 20, 1],
};

/// 周期感受池（原型 SYMPS）。
const List<String> kSymPool = [
  '😊 心情好', '😌 平静', '⚡ 精力旺', '🌀 痛经', '🍫 食欲旺',
  '😢 情绪低落', '🌡 涨奶', '💆 头痛',
];

/// 便便颜色 7 点（原型 POO_COLORS；砖红/灰白触发就医参考提示）。
const List<(String, String)> kPooColors = [
  ('黄绿', '#84cc16'), ('金黄', '#f59e0b'), ('棕色', '#92400e'), ('墨绿', '#166534'),
  ('茶色', '#7c2d12'), ('砖红', '#b91c1c'), ('灰白', '#cbd5e1'),
];

/// 粘稠度 4 档（婴儿口径，2026-09-24 定案；无称重字段）。
const List<String> kPooTex = ['糊状', '水样', '成形', '蛋花样'];

/// 辅食过敏候选食物池（原型 ALA_FOODS）。
const List<String> kAllergyFoods = [
  '牛奶', '酸奶', '奶酪', '蛋黄', '蛋白', '鸡蛋', '虾', '蟹', '贝柱', '花甲',
  '鳕鱼', '三文鱼', '鲈鱼', '银鱼', '龙利鱼', '豆腐', '腐竹', '芝麻', '核桃',
  '花生', '腰果', '猕猴桃', '芒果', '菠萝', '小麦粉(麸质)', '大豆', '蜂蜜',
];

/// 过敏常见症状（原型 ALA_SYMS）。
const List<String> kAllergySyms = ['皮疹', '呕吐', '腹泻', '湿疹加重', '口周发红', '哭闹不安'];

/// 常见补剂 chips（原型 elSuppNames）。
const List<String> kSuppPresets = ['维生素AD', '维生素D3', '益生菌', '钙', '锌', '铁', 'DHA'];

/// 解析事件定义：内置 → 自定义 → 兜底（原型 evDef）。
EvDef resolveEv(String key, Map<String, CareCustomEvent> customs) {
  final b = kBuiltinEvents[key];
  if (b != null) return b;
  final c = customs[key];
  if (c != null) {
    return EvDef(
      key: key,
      name: c.name,
      icon: c.icon,
      unit: c.unit,
      dur: true,
      amt: true,
      sp: 'cus',
      tint: '#94a3b8',
    );
  }
  return const EvDef(key: 'custom', name: '记录', icon: '✨', unit: 'min', dur: true, tint: '#94a3b8');
}

/// 记录图标（原型 icOf：尿布按类型取滴/便图标）。
String careIconOf(CareRecord r) {
  if (r.k == 'diaper') return r.dia == 'pee' ? '💧' : '💩';
  return (kBuiltinEvents[r.k]?.icon ?? kBuiltinEvents['custom']!.icon);
}

/// 记录展示标题（原型 logTitle 逐案同构）。
String careLogTitle(CareRecord r, Map<String, CareCustomEvent> customs) {
  final E = resolveEv(r.k, customs);
  switch (r.k) {
    case 'nurse':
      return '母乳亲喂 · ${careHms(r.durOr0)}${r.seg != null && r.seg!.isNotEmpty ? '（${r.seg}）' : ''}';
    case 'bmilk':
      return '瓶喂母乳 ${_num(r.ml)}ml';
    case 'formula':
      return '配方奶 ${_num(r.ml)}ml${r.tmp != null ? ' · ${_num(r.tmp)}°C' : ''}';
    case 'water':
      return '喝水 ${_num(r.ml)}ml';
    case 'sleep':
      return '睡眠 ${r.s}~${r.e ?? ''} · ${careHms(r.durOr0)}';
    case 'diaper':
      return '尿布 · ${r.dia == 'pee' ? '尿尿' : r.dia == 'mix' ? '臭臭+尿尿' : '臭臭'}'
          '${r.dia != 'pee' ? ' · ${r.color}·${r.tex}·${r.vol}量' : ''}';
    case 'supp':
      return '补剂 · ${r.name ?? ''}${r.amt != null && r.amt!.isNotEmpty ? ' · ${r.amt}' : ''}';
    case 'solids':
      return '辅食 · ${r.name?.isNotEmpty == true ? r.name : '未命名'}'
          '${r.amt != null && r.amt!.isNotEmpty ? ' ${r.amt}g' : ''}'
          '${r.ala?.isNotEmpty == true ? ' · 过敏提示' : ''}';
    case 'pump':
      return r.ml != null && r.ml! > 0
          ? '吸奶 ${_num(r.ml)}ml${r.dur != null ? ' · ${careHms(r.dur!)}' : ''}'
          : '计时 ${r.dur != null ? careHms(r.dur!) : '—'}${r.dur != null ? ' · 奶量待补' : ''}';
    case 'bath':
      return '洗澡 ${careHms(r.durOr0)}';
    case 'swim':
      return '游泳 ${careHms(r.durOr0)}';
    case 'play':
      return '玩耍 · ${r.name ?? ''} ${careHms(r.durOr0)}';
    default:
      final amount = [
        if (r.amt != null && r.amt!.isNotEmpty) '${r.amt}${r.unit ?? ''}',
        if ((r.amt == null || r.amt!.isEmpty) && r.dur != null && r.dur! > 0) '${r.dur}${r.unit ?? 'min'}',
      ].join();
      return '${r.name?.isNotEmpty == true ? r.name : E.name} · $amount';
  }
}

String _num(num? v) {
  if (v == null) return '0';
  return v == v.roundToDouble() ? v.toInt().toString() : '$v';
}
