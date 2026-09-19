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
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get overdue =>
      !done && dueAt != null && dueAt!.isBefore(DateTime.now());

  Todo copyWith({
    int? id,
    String? title,
    String? note,
    Quadrant? quadrant,
    DateTime? dueAt,
    DateTime? remindAt,
    String? tag,
    bool? done,
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
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
      );
}
