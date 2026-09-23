import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../data/habit_repository.dart';
import '../domain/habit.dart';
import '../domain/habit_calc.dart';
import '../domain/habit_dict.dart';
import '../domain/habit_entry.dart';

/// 习惯模块 providers（仿 read_providers 范式：写库后 habitTick++ 全量重取）。

final habitRepositoryProvider = Provider<HabitRepository>(
  (ref) => HabitRepository(AppDatabase.instance.db),
);

final habitTickProvider = StateProvider<int>((ref) => 0);

/// 主页视图三态 / 状态筛选 / 分类筛选偏好键（§3.2 偏好本地记忆 · settings KV）。
const kHabitViewKey = 'habit.view'; // list|compact|grid
const kHabitSegKey = 'habit.seg'; // all|todo|ok|grp|neg|arch
const kHabitCatKey = 'habit.catF'; // 全部|<分类名>

/// 一帧习惯域数据（主页/弹层共用一次取齐）。
class HabitData {
  const HabitData({
    required this.habits,
    required this.entries,
    required this.cats,
    required this.units,
    required this.view,
    required this.seg,
    required this.catF,
    required this.weekStart,
    required this.spanFromStart,
    required this.rateByTotalDays,
    required this.grace,
    required this.graceOf,
  });

  final List<Habit> habits;

  /// habitId → (day → entry)。
  final Map<String, Map<String, HabitEntry>> entries;
  final List<HabitDict> cats;
  final List<HabitDict> units;
  final String view;
  final String seg;
  final String catF;

  /// 0=周一开头 1=周日开头（habit.weekStart · 月历分列用）。
  final int weekStart;
  final bool spanFromStart;
  final bool rateByTotalDays;
  final int grace;

  /// habitId → 本月剩余宽限张数（§2.1：余额按 月已用 推导）。
  final Map<String, int> graceOf;

  /// 未归档（原型 hbBook）。
  List<Habit> get book => habits.where((h) => !h.isArchived).toList();
  List<Habit> get archived => habits.where((h) => h.isArchived).toList();

  Map<String, HabitEntry> of(String habitId) =>
      entries[habitId] ?? const {};

  bool okOn(Habit h, String day) => habitOkAt(h, of(h.id)[day]);

  /// 今日应打卡集合（原型 hbToday：day 每天 / week 固定日 / month 未满目标次数）。
  List<Habit> dueToday(DateTime today) {
    final k = dayKey(today);
    return book.where((h) {
      if (k.compareTo(h.startDate) < 0) return false;
      switch (h.cycle) {
        case Habit.kWeek:
          // 原型口径：仅固定日当天入今日队列；「每周任意 1 天」不占。
          return h.weekDays.contains(today.weekday - 1);
        case Habit.kMonth:
          final m0 = DateTime(today.year, today.month);
          return habitCountOkInRange(h, of(h.id), m0, today) <
              (h.monthTarget ?? 0);
        default:
          return true;
      }
    }).toList();
  }
}

final habitDataProvider = FutureProvider<HabitData>((ref) async {
  ref.watch(habitTickProvider);
  final repo = ref.watch(habitRepositoryProvider);
  final habits = await repo.allHabits();
  final entries = await repo.entriesByHabit();
  final cats = await repo.dictOf(HabitDict.kCat);
  final units = await repo.dictOf(HabitDict.kUnit);
  return HabitData(
    habits: habits,
    entries: entries,
    cats: cats,
    units: units,
    view: await repo.kv(kHabitViewKey) ?? 'list',
    seg: await repo.kv(kHabitSegKey) ?? 'all',
    catF: await repo.kv(kHabitCatKey) ?? '全部',
    weekStart: await repo.kvInt('habit.weekStart', 0),
    spanFromStart: await repo.kvBool('habit.spanFromStart', true),
    rateByTotalDays: (await repo.kvInt('habit.rateBase', 0)) == 1,
    grace: await repo.kvInt('habit.grace', 1),
    graceOf: {
      for (final h in habits) h.id: await repo.graceLeft(h),
    },
  );
});

/// 单条习惯的一行渲染数据（三视图共用 · 滚动 7 日窗口 = 今天往前 7 天，
/// 回看模式下高亮格随所选日移动，永不越窗）。
class HabitRowInfo {
  const HabitRowInfo({
    required this.flags,
    required this.frozens,
    required this.tips,
    required this.todayIdx,
    required this.rate,
    required this.weekOk,
    required this.bfCount,
    required this.dayOk,
    required this.dayEntry,
    required this.daySubs,
    required this.dayValText,
    required this.dayShortVal,
    required this.negUsed,
  });

