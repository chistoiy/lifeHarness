import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/load_error_state.dart';
import '../data/media_repo_list.dart';
import '../domain/media_item.dart';
import 'media_list_sheets.dart';
import 'media_providers.dart';

/// 影音单列表面（原型 `m-lists` · 路由 `/media/lists` · 批8b）。
///
/// 瓦片＝年度底稿置顶（合成行·零落库）＋手动单按建单序；读数＝「n 条 · x.x h」
/// 与详情面同一 bundle 出口（一 tick 一次全取＝整屏同帧，不逐瓦片错峰跳数）。
class MediaListsPage extends ConsumerWidget {
  const MediaListsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundle = ref.watch(mediaListsBundleProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('影音单'),
        actions: [
          IconButton(
            key: const ValueKey('mls-new'),
            icon: const Icon(Icons.add),
            onPressed: () async {
              final c = ProviderScope.containerOf(context, listen: false);
              final picked = await showMediaListNewSheet(context);
              if (picked == null) return;
              final id = await c
                  .read(mediaRepositoryProvider)
                  .createList(picked.$1, picked.$2);
              final t = c.read(mediaTickProvider.notifier);
              t.state = t.state + 1;
              if (!context.mounted) return;
              context.push('/media/list/$id');
            },
          ),
        ],
      ),
      body: bundle.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => LoadErrorBanner(
          title: '影音单没加载出来',
          error: e,
          onRetry: () => ref.invalidate(mediaListsBundleProvider),
        ),
        data: (b) => ListView(
          key: const ValueKey('mls-list'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _tile(
              context,
              keyId: 'auto',
              name: b.yearRow.name,
              typeLabel: '年度底稿',
              items: b.year,
              sub: '本年度',
              onTap: () => context.push('/media/list/auto'),
            ),
            for (final l in b.lists)
              _tile(
                context,
                keyId: '${l.id}',
                name: l.name,
                typeLabel: l.typeLabel,
                items: b.of(l),
                sub: l.note,
                onTap: () => context.push('/media/list/${l.id}'),
              ),
            if (b.lists.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: Text('还没有手动单 · 点右上角 ＋ 建一张',
                    style: TextStyle(fontSize: 11)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required String keyId,
    required String name,
    required String typeLabel,
    required List<MediaItem> items,
    required String? sub,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final min = items.fold<int>(0, (a, x) => a + x.durationMin);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        key: ValueKey('mls-tile-$keyId'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Text(typeLabel,
                        style: const TextStyle(fontSize: 9)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('${items.length} 条 · ${(min / 60).toStringAsFixed(1)} h',
                  style: TextStyle(
                      fontSize: 10.5,
                      color: scheme.onSurfaceVariant,
                      fontFeatures: kMdsShareTabular)),
              if (sub != null && sub.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10, color: scheme.onSurfaceVariant)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
