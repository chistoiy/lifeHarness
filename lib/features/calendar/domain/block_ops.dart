import 'time_block.dart';

/// V1.52 时间块纯操作层（无 DB / 无 Widget 依赖，便于用例直测）。
/// 规则来源：`prototype/index.html` 时间模块 V1.52（time52patch*.js 落地并 31/31 绿）。

/// 合并允许的最大间隙（分钟）：超过则视为不相邻，不提供合并。
const int kMergeGapLimit = 30;

/// 轴视图可点的空隙最小长度（分钟）。
const int kGapMinMin = 15;

/// 分钟 → 'HH:MM'（>1440 自动回绕到次日钟面）。
String fmtMin(int m) =>
    '${(m ~/ 60 % 24).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

/// 时长分钟 → 人类可读（45 分 / 1 时 30 分 / 1 天 1 时）。
/// 年档累计可达数千分钟，必须带「天」档，否则出现「7686 时」这类不可读数。
String fmtDur(int m) {
  if (m <= 0) return '0 分';
  final d = m ~/ 1440, h = (m % 1440) ~/ 60, r = m % 60;
  final parts = <String>[
    if (d > 0) '$d 天',
    if (h > 0) '$h 时',
    if (r > 0 || (d == 0 && h == 0)) '$r 分',
  ];
  return parts.join(' ');
}

/// 添加新段 [bStart,bEnd] 时，计时中块 a 应收口到的分钟；null=不收口。
///
/// 规则（用户 2026-09-28 拍板）：
/// · b 起始 ≥ a 起始 → a 收口 = max(a 起始, min(b 起始, 当前))；
/// · b 起始 < a 起始 → 纯补录，a 继续计时不收口。
int? closeMinuteForAdd({
  required TimeBlock timing,
  required int bStart,
  required int nowMin,
}) {
  if (bStart < timing.startMin) return null;
  final cut = bStart < nowMin ? bStart : nowMin; // min(b 起始, 当前)
  return cut > timing.startMin ? cut : timing.startMin; // max(a 起始, …)
}

/// 补录越界判定：b 起始早于计时块 a 起始（算补录），但 b 结束晚于 a 起始
/// → 会吞掉正在计时的区间，拒绝。
bool addRejected({
  required TimeBlock timing,
  required int bStart,
  required int bEnd,
}) =>
    bStart < timing.startMin && bEnd > timing.startMin;

/// 对半拆分：中点切两段；不足 2 分钟返回 null。
/// 第二段必须是**新行**（id=null），copyWith 的 `id ?? this.id` 语义无法清空 id，故显式构造。
List<TimeBlock>? splitHalf(TimeBlock b, [DateTime? now]) {
  final e = b.effEnd(now);
  final mid = (b.startMin + e) ~/ 2;
  if (mid <= b.startMin || mid >= e) return null;
  return [
    b.copyWith(endMin: mid),
    TimeBlock(
        day: b.day,
        startMin: mid,
        endMin: e,
        catId: b.catId,
        catName: b.catName,
        note: b.note,
        source: b.isTiming ? kSrcMark : b.source,
        eventId: b.eventId),
  ];
}

/// 同日前/后最近的可合并块（排除计时中；间隙 > [kMergeGapLimit] 视为不相邻）。
TimeBlock? neighborOf(List<TimeBlock> day, TimeBlock b, int dir,
    {int gapLimit = kMergeGapLimit, DateTime? now}) {
  final bs = b.startMin, be = b.effEnd(now);
  final list = day.where((x) => x.id != b.id && !x.isTiming).toList();
  if (dir < 0) {
    final c = list.where((x) => x.effEnd(now) <= bs && bs - x.effEnd(now) <= gapLimit).toList()
      ..sort((p, q) => q.startMin.compareTo(p.startMin));
    return c.isEmpty ? null : c.first;
  }
  final c = list
      .where((x) => x.startMin >= be && x.startMin - be <= gapLimit)
      .toList()
    ..sort((p, q) => p.startMin.compareTo(q.startMin));
  return c.isEmpty ? null : c.first;
}

/// 两段并成一段：区间取并集，分类/备注取更早那段。
TimeBlock mergePair(TimeBlock a, TimeBlock b, [DateTime? now]) {
  final first = a.startMin <= b.startMin ? a : b;
  final other = identical(first, a) ? b : a;
  return first.copyWith(
    startMin: [first.startMin, other.startMin].reduce((x, y) => x < y ? x : y),
    endMin: [first.effEnd(now), other.effEnd(now)].reduce((x, y) => x > y ? x : y),
    source: kSrcMark,
  );
}

/// 排序后区间之间的空隙（用于轴视图「空闲·点此补录」条）。
List<List<int>> freeGaps(List<TimeBlock> blocks,
    {int from = 0, int to = 1440, int minMin = kGapMinMin, DateTime? now}) {
  final iv = blocks
      .map((b) => [b.startMin, b.effEnd(now)])
      .where((r) => r[1] > r[0])
      .toList()
    ..sort((a, b) => a[0].compareTo(b[0]));
  final out = <List<int>>[];
  var cursor = from;
  for (final r in iv) {
    if (r[0] - cursor >= minMin) out.add([cursor, r[0]]);
    cursor = r[1] > cursor ? r[1] : cursor;
  }
  if (to - cursor >= minMin) out.add([cursor, to]);
  return out;
}

/// 分类时长聚合（计时中按 [now] 已耗时计入）。
Map<String, int> minutesByCat(Iterable<TimeBlock> blocks, [DateTime? now]) {
  final m = <String, int>{};
  for (final b in blocks) {
    final d = b.durationMin(now);
    if (d > 0) m[b.catName] = (m[b.catName] ?? 0) + d;
  }
  return m;
}

/// 总时长（分钟）。
int totalMinutes(Iterable<TimeBlock> blocks, [DateTime? now]) =>
    blocks.fold(0, (t, b) => t + b.durationMin(now));

/// 环比：本期 vs 上期（上期为 0 时返回 null，表示无可比）。
double? deltaPct(num cur, num prev) => prev <= 0 ? null : (cur - prev) / prev * 100;
