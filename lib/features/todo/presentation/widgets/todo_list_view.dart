import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/logging/app_log.dart';
import '../../../../core/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/scroll_pad.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/todo.dart';
import '../../domain/todo_insights.dart';
import '../todo_providers.dart';
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
class TodoListView extends ConsumerStatefulWidget {
  const TodoListView({super.key, required this.todos});

  final List<Todo> todos;

  @override
  ConsumerState<TodoListView> createState() => _TodoListViewState();
}

/// 清单宿主：除了渲染，还管一件小事——**乐观出树**。
/// Dismissible 的契约是回调触发后本帧必须出树，而 `todosProvider` 重查是异步的；
/// 笔记左滑（note_tab）早就用同一张 `_gone` 集合解掉这个问题，此处同式。
class _TodoListViewState extends ConsumerState<TodoListView> {
  /// 已滑掉、等重查落定的条目 id（点撤销放回时移除）。
  final Set<int> _gone = {};

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filter = ref.watch(todoFilterProvider);
    final shown = widget.todos
        .where((t) => !_gone.contains(t.id) && matchTodo(t, filter))
        .toList();
    final overdueCount =
        widget.todos.where((t) => t.overdue).length;
    final overdueImportant = widget.todos
        .where((t) => t.overdue && (t.quadrant == Quadrant.q1 || t.quadrant == Quadrant.q2))
        .length;
    // M0末B 临期升紧急建议（受设置「逾期/临期升级建议」开关控制）
    final escalateOn =
        ref.watch(settingsControllerProvider).notify.overdueEscalate;
    final escalate =
        escalateOn ? escalateSuggestions(widget.todos) : <Todo>[];

    return ScrollPad(
      // T2-B：切栏销毁子路由，滚动位经常驻 provider 垫回。
      id: 'todo-list',
      child: ReorderableListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      // T6：清单长按拖拽排序（仅「全部」筛选下持久化，避免子集写序污染全表）
      onReorder: (oldIndex, newIndex) async {
        if (oldIndex >= shown.length) return;
        var to = newIndex > oldIndex ? newIndex - 1 : newIndex;
        if (to >= shown.length) to = shown.length - 1;
        if (to == oldIndex || filter != 'all') return;
        final ids = shown.map((t) => t.id!).toList();
        ids.insert(to, ids.removeAt(oldIndex));
        await ref.read(todoRepositoryProvider).reorder(ids);
        ref.invalidate(todosProvider);
      },
      children: [
        for (final t in shown)
          _TodoTile(
            key: ValueKey('todo-${t.id}'),
            todo: t,
            onGone: (id) => setState(() => _gone.add(id)),
            onBack: (id) => setState(() => _gone.remove(id)),
          ),
        if (shown.isEmpty)
          const Padding(
            key: ValueKey('todo-empty'),
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text('该筛选下暂无任务', style: TextStyle(color: Colors.grey)),
            ),
          ),
        if (overdueCount > 0)
          Container(
            key: const ValueKey('overdue-card'),
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
        // M0末B 临期升紧急建议卡：Q2 任务已逾期/24h 内到期 → 一键升入「重要且紧急」
        // （T9 批三：整卡外提成 _EscalateCard，逐条 await 的批量改写要防重入；
        //  key 必须留在列表子项上——ReorderableListView 断言全部子项带 key）
        if (escalate.isNotEmpty)
          _EscalateCard(key: const ValueKey('escalate-card'), todos: escalate),
      ],
    ),
    );
  }
}

/// 临期升紧急建议卡（M0末B）：按钮一次改多条，需防连点重复写库（T9）。
/// key 由父侧给（列表子项必须带 key），卡内不再重复挂。
class _EscalateCard extends ConsumerStatefulWidget {
  const _EscalateCard({super.key, required this.todos});

  final List<Todo> todos;

  @override
  ConsumerState<_EscalateCard> createState() => _EscalateCardState();
}

class _EscalateCardState extends ConsumerState<_EscalateCard> {
  bool _saving = false;

