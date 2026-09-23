import 'dart:convert';

/// 习惯数据模型（习惯计划 §2.1 · DB v16）。
///
/// 口径：
/// - 自然日一律 'YYYY-MM-DD' TEXT（D13 日界线 00:00，防时区歧义）；
/// - streak/best 为**写入时重算的缓存列**（habit_entries 流水是唯一真源）；
/// - 负向习惯 checked=1 表「当日未触发/已规避」，判定函数与正向分叉（§5-10）。
class HabitSub {
  const HabitSub({
    this.id = 0,
    required this.name,
    required this.unit,
    required this.goal,
    this.sort = 0,
  });

  final int id;
  final String name;
  final String unit;
  final double goal;
  final int sort;

  factory HabitSub.fromRow(Map<String, Object?> r) => HabitSub(
    id: r['id'] as int,
    name: r['name'] as String,
    unit: (r['unit'] as String?) ?? '',
    goal: (r['goal'] as num?)?.toDouble() ?? 0,
    sort: (r['sort'] as int?) ?? 0,
  );
}

class Habit {
  const Habit({
    this.id = '',
    required this.name,
    this.icon = 'run',
    this.type = kPos,
    this.cat,
    this.cycle = kDay,
    this.weekDays = const [],
    this.monthTarget,
    this.negLimit = 0,
    this.unit,
    this.goal,
    this.groupRule,
    this.sourceKinds = const ['手动打卡'],
    this.remindAt,
    this.todoId,
    this.todoForm,
    required this.startDate,
    this.streak = 0,
    this.best = 0,
    this.archivedAt,
    this.createdAt = 0,
    this.updatedAt = 0,
    this.deletedAt,
    this.subs = const [],
  });

  static const kPos = 'pos';
  static const kNeg = 'neg';
  static const kDay = 'day';
  static const kWeek = 'week';
  static const kMonth = 'month';
  static const kRuleAll = 'all';
  static const kRuleHalf = 'half';
  static const kRuleAny = 'any';

  final String id;
  final String name;

  /// 线性图标 key（HB_IC 同源，禁 emoji）。
  final String icon;
  final String type;

  /// 引用 habit_dict(kind='cat').name（非外键，改名走事务迁移）。
  final String? cat;
  final String cycle;

  /// cycle=week 的固定打卡日：0=周一 … 6=周日；空=每周任意 1 天。
  final List<int> weekDays;
  final int? monthTarget;

  /// 负向：周期内触发上限（0=一次都不许）。
  final int negLimit;

  /// 记录量单位（引用 habit_dict(kind='unit')）；null=纯布尔打卡。
  final String? unit;
  final double? goal;

  /// all|half|any；null=非组。
  final String? groupRule;

  /// 自动达成源（手动打卡/待办勾选/番茄完成/阅读计时/日程事件）。
  final List<String> sourceKinds;

  /// 'HH:MM' 提醒锚点，不参与达成判定（§5 既有拍板）。
  final String? remindAt;
  final String? todoId;

  /// normal|pomo（L10 关联待办形态）。
  final String? todoForm;

  /// 开始跟踪日 'YYYY-MM-DD'（口径分母起点 §5-1）。
  final String startDate;
  final int streak;
  final int best;
  final int? archivedAt;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;

  /// 组内子项（非组习惯为空表）。
  final List<HabitSub> subs;

  bool get isNeg => type == kNeg;
  bool get isPos => type == kPos;
  bool get isGroup => groupRule != null;
  bool get hasVal => isGroup || (unit != null && unit!.isNotEmpty);
  bool get isArchived => archivedAt != null;

