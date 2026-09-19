import 'package:flutter/material.dart';

/// 日程状态两态流（需求 V1.12）：计划中 → 进行中 → 已完成。
enum EventStatus { planning, active, done }

/// 日程事件（对应 events 表；时间存 epoch 毫秒，日界线自然日 00:00，ADR D13）。
class CalEvent {
  const CalEvent({
    this.id,
    required this.title,
    required this.start,
    this.end,
    this.allDay = false,
    this.colorIdx = 0,
    this.status = EventStatus.planning,
    this.durationMin,
  });

  final int? id;
  final String title;
  final DateTime start;
  final DateTime? end;
  final bool allDay;

  /// 色标索引 0-3（brand/violet/mint/sun，0 随主题 accent）。
  final int colorIdx;
  final EventStatus status;

  /// 完成后回填的实际耗时（L1 联动）。
  final int? durationMin;

  bool get crossDay =>
      end != null &&
      (end!.year != start.year ||
          end!.month != start.month ||
          end!.day != start.day);

  Color colorOf(Color accent) => [
        accent,
        const Color(0xFF8B5CF6),
        const Color(0xFF2DD4BF),
        const Color(0xFFF59E0B),
      ][colorIdx % 4];

  static Color palette(Color accent, int idx) =>
      [accent, const Color(0xFF8B5CF6), const Color(0xFF2DD4BF), const Color(0xFFF59E0B)][idx % 4];

  CalEvent copyWith({
    int? id,
    String? title,
    DateTime? start,
    DateTime? end,
    bool? allDay,
    int? colorIdx,
    EventStatus? status,
    int? durationMin,
  }) =>
      CalEvent(
        id: id ?? this.id,
        title: title ?? this.title,
        start: start ?? this.start,
        end: end ?? this.end,
        allDay: allDay ?? this.allDay,
        colorIdx: colorIdx ?? this.colorIdx,
        status: status ?? this.status,
        durationMin: durationMin ?? this.durationMin,
      );

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'title': title,
        'start_at': start.millisecondsSinceEpoch,
        'end_at': end?.millisecondsSinceEpoch,
        'all_day': allDay ? 1 : 0,
        'color_tag': colorIdx.toString(), // 列为 TEXT，存数字串
        'status': status.index,
        'cross_day': crossDay ? 1 : 0,
        'duration_min': durationMin,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };

  factory CalEvent.fromRow(Map<String, Object?> r) => CalEvent(
        id: r['id'] as int,
        title: r['title'] as String,
        start: DateTime.fromMillisecondsSinceEpoch(r['start_at'] as int),
        end: r['end_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['end_at'] as int),
        allDay: (r['all_day'] as int? ?? 0) == 1,
        colorIdx: int.tryParse('${r['color_tag'] ?? 0}') ?? 0,
        status: EventStatus.values[(r['status'] as int? ?? 0).clamp(0, 2)],
        durationMin: r['duration_min'] as int?,
      );
}
