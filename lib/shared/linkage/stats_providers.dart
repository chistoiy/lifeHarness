import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../features/calendar/presentation/calendar_providers.dart';
import '../../features/inbox/presentation/inbox_providers.dart';
import '../../features/read/presentation/read_providers.dart'
    show booksProvider;
import '../../features/todo/presentation/todo_providers.dart';

// 跨模块聚合出口：仪表盘/设置等只 import 本文件，不直接 import 其他 feature。
export '../../features/todo/presentation/todo_providers.dart' show todosProvider, todoRepositoryProvider, activePomoProvider, PomoSession;
export '../../features/todo/domain/todo.dart' show Todo, Quadrant;
export '../../features/todo/domain/todo_insights.dart' show energyCaption;
export '../../features/calendar/presentation/calendar_providers.dart' show dayBlocksProvider;
export '../../features/calendar/presentation/calendar_providers.dart' show eventsProvider;
export '../../features/calendar/domain/cal_event.dart' show CalEvent, EventStatus;
export '../../features/calendar/domain/time_block.dart' show TimeBlock;
export '../../features/calendar/presentation/calendar_providers.dart' show categoriesProvider;
export '../../features/calendar/domain/category.dart' show Category;
export '../../features/journal/presentation/journal_providers.dart' show journalRepositoryProvider, journalsProvider, noteDaoProvider;
export '../../features/journal/domain/journal_entry.dart' show JournalEntry, kJournalMoods, moodEmoji, moodLabel;
export '../../features/journal/domain/note.dart' show Note;
export '../../features/inbox/presentation/inbox_providers.dart' show inboxItemsProvider;
// 批5 收集箱 → 阅读摘录分流（L6）：只经本文件透出，不直连 read feature。
export '../../features/read/presentation/read_providers.dart' show readRepositoryProvider, readTickProvider, booksProvider;
export '../../features/read/domain/book_quote.dart' show BookQuote;
// V1.42 批4 联动收口（L10）：仪表盘「最近的日子」倒数卡 + hero 持有成本块，
// days/items 数据与实算引擎只经本文件透出（R1）。
export '../../features/days/presentation/days_providers.dart' show daysDataProvider, daysRepositoryProvider, daysClockProvider;
export '../../features/days/presentation/days_kit.dart' show dayGradientOf, dayIconOf, kDaysMuted;
export '../../features/days/domain/day_models.dart' show DayEntry, DaysData;
export '../../features/days/domain/day_calc.dart' show dashboardUpcoming, countdownDays;
export '../../features/items/presentation/items_providers.dart' show itemsDataProvider, itemsRepositoryProvider, itemsClockProvider;
export '../../features/items/domain/item_models.dart' show ItemProfile, ItemsData;
export '../../features/items/domain/item_calc.dart' show totalDailyCost, fmtY;

/// 跨模块聚合查询（shared/linkage 唯一聚合层；直查 DB，M1 起服务化）。
/// 各 provider watch 对应源列表，源变更后自动重算。

/// 今日日程数（start_at 落在今日）。
final todayEventCountProvider = FutureProvider<int>((ref) async {
  ref.watch(eventsProvider);
  final db = AppDatabase.instance.db;
  final now = DateTime.now();
  final dayStart = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
  final dayEnd = dayStart + 86400000;
  final rows = await db.rawQuery(
      'SELECT COUNT(*) c FROM events WHERE start_at >= ? AND start_at < ?',
      [dayStart, dayEnd]);
  return (rows.first['c'] as int?) ?? 0;
});

/// 收集箱未整理条数（routed_to 为空；watch 列表源，分流后自动重算）。
final inboxPendingCountProvider = FutureProvider<int>((ref) async {
  ref.watch(inboxItemsProvider);
  final db = AppDatabase.instance.db;
  final rows = await db
      .rawQuery('SELECT COUNT(*) c FROM inbox_items WHERE routed_to IS NULL');
  return (rows.first['c'] as int?) ?? 0;
});

/// 连续记录天数（todos/journal/events 任一有活动的自然日去重计数，骨架近似）。
final streakDaysProvider = FutureProvider<int>((ref) async {
  ref.watch(todosProvider);
  ref.watch(eventsProvider);
  final db = AppDatabase.instance.db;
  final rows = await db.rawQuery('''
    SELECT COUNT(DISTINCT (created_at / 86400000)) c FROM (
      -- V1.61：删进回收站的待办不算「当天有过活动」（在册口径，与物品/笔记同源）
      SELECT created_at FROM todos WHERE deleted_at IS NULL
      UNION ALL SELECT created_at FROM journal_entries
      UNION ALL SELECT created_at FROM events
    )
  ''');
  return (rows.first['c'] as int?) ?? 0;
});

/// 已完成任务总数（我的页统计宫格）。
final doneTaskCountProvider = FutureProvider<int>((ref) async {
  ref.watch(todosProvider);
  final db = AppDatabase.instance.db;
  final rows =
      await db.rawQuery('SELECT COUNT(*) c FROM todos WHERE done = 1');
  return (rows.first['c'] as int?) ?? 0;
});

/// 在册书籍数（R14-13·我的页统计宫格第三格）。
/// 走 booksProvider 而不是直查库：加书/删书后随阅读侧心跳自动重算，
/// 且 widget 测试可用 `readRepositoryProvider` 注入内存库（不依赖 AppDatabase 单例）。
/// 轮7 口径修正：booksProvider 含软删行（垃圾箱依赖），「在册」必须剔除
/// deleted_at 非空者——此前把垃圾箱里的书也计进（真机 24 vs 书架 6）。
final shelfBookCountProvider = FutureProvider<int>((ref) async {
  final books = await ref.watch(booksProvider.future);
  return books.where((b) => !b.isDeleted).length;
});
