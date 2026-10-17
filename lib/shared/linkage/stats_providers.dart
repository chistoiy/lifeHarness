import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../features/calendar/presentation/calendar_providers.dart';
import '../../features/inbox/presentation/inbox_providers.dart';
// UIUX批（2026-10-12）：dashMoodOfTodayProvider 要在本文件作用域内用到这三者
//（下方 export 只对导入方可见，不进本文件命名空间）。
import '../../features/journal/presentation/journal_providers.dart'
    show journalRepositoryProvider, journalsProvider;
import '../../features/journal/domain/journal_entry.dart' show JournalEntry;
import '../../features/read/presentation/read_providers.dart'
    show booksProvider;
import '../../features/todo/presentation/todo_providers.dart';

// 跨模块聚合出口：仪表盘/设置等只 import 本文件，不直接 import 其他 feature。
export '../../features/todo/presentation/todo_providers.dart' show todosProvider, todoRepositoryProvider, activePomoProvider, PomoSession;
export '../../features/todo/domain/todo.dart' show Todo, Quadrant;
export '../../features/todo/domain/todo_insights.dart' show energyCaption;
export '../../features/calendar/presentation/calendar_providers.dart' show dayBlocksProvider, monthBlockDaysProvider;
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

/// 收集箱未整理条数（routed_to 为空；watch 列表源，分流后自动重算）。
final inboxPendingCountProvider = FutureProvider<int>((ref) async {
  ref.watch(inboxItemsProvider);
  final db = AppDatabase.instance.db;
  final rows = await db
      .rawQuery('SELECT COUNT(*) c FROM inbox_items WHERE routed_to IS NULL');
  return (rows.first['c'] as int?) ?? 0;
});

/// 连续记录天数（todos/journal/time_blocks 任一有活动的自然日去重计数，骨架近似）。
/// B10：events 行已并入 time_blocks 并删行退役，活动面改算块表。
final streakDaysProvider = FutureProvider<int>((ref) async {
  ref.watch(todosProvider);
  ref.watch(dayBlocksProvider(DateTime.now()));
  final db = AppDatabase.instance.db;
  final rows = await db.rawQuery('''
    SELECT COUNT(DISTINCT (created_at / 86400000)) c FROM (
      -- V1.61：删进回收站的待办不算「当天有过活动」（在册口径，与物品/笔记同源）
      SELECT created_at FROM todos WHERE deleted_at IS NULL
      UNION ALL SELECT created_at FROM journal_entries
      UNION ALL SELECT created_at FROM time_blocks
    )
  ''');
  return (rows.first['c'] as int?) ?? 0;
});

/// 今天页心情回填（UIUX批 2026-10-12）：当天最新带心情篇的 mood（1..7；无＝null）。
/// 此前仪表盘 `_mood` 是纯内存态，切栏销毁子路由即丢——DB 里当天明明已打卡，
/// 回页却显示未选，再点会静默覆盖。现 watch journalsProvider：打卡落库与
/// 日记编辑页改心情后自动重算（listByDay 新→旧，取首个非空 mood＝最新一次）。
final dashMoodOfTodayProvider = FutureProvider<int?>((ref) async {
  ref.watch(journalsProvider);
  final entries = await ref.watch(journalRepositoryProvider)
      .listByDay(JournalEntry.dayStart(DateTime.now()));
  for (final e in entries) {
    if (e.mood != null) return e.mood;
  }
  return null;
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
