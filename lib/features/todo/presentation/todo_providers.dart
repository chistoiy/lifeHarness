import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers.dart';
import '../data/todo_dao.dart';
import '../domain/todo.dart';
import '../domain/todo_repository.dart';

final todoRepositoryProvider = Provider<TodoRepository>((ref) {
  return TodoRepository(TodoDao(AppDatabase.instance.db), ref.watch(eventBusProvider));
});

/// 全部待办（变更后 invalidate 刷新）。
final todosProvider = FutureProvider<List<Todo>>((ref) {
  return ref.watch(todoRepositoryProvider).list();
});

/// 逾期计数（仪表盘角标 / 列表头提示共用）。
final overdueCountProvider = FutureProvider<int>((ref) {
  return ref.watch(todoRepositoryProvider).countOverdue();
});

/// 番茄会话（V1.20 · 单活：全局同时仅一个番茄，与日程「进行中」同规则）。
class PomoSession {
  PomoSession({
    required this.todoId,
    required this.title,
    required this.mode,
    this.minutes,
    DateTime? startedAt,
  })  : startedAt = startedAt ?? DateTime.now();

  final int todoId;
  final String title;

  /// up=正计时 / down=倒计时。
  final String mode;
  final int? minutes;
  final DateTime startedAt;

  /// 累计暂停毫秒与本次暂停起点（V1.22.1：暂停期间时钟冻结，不计耗时）。
  int pausedMs = 0;
  DateTime? pauseStarted;

  int elapsedSec() {
    final live = DateTime.now().difference(startedAt).inMilliseconds -
        pausedMs -
        (pauseStarted == null ? 0 : DateTime.now().difference(pauseStarted!).inMilliseconds);
    return (live ~/ 1000).clamp(0, 24 * 3600);
  }

  int runningSec() =>
      DateTime.now().difference(startedAt).inMilliseconds ~/ 1000 - pausedMs ~/ 1000;
}

final activePomoProvider = StateProvider<PomoSession?>((ref) => null);

/// 列表 / 四象限视图切换（页面级临时状态）。
final todoViewModeProvider = StateProvider<bool>((ref) => false); // false=清单 true=四象限

/// 清单智能筛选（原型 todoChips）：all/today/week/scheduled/done/overdue。
final todoFilterProvider = StateProvider<String>((ref) => 'all');

/// V1.26 筛选面板开合（顶栏漏斗按钮控制；清单视图只留列表防臃肿）。
final todoFilterOpenProvider = StateProvider<bool>((ref) => false);
