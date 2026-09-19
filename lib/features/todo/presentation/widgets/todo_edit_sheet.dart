import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/todo.dart';
import '../todo_providers.dart';

/// 打开新建弹层（原型 sheetAddTask）。
Future<void> showTodoAddSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _TodoAddSheet(),
  );
}

/// 打开任务详情/编辑弹层（原型 sheetTask）。
Future<void> showTodoDetailSheet(BuildContext context, WidgetRef ref, Todo todo) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TodoDetailSheet(todo: todo),
  );
}

/// 到期文本（原型 due 展示：今天/明天/本周/已逾期 N 天/MM-dd）。
String dueLabel(Todo t) {
  if (t.dueAt == null) return '—';
  final now = DateTime.now();
  final due = t.dueAt!;
  final today = DateTime(now.year, now.month, now.day);
  final dueDay = DateTime(due.year, due.month, due.day);
  final diff = dueDay.difference(today).inDays;
  if (t.overdue) return diff <= -1 ? '已逾期 ${-diff} 天' : '已逾期';
  if (diff == 0) return '今天';
  if (diff == 1) return '明天';
  if (diff < 7) return '本周';
  return '${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}';
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(milliseconds: 1600)));
}

class _TodoAddSheet extends ConsumerStatefulWidget {
  const _TodoAddSheet();

  @override
  ConsumerState<_TodoAddSheet> createState() => _TodoAddSheetState();
}

class _TodoAddSheetState extends ConsumerState<_TodoAddSheet> {
  final _title = TextEditingController();
  final _tag = TextEditingController();
  bool? _imp; // null=未答
  bool? _urg;
  DateTime? _due;
  int _remind = 0; // 0 不提醒 1 当天09:00 2 提前1小时

