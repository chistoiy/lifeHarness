import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/todo.dart';
import '../todo_providers.dart';
import '../../../../core/widgets/wheel_time.dart';

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

  // ===== V1.19~V1.25 扩展字段 =====
  String _type = 'normal'; // normal | pomo
  String _pomoMode = 'up'; // up 正计时 | down 倒计时
  int _pomoMin = 25;
  String _status = 'open'; // open | done | drop
  String _timeMode = 'none'; // none | point | range | all
  late TimeOfDay _tStart;
  late TimeOfDay _tEnd;
  int? _colorIdx;

  @override
  void initState() {
    super.initState();
    // V1.26 时间点/段默认当前时间（5 分一档），用户滑动修改
    final n = DateTime.now();
    final t = TimeOfDay(hour: n.hour, minute: ((n.minute / 5).round() * 5) % 60);
    _tStart = t;
    _tEnd = t;
  }

  static const _palette = <String>[
    '#6366F1', '#8B5CF6', '#F59E0B', '#F97316',
    '#F472B6', '#3730A3', '#34D399', '#B45309', '#64748B',
  ];

  int get _sMin => _tStart.hour * 60 + _tStart.minute;
  int get _eMin => _tEnd.hour * 60 + _tEnd.minute;

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
    final tagTxt = _tag.text.trim();
    await ref.read(todoRepositoryProvider).add(Todo(
          title: title,
          quadrant: q,
          dueAt: _due,
          remindAt: remindAt,
          tag: tagTxt.isEmpty
              ? (_status == 'drop' ? '放弃' : null)
              : (_status == 'drop' ? '$tagTxt 放弃' : tagTxt),
          done: _status == 'done' || _status == 'drop',
          dropped: _status == 'drop',
          pomoMode: _type == 'pomo' ? _pomoMode : null,
          pomoMin: _type == 'pomo' && _pomoMode == 'down' ? _pomoMin : null,
          timeMode: _timeMode == 'none' ? null : _timeMode,
          startMin: _timeMode == 'point' || _timeMode == 'range'
              ? _sMin
              : (_timeMode == 'all' ? 0 : null),
          endMin: _timeMode == 'range'
              ? (_eMin <= _sMin ? 0 : _eMin)
              : (_timeMode == 'all' ? 1440 : null),
          colorIdx: _colorIdx,
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
            // ===== V1.20 两型 + 状态三态 =====
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'normal', label: Text('常规', style: TextStyle(fontSize: 11))),
                      ButtonSegment(value: 'pomo', label: Text('番茄', style: TextStyle(fontSize: 11))),
                    ],
                    selected: {_type},
                    onSelectionChanged: (v) => setState(() => _type = v.first),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'open', label: Text('未完成', style: TextStyle(fontSize: 10.5))),
                      ButtonSegment(value: 'done', label: Text('完成', style: TextStyle(fontSize: 10.5))),
                      ButtonSegment(value: 'drop', label: Text('放弃', style: TextStyle(fontSize: 10.5))),
                    ],
                    selected: {_status},
                    onSelectionChanged: (v) => setState(() => _status = v.first),
                  ),
                ),
              ],
            ),
            if (_type == 'pomo') ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('计时', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  for (final m in const [('up', '正计时'), ('down', '倒计时')])
                    ChoiceChip(
                      label: Text(m.$2, style: const TextStyle(fontSize: 12)),
                      selected: _pomoMode == m.$1,
                      onSelected: (_) => setState(() => _pomoMode = m.$1),
                    ),
                  if (_pomoMode == 'down')
                    DropdownButton<int>(
                      value: _pomoMin,
                      isDense: true,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(value: 5, child: Text('5 分', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: 15, child: Text('15 分', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: 25, child: Text('25 分', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: 45, child: Text('45 分', style: TextStyle(fontSize: 12))),
                      ],
                      onChanged: (v) => setState(() => _pomoMin = v ?? 25),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('时间', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                for (final m in const [('none', '无'), ('point', '时间点'), ('range', '时间段'), ('all', '全天')])
                  ChoiceChip(
                    label: Text(m.$2, style: const TextStyle(fontSize: 12)),
                    selected: _timeMode == m.$1,
                    onSelected: (_) => setState(() {
                      _timeMode = m.$1;
                      // V1.26 默认当前时间（每次进入模式重置，滚轮 key 随模式变化重建）
                      final n = DateTime.now();
                      final t = TimeOfDay(hour: n.hour, minute: ((n.minute / 5).round() * 5) % 60);
                      if (m.$1 == 'point' || m.$1 == 'range') _tStart = t;
                      if (m.$1 == 'range') _tEnd = t;
                    }),
                  ),
              ],
            ),
            // V1.26.2 内嵌滚轮：就地上下滑动选时分，无二次弹层
            if (_timeMode == 'point') ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  SizedBox(
                      width: 40,
                      child: Text('时间',
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant))),
                  Expanded(
                    child: InlineWheelTime(
                      key: const ValueKey('tk-point'),
                      initial: _tStart,
                      onChanged: (h, m) => _tStart = TimeOfDay(hour: h, minute: m),
                    ),
                  ),
                ],
              ),
            ],
            if (_timeMode == 'range') ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  SizedBox(
                      width: 40,
                      child: Text('起',
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant))),
                  Expanded(
                    child: InlineWheelTime(
                      key: const ValueKey('tk-start'),
                      initial: _tStart,
                      onChanged: (h, m) => _tStart = TimeOfDay(hour: h, minute: m),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  SizedBox(
                      width: 40,
                      child: Text('止',
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant))),
                  Expanded(
                    child: InlineWheelTime(
                      key: const ValueKey('tk-end'),
                      initial: _tEnd,
                      onChanged: (h, m) => _tEnd = TimeOfDay(hour: h, minute: m),
                    ),
                  ),
                ],
              ),
            ],
            if (_timeMode == 'range')
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('起止相同将自动设为全天',
                    style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('颜色', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                for (var i = 0; i < _palette.length; i++)
                  GestureDetector(
                    onTap: () => setState(() => _colorIdx = _colorIdx == i ? null : i),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF000000 | (int.tryParse(_palette[i].substring(1), radix: 16) ?? 0)),
                        border: _colorIdx == i
                            ? Border.all(color: scheme.onSurface, width: 2)
                            : null,
                      ),
                      child: _colorIdx == i
                          ? const Icon(Icons.check, size: 13, color: Colors.white)
                          : null,
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
