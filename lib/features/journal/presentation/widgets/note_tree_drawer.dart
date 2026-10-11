import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/platform/saf_tree.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/note_folder.dart';
import '../journal_providers.dart';
import '../note_local_import.dart';

/// 左边缘右滑开文件树（2026-10-11 真机反馈轮·产品定「左边缘右滑开树」）。
///
/// 为什么用 `Listener` 而不挂 `GestureDetector`：卡片那层的 `Dismissible`（左滑＝移入回收站）
/// 与本手势同为横向拖拽识别器，进了手势竞技场必然是**更深的子级赢**——那样边缘手势在卡片上
/// 永远不触发。`Listener` 不参与竞技场，只观察原始指针：起点贴左边缘、累计右移够距且横向
/// 位移大于纵向（避开竖滚列表误触）才开一次，抬手前不再重复触发。
class EdgeSwipeToOpen extends StatefulWidget {
  const EdgeSwipeToOpen(
      {super.key,
      required this.onOpen,
      required this.child,
      this.edgeZone = 28,
      this.triggerPx = 56});

  final VoidCallback onOpen;
  final Widget child;

  /// 起点判定带（逻辑像素）：Android 系统「边缘返回」也吃这段，若机型冲突可调窄。
  final double edgeZone;

  /// 触发所需的累计右移量。
  final double triggerPx;

  @override
  State<EdgeSwipeToOpen> createState() => _EdgeSwipeToOpenState();
}

class _EdgeSwipeToOpenState extends State<EdgeSwipeToOpen> {
  int? _pid;
  bool _armed = false, _fired = false;
  double _dx = 0, _dy = 0;

  void _reset() => _pid = null;