  Quadrant get _derived =>
      (_imp == true && _urg == true) ? Quadrant.q1
          : _imp == true ? Quadrant.q2
          : _urg == true ? Quadrant.q3
          : Quadrant.q4;

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      _toast(context, '请先输入任务标题');
      return;
    }
    DateTime? remindAt;
    if (_due != null) {
      if (_remind == 1) {
        remindAt = DateTime(_due!.year, _due!.month, _due!.day, 9);
      } else if (_remind == 2) {
        remindAt = _due!.subtract(const Duration(hours: 1));
      }
    }
    final q = _derived;
    await ref.read(todoRepositoryProvider).add(Todo(
          title: title,
          quadrant: q,
          dueAt: _due,
          remindAt: remindAt,
          tag: _tag.text.trim().isEmpty ? null : _tag.text.trim(),
        ));
    ref.invalidate(todosProvider);
    ref.invalidate(overdueCountProvider);
    if (!mounted) return;
    Navigator.of(context).pop();
    _toast(context, '已存入「${q.label}」象限 ✓');
  }

  @override
  void dispose() {
    _title.dispose();
    _tag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('新建待办', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                  hintText: '任务标题，如：给绿植浇水', isDense: true),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            Text('引导式判象限（推荐）',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _AskCard(
                    question: '这件事重要吗？',
                    sub: '对目标/价值有贡献',
                    answer: _imp,
                    accent: tokens.accent,
                    onTap: () => setState(() => _imp = _imp == true ? false : true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AskCard(
                    question: '这件事紧急吗？',
                    sub: '有明确近期期限',
                    answer: _urg,
                    accent: tokens.accent,
                    onTap: () => setState(() => _urg = _urg == true ? false : true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _DueRow(due: _due, onChanged: (d) => setState(() => _due = d)),
            if (_due != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('提醒：', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  for (final (i, label) in const [(0, '不提醒'), (1, '当天 09:00'), (2, '提前1小时')])
                    ChoiceChip(
                      label: Text(label, style: const TextStyle(fontSize: 12)),
                      selected: _remind == i,
                      onSelected: (_) => setState(() => _remind = i),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _tag,
              decoration: const InputDecoration(labelText: '标签（可选，如：工作）', isDense: true),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: tokens.gradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TextButton(
                  onPressed: _save,
                  child: const Text('存入四象限',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 引导两问卡（原型 .q-ask）：未答显示副文案，答后显示 是 ✓ / 否。
class _AskCard extends StatelessWidget {
  const _AskCard({
    required this.question,
    required this.sub,
    required this.answer,
    required this.accent,
    required this.onTap,
  });

  final String question;
  final String sub;
  final bool? answer;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final answered = answer != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: answered ? accent : Colors.grey.withValues(alpha: .4),
            width: answered ? 1.6 : 1,
          ),
          color: answered ? accent.withValues(alpha: .08) : Colors.transparent,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(question, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(
              answer == null ? sub : (answer == true ? '是 ✓' : '否'),
              style: TextStyle(
                fontSize: 11,
                color: answer == null
                    ? Colors.grey
                    : (answer == true ? accent : Colors.grey),
                fontWeight: answer == null ? FontWeight.normal : FontWeight.w700,
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
    DateTime day(int add) => DateTime(now.year, now.month, now.day + add, 18);
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('到期：', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        for (final (label, d) in [
          ('无', null),
          ('今天', day(0)),
          ('明天', day(1)),
          ('本周末', day((7 - now.weekday) % 7 == 0 ? 7 : (7 - now.weekday))),
        ])
          ChoiceChip(
            label: Text(label, style: const TextStyle(fontSize: 12)),
            selected: due == null ? d == null : (d != null && due!.day == d.day && due!.month == d.month),
            onSelected: (_) => onChanged(d),
          ),
      ],
    );
  }
}

/// 任务详情/编辑（原型 sheetTask：标题 + q-move 改判四按钮 + 备注 + 删除）。
class _TodoDetailSheet extends ConsumerStatefulWidget {
  const _TodoDetailSheet({required this.todo});

  final Todo todo;

  @override
  ConsumerState<_TodoDetailSheet> createState() => _TodoDetailSheetState();
}

class _TodoDetailSheetState extends ConsumerState<_TodoDetailSheet> {
  late Quadrant _q = widget.todo.quadrant;
  late final TextEditingController _note = TextEditingController(text: widget.todo.note ?? '');

  Future<void> _save() async {
    final repo = ref.read(todoRepositoryProvider);
    final changed = _q != widget.todo.quadrant;
    await repo.edit(Todo(
      id: widget.todo.id,
      title: widget.todo.title,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      quadrant: _q,
      dueAt: widget.todo.dueAt,
      remindAt: widget.todo.remindAt,
      tag: widget.todo.tag,
      done: widget.todo.done,
    ));
    ref.invalidate(todosProvider);
    ref.invalidate(overdueCountProvider);
    if (!mounted) return;
    Navigator.of(context).pop();
    if (changed) _toast(context, '已改判为「${_q.label}」（拖拽同样可用）');
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = widget.todo;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('◉ ${t.quadrant.label} · ⏰ ${dueLabel(t)}${t.tag != null ? ' · #${t.tag}' : ''}',
                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            Text('改判象限', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final q in Quadrant.values)
                  ChoiceChip(
                    avatar: CircleAvatar(
                      radius: 5,
                      backgroundColor: q.colorOf(scheme.primary),
                    ),
                    label: Text(q.label, style: const TextStyle(fontSize: 12)),
                    selected: _q == q,
                    onSelected: (_) => setState(() => _q = q),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: '备注', isDense: true),
              maxLines: 2,
              minLines: 1,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final navigator = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(context);
                      await ref.read(todoRepositoryProvider).remove(t);
                      ref.invalidate(todosProvider);
                      ref.invalidate(overdueCountProvider);
                      navigator.pop();
                      messenger
                        ..hideCurrentSnackBar()
                        ..showSnackBar(const SnackBar(
                            content: Text('已删除'),
                            duration: Duration(milliseconds: 1400)));
                    },
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFFECACA)),
                    ),
                    child: const Text('删除'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
