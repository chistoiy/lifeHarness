import 'habit.dart';
import 'habit_entry.dart';

/// 口径纯函数（习惯计划 §5 十一条的实现基线 · 单测友好、零依赖）。

/// 'YYYY-MM-DD'（D13 自然日）。
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime parseDay(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

/// 某日是否「计划日」（§5-6：非计划日不计分母也不断连）。
/// - day：每天都是计划日；
/// - week：落在 week_days 才是计划日；week_days 空=每周任意 1 天，
///   无固定计划日（分母另行按 1 次/周计，见 habitDueDaysInRange）；
/// - month：按月目标「次」计，天维度无计划日概念 → 均视为可打卡日。
bool habitPlannedOn(Habit h, DateTime day) {
  if (dayKey(day).compareTo(h.startDate) < 0) return false;
  if (h.cycle != Habit.kWeek) return true;
  return h.weekDays.contains(day.weekday - 1);
}

/// 区间应打卡天数（达成率分母 · §5-1）。开始日截断**不在此处**（统一由
/// habitEffDays 负责，rateBase=周期总天数时不受开始日影响）：
/// - month 周期按 targetM「次」而非「天」（语义分离）；
/// - week 无固定日按每周 1 次（任意日达成即算）。
int habitDueDaysInRange(Habit h, DateTime from, DateTime to) {
  if (to.isBefore(from)) return 0;
  final n = dayStart(to).difference(dayStart(from)).inDays + 1;
  switch (h.cycle) {
    case Habit.kMonth:
      return h.monthTarget == null ? n : h.monthTarget!;
    case Habit.kWeek:
      if (h.weekDays.isEmpty) {
        return (n / 7).ceil();
      }
      var c = 0;
      for (var i = 0; i < n; i++) {
        final d = dayStart(from.add(Duration(days: i)));
        if (h.weekDays.contains(d.weekday - 1)) c++;
      }
      return c;
    default:
      return n;
  }
}

/// 有效天数截断（§5-1/§5-2 核心防摊薄）：spanFromStart 开且周期起点
/// 早于开始跟踪日时，分母只计开始日之后天数；关或已开始则返回 full。
int habitEffDays(
  Habit h, {
  required int periodDays,
  required DateTime periodStart,
  required DateTime today,
  bool spanFromStart = true,
}) {
  if (!spanFromStart) return periodDays;
  final s = parseDay(h.startDate);
  final end = periodStart.add(Duration(days: periodDays - 1));
  if (s.isAfter(end)) return 0; // 周期整体早于开始跟踪日：无有效天
  if (s.isAfter(periodStart)) {
    if (s.isAfter(today)) return 0;
    return [
      periodDays,
      dayStart(today).difference(s).inDays + 1,
    ].reduce((a, b) => a < b ? a : b);
  }
  return periodDays;
}

/// 达成率（§5-2）：分子=区间内达成天数（habitOkAt 判定），
/// 分母=应打卡天数（rateBase=1 时改周期总天数），两者都先过 effDays 截断。
int habitRate(
  Habit h, {
  required Map<String, HabitEntry> entries,
  required DateTime from,
  required DateTime to,
  bool spanFromStart = true,
  bool rateByTotalDays = false,
}) {
  final n = dayStart(to).difference(dayStart(from)).inDays + 1;
  var due = habitDueDaysInRange(h, from, to);
  final full = rateByTotalDays ? n : due;
  due = habitEffDays(
    h,
    periodDays: full,
    periodStart: from,
    today: to,
    spanFromStart: spanFromStart,
  );
  if (due <= 0) return 0;
  var ok = 0;
  for (var i = 0; i < n; i++) {
    final d = dayStart(from.add(Duration(days: i)));
    if (!habitPlannedOn(h, d)) continue;
    if (habitOkAt(h, entries[dayKey(d)])) ok++;
  }
  return (ok * 100 / due).clamp(0, 100).round();
}

/// 「不断连」判定：达成 或 宽限卡抵住（frozen=1 只保连续，不算达成率分子）。
bool _keepsChain(Habit h, HabitEntry? e) =>
    habitOkAt(h, e) || (e?.frozen ?? false);

/// 连续天数（当前 streak · §5-6）：自 today 沿日回溯，仅计划日计入；
/// 计划日未达成即断；frozen=1（宽限日）与非计划日不断连也不计数。
/// 今天（计划日）尚未打卡不判为断，从昨天起算（当日仍开放）；
/// 但负向今日已有触发行（checked=0）＝事实断连，不适用开放豁免（§5-10）。
int habitStreak(Habit h, Map<String, HabitEntry> entries, DateTime today) {
  final start = parseDay(h.startDate);
  var d = dayStart(today);
  if (d.isBefore(start)) return 0;
  final e0 = entries[dayKey(d)];
  if (habitPlannedOn(h, d) && !_keepsChain(h, e0)) {
    if (e0 == null || (!h.isNeg && e0.checked && !h.hasVal)) {
      // 当日仍开放：无流水行，或正向无量今日未打卡（撤销态≠断签）。
      d = d.subtract(const Duration(days: 1));
    } else {
      // 负向触发行（checked=0）＝事实断连，不适用开放豁免（§5-10）。
      return 0;
    }
  }
  // 注：week 无固定日/月周期不存在「日」粒度计划，streak 恒 0（原型同口径）。
  var n = 0;
  while (!d.isBefore(start)) {
    if (habitPlannedOn(h, d)) {
      if (_keepsChain(h, entries[dayKey(d)])) {
        n++;
      } else {
        break;
      }
    }
    d = d.subtract(const Duration(days: 1));
  }
  return n;
}

/// 历史最长连续（best）：自开始日全量顺扫，规则同上。
int habitBestStreak(
  Habit h,
  Map<String, HabitEntry> entries,
  DateTime today,
) {
  final start = parseDay(h.startDate);
  final end = dayStart(today);
  if (end.isBefore(start)) return 0;
  var best = 0, cur = 0;
  for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
    if (!habitPlannedOn(h, d)) continue; // 非计划日：不计也不断
    if (_keepsChain(h, entries[dayKey(d)])) {
      cur++;
      if (cur > best) best = cur;
    } else {
      cur = 0;
    }
  }
  return best;
}

