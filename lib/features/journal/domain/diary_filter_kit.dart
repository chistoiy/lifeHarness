/// 日记改版批2c · 筛选弹层的胶囊几何、标签段折叠判定与筛选命中（纯逻辑）。
///
/// 为什么「要不要折叠」放在 domain 而不是 widget 里：原型在同一个坑上踩过三次——
/// 折叠态是「定高一行 + 裁掉溢出」，被裁掉的胶囊在布局阶段就被排除，
/// 于是「先裁再量」永远量到 `scrollHeight == clientHeight`，恒判「不超一行」；
/// 反过来先解折叠再量，容器当场变成两行，判据又回到原点。
/// 定案是**容器宽度判据**：逐枚累加「胶囊宽 + 间距」，装不下即折行。
/// 这个判据不依赖渲染时序，所以能整段脱开 widget 树做单测
/// （别改成「按标签数 > 4 猜」——那是原型明确否掉的硬编码）。
library;

import 'journal_entry.dart';

/// 胶囊几何（与原型 `.df-chip` 同口径：高 32 / 左右内边距 12 / 描边 1 / 圆角 16 / 字号 13）。
///
/// 改这里必须同步原型 `index-journal.html` 的 `.df-chip`，否则「按宽度算折行」
/// 会与实际渲染错开，出现「明明两行却没折叠」或「只有一行却多出一枚按钮」。
const double kDfChipH = 32;
const double kDfChipPadX = 12;
const double kDfChipBorder = 1;
const double kDfChipIcon = 14;
const double kDfChipIconGap = 6;
const double kDfChipFontSize = 13;

/// 胶囊横竖间距（原型 `.df-tags{gap:8px}` 与 `flex-wrap gap-2` 同一值）。
const double kDfChipGap = 8;

/// 时间段胶囊几何（原型 `.df-pill`：高 34 / 左右内边距 14 / 圆角 999 / 字号 13）。
///
/// 与标签胶囊 [kDfChipH]（32）**不是一个高度**——原型就这样：时间胶囊纯文字无图标，
/// 靠 34 的更高内边距撑出与带图标胶囊相同的视觉重量。别为了「统一」把它改成 32，
/// 那样同一行里只剩文字会显矮。
const double kDfPillH = 34;
const double kDfPillPadX = 14;

/// 固定键顺序（与原型 `DF_GROUPS[0].items` 同序：全部 / 收藏 / 点亮 / 待办）。
///
/// 顺序留在 kit 里而不是 UI 里：`journal_flags_test` 与筛选弹层都读它，
/// 两处各写一份就会出现「弹层顺序改了、纯逻辑断言还按老顺序」的假绿。
const List<String> kDfMarkKeys = ['all', 'starred', 'liked', 'todo'];

/// 固定键的中文名（原型 `dfLabel` 同名口径）。
///
/// **不带符号**：原型曾把 `♥ 收藏` 整串当显示名，行首已有一枚线性图标、
/// 文字前又出现同一个符号，产品实测点名「同一个符号出现两遍」。
/// 符号只留在筛选值（`'♥ 收藏'` 那种历史键）里。
String dfMarkLabel(String key) => switch (key) {
      'todo' => '待办',
      'starred' => '收藏',
      'liked' => '点亮',
      _ => '全部',
    };

/// 一枚胶囊的占位宽＝左右内边距 + 描边 + 图标 + 图标与文字间距 + 文字宽。
///
/// 只服务「会不会折行」的估算，故不把 `Wrap` 的亚像素取整算进来——
/// 差 1px 以内不影响「一行还是两行」的判定，但会影响可读性（贴边那枚差一点点就折）。
double dfChipWidth(double textWidth) =>
    kDfChipPadX * 2 + kDfChipBorder * 2 + kDfChipIcon + kDfChipIconGap + textWidth;

/// 这些宽度的胶囊在 [maxW] 里排得下几行（贪心累加，与 `Wrap` 的折行一致）。
///
/// 空列表返回 0（无内容＝零行，调用方据此连分组标题都不出）。
int dfChipLines(List<double> widths, double maxW, {double gap = kDfChipGap}) {
  if (widths.isEmpty) return 0;
  if (maxW <= 0) return 1; // 未测量到宽度：按「一行」处理，绝不无中生有地折叠
  var run = 0.0;
  var lines = 1;
  for (final w in widths) {
    if (run > 0 && run + gap + w > maxW) {
      lines++;
      run = w;
    } else {
      run = run > 0 ? run + gap + w : w;
    }
  }
  return lines;
}