  void _onPointer(PointerEvent e) {
    if (e is PointerDownEvent) {
      _pid = e.pointer;
      _armed = e.position.dx <= widget.edgeZone;
      _fired = false;
      _dx = 0;
      _dy = 0;
    } else if (e is PointerMoveEvent && e.pointer == _pid && _armed && !_fired) {
      _dx += e.delta.dx;
      _dy += e.delta.dy.abs();
      if (_dx >= widget.triggerPx && _dx > _dy) {
        _fired = true;
        widget.onOpen();
      }
    } else if ((e is PointerUpEvent || e is PointerCancelEvent) &&
        e.pointer == _pid) {
      _reset();
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: _onPointer,
        onPointerMove: _onPointer,
        onPointerUp: _onPointer,
        onPointerCancel: _onPointer,
        child: widget.child,
      );
}

/// V1.29 批A3 · 文件夹树抽屉（原型 noteTree · Obsidian 形态）：
/// 左边缘右滑或右上文件夹钮开 62% 面板；点文件夹=选中当前目录（不关抽屉·自动展开）；
/// 点树外内容区＝收起（真机反馈轮显式钉死 barrierDismissible）；
/// 「添加文件夹」建在选中目录下（未选=顶层）；长按节点=重命名/删除，
/// 长按本地/导出挂载节点=移除挂载（V1.64 批2）；底部操作条：重命名/添加/展开折叠/关闭。
Future<void> showNoteTreeDrawer(BuildContext context) => showGeneralDialog(
      context: context,
      barrierLabel: '文件夹',
      barrierColor: Colors.black54,
      // 真机反馈轮：点树外（右侧内容区）必收起——写死显式值，防默认值漂移。
      barrierDismissible: true,
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
    // V1.64 批2 N-1c（工单 §1.2 · 拍板 H）：挂载节点（本地导入的目录／导出目录）
    // 长按＝进「移除挂载」确认层；手建夹维持原「重命名／删除」菜单。
    if (node.folder.isMount) return _unmount(node);
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
      final ok = await dao.deleteTree(node.id);
      // 批1 的 DAO 守卫原本静默吞掉「系统打开」的删除请求＝点了没反应；批2 补可见提示。
      if (!ok && mounted) {
        AppToast.show(context, '「$kSystemOpenFolder」是系统夹 · 不能删除');
      }
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

  /// 移除挂载（N-1c）：确认层后果三行现算；确认后只摘挂载行，笔记与磁盘原件都不动。
  Future<void> _unmount(FolderNode node) async {
    final dao = ref.read(noteFolderDaoProvider);
    final notes = ref.read(noteDaoProvider);
    final ids = await dao.subtreeIds(node.id);
    final keep = await mountNoteCount(dao, notes, node.id);
    if (!mounted) return;
    await showNoteUnmountSheet(context,
        folder: node.folder,
        childCount: ids.length - 1,
        keepCount: keep,
        onConfirm: () async {
          final removed =
              await unmountFolder(folders: dao, notes: notes, folder: node.folder);
          if (ref.read(noteFilterProvider).folder == node.name) {
            ref.read(noteFilterProvider.notifier).state = (folder: '',
                sort: ref.read(noteFilterProvider).sort,
                asc: ref.read(noteFilterProvider).asc);
          }
          ref.invalidate(noteFolderListProvider);
          ref.invalidate(notesProvider);
          ref.invalidate(noteLocalFoldersProvider);
          setState(() {});
          if (mounted && removed > 0) {
            AppToast.show(context,
                '已移除挂载「${node.name}」 · $keep 条笔记保留在库 · 原文件不动');
          }
        });
  }

  /// 「导入本地」面板（N-1 目录档／文件档）；选择器与导入都在回调里跑。
  Future<void> _importLocal() async {
    final dao = ref.read(noteDaoProvider);
    final folders = ref.read(noteFolderDaoProvider);
    await showNoteLocalImportSheet(context, onRun: (kind) async {
      final LocalImportReport? r;
      try {
        if (kind == 'dir') {
          final treeUri = await safPickTree();
          if (treeUri == null) return null; // 用户在系统选择器里取消＝不出提示
          r = await importLocalTree(
              notes: dao,
              folders: folders,
              root: await safListTree(treeUri),
              readText: safReadText);
        } else {
          final docs = await safPickFiles();
          if (docs.isEmpty) return null;
          r = await importLocalFiles(
              notes: dao,
              folders: folders,
              docs: docs,
              currentFolder: ref.read(noteFilterProvider).folder,
              readText: safReadText);
        }
      } catch (_) {
        // catch-ok: 授权失效/provider 拒绝都要可见（工单 §3「点了必须有看得见的变化」）。
        if (mounted) AppToast.show(context, '读不到所选内容（授权可能已失效）');
        return null;
      }
      ref.invalidate(noteFolderListProvider);
      ref.invalidate(notesProvider);
      ref.invalidate(noteLocalFoldersProvider);
      setState(() {});
      return r;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tree = ref.watch(noteTreeProvider).valueOrNull ?? const [];
    // 单文件导入的「本地」挂标随该夹是否还有本地来源笔记自动回落（工单 §1.2）。
    final localFolders =
        ref.watch(noteLocalFoldersProvider).valueOrNull ?? const <String>{};
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
                      ..._nodes(tree, 0, localFolders),
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
                      // V1.64 批2 N-1：树底「导入本地」入口（目录／文件就地两取法）。
                      _row(context,
                          keyName: 'nt-import',
                          icon: Icons.drive_folder_upload_outlined,
                          label: '导入本地 · 目录或文件',
                          depth: 0,
                          onTap: _importLocal),
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

  /// 树上角标来源（''＝不画）：挂载夹直取；`local_file` 挂标随本地来源笔记清空自动回落。
  String _badgeOf(FolderNode n, Set<String> localFolders) {
    final s = n.folder.source;
    if (s == 'local_file') return localFolders.contains(n.name) ? s : '';
    return s;
  }

  List<Widget> _nodes(List<FolderNode> nodes, int depth,
          Set<String> localFolders) =>
      [
        for (final n in nodes) ...[
          _row(context,
              keyName: 'nt-${n.name}',
              icon: Icons.folder_outlined,
              label: n.name,
              badgeSource: _badgeOf(n, localFolders),
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
          if (_open.contains(n.id)) ..._nodes(n.children, depth + 1, localFolders),
        ],
      ];

  Widget _row(BuildContext context,
      {required String keyName,
      required IconData icon,
      required String label,
      String badgeSource = '',
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
                child: Row(
              children: [
                Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                selected ? FontWeight.w800 : FontWeight.w600,
                            color: selected ? tokens.accent : null))),
                // V1.64 批2：挂载来源角标（纯文字线性胶囊·零 emoji）。
                if (badgeSource.isNotEmpty) MountBadge(source: badgeSource),
              ],
            )),
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
