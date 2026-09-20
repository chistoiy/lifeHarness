import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/grad_fab.dart';
import '../../../shared/linkage/linkage_events.dart';
import 'todo_providers.dart';
import 'widgets/quadrant_board.dart';
import 'widgets/todo_edit_sheet.dart';
import 'widgets/todo_list_view.dart';

/// 模块2 待办 + 四象限（M0 · 已对齐高保真原型 p-todo）：
/// 清单/四象限双视图、引导式两问单表单、拖拽换象限、智能筛选 chips、逾期提示卡。
class TodoPage extends ConsumerStatefulWidget {
  const TodoPage({super.key});

  @override
  ConsumerState<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends ConsumerState<TodoPage> {
  @override
  void initState() {
    super.initState();
    // 仪表盘 FAB「✅ 记待办」跨页直达新建弹层（事件总线解耦，守 R1）。
    ref.read(eventBusProvider).on<QuickAddEvent>().listen((e) {
      if (!mounted || e.target != 'todo') return;
      showTodoAddSheet(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final quadrantMode = ref.watch(todoViewModeProvider);
    final filterOpen = ref.watch(todoFilterOpenProvider);
    final todosAsync = ref.watch(todosProvider);
    final overdue = ref.watch(overdueCountProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text('待办'),
                if (overdue > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF43F5E).withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('⏰ $overdue',
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFF43F5E),
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
            Text('四象限 · 引导式时间管理',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.normal,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
        // 原型全局顶栏：搜索常驻 + 待办页漏斗筛选（清单视图显）
        actions: [
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search),
            onPressed: () => ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(
                  content: Text('全局搜索 · 即将开放'),
                  duration: Duration(milliseconds: 1500))),
          ),
          if (!quadrantMode)
            IconButton(
              tooltip: '智能筛选',
              icon: Icon(filterOpen
                  ? Icons.filter_alt
                  : Icons.filter_alt_outlined),
              onPressed: () => ref
                  .read(todoFilterOpenProvider.notifier)
                  .state = !filterOpen,
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                          value: false,
                          label: Text('清单视图'),
                          icon: Icon(Icons.check_circle_outline, size: 16)),
                      ButtonSegment(
                          value: true,
                          label: Text('四象限'),
                          icon: Icon(Icons.grid_view_outlined, size: 16)),
                    ],
                    selected: {quadrantMode},
                    onSelectionChanged: (s) {
                      ref.read(todoViewModeProvider.notifier).state = s.first;
                      ref.read(todoFilterOpenProvider.notifier).state = false;
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  decoration: BoxDecoration(
                    gradient: tokens.gradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    tooltip: '新建待办',
                    icon: const Icon(Icons.add, color: Colors.white),
                    onPressed: () => showTodoAddSheet(context, ref),
                  ),
                ),
              ],
            ),
          ),
          if (filterOpen && !quadrantMode)
            SmartFilterBar(todos: todosAsync.valueOrNull ?? const []),
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
      floatingActionButton: GradFab(
        tooltip: '新建待办',
        icon: const Icon(Icons.add, color: Colors.white, size: 26),
        onTap: () => showTodoAddSheet(context, ref),
      ),
    );
  }
}