/// 标签段是否该折叠（严格超一行才折叠，才出「展开全部」）。
///
/// 产品口径「不超一行时不出按钮、不裁剪」就落在这一个 return 上：
/// 一行以内返回 false，调用方连 `ClipRect` 都不挂——按钮不存在，也不占位。
bool dfTagsOverflow(List<double> widths, double maxW, {double gap = kDfChipGap}) =>
    dfChipLines(widths, maxW, gap: gap) > 1;

/// 展开按钮文案：折叠态「展开全部 (N)」，展开态「收起」。
///
/// N 是**池内全量标签数**（不是「被裁掉几枚」）：用户点它是想看全量，
/// 报「还有 3 枚」会让池子大小看起来比实际小。
String dfMoreLabel({required bool open, required int total}) =>
    open ? '收起' : '展开全部 ($total)';

/// 一篇日记是否命中筛选键。
///
/// 固定键走白名单，其余按标签名比（兼容历史 `#标签` 键——原型 `dwHit` 曾因
/// 「按名字精确等于 `'#复盘'` 比、池内名字不带 `#`」导致该标签恒 0 篇）。
///
/// 放在 domain 是给两处共用：页面列表的 `shown` 与筛选弹层的实时计数。
/// 分两份写过一次就出过「弹层说筛出 3 篇、关掉弹层只剩 1 篇」。
///
/// **注意**：本函数只判「标记／标签」。时间段是**另一条正交条件**，
/// 由 [diaryInRange] 单独判、调用方先过它（对齐原型 `dwHit` 的第一行 `dwInRange`）。
/// 两者别合并进一个 `switch`——时间段有 `custom` 这种要带两个额外参数的形态。
bool diaryHit(JournalEntry e, String key) => switch (key) {
      'all' => true,
      'todo' => e.todoLines().isNotEmpty,
      'starred' => e.starred,
      'liked' => e.liked,
      _ => e.tags.any((t) => t == key || '#$t' == key),
    };

// ---------------------------------------------------------------------------
// 时间段（批2d · 对齐原型 `DIARY_RANGES` / `dwInRange` / `dfRangeName`）
// ---------------------------------------------------------------------------

/// 时间段一档：`k` 是落盘键，`n` 是胶囊文案。
typedef DiaryRangeDef = ({String k, String n});

/// 8 档预设，**顺序即原型数组字面序**（`all` 排最前＝默认最常用，其余按跨度递增：
/// 天数窗 → 自然年/月 → 更长天数窗）。
///
/// 原型里还留着 `g:0/1/2` 的分组字段，那是「按近期／按日历分两行」时代的残留；
/// 产品令「单段横排」后分组已废，这里不再保留（留着会被误当成渲染分组用）。
const List<DiaryRangeDef> kDiaryRanges = [
  (k: 'all', n: '全部'),
  (k: '7d', n: '近 7 天'),
  (k: '30d', n: '近 30 天'),
  (k: '90d', n: '近 3 月'),
  (k: 'year', n: '今年'),
  (k: 'month', n: '上月'),
  (k: '1y', n: '近一年'),
  (k: '2y', n: '近两年'),
];

/// 落盘合法键＝8 档预设 ＋ `custom`。
///
/// `custom` **不在** [kDiaryRanges] 里（它不是一枚预设胶囊，而是「应用自定义起止」
/// 之后的态），但读数时必须认它，否则冷启动会把自定义区间静默拽回「全部」。
const String kDiaryRangeCustom = 'custom';

/// 合法键集合（含 `custom`），供 settings 层脏值收敛。
const Set<String> kDiaryRangeKeys = {
  'all', '7d', '30d', '90d', 'year', 'month', '1y', '2y', kDiaryRangeCustom,
};

/// `YYYY-MM-DD` 日期串（**按本地年月日补零**，不是 `toIso8601String()`——
/// 后者带时刻与毫秒，与落盘的起止串比大小会因长度不同而错序）。
String dfIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// 两个日期相差几个「自然日」（b - a，取整到天）。
///
/// 用 UTC 构造再相减：本地时间在夏令时切换日是 23h/25h，`inDays` 会截成 0/1 之误；
/// UTC 每天恒 24h，天数差与日历一致。
int dfDayDiff(DateTime a, DateTime b) {
  final ua = DateTime.utc(a.year, a.month, a.day);
  final ub = DateTime.utc(b.year, b.month, b.day);
  return ub.difference(ua).inDays;
}

