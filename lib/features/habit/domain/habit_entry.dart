import 'habit.dart';

/// 按日流水（habit_entries · 习惯计划 §2.1 ★表）。
///
/// UNIQUE(habit_id, day)：同日二次写=改值不新增；
/// origin 必写来源（手动/自动四源/补记/模板），统计与流水可区分（§5-8）。
class HabitEntry {
  const HabitEntry({
    this.id = 0,
    required this.habitId,
    required this.day,
    this.checked = true,
    this.value,
    required this.origin,
    this.checkAt,
    this.backfilled = false,
    this.frozen = false,
    this.note,
    this.createdAt = 0,
    this.updatedAt = 0,
    this.subValues = const {},
  });

  // 来源枚举（origin 列值 · 计划 §2.1）
  static const oManual = 'manual';
  static const oAutoTodo = 'auto-todo';
  static const oAutoPomo = 'auto-pomo';
  static const oAutoRead = 'auto-read';
  static const oAutoSchedule = 'auto-schedule';
  static const oBackfill = 'backfill';
  static const oTemplate = 'template';

  final int id;
  final String habitId;

  /// 自然日 'YYYY-MM-DD'。
  final String day;

  /// 正向=已达成；负向=当日未触发/已规避。
  final bool checked;

  /// 非组习惯的记录量；null=只打卡无量。
  final double? value;
  final String origin;

  /// 'HH:MM' 打卡时刻（自动源取源事件完成时刻）。
  final String? checkAt;

  /// 补记（统计单列展示 · UI ring-amber）。
  final bool backfilled;

  /// 宽限卡抵断签日：checked=false 但不断连（批5 用列，批1 判定即生效）。
  final bool frozen;
  final String? note;
  final int createdAt;
  final int updatedAt;

  /// 组打卡逐子项数值 subId → value（habit_entry_subs）。
  final Map<int, double> subValues;

  Map<String, Object?> toRow() => {
    'id': id == 0 ? null : id,
    'habit_id': habitId,
    'day': day,
    'checked': checked ? 1 : 0,
    'value': value,
    'origin': origin,
    'check_at': checkAt,
    'backfilled': backfilled ? 1 : 0,
    'frozen': frozen ? 1 : 0,
    'note': note,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory HabitEntry.fromRow(Map<String, Object?> r) => HabitEntry(
    id: r['id'] as int,
    habitId: r['habit_id'] as String,
    day: r['day'] as String,
    checked: (r['checked'] as int) == 1,
    value: (r['value'] as num?)?.toDouble(),
    origin: r['origin'] as String,
    checkAt: r['check_at'] as String?,
    backfilled: (r['backfilled'] as int? ?? 0) == 1,
    frozen: (r['frozen'] as int? ?? 0) == 1,
    note: r['note'] as String?,
    createdAt: (r['created_at'] as int?) ?? 0,
    updatedAt: (r['updated_at'] as int?) ?? 0,
  );
}

/// 该日是否「达成」（判定函数按正/负分叉 · 计划 §5-10）：
/// - 非组：正向看 checked；负向 checked=1 即「未触发」达成。
/// - 组：按 group_rule 判定子项达标数（all/half/any），无流水行=未达成。
bool habitOkAt(Habit h, HabitEntry? e) {
  if (e == null) return false;
  if (!h.isGroup) return e.checked;
  final goals = h.subs;
  if (goals.isEmpty) return e.checked;
  var met = 0;
  for (final s in goals) {
    if ((e.subValues[s.id] ?? 0) >= s.goal && s.goal > 0) met++;
  }
  return switch (h.groupRule) {
    Habit.kRuleAny => met >= 1,
    Habit.kRuleHalf => met >= (goals.length / 2).ceil(),
    _ => met == goals.length,
  };
}

/// 展示用记录量短串（原型 hbValTxt 口径）：组按子项分别显示，禁跨单位求和。
String habitValText(Habit h, HabitEntry? e) {
  if (e == null) return '—';
  if (h.isGroup) {
    final parts = [
      for (final s in h.subs)
        if ((e.subValues[s.id] ?? 0) > 0) '${s.name} ${_n(e.subValues[s.id])}${s.unit}',
    ];
    return parts.isEmpty ? '—' : parts.join(' · ');
  }
  return e.value == null ? '—' : '${_n(e.value)} ${h.unit ?? '次'}';
}

String _n(double? v) =>
    v == null ? '0' : (v % 1 == 0 ? '${v.toInt()}' : '$v');
