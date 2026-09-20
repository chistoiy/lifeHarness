import '../../../core/host/event_bus.dart';
import '../../../shared/linkage/linkage_events.dart';
import '../data/event_dao.dart';
import '../data/time_block_dao.dart';
import '../domain/cal_event.dart';
import 'time_block.dart';

/// 冲突对（同区间重叠的两条计划中日程）。
class EventConflict {
  const EventConflict(this.a, this.b, this.overlapMin);
  final CalEvent a;
  final CalEvent b;
  final int overlapMin;
}

/// 日程仓库：两态流（▶开始/■结束 + 耗时回填 L1/L4）与冲突检测。
class EventRepository {
  EventRepository(this._dao, this._bus, {TimeBlockDao? tbDao}) : _tbDao = tbDao;

  final EventDao _dao;
  final EventBus _bus;
  final TimeBlockDao? _tbDao;

  Future<List<CalEvent>> listAll() => _dao.listAll();

  Future<CalEvent?> activeEvent() => _dao.activeOne();

  Future<CalEvent> create(CalEvent e) async {
    final saved = await _dao.insert(e);
    _bus.publish(RecordAddedEvent('event', saved.id!, DateTime.now().millisecondsSinceEpoch));
    return saved;
  }

  Future<void> update(CalEvent e) => _dao.update(e);

  Future<void> remove(CalEvent e) => _dao.remove(e.id!);

  /// ▶ 现在就开始：同一时刻仅允许一个进行中（原型 liveEv 单值约束）。
  Future<CalEvent> startNow(CalEvent draft) async {
    if (await _dao.activeOne() != null) {
      throw StateError('已有进行中的事项，请先结束');
    }
    final now = DateTime.now();
    final started = draft.copyWith(
      start: now,
      end: now.add(const Duration(hours: 1)),
      status: EventStatus.active,
    );
    final saved = await _dao.insert(started);
    _bus.publish(TimeTrackingEvent(saved.id!, true, now.millisecondsSinceEpoch));
    return saved;
  }

  /// ■ 结束：实际耗时回填（L1 排程→执行→回填 · L4 时间账本）。
  Future<CalEvent?> endActive() async {
    final active = await _dao.activeOne();
    if (active == null) return null;
    final now = DateTime.now();
    final dur = now.difference(active.start).inMinutes.clamp(1, 1 << 30);
    await _dao.setStatus(active.id!, EventStatus.done, durationMin: dur, endAt: now);
    // L4：回填为格子时间块（工作分类，原型 endNow 行为），覆盖同区间旧手动标记。
    final tb = _tbDao;
    if (tb != null && active.id != null) {
      final day0 = DateTime(active.start.year, active.start.month, active.start.day);
      final sMin = active.start.hour * 60 + active.start.minute;
      final eMin = (now.difference(day0).inMinutes).clamp(sMin + 1, 1440);
      await tb.removeOverlapping(day0, sMin, eMin);
      await tb.insert(TimeBlock(
        day: day0,
        startMin: sMin,
        endMin: eMin,
        catId: 1,
        catName: '工作',
        note: active.title,
        source: 'event',
        eventId: active.id,
      ));
    }
    _bus.publish(TimeTrackingEvent(active.id!, false, now.millisecondsSinceEpoch));
    return active.copyWith(status: EventStatus.done, durationMin: dur, end: now);
  }

  /// 冲突检测：非全天、有结束时间的事件两两区间重叠（按天分组）。
  static List<EventConflict> conflictsOf(List<CalEvent> events) {
    final out = <EventConflict>[];
    final timed = events
        .where((e) => !e.allDay && e.end != null && e.status != EventStatus.done)
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    for (var i = 0; i < timed.length; i++) {
      for (var j = i + 1; j < timed.length; j++) {
        final a = timed[i], b = timed[j];
        final overlapStart = a.start.isAfter(b.start) ? a.start : b.start;
        final overlapEnd = a.end!.isBefore(b.end!) ? a.end! : b.end!;
        if (overlapEnd.isAfter(overlapStart)) {
          out.add(EventConflict(a, b, overlapEnd.difference(overlapStart).inMinutes));
        }
      }
    }
    return out;
  }
}
