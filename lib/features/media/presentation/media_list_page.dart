import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/load_error_state.dart';
import '../data/media_repo_list.dart';
import '../domain/media_item.dart';
import '../domain/media_list.dart';
import 'media_list_sheets.dart';
import 'media_providers.dart';
import 'widgets/media_card.dart';

/// 影音单详情面（原型 `m-list` · 路由 `/media/list/:id` · 批8b）。
///
/// `id` 两态：`auto`＝年度底稿（成员动态求得·整面只读——无移出、无添加、
/// 无导出、无改名铅笔，仅分享在场）；数字＝手动单（拖拽重排当场落 pos、
/// 行内移出、＋添加条目、导出 MD 直落分享弹层 MD 档）。
class MediaListPage extends ConsumerWidget {
  const MediaListPage({super.key, required this.listId});

  final String listId;

  bool get _isYear => listId == 'auto';

  MediaList? _rowOf(MediaListsBundle b) => _isYear
      ? b.yearRow
      : b.lists.where((l) => '${l.id}' == listId).firstOrNull;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundle = ref.watch(mediaListsBundleProvider);
    final row = bundle.valueOrNull == null ? null : _rowOf(bundle.value!);
    return Scaffold(
      appBar: AppBar(
        title: Text(row?.name ?? '影音单',
            key: const ValueKey('ml-title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        actions: [
          if (!_isYear)
            IconButton(
              key: const ValueKey('ml-rename'),
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () async {
                final r = row;
                if (r == null) return;
                final c = ProviderScope.containerOf(context, listen: false);
                final name = await showMediaListRenameSheet(context, r);
                if (name == null) return;
                await c.read(mediaRepositoryProvider).renameList(r.id, name);
                final t = c.read(mediaTickProvider.notifier);
                t.state = t.state + 1;
              },
            ),
        ],
      ),
      body: bundle.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => LoadErrorBanner(
          title: '这张单没加载出来',
          error: e,
          onRetry: () => ref.invalidate(mediaListsBundleProvider),
        ),
        data: (b) {
          final r = _rowOf(b);
          if (r == null) {
            return const Center(child: Text('这张单不在了'));
          }
          final items = _isYear ? b.year : b.of(r);
          return Column(
            children: [
              Expanded(
                child: _isYear
                    ? ListView(
                        key: const ValueKey('ml-year-list'),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        children: [
                          for (final x in items) _row(context, ref, b, r, x, year: true),
                          if (items.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 14),
                              child: Text('今年还没有完结的条目',
                                  style: TextStyle(fontSize: 11)),
                            ),
                        ],
                      )
                    : ReorderableListView(
                        key: const ValueKey('ml-reorder'),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        onReorder: (oldIndex, newIndex) async {
                          // Material 口径：newIndex 按「旧列表插入位」给，落在被挪项之后要退一格。
                          var to = newIndex;
                          if (to > oldIndex) to -= 1;
                          final ids = items.map((x) => x.id).toList();
                          final moved = ids.removeAt(oldIndex);
                          ids.insert(to, moved);
                          final repo = ref.read(mediaRepositoryProvider);
                          await repo.setMembers(r.id, ids);
                          final t = ref.read(mediaTickProvider.notifier);
                          t.state = t.state + 1;
                        },
                        children: [
                          for (final x in items) _row(context, ref, b, r, x),
                          if (items.isEmpty)
                            const Padding(
                              key: ValueKey('ml-empty'),
                              padding: EdgeInsets.only(top: 14),
                              child: Text('这张单还是空的 · 点下面添加',
                                  style: TextStyle(fontSize: 11)),
                            ),
                        ],
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Row(
                  children: [
                    if (!_isYear) ...[
                      TextButton(
                        key: const ValueKey('ml-add'),
                        onPressed: () {
                          final c =
                              ProviderScope.containerOf(context, listen: false);
                          showMediaListAddItemSheet(context, c, r);
                        },
                        child: const Text('＋ 添加条目'),
                      ),
                      TextButton(
                        key: const ValueKey('ml-export'),
                        onPressed: () =>
                            _share(context, r, items, md: true, year: false),
                        child: const Text('导出 MD'),
                      ),
                    ],
                    TextButton(
                      key: const ValueKey('ml-share'),
                      onPressed: () =>
                          _share(context, r, items, md: false, year: _isYear),
                      child: const Text('分享长图'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  key: const ValueKey('ml-stat'),
                  mdsShareSum(items),
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontFeatures: kMdsShareTabular,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _share(BuildContext context, MediaList row, List<MediaItem> items,
      {required bool md, required bool year}) {
    showMediaListShareSheet(
      context,
      name: row.name,
      typeLine: year ? mdsYearTypeLine(DateTime.now().year) : row.typeLabel,
      items: items,
      year: year,
      md: md,
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, MediaListsBundle b, MediaList row,
      MediaItem x,
      {bool year = false}) {
    final scheme = Theme.of(context).colorScheme;
    final e = x.endedAt;
    final d = e == null ? null : DateTime.fromMillisecondsSinceEpoch(e);
    final dateTxt = d == null
        ? ''
        : ' · ${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return ListTile(
      key: ValueKey('ml-mem-${x.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: SizedBox(
        width: 34,
        height: 46,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: MdsCoverArt(item: x, monoSize: 16),
        ),
      ),
      title: Text(x.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
      subtitle: Text('${x.kind} · ${x.state}$dateTxt',
          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
      trailing: year
          ? Text('底稿只读',
              style: TextStyle(
                  fontSize: 9.5,
                  color: scheme.onSurfaceVariant.withValues(alpha: .6)))
          : TextButton(
              key: ValueKey('ml-remove-${x.id}'),
              onPressed: () async {
                final ids = b
                    .of(row)
                    .map((m) => m.id)
                    .where((i) => i != x.id)
                    .toList();
                final repo = ref.read(mediaRepositoryProvider);
                await repo.setMembers(row.id, ids);
                final t = ref.read(mediaTickProvider.notifier);
                t.state = t.state + 1;
              },
              child: const Text('移出', style: TextStyle(fontSize: 10.5)),
            ),
    );
  }
}
