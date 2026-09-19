import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/time_block.dart';
import '../calendar_providers.dart';

/// 松手后弹出标记面板（原型 sheetGridMark）。
Future<void> showBlockMarkSheet(
  BuildContext context,
  WidgetRef ref, {
  required DateTime day,
  required int gran,
  required int startMin,
  required int endMin,
  TimeBlock? existing,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _MarkSheet(
      day: day,
      startMin: startMin,
      endMin: endMin,
      existing: existing,
    ),
  );
}

String _hm(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

class _MarkSheet extends ConsumerStatefulWidget {
  const _MarkSheet({
    required this.day,
    required this.startMin,
    required this.endMin,
    this.existing,
  });

  final DateTime day;
  final int startMin;
  final int endMin;
  final TimeBlock? existing;

  @override
  ConsumerState<_MarkSheet> createState() => _MarkSheetState();
}

class _MarkSheetState extends ConsumerState<_MarkSheet> {
  BlockCat _cat = BlockCat.work;
  final _note = TextEditingController();

  Future<void> _confirm() async {
    final dao = ref.read(timeBlockDaoProvider);
    // 覆盖语义：先删与新区间重叠的旧手动标记，再写入（L4 账本）。
    await dao.removeOverlapping(widget.day, widget.startMin, widget.endMin);
    await dao.insert(TimeBlock(
      day: DateTime(widget.day.year, widget.day.month, widget.day.day),
      startMin: widget.startMin,
      endMin: widget.endMin,
      category: _cat,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    ));
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✔ 已标记 ${_hm(widget.startMin)}-${_hm(widget.endMin)} · ${_cat.label} → 已写入时间账本（联动 L4）'),
        duration: const Duration(milliseconds: 1800)));
  }

  Future<void> _delete() async {
    final ex = widget.existing;
    if (ex?.id == null) return;
    await ref.read(timeBlockDaoProvider).remove(ex!.id!);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('标记已取消，格子恢复空闲'), duration: Duration(milliseconds: 1500)));
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final ex = widget.existing;
    final span = widget.endMin - widget.startMin;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('标记时间块', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              ex == null
                  ? '${_hm(widget.startMin)} - ${_hm(widget.endMin)}（${span ~/ 60 > 0 ? '${span ~/ 60} 小时 ' : ''}${span % 60} 分钟）'
                  : '${_hm(ex.startMin)} - ${_hm(ex.endMin)} · ${ex.category.label}'
                      '${ex.note == null ? '' : ' · ${ex.note}'}（点击已标记格，可取消标记或覆盖新标记）',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Text('选择分类', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in BlockCat.values)
                  ChoiceChip(
                    avatar: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                          color: c.colorOf(tokens.accent),
                          borderRadius: BorderRadius.circular(3)),
                    ),
                    label: Text(c.label, style: const TextStyle(fontSize: 12)),
                    selected: _cat == c,
                    onSelected: (_) => setState(() => _cat = c),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                  hintText: '备注（可选），如：专注报销单', isDense: true),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text('✓ 计入时间账本统计（联动 L4）',
                      style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                ),
                if (ex != null)
                  TextButton(
                    onPressed: _delete,
                    style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFF43F5E)),
                    child: const Text('取消标记', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 44,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: tokens.gradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextButton(
                      onPressed: _confirm,
                      child: const Text('确认标记',
                          style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w700)),
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