  final List<bool> flags;
  final List<bool> frozens;
  final List<String> tips;

  /// 所选日在 7 格中的下标（6 - 回看天数）。
  final int todayIdx;
  final int rate;
  final int weekOk;
  final int bfCount;

  /// 所选日是否达成（正向已打卡 / 负向已记「没做」）。
  final bool dayOk;
  final HabitEntry? dayEntry;

  /// 所选日组子项值。
  final Map<int, double> daySubs;

  /// 所选日量摘要（非组：'35 分钟'；无值空串）。
  final String dayValText;
  final String dayShortVal;

  /// 负向本周已触发次数。
  final int negUsed;
}

/// 装配一行数据。[viewDay] = 当前查看日（今天或回看日）。
HabitRowInfo buildRowInfo(
  HabitData d,
  Habit h,
  DateTime today,
  DateTime viewDay,
) {
  final t0 = dayStart(today);
  final keys = [
    for (var i = 6; i >= 0; i--) dayKey(t0.subtract(Duration(days: i))),
  ];
  final entries = d.of(h.id);
  final flags = [for (final k in keys) habitOkAt(h, entries[k])];
  final frozens = [
    for (final k in keys)
      (entries[k]?.frozen ?? false) && !habitOkAt(h, entries[k]),
  ];
  final tips = [
    for (var i = 0; i < 7; i++)
      () {
        final e = entries[keys[i]];
        final parts = <String>[
          '${keys[i].substring(5)} ${'周${'一二三四五六日'[parseDay(keys[i]).weekday - 1]}'}',
        ];
        if (h.isNeg) {
          parts.add(
            e == null
                ? '未记录'
                : (e.checked ? '未触发' : '触发${e.value != null ? ' · ${e.value} ${h.unit ?? '次'}' : ''}'),
          );
        } else if (e != null) {
          parts.add(habitOkAt(h, e) ? '已打卡' : '未达成');
          if (h.hasVal) parts.add(habitValText(h, e));
        }
        if (e?.checkAt?.isNotEmpty ?? false) parts.add(e!.checkAt!);
        if (e?.backfilled ?? false) parts.add('补记');
        return parts.join(' · ');
      }(),
  ];
  final idx = dayKey(dayStart(viewDay)) == keys[6]
      ? 6
      : keys.indexOf(dayKey(dayStart(viewDay)));
  final vk = dayKey(dayStart(viewDay));
  final dayEntry = entries[vk];
  final weekFrom = dayStart(today).subtract(const Duration(days: 6));
  final rate = habitRate(
    h,
    entries: entries,
    from: weekFrom,
    to: t0,
    spanFromStart: d.spanFromStart,
    rateByTotalDays: d.rateByTotalDays,
  );
  final weekOk = flags.where((f) => f).length;
  final bfCount = [
    for (final k in keys)
      if (entries[k]?.backfilled ?? false) 1,
  ].length;
  return HabitRowInfo(
    flags: flags,
    frozens: frozens,
    tips: tips,
    todayIdx: idx < 0 ? 6 : idx,
    rate: rate,
    weekOk: weekOk,
    bfCount: bfCount,
    dayOk: habitOkAt(h, dayEntry),
    dayEntry: dayEntry,
    daySubs: dayEntry?.subValues ?? const {},
    dayValText:
        h.isGroup || dayEntry?.value == null ? '' : habitValText(h, dayEntry),
    dayShortVal: h.isGroup
        ? [
            for (final s in h.subs)
              '${(dayEntry?.subValues[s.id] ?? 0).toString().replaceAll(RegExp(r'\.0$'), '')}${s.unit}',
          ].join(' / ')
        : (dayEntry?.value != null ? habitValText(h, dayEntry) : ''),
    negUsed: [
      for (final e in entries.values)
        if (!e.checked &&
            e.day.compareTo(dayKey(weekFrom)) >= 0 &&
            e.day.compareTo(dayKey(t0)) <= 0)
          e,
    ].length,
  );
}

/// 顶栏日期行文案（原型 hbDayLabel：今天 · 09-19 周六 / 昨天 / 前天 / 回看 N 天前）。
String habitDayLabel(DateTime today, DateTime viewDay) {
  final back = dayStart(today).difference(dayStart(viewDay)).inDays;
  final d = dayStart(viewDay);
  final md =
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  final wd = '周${'一二三四五六日'[d.weekday - 1]}';
  return switch (back) {
    0 => '今天 · $md $wd',
    1 => '昨天 · $md $wd',
    2 => '前天 · $md $wd',
    _ => '回看 $back 天前',
  };
}
