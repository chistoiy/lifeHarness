/// 小工具合集 · 纯计算（原型 `KIT_METRICS` / 统计页实算口径）。
///
/// 全部函数无副作用、时钟由参数注入（红线：用例禁时间炸弹，
/// 23:55–00:30 跨日窗口内也能稳定判定）。
library;

import 'kit_models.dart';

/// 当日零点（本模块自用；habit 侧同名函数属 feature，R1 不得跨模块 import）。
DateTime kitDayStart(DateTime d) => DateTime(d.year, d.month, d.day);

/// 近 N 天窗口起点（含今天，N=7 → 今天往前数 6 天的零点）。
DateTime kitWindowStart(DateTime now, int days) =>
    kitDayStart(now).subtract(Duration(days: days - 1));

/// 八枚数据位取值（[plugCount]/[plugOnCount]/[plugSizeKb] 由仓储侧传入，
/// 让本文件保持零依赖、可直接单测）。
int kitMetricValue(
  KitMetric m, {
  required List<KitUsage> log,
  required DateTime now,
  required List<String> fav,
  int plugCount = 0,
  int plugOnCount = 0,
  int plugSizeKb = 0,
}) {
  switch (m) {
    case KitMetric.total:
      return log.length;
    case KitMetric.week:
      final from = kitWindowStart(now, 7).millisecondsSinceEpoch;
      return log.where((e) => e.ts >= from).length;
    case KitMetric.today:
      final from = kitDayStart(now).millisecondsSinceEpoch;
      return log.where((e) => e.ts >= from).length;
    case KitMetric.fav:
      return fav.length;
    case KitMetric.recent:
      return kitCountByTool(log).length;
    case KitMetric.plug:
      return plugCount;
    case KitMetric.plugOn:
      return plugOnCount;
    case KitMetric.size:
      return plugSizeKb;
  }
}

/// 按工具聚合使用次数（保持首次出现顺序无关，调用侧按次数排序）。
Map<String, int> kitCountByTool(List<KitUsage> log) {
  final out = <String, int>{};
  for (final e in log) {
    out[e.tool] = (out[e.tool] ?? 0) + 1;
  }
  return out;
}

/// 某工具最近一次使用时间（无记录返回 null；原型「最近使用」横条同口径）。
int? kitLastUse(List<KitUsage> log, String tool) {
  int? last;
  for (final e in log) {
    if (e.tool == tool && (last == null || e.ts > last)) last = e.ts;
  }
  return last;
}

/// 按日聚合（热力图与「近 7 天」柱列共用；key=当日零点毫秒）。
Map<int, int> kitCountByDay(List<KitUsage> log, DateTime now, int days) {
  final start = kitWindowStart(now, days).millisecondsSinceEpoch;
  final out = <int, int>{};
  for (final e in log) {
    if (e.ts < start) continue;
    final key = kitDayStart(
      DateTime.fromMillisecondsSinceEpoch(e.ts),
    ).millisecondsSinceEpoch;
    out[key] = (out[key] ?? 0) + 1;
  }
  return out;
}

/// 分类分布（工具键 → 分类；未登记键归入「其他」，与原型 `kitCatOf` 兜底一致）。
Map<KitCat, int> kitCountByCat(List<KitUsage> log) {
  final out = <KitCat, int>{};
  for (final e in log) {
    final t = kitToolOf(e.tool);
    final cat = t?.cat ?? KitCat.demo;
    out[cat] = (out[cat] ?? 0) + 1;
  }
  return out;
}

/// 相对时间文案（原型 `kitRel`：刚刚 / N 分钟前 / 今天 / N 天前 / M-D）。
String kitRelText(int? ts, DateTime now) {
  if (ts == null) return '未使用';
  final diff = now.difference(DateTime.fromMillisecondsSinceEpoch(ts));
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  final day = kitDayStart(
    now,
  ).difference(kitDayStart(DateTime.fromMillisecondsSinceEpoch(ts))).inDays;
  if (day == 0) return '${diff.inHours} 小时前';
  if (day == 1) return '昨天';
  if (day < 7) return '$day 天前';
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  return '${d.month}-${d.day}';
}

/// 体积可读化（原型走查 A6 的 `kitKB()` 口径：<1KB 显示 B，空文件标注）。
String kitKbText(int kb) {
  if (kb <= 0) return '0 B';
  if (kb < 1) return '${(kb * 1024).round()} B';
  if (kb < 1024) return '${kb.round()}KB';
  return '${(kb / 1024).toStringAsFixed(1)}M';
}

/// 字节 → 可读体积（原型 `kitKB(n)`：B / KB（<10KB 留一位小数））。
String kitBytesText(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  final kb = bytes / 1024;
  return '${kb.toStringAsFixed(bytes < 10240 ? 1 : 0)}KB';
}

String _two(int n) => n.toString().padLeft(2, '0');

/// 日期键 `YYYY-MM-DD`（原型 `kitDkey`）。
String kitDateKey(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  return '${d.year}-${_two(d.month)}-${_two(d.day)}';
}

/// `MM-DD`（原型 `kitDkey(ts).slice(5)`；测速历史行首）。
String kitMonthDay(int ts) => kitDateKey(ts).substring(5);

/// `HH:MM` 24 小时制（原型 `toTimeString().slice(0,5)`；AI 验证记录行首）。
String kitHourMinute(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  return '${_two(d.hour)}:${_two(d.minute)}';
}
