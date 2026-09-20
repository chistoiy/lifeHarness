import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/cal_event.dart';
import '../../domain/category.dart';
import '../../domain/event_repository.dart';
import '../../domain/time_block.dart';
import '../calendar_providers.dart';
import 'event_sheet.dart';

/// 统一事件详情弹层（V1.19 · 任意视图任意状态：查看/开始/结束/编辑/删除）。
/// 修复"完成即失联"：已完成事件保持可编辑/删除，删除同步五视图与时间账本。
Future<void> showEventDetailSheet(BuildContext context, WidgetRef ref, CalEvent e) {
  return showModalBottomSheet(
    context: context,
    builder: (_) => _EventDetail(e: e),
  );
}

class _EventDetail extends ConsumerWidget {
  const _EventDetail({required this.e});
  final CalEvent e;

  static String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (e.status) {
      EventStatus.planning => ('计划中', tokens.accent),
      EventStatus.active => ('进行中', const Color(0xFFF43F5E)),
      EventStatus.done => ('已完成', const Color(0xFF10B981)),
    };
    // 原型详情行：🏷 分类 · 备注 · 冲突检测
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    final catName =
        cats.where((c) => c.id == e.catId).map((c) => c.name).firstOrNull;
    final allEvents = ref.watch(eventsProvider).valueOrNull ?? const <CalEvent>[];
    final dayList = allEvents
        .where((x) =>
            x.start.year == e.start.year &&
            x.start.month == e.start.month &&
            x.start.day == e.start.day &&
            x.id != e.id)
        .toList();
    final hasConflict = EventRepository.conflictsOf([e, ...dayList]).isNotEmpty;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(e.title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(8)),
                  child: Text(label,
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: color)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '📅 ${e.start.month}月${e.start.day}日 · '
              '${e.allDay ? '全天' : '${_hm(e.start)} – ${e.end == null ? '' : _hm(e.end!)}'}'
              '${e.crossDay ? ' · 跨天' : ''}'
              '${e.status == EventStatus.done && e.durationMin != null ? ' · 实际 ${e.durationMin} 分钟（回填L1·入L4）' : ''}',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 2),
            Text(
              '🏷 分类：${catName ?? '未分类'} · 备注：— · '
              '冲突检测 ${hasConflict ? '⚠ 有重叠' : '✓ 无冲突'}',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (e.status == EventStatus.planning)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _start(context, ref),
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFF43F5E), minimumSize: const Size.fromHeight(44)),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('▶ 现在就开始'),
                    ),
                  ),
                if (e.status == EventStatus.active)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _end(context, ref),
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFF43F5E), minimumSize: const Size.fromHeight(44)),
                      icon: const Icon(Icons.stop, size: 18),
                      label: const Text('■ 结束'),
                    ),
                  ),
                if (e.status != EventStatus.done) const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await showEventEditSheet(context, ref, e);
                    },
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    child: const Text('✎ 编辑'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _delete(context, ref),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFFECACA)),
                    ),
                    child: const Text('🗑 删除'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        foregroundColor: scheme.onSurfaceVariant),
                    child: const Text('关闭'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('已完成事件同样可查看 / 编辑 / 删除 · 轴/块/日/周四视图与时间账本同步',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(eventRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (await repo.activeEvent() != null) {
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('已有进行中的事项，请先结束当前事项（单活约束）')));
      return;
    }
    await repo.update(e.copyWith(status: EventStatus.active, start: DateTime.now()));
    ref.invalidate(eventsProvider);
    ref.invalidate(activeEventProvider);
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text('▶ 已开始：${e.title} · 做完点悬浮条「■ 结束」')));
  }

  Future<void> _end(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(eventRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ended = await repo.endActive();
    ref.invalidate(eventsProvider);
    ref.invalidate(activeEventProvider);
    navigator.pop();
    if (ended != null) {
      messenger.showSnackBar(SnackBar(
          content: Text('✔ 耗时 ${ended.durationMin} 分钟 · 实际耗时已回填（L1）· 写入时间账本（L4）')));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await ref.read(eventRepositoryProvider).remove(e);
    ref.invalidate(eventsProvider);
    ref.invalidate(activeEventProvider);
    ref.invalidate(dayBlocksProvider(DateTime(e.start.year, e.start.month, e.start.day)));
    navigator.pop();
    messenger.showSnackBar(const SnackBar(content: Text('🗑 已删除 · 四视图与时间账本同步移除')));
  }
}

/// 手动标记块详情（点已标记格）：查看信息 + 取消标记。
Future<void> showBlockDetailSheet(
    BuildContext context, WidgetRef ref, DateTime day, TimeBlock b) {
  return showModalBottomSheet(
    context: context,
    builder: (sheetCtx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('时间块 · ${b.catName}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              '${(b.startMin ~/ 60).toString().padLeft(2, '0')}:${(b.startMin % 60).toString().padLeft(2, '0')}'
              ' - ${(b.endMin ~/ 60).clamp(0, 23).toString().padLeft(2, '0')}:${(b.endMin % 60).toString().padLeft(2, '0')}'
              ' · ${b.endMin - b.startMin} 分钟${b.note == null ? '' : ' · ${b.note}'}',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(sheetCtx);
                      final navigator = Navigator.of(sheetCtx);
                      await ref.read(timeBlockDaoProvider).remove(b.id!);
                      ref.invalidate(dayBlocksProvider(day));
                      navigator.pop();
                      messenger.showSnackBar(const SnackBar(content: Text('标记已取消，格子恢复空闲（四视图同步）')));
                    },
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        foregroundColor: const Color(0xFFEF4444),
                        side: const BorderSide(color: Color(0xFFFECACA))),
                    child: const Text('取消标记'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    child: const Text('关闭'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('重新标记：滑选该段后点右侧新分类即可拆分覆盖',
                style: TextStyle(fontSize: 9.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    ),
  );
}
