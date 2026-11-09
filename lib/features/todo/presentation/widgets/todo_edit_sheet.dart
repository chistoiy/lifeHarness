import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ai/ai_review.dart';
import '../../../../core/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/wheel_date.dart';
import '../todo_providers.dart';
import '../../../../core/widgets/wheel_time.dart';
import '../../../../shared/linkage/stats_providers.dart';

part 'todo_add_sheet.dart';

/// 打开新建弹层（原型 sheetAddTask）。
/// [type] norm/pomo（FAB 前置选择决定，弹层内不再显示类型切换）；
/// [preset] 预置两问答案（失衡提醒「去规划」= Quadrant.q2）；
/// [editing] 非空=编辑态（V1.27 T3 详情复用本表单，保存覆盖原条目）。
Future<void> showTodoAddSheet(BuildContext context, WidgetRef ref,
    {String type = 'norm', Quadrant? preset, Todo? editing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TodoAddSheet(type: type, preset: preset, editing: editing),
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

/// 原型 CAT_COLORS（设置·分类管理共用色板的 9 个命名色）。
const catColorNames = <(String, String)>[
  ('亚麻色', '#A16207'),
  ('品牌蓝', '#6366F1'),
  ('天青', '#38BDF8'),
  ('橙', '#FB923C'),
  ('玫瑰', '#FB7185'),
  ('薄荷', '#2DD4BF'),
  ('紫罗兰', '#8B5CF6'),
  ('石墨', '#64748B'),
  ('靛夜', '#3730A3'),
];

Color catColorOf(int idx, Color accent) => idx == 1
    ? accent // 品牌蓝随主题令牌
    : Color(0xFF000000 |
        (int.tryParse(catColorNames[idx].$2.substring(1), radix: 16) ?? 0));


/// 小型分段选择器（原型 p-1 深灰底 + seg-on 白底）。
class _MiniSeg extends StatelessWidget {
  const _MiniSeg({
    required this.options,
    required this.value,
    required this.onChanged,
    this.colorFor,
    this.compact = false,
  });

  final List<(String, String)> options;
  final String value;
  final ValueChanged<String> onChanged;
  final Map<String, Color>? colorFor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (v, label) in options)
            GestureDetector(
              onTap: () => onChanged(v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: EdgeInsets.symmetric(
                    horizontal: compact ? 8 : 10, vertical: compact ? 4 : 5),
                decoration: BoxDecoration(
                  color: v == value ? scheme.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  boxShadow: v == value
                      ? const [BoxShadow(color: Color(0x1A0F172A), blurRadius: 4)]
                      : null,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                      fontSize: compact ? 10.5 : 11,
                      fontWeight: FontWeight.w700,
                      color: v == value
                          ? (colorFor?[v] ?? scheme.onSurface)
                          : scheme.onSurfaceVariant),
                ),
              ),
            ),
        ],
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

/// 任务详情（原型 sheetTask：圆形勾选 + 右上删除 + q-move 四钮 + 关联信息行 + 关闭）。
class _TodoDetailSheet extends ConsumerStatefulWidget {
  const _TodoDetailSheet({required this.todo});

  final Todo todo;

  @override
  ConsumerState<_TodoDetailSheet> createState() => _TodoDetailSheetState();
}

class _TodoDetailSheetState extends ConsumerState<_TodoDetailSheet> {
  late Todo _t = widget.todo;

  static const _qMoveLabels = ['立即做', '计划做', '委托', '淘汰'];

