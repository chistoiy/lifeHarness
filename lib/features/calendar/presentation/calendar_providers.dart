import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers.dart';
import '../data/event_dao.dart';
import '../domain/cal_event.dart';
import '../domain/event_repository.dart';

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  return EventRepository(EventDao(AppDatabase.instance.db), ref.watch(eventBusProvider));
});

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
