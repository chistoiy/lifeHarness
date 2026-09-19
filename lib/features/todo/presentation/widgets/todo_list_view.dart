import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/todo.dart';
import '../todo_providers.dart';
import 'todo_edit_sheet.dart';

/// 清单视图：未完成在前、逾期标红，滑动删除，点按编辑。
class TodoListView extends ConsumerWidget {
  const TodoListView({super.key, required this.todos});

  final List<Todo> todos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = todos.where((t) => !t.done).toList();
    final done = todos.where((t) => t.done).toList();
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      children: [
        for (final t in pending) _TodoTile(todo: t),
        if (done.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('已完成 (${done.length})',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          for (final t in done) _TodoTile(todo: t),
        ],
        if (todos.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(
              child: Text('暂无待办，点右下角 + 新建任务',
                  style: TextStyle(color: Colors.grey)),
            ),
          ),
      ],
    );
  }
}

class _TodoTile extends ConsumerWidget {
  const _TodoTile({required this.todo});

  final Todo todo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(todoRepositoryProvider);
    final scheme = Theme.of(context).colorScheme;

    return Dismissible(
      key: ValueKey('todo-${todo.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withValues(alpha: .12),
          borderRadius: BorderRadius.circular(context.tokens.cardRadius),
        ),
        child: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
      ),
      onDismissed: (_) {
        repo.remove(todo);
        ref.invalidate(todosProvider);
        ref.invalidate(overdueCountProvider);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        decoration: context.cardDecoration,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          leading: Checkbox(
            value: todo.done,
            activeColor: todo.quadrant.color,
            onChanged: (_) {
              repo.toggleDone(todo);
              ref.invalidate(todosProvider);
              ref.invalidate(overdueCountProvider);
            },
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  todo.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface,
                    decoration: todo.done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (todo.overdue)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('逾期',
                      style: TextStyle(fontSize: 10, color: Color(0xFFEF4444))),
                ),
            ],
          ),
          subtitle: todo.dueAt == null
              ? null
              : Text(
                  '到期 ${todo.dueAt!.month}/${todo.dueAt!.day}',
                  style: TextStyle(
                      fontSize: 11,
                      color: todo.overdue
                          ? const Color(0xFFEF4444)
                          : scheme.onSurfaceVariant),
                ),
          trailing: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: todo.quadrant.color),
          ),
          onTap: () => showTodoEditSheet(context, ref, existing: todo),
        ),
      ),
    );
  }
}
