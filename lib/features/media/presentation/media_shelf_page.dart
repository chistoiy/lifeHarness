import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/grad_fab.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/load_error_state.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/media_item.dart';
import 'media_add_sheet.dart';
import 'media_providers.dart';
import 'media_sheets.dart';
import 'widgets/media_card.dart';

/// 影音架（原型 `m-shelf` · 路由 `/media/shelf`）：
/// 桌面 / 脊 / 列表三视图＋类型 chip＋分区 chip＋搜索＋长按批量。
///
/// 两条硬判定（面板第 3 项）：
/// · 脊视图**电影不出现**（`.mds-spine` 只有剧集/音乐/游戏三类形态）；
/// · 桌面视图按四类各自的扁平卡形态渲染，条目数＝卡数。
class MediaShelfPage extends ConsumerStatefulWidget {
  const MediaShelfPage({super.key, this.initialKind, this.initialQuery});

  /// 深链带进来的类型（如记录页「音乐」入口 → `/media/shelf?kind=music`）。
  final String? initialKind;

  /// 深链关键词（详情页创作者/发行方芯片的反查落点 → `/media/shelf?q=`）。
  final String? initialQuery;

  @override
  ConsumerState<MediaShelfPage> createState() => _MediaShelfPageState();
}

class _MediaShelfPageState extends ConsumerState<MediaShelfPage> {
  static const _views = ['desk', 'spine', 'list'];
  final _search = TextEditingController();
  final Set<String> _sel = {};
  bool _selMode = false;