  Habit copyWith({
    String? id,
    String? name,
    String? icon,
    String? type,
    String? cat,
    bool clearCat = false,
    String? cycle,
    List<int>? weekDays,
    int? monthTarget,
    bool clearMonthTarget = false,
    int? negLimit,
    String? unit,
    bool clearUnit = false,
    double? goal,
    bool clearGoal = false,
    String? groupRule,
    List<String>? sourceKinds,
    String? remindAt,
    bool clearRemind = false,
    String? todoId,
    String? todoForm,
    String? startDate,
    int? streak,
    int? best,
    int? archivedAt,
    bool clearArchived = false,
    int? createdAt,
    int? updatedAt,
    List<HabitSub>? subs,
  }) => Habit(
    id: id ?? this.id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    type: type ?? this.type,
    cat: clearCat ? null : (cat ?? this.cat),
    cycle: cycle ?? this.cycle,
    weekDays: weekDays ?? this.weekDays,
    monthTarget: clearMonthTarget ? null : (monthTarget ?? this.monthTarget),
    negLimit: negLimit ?? this.negLimit,
    unit: clearUnit ? null : (unit ?? this.unit),
    goal: clearGoal ? null : (goal ?? this.goal),
    groupRule: groupRule ?? this.groupRule,
    sourceKinds: sourceKinds ?? this.sourceKinds,
    remindAt: clearRemind ? null : (remindAt ?? this.remindAt),
    todoId: todoId ?? this.todoId,
    todoForm: todoForm ?? this.todoForm,
    startDate: startDate ?? this.startDate,
    streak: streak ?? this.streak,
    best: best ?? this.best,
    archivedAt: clearArchived ? null : (archivedAt ?? this.archivedAt),
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    subs: subs ?? this.subs,
  );

  /// 频率展示文案（原型 hbDueOf）。
  static const _wdCn = ['一', '二', '三', '四', '五', '六', '日'];
  String get dueText => switch (cycle) {
    kWeek => '每周 ${weekDays.map((d) => _wdCn[d % 7]).join('、')}',
    kMonth => '每月 ${monthTarget ?? 0} 次',
    _ => '每天',
  };

  Map<String, Object?> toRow() => {
    'id': id.isEmpty ? null : id,
    'name': name,
    'icon': icon,
    'type': type,
    'cat': cat,
    'cycle': cycle,
    'week_days': weekDays.isEmpty ? null : _jsonList(weekDays),
    'month_target': monthTarget,
    'neg_limit': negLimit,
    'unit': (unit == null || unit!.isEmpty) ? null : unit,
    'goal': goal,
    'group_rule': groupRule,
    'source_kinds': _jsonList(sourceKinds),
    'remind_at': remindAt,
    'todo_id': todoId,
    'todo_form': todoForm,
    'start_date': startDate,
    'streak': streak,
    'best': best,
    'archived_at': archivedAt,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'deleted_at': deletedAt,
  };

  factory Habit.fromRow(Map<String, Object?> r) {
    List<int> ints(Object? v) => v == null
        ? const []
        : (jsonDecode(v as String) as List).cast<int>();
    return Habit(
      id: r['id'] as String,
      name: r['name'] as String,
      icon: r['icon'] as String,
      type: r['type'] as String,
      cat: r['cat'] as String?,
      cycle: r['cycle'] as String,
      weekDays: ints(r['week_days']),
      monthTarget: r['month_target'] as int?,
      negLimit: (r['neg_limit'] as int?) ?? 0,
      unit: r['unit'] as String?,
      goal: (r['goal'] as num?)?.toDouble(),
      groupRule: r['group_rule'] as String?,
      sourceKinds: r['source_kinds'] == null
          ? const ['手动打卡']
          : (jsonDecode(r['source_kinds'] as String) as List).cast<String>(),
      remindAt: r['remind_at'] as String?,
      todoId: r['todo_id'] as String?,
      todoForm: r['todo_form'] as String?,
      startDate: r['start_date'] as String,
      streak: (r['streak'] as int?) ?? 0,
      best: (r['best'] as int?) ?? 0,
      archivedAt: r['archived_at'] as int?,
      createdAt: (r['created_at'] as int?) ?? 0,
      updatedAt: (r['updated_at'] as int?) ?? 0,
      deletedAt: r['deleted_at'] as int?,
    );
  }
}

String _jsonList(List<Object> l) => jsonEncode(l);
