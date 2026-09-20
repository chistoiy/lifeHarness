import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/wheel_time.dart';
import '../../domain/cal_event.dart';
import '../../domain/category.dart';
import '../calendar_providers.dart';
import '../../../../core/widgets/wheel_date.dart';

/// 编辑事件表单（V1.23 起 sheetAddEvent 仅保留编辑用途；添加统一走 sheetTimePick）。
Future<void> showEventEditSheet(BuildContext context, WidgetRef ref, CalEvent e) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EventEdit(e: e),
  );
}

class _EventEdit extends ConsumerStatefulWidget {
  const _EventEdit({required this.e});
  final CalEvent e;

  @override
  ConsumerState<_EventEdit> createState() => _EventEditState();
}

class _EventEditState extends ConsumerState<_EventEdit> {
  late final TextEditingController _title = TextEditingController(text: widget.e.title);
  late DateTime _start = widget.e.start;
  late int _durMin = widget.e.durationMin ??
      (widget.e.end != null ? widget.e.end!.difference(widget.e.start).inMinutes : 60);
  late bool _allDay = widget.e.allDay;
  late int? _catId = widget.e.catId;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showWheelDatePick(context, _start);
    if (d != null) {
      setState(() => _start = DateTime(d.year, d.month, d.day, _start.hour, _start.minute));
    }
  }

  Future<void> _save() async {
    final repo = ref.read(eventRepositoryProvider);
    final title = _title.text.trim().isEmpty ? widget.e.title : _title.text.trim();
    await repo.update(widget.e.copyWith(
      title: title,
      start: _start,
      end: _allDay ? null : _start.add(Duration(minutes: _durMin)),
      allDay: _allDay,
      catId: _catId,
    ));
    ref.invalidate(eventsProvider);
    ref.invalidate(activeEventProvider);
    if (!mounted) return;
    final day0 = DateTime(_start.year, _start.month, _start.day);
    ref.invalidate(dayBlocksProvider(day0));
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已保存 · 四视图与时间账本同步更新')));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    final primary = cats.where((c) => c.isPrimary).toList();
    final catColors = ref.watch(catColorsByNameProvider);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('编辑事件（${widget.e.title}）',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
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
                    onPressed: _allDay ? null : _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 15),
                    label: Text('${_start.month}月${_start.day}日'),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 100,
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
            // V1.26.2 内嵌滚轮：就地上下滑动选开始时分，无二次弹层
            if (!_allDay)
              Row(
                children: [
                  SizedBox(
                      width: 40,
                      child: Text('开始',
                          style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant))),
                  Expanded(
                    child: InlineWheelTime(
                      initial: TimeOfDay.fromDateTime(_start),
                      onChanged: (h, m) => _start =
                          DateTime(_start.year, _start.month, _start.day, h, m),
                    ),
                  ),
                ],
              ),
            Row(
              children: [
                const Text('全天', style: TextStyle(fontSize: 13)),
                Switch(value: _allDay, onChanged: (v) => setState(() => _allDay = v)),
              ],
            ),
            const SizedBox(height: 4),
            Text('分类', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in primary)
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    selected: _catId == c.id,
                    onSelected: (_) => setState(() => _catId = c.id),
                    avatar: Container(
                        width: 9, height: 9,
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            color: c.name == '工作' ? tokens.accent : catColors[c.name])),
                    label: Text(c.name, style: const TextStyle(fontSize: 11)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: tokens.accent, minimumSize: const Size.fromHeight(46)),
                onPressed: _save,
                child: const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
