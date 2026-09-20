import 'package:flutter/material.dart';

/// 时间块分类名兜底（categories 表未命中时）。
const String kCatOther = '其他';

/// 格子时间块标记（time_blocks 表；分钟 0-1440；V1.19.1 起引用两级分类表）。
class TimeBlock {
  const TimeBlock({
    this.id,
    required this.day,
    required this.startMin,
    required this.endMin,
    this.catId,
    this.catName = kCatOther,
    this.note,
    this.source = 'mark',
    this.eventId,
  });

  final int? id;
  final DateTime day; // 当日 00:00
  final int startMin;
  final int endMin;

  /// 两级分类表引用（V1.19.1）；category TEXT 列继续存名称做展示兜底。
  final int? catId;
  final String catName;
  final String? note;

  /// mark=手动标记；event=日程两态流回填（L1→L4）。
  final String source;
  final int? eventId;

  bool covers(int minute) => minute >= startMin && minute < endMin;

  TimeBlock copyWith({int? id, int? startMin, int? endMin, String? note}) => TimeBlock(
        id: id ?? this.id,
        day: day,
        startMin: startMin ?? this.startMin,
        endMin: endMin ?? this.endMin,
        catId: catId,
        catName: catName,
        note: note ?? this.note,
        source: source,
        eventId: eventId,
      );

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        // day 列规范=当日 00:00（ADR D13 日界线），入库存截断值。
        'day': DateTime(day.year, day.month, day.day).millisecondsSinceEpoch,
        'start_min': startMin,
        'end_min': endMin,
        'category': catName,
        'note': note,
        'source': source,
        'event_id': eventId,
        'cat_id': catId,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };

  factory TimeBlock.fromRow(Map<String, Object?> r) => TimeBlock(
        id: r['id'] as int,
        day: DateTime.fromMillisecondsSinceEpoch(r['day'] as int),
        startMin: r['start_min'] as int,
        endMin: r['end_min'] as int,
        catId: r['cat_id'] as int?,
        catName: (r['category'] as String?) ?? kCatOther,
        note: r['note'] as String?,
        source: (r['source'] as String?) ?? 'mark',
        eventId: r['event_id'] as int?,
      );
}

/// 分类取色：byName 由 categoriesProvider 构建（次级继承父级色）；工作随主题 accent。
Color blockColor(TimeBlock b, Map<String, Color> byName, Color accent) {
  if (b.catName == '工作') return accent;
  return byName[b.catName] ?? const Color(0xFF94A3B8);
}
