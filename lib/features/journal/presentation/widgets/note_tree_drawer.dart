import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/note_folder.dart';
import '../journal_providers.dart';

/// V1.29 批A3 · 文件夹树抽屉（原型 noteTree · Obsidian 形态）：
/// 左滑入 62% 面板；点文件夹=选中当前目录（不关抽屉·自动展开）；
/// 「添加文件夹」建在选中目录下（未选=顶层）；长按节点=重命名/删除；
/// 底部操作条：重命名 / 添加 / 展开折叠 / 关闭。
Future<void> showNoteTreeDrawer(BuildContext context) => showGeneralDialog(
      context: context,
      barrierLabel: '文件夹',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => const _TreeDrawer(),
      transitionBuilder: (_, anim, _, child) => SlideTransition(
        position: Tween(begin: const Offset(-.6, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );

class _TreeDrawer extends ConsumerStatefulWidget {
  const _TreeDrawer();

  @override
  ConsumerState<_TreeDrawer> createState() => _TreeDrawerState();
}

class _TreeDrawerState extends ConsumerState<_TreeDrawer> {
  final Set<int> _open = {};

  void _pick(String folder, {bool hasKids = false, int? id}) {
    ref.read(noteFilterProvider.notifier).state = (folder: folder,
        sort: ref.read(noteFilterProvider).sort,
        asc: ref.read(noteFilterProvider).asc);
    if (hasKids && id != null) _open.add(id);
    setState(() {});
  }

  FolderNode? _find(List<FolderNode> nodes, String name) {
    for (final n in nodes) {
      if (n.name == name) return n;
      final r = _find(n.children, name);
      if (r != null) return r;
    }
    return null;
  }

  Future<void> _add(FolderNode? parent) async {
    final name = await _promptName(context,
        title: parent == null ? '新建文件夹（顶层）' : '在「${parent.name}」下新建');
    if (name == null || name.trim().isEmpty) return;
    await ref.read(noteFolderDaoProvider).create(name, parentId: parent?.id);
    if (parent != null) _open.add(parent.id);
    ref.invalidate(noteFolderListProvider);
    setState(() {});
    if (mounted) {
      AppToast.show(context,
          parent == null ? '已新建文件夹「${name.trim()}」' : '已在「${parent.name}」下新建「${name.trim()}」');
    }
  }

  Future<void> _nodeActions(FolderNode node) async {
    final act = await showModalBottomSheet<String>(
      context: context,
      builder: (bc) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: Text('重命名「${node.name}」'),
                onTap: () => Navigator.of(bc).pop('rename')),
            ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: Color(0xFFF43F5E)),
                title: const Text('删除文件夹'),
                onTap: () => Navigator.of(bc).pop('delete')),
          ],
        ),
      ),
    );
    if (act == null || !mounted) return;
    final dao = ref.read(noteFolderDaoProvider);
    if (act == 'rename') {
      final name = await _promptName(context,
          title: '重命名', initial: node.name);
      if (name == null || name.trim().isEmpty) return;
      await dao.rename(node.id, name);
    } else {
      await dao.deleteTree(node.id);
      final sel = ref.read(noteFilterProvider).folder;
      if (sel == node.name) {
        ref.read(noteFilterProvider.notifier).state = (folder: '',
            sort: ref.read(noteFilterProvider).sort,
            asc: ref.read(noteFilterProvider).asc);
      }
    }
    ref.invalidate(noteFolderListProvider);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tree = ref.watch(noteTreeProvider).valueOrNull ?? const [];
    final total =
        (ref.watch(notesProvider).valueOrNull ?? const []).length;
    final selName = ref.watch(noteFilterProvider).folder;
    final selNode = selName.isEmpty ? null : _find(tree, selName);
    final w = MediaQuery.sizeOf(context).width * .62;

    return SafeArea(
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: w,
          height: double.infinity,
          child: Material(
            color: scheme.surface,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 4, 4),
                  child: Row(
                    children: [
                      const Expanded(
                          child: Text('文件夹',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15))),
                      IconButton(
                          key: const ValueKey('nt-close-hd'),
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, size: 20)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: [
                      _row(context,
                          keyName: 'nt-all',
                          icon: Icons.notes_outlined,
                          label: '全部笔记',
                          count: total,
                          depth: 0,
                          selected: selName == '',
                          onTap: () => _pick('')),
                      ..._nodes(tree, 0),
                      // V1.60 全局回收站：抽屉行改道统一屏并落「笔记」段
                      // （页内垃圾箱视图随本批下架，恢复/彻底删除只在此屏做）。
                      _row(context,
                          keyName: 'nt-trash',
                          icon: Icons.delete_outline,
                          label: '回收站',
                          depth: 0,
                          onTap: () {
                            final router = GoRouter.of(context);
                            Navigator.of(context).pop();
                            router.push('/settings/trash?seg=note');
                          }),
                      _row(context,
                          keyName: 'nt-add',
                          icon: Icons.add,
                          label: '添加文件夹 · ${selNode?.name ?? '顶层'}',
                          depth: 0,
                          onTap: () => _add(selNode)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // 轮11-2：底部操作条恢复线性图标四钮（用户反馈文字钮不如图标直观）。
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                          key: const ValueKey('nt-bt-rename'),
                          tooltip: selNode == null
                              ? '先点选文件夹'
                              : '重命名「${selNode.name}」',
                          onPressed: () => selNode == null
                              ? AppToast.show(context, '先点选文件夹')
                              : _nodeActions(selNode),
                          icon: const Icon(Icons.edit_outlined, size: 20)),
                      IconButton(
                          key: const ValueKey('nt-bt-add'),
                          tooltip: '添加文件夹',
                          onPressed: () => _add(selNode),
                          icon: const Icon(Icons.create_new_folder_outlined,
                              size: 20)),
                      IconButton(
                          key: const ValueKey('nt-bt-expand'),
                          tooltip: '全部展开/折叠',
                          onPressed: () {
                            final all = <int>[];
                            void collect(List<FolderNode> ns) {
                              for (final n in ns) {
                                all.add(n.id);
                                collect(n.children);
                              }
                            }

                            collect(tree);
                            setState(() => _open.addAll(all));
                          },
                          icon: const Icon(Icons.unfold_more, size: 20)),
                      IconButton(
                          key: const ValueKey('nt-bt-close'),
                          tooltip: '关闭',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, size: 20)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _nodes(List<FolderNode> nodes, int depth) => [
        for (final n in nodes) ...[
          _row(context,
              keyName: 'nt-${n.name}',
              icon: Icons.folder_outlined,
              label: n.name,
              count: n.noteCount,
              depth: depth,
              selected: ref.watch(noteFilterProvider).folder == n.name,
              caret: n.children.isNotEmpty
                  ? (_open.contains(n.id)
                      ? Icons.expand_more
                      : Icons.chevron_right)
                  : null,
              onCaret: () => setState(() =>
                  _open.contains(n.id) ? _open.remove(n.id) : _open.add(n.id)),
              onTap: () => _pick(n.name, hasKids: n.children.isNotEmpty, id: n.id),
              onLongPress: () => _nodeActions(n)),
          if (_open.contains(n.id)) ..._nodes(n.children, depth + 1),
        ],
      ];

  Widget _row(BuildContext context,
      {required String keyName,
      required IconData icon,
      required String label,
      int? count,
      int depth = 0,
      bool selected = false,
      IconData? caret,
      VoidCallback? onCaret,
      required VoidCallback onTap,
      VoidCallback? onLongPress}) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: ValueKey(keyName),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        // 轮10-9：行卡圆角化（与弹层条目同语言）。
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(
          color: selected ? tokens.accent.withValues(alpha: .10) : null,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: EdgeInsets.fromLTRB(10.0 + depth * 16, 11, 12, 11),
        child: Row(
          children: [
            SizedBox(
                width: 20,
                child: caret == null
                    ? null
                    : IconButton(
                        key: ValueKey('$keyName-caret'),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        visualDensity: VisualDensity.compact,
                        onPressed: onCaret,
                        icon: Icon(caret, size: 18))),
            Icon(icon,
                size: 17,
                color: selected ? tokens.accent : scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                        color: selected ? tokens.accent : null))),
            if (count != null)
              Text('$count',
                  style: TextStyle(
                      fontSize: 10, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

Future<String?> _promptName(BuildContext context,
    {required String title, String? initial}) =>
    showDialog<String>(
      context: context,
      builder: (bc) => _NameDialog(title: title, initial: initial),
    );

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, this.initial});

  final String title;
  final String? initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _ctl =
      TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        content: TextField(
            key: const ValueKey('nt-name-input'),
            controller: _ctl,
            autofocus: true,
            decoration: const InputDecoration(hintText: '文件夹名称')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消')),
          TextButton(
              key: const ValueKey('nt-name-ok'),
              onPressed: () => Navigator.pop(context, _ctl.text),
              child: const Text('确定')),
        ],
      );
}

/// 「移动到」选择弹层（批量操作 · 原型 sheetNoteMove）：返回目标文件夹名。
Future<String?> showFolderPickSheet(BuildContext context,
    WidgetRef ref) async {
  final tree = ref.read(noteTreeProvider).valueOrNull ?? const [];
  return showModalBottomSheet<String>(
    context: context,
    builder: (bc) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text('移动到文件夹',
                style: TextStyle(fontWeight: FontWeight.w900)),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final (name, depth) in _flatten(tree))
                  ListTile(
                    key: ValueKey('mv-$name'),
                    dense: true,
                    contentPadding: EdgeInsets.only(left: 12.0 + depth * 18),
                    leading: const Icon(Icons.folder_outlined, size: 18),
                    title: Text(name),
                    onTap: () => Navigator.of(bc).pop(name),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

List<(String, int)> _flatten(List<FolderNode> nodes, [int depth = 0]) => [
      for (final n in nodes) ...[(n.name, depth), ..._flatten(n.children, depth + 1)],
    ];
