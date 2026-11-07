/// C04 ICS 收集器（竞品补全批1 子批B）：把时间块 / 待办 / 重要日子映射成
/// [IcsItem]。纯函数、零 DB 零 Widget——调用方（导出弹层）负责取数与落盘。
///
/// 口径（过门样张 01 · 2026-11-06）：
/// - 时间块 → VEVENT（DTSTART=当日+startMin，DTEND=当日+endMin，SUMMARY=分类名）；
/// - 待办 → VTODO（仅带到期日的；`includeDone=false` 时跳过已完成）；
/// - 重要日子 → VEVENT（once/solarYear 锚 targetDate、monthly 用 monthDay、
///   lunar 走 [IcsRepeat.lunarYear] 逐年展开）；归档的日子不导出。
/// - [range] 非 null 时按**起始日期**过滤（闭区间）；null＝不过滤。
library;

import '../../features/calendar/domain/ics_export.dart';
import '../../features/calendar/domain/time_block.dart';
import '../../features/days/domain/day_models.dart';
import '../../features/todo/domain/todo.dart';

bool _inRange(DateTime d, ({DateTime from, DateTime to})? r) =>
    r == null || !d.isBefore(DateTime(r.from.year, r.from.month, r.from.day));

/// 时间块 → VEVENT。UID 前缀 `tb-`。
List<IcsItem> icsOfTimeBlocks(
  List<TimeBlock> blocks, {
  ({DateTime from, DateTime to})? range,
}) {
  final out = <IcsItem>[];
  for (final b in blocks) {
    final start =
        DateTime(b.day.year, b.day.month, b.day.day).add(Duration(minutes: b.startMin));
    if (!_inRange(start, range)) continue;
    out.add(IcsItem(
      uid: 'tb-${b.id ?? start.microsecondsSinceEpoch}',
      title: b.note?.trim().isNotEmpty == true ? '${b.catName} · ${b.note!.trim()}' : b.catName,
      start: start,
      end: start.add(Duration(minutes: b.endMin - b.startMin)),
    ));
  }
  return out;
}

/// 待办 → VTODO（无到期日的没法落到日历上，跳过）。UID 前缀 `td-`。
List<IcsItem> icsOfTodos(
  List<Todo> todos, {
  bool includeDone = false,
  ({DateTime from, DateTime to})? range,
}) {
  final out = <IcsItem>[];
  for (final t in todos) {
    final due = t.dueAt;
    if (due == null) continue;
    if (t.done && !includeDone) continue;
    if (!_inRange(due, range)) continue;
    out.add(IcsItem(
      uid: 'td-${t.id ?? due.microsecondsSinceEpoch}',
      title: t.title,
      start: due,
      note: t.note,
      todo: true,
      done: t.done,
    ));
  }
  return out;
}

/// 重要日子 → VEVENT。归档不导出；锚点日期缺失且非农历的跳过（没锚没法摆）。
/// UID 前缀 `day-`。
List<IcsItem> icsOfDays(
  List<DayEntry> days, {
  ({DateTime from, DateTime to})? range,
}) {
  final out = <IcsItem>[];
  for (final d in days) {
    if (d.archived) continue;
    final rep = switch (d.repeat) {
      DayRepeat.solarYear => IcsRepeat.solarYear,
      DayRepeat.monthly => IcsRepeat.monthly,
      DayRepeat.lunar => IcsRepeat.lunarYear,
      DayRepeat.once => IcsRepeat.none,
    };
    if (rep == IcsRepeat.lunarYear) {
      // 农历：锚点取 targetDate（仅取时分秒），月日号用 lunar 字段；
      // 两者齐全才展开（lunarToSolarInYear 在 buildIcs 内逐年换算）。
      if (d.lunarMonth == null || d.lunarDay == null || d.targetDate == null) {
        continue;
      }
      out.add(IcsItem(
        uid: 'day-${d.id}',
        title: d.title,
        start: d.targetDate!,
        note: d.note,
        repeat: IcsRepeat.lunarYear,
        lunarMonth: d.lunarMonth,
        lunarDay: d.lunarDay,
      ));
      continue;
    }
    final monthDay = d.monthDay;
    final anchor = d.targetDate ??
        (monthDay == null ? null : DateTime(2000, 1, monthDay));
    if (anchor == null) continue;
    if (!_inRange(anchor, range) && rep == IcsRepeat.none) continue;
    out.add(IcsItem(
      uid: 'day-${d.id}',
      title: d.title,
      start: anchor,
      note: d.note,
      repeat: rep,
    ));
  }
  return out;
}
