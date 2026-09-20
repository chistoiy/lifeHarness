import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../features/calendar/presentation/calendar_providers.dart';
import '../../features/todo/presentation/todo_providers.dart';

// 跨模块聚合出口：仪表盘/设置等只 import 本文件，不直接 import 其他 feature。
export '../../features/todo/presentation/todo_providers.dart' show todosProvider, todoRepositoryProvider, activePomoProvider, PomoSession;
export '../../features/todo/domain/todo.dart' show Todo;
export '../../features/calendar/presentation/calendar_providers.dart' show dayBlocksProvider;
export '../../features/calendar/presentation/calendar_providers.dart' show eventsProvider;

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

/// 收集箱未整理条数（routed_to 为空）。
final inboxPendingCountProvider = FutureProvider<int>((ref) async {
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
      SELECT created_at FROM todos
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
