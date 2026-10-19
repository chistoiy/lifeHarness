import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/widgets/grad_fab.dart';
import '../../../shared/linkage/mindmap_mounts.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../data/mindmap_dao.dart';
import '../domain/md_parse.dart';
import '../domain/mindmap_models.dart';
import 'mindmap_node_sheet.dart' show showMmNodeSheet;
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
  List<MindmapFolder> _folders = const [];
  bool _loading = true;

  /// 文件夹筛选（批2 F4-4）：null＝全部；-1＝未归类；其余＝文件夹 id。
  int? _filter;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final v = await _dao.listLive();
    final f = await _dao.listFolders();
    if (!mounted) return;
    setState(() {
      _maps = v;
      _folders = f;
      _loading = false;
    });
  }

  /// 归入/移出文件夹（行菜单二级选择）。
  Future<void> _assignFolder(Mindmap m) async {
    final r = await showModalBottomSheet<int?>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bc) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              key: const ValueKey('mm-assign-none'),
              dense: true,
              leading: const Icon(Icons.folder_off_outlined, size: 20),
              title: const Text('移出文件夹', style: TextStyle(fontSize: 14)),
              onTap: () => Navigator.pop(bc, -1),
            ),
            for (final f in _folders)
              ListTile(
                key: ValueKey('mm-assign-${f.id}'),
                dense: true,
                leading: const Icon(Icons.folder_outlined, size: 20),
                title: Text(f.title, style: const TextStyle(fontSize: 14)),
                trailing: m.folderId == f.id
                    ? Icon(Icons.check, size: 18, color: cs0(context).primary)
                    : null,
                onTap: () => Navigator.pop(bc, f.id),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (r == null || !mounted || m.id == null) return;
    await _dao.setMapFolder(m.id!, r == -1 ? null : r);
    ref.read(mindmapTickProvider.notifier).state++;
    await _reload();
  }

  ColorScheme cs0(BuildContext c) => Theme.of(c).colorScheme;

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
      (key: 'folder', icon: Icons.folder_outlined, label: '归入文件夹', enabled: true),
      (key: 'copy', icon: Icons.copy_outlined, label: '复制', enabled: true),
      (key: 'del', icon: Icons.delete_outlined, label: '删除导图', enabled: true),
    ]);
    if (key == null || !mounted || m.id == null) return;
    switch (key) {
      case 'folder':
        await _assignFolder(m);
      case 'rename':
        final r = await showMmNodeSheet(
          context,
          headline: '重命名导图',
          initialTitle: m.title,
        );
        if (r != null) {
          await _dao.renameMap(m.id!, r.title);
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
    // 文件夹筛选（null=全部 / -1=未归类 / 文件夹 id）。
    final shown = _filter == null
        ? _maps
        : _maps
            .where((e) =>
                _filter == -1
                    ? e.$1.folderId == null
                    : e.$1.folderId == _filter)
            .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('思维导图'),
        actions: [
          IconButton(
            key: const ValueKey('mm-folders-btn'),
            tooltip: '文件夹',
            onPressed: () async {
              await showMmFolderSheet(context, _dao);
              await _reload();
            },
            icon: const Icon(Icons.folder_outlined, size: 21),
          ),
        ],
      ),
      // 日记批2d：原生 `FloatingActionButton` 在 M3 下是 16px 圆角**方块底**
      // ＋ `primaryContainer` 实心底色（用户报障「加号带一块正方形底纹」即此）。
      // 统一走 `GradFab` 圆球。
      floatingActionButton: GradFab(
        key: const ValueKey('mm-new-fab'),
        tooltip: '新建导图',
        icon: const Icon(Icons.add, color: Colors.white, size: 26),
        onTap: () => _newMapFlow(),
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
              : Column(
                  children: [
                    // 文件夹筛选条（有文件夹或已归入才显；空态不占位）。
                    if (_folders.isNotEmpty ||
                        _maps.any((e) => e.$1.folderId != null))
                      SizedBox(
                        key: const ValueKey('mm-folder-filter'),
                        height: 44,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          children: [
                            _filterChip(null, '全部'),
                            _filterChip(-1, '未归类'),
                            for (final f in _folders)
                              _filterChip(f.id!, f.title),
                          ],
                        ),
                      ),
                    Expanded(
                      child: shown.isEmpty
                          ? Center(
                              child: Text('这个筛选下没有导图',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: cs.onSurfaceVariant)))
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 88),
                              itemCount: shown.length,
                              itemBuilder: (context, i) {
                                final (m, cnt) = shown[i];
                                return ListTile(
                                  key: ValueKey('mm-row-${m.id}'),
                                  leading: Icon(Icons.account_tree_outlined,
                                      size: 20, color: cs.onSurfaceVariant),
                                  title: Text(m.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600)),
                                  subtitle: Text(
                                      '$cnt 个节点 · ${_stamp(m.updatedAt)}',
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          color: cs.onSurfaceVariant)),
                                  trailing: IconButton(
                                    key: ValueKey('mm-row-more-${m.id}'),
                                    icon: const Icon(Icons.more_vert,
                                        size: 20),
                                    onPressed: () => _rowMenu(m),
                                  ),
                                  onTap: () => context.push(
                                      '/mindmap/canvas?id=${m.id}'),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _filterChip(int? value, String label) {
    final cs = Theme.of(context).colorScheme;
    final on = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        key: ValueKey('mm-filter-${value ?? 'all'}'),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: on,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => setState(() => _filter = value),
        labelPadding: const EdgeInsets.symmetric(horizontal: 10),
        backgroundColor: cs.surfaceContainerHighest.withValues(alpha: .5),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
