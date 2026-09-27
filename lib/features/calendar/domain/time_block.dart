import 'package:flutter/material.dart';

/// 时间块分类名兜底（categories 表未命中时）。
const String kCatOther = '其他';

/// 块来源：手动标记 mark / 日程回填 event / **计时中 timing**（V1.52 单一计时态）。
const String kSrcMark = 'mark';
const String kSrcEvent = 'event';
const String kSrcTiming = 'timing';

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

  /// mark=手动标记；event=日程两态流回填（L1→L4）；timing=计时中（V1.52）。
  final String source;
  final int? eventId;

  /// V1.52：计时中块——结束时间随当前时刻推进，直到「■ 结束计时」或被后续事件收口。
  bool get isTiming => source == kSrcTiming;

  /// 有效结束分钟：计时中=此刻（不早于起始，封顶 1440），其余=库存值。
  int effEnd([DateTime? now]) {
    if (!isTiming) return endMin;
    final n = now ?? DateTime.now();
    final nm = n.hour * 60 + n.minute;
    return nm.clamp(startMin, 1440);
  }

  /// 有效耗时分钟（跨天块由调用方按段计）。
  int durationMin([DateTime? now]) => (effEnd(now) - startMin).clamp(0, 1440);

  bool covers(int minute) => minute >= startMin && minute < effEnd();

  TimeBlock copyWith(
          {int? id,
          DateTime? day,
          int? startMin,
          int? endMin,
          int? catId,
          String? catName,
          String? note,
          String? source,
          int? eventId}) =>
      TimeBlock(
        id: id ?? this.id,
        day: day ?? this.day,
        startMin: startMin ?? this.startMin,
        endMin: endMin ?? this.endMin,
        catId: catId ?? this.catId,
        catName: catName ?? this.catName,
        note: note ?? this.note,
        source: source ?? this.source,
        eventId: eventId ?? this.eventId,
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
