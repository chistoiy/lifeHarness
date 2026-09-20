import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers.dart';
import '../data/category_dao.dart';
import '../data/event_dao.dart';
import '../data/time_block_dao.dart';
import '../domain/cal_event.dart';
import '../domain/category.dart';
import '../domain/event_repository.dart';
import '../domain/time_block.dart';

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  final db = AppDatabase.instance.db;
  // tbDao：■结束时把实际耗时区间回填为时间块（L1→L4，格子视图可见）。
  return EventRepository(EventDao(db), ref.watch(eventBusProvider), tbDao: TimeBlockDao(db));
});

final timeBlockDaoProvider = Provider<TimeBlockDao>(
    (ref) => TimeBlockDao(AppDatabase.instance.db));

/// 两级分类（V1.19.1 · 全局唯一分类源）。
final categoryDaoProvider =
    Provider<CategoryDao>((ref) => CategoryDao(AppDatabase.instance.db));

final categoriesProvider = FutureProvider<List<Category>>(
    (ref) => ref.watch(categoryDaoProvider).list());

/// 分类名→颜色（次级继承父级；「工作」由 blockColor 特判随主题 accent）。
final catColorsByNameProvider = Provider<Map<String, Color>>((ref) {
  final cats = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
  final byId = {for (final c in cats) c.id: c};
  final m = <String, Color>{};
  for (final c in cats) {
    final src = c.isPrimary ? c : (byId[c.parentId] ?? c);
    m[c.name] = src.colorHex == null ? const Color(0xFF94A3B8) : src.color(const Color(0xFF94A3B8));
  }
  return m;
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

/// 视图模式（V1.19 · 四视图）：axis=时间轴 block=格子时间块 day=小时日板 week=7×24。
final calViewModeProvider = StateProvider<String>((ref) => 'block');

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

/// V1.27 C3：月内有手动标记块的日集合（月历圆点=事件/块任一存在）。
final monthBlockDaysProvider =
    FutureProvider.family<Set<int>, (int, int)>((ref, ym) {
  return ref.watch(timeBlockDaoProvider).daysWithBlocks(ym.$1, ym.$2);
});
