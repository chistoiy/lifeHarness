import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/cal_event.dart';
import '../../domain/event_repository.dart';
import '../calendar_providers.dart';

Future<void> showEventSheet(BuildContext context, WidgetRef ref, {DateTime? presetDay}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EventSheet(presetDay: presetDay),
  );
}

class _EventSheet extends ConsumerStatefulWidget {
  const _EventSheet({this.presetDay});

  final DateTime? presetDay;

  @override
  ConsumerState<_EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends ConsumerState<_EventSheet> {
  final _title = TextEditingController();
  late DateTime _start;
  int _durMin = 60;
  bool _allDay = false;
  int _color = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // 日历页选中的日期必须作为默认日期（否则点17号新建会落到今天 = 事件补录 bug）。
    final d = widget.presetDay ?? now;
    final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
    // 今天 → 下一整点（23 点封顶防溢出次日）；其他日期 → 上午 9 点。
    final h = isToday ? (now.hour + 1).clamp(0, 23) : 9;
    _start = DateTime(d.year, d.month, d.day, h, 0);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
    );
    if (t != null) {
      setState(() => _start = DateTime(_start.year, _start.month, _start.day, t.hour, t.minute));
    }
  }

  CalEvent _draft() => CalEvent(
        title: _title.text.trim().isEmpty ? '未命名日程' : _title.text.trim(),
        start: _start,
        end: _allDay ? null : _start.add(Duration(minutes: _durMin)),
        allDay: _allDay,
        colorIdx: _color,
      );

  Future<void> _create() async {
    final repo = ref.read(eventRepositoryProvider);
    final saved = await repo.create(_draft());
    _afterSave();
    final conflicts = EventRepository.conflictsOf(
        [...(await repo.listAll())]).where((c) => c.a.id == saved.id || c.b.id == saved.id);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (conflicts.isNotEmpty) {
      final c = conflicts.first;
      messenger.showSnackBar(SnackBar(
          content: Text('⏱ 时间冲突：「${c.a.title}」与「${c.b.title}」重叠 ${c.overlapMin} 分钟'),
          duration: const Duration(seconds: 3)));
    } else {
      messenger.showSnackBar(const SnackBar(content: Text('日程已创建 ✓')));
    }
  }

  Future<void> _startNow() async {
    final repo = ref.read(eventRepositoryProvider);
    try {
      final e = await repo.startNow(_draft());
      _afterSave();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('▶ 已开始：${e.title} · 做完点悬浮条「■ 结束」'),
          duration: const Duration(seconds: 3)));
    } on StateError {
      _afterSave();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已有进行中的事项，请先结束当前事项')));
    }
  }

  void _afterSave() {
    ref.invalidate(eventsProvider);
    ref.invalidate(activeEventProvider);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  String get _timeLabel =>
      '${_start.hour.toString().padLeft(2, '0')}:${_start.minute.toString().padLeft(2, '0')}';

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
            const Text('新建日程', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: '事项标题', isDense: true),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _allDay ? null : _pickTime,
                    icon: const Icon(Icons.schedule, size: 16),
                    label: Text(_allDay ? '全天' : '开始 $_timeLabel'),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 110,
                  child: DropdownButtonFormField<int>(
                    initialValue: _durMin,
                    isExpanded: true,
                    decoration: const InputDecoration(isDense: true),
                    items: const [
                      DropdownMenuItem(value: 30, child: Text('30 分钟')),
                      DropdownMenuItem(value: 60, child: Text('1 小时')),
                      DropdownMenuItem(value: 90, child: Text('1.5 小时')),
                      DropdownMenuItem(value: 120, child: Text('2 小时')),
                    ],
                    onChanged: (v) => setState(() => _durMin = v ?? 60),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const Text('全天', style: TextStyle(fontSize: 13)),
                Switch(value: _allDay, onChanged: (v) => setState(() => _allDay = v)),
                const Spacer(),
                const Text('色标 ', style: TextStyle(fontSize: 13)),
                for (var i = 0; i < 4; i++)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: InkWell(
                      onTap: () => setState(() => _color = i),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: CalEvent.palette(tokens.accent, i),
                          border: _color == i
                              ? Border.all(color: scheme.onSurface, width: 2)
                              : null,
                        ),
                        child: _color == i
                            ? const Icon(Icons.check, size: 13, color: Colors.white)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: FilledButton.icon(
                      onPressed: _startNow,
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFF43F5E)),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('▶ 现在就开始'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: tokens.gradient,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: TextButton(
                        onPressed: _create,
                        child: const Text('创建（预约）',
                            style: TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ),
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
