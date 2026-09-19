import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/todo.dart';
import '../todo_providers.dart';

/// 2×2 四象限看板：任务卡可拖拽跨象限流转（AC：<300ms 持久化）。
class QuadrantBoard extends ConsumerWidget {
  const QuadrantBoard({super.key, required this.todos});

  final List<Todo> todos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = [
      [Quadrant.q1, Quadrant.q2],
      [Quadrant.q3, Quadrant.q4],
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      child: Column(
        children: [
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
                          todos: todos.where((t) => t.quadrant == q && !t.done).toList(),
                        ),
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

class _QuadrantCell extends ConsumerWidget {
  const _QuadrantCell({required this.quadrant, required this.todos});

  final Quadrant quadrant;
  final List<Todo> todos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<Todo>(
      onWillAcceptWithDetails: (d) => d.data.quadrant != quadrant,
      onAcceptWithDetails: (d) {
        ref.read(todoRepositoryProvider).moveQuadrant(d.data, quadrant);
        ref.invalidate(todosProvider);
      },
      builder: (context, candidate, _) {
        final highlighted = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: quadrant.color.withValues(alpha: highlighted ? .20 : .08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: quadrant.color.withValues(alpha: highlighted ? .9 : .3),
            ),
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
                    decoration: BoxDecoration(shape: BoxShape.circle, color: quadrant.color),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      quadrant.label,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: scheme.onSurface),
                    ),
                  ),
                  Text('${todos.length}',
                      style: TextStyle(fontSize: 12, color: quadrant.color, fontWeight: FontWeight.w700)),
                ],
              ),
              Text(quadrant.hint, style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
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
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: quadrant.color,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(t.title,
                                style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                          ),
                        ),
                        childWhenDragging: const SizedBox(height: 30),
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: quadrant.color.withValues(alpha: .45)),
                          ),
                          child: Row(
                            children: [
                              if (t.overdue)
                                const Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: Icon(Icons.error_outline, size: 13, color: Color(0xFFEF4444)),
                                ),
                              Expanded(
                                child: Text(
                                  t.title,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
