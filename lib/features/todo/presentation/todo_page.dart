import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/widgets/grad_fab.dart';
import '../../../shared/linkage/linkage_events.dart';
// UIUX批（2026-10-12）：搜索钮接全局搜索半屏（守 R1：经 shared/linkage 出口）。
import '../../../shared/linkage/search_mounts.dart';
import 'todo_providers.dart';
import 'widgets/quadrant_board.dart';
import 'widgets/todo_edit_sheet.dart';
import 'widgets/todo_list_view.dart';
import '../../../shared/widgets/load_error_state.dart';

/// 模块2 待办 + 四象限（M0 · 已对齐高保真原型 p-todo）：
/// 清单/四象限双视图、引导式两问单表单、拖拽换象限、智能筛选 chips、逾期提示卡。
class TodoPage extends ConsumerStatefulWidget {
  const TodoPage({super.key});

  @override
  ConsumerState<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends ConsumerState<TodoPage> {
  /// V1.27 追加：FAB 类型二选一=首页快捷记录同款行卡菜单（页面风格统一）。
  bool _fabMenu = false;

  @override
  void initState() {
    super.initState();
    // 仪表盘 FAB「✅ 记待办」跨页直达本页 FAB 类型菜单（事件总线解耦，守 R1）。
    ref.read(eventBusProvider).on<QuickAddEvent>().listen((e) {
      if (!mounted || e.target != 'todo') return;
      setState(() => _fabMenu = true);
    });
  }

  @override
  Widget build(BuildContext context) {
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
        // T12：顶行 = 视图切换 ⇄ + 智能筛选漏斗 + 搜索（漏斗两视图均生效）
        actions: [
          IconButton(
            key: const ValueKey('btn-view-toggle'),
            tooltip: quadrantMode ? '切换到清单' : '切换到四象限',
            icon: const Icon(Icons.swap_horiz),
            onPressed: () {
              ref.read(todoViewModeProvider.notifier).state = !quadrantMode;
              ref.read(todoFilterOpenProvider.notifier).state = false;
            },
          ),
          IconButton(
            key: const ValueKey('btn-filter'),
            tooltip: '智能筛选',
            icon: Icon(
                filterOpen ? Icons.filter_alt : Icons.filter_alt_outlined),
            onPressed: () =>
                ref.read(todoFilterOpenProvider.notifier).state = !filterOpen,
          ),
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search),
            // UIUX批（2026-10-12）：僵尸钮兑现——接全局搜索半屏（笔记＋日记）。
            onPressed: () => showGlobalSearch(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          if (filterOpen) SmartFilterBar(todos: todosAsync.valueOrNull ?? const []),
          Expanded(
            child: todosAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => LoadErrorBanner(
                    title: '待办清单没加载出来',
                    error: e,
                    onRetry: () => ref.invalidate(todosProvider),
                  ),
              data: (todos) => quadrantMode
                  ? QuadrantBoard(todos: todos)
                  : TodoListView(todos: todos),
            ),
          ),
        ],
      ),
      // 原型同款：FAB 展开行卡菜单（普通待办 / 番茄计时），与首页快捷记录风格统一
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_fabMenu)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // UIUX批（2026-10-13）：两枚 emoji 迁线性 IconData（原型 todoFabMenu 段已先行）。
                  for (final (type, label, icon) in const [
                    ('norm', '普通待办', Icons.check_circle_outline),
                    ('pomo', '番茄计时', Icons.timer_outlined),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: FabActionCard(
                          key: ValueKey('fab-$type'),
                          label: label,
                          icon: icon,
                          onTap: () {
                            setState(() => _fabMenu = false);
                            showTodoAddSheet(context, ref, type: type);
                          }),
                    ),
                ],
              ),
            ),
          AnimatedRotation(
            duration: const Duration(milliseconds: 180),
            turns: _fabMenu ? 1 / 8 : 0,
            child: GradFab(
              tooltip: '添加待办',
              icon: const Icon(Icons.add, color: Colors.white, size: 26),
              onTap: () => setState(() => _fabMenu = !_fabMenu),
            ),
          ),
        ],
      ),
    );
  }
}
