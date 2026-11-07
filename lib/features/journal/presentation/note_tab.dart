import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/logging/app_log.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/note_dao.dart';
import '../domain/note.dart';
import 'journal_providers.dart';
import '../../../shared/widgets/scroll_pad.dart';
import 'note_paper.dart';
import 'widgets/note_sheet_lang.dart';
import 'widgets/note_tree_drawer.dart';
import 'widgets/note_tree_overlay.dart';

/// 瀑布流高度估算的**实际计算次数**（缓存命中不计数）——仅供用例钉
/// 「按篇缓存生效」（批1 顺滑：原每帧对每篇重跑 TextPainter）。
@visibleForTesting
int kNoteEstComputeCount = 0;

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

  /// 常驻叠层批：树面板的开合动画挂在叠层件上，文件夹钮经这条 key 复用同一开合。
  final GlobalKey<NoteTreeOverlayState> _treeKey =
      GlobalKey<NoteTreeOverlayState>();

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
    // 批5⑤：当前来源筛选键（''=全部）。
    final src = ref.watch(noteSourceProvider);
    final sel = ref.watch(noteSelProvider);
    final selMode = sel.isNotEmpty;

    final list = Column(
      children: [
        // 轮9：多选态顶部「已选择 x 项」（原型 noteSelTop）
        // 批6②：进出同走 160ms AnimatedSize（与底部多选条同一档，进出对称）。
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: selMode
              ? Padding(
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
                )
              : const SizedBox(width: double.infinity),
        ),
        // V1.29轮6：右侧一行三钮 = 排序 / 文件夹树 / 视图循环（轮9i 行距收紧）
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // 批5⑤（工单 §2 · 2026-10-12）：按来源筛选——兑现卸载弹层
              //「已导入的 N 条笔记保留在库 · 来源标仍可筛」；激活时图标转 accent。
              IconButton(
                key: const ValueKey('note-source'),
                tooltip: '按来源筛选',
                onPressed: () => _pickSource(context),
                icon: Icon(
                    src.isEmpty ? Icons.filter_alt_outlined : Icons.filter_alt,
                    size: 22,
                    color: src.isEmpty ? scheme.onSurfaceVariant : tokens.accent),
              ),
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
                    // 批5③：走 helper 写回设置（排序键/方向持久化）。
                    saveNoteFilter(ref,
                        (folder: cur.folder, sort: s, asc: asc));
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
                onPressed: () =>
                    _treeKey.currentState?.open(), // 常驻叠层：开树＝钉同一条动画
                icon: Icon(Icons.folder_outlined,
                    size: 22,
                    color: filter.folder.isEmpty
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
                onPressed: () => saveNoteViewCols(
                    ref, cols == 0 ? 2 : (cols >= 3 ? 0 : cols + 1)),
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
                  text: src.isNotEmpty
                      ? '该来源下暂无笔记'
                      : filter.folder.isEmpty
                          ? '还没有笔记 · 点右下角 ＋ 开始'
                          : '「${filter.folder}」下还没有笔记',
                  onTap: () => context.push('/note/edit'),
                )
              : cols == 0
                  ? ScrollPad(
                      // T2-B：记录栏笔记列表滚动垫（切栏回来原位）。
                      id: 'journal-notes',
                      // 批1 顺滑：列表改懒构建（原 `ListView(children: [for …])` 全量建条目，
                      // 笔记一多首帧与滚动都偏重）。零视觉：padding 与条目间距不变。
                      child: ListView.builder(
                        key: const ValueKey('note-list'),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        itemCount: notes.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child:
                              _card(context, ref, notes[i], sel, cardMode: false),
                        ),
                      ),
                    )
                  : LayoutBuilder(builder: (context, box) =>
                      _masonry(context, ref, notes, cols, sel,
                          box.maxWidth - 32)),
        ),
      ],
    );

    // 轮9③：底部批量条=线性图标+文字三钮（无 emoji）·置顶钮智能切换
    // 批2②（工单 §2 · 准则 HG-H4）：多选态系统返回＝**先退多选**、不退出记录页
    //（日记段 _DiaryTab 同构，笔记段此前漏接 ⇒ 一按返回整页退出、选择全丢）。
    final byId = {for (final n in notes) n.id: n};
    final allPinned = sel.every((id) => byId[id]?.pinned ?? false);
    final bar = Container(
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
                    color: kNoteDanger)),
            IconButton(
                key: const ValueKey('sel-exit'),
                onPressed: () =>
                    ref.read(noteSelProvider.notifier).state = const {},
                icon: const Icon(Icons.close, size: 18)),
          ],
        ),
      ),
    );

    // 真机反馈轮（2026-10-11）：右滑＝开文件树（批量选择态不给该手势，避免误开）。
    // 常驻叠层批：承载从路由式弹层换成 NoteTreeOverlay（body 之上 Stack 常驻＋自带整屏起手监听）——
    // 拖拽中途 push 会被 Navigator 取消指针（轮4 定位），叠层形态下面板才可能真随指推出。
    //
    // 批6②（工单 §2 · 2026-10-12）：多选条进出＝160ms AnimatedSize（〇B 微动档）。
    // 为此把「叠层 / 非叠层」两条互斥分支收进**同一个 Column**：底条槽位恒在（非多选态高 0），
    // 才存在可补间的同一实例（挂在两棵互斥子树上就没有所谓「进出」——那只是硬换）。
    final body = selMode ? list : NoteTreeOverlay(key: _treeKey, child: list);
    return PopScope(
      canPop: !selMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(noteSelProvider.notifier).state = const {};
      },
      child: Column(
        children: [
          Expanded(child: body),
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: selMode ? bar : const SizedBox(width: double.infinity),
          ),
        ],
      ),
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
      int cols, Set<int> sel, double width) {
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
                      child: _card(context, ref, notes[i], sel,
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
  /// 批1 顺滑：按 `(id, 标题, 正文, 列宽)` 记忆化——原实现每次 rebuild 都对每篇
  /// 重跑一次 `TextPainter.layout`，而多选点选会整屏重建 ⇒ 点一下卡一下。
  static final Map<(int?, String, String, double), double> _hCache = {};

  static double _estHeight(Note n, double colW) {
    final key = (n.id, n.title, n.preview, colW);
    final hit = _hCache[key];
    if (hit != null) return hit;
    if (_hCache.length > 600) _hCache.clear(); // 防无界（笔记量级远小于此）
    kNoteEstComputeCount++;
    return _hCache[key] = _estHeightRaw(n, colW);
  }

  static double _estHeightRaw(Note n, double colW) {
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

  Widget _card(BuildContext context, WidgetRef ref, Note n, Set<int> sel,
      {required bool cardMode}) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final selMode = sel.isNotEmpty;
    final selected = sel.contains(n.id);
    // 轮9n修正：纸色仅在卡片视图体现条目底色（列表视图不体现）·按笔记独立。
    final paperOn = cardMode && n.paper.isNotEmpty;
    final pFg = paperOn ? paperFg(n.paper) : null;

    // 笔记树手感批 T-D：卡外套 LH-K00 Pressable（Listener 只观察不进竞技场，
    // 与 Dismissible 左滑回收站无冲突）——裸 GestureDetector 无按压态＝实锤缺口。
    Widget card = Pressable(
      child: GestureDetector(
      key: ValueKey('note-card-${n.id}'),
      onTap: () {
        if (selMode) {
          _toggleSel(ref, n.id!);
          return;
        }
        context.push('/note/edit', extra: n.id);
      },
      onLongPress: () {
        // 轮9②：进入批量不再 toast 提示（回收站操作在全局回收站屏，V1.60）
        // 批2③（工单 §2）：长按进管理态＝触觉锚（〇B 四处之一），与影音架
        // `_enterSel` 的 mediumImpact 同语义（产品随样张点头）。
        HapticFeedback.mediumImpact();
        ref.read(noteSelProvider.notifier).state = {n.id!};
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
                            _timeLabel(n.updatedAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 10,
                                color: paperOn
                                    ? pFg!.withValues(alpha: .6)
                                    : scheme.onSurfaceVariant)),
                      ),
                      if (n.pinned) ...[
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
      ),
    );

    if (selMode) return card;
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
        // 批2①（工单 §2）：左滑＝**一划即删**，删后给一次「撤销」后悔药
        //（长时效退路仍在回收站）。Dismissible 本帧出树 ⇒ messenger / container
        // 必须在出树前取好；撤销回调可能在页面离场后触发，故一律走 container。
        final messenger = ScaffoldMessenger.of(context);
        final container = ProviderScope.containerOf(context, listen: false);
        final dao = container.read(noteDaoProvider);
        final id = n.id!;
        setState(() => _gone.add(id));
        try {
          await dao.softDelete(id);
        } catch (e) {
          // catch-ok: 抛出去也没人接（异步回调里），至少留一行日志。
          AppLog.add('笔记移入回收站失败：${n.title} · $e', level: LhLevel.warn);
        }
        // 真机反馈轮（2026-10-11·工单 交棒话术-20261011 §3）：`_gone` 是"先隐藏再异步软删"
        // 的动画垫片。若那次软删没落库，卡片就永久隐身而树上计数照算＝产品报的
        // 「计 2 条、只见 1 条」。当场核验：仍在册即交还列表并留痕，绝不静默吞。
        final back = await dao.byId(id);
        container.invalidate(notesProvider);
        container.invalidate(noteTreeProvider);
        if (back != null && back.deletedAt == null) {
          AppLog.add('笔记软删未落库，卡片已交还列表：${n.title}',
              level: LhLevel.warn);
          if (mounted) setState(() => _gone.remove(id));
          return;
        }
        AppToast.showUndoWith(messenger, '已移入回收站 · 30 天内可恢复',
            onUndo: () async {
          await dao.restore(id);
          // 撤销后必须撤掉「立即隐藏」垫片，否则卡片不回归（`_gone` 只加不删
          // ⇒ 撤销了也看不见，本批实锤）。
          if (mounted) setState(() => _gone.remove(id));
          container.invalidate(notesProvider);
          container.invalidate(noteTreeProvider);
        });
      },
      child: card,
    );
  }

  void _toggleSel(WidgetRef ref, int id) {
    final cur = {...ref.read(noteSelProvider)};
    cur.contains(id) ? cur.remove(id) : cur.add(id);
    ref.read(noteSelProvider.notifier).state = cur;
  }

  /// 批5⑤：按来源筛选弹层（走 NoteSheetHeader / NoteSheetRow 单源语言）。
  Future<void> _pickSource(BuildContext context) async {
    const opts = <(String, String)>[
      ('', '全部来源'),
      ('local', '本地导入'),
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
                  icon: v == cur
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
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
    // 批5④（工单 §2 · 2026-10-12）：批量删除补**二次确认**——与日记段
    // `_DiaryTab._batchDelete` 对齐（同 App 内两段删批此前一个要确认一个不要，
    // 属口径不一致而非新设计）。取消＝原样留在多选态（不清选择，可重试）。
    final n = ids.length;
    final yes = await showDialog<bool>(
      context: context,
      builder: (bc) => AlertDialog(
        title: Text('删除选中的 $n 篇笔记？'),
        content: const Text('删除后可在回收站保留 30 天，期间可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(bc).pop(false),
              child: const Text('取消')),
          TextButton(
            key: const ValueKey('note-del-batch-ok'),
            onPressed: () => Navigator.of(bc).pop(true),
            child:
                const Text('删除', style: TextStyle(color: kNoteDanger)),
          ),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
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
}
