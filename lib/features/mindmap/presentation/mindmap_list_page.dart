import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/linkage/mindmap_mounts.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../data/mindmap_dao.dart';
import '../domain/md_parse.dart';
import '../domain/mindmap_models.dart';
import 'mindmap_providers.dart';
import 'mindmap_sheets.dart';

/// 导图列表屏（原型 mm-list）：全部在册图（标题＋节点数＋更新于）＋空态＋
/// 新建三起点（空白 / 从 md 笔记 / 从收集箱，F1-1）。行 tap 进画布；
/// 行内更多＝图管理三件（F2-2 改名 / F2-3 复制 / F2-4 删图进回收站第九类）。
class MindmapListPage extends ConsumerStatefulWidget {
  const MindmapListPage({super.key, this.dao});

  /// 测试注入缝（生产 null＝走 AppDatabase.instance）。
  final MindmapDao? dao;

  @override
  ConsumerState<MindmapListPage> createState() => _MindmapListPageState();
}

class _MindmapListPageState extends ConsumerState<MindmapListPage> {
  late final MindmapDao _dao =
      widget.dao ?? MindmapDao(AppDatabase.instance.db);
  List<(Mindmap, int)> _maps = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final v = await _dao.listLive();
    if (!mounted) return;
    setState(() {
      _maps = v;
      _loading = false;
    });
  }

  Future<void> _newMapFlow() async {
    final r = await _showNewSheet();
    if (r == null || !mounted) return;
    final (name, origin) = r;
    if (origin == 'md') {
      final noteId = await showMmBindSheet(context);
      if (noteId == null || noteId == -1) return;
      final notes = await mmMountableNotes();
      final hit = notes.where((n) => n.id == noteId).toList();
      final src = await mmNoteContentOf(noteId);
      if (!mounted) return;
      final parsed = parseMdOutline(src ?? '');
      final flat = flattenMdTree(parsed.roots);
      // 解析失败降级＝零节点不建图，给人话提示（尼尔森 9）。
      if (flat.isEmpty) {
        _toast('这篇笔记没解析出大纲内容');
        return;
      }
      final ok = await showMmFromMdPreview(context, flat,
          truncated: parsed.truncated);
      if (!ok) return;
      final mapId = await _dao.createMap(
          name.isEmpty ? (hit.isNotEmpty ? hit.first.title : '未命名导图') : name);
      await _insertParsed(mapId, flat);
      ref.read(mindmapTickProvider.notifier).state++;
      await _reload();
      if (mounted) context.push('/mindmap/canvas?id=$mapId');
      return;
    }
    if (origin == 'inbox') {
      final items = await mmPendingInbox();
      if (!mounted) return;
      final picked = await _showInboxPick(items);
      if (picked == null || picked.isEmpty) return;
      final mapId = await _dao.createMap(name.isEmpty ? '收集箱整理' : name);
      // 收集箱起点＝每条目一枚根节点，多根各自成树（C6），不补「中心主题」根。
      for (final (_, text) in picked) {
        await _dao.addNode(
            mapId: mapId,
            parentId: null,
            title:
                text.trim().isEmpty ? '（空条目）' : text.trim().split('\n').first);
      }
      await mmRouteInboxToMindmap(picked.map((e) => e.$1).toList(), mapId);
      if (mounted) {
        ref.read(mindmapTickProvider.notifier).state++;
        await _reload();
        if (!mounted) return;
        context.push('/mindmap/canvas?id=$mapId');
      }
      return;
    }
    // 空白起点：默认建 1 个根节点「中心主题」（可改名，F1-1）。
    final mapId = await _dao.createMap(name.isEmpty ? '未命名导图' : name);
    await _dao.addNode(mapId: mapId, parentId: null, title: '中心主题');
    ref.read(mindmapTickProvider.notifier).state++;
    await _reload();
    if (!mounted) return;
    context.push('/mindmap/canvas?id=$mapId');
  }

  Future<void> _insertParsed(int mapId, List<(String, int)> flat) async {
    // 先序扁平序：按 depth 弹栈挂父（根 depth==0；父＝栈中 depth-1 层最近节点）。
    final stack = <int?>[]; // stack[d] = 该层最近节点 id
    for (final (title, depth) in flat) {
      final parent =
          depth == 0 ? null : (depth - 1 < stack.length ? stack[depth - 1] : null);
      final n = await _dao.addNode(mapId: mapId, parentId: parent, title: title);
      if (stack.length <= depth) stack.length = depth + 1;
      stack[depth] = n.id;
    }
  }

  Future<(String, String)?> _showNewSheet() {
    final ctrl = TextEditingController();
    return showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bc) {
        final cs = Theme.of(bc).colorScheme;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(bc).bottom),
          child: SafeArea(
            child: Padding(
              key: const ValueKey('mm-new-sheet'),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('新建导图',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('mm-new-name'),
                    controller: ctrl,
                    autofocus: true,
                    maxLines: 1,
                    decoration: const InputDecoration(
                        hintText: '导图名称（可留空）', isDense: true),
                  ),
                  const SizedBox(height: 12),
                  for (final (k, icon, label) in const [
                    ('blank', Icons.account_tree_outlined, '空白'),
                    ('md', Icons.article_outlined, '从 md 笔记解析'),
                    ('inbox', Icons.inbox_outlined, '从收集箱条目'),
                  ])
                    ListTile(
                      key: ValueKey('mm-new-$k'),
                      dense: true,
                      leading: Icon(icon, size: 20, color: cs.onSurfaceVariant),
                      title: Text(label, style: const TextStyle(fontSize: 14)),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () =>
                          Navigator.pop(bc, (ctrl.text.trim(), k)),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<List<(int, String)>?> _showInboxPick(List<(int, String)> items) {
    final sel = <int>{};
    return showModalBottomSheet<List<(int, String)>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bc) {
        final cs = Theme.of(bc).colorScheme;
        return StatefulBuilder(
          builder: (bc, setS) => SafeArea(
            child: SizedBox(
              key: const ValueKey('mm-inbox-sheet'),
              height: MediaQuery.sizeOf(bc).height * 0.6,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('从收集箱导入',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  Expanded(
                    child: items.isEmpty
                        ? Center(
                            child: Text('没有待整理条目',
                                style: TextStyle(
                                    fontSize: 13, color: cs.onSurfaceVariant)))
                        : ListView.builder(
                            itemCount: items.length,
                            itemBuilder: (bc, i) {
                              final (id, text) = items[i];
                              final on = sel.contains(id);
                              return CheckboxListTile(
                                key: ValueKey('mm-inbox-item-$id'),
                                dense: true,
                                value: on,
                                title: Text(text,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13.5)),
                                onChanged: (v) => setS(() =>
                                    v == true ? sel.add(id) : sel.remove(id)),
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(bc),
                          child: const Text('取消'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          key: const ValueKey('mm-inbox-ok'),
                          onPressed: sel.isEmpty
                              ? null
                              : () => Navigator.pop(bc, items
                                  .where((e) => sel.contains(e.$1))
                                  .toList()),
                          child: Text('导入 ${sel.length} 条'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _rowMenu(Mindmap m) async {
    final key = await showMmMenu(context, [
      (key: 'rename', icon: Icons.edit_outlined, label: '重命名', enabled: true),
      (key: 'copy', icon: Icons.copy_outlined, label: '复制', enabled: true),
      (key: 'del', icon: Icons.delete_outlined, label: '删除导图', enabled: true),
    ]);
    if (key == null || !mounted || m.id == null) return;
    switch (key) {
      case 'rename':
        final r = await showMmNodeSheet(
          context,
          headline: '重命名导图',
          initialTitle: m.title,
        );
        if (r != null) {
          await _dao.renameMap(m.id!, r.$1);
          ref.read(mindmapTickProvider.notifier).state++;
          await _reload();
        }
      case 'copy':
        await _dao.copyMap(m.id!);
        ref.read(mindmapTickProvider.notifier).state++;
        await _reload();
      case 'del':
        final ok = await lhConfirm(context, '删除导图「${m.title}」？\n将进回收站，30 天内可恢复');
        if (ok) {
          await _dao.trashMap(m.id!);
          ref.read(mindmapTickProvider.notifier).state++;
          await _reload();
        }
    }
  }

  String _toast(String msg) {
    if (!mounted) return msg;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(msg), duration: const Duration(milliseconds: 1600)));
    return msg;
  }

  String _stamp(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '更新于 ${d.year}-${two(d.month)}-${two(d.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('思维导图')),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('mm-new-fab'),
        onPressed: _newMapFlow,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _maps.isEmpty
              ? Center(
                  key: const ValueKey('mm-empty'),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.account_tree_outlined,
                          size: 44, color: cs.onSurfaceVariant),
                      const SizedBox(height: 10),
                      Text('还没有导图，新建一张图开始思考',
                          style: TextStyle(
                              fontSize: 13, color: cs.onSurfaceVariant)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: _maps.length,
                  itemBuilder: (context, i) {
                    final (m, cnt) = _maps[i];
                    return ListTile(
                      key: ValueKey('mm-row-${m.id}'),
                      leading: Icon(Icons.account_tree_outlined,
                          size: 20, color: cs.onSurfaceVariant),
                      title: Text(m.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text('$cnt 个节点 · ${_stamp(m.updatedAt)}',
                          style: TextStyle(
                              fontSize: 11.5, color: cs.onSurfaceVariant)),
                      trailing: IconButton(
                        key: ValueKey('mm-row-more-${m.id}'),
                        icon: const Icon(Icons.more_vert, size: 20),
                        onPressed: () => _rowMenu(m),
                      ),
                      onTap: () => context.push('/mindmap/canvas?id=${m.id}'),
                    );
                  },
                ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