  Future<void> _escalate() async {
    if (_saving) return;
    setState(() => _saving = true);
    final repo = ref.read(todoRepositoryProvider);
    final escalate = widget.todos;
    try {
      for (final t in escalate) {
        await repo.moveQuadrant(t, Quadrant.q1);
      }
      // 一次改多条，留「改了哪些 id」才可能事后逐条核对。
      AppLog.addKey('待办一键升紧急：${escalate.length} 项 重要不紧急→重要且紧急 '
          '（id ${escalate.map((t) => t.id).join('/')}）');
      ref.invalidate(todosProvider);
      ref.invalidate(overdueCountProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('已升入「重要且紧急」，先救最要紧的火'),
            duration: Duration(milliseconds: 1600)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final escalate = widget.todos;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: .08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: .3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📌', style: TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${escalate.length} 项「重要不紧急」已临近截止。',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                Text('再不动手就会变成救火任务，建议升入紧急象限排优先。',
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          TextButton(
            key: const ValueKey('escalate-go'),
            onPressed: _saving ? null : _escalate,
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFB45309)),
            child: const Text('一键升紧急', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _TodoTile extends ConsumerWidget {
  const _TodoTile({
    super.key,
    required this.todo,
    required this.onGone,
    required this.onBack,
  });

  final Todo todo;

  /// 乐观出树 / 撤销放回（集合由清单宿主持有）。
  final ValueChanged<int> onGone;
  final ValueChanged<int> onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final accent = Theme.of(context).colorScheme.primary;
    final qc = todo.quadrant.colorOf(accent);

    return Dismissible(
      key: ValueKey('dismiss-${todo.id}'),
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
        // T3（批六·拍板①）：左滑＝软删进全局回收站（可恢复），不再真 DELETE。
        // 撤销条沿用批一 T4 的排他基建；restore 只清 deleted_at，回原象限原截止。
        // 本枚 tile 马上要随 Dismissible 出树，所以 container/messenger 都在此先取，
        // 回调里不再碰 `ref`/`context`（ref-after-disposed 既定坑）。
        final container = ProviderScope.containerOf(context, listen: false);
        final messenger = ScaffoldMessenger.of(context);
        final repo = container.read(todoRepositoryProvider);
        // 写库不 await：Dismissible 要求本帧出树，invalidate 必须紧跟着发；
        // 与旧真删路径同一时序，sqflite 按连接串行，重查读到的是写完之后的行。
        onGone(todo.id!); // 本帧出树（不等重查）
        unawaited(repo.softRemove(todo));
        container.invalidate(todosProvider);
        container.invalidate(overdueCountProvider);
        // 提示条推到下一帧：showUndoWith 里的 hideCurrentSnackBar 会强制本帧重绘，
        // 而 Dismissible 要求「回调触发后本帧不得再被重建」——同帧挂条＝框架断言炸。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          AppToast.showUndoWith(messenger, '已移入回收站', onUndo: () {
            onBack(todo.id!); // 放回清单（随后重查会自洽）
            unawaited(repo.restore(todo));
            container.invalidate(todosProvider);
            container.invalidate(overdueCountProvider);
          });
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: context.cardDecoration,
        child: Row(
          children: [
            // 原型 task-row：方框 chk（18~20px 圆角6 描边2 · 点方框=完成此待办）
            InkWell(
              key: ValueKey('chk-${todo.id}'),
              borderRadius: BorderRadius.circular(8),
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
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
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
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        todo.title,
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
                        '⏰ ${dueLabel(todo)}${todo.tag != null ? ' · #${todo.tag}' : ''}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: todo.overdue
                              ? const Color(0xFFF43F5E)
                              : scheme.onSurfaceVariant,
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
                      ref.watch(activePomoProvider)?.todoId == todo.id
                          ? '■ 结束'
                          : '▶ 专注',
                      style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white),
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 6),
            // 原型 V1.27：象限=12px 圆点标识（不再显示数字角标）
            Container(
              key: ValueKey('qdot-${todo.id}'),
              width: 12,
              height: 12,
              decoration: BoxDecoration(shape: BoxShape.circle, color: qc),
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
  // T7→T10：全屏专注页改走命名路由 `/pomo`（登记在 todo_routes：它在壳层之外，
  // 照样覆盖壳层无底栏，`fullscreenDialog` 由路由侧的 pageBuilder 保留）
  context.push('/pomo', extra: s);
}
