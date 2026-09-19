import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'todo_providers.dart';
import 'widgets/quadrant_board.dart';
import 'widgets/todo_edit_sheet.dart';
import 'widgets/todo_list_view.dart';

/// 模块2 待办 + 四象限（M0 基础版）：
/// 清单/四象限双视图、双录入（手动/引导两问）、勾选完成、拖拽换象限、滑动删除、逾期标记。
class TodoPage extends ConsumerWidget {
  const TodoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final quadrantMode = ref.watch(todoViewModeProvider);
    final todosAsync = ref.watch(todosProvider);
    final overdue = ref.watch(overdueCountProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('待办'),
        actions: [
          if (overdue > 0)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('逾期 $overdue',
                  style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('清单'), icon: Icon(Icons.view_list_outlined, size: 18)),
                  ButtonSegment(value: true, label: Text('四象限'), icon: Icon(Icons.grid_view_outlined, size: 18)),
                ],
                selected: {quadrantMode},
                onSelectionChanged: (s) =>
                    ref.read(todoViewModeProvider.notifier).state = s.first,
              ),
            ),
          ),
          Expanded(
            child: todosAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败：$e')),
              data: (todos) => quadrantMode
                  ? QuadrantBoard(todos: todos)
                  : TodoListView(todos: todos),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: tokens.accent,
        onPressed: () => showTodoEditSheet(context, ref),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
