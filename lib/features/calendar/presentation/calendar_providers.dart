import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers.dart';
import '../data/event_dao.dart';
import '../data/time_block_dao.dart';
import '../domain/cal_event.dart';
import '../domain/event_repository.dart';
import '../domain/time_block.dart';

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  final db = AppDatabase.instance.db;
  // tbDao：■结束时把实际耗时区间回填为时间块（L1→L4，格子视图可见）。
  return EventRepository(EventDao(db), ref.watch(eventBusProvider), tbDao: TimeBlockDao(db));
});

final timeBlockDaoProvider = Provider<TimeBlockDao>(
    (ref) => TimeBlockDao(AppDatabase.instance.db));

/// 全部日程（变更后 invalidate）。
final eventsProvider = FutureProvider<List<CalEvent>>((ref) {
  return ref.watch(eventRepositoryProvider).listAll();
});

/// 当前进行中事项（驱动悬浮计时条与时间轴脉冲卡）。
final activeEventProvider = FutureProvider<CalEvent?>((ref) {
  return ref.watch(eventRepositoryProvider).activeEvent();
});

/// 秒级心跳（进行中耗时/计时条刷新；无进行中事项时页面可不 watch）。
final calendarTickerProvider = StreamProvider<DateTime>((ref) {
  final t = Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now());
  final sub = t.listen((_) {});
  ref.onDispose(sub.cancel);
  return t;
});

/// 选中日期（真实日历）。
final calSelectedProvider = StateProvider<DateTime>((ref) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
});

/// 视图模式：day/week/month。
final calViewModeProvider = StateProvider<String>((ref) => 'day');

/// 月历展开/收起（智能折叠：滚动或点内容区收起为周行）。
final monthExpandedProvider = StateProvider<bool>((ref) => true);

/// 日视图子模式：line=时间轴 / grid=格子·时间块（需求 V1.4）。
final dayModeProvider = StateProvider<String>((ref) => 'line');

/// 格子粒度（分钟，1/5/10/15/30/60，默认 15）。
final granularityProvider = StateProvider<int>((ref) => 15);

/// 某日时间块标记（格子视图数据源，L4 时间账本）。
final dayBlocksProvider = FutureProvider.family<List<TimeBlock>, DateTime>((ref, day) {
  return ref.watch(timeBlockDaoProvider).listByDay(day);
});