  @override
  void initState() {
    super.initState();
    final k = widget.initialKind;
    if (k != null && MediaItem.kinds.contains(k)) {
      // initState 期不能同步改 provider，落到本帧之后（壳层同款处理）。
      Future<void>.microtask(() {
        if (mounted) ref.read(mediaKindProvider.notifier).state = k;
      });
    }
    final q = (widget.initialQuery ?? '').trim();
    if (q.isNotEmpty) {
      _search.text = q;
      Future<void>.microtask(() {
        if (mounted) ref.read(mediaQueryProvider.notifier).state = q;
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _exitSel() => setState(() {
    _selMode = false;
    _sel.clear();
  });

  void _toggleSel(String id) => setState(() {
    if (_sel.contains(id)) {
      _sel.remove(id);
      if (_sel.isEmpty) _selMode = false;
    } else {
      _sel.add(id);
    }
  });

  void _enterSel(String id) => setState(() {
    _selMode = true;
    _sel
      ..clear()
      ..add(id);
  });

  Future<void> _deleteSelected() async {
    final ids = _sel.toList();
    if (ids.isEmpty) return;
    final ok = await lhConfirm(
      context,
      '把选中的 ${ids.length} 条移入回收站？7 天内可从「我的 · 回收站」找回。',
    );
    if (!ok || !mounted) return;
    await ref.read(mediaRepositoryProvider).softDelete(ids);
    if (!mounted) return;
    final tick = ref.read(mediaTickProvider.notifier);
    tick.state = tick.state + 1;
    _exitSel();
    AppToast.show(context, '已移入回收站');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final view = ref.watch(mediaViewProvider);
    final kind = ref.watch(mediaKindProvider);
    final state = ref.watch(mediaStateProvider);
    final items = ref.watch(mediaItemsProvider);
    final counts = ref.watch(mediaKindCountsProvider).valueOrNull ?? const {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('影音架'),
        actions: [
          for (final v in _views)
            _ViewBtn(
              key: ValueKey('mds-view-$v'),
              icon: switch (v) {
                'desk' => Icons.grid_view_outlined,
                'spine' => Icons.view_week_outlined,
                _ => Icons.view_list_outlined,
              },
              label: switch (v) {
                'desk' => '桌面',
                'spine' => '脊',
                _ => '列表',
              },
              selected: view == v,
              // 电影没有侧脊：全部/单类为电影时该钮置灰（原型 mdsVbtnSpine 淡化同口径）
              enabled: !(v == 'spine' && kind == MediaItem.kMovie),
              onTap: () => ref.read(mediaViewProvider.notifier).state = v,
            ),
          PopupMenuButton<String>(
            key: const ValueKey('mds-sort'),
            tooltip: '排序',
            icon: const Icon(Icons.swap_vert, size: 22),
            initialValue: 'recent',
            onSelected: (v) => ref.read(mediaSortProvider.notifier).state = v,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'recent', child: Text('最近活动')),
              PopupMenuItem(value: 'rating', child: Text('按评分')),
              PopupMenuItem(value: 'added', child: Text('新增在前')),
              PopupMenuItem(value: 'name', child: Text('按名称')),
              PopupMenuItem(value: 'duration', child: Text('按时长')),
            ],
          ),
          _ViewBtn(
            key: const ValueKey('mds-notes-entry'),
            icon: Icons.description_outlined,
            label: '影音笔记库',
            selected: false,
            onTap: () => context.push('/media/notes'),
          ),
          _ViewBtn(
            key: const ValueKey('mds-mgr-entry'),
            icon: Icons.category_outlined,
            label: '影音资料',
            selected: false,
            onTap: () => context.push('/media/mgr'),
          ),
          _ViewBtn(
            key: const ValueKey('mds-manage'),
            icon: Icons.checklist_outlined,
            label: '管理',
            selected: _selMode,
            onTap: () => _selMode ? _exitSel() : _enterSelMulti(),
          ),
        ],
      ),
      // 批量条挂 bottomNavigationBar：放 body 末尾会被 FAB 压住右端动作点不到（真机同形）。
      bottomNavigationBar: _selMode ? _multiBar(scheme) : null,
      floatingActionButton: GradFab(
        key: const ValueKey('mds-fab-add'),
        tooltip: '新条目',
        icon: const Icon(Icons.add, color: Colors.white, size: 26),
        onTap: () => showMediaAddSheet(context, ref),
      ),
      body: Column(
        children: [
          // 类型 chip（全部＋四类，角标＝在册条数）
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final (k, label) in _kindTabs)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PillChip(
                      key: ValueKey('mds-kind-$k'),
                      label: counts[k] == null
                          ? label
                          : '$label ${counts[k]}',
                      selected: kind == k,
                      onTap: () => ref.read(mediaKindProvider.notifier).state = k,
                    ),
                  ),
              ],
            ),
          ),
          // 分区 chip（单类＝该类四/五档；全部＝语义归并四档；音乐无分区面）
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final s in _stateTabs(kind))
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PillChip(
                      key: ValueKey('mds-state-tab-$s'),
                      label: s == 'all' ? '全部分区' : s,
                      selected: state == s,
                      onTap: () => ref.read(mediaStateProvider.notifier).state = s,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
            child: TextField(
              key: const ValueKey('mds-search'),
              controller: _search,
              onChanged: (v) =>
                  ref.read(mediaQueryProvider.notifier).state = v,
              decoration: const InputDecoration(
                hintText: '片名 / 艺人 / 工作室 / 导演',
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: items.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => LoadErrorBanner(
                title: '影音架没加载出来',
                error: e,
                onRetry: () => ref.invalidate(mediaItemsProvider),
              ),
              data: (list) => _body(view, kind, list),
            ),
          ),
        ],
      ),
    );
  }

  static const _kindTabs = <(String, String)>[
    ('all', '全部'),
    (MediaItem.kMovie, '电影'),
    (MediaItem.kSeries, '剧集'),
    (MediaItem.kMusic, '音乐'),
    (MediaItem.kGame, '游戏'),
  ];

  List<String> _stateTabs(String kind) {
    if (kind == 'all') {
      return ['all', for (final (label, _) in MediaItem.stateGroups) label];
    }
    return ['all', ...MediaItem.states[kind] ?? const []];
  }

  void _enterSelMulti() {
    final list = ref.read(mediaItemsProvider).valueOrNull ?? const [];
    if (list.isEmpty) {
      AppToast.show(context, '架面还没有条目');
      return;
    }
    setState(() {
      _selMode = !_selMode;
      if (!_selMode) {
        _sel.clear();
      } else {
        _sel
          ..clear()
          ..add(list.first.id);
      }
    });
  }

  Widget _body(String view, String kind, List<MediaItem> list) {
    if (list.isEmpty) {
      return EmptyDashRow(
        text: '影音架还是空的 · 点右下角 ＋ 建第一条',
        onTap: () => showMediaAddSheet(context, ref),
      );
    }
    if (view == 'spine') {
      // 刀2：这一行判定摘掉，脊视图就会把电影也画出来。
      final spines = list.where((x) => x.kind != MediaItem.kMovie).toList();
      if (spines.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '电影无侧脊 · 请切桌面或列表视图',
            style: TextStyle(fontSize: 11),
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
        children: [
          for (final x in spines)
            MediaSpineRow(
              item: x,
              onTap: () => context.push('/media/item/${x.id}'),
            ),
        ],
      );
    }
    if (view == 'list') {
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
        children: [
          for (final x in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: MediaListRow(
                item: x,
                selected: _sel.contains(x.id),
                selectionMode: _selMode,
                onTap: () => _selMode
                    ? _toggleSel(x.id)
                    : context.push('/media/item/${x.id}'),
                onLongPress: () => _enterSel(x.id),
              ),
            ),
        ],
      );
    }
    // 桌面视图：三列网格（原型 .mds-grid 3 列）
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 10,
        childAspectRatio: .6,
      ),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final x = list[i];
        return MediaItemCard(
          item: x,
          selected: _sel.contains(x.id),
          selectionMode: _selMode,
          onTap: () => _selMode
              ? _toggleSel(x.id)
              : context.push('/media/item/${x.id}'),
          onLongPress: () => _enterSel(x.id),
        );
      },
    );
  }

  /// 长按批量条（原型 #mMultiBar：深色胶囊＋选中数＋三个动作）。
  Widget _multiBar(ColorScheme scheme) {
    final ids = _sel.toList();
    final kind = ref.read(mediaKindProvider);
    return Container(
      key: const ValueKey('mds-multi-bar'),
      color: scheme.inverseSurface,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Text(
            '选中 ${ids.length}',
            style: TextStyle(
              fontSize: 11,
              color: scheme.onInverseSurface,
              fontFeatures: kMediaTabularRead,
            ),
          ),
          const Spacer(),
          for (final (label, run) in <(String, Future<void> Function())>[
            (
              '改分区',
              () => showMediaBulkStateSheet(context, ref, ids, kind)
                  .then((_) => _exitSel()),
            ),
            (
              '加标签',
              () => showMediaBulkTagSheet(context, ref, ids)
                  .then((_) => _exitSel()),
            ),
            ('删除', _deleteSelected),
          ])
            TextButton(
              key: ValueKey('mds-bulk-$label'),
              onPressed: ids.isEmpty ? null : run,
              style: TextButton.styleFrom(
                foregroundColor: scheme.onInverseSurface,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(label, style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

/// 顶栏视图钮（原型 `.mds-vbtn`／`.on`：36 圆角、选中描边底）。
class _ViewBtn extends StatelessWidget {
  const _ViewBtn({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 置灰不可点＝点了没反应也不改状态（LH-K36 口径）
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 38,
          height: 44,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: selected
                    ? scheme.primary.withValues(alpha: .14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 19,
                color: !enabled
                    ? scheme.onSurface.withValues(alpha: .25)
                    : selected
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
