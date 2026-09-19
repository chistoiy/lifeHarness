import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/todo.dart';
import '../todo_providers.dart';

/// 打开新建/编辑弹层。existing 为 null 时新建。
Future<void> showTodoEditSheet(BuildContext context, WidgetRef ref, {Todo? existing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => TodoEditSheet(existing: existing),
  );
}

/// 双录入（需求模块2）：手动选象限 / 引导式「重要吗·紧急吗」两问 100% 落象限。
class TodoEditSheet extends ConsumerStatefulWidget {
  const TodoEditSheet({super.key, this.existing});

  final Todo? existing;

  @override
  ConsumerState<TodoEditSheet> createState() => _TodoEditSheetState();
}

class _TodoEditSheetState extends ConsumerState<TodoEditSheet> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.existing?.note ?? '');
  late Quadrant _quadrant = widget.existing?.quadrant ?? Quadrant.q2;
  late DateTime? _due = widget.existing?.dueAt;
  bool _guided = false;
  // 引导两问状态：null=未答
  bool? _important;
  bool? _urgent;
  int _step = 0; // 0 重要? 1 紧急? 2 落焦+标题

  bool get _isEdit => widget.existing != null;

  Quadrant get _derived => Quadrant.values.firstWhere(
        (q) =>
            q.value ==
            ((_important == true) ? ((_urgent == true) ? 1 : 2) : ((_urgent == true) ? 3 : 4)),
      );

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final repo = ref.read(todoRepositoryProvider);
    final q = _guided ? _derived : _quadrant;
    if (_isEdit) {
      await repo.edit(widget.existing!.copyWith(
          title: title, note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          quadrant: q, dueAt: _due));
    } else {
      await repo.add(Todo(
          title: title, note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          quadrant: q, dueAt: _due));
    }
    ref.invalidate(todosProvider);
    ref.invalidate(overdueCountProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(_isEdit ? '编辑任务' : '新建任务',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _guided = !_guided),
                  child: Text(_guided ? '切到手动' : '引导式录入'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (_guided && _step < 2) ...[
              Text(_step == 0 ? '这件事【重要】吗？' : '这件事【紧急】吗？',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurface)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => setState(() {
                        if (_step == 0) {
                          _important = true;
                          _step = 1;
                        } else {
                          _urgent = true;
                          _step = 2;
                        }
                      }),
                      child: Text(_step == 0 ? '重要' : '紧急'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() {
                        if (_step == 0) {
                          _important = false;
                          _step = 1;
                        } else {
                          _urgent = false;
                          _step = 2;
                        }
                      }),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
                      child: Text(_step == 0 ? '不重要' : '不紧急'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_important != null)
                Text('判定：${_important == true ? '重要' : '不重要'}${_urgent != null ? ' · ${_urgent == true ? '紧急' : '不紧急'}' : ''}',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ] else ...[
              if (_guided)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _derived.color.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('已落入：${_derived.label}',
                            style: TextStyle(fontSize: 12, color: _derived.color, fontWeight: FontWeight.w600)),
                      ),
                      const Spacer(),
                      TextButton(
                          onPressed: () => setState(() {
                                _step = 0;
                                _important = null;
                                _urgent = null;
                              }),
                          child: const Text('重新判定')),
                    ],
                  ),
                ),
              if (!_guided)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final q in Quadrant.values)
                      ChoiceChip(
                        label: Text(q.label, style: const TextStyle(fontSize: 12)),
                        selected: _quadrant == q,
                        onSelected: (_) => setState(() => _quadrant = q),
                      ),
                  ],
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _title,
                autofocus: !_isEdit && !(_guided && _step < 2),
                decoration: const InputDecoration(labelText: '任务标题', isDense: true),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _note,
                decoration: const InputDecoration(labelText: '备注（可选）', isDense: true),
                maxLines: 2,
                minLines: 1,
              ),
              const SizedBox(height: 10),
              _DueRow(due: _due, onChanged: (d) => setState(() => _due = d)),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_guided && _step < 2) ? null : _save,
                child: Text(_isEdit ? '保存修改' : '添加任务'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DueRow extends StatelessWidget {
  const _DueRow({required this.due, required this.onChanged});

  final DateTime? due;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    DateTime day(int add) => DateTime(now.year, now.month, now.day + add, 23, 59);
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('到期：', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        for (final (label, d) in [('无', null), ('今天', day(0)), ('明天', day(1)), ('本周末', day((7 - now.weekday) % 7 == 0 ? 7 : (7 - now.weekday)))] )
          ChoiceChip(
            label: Text(label, style: const TextStyle(fontSize: 12)),
            selected: due == null ? d == null : (d != null && due!.day == d.day && due!.month == d.month),
            onSelected: (_) => onChanged(d),
          ),
      ],
    );
  }
}
