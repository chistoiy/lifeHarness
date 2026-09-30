import 'package:flutter/material.dart';

/// 四象限枚举（文案与配色对齐高保真原型 D.quads：Q1 rose / Q2 brand(随主题) / Q3 sun / Q4 slate）。
enum Quadrant {
  q1(1, '重要且紧急', '立即做', Color(0xFFF43F5E)),
  q2(2, '重要不紧急', '计划做', Color(0xFF6366F1)),
  q3(3, '紧急不重要', '快速处理', Color(0xFFF59E0B)),
  q4(4, '不紧急不重要', '考虑淘汰', Color(0xFF94A3B8));

  const Quadrant(this.value, this.label, this.hint, this.color);

  final int value;
  final String label;
  final String hint;
  final Color color;

  /// Q2 使用品牌强调色（原型 bg-brand-500 = var(--accent)，随主题令牌变化）。
  Color colorOf(Color accent) => this == Quadrant.q2 ? accent : color;

  static Quadrant of(int v) =>
      Quadrant.values.firstWhere((q) => q.value == v, orElse: () => Quadrant.q4);
}

/// 待办任务模型（对应 todos 表；时间存 epoch 毫秒）。
class Todo {
  const Todo({
    this.id,
    required this.title,
    this.note,
    this.quadrant = Quadrant.q4,
    this.dueAt,
    this.remindAt,
    this.tag,
    this.done = false,
    this.timeMode,
    this.startMin,
    this.endMin,
    this.pomoMode,
    this.pomoMin,
    this.dropped = false,
    this.colorIdx,
    this.grp,
    this.habitId,
    this.linkCat,
    this.sortOrder = 0,
    this.deletedAt,
    this.createdAt,
    this.updatedAt,
  });

  final int? id;
  final String title;
  final String? note;
  final Quadrant quadrant;
  final DateTime? dueAt;
  final DateTime? remindAt;
  final String? tag;
  final bool done;

  /// V1.19~V1.25 扩展：时间三态 none(=null)/point/range/all（分钟 0-1440）。
  final String? timeMode;
  final int? startMin;
  final int? endMin;

  /// 番茄待办：up=正计时 / down=倒计时（pomoMin 分钟）；null=常规待办。
  final String? pomoMode;
  final int? pomoMin;

  /// 放弃态（状态三态：未完成/完成/放弃）。
  final bool dropped;

  /// 颜色索引（体现在时间模块，命名色板共用）与分组。
  final int? colorIdx;
  final String? grp;

  /// 绑定习惯 id（V1.25 · 习惯模块落地后启用）与关联计时分类 id（L4）。
  final int? habitId;
  final int? linkCat;

  /// 长按拖拽排序位（V1.27 T6；默认 0=未参与手动排序，列表按到期/更新智能序）。
  final int sortOrder;

  bool get isPomo => pomoMode != null;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// V1.57 E 批 · 待办垃圾箱：软删时刻（null=在册；非空=在垃圾箱，保留期内可恢复）。
  final DateTime? deletedAt;

  bool get trashed => deletedAt != null;

  /// 逾期=过了截止日的**当天**（自然日粒度，与原型 dueLabel「今天≠逾期」一致）。
  /// due_at 携带的隐藏时刻（默认 18:00）只用于「提前1小时」类提醒锚点，不参与逾期判定；
  /// 计划执行时间点（start_min）是独立字段，同样不参与。
  bool get overdue {
    if (done || dueAt == null) return false;
    final now = DateTime.now();
    final dueDay = DateTime(dueAt!.year, dueAt!.month, dueAt!.day);
    return dueDay.isBefore(DateTime(now.year, now.month, now.day));
  }

  Todo copyWith({
    int? id,
    String? title,
    String? note,
    Quadrant? quadrant,
    DateTime? dueAt,
    DateTime? remindAt,
    String? tag,
    bool? done,
    String? timeMode,
    int? startMin,
    int? endMin,
    String? pomoMode,
    int? pomoMin,
    bool? dropped,
    int? colorIdx,
    String? grp,
    int? habitId,
    int? linkCat,
    int? sortOrder,
    DateTime? deletedAt,
  }) =>
      Todo(
        id: id ?? this.id,
        title: title ?? this.title,
        note: note ?? this.note,
        quadrant: quadrant ?? this.quadrant,
        dueAt: dueAt ?? this.dueAt,
        remindAt: remindAt ?? this.remindAt,
        tag: tag ?? this.tag,
        done: done ?? this.done,
        timeMode: timeMode ?? this.timeMode,
        startMin: startMin ?? this.startMin,
        endMin: endMin ?? this.endMin,
        pomoMode: pomoMode ?? this.pomoMode,
        pomoMin: pomoMin ?? this.pomoMin,
        dropped: dropped ?? this.dropped,
        colorIdx: colorIdx ?? this.colorIdx,
        grp: grp ?? this.grp,
        habitId: habitId ?? this.habitId,
        linkCat: linkCat ?? this.linkCat,
        sortOrder: sortOrder ?? this.sortOrder,
        deletedAt: deletedAt ?? this.deletedAt,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'title': title,
        'note': note,
        'quadrant': quadrant.value,
        'due_at': dueAt?.millisecondsSinceEpoch,
        'remind_at': remindAt?.millisecondsSinceEpoch,
        'tag': tag,
        'done': done ? 1 : 0,
        'time_mode': timeMode,
        'start_min': startMin,
        'end_min': endMin,
        'pomo_mode': pomoMode,
        'pomo_min': pomoMin,
        'dropped': dropped ? 1 : 0,
        'color': colorIdx,
        'grp': grp,
        'habit_id': habitId,
        'link_cat': linkCat,
        'sort_order': sortOrder,
        'deleted_at': deletedAt?.millisecondsSinceEpoch,
        'created_at': (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
        'updated_at': (updatedAt ?? DateTime.now()).millisecondsSinceEpoch,
      };

  factory Todo.fromRow(Map<String, Object?> r) => Todo(
        id: r['id'] as int,
        title: r['title'] as String,
        note: r['note'] as String?,
        quadrant: Quadrant.of((r['quadrant'] as int?) ?? 4),
        dueAt: r['due_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['due_at'] as int),
        remindAt: r['remind_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['remind_at'] as int),
        tag: r['tag'] as String?,
        done: (r['done'] as int? ?? 0) == 1,
        timeMode: r['time_mode'] as String?,
        startMin: r['start_min'] as int?,
        endMin: r['end_min'] as int?,
        pomoMode: r['pomo_mode'] as String?,
        pomoMin: r['pomo_min'] as int?,
        dropped: (r['dropped'] as int? ?? 0) == 1,
        colorIdx: r['color'] as int?,
        grp: r['grp'] as String?,
        habitId: r['habit_id'] as int?,
        linkCat: r['link_cat'] as int?,
        sortOrder: (r['sort_order'] as int?) ?? 0,
        deletedAt: r['deleted_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['deleted_at'] as int),
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
      );
}
