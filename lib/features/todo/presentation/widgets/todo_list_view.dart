import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/todo.dart';
import '../todo_providers.dart';
import 'pomo_screen.dart';
import 'todo_edit_sheet.dart';

/// 智能筛选定义（原型 todoChips：今天/最近7天/四象限入口/已安排/已完成/已过期）。
const todoChips = <(String, String)>[
  ('all', '全部'),
  ('today', '📅 今天'),
  ('week', '🗓 最近7天'),
  ('quad', '⭐ 四象限'),
  ('scheduled', '🗃 已安排'),
  ('done', '☑️ 已完成'),
  ('overdue', '⏰ 已过期'),
];

bool matchTodo(Todo t, String f) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  switch (f) {
    case 'today':
      return !t.done && t.dueAt != null && DateTime(t.dueAt!.year, t.dueAt!.month, t.dueAt!.day) == today;
    case 'week':
      return !t.done &&
          t.dueAt != null &&
          t.dueAt!.isBefore(today.add(const Duration(days: 8)));
    case 'scheduled':
      return !t.done && t.dueAt != null;
    case 'done':
      return t.done;
    case 'overdue':
      return t.overdue;
    default:
      return true; // 全部：含已完成（DAO 已按未完成在前排序，原型同款）
  }
}

/// V1.26 智能筛选 chips（收进顶栏漏斗面板 · 点选后自动收起 · 原型 todoFilterPanel 卡）。
class SmartFilterBar extends ConsumerWidget {
  const SmartFilterBar({super.key, required this.todos});

  final List<Todo> todos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(todoFilterProvider);
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('智能筛选 · 选择后自动收起',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final (id, label) in todoChips)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        id == 'all' || id == 'scheduled' || id == 'quad'
                            ? label
                            : '$label ${todos.where((t) => matchTodo(t, id)).length}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: filter == id ? Colors.white : scheme.onSurfaceVariant),
                      backgroundColor: scheme.onSurface.withValues(alpha: .08),
                      selectedColor: tokens.accent,
                      showCheckmark: false,
                      shape: const StadiumBorder(),
                      visualDensity: VisualDensity.compact,
                      selected: filter == id,
                      onSelected: (_) {
                        if (id == 'quad') {
                          // 原型「⭐ 四象限」chip = 切换四象限视图
                          ref.read(todoViewModeProvider.notifier).state = true;
                          ref.read(todoFilterOpenProvider.notifier).state = false;
                          return;
                        }
                        ref.read(todoFilterProvider.notifier).state = id;
                        ref.read(todoFilterOpenProvider.notifier).state = false;
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 清单视图（原型 p-todo listWrap · V1.26 筛选移入顶栏面板后只留列表）：
/// 任务卡 + 逾期提示大卡 + 快速添加。
class TodoListView extends ConsumerWidget {
  const TodoListView({super.key, required this.todos});

  final List<Todo> todos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final filter = ref.watch(todoFilterProvider);
    final shown = todos.where((t) => matchTodo(t, filter)).toList();
    final overdueCount = todos.where((t) => t.overdue).length;
    final overdueImportant = todos.where((t) => t.overdue && (t.quadrant == Quadrant.q1 || t.quadrant == Quadrant.q2)).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        for (final t in shown) _TodoTile(todo: t),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text('该筛选下暂无任务', style: TextStyle(color: Colors.grey)),
            ),
          ),
        OutlinedButton(
          onPressed: () => showTodoAddSheet(context, ref),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            side: BorderSide(color: Colors.grey.withValues(alpha: .45)),
            foregroundColor: scheme.onSurfaceVariant,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: const Text('+ 快速添加任务'),
        ),
        if (overdueCount > 0)
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF43F5E).withValues(alpha: .07),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF43F5E).withValues(alpha: .3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('⚠️', style: TextStyle(fontSize: 15)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$overdueCount 项任务已逾期${overdueImportant > 0 ? '，其中 $overdueImportant 项标记为「重要」象限' : ''}。',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      Text('临近截止的任务会被自动建议升入紧急象限',
                          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => ref.read(todoViewModeProvider.notifier).state = true,
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFFF43F5E)),
                  child: const Text('处理', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
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
    final scheme = Theme.of(context).colorScheme;
    final accent = Theme.of(context).colorScheme.primary;
    final qc = todo.quadrant.colorOf(accent);

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
        ref.read(todoRepositoryProvider).remove(todo);
        ref.invalidate(todosProvider);
        ref.invalidate(overdueCountProvider);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: context.cardDecoration,
        child: Row(
          children: [
            // 原型 .chk：22px 圆形勾选（选中=主题色底白勾）
            InkWell(
              key: ValueKey('chk-${todo.id}'),
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                final wasDone = todo.done;
                ref.read(todoRepositoryProvider).toggleDone(todo);
                ref.invalidate(todosProvider);
                ref.invalidate(overdueCountProvider);
                if (!wasDone) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(const SnackBar(
                        content: Text('完成 ✓ 已计入今日小结（联动 L2）'),
                        duration: Duration(milliseconds: 1400)));
                }
              },
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: todo.done ? qc : Colors.transparent,
                  border: Border.all(
                      color: todo.done ? qc : const Color(0xFFCBD5E1), width: 2),
                ),
                child: todo.done
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ),
            Expanded(
              child: InkWell(
                onTap: () => showTodoDetailSheet(context, ref, todo),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${todo.isPomo ? '🍅 ' : ''}${todo.title}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: todo.done ? Colors.grey : scheme.onSurface,
                          decoration: todo.done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '◉ ${todo.quadrant.label} · ⏰ ${dueLabel(todo)}${todo.tag != null ? ' · #${todo.tag}' : ''}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: todo.overdue ? const Color(0xFFF43F5E) : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (todo.isPomo && !todo.done)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => startPomoFromList(context, ref, todo),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF43F5E),
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      ref.watch(activePomoProvider)?.todoId == todo.id ? '■' : '▶ 🍅',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 6),
            // 原型 .qbadge：20px 圆角方块象限角标
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: qc, borderRadius: BorderRadius.circular(6)),
              child: Text(
                '①②③④'[todo.quadrant.value - 1],
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

/// 列表直启番茄：单活约束（同日程「进行中」规则），已有其他番茄则提示。
void startPomoFromList(BuildContext context, WidgetRef ref, Todo todo) {
  final cur = ref.read(activePomoProvider);
  if (cur != null && cur.todoId != todo.id) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已有番茄进行中 · 请先结束（单活约束）')));
    return;
  }
  final s = (cur != null && cur.todoId == todo.id)
      ? cur
      : PomoSession(
          todoId: todo.id!,
          title: todo.title,
          mode: todo.pomoMode ?? 'up',
          minutes: todo.pomoMin);
  if (cur == null) ref.read(activePomoProvider.notifier).state = s;
  Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true, builder: (_) => PomoScreen(session: s)));
}
