import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/note_dao.dart';
import '../domain/note.dart';
import 'journal_providers.dart';
import 'widgets/note_tree_drawer.dart';

/// 笔记 tab（原型 recNote · V1.29轮6）：页内搜索移除（全局搜索承接）·
/// 右侧行=排序三方式/📂文件夹树/视图循环；卡片精简=📌标题+时间+两行预览；
/// 左滑=入回收站；长按=批量选择（置顶/移动到/删除）。
class NoteTab extends ConsumerStatefulWidget {
  const NoteTab({super.key});

  @override
  ConsumerState<NoteTab> createState() => _NoteTabState();
}

class _NoteTabState extends ConsumerState<NoteTab> {
  /// 已左滑移除的 id：立即隐藏，避免异步刷新前 Dismissible 重建报错。
  final Set<int> _gone = {};

  static String _timeLabel(DateTime d) {
    final now = DateTime.now();
    final hm = '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return '今天 $hm';
    }
    return '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final filter = ref.watch(noteFilterProvider);
    final notes = (ref.watch(notesProvider).valueOrNull ?? const <Note>[])
        .where((n) => !_gone.contains(n.id))
        .toList();
    final cols = ref.watch(noteViewColsProvider);
    final sel = ref.watch(noteSelProvider);
    final inTrash = filter.folder == kNoteTrash;

