import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/note_dao.dart';
import '../domain/note.dart';
import 'journal_providers.dart';
import 'note_paper.dart';
import 'widgets/note_tree_drawer.dart';

/// 笔记 tab（原型 recNote · V1.29轮9）：卡片三行=标题1/正文(列表1行·卡片≤4行)/时间行
/// （时间右=置顶黄色小钉·线性图标非 emoji）；多选圈在条目右侧；长按进入批量无 toast；
/// 顶部「已选择 x 项」+底部线性图标三钮（置顶钮随所选全置顶=「取消置顶」智能切换）；
/// 视图循环 列表→2列→3列（卡片=瀑布流错落·非行对齐）；时间三档 今天/今年MM-DD/跨年YYYY-MM-DD。
class NoteTab extends ConsumerStatefulWidget {
  const NoteTab({super.key});

  @override
  ConsumerState<NoteTab> createState() => _NoteTabState();
}

class _NoteTabState extends ConsumerState<NoteTab> {
  /// 已左滑移除的 id：立即隐藏，避免异步刷新前 Dismissible 重建报错。
  final Set<int> _gone = {};

  /// 轮8④：翻转当前排序项后重开菜单（等效原型的「菜单保持打开」）。
  final _sortKey = GlobalKey<PopupMenuButtonState<NoteSort>>();

  static const double _gap = 10;

  static String _sortLabel(NoteSort s, bool asc) => switch (s) {
        NoteSort.updated => asc ? '最后修改 ↑' : '最后修改 ↓',
        NoteSort.created => asc ? '创建时间 ↑' : '创建时间 ↓',
        NoteSort.title => asc ? '标题 Z→A' : '标题 A→Z',
      };

  /// 轮9s：时间三档=今天 时:分 / 今年 MM-DD / 跨年 YYYY-MM-DD（回收站「删于」同规则）。
  static String _timeLabel(DateTime d) {
    final now = DateTime.now();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return '今天 ${d.hour.toString().padLeft(2, '0')}:'
          '${d.minute.toString().padLeft(2, '0')}';
    }
    return d.year == now.year ? '$mm-$dd' : '${d.year}-$mm-$dd';
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
    final selMode = !inTrash && sel.isNotEmpty;

    final list = Column(
      children: [
        // 轮9：多选态顶部「已选择 x 项」（原型 noteSelTop）
        if (selMode)
          Padding(
            key: const ValueKey('note-sel-top'),
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Row(
              children: [
                Text('已选择 ${sel.length} 项',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: scheme.onSurface)),
              ],
            ),
          ),
        // V1.29轮6：右侧一行三钮 = 排序 / 文件夹树 / 视图循环（轮9i 行距收紧）
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // 轮8④：再点当前项=方向翻转（菜单保持打开·箭头变化可见）；
              // 选其他项=切换并回默认方向。
              KeyedSubtree(
                key: const ValueKey('note-sort'),
                child: PopupMenuButton<NoteSort>(
                  key: _sortKey,
                  tooltip: '排序',
                  icon: const Icon(Icons.swap_vert, size: 22),
                  onSelected: (s) {
                    final cur = ref.read(noteFilterProvider);
                    final flip = s == cur.sort;
                    final asc = flip ? !cur.asc : false;
                    ref.read(noteFilterProvider.notifier).state =
                        (folder: cur.folder, sort: s, asc: asc);
                    AppToast.show(context, '排序：${_sortLabel(s, asc)}');
                    if (flip) {
                      WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _sortKey.currentState?.showButtonMenu());
                    }
                  },
                  itemBuilder: (_) => [
                    for (final s in NoteSort.values)
                      PopupMenuItem(
                        value: s,
                        child: Row(
                          children: [
                            Text(
                                _sortLabel(
                                    s, s == filter.sort ? filter.asc : false),
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: s == filter.sort
                                        ? tokens.accent
                                        : null)),
                            if (s == filter.sort) ...[
                              const Spacer(),
                              Icon(Icons.check,
                                  size: 18, color: tokens.accent),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
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
                // 轮9b：循环收为 列表→2列→3列（4列内容不可读）
                tooltip: cols == 0
                    ? '卡片视图 · 每行 2 个'
                    : cols == 2
                        ? '卡片视图 · 每行 3 个'
                        : '列表视图',
                onPressed: () =>
                    ref.read(noteViewColsProvider.notifier).state =
                        cols == 0 ? 2 : (cols >= 3 ? 0 : cols + 1),
                icon: Icon(
                    cols == 0
                        ? Icons.menu
                        : cols == 2
                            ? Icons.grid_view
                            : Icons.view_week,
                    size: 22),
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
                            child: _card(context, ref, n, inTrash, sel,
                                cardMode: false),
                          ),
                        // V1.29轮9l：底部「共 N 篇 · 左滑删除 · 长按批量」教学文案移除（无价值）。
                      ],
                    )
                  : LayoutBuilder(builder: (context, box) =>
                      _masonry(context, ref, notes, cols, inTrash, sel,
                          box.maxWidth - 32)),
        ),
      ],
    );

