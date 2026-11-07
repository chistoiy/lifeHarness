import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart' show AppToast;
import '../data/note_dao.dart' show NoteSort;
import 'journal_providers.dart';
import 'widgets/note_sheet_lang.dart';

/// C 案批1 真机补口（2026-11-07）：笔记页「筛选／排序／文件夹／视图」四枚操作的
/// **唯一实现**。原型已把整排并入顶栏第一行（列表上方不再单独占一排）：
/// 独立笔记页由 `JournalPage` 的 `AppBar.actions` 托管（inAppBar=true）；
/// 存量用例直接 pump `NoteTab()` 时仍由页内第二行承载（inAppBar=false）。
/// 两处共用这一份逻辑与同一组 key，避免「顶栏与列表各写一套」漂移。

/// 排序菜单与 toast 的同一份文案（轮8④ 翻转当前项＝方向取反）。
String noteSortLabel(NoteSort s, bool asc) => switch (s) {
      NoteSort.updated => asc ? '最后修改 ↑' : '最后修改 ↓',
      NoteSort.created => asc ? '创建时间 ↑' : '创建时间 ↓',
      NoteSort.title => asc ? '标题 Z→A' : '标题 A→Z',
    };

/// 批5⑤：按来源筛选弹层（走 NoteSheetHeader / NoteSheetRow 单源语言）。
/// 从 `NoteTab` 抽到这里，顶栏形态与页内形态共用。
Future<void> pickNoteSource(BuildContext context, WidgetRef ref) async {
  const opts = <(String, String)>[
    ('', '全部来源'),
    ('local', '本地文件'),
    ('export', '导出目录'),
    ('open_with', '系统打开'),
  ];
  final cur = ref.read(noteSourceProvider);
  final picked = await showModalBottomSheet<String>(
    context: context,
    builder: (bc) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const NoteSheetHeader(title: '按来源筛选'),
            for (final (v, label) in opts)
              NoteSheetRow(
                key: ValueKey('nsrc-$v'),
                icon:
                    v == cur ? Icons.check_circle : Icons.radio_button_unchecked,
                label: label,
                color: v == cur ? context.tokens.accent : null,
                onTap: () => Navigator.of(bc).pop(v),
              ),
          ],
        ),
      ),
    ),
  );
  if (picked == null) return;
  ref.read(noteSourceProvider.notifier).state = picked;
  if (context.mounted) {
    AppToast.show(
        context, '来源：${opts.firstWhere((o) => o.$1 == picked).$2}');
  }
}

/// 四枚操作按钮组。key 保持原页内第二行的字面量，存量用例不用改定位。
class NoteToolbarActions extends ConsumerStatefulWidget {
  const NoteToolbarActions({
    super.key,
    required this.onOpenTree,
    this.inAppBar = false,
  });

  /// 文件夹钮开树：两处形态各自传自己那棵 `NoteTreeOverlay` 的键。
  final VoidCallback onOpenTree;

  /// true＝挂在 AppBar：按钮收窄到 32px 一排，防 390 宽顶栏溢出。
  /// 菜单天然锚在按钮下方、点空白关闭（PopupMenuButton 默认行为）。
  final bool inAppBar;

  @override
  ConsumerState<NoteToolbarActions> createState() =>
      _NoteToolbarActionsState();
}

class _NoteToolbarActionsState extends ConsumerState<NoteToolbarActions> {
  /// 轮8④：翻转当前排序项后重开菜单（等效原型的「菜单保持打开」）。
  final _sortKey = GlobalKey<PopupMenuButtonState<NoteSort>>();

  @override
  Widget build(BuildContext context) {
    final compact = widget.inAppBar;
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final filter = ref.watch(noteFilterProvider);
    final cols = ref.watch(noteViewColsProvider);
    final src = ref.watch(noteSourceProvider);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 批5⑤（工单 §2 · 2026-10-12）：按来源筛选——激活时图标转 accent。
        IconButton(
          key: const ValueKey('note-source'),
          tooltip: '按来源筛选',
          constraints: compact
              ? const BoxConstraints.tightFor(width: 32, height: 32)
              : null,
          padding: compact ? EdgeInsets.zero : null,
          onPressed: () => pickNoteSource(context, ref),
          icon: Icon(
              src.isEmpty ? Icons.filter_alt_outlined : Icons.filter_alt,
              size: compact ? 19 : 22,
              color: src.isEmpty ? scheme.onSurfaceVariant : tokens.accent),
        ),
        // 轮8④：再点当前项＝方向翻转（菜单保持打开·箭头变化可见）；
        // 选其他项＝切换并回默认方向。
        KeyedSubtree(
          key: const ValueKey('note-sort'),
          child: PopupMenuButton<NoteSort>(
            key: _sortKey,
            tooltip: '排序',
            padding: compact ? EdgeInsets.zero : const EdgeInsets.all(8),
            icon: compact ? null : const Icon(Icons.swap_vert, size: 22),
            child: compact
                ? const SizedBox(
                    width: 32,
                    height: 32,
                    child: Center(child: Icon(Icons.swap_vert, size: 19)),
                  )
                : null,
            onSelected: (s) {
              final cur = ref.read(noteFilterProvider);
              final flip = s == cur.sort;
              final asc = flip ? !cur.asc : false;
              saveNoteFilter(ref, (folder: cur.folder, sort: s, asc: asc));
              AppToast.show(context, '排序：${noteSortLabel(s, asc)}');
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
                          noteSortLabel(
                              s, s == filter.sort ? filter.asc : false),
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: s == filter.sort ? tokens.accent : null)),
                      if (s == filter.sort) ...[
                        const Spacer(),
                        Icon(Icons.check, size: 18, color: tokens.accent),
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
          constraints: compact
              ? const BoxConstraints.tightFor(width: 32, height: 32)
              : null,
          padding: compact ? EdgeInsets.zero : null,
          onPressed: widget.onOpenTree,
          icon: Icon(Icons.folder_outlined,
              size: compact ? 19 : 22,
              color: filter.folder.isEmpty
                  ? scheme.onSurfaceVariant
                  : tokens.accent),
        ),
        IconButton(
          key: const ValueKey('note-view'),
          // 轮9b：循环收为 列表→2列→3列（4列内容不可读）。
          tooltip: cols == 0
              ? '卡片视图 · 每行 2 个'
              : cols == 2
                  ? '卡片视图 · 每行 3 个'
                  : '列表视图',
          constraints: compact
              ? const BoxConstraints.tightFor(width: 32, height: 32)
              : null,
          padding: compact ? EdgeInsets.zero : null,
          onPressed: () =>
              saveNoteViewCols(ref, cols == 0 ? 2 : (cols >= 3 ? 0 : cols + 1)),
          icon: Icon(
              cols == 0
                  ? Icons.menu
                  : cols == 2
                      ? Icons.grid_view
                      : Icons.view_week,
              size: compact ? 19 : 22),
        ),
      ],
    );
  }
}