    final list = Column(
      children: [
        // V1.29轮6：右侧一行三钮 = 排序 / 文件夹树 / 视图循环
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              PopupMenuButton<NoteSort>(
                key: const ValueKey('note-sort'),
                tooltip: '排序',
                icon: const Icon(Icons.swap_vert, size: 22),
                onSelected: (s) => ref.read(noteFilterProvider.notifier)
                    .state = (folder: filter.folder, sort: s),
                itemBuilder: (_) => [
                  for (final e in const {
                    NoteSort.updated: '最后修改 ↓',
                    NoteSort.created: '创建时间 ↓',
                    NoteSort.title: '标题 A→Z',
                  }.entries)
                    PopupMenuItem(
                      value: e.key,
                      child: Row(
                        children: [
                          Text(e.value,
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color:
                                      e.key == filter.sort ? tokens.accent : null)),
                          if (e.key == filter.sort) ...[
                            const Spacer(),
                            Icon(Icons.check, size: 18, color: tokens.accent),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
              IconButton(
                key: const ValueKey('note-folder'),
                tooltip: '文件夹',
                onPressed: () => showNoteTreeDrawer(context),
                icon: Icon(Icons.folder_outlined,
                    size: 22,
                    color: filter.folder.isEmpty || inTrash
                        ? scheme.onSurfaceVariant
                        : tokens.accent),
              ),
              IconButton(
                key: const ValueKey('note-view'),
                tooltip: cols == 0 ? '切换到卡片' : '切换到列表',
                onPressed: () => ref.read(noteViewColsProvider.notifier).state =
                    cols == 0 ? 2 : (cols >= 4 ? 0 : cols + 1),
                icon: Icon(cols == 0 ? Icons.menu : Icons.grid_view, size: 22),
              ),
            ],
          ),
        ),
        Expanded(
          child: notes.isEmpty
              ? EmptyDashRow(
                  text: inTrash
                      ? '回收站是空的'
                      : filter.folder.isEmpty
                          ? '还没有笔记 · 点右下角 ＋ 开始'
                          : '「${filter.folder}」下还没有笔记',
                  onTap: () => context.push('/note/edit'),
                )
              : cols == 0
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      children: [
                        for (final n in notes)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _card(context, ref, n, inTrash, sel),
                          ),
                        Center(
                          child: Text(
                            inTrash
                                ? '共 ${notes.length} 篇 · 长按可恢复或彻底删除'
                                : '共 ${notes.length} 篇 · 左滑删除 · 长按批量选择',
                            style: TextStyle(
                                fontSize: 10, color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    )
                  : GridView.count(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      crossAxisCount: cols,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: .92,
                      shrinkWrap: true,
                      children: [
                        for (final n in notes) _card(context, ref, n, inTrash, sel),
                      ],
                    ),
        ),
      ],
    );

    if (inTrash || sel.isEmpty) return list;
    // 批量操作条（原型 noteSelBar：已选 N · 置顶 / 移动到 / 删除 / ✕）
    return Column(
      children: [
        Expanded(child: list),
        Container(
          key: const ValueKey('note-sel-bar'),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
              color: tokens.card,
              border: Border(top: BorderSide(color: tokens.cardBorder))),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('已选 ${sel.length}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: tokens.accent)),
                ),
                TextButton(
                    key: const ValueKey('sel-pin'),
                    onPressed: () => _batch(context, ref, sel, 'pin'),
                    child: const Text('📌 置顶', style: TextStyle(fontSize: 12))),
                TextButton(
                    key: const ValueKey('sel-move'),
                    onPressed: () => _batch(context, ref, sel, 'move'),
                    child: const Text('📂 移动到', style: TextStyle(fontSize: 12))),
                TextButton(
                    key: const ValueKey('sel-del'),
                    onPressed: () => _batch(context, ref, sel, 'del'),
                    child: const Text('🗑 删除',
                        style: TextStyle(fontSize: 12, color: Color(0xFFF43F5E)))),
                IconButton(
                    key: const ValueKey('sel-exit'),
                    onPressed: () =>
                        ref.read(noteSelProvider.notifier).state = const {},
                    icon: const Icon(Icons.close, size: 18)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _card(BuildContext context, WidgetRef ref, Note n, bool inTrash,
      Set<int> sel) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final selected = sel.contains(n.id);

    Widget card = GestureDetector(
      key: ValueKey('note-card-${n.id}'),
      onTap: () {
        if (sel.isNotEmpty && !inTrash) {
          _toggleSel(ref, n.id!);
          return;
        }
        context.push('/note/edit', extra: n.id);
      },
      onLongPress: () {
        if (inTrash) {
          _trashActions(context, ref, n);
        } else {
          ref.read(noteSelProvider.notifier).state = {n.id!};
          AppToast.show(context, '批量模式 · 点选卡片可多选');
        }
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: context.cardDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (sel.isNotEmpty && !inTrash) ...[
                  Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      key: ValueKey('note-sel-${n.id}'),
                      size: 18,
                      color: selected
                          ? tokens.accent
                          : scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                ],
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
                        fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 6),
                Text(inTrash ? '删于 ${_timeLabel(n.deletedAt!)}' : _timeLabel(n.updatedAt),
                    style: TextStyle(
                        fontSize: 10, color: scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 6),
            Text(n.preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );

    if (inTrash || sel.isNotEmpty) return card;
    // 左滑入回收站（原型 note-sw：红色 🗑 跟手露出）
    return Dismissible(
      key: ValueKey('note-swipe-${n.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
            color: const Color(0xFFEF4444),
            borderRadius: BorderRadius.circular(tokens.cardRadius)),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) async {
        setState(() => _gone.add(n.id!));
        await ref.read(noteDaoProvider).softDelete(n.id!);
        ref.invalidate(notesProvider);
        ref.invalidate(noteTreeProvider);
        if (context.mounted) AppToast.show(context, '已移入回收站 · 30 天内可恢复');
      },
      child: card,
    );
  }

  void _toggleSel(WidgetRef ref, int id) {
    final cur = {...ref.read(noteSelProvider)};
    cur.contains(id) ? cur.remove(id) : cur.add(id);
    ref.read(noteSelProvider.notifier).state = cur;
  }

  Future<void> _batch(
      BuildContext context, WidgetRef ref, Set<int> sel, String act) async {
    final dao = ref.read(noteDaoProvider);
    final ids = sel.toList();
    if (act == 'move') {
      final folder = await showFolderPickSheet(context, ref);
      if (folder == null) return;
      await dao.setFolderMany(ids, folder);
      if (!context.mounted) return;
      _finishBatch(context, ref, '已移动 ${ids.length} 篇到「$folder」');
      return;
    }
    if (act == 'pin') {
      await dao.setPinnedMany(ids, true);
      if (!context.mounted) return;
      _finishBatch(context, ref, '已置顶 ${ids.length} 篇');
      return;
    }
    await dao.softDeleteMany(ids);
    if (!context.mounted) return;
    _finishBatch(context, ref, '已移入回收站 ${ids.length} 篇 · 30 天内可恢复');
  }

  void _finishBatch(BuildContext context, WidgetRef ref, String msg) {
    ref.read(noteSelProvider.notifier).state = const {};
    ref.invalidate(notesProvider);
    ref.invalidate(noteTreeProvider);
    AppToast.show(context, msg);
  }

  Future<void> _trashActions(
      BuildContext context, WidgetRef ref, Note n) async {
    final dao = ref.read(noteDaoProvider);
    final act = await showModalBottomSheet<String>(
      context: context,
      builder: (bc) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
                title: const Text('♻️ 恢复'),
                onTap: () => Navigator.of(bc).pop('restore')),
            ListTile(
                title: const Text('❌ 彻底删除',
                    style: TextStyle(color: Color(0xFFF43F5E))),
                onTap: () => Navigator.of(bc).pop('purge')),
          ],
        ),
      ),
    );
    if (act == null) return;
    if (act == 'restore') {
      await dao.restore(n.id!);
    } else {
      await dao.purge(n.id!);
    }
    ref.invalidate(notesProvider);
    ref.invalidate(noteTreeProvider);
    if (context.mounted) {
      AppToast.show(context, act == 'restore' ? '已恢复' : '已彻底删除');
    }
  }
}