    if (inTrash || !selMode) return list;
    // 轮9③：底部批量条=线性图标+文字三钮（无 emoji）·置顶钮智能切换
    final byId = {for (final n in notes) n.id: n};
    final allPinned = sel.every((id) => byId[id]?.pinned ?? false);
    return Column(
      children: [
        Expanded(child: list),
        Container(
          key: const ValueKey('note-sel-bar'),
          decoration: BoxDecoration(
              color: tokens.card,
              border: Border(top: BorderSide(color: tokens.cardBorder))),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                    child: _barBtn(
                        'sel-pin',
                        Icons.push_pin_outlined,
                        allPinned ? '取消置顶' : '置顶',
                        () => _batch(context, ref, sel, 'pin'),
                        scheme)),
                Expanded(
                    child: _barBtn(
                        'sel-move',
                        Icons.folder_outlined,
                        '移动到',
                        () => _batch(context, ref, sel, 'move'),
                        scheme)),
                Expanded(
                    child: _barBtn(
                        'sel-del',
                        Icons.delete_outline,
                        '删除',
                        () => _batch(context, ref, sel, 'del'),
                        scheme,
                        color: const Color(0xFFF43F5E))),
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

  /// 底部条按钮：上=线性图标 下=文字（原型 noteSelBar flex-col）。
  Widget _barBtn(String key, IconData icon, String label, VoidCallback onTap,
      ColorScheme scheme,
      {Color? color}) {
    return InkWell(
        key: ValueKey(key),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color ?? scheme.onSurface),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color ?? scheme.onSurface)),
            ],
          ),
        ));
  }

  /// 轮9b：卡片视图=瀑布流错落（按最短列分配·非 GridView 行对齐）。
  Widget _masonry(BuildContext context, WidgetRef ref, List<Note> notes,
      int cols, bool inTrash, Set<int> sel, double width) {
    final colW = (width - _gap * (cols - 1)) / cols;
    final buckets = List.generate(cols, (_) => <int>[]);
    final totals = List.filled(cols, 0.0);
    for (var i = 0; i < notes.length; i++) {
      var t = 0;
      for (var c = 1; c < cols; c++) {
        if (totals[c] < totals[t]) t = c;
      }
      buckets[t].add(i);
      totals[t] += _estHeight(notes[i], colW) + _gap;
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var c = 0; c < cols; c++) ...[
            if (c > 0) const SizedBox(width: _gap),
            Expanded(
              child: Column(
                children: [
                  for (final i in buckets[c])
                    Padding(
                      padding: const EdgeInsets.only(bottom: _gap),
                      child: _card(context, ref, notes[i], inTrash, sel,
                          cardMode: true),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 瀑布流分列用的卡片高度估算（标题1行+正文≤4行+时间行+内边距）。
  static double _estHeight(Note n, double colW) {
    final inner = colW - 28;
    double blockH(String text, double fs, double lh, int maxLines) {
      if (text.isEmpty) return fs * lh;
      final tp = TextPainter(
          text: TextSpan(
              text: text, style: TextStyle(fontSize: fs, height: lh)),
          textDirection: TextDirection.ltr)
        ..layout(maxWidth: inner);
      final lines = tp.computeLineMetrics().length.clamp(1, maxLines);
      tp.dispose();
      return lines * fs * lh;
    }

    return 28 +
        blockH(n.title.isEmpty ? '未命名笔记' : n.title, 14, 1.4, 1) +
        6 +
        blockH(n.preview, 12, 1.6, 4) +
        6 +
        14;
  }

  Widget _card(BuildContext context, WidgetRef ref, Note n, bool inTrash,
      Set<int> sel,
      {required bool cardMode}) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final selMode = !inTrash && sel.isNotEmpty;
    final selected = sel.contains(n.id);
    // 轮9n修正：纸色仅在卡片视图体现条目底色（列表视图不体现）·按笔记独立。
    final paperOn = cardMode && n.paper.isNotEmpty;
    final pFg = paperOn ? paperFg(n.paper) : null;

    Widget card = GestureDetector(
      key: ValueKey('note-card-${n.id}'),
      onTap: () {
        if (selMode) {
          _toggleSel(ref, n.id!);
          return;
        }
        context.push('/note/edit', extra: n.id);
      },
      onLongPress: () {
        if (inTrash) {
          _trashActions(context, ref, n);
        } else {
          // 轮9②：进入批量不再 toast 提示
          ref.read(noteSelProvider.notifier).state = {n.id!};
        }
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: paperOn
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(tokens.cardRadius),
                border: Border.all(color: tokens.cardBorder),
                color: paperBg(n.paper),
              )
            : context.cardDecoration,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 行1 标题
                  Text(
                    n.title.isEmpty ? '未命名笔记' : n.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: pFg),
                  ),
                  const SizedBox(height: 6),
                  // 行2 正文：列表 1 行 / 卡片 ≤4 行（轮9b 最大6行=1+4+1）
                  Text(n.preview,
                      maxLines: cardMode ? 4 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.6,
                          color: paperOn
                              ? pFg!.withValues(alpha: .78)
                              : scheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  // 行3 时间 + 置顶黄小钉（时间右侧·线性非 emoji）
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                            inTrash
                                ? '删于 ${_timeLabel(n.deletedAt!)}'
                                : _timeLabel(n.updatedAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 10,
                                color: paperOn
                                    ? pFg!.withValues(alpha: .6)
                                    : scheme.onSurfaceVariant)),
                      ),
                      if (n.pinned && !inTrash) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.push_pin,
                            size: 13, color: const Color(0xFFF59E0B)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // 轮9③：多选圈在条目右侧
            if (selMode) ...[
              const SizedBox(width: 8),
              Icon(
                  selected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  key: ValueKey('note-sel-${n.id}'),
                  size: 18,
                  color:
                      selected ? tokens.accent : scheme.onSurfaceVariant),
            ],
          ],
        ),
      ),
    );

    if (inTrash || selMode) return card;
    // 左滑入回收站（原型 note-sw：红色删除区跟手露出）
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
      // 轮9①：所选全置顶=取消置顶，否则=置顶（按钮标签已在 build 内联动）
      final notes = ref.read(notesProvider).valueOrNull ?? const <Note>[];
      final byId = {for (final n in notes) n.id: n};
      final un = ids.every((id) => byId[id]?.pinned ?? false);
      await dao.setPinnedMany(ids, !un);
      if (!context.mounted) return;
      _finishBatch(context, ref,
          un ? '已取消置顶 ${ids.length} 篇' : '已置顶 ${ids.length} 篇');
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
                title: const Text('恢复'),
                onTap: () => Navigator.of(bc).pop('restore')),
            ListTile(
                title: const Text('彻底删除',
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
