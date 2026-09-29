/// 小工具合集 · 轮盘抽签域层（批2 · 原型 `wheel*` 系列函数同源）。
///
/// 落库形态：`kit_tool_data.tool='wheel'`，data=`{cur, sets:[{id,name,items:[{t,w}],hist:[{o,ts}]}]}`
/// （与原型 `KITS.wsets` / `KITS.wCur` 同构）。本文件只做纯数据与纯计算，
/// 读写与动画归 presentation 侧。
library;

import 'dart:math' as math;

/// 轮盘选项（名称截断 12 字，权重钳制 1~9，与原型 `wheelAdd`/`wheelWeight` 一致）。
class KitWheelItem {
  const KitWheelItem(this.text, this.weight);

  final String text;
  final int weight;

  factory KitWheelItem.fromJson(Map<String, Object?> j) => KitWheelItem(
        kitWheelClampText('${j['t'] ?? ''}'),
        kitWheelClampWeight((j['w'] as num?)?.toInt() ?? 1),
      );

  Map<String, Object?> toJson() => {'t': text, 'w': weight};
}

/// 一套数据（原型 `KITS.wsets` 一项）。
class KitWheelSet {
  const KitWheelSet({
    required this.id,
    required this.name,
    required this.items,
    this.history = const [],
  });

  final String id;
  final String name;
  final List<KitWheelItem> items;

  /// 本套历史结果（表头=最近一次，上限 12）。
  final List<KitWheelResult> history;

  factory KitWheelSet.fromJson(Map<String, Object?> j) => KitWheelSet(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? '未命名'}',
        items: [
          for (final e in (j['items'] is List ? j['items'] as List : const []))
            if (e is Map<String, Object?>) KitWheelItem.fromJson(e),
        ],
        history: [
          for (final e in (j['hist'] is List ? j['hist'] as List : const []))
            if (e is Map<String, Object?>) KitWheelResult.fromJson(e),
        ],
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'items': [for (final x in items) x.toJson()],
        'hist': [for (final x in history) x.toJson()],
      };

  int get totalWeight =>
      items.fold(0, (a, x) => a + kitWheelClampWeight(x.weight));

  /// 单项占比（整数百分比，原型 `Math.round(w/total*100)`）。
  int percentOf(int index) {
    if (totalWeight <= 0 || index < 0 || index >= items.length) return 0;
    return (kitWheelClampWeight(items[index].weight) / totalWeight * 100).round();
  }
}

/// 一次抽签结果（原型 `{o, ts}`）。
class KitWheelResult {
  const KitWheelResult(this.option, this.ts);

  final String option;
  final int ts;

  factory KitWheelResult.fromJson(Map<String, Object?> j) =>
      KitWheelResult('${j['o'] ?? ''}', (j['ts'] as num?)?.toInt() ?? 0);

  Map<String, Object?> toJson() => {'o': option, 'ts': ts};
}

/// 默认 6 项（原型 `wheelReset` / 首次初始化）。
const List<KitWheelItem> kKitWheelDefaultItems = [
  KitWheelItem('写日记', 1),
  KitWheelItem('跑步 5km', 1),
  KitWheelItem('阅读 30 分钟', 1),
  KitWheelItem('吃顿好的', 1),
  KitWheelItem('看部电影', 1),
  KitWheelItem('发呆时间', 1),
];

/// 扇区配色 12 色（原型 `wheelColors`，按项数截取，最少 2 最多 12）。
const List<String> kKitWheelPalette = [
  '#6366f1', '#2dd4bf', '#f59e0b', '#fb7185', '#8b5cf6', '#0ea5e9',
  '#84cc16', '#f472b6', '#fbbf24', '#34d399', '#a78bfa', '#38bdf8',
];

List<String> kitWheelColors(int n) =>
    kKitWheelPalette.sublist(0, math.min(12, math.max(2, n)));

/// 约束常量（原型口径：2~12 项、最多 8 套、历史 12 条、权重 1~9）。
const int kKitWheelMinItems = 2;
const int kKitWheelMaxItems = 12;
const int kKitWheelMaxSets = 8;
const int kKitWheelMaxHistory = 12;
const int kKitWheelTextMax = 12;

String kitWheelClampText(String t) =>
    t.length <= kKitWheelTextMax ? t : t.substring(0, kKitWheelTextMax);

