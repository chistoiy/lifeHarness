import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/media_item.dart';
import 'media_add_sheet.dart';
import 'media_progress_sheet.dart';
import 'media_providers.dart';
import 'media_sheets.dart';

/// 条目操作弹层（LH-S34 · 原型 `m-sheet-ops`）：详情页顶栏「更多」与架面长按共用的动作面。
///
/// 原型那列动作里，**影音单/轨迹/导出属后续批次**（批4 统计与影音单），
/// 本批不铺假入口：只给真做得动的五项，做不了的整条不出现（不是置灰骗点）。
Future<void> showMediaOpsSheet(
  BuildContext context,
  WidgetRef ref,
  MediaItem item,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _OpsSheet(item: item),
  );
}

class _OpsSheet extends ConsumerWidget {
  const _OpsSheet({required this.item});

  final MediaItem item;

  void _bump(WidgetRef ref) {
    final t = ref.read(mediaTickProvider.notifier);
    t.state = t.state + 1;
  }

  Future<void> _markDone(BuildContext context, WidgetRef ref, String state) async {
    await ref
        .read(mediaRepositoryProvider)
        .moveState(item.id, item.kind, state);
    _bump(ref);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    AppToast.show(context, '已标记「$state」');
  }

  Future<void> _trash(BuildContext context, WidgetRef ref) async {
    final ok = await lhConfirm(
      context,
      '把「${item.title}」移入回收站？7 天内可从「我的 · 回收站」找回。',
    );
    if (!ok || !context.mounted) return;
    await ref.read(mediaRepositoryProvider).softDelete([item.id]);
    _bump(ref);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    AppToast.show(context, '已移入回收站');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final done = (MediaItem.states[item.kind] ?? const [])
        .firstWhere(
          (s) => s == '看完' || s == '追完' || s == '通关',
          orElse: () => '',
        );
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            item.title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          for (final (label, run) in <(String, Future<void> Function())>[
            (
              '编辑条目信息',
              () async {
                Navigator.of(context).pop();
                await showMediaAddSheet(context, ref, existing: item);
              },
            ),
            (
              '改分区（当前：${item.state}）',
              () async {
                Navigator.of(context).pop();
                await showMediaBulkStateSheet(context, ref, [item.id], item.kind);
              },
            ),
            if (done.isNotEmpty && item.state != done)
              (
                '标记「$done」',
                () => _markDone(context, ref, done),
              ),
            (
              '记进度',
              () async {
                Navigator.of(context).pop();
                await showMediaProgressSheet(context, ref, item);
              },
            ),
            (
              '条目资料',
              () async {
                Navigator.of(context).pop();
                if (!context.mounted) return;
                context.push('/media/item/${item.id}/info');
              },
            ),
            (
              '计时明细',
              () async {
                Navigator.of(context).pop();
                if (!context.mounted) return;
                context.push('/media/item/${item.id}/sessions');
              },
            ),
            (
              '移入回收站',
              () => _trash(context, ref),
            ),
          ])
            InkWell(
              key: ValueKey('mds-ops-$label'),
              borderRadius: BorderRadius.circular(12),
              onTap: run,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: label == '移入回收站' ? scheme.error : scheme.onSurface,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