/// 「应用」按钮是否可点（原型 `ok = dfFrom && dfTo && dfFrom<=dfTo`）。
///
/// **比原型放宽一端**：原型注释明写「两端都可留空 ⇒ 只填一端就是某日之后／某日之前
/// 的开区间，比预设更通用」，但 `ok` 判据只认两端齐——设计与实现自相矛盾。
/// 这里按**设计意图**落：一端非空即可应用（[diaryInRange] 的 custom 分支本来就
/// 只在非空那端设限），两端都空＝还没选，不给点；`from > to`＝非法区间，不给点。
bool dfRangeValid({String from = '', String to = ''}) {
  final hasFrom = from.isNotEmpty;
  final hasTo = to.isNotEmpty;
  if (!hasFrom && !hasTo) return false;
  if (hasFrom && hasTo && from.compareTo(to) > 0) return false;
  return true;
}

/// 时间段显示名（原型 `dfRangeName`）。
///
/// `custom` 的四种兜名有实际用处：底部计数行、「已应用」提示都要说出人话，
/// 不能只显示一个 `custom`。
String dfRangeName(String range, {String from = '', String to = ''}) {
  if (range == kDiaryRangeCustom) {
    if (from.isNotEmpty && to.isNotEmpty) return '$from 至 $to';
    if (from.isNotEmpty) return '$from 起';
    if (to.isNotEmpty) return '$to 前';
    return '自定义';
  }
  for (final r in kDiaryRanges) {
    if (r.k == range) return r.n;
  }
  return '全部'; // 脏键按「不设限」处理，与 diaryInRange 的宽容分支同口径
}

/// 一篇日记是否落在当前时间段内（原型 `dwInRange`）。
///
/// 判据分三类，**与原型逐条对齐**：
/// - 相对天数窗：含今天（7d ⇒ 0..6 天，30d ⇒ 0..29，90d ⇒ 0..89，1y ⇒ 0..364，
///   2y ⇒ 0..729）——注意全部是**闭区间且以「今天 0 点」为基准**，未来日期落不进来；
/// - 自然年/自然月：`year`＝当年；`month`＝**上一个自然月**（不是本自然月，
///   产品要的是「上月的复盘」，一月时回退到去年十二月）；
/// - `custom`：起止串直接比 `YYYY-MM-DD`（免手算天数差），**一端空即开区间**。
///
/// [now] 只为可测注入，生产不传＝ `DateTime.now()`。
bool diaryInRange(
  JournalEntry e, {
  required String range,
  String from = '',
  String to = '',
  DateTime? now,
}) {
  if (range == 'all') return true;
  final today = now ?? DateTime.now();
  final d = e.day;
  switch (range) {
    case '7d':
      final n = dfDayDiff(d, today);
      return n >= 0 && n <= 6;
    case '30d':
      final n = dfDayDiff(d, today);
      return n >= 0 && n <= 29;
    case '90d':
      final n = dfDayDiff(d, today);
      return n >= 0 && n <= 89;
    case '1y':
      final n = dfDayDiff(d, today);
      return n >= 0 && n <= 364;
    case '2y':
      final n = dfDayDiff(d, today);
      return n >= 0 && n <= 729;
    case 'year':
      return d.year == today.year;
    case 'month':
      // 上一自然月：一月要回退到去年十二月。
      final py = today.month == 1 ? today.year - 1 : today.year;
      final pm = today.month == 1 ? 12 : today.month - 1;
      return d.year == py && d.month == pm;
    case kDiaryRangeCustom:
      final iso = dfIsoDate(d);
      if (from.isNotEmpty && iso.compareTo(from) < 0) return false;
      if (to.isNotEmpty && iso.compareTo(to) > 0) return false;
      return true;
    default:
      // 未知档位不设限：宁可多显示，也不把用户的日记藏没（与原型 `return true` 一致）。
      return true;
  }
}

/// 弹层底部计数文案（原型 `renderDfCount`）。
///
/// 无任何条件时是「共 N 篇日记」，有条件时把条件逐项说出来——用户关掉弹层后
/// 只能看列表，得能从这行文字反推「为什么只剩这么几篇」。
///
/// [mark] 是单选筛选键：命中 [kDfMarkKeys] 的走中文名，其余**当标签**输出 `#名字`
/// （原型 `diaryTags.map(t=>'#'+t)` 同一形态）。这个分流不能省——`dfMarkLabel`
/// 对未知键回「全部」，直接套会把「筛的是 #复盘」显示成「当前筛选：全部」。
String dfCountLabel({
  required int n,
  String mark = 'all',
  String range = 'all',
  String from = '',
  String to = '',
}) {
  final parts = <String>[];
  if (mark != 'all') {
    parts.add(kDfMarkKeys.contains(mark) ? dfMarkLabel(mark) : '#$mark');
  }
  if (range != 'all') parts.add(dfRangeName(range, from: from, to: to));
  if (parts.isEmpty) return '共 $n 篇日记';
  return '当前筛选：${parts.join(' · ')}，共 $n 篇';
}
