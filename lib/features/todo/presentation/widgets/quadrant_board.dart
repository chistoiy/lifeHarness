import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/todo.dart';
import '../../domain/todo_insights.dart';
import '../todo_providers.dart';
import 'todo_edit_sheet.dart';

/// 2×2 四象限看板（原型 quadWrap）：拖拽卡片跨象限流转（AC <300ms 持久化），
/// 格内 + 添加、拖拽反馈 toast、文案「立即做/计划做/快速处理/考虑淘汰」。
class QuadrantBoard extends ConsumerWidget {
  const QuadrantBoard({super.key, required this.todos});

  final List<Todo> todos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final rows = [
      [Quadrant.q1, Quadrant.q2],
      [Quadrant.q3, Quadrant.q4],
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text('💡 长按卡片可拖到其他象限',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ),
          const SizedBox(height: 6),
          for (final row in rows)
            Expanded(
              child: Row(
                children: [
                  for (final q in row)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: _QuadrantCell(
                          quadrant: q,
                          todos: todos.where((t) => t.quadrant == q).toList(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          // M0末B 失衡提醒（原型 quadWrap 底部 amber 卡 · Q2 连续空置 ≥3 天才出现）
          _ImbalanceCard(todos: todos),
        ],
      ),
    );
  }
}

/// 「重要不紧急」象限失衡提醒卡：🧭 + 空置天数 + 去规划（直开 Q2 预置新建）。
class _ImbalanceCard extends ConsumerWidget {
  const _ImbalanceCard({required this.todos});

  final List<Todo> todos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final empty = q2EmptyDays(todos);
    if (empty == null || empty < kImbalanceThresholdDays) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    const sun = Color(0xFFF59E0B);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: sun.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: sun.withValues(alpha: .3)),
      ),
      child: Row(
        children: [
          const Text('🧭', style: TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 11.5, color: scheme.onSurface, height: 1.35),
                children: [
                  const TextSpan(text: '失衡提醒：', style: TextStyle(fontWeight: FontWeight.w800)),
                  TextSpan(
                      text: '「重要不紧急」象限已 $empty 天空置，长期如此容易陷入救火模式。'
                          '先安排一件只属于未来的事。'),
                ],
              ),
            ),
          ),
          TextButton(
            onPressed: () => showTodoAddSheet(context, ref, preset: Quadrant.q2),
            style: TextButton.styleFrom(foregroundColor: sun),
            child: const Text('去规划', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _QuadrantCell extends ConsumerWidget {
  const _QuadrantCell({required this.quadrant, required this.todos});

  final Quadrant quadrant;
  final List<Todo> todos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final qc = quadrant.colorOf(scheme.primary);
    final pending = todos.where((t) => !t.done).length;

    return DragTarget<Todo>(
      onWillAcceptWithDetails: (d) => d.data.quadrant != quadrant,
      onAcceptWithDetails: (d) {
        ref.read(todoRepositoryProvider).moveQuadrant(d.data, quadrant);
        ref.invalidate(todosProvider);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
              content: Text(quadrant.value <= 2
                  ? '好的，已标记为重要 ✓'
                  : '已移出「重要」区，注意别逃避重要事哦'),
              duration: const Duration(milliseconds: 1600)));
      },
      builder: (context, candidate, _) {
        final highlighted = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: qc.withValues(alpha: highlighted ? .18 : .06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: qc.withValues(alpha: highlighted ? .9 : 0)),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: qc),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      quadrant.label,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface),
                    ),
                  ),
                ],
              ),
              Text('${quadrant.hint} · $pending 待办',
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              Expanded(
                child: ListView(
                  children: [
                    for (final t in todos)
                      Draggable<Todo>(
                        key: ValueKey('drag-${t.id}'),
                        data: t,
                        feedback: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: qc,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(t.title,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12.5)),
                          ),
                        ),
                        childWhenDragging: const SizedBox(height: 36),
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: qc.withValues(alpha: .25)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  t.title,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: t.done ? Colors.grey : scheme.onSurface,
                                    decoration:
                                        t.done ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                              ),
                              if (t.overdue)
                                const Icon(Icons.error_outline,
                                    size: 14, color: Color(0xFFF43F5E)),
                              // V1.26 条目 ✕ 直接完成/关闭（与列表勾选同联动）
                              InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () {
                                  final wasDone = t.done;
                                  ref.read(todoRepositoryProvider).toggleDone(t);
                                  ref.invalidate(todosProvider);
                                  ref.invalidate(overdueCountProvider);
                                  if (!wasDone) {
                                    ScaffoldMessenger.of(context)
                                      ..hideCurrentSnackBar()
                                      ..showSnackBar(const SnackBar(
                                          content: Text(
                                              '完成 ✓ 已计入今日小结（联动 L2）'),
                                          duration: Duration(milliseconds: 1400)));
                                  }
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 2),
                                  child: Icon(Icons.close,
                                      size: 16, color: Color(0xFFCBD5E1)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              InkWell(
                onTap: () => showTodoAddSheet(context, ref),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('+ 添加',
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
