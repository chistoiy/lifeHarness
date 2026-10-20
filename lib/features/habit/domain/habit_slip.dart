/// 负向习惯的一次触发（habit_slips · 计划 §2.1）。
///
/// §5-10：触发日是一等数据——日历/流水/触发统计三处必须可见，
/// 配色 rose 中性事实色，不得带评判感。
class HabitSlip {
  const HabitSlip({
    this.id = 0,
    required this.habitId,
    required this.day,
    this.checkAt,
    this.amount,
    this.amountText,
    this.reasons = const [],
    this.note,
    this.createdAt = 0,
  });

  final int id;
  final String habitId;

  /// 'YYYY-MM-DD'。
  final String day;

  /// 'HH:MM' 触发时刻。
  final String? checkAt;
  final double? amount;

  /// 展示串（原型 amt：'1 杯 · 大杯'）。
  final String? amountText;

  /// 情境标签（熬夜/应酬/情绪/赶时间/忘记/他人带动）。
  final List<String> reasons;
  final String? note;
  final int createdAt;

  factory HabitSlip.fromRow(Map<String, Object?> r) => HabitSlip(
    id: r['id'] as int,
    habitId: r['habit_id'] as String,
    day: r['day'] as String,
    checkAt: r['check_at'] as String?,
    amount: (r['amount'] as num?)?.toDouble(),
    amountText: r['amount_text'] as String?,
    reasons: (r['reasons'] as String? ?? '')
        .split(',')
        .map((x) => x.trim())
        .where((x) => x.isNotEmpty)
        .toList(),
    note: r['note'] as String?,
    createdAt: (r['created_at'] as int?) ?? 0,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'habit_id': habitId,
    'day': day,
    'check_at': checkAt,
    'amount': amount,
    'amount_text': amountText,
    'reasons': reasons.join(','),
    'note': note,
    'created_at': createdAt,
  };
}