/// 区间达成次数（hero 计数 / 月周期「每月 N 次」分子）。
int habitCountOkInRange(
  Habit h,
  Map<String, HabitEntry> entries,
  DateTime from,
  DateTime to,
) {
  final lo = dayKey(from), hi = dayKey(to);
  var n = 0;
  for (final e in entries.values) {
    if (e.habitId != h.id || e.day.compareTo(lo) < 0 || e.day.compareTo(hi) > 0) {
      continue;
    }
    if (habitOkAt(h, e)) n++;
  }
  return n;
}

/// 区间记录总量（日均分子 · §5-3）。组习惯禁跨单位求和：返回 null，
/// 调用方改走 habitSubTotals 按子项分别显示。
double? habitTotalValue(
  Habit h,
  Map<String, HabitEntry> entries,
  DateTime from,
  DateTime to,
) {
  if (h.isGroup) return null;
  var sum = 0.0;
  for (final e in entries.values) {
    if (e.habitId != h.id || e.value == null) continue;
    if (e.day.compareTo(dayKey(from)) >= 0 && e.day.compareTo(dayKey(to)) <= 0) {
      sum += e.value!;
    }
  }
  return sum;
}

/// 组习惯子项区间合计（subId → 总量）。
Map<int, double> habitSubTotals(
  Habit h,
  Map<String, HabitEntry> entries,
  DateTime from,
  DateTime to,
) {
  final out = <int, double>{};
  final lo = dayKey(from), hi = dayKey(to);
  for (final e in entries.values) {
    if (e.habitId != h.id || e.day.compareTo(lo) < 0 || e.day.compareTo(hi) > 0) {
      continue;
    }
    e.subValues.forEach((k, v) => out[k] = (out[k] ?? 0) + v);
  }
  return out;
}

// ---- 提醒门控（批5 · 计划 §6/§7：remindAll × dnd 双重门控）----

/// 晚间提醒时间档（habit.nightAt 下标 → HH:mm）。
const kHabitNightAts = ['18:00', '20:00', '21:30', '22:30'];

/// 免打扰时段档（habit.dnd 下标 → (起,止)，null=关闭）。
const kHabitDndWindows = <(String, String)?>[
  null,
  ('22:00', '08:00'),
  ('23:00', '07:00'),
];

/// 某时刻（HH:mm）是否落在 dnd 档内（跨零点窗口按 起..24 + 0..止 判定）。
bool habitInDnd(int dnd, String hhmm) {
  final w = dnd >= 0 && dnd < kHabitDndWindows.length ? kHabitDndWindows[dnd] : null;
  if (w == null) return false;
  int mins(String t) {
    final p = t.split(':');
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }
  final m = mins(hhmm), s = mins(w.$1), e = mins(w.$2);
  return s > e ? (m >= s || m < e) : (m >= s && m < e);
}
