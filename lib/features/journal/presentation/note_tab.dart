import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/note_dao.dart';
import '../domain/note.dart';
import 'journal_providers.dart';

/// 笔记 tab（原型 recNote · M1 批1a）：搜索+排序+写笔记 · 文件夹/回收站 chips ·
/// 笔记卡（📌置顶+预览+文件夹·字数·日期）· 长按=置顶/归档/回收站（回收站内=恢复/彻底删除）。
class NoteTab extends ConsumerWidget {
  const NoteTab({super.key});

  static String _md(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _setFilter(WidgetRef ref,
          {String? folder, String? query, NoteSort? sort}) =>
      ref.read(noteFilterProvider.notifier).state = (
        folder: folder ?? ref.read(noteFilterProvider).folder,
        query: query ?? ref.read(noteFilterProvider).query,
        sort: sort ?? ref.read(noteFilterProvider).sort,
      );

  Future<void> _longPressActions(
      BuildContext context, WidgetRef ref, Note n) async {
    final inTrash = ref.read(noteFilterProvider).folder == kNoteTrash;
    final dao = ref.read(noteDaoProvider);
    final act = await showModalBottomSheet<String>(
      context: context,
      builder: (bc) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!inTrash) ...[
              ListTile(
                  title: Text(n.pinned ? '📌 取消置顶' : '📌 置顶'),
                  onTap: () => Navigator.of(bc).pop('pin')),
              ListTile(
                  title: const Text('🗄 归档'),
                  onTap: () => Navigator.of(bc).pop('archive')),
              ListTile(
                  title: const Text('🗑 移入回收站'),
                  onTap: () => Navigator.of(bc).pop('trash')),
            ] else ...[
              ListTile(
                  title: const Text('♻️ 恢复'),
                  onTap: () => Navigator.of(bc).pop('restore')),
              ListTile(
                  title: const Text('❌ 彻底删除',
                      style: TextStyle(color: Color(0xFFF43F5E))),
                  onTap: () => Navigator.of(bc).pop('purge')),
            ],
          ],
        ),
      ),
    );
    if (act == null) return;
    switch (act) {
      case 'pin':
        await dao.setPinned(n.id!, !n.pinned);
      case 'archive':
        await dao.setArchived(n.id!, true);
      case 'trash':
        await dao.softDelete(n.id!);
      case 'restore':
        await dao.restore(n.id!);
      case 'purge':
        await dao.purge(n.id!);
    }
    ref.invalidate(notesProvider);
    ref.invalidate(noteFoldersProvider);
    if (context.mounted) {
      AppToast.show(
          context,
          switch (act) {
            'pin' => n.pinned ? '已取消置顶' : '已置顶',
            'archive' => '已归档',
            'trash' => '已移入回收站',
            'restore' => '已恢复',
            _ => '已彻底删除',
          });
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final filter = ref.watch(noteFilterProvider);
    final notes = ref.watch(notesProvider).valueOrNull ?? const <Note>[];
    final folders = ref.watch(noteFoldersProvider).valueOrNull ?? const [];
    final inTrash = filter.folder == kNoteTrash;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 42,
                child: TextField(
                  key: const ValueKey('note-search'),
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: '搜索标题或全文…',
                    prefixIcon:
                        const Text('🔍', style: TextStyle(fontSize: 13)),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 34, minHeight: 34),
                    filled: true,
                    fillColor: scheme.onSurface.withValues(alpha: .05),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (v) => _setFilter(ref, query: v),
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('note-sort'),
              onPressed: () {
                final next = NoteSort.values[
                    (filter.sort.index + 1) % NoteSort.values.length];
                _setFilter(ref, sort: next);
                AppToast.show(
                    context,
                    '排序：'
                    '${switch (next) {
                      NoteSort.updated => '更新时间 ↓',
                      NoteSort.created => '创建时间 ↓',
                      NoteSort.words => '字数 ↓',
                    }}');
              },
              icon: const Icon(Icons.swap_vert, size: 22),
            ),
            GestureDetector(
              key: const ValueKey('note-new'),
              onTap: () => context.push('/note/edit'),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                    gradient: tokens.gradient,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: tokens.cardShadow),
                child: const Text('✎ 写笔记',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              PillChip(
                  key: const ValueKey('note-f-all'),
                  label: '全部',
                  selected: filter.folder == '',
                  onTap: () => _setFilter(ref, folder: '')),
              for (final f in folders) ...[
                const SizedBox(width: 8),
                PillChip(
                    key: ValueKey('note-f-$f'),
                    label: f,
                    selected: filter.folder == f,
                    onTap: () => _setFilter(ref, folder: f)),
              ],
              const SizedBox(width: 8),
              PillChip(
                  key: const ValueKey('note-f-trash'),
                  label: '🗑 回收站',
                  selected: inTrash,
                  onTap: () => _setFilter(ref, folder: kNoteTrash)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (notes.isEmpty)
          EmptyDashRow(
            text: inTrash
                ? '回收站是空的'
                : filter.query.isNotEmpty
                    ? '没有匹配「${filter.query}」的笔记'
                    : '还没有笔记 · 点「✎ 写笔记」开始',
            onTap: () => context.push('/note/edit'),
          )
        else
          for (final n in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                key: ValueKey('note-card-${n.id}'),
                onTap: () => context.push('/note/edit', extra: n.id),
                onLongPress: () => _longPressActions(context, ref, n),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: context.cardDecoration,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (n.pinned && !inTrash) ...[
                            const Text('📌', style: TextStyle(fontSize: 12)),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              n.title.isEmpty ? '未命名笔记' : n.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (n.kind == 'md')
                            Text('MD',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: tokens.accent)),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(n.preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              height: 1.6,
                              color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 7),
                      Text(
                        '${n.folder ?? '无分类'} · ${n.wordCount} 字 · '
                        '${inTrash ? '删于 ${_md(n.deletedAt!)}' : _md(n.updatedAt)}',
                        style: TextStyle(
                            fontSize: 10, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            inTrash
                ? '共 ${notes.length} 篇 · 长按可恢复或彻底删除'
                : '共 ${notes.length} 篇 · 长按列表项可置顶 / 归档 / 移入回收站',
            style:
                TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
