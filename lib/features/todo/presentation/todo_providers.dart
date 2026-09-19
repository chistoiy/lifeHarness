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

/// 列表 / 四象限视图切换（页面级临时状态）。
final todoViewModeProvider = StateProvider<bool>((ref) => false); // false=清单 true=四象限

/// 清单智能筛选（原型 todoChips）：all/today/week/scheduled/done/overdue。
final todoFilterProvider = StateProvider<String>((ref) => 'all');
