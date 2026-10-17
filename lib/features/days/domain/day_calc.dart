/// 日子引擎（HG-E1：列表倒数、提醒排期、去年今日一律实算，禁手填）。
library;

import 'day_models.dart';
import '../../../shared/calendar/lunar.dart';

/// 自然日差（b − a，按零点日界）。
int dayDiff(DateTime a, DateTime b) =>
    DateTime(b.year, b.month, b.day).difference(DateTime(a.year, a.month, a.day)).inDays;

/// 一条日子的下次（或本次已过的最近一次）发生日。
/// - once：即锚点日（可过去，列表显「已过 N 天 · 去处理」）；
/// - solarYear：锚点月日在 today 当年或之后的第一次（2/29 无该日→2/28）；
/// - lunar：农历月日逐年换算公历（平月优先），取 today 起最近一次；
/// - monthly：monthDay 落本月（超出当月天数收敛到月末），已过则下月。
DateTime nextOccurrence(DayEntry d, DateTime today) {
  final t = DateTime(today.year, today.month, today.day);
  switch (d.repeat) {
    case DayRepeat.once:
      final g = d.targetDate!;
      return DateTime(g.year, g.month, g.day);
    case DayRepeat.solarYear:
      final g = d.targetDate!;
      for (var y = t.year;; y++) {
        final day = _clampDay(y, g.month, g.day);
        final cand = DateTime(y, g.month, day);
        if (!cand.isBefore(t)) return cand;
      }
    case DayRepeat.lunar:
      for (var y = t.year;; y++) {
        final cand = lunarToSolarInYear(y, d.lunarMonth!, d.lunarDay!);
        if (cand == null) return DateTime(t.year, 12, 31);
        if (!cand.isBefore(t)) return cand;
      }
    case DayRepeat.monthly:
      final md = d.monthDay!;
      final thisMonth = _clampDay(t.year, t.month, md);
      final cand = DateTime(t.year, t.month, thisMonth);
      return cand.isBefore(t)
          ? DateTime(t.year, t.month + 1, _clampDay(t.year, t.month + 1, md))
          : cand;
  }
}

int _clampDay(int y, int m, int day) {
  final last = DateTime(y, m + 1, 0).day; // m 月天数
  return day > last ? last : day;
}

/// 倒数天数（正=还剩，负=已过）。归档条目同样可算（详情回看用）。
int countdownDays(DayEntry d, DateTime today) =>
    dayDiff(today, nextOccurrence(d, today));

/// 是否「已过」展示态：once 过期、或循环条目最近一次发生日严格早于今天。
/// 循环条目 nextOccurrence 恒 >= 今天，故负数仅出现在 once。
bool isOverdue(DayEntry d, DateTime today) => countdownDays(d, today) < 0;

/// 列表副行标签（原型 x.l 同语义，但数值全实算）。
String occurrenceLabel(DayEntry d, DateTime today) {
  final occ = nextOccurrence(d, today);
  final md = '${_two(occ.month)}-${_two(occ.day)}';
  switch (d.repeat) {
    case DayRepeat.once:
      final past = countdownDays(d, today) < 0;
      return past
          ? '已过 ${-countdownDays(d, today)} 天 · 去处理'
          : '${occ.year}-${_two(occ.month)}-${_two(occ.day)}';
    case DayRepeat.solarYear:
      return '公历 ${_two(d.targetDate!.month)}-${_two(d.targetDate!.day)} · 每年循环';
    case DayRepeat.lunar:
      return '农历 ${lunarLabel(d.lunarMonth!, d.lunarDay!)} · 对应公历 $md';
    case DayRepeat.monthly:
      return '每月 ${d.monthDay} 日 · 循环';
  }
}

String _two(int v) => v.toString().padLeft(2, '0');

/// 一个提醒排期点（通知触发日 + 该次对应的发生日）。
class DayReminderHit {
  const DayReminderHit({
    required this.dayId,
    required this.offset,
    required this.occurrence,
    required this.remindAt,
  });
  final int dayId;
  final int offset;
  final DateTime occurrence;

  /// 触发日零点（presentation 侧按 09:00 组装通知时刻）。
  final DateTime remindAt;
}

/// 未来 [horizonDays] 天内该日子应触发的全部提前提醒（含当天档）。
List<DayReminderHit> upcomingReminders(
    DayEntry d, DateTime today, int horizonDays) {
  final out = <DayReminderHit>[];
  if (d.id == null || d.archived || d.remOffsets.isEmpty) return out;
  var occ = nextOccurrence(d, today);
  final maxOff = d.remOffsets.reduce((a, b) => a > b ? a : b);
  while (true) {
    // 锚点日超出「视界+最大提前量」即停：保证 occ-偏移 落在视界内的锚点都被评估
    if (dayDiff(today, occ) > horizonDays + maxOff) break;
    for (final off in d.remOffsets) {
      final at = occ.subtract(Duration(days: off));
      if (dayDiff(today, at) >= 0 && dayDiff(today, at) <= horizonDays) {
        // 今天或未来视界内（当天档若尚未过触发时刻也算）
        out.add(DayReminderHit(
            dayId: d.id!, offset: off, occurrence: occ, remindAt: at));
      }
    }
    final next = nextOccurrence(d, occ.add(const Duration(days: 1)));
    if (next == occ) break; // once：不再滚动
    occ = next;
  }
  out.sort((a, b) => a.remindAt.compareTo(b.remindAt));
  return out;
}

/// 列表排序（原型 renderDays：按 |倒数天数| 最近/最久优先；置顶恒在前）。
List<DayEntry> sortDays(List<DayEntry> src, DateTime today,
    {bool asc = true}) {
  final list = [...src];
  list.sort((a, b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    final da = countdownDays(a, today).abs();
    final db = countdownDays(b, today).abs();
    return asc ? da.compareTo(db) : db.compareTo(da);
  });
  return list;
}

/// 仪表盘「最近的日子」倒数卡成员（未归档、非过期，按剩余升序，置顶第一）。
List<DayEntry> dashboardUpcoming(List<DayEntry> src, DateTime today,
    {int limit = 3}) {
  final act = src.where((d) => !d.archived && !isOverdue(d, today)).toList();
  act.sort((a, b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    return countdownDays(a, today).compareTo(countdownDays(b, today));
  });
  return act.take(limit).toList();
}

/// 「去年今天」检索参数：与今天同 MM-DD 的历史年（当年日记回看联动 L5 共用）。
({int month, int day}) anniversaryOf(DateTime today) =>
    (month: today.month, day: today.day);