int kitWheelClampWeight(int w) => w.clamp(1, 9);

/// 批量粘贴解析（原型 `wheelParsePaste`：换行/逗号/顿号/分号分隔，
/// 「选项:权重」支持中英文冒号，权重缺省 1）。
List<KitWheelItem> kitWheelParsePaste(String text) {
  return [
    for (final raw in text.split(RegExp(r'[\n,，、;；]+')))
      if (raw.trim().isNotEmpty)
        () {
          final s = raw.trim();
          final m = RegExp(r'^(.*?)[：:]([0-9]+)$').firstMatch(s);
          if (m != null) {
            return KitWheelItem(
              kitWheelClampText(m.group(1)!.trim()),
              kitWheelClampWeight(int.parse(m.group(2)!)),
            );
          }
          return KitWheelItem(kitWheelClampText(s), 1);
        }(),
  ];
}

/// 追加粘贴（返回 [剩余项, 实际追加数]；满 12 项时追加 0，界面侧提示）。
({List<KitWheelItem> added, int skipped}) kitWheelAppend(
  List<KitWheelItem> current,
  List<KitWheelItem> parsed,
) {
  final room = kKitWheelMaxItems - current.length;
  if (room <= 0) return (added: const [], skipped: parsed.length);
  final take = parsed.take(room).toList();
  return (added: take, skipped: parsed.length - take.length);
}

/// 扇区角度表（累计权重占比 → 起始/结束角，0° 指向正上方顺时针）。
List<({double start, double end})> kitWheelSectors(KitWheelSet set) {
  final tot = set.totalWeight;
  if (tot <= 0) return const [];
  var acc = 0.0;
  return [
    for (final x in set.items)
      () {
        final start = acc / tot * 360;
        acc += kitWheelClampWeight(x.weight);
        return (start: start, end: acc / tot * 360);
      }(),
  ];
}

/// 抽签落点（原型 `wheelGo`：按权重随机抽 idx，再算把该扇区中线转到
/// 顶部指针所需的旋转角，最少多转三圈 1080°）。
({int index, double rotateTo}) kitWheelSpin(
  KitWheelSet set, {
  required double currentRotation,
  required double rand01,
}) {
  final tot = set.totalWeight;
  var r = rand01 * tot;
  var idx = 0;
  for (var i = 0; i < set.items.length; i++) {
    r -= kitWheelClampWeight(set.items[i].weight);
    if (r <= 0) {
      idx = i;
      break;
    }
  }
  final sectors = kitWheelSectors(set);
  if (sectors.isEmpty || idx >= sectors.length) {
    return (index: idx, rotateTo: currentRotation + 1080);
  }
  final seg = sectors[idx].end - sectors[idx].start;
  final need = (360 - (sectors[idx].start + seg / 2)) % 360;
  final cur = ((currentRotation % 360) + 360) % 360;
  final fw = ((need - cur) % 360 + 360) % 360;
  return (index: idx, rotateTo: currentRotation + 1080 + fw);
}

/// 结果写历史（表头插入 + 截断 12）。
List<KitWheelResult> kitWheelPushHistory(
  List<KitWheelResult> history,
  KitWheelResult result,
) =>
    [result, ...history].take(kKitWheelMaxHistory).toList();

/// 套数据整体序列化（`kit_tool_data.data` 的 JSON 形态）。
Map<String, Object?> kitWheelEncode(
  List<KitWheelSet> sets,
  String curId,
) =>
    {
      'cur': curId,
      'sets': [for (final s in sets) s.toJson()],
    };

/// 反序列化 + 自愈（原型 `wheelSets`：无数据建默认套、空集兜底、
/// cur 指向不存在的套回落首套）。
({List<KitWheelSet> sets, String curId}) kitWheelDecode(
  Map<String, Object?> data,
) {
  List<KitWheelSet> parse() {
    final raw = data['sets'];
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is Map<String, Object?>) KitWheelSet.fromJson(e),
    ];
  }

  var sets = parse();
  if (sets.isEmpty) {
    sets = [
      const KitWheelSet(id: 'w1', name: '日常', items: kKitWheelDefaultItems),
    ];
  }
  var curId = '${data['cur'] ?? ''}';
  if (!sets.any((s) => s.id == curId)) curId = sets.first.id;
  return (sets: sets, curId: curId);
}
