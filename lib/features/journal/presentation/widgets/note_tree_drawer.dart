import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/platform/saf_tree.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/note_folder.dart';
import '../journal_providers.dart';
import '../note_local_import.dart';

/// 面板开合补间时长（原路由 transitionDuration 同值；叠层与本件都用）。
/// 开侧阈值 24 与甩速 500 常量在 `note_tree_overlay.dart`（手势执行点）。
/// 沿革：轮2 贴边判定带 110 → 轮4 整屏口径作废判定带；轮4 阈值 56→24（更早入树）。
const Duration kNoteTreeAnimDur = Duration(milliseconds: 220);

/// V1.29 批A3 · 文件夹树面板（原型 noteTree · Obsidian 形态）：
/// 整屏右滑或右上文件夹钮开 62% 悬浮圆角卡（承载＝常驻叠层 `NoteTreeOverlay`，不走 Navigator）；
/// 点文件夹=选中当前目录（不关面板·自动展开）；点树外遮罩＝收起（全开时遮罩才参与命中）；
/// 「添加文件夹」建在选中目录下（未选=顶层）；长按手建夹=行内就地重命名/删除（T-E），
/// 长按本地/导出挂载节点=移除挂载（V1.64 批2）；底部操作条：重命名/添加/展开折叠/关闭。
///
/// 树内再弹的**输入框/导入面板/移除挂载半屏仍走路由**——它们发生在抬手之后，不影响手势。
class NoteTreePanel extends ConsumerStatefulWidget {
  const NoteTreePanel(
      {super.key,
      required this.onClose,
      required this.follow,
      required this.settleClose});

  /// 六处「收起自己」入口统一走它（不许再 Navigator.pop）。
  final VoidCallback onClose;

  /// 面板左滑逐帧钉进度（T-B：位移与遮罩淡入同帧跟随）。
  final ValueChanged<double> follow;

  /// 面板左滑松手判定交回叠层（p∈[0,1] 剩开度，vx 横向甩速）。
  final void Function(double p, double vx) settleClose;

  @override
  ConsumerState<NoteTreePanel> createState() => _TreeDrawerState();
}

class _TreeDrawerState extends ConsumerState<NoteTreePanel> {
  final Set<int> _open = {};

  /// T-E（原型 ntAct 同款）：当前展开行内动作的文件夹 id（同一时刻只有一行有动作钮）。
  int? _actId;

  /// T-B：面板左滑收起过程中的进度累计（拖起手时以叠层当前值打底）。
  double? _closeFrom;

