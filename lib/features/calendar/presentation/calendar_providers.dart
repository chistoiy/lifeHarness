import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart' show Database;

import '../../../core/database/app_database.dart';
import '../../../core/providers.dart';
import '../data/category_dao.dart';
import '../data/time_block_dao.dart';
import '../domain/category.dart';
import '../domain/time_block.dart';

final timeBlockDaoProvider = Provider<TimeBlockDao>(
    (ref) => TimeBlockDao(AppDatabase.instance.db));

/// B10 搬移服务的 db 供给口（独立 provider＝测试可注入 ffi 内存库，
/// 不触 AppDatabase 单例；CalendarPage init 经此触发一次性并入）。
final legacyEventMergeDbProvider = Provider<Database>(
    (ref) => AppDatabase.instance.db);

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

/// 秒级心跳（计时中块耗时刷新；无计时中块时页面可不 watch）。
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

/// 月历展开/收起（C2/B9 冻结口径：**首次默认展开**；用户手动切换后持久化，
/// 跨会话记住；与视图档**解耦**——切档不再改写展开态，见 calendar_page 的 _setMonthExpanded）。
/// 种子读设置键 `lh.cal_month_expanded`（SettingsRepository 四处同步之一）。
final monthExpandedProvider = StateProvider<bool>(
    (ref) => ref.read(settingsControllerProvider).calMonthExpanded);

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

/// V1.52：全局唯一「计时中」块（轴视图卡片/结束计时按钮/账本 hero 共用）。
final timingBlockProvider =
    FutureProvider<TimeBlock?>((ref) => ref.watch(timeBlockDaoProvider).activeTiming());

/// V1.52：月内有计时中块的日（月历红脉冲点，优先级最高）。
final monthTimingDaysProvider =
    FutureProvider.family<Set<int>, (int, int)>((ref, ym) {
  return ref.watch(timeBlockDaoProvider).daysWithTiming(ym.$1, ym.$2);
});

/// V1.52 时间账本：区间内全部时间块（含计时中，按已耗时计入）。
final blocksInRangeProvider =
    FutureProvider.family<List<TimeBlock>, (DateTime, DateTime)>((ref, r) {
  return ref.watch(timeBlockDaoProvider).listInRange(r.$1, r.$2);
});

/// V1.46⑤ 周视图格子并排分段：≤3 项按份数等分；>3 项前 3 段并排、
/// 第 4 个起并入末段（[WeekCellSegment.item]＝该段可点项，末段代表第 4 项）。
class WeekCellSegment<T> {
  WeekCellSegment(this.item, [List<T>? rest]) : rest = rest ?? const [];
  final T item;

  /// 并入本段的第 5 个及以后各项（仅末段且段内 ≥2 项时非空）。
  final List<T> rest;

  /// 「+N」小徽标文本：本段共含几项（≥2 项才显，单项无徽标）。
  String get badgeText => rest.isEmpty ? '' : '+${rest.length + 1}';
}

/// V1.46⑤ 并排分段纯函数（items＝该小时格命中的事件/时间块，顺序即分段顺序）。
List<WeekCellSegment<T>> weekCellSegments<T>(List<T> items) {
  if (items.length <= 3) {
    return [for (final it in items) WeekCellSegment<T>(it)];
  }
  return [
    for (final it in items.take(3)) WeekCellSegment<T>(it),
    WeekCellSegment<T>(items[3], items.sublist(4)),
  ];
}
