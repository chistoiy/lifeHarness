import 'package:flutter/material.dart';

/// 时间块分类（原型 CATS 八类；工作色随主题 accent）。
enum BlockCat {
  work('工作', Color(0xFF6366F1)),
  study('学习', Color(0xFF8B5CF6)),
  sport('运动', Color(0xFFF59E0B)),
  food('餐饮', Color(0xFFFDBA74)),
  fun('娱乐', Color(0xFFA855F7)),
  sleep('睡眠', Color(0xFF3730A3)),
  clean('清洁', Color(0xFF2DD4BF)),
  other('其他', Color(0xFF94A3B8));

  const BlockCat(this.label, this.color);
  final String label;
  final Color color;

  Color colorOf(Color accent) => this == work ? accent : color;

  static BlockCat of(String? name) => BlockCat.values.firstWhere(
        (c) => c.label == name,
        orElse: () => BlockCat.other,
      );
}

/// 格子时间块标记（time_blocks 表；分钟 0-1440）。
class TimeBlock {
  const TimeBlock({
    this.id,
    required this.day,
    required this.startMin,
    required this.endMin,
    this.category = BlockCat.other,
    this.note,
    this.source = 'mark',
    this.eventId,
  });

  final int? id;
  final DateTime day; // 当日 00:00
  final int startMin;
  final int endMin;
  final BlockCat category;
  final String? note;

  /// mark=手动标记；event=日程两态流回填（L1→L4）。
  final String source;
  final int? eventId;

  bool covers(int minute) => minute >= startMin && minute < endMin;

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'day': day.millisecondsSinceEpoch,
        'start_min': startMin,
        'end_min': endMin,
        'category': category.label,
        'note': note,
        'source': source,
        'event_id': eventId,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };

  factory TimeBlock.fromRow(Map<String, Object?> r) => TimeBlock(
        id: r['id'] as int,
        day: DateTime.fromMillisecondsSinceEpoch(r['day'] as int),
        startMin: r['start_min'] as int,
        endMin: r['end_min'] as int,
        category: BlockCat.of(r['category'] as String?),
        note: r['note'] as String?,
        source: (r['source'] as String?) ?? 'mark',
        eventId: r['event_id'] as int?,
      );
}