  void _pick(String folder, {bool hasKids = false, int? id}) {
    ref.read(noteFilterProvider.notifier).state = (folder: folder,
        sort: ref.read(noteFilterProvider).sort,
        asc: ref.read(noteFilterProvider).asc);
    if (hasKids && id != null) _open.add(id);
    _actId = null; // 原型 ntPick：点别的行＝行内动作收起
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

  /// T-E（树手感批2·真机反馈轮3）：长按手建夹＝行尾**就地**现「重命名/删除」两钮
  /// （原型 ntLong/ntAct 同款，再长按同夹收起）；挂载节点维持「移除挂载」半屏（N-1c）。
  /// 旧的白色 `showModalBottomSheet` 菜单撤掉——与胶囊语言不符，且多一层转场。
  void _longPress(FolderNode node) {
    if (node.folder.isMount) {
      _unmount(node);
      return;
    }
    setState(() => _actId = _actId == node.id ? null : node.id);
  }

  Future<void> _rename(FolderNode node) async {
    setState(() => _actId = null);
    final dao = ref.read(noteFolderDaoProvider);
    final name = await _promptName(context, title: '重命名', initial: node.name);
    if (name == null || name.trim().isEmpty || !mounted) return;
    await dao.rename(node.id, name);
    ref.invalidate(noteFolderListProvider);
    setState(() {});
  }

  Future<void> _delete(FolderNode node) async {
    setState(() => _actId = null);
    final dao = ref.read(noteFolderDaoProvider);
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
    ref.invalidate(noteFolderListProvider);
    setState(() {});
  }

  /// 底部条「重命名」钮：手建夹直接开输入弹层，挂载节点走「移除挂载」（菜单撤了，入口得留着）。
  void _renameOrUnmount(FolderNode node) {
    if (node.folder.isMount) {
      _unmount(node);
    } else {
      _rename(node);
    }
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

    // 笔记树手感批 T-A（真机反馈轮3·产品确认）：直角满高贴边 → Obsidian 式悬浮圆角卡
    // （留边 8·圆角 16·描边＋阴影；原型 #noteTree 同形）。点树外收起/返回键/底部条沿用。
    // T-B：面板面上左滑＝叠层同一条 controller 反向跟手收起（跟手开、跟手收是成对要求）。
    return GestureDetector(
      key: const ValueKey('nt-swipe-close'),
      // 面板只在遮罩全开时才接收指针（叠层 IgnorePointer 钉 value==1），起手开度恒 1 打底。
      onHorizontalDragStart: (_) => _closeFrom = 1,
      onHorizontalDragUpdate: (d) {
        final from = _closeFrom;
        if (from == null) return;
        final p = (from + (d.primaryDelta ?? d.delta.dx) / w).clamp(0.0, 1.0);
        _closeFrom = p;
        widget.follow(p);
      },
      onHorizontalDragEnd: (d) => _settleClose(d.velocity.pixelsPerSecond.dx),
      onHorizontalDragCancel: () => _settleClose(0),
      child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: w,
            height: double.infinity,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: .18),
                      blurRadius: 24,
                      offset: const Offset(0, 8))
                ],
              ),
              child: ClipRRect(
                key: const ValueKey('nt-card-shape'),
                borderRadius: BorderRadius.circular(16),
                child: Material(
                  color: scheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: context.tokens.cardBorder),
                  ),
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
                          onPressed: widget.onClose,
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
                            widget.onClose(); // 常驻叠层批：跳转前收起＝本地 close()
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
                              : _renameOrUnmount(selNode),
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
                          onPressed: widget.onClose,
                          icon: const Icon(Icons.close, size: 20)),
                    ],
                  ),
                ),
              ],
            ),
          ),
            ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  /// T-B：面板左滑松手判定（常驻叠层批口径＝工单 §1：剩开度 p<0.6 或左甩过速即关，否则补间回全开）。
  void _settleClose(double vx) {
    final p = _closeFrom;
    _closeFrom = null;
    if (p == null) return;
    widget.settleClose(p, vx);
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
              onCaret: () => setState(() {
                    // 原型 ntToggle：展开/折叠同时收起行内动作。
                    if (_open.contains(n.id)) {
                      _open.remove(n.id);
                    } else {
                      _open.add(n.id);
                    }
                    _actId = null;
                  }),
              onTap: () => _pick(n.name, hasKids: n.children.isNotEmpty, id: n.id),
              onLongPress: () => _longPress(n),
              actions: _actId == n.id ? _actBtns(n) : null),
          // 笔记树手感批 T-C：展开/折叠＝AnimatedSize 150ms easeOut（〇B 微动档），不再跳变。
          AnimatedSize(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _open.contains(n.id)
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _nodes(n.children, depth + 1, localFolders))
                : const SizedBox(width: double.infinity),
          ),
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
      VoidCallback? onLongPress,
      Widget? actions}) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: ValueKey(keyName),
      // 常驻叠层批·命中闭环（工单 §1 成因二）：动作态下行 onTap 让位给行尾两钮，
      // 免得点钮落空时被整行接走＝「点了只变选中」。
      onTap: actions == null ? onTap : null,
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
            // T-E：动作态下行尾两钮替掉计数位（原型 ntAct 同款）。
            if (actions != null)
              actions
            else if (count != null)
              Text('$count',
                  style: TextStyle(
                      fontSize: 10, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  /// T-E 行内动作（原型 nt-act-rename／nt-act-del）：行尾就地两枚线性图标钮，
  /// 点哪枚即收起动作态；不再开白色半屏菜单。
  ///
  /// **命中区不许压到图标尺寸**（模拟器装机验出的真缺陷：`constraints: BoxConstraints()`
  /// ＋zero padding 把 IconButton 缩成图标大小，手指点在图标上仍落到整行＝变成"选中目录"，
  /// 而 widget 测试按 key 点中心永远点得中，抓不到）。下限 44×44（U6 同一口径）。
  Widget _actBtns(FolderNode node) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // opaque 包裹＝该矩形命中必落此处，祖先 InkWell 抢不走（摘掉＝中心命中例红＝刀③）。
          GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: IconButton(
              key: const ValueKey('nt-act-rename'),
              tooltip: '重命名',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              onPressed: () => _rename(node),
              icon: const Icon(Icons.edit_outlined, size: 18))),
          GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: IconButton(
              key: const ValueKey('nt-act-del'),
              tooltip: '删除文件夹',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              onPressed: () => _delete(node),
              icon: Icon(Icons.delete_outline,
                  size: 18, color: Theme.of(context).colorScheme.error))),
        ],
      );
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
