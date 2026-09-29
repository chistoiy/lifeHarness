/// 小工具合集 · 随机数域层（批2 · 原型 `randGo` / `randCard` / `KITS.rHist` 同源）。
///
/// 随机源由参数注入（默认 [math.Random]，用例传固定种子随机流即可稳定复现，
/// 也满足「widget 测试禁真实异步 I/O」——本文件无任何 I/O）。
library;

import 'dart:math' as math;

/// 历史保留组数（原型 `slice(0,6)`）。
const int kKitRandHistMax = 6;

/// 单次最多生成个数（原型 `Math.min(50, …)`）。
const int kKitRandMaxCount = 50;

/// 一组生成结果（原型 `{r:[a,b], n, u, v, ts}`）。
/// 一组生成留痕（原型 `{r:[a,b], n, u, v, ts}`；值一律字符串，
/// 抽牌记录（如 `♠A`）与数字记录同表存放）。
class KitRandRecord {
  const KitRandRecord({
    required this.min,
    required this.max,
    required this.values,
    required this.unique,
    required this.ts,
  });

  final int min;
  final int max;
  final List<String> values;
  final bool unique;
  final int ts;

  factory KitRandRecord.fromJson(Map<String, Object?> j) {
    final r = j['r'] is List ? j['r'] as List : const [];
    return KitRandRecord(
      min: _num(r, 0),
      max: _num(r, 1),
      values: [
        for (final e in (j['v'] is List ? j['v'] as List : const [])) '$e',
      ],
      unique: (j['u'] as bool?) ?? false,
      ts: j['ts'] is num ? (j['ts'] as num).toInt() : 0,
    );
  }

  /// 区间端点宽容取值（损坏/越界的 JSON 一律按 0，不让历史行炸界面）。
  static int _num(List r, int i) =>
      r.length > i && r[i] is num ? (r[i] as num).toInt() : 0;

  Map<String, Object?> toJson() => {
        'r': [min, max],
        'n': values.length,
        'u': unique,
        'v': values,
        'ts': ts,
      };

  /// 历史行左侧参数串（原型 `[a, b] ×n 不重复`）。
  String get paramsText =>
      '[$min, $max] ×${values.length}${unique ? ' 不重复' : ''}';

  /// 历史行右侧结果串。
  String get valuesText => values.join(' · ');
}

/// 生成结果：[error] 非空表示参数不合法（界面侧只提示、不写历史）。
class KitRandOutcome {
  const KitRandOutcome(this.values, {this.error = ''});

  final List<String> values;
  final String error;

  bool get ok => error.isEmpty;

  /// 复制/分享串（原型 `randOutText`：`a · b · c`）。
  String get text => values.join(' · ');
}

/// 分享文案（原型 `KIT_SHARE_TXT`：`随机数 a~b ×n（不重复）：…`）。
String kitRandShareText(int min, int max, KitRandOutcome out, bool unique) =>
    '随机数 $min~$max ×${out.values.length}${unique ? '（不重复）' : ''}：${out.text}';

/// 区间生成（原型 `randGo`：a>b 报错；不重复模式个数需 ≤ 区间大小）。
KitRandOutcome kitRandGenerate({
  required int min,
  required int max,
  required int count,
  required bool unique,
  required math.Random rnd,
}) {
  if (min > max) return const KitRandOutcome([], error: '区间不合法：起点需 ≤ 终点');
  final n = count.clamp(1, kKitRandMaxCount);
  if (unique && n > (max - min + 1)) {
    return KitRandOutcome(
      const [],
      error: '不重复模式下个数需 ≤ 区间大小（${max - min + 1}）',
    );
  }
  if (unique) {
    final pool = [for (var i = min; i <= max; i++) i];
    return KitRandOutcome([
      for (var i = 0; i < n; i++) '${pool.removeAt(rnd.nextInt(pool.length))}',
    ]);
  }
  return KitRandOutcome([
    for (var i = 0; i < n; i++) '${min + rnd.nextInt(max - min + 1)}',
  ]);
}

/// 抽牌花色与点数（原型 `randCard`：♠♥♣♦ × A..K，52 张牌堆等概率）。
const List<String> kKitCardSuits = ['♠', '♥', '♣', '♦'];
const List<String> kKitCardRanks = [
  'A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K',
];

/// 返回抽到的牌面串与要写入历史的记录（区间按原型记作 1~52）。
({String card, KitRandRecord record}) kitRandCard({
  required math.Random rnd,
  required int ts,
}) {
  final card =
      '${kKitCardSuits[rnd.nextInt(4)]}${kKitCardRanks[rnd.nextInt(13)]}';
  return (
    card: card,
    record: KitRandRecord(
      min: 1,
      max: 52,
      values: [card],
      unique: false,
      ts: ts,
    ),
  );
}

/// 历史压入（表头 + 截断 6 组）。
List<KitRandRecord> kitRandPush(
  List<KitRandRecord> history,
  KitRandRecord record,
) =>
    [record, ...history].take(kKitRandHistMax).toList();

/// `kit_tool_data.tool='rand'` 的 JSON 形态（`{u, rHist:[…]}`）。
Map<String, Object?> kitRandEncode({
  required bool unique,
  required List<KitRandRecord> history,
}) =>
    {
      'u': unique,
      'rHist': [for (final x in history) x.toJson()],
    };

({bool unique, List<KitRandRecord> history}) kitRandDecode(Map<String, Object?> data) {
  final raw = data['rHist'];
  return (
    unique: data['u'] is bool ? data['u'] as bool : false,
    history: [
      if (raw is List)
        for (final e in raw)
          if (e is Map<String, Object?>) KitRandRecord.fromJson(e),
    ],
  );
}
