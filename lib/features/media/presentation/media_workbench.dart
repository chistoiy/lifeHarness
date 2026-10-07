import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/media_item.dart';
import 'media_providers.dart';
import 'widgets/media_card.dart';

/// 记录页·影音游 tab（计划 §〇 S-01 的批2 落点）：真实影音架入口＋四类在册计数
/// ＋最近四条俯瞰（原型 #recMedia「桌面俯瞰」同段）。
///
/// 今日时长环/名场面复习两块分属计时批与笔记批，这里不留假读数占位。
class MediaWorkbench extends ConsumerWidget {
  const MediaWorkbench({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(mediaKindCountsProvider).valueOrNull ?? const {};
    final recent = ref.watch(mediaRecentProvider).valueOrNull ?? const [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        // 影音架入口（点=直达架面，管理动作都在那边）
        Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('media-open-shelf'),
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.push('/media/shelf'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    mdsKindIcon(MediaItem.kMovie),
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '影音架',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '在册 ${counts['all'] ?? 0}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontFeatures: kMediaTabular,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        // 四类直达（角标＝该类在册条数，与架面 chip 同源）
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final k in MediaItem.kinds)
              ActionChip(
                key: ValueKey('media-kind-$k'),
                avatar: Icon(mdsKindIcon(k), size: 16),
                label: Text('${MediaItem.labelOf(k)} ${counts[k] ?? 0}'),
                onPressed: () => context.push('/media/shelf?kind=$k'),
              ),
          ],
        ),
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '桌面俯瞰 · 最近四条',
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 172,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final x in recent)
                  SizedBox(
                    width: 106,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: MediaItemCard(
                        item: x,
                        onTap: () => context.push('/media/shelf?kind=${x.kind}'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