  static String _hm2(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  Future<void> _toggleDone() async {
    await ref.read(todoRepositoryProvider).toggleDone(_t);
    ref.invalidate(todosProvider);
    ref.invalidate(overdueCountProvider);
    setState(() => _t = _t.copyWith(done: !_t.done));
  }

  Future<void> _move(Quadrant q) async {
    if (q == _t.quadrant) return;
    await ref.read(todoRepositoryProvider).moveQuadrant(_t, q);
    ref.invalidate(todosProvider);
    ref.invalidate(overdueCountProvider);
    setState(() => _t = _t.copyWith(quadrant: q));
    if (mounted) _toast(context, '已改判为「${q.label}」（拖拽同样可用）');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final t = _t;
    final qc = t.quadrant.colorOf(tokens.accent);

    final planBlock = t.timeMode == null
        ? null
        : t.timeMode == 'all'
            ? '今日 全天（联动 L1）'
            : (t.timeMode == 'point'
                ? '今日 ${_hm2(t.startMin ?? 0)}（联动 L1）'
                : '今日 ${_hm2(t.startMin ?? 0)}-${_hm2(t.endMin ?? 0)}（联动 L1）');

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 圆形勾选（原型 sheetTask 顶部 chk）
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _toggleDone,
                  child: Container(
                    width: 24,
                    height: 24,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: t.done ? qc : Colors.transparent,
                      border: Border.all(color: qc, width: 2),
                    ),
                    child: t.done
                        ? const Icon(Icons.check, size: 15, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              decoration:
                                  t.done ? TextDecoration.lineThrough : null,
                              color: t.done ? Colors.grey : scheme.onSurface)),
                      const SizedBox(height: 2),
                      Text(
                          '⏰ ${dueLabel(t)}'
                          '${t.remindAt != null ? ' · 提醒 ${t.remindAt!.month.toString().padLeft(2, '0')}-${t.remindAt!.day.toString().padLeft(2, '0')} ${t.remindAt!.hour.toString().padLeft(2, '0')}:${t.remindAt!.minute.toString().padLeft(2, '0')}' : ''}'
                          '${t.tag != null ? ' · #${t.tag}' : ''}',
                          style: TextStyle(
                              fontSize: 11.5, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // ✏️ 编辑（T3：复用新建弹层编辑态回填）
                OutlinedButton(
                  onPressed: () {
                    final navigator = Navigator.of(context);
                    final bc = context;
                    navigator.pop();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (bc.mounted) {
                        showTodoAddSheet(bc, ref,
                            type: t.pomoMode == null ? 'norm' : 'pomo',
                            editing: t);
                      }
                    });
                  },
                  style: OutlinedButton.styleFrom(
                      foregroundColor: tokens.accent,
                      side: BorderSide(color: tokens.accent.withValues(alpha: .4)),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                  child: const Text('✏️ 编辑', style: TextStyle(fontSize: 11)),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    final keep = ref.read(settingsControllerProvider).trashKeepTxt; // V1.57 E 批：软删进垃圾箱·pop 前取档位文案
                    await ref.read(todoRepositoryProvider).softRemove(t);
                    ref.invalidate(todosProvider);
                    ref.invalidate(overdueCountProvider);
                    navigator.pop();
                    messenger.showSnackBar(SnackBar(content: Text('已移入垃圾箱 · $keep'), duration: const Duration(milliseconds: 1600)));
                  },
                  style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFF43F5E),
                      side: const BorderSide(color: Color(0xFFFDA4AF)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                  child: const Text('🗑 删除', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // q-move 四钮（原型 grid-cols-4）
            Row(
              children: [
                for (var i = 0; i < 4; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: i == 3 ? 0 : 8),
                      child: GestureDetector(
                        onTap: () => _move(Quadrant.of(i + 1)),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: t.quadrant.value == i + 1
                                ? tokens.accent
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: t.quadrant.value == i + 1
                                    ? tokens.accent
                                    : scheme.outlineVariant),
                          ),
                          child: Text(
                            _qMoveLabels[i],
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: t.quadrant.value == i + 1
                                    ? Colors.white
                                    : scheme.onSurfaceVariant),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // 关联信息行（原型 text-xs space-y-2）
            _InfoRow(label: '子任务', value: '—'),
            _InfoRow(
                label: '计划时间块',
                value: planBlock ?? '未设置',
                valueColor: planBlock != null ? tokens.accent : null,
                bold: planBlock != null),
            _InfoRow(
                label: '实际耗时',
                value: t.isPomo ? '番茄结束后自动入账' : '手动回填（番茄钟自动 · V1.x）'),
            _InfoRow(label: '关联目标', value: '—'),
            if (t.note != null && t.note!.isNotEmpty)
              _InfoRow(label: '备注', value: t.note!),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    foregroundColor: scheme.onSurface),
                child: const Text('关闭'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.valueColor, this.bold = false});

  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
                  color: valueColor ?? scheme.onSurface)),
        ],
      ),
    );
  }
}

