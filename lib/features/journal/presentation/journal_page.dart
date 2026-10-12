import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/grad_fab.dart';
import '../../../shared/linkage/media_mounts.dart';
import '../../../shared/linkage/read_mounts.dart';
import '../../../shared/weather/weather.dart';
import '../../../shared/widgets/ui_kit.dart' show AppToast;
import '../domain/journal_entry.dart';
import '../../read/domain/book_quote.dart';
import '../../read/presentation/read_providers.dart'
    show readRepositoryProvider, readTickProvider;
import 'diary_edit_page.dart';
import 'journal_providers.dart';
import 'note_edit_page.dart';
import 'note_search.dart';
import 'note_tab.dart';
import 'widgets/diary_review_sheet.dart';
import '../../../shared/widgets/image_attach.dart' show showImageLightbox;
import '../../../shared/widgets/scroll_pad.dart';
import 'widgets/ins_card.dart';
import 'widgets/note_tree_drawer.dart'
    show noteImportLocalAction, noteExportLocalAction, noteOpenHistoryAction;

/// 笔记段 FAB（V1.29轮2 原型 noteFabMenu）：与主页同款竖排三选
/// 📝富文本 / 📃纯文本 / ⌨️MD 文档；新建默认归属当前选中文件夹。
class _NoteFab extends ConsumerStatefulWidget {
  const _NoteFab();

  @override
  ConsumerState<_NoteFab> createState() => _NoteFabState();
}

class _NoteFabState extends ConsumerState<_NoteFab> {
  bool _open = false;

  // 轮10-9：FAB 三选去 emoji=线性图标（与弹层/菜单同语言）。
  static const _acts = [
    (Icons.edit_document, '添加富文本笔记', 'rich'),
    (Icons.notes_outlined, '添加纯文本笔记', 'plain'),
    (Icons.keyboard_outlined, '添加 MD 文档', 'md'),
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final (ico, label, kind) in _acts)
          if (_open)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                key: ValueKey('note-fab-$kind'),
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  setState(() => _open = false);
                  final folder = ref.read(noteFilterProvider).folder;
                  context.push('/note/edit',
                      extra: NoteEditArg(
                          kind: kind,
                          folder: folder));
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                      color: tokens.card,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: tokens.cardBorder),
                      boxShadow: tokens.cardShadow),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(ico, size: 16),
                      const SizedBox(width: 8),
                      Text(label,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ),
        GradFab(
          tooltip: '添加笔记',
          icon: Icon(_open ? Icons.close : Icons.add,
              color: Colors.white, size: 26),
          onTap: () => setState(() => _open = !_open),
        ),
      ],
    );
  }
}

/// 模块3 记录页（原型 p-records · V1.29轮5）：无段切换行，
/// 标题随当前段显「记录 · X」，右上 ⇄ 钮开四能力菜单。
/// 日记（M0/V1.28）与笔记列表管理（M1 批1a）为真实数据；阅读/影音游留占位。
///
/// V1.58 反馈轮5：支持段深链 [initialTab]（仪表盘「阅读」格 → `/journal?tab=book`），
/// 进来即落在对应段视图，不再停在默认日记段。
class JournalPage extends ConsumerStatefulWidget {
  const JournalPage({super.key, this.initialTab});

  /// 深链段名（diary/note/book/media）；null 或非法值 = 沿用当前段。
  final String? initialTab;

  static const kRecordLabels = {
    'diary': '日记',
    'note': '笔记',
    'book': '阅读',
    'media': '影音游',
  };

  /// 段名合法性：深链参数来自外部 URI，必须先校验再落状态。
  static bool isRecordTab(String? t) => kRecordLabels.containsKey(t);

  @override
  ConsumerState<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends ConsumerState<JournalPage> {
  /// 本帧生效的深链段：provider 落定前先按它渲染，避免「先闪日记再切段」。
  String? _linkTab;

  @override
  void initState() {
    super.initState();
    _takeLink();
  }

  @override
  void didUpdateWidget(covariant JournalPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) _takeLink();
  }

  /// 把深链段写回 [recordTabProvider]（⇄ 菜单同款通道）。
  /// initState/build 期不能同步改 provider，故落到本帧之后的微任务。
  void _takeLink() {
    final t = widget.initialTab;
    if (!JournalPage.isRecordTab(t)) return;
    final seg = t!;
    // 只在 initState/didUpdateWidget 里调用，本帧必然重建，无需 setState。
    _linkTab = seg;
    Future<void>.microtask(() {
      if (mounted) ref.read(recordTabProvider.notifier).state = seg;
    });
  }

  /// ⇄ 菜单选段：用户意图优先于深链，清掉本帧覆盖后交给 provider。
  void _selectTab(String v) {
    if (_linkTab != null) setState(() => _linkTab = null);
    ref.read(recordTabProvider.notifier).state = v;
  }

  @override
  Widget build(BuildContext context) {
    final providerTab = ref.watch(recordTabProvider);
    final tab = _linkTab ?? providerTab;
    final tokens = context.tokens;

    return Scaffold(
      appBar: AppBar(
        title: Text('记录 · ${JournalPage.kRecordLabels[tab]}'),
        actions: [
          // ⇄ 四能力切换（仅记录页；当前项高亮✓）
          // 轮10-9：菜单条目改圆角行卡+选中底色（与弹层/抽屉同语言·accent 随主题）。
          PopupMenuButton<String>(
            key: const ValueKey('rec-switch'),
            tooltip: '切换 日记/笔记/阅读/影音游',
            icon: const Icon(Icons.sync_alt),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18)),
            onSelected: _selectTab,
            itemBuilder: (_) => [
              for (final e in JournalPage.kRecordLabels.entries)
                PopupMenuItem<String>(
                  value: e.key,
                  height: 46,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: e.key == tab
                          ? tokens.accent.withValues(alpha: .12)
                          : null,
                    ),
                    child: Row(
                      children: [
                        Text(e.value,
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: e.key == tab ? tokens.accent : null)),
                        const Spacer(),
                        if (e.key == tab)
                          Icon(Icons.check, size: 17, color: tokens.accent),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          // 批5①（2026-10-12）：搜索钮**兑现**——原只弹「全局搜索 · 即将开放」
          //（DAO 的 `list(query:)` 早已在册，缺的只是一个入口）。
          IconButton(
            key: const ValueKey('rec-search'),
            tooltip: '搜索',
            icon: const Icon(Icons.search),
            onPressed: () => showNoteSearchSheet(context, ref),
          ),
          // 批5②：笔记段的「更多」——把原本只藏在文件树里的 导入/导出/打开历史
          // 提到顶栏（列表页此前零入口，要先用整屏右滑开树才够得着）。
          if (tab == 'note')
            PopupMenuButton<String>(
              key: const ValueKey('rec-more'),
              tooltip: '更多',
              icon: const Icon(Icons.more_horiz),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              onSelected: (v) {
                if (v == 'import') noteImportLocalAction(context, ref);
                if (v == 'export') noteExportLocalAction(context, ref);
                if (v == 'history') noteOpenHistoryAction(context, ref);
              },
              itemBuilder: (_) => [
                for (final (v, label) in const [
                  ('import', '导入本地'),
                  ('export', '导出为本地目录'),
                  ('history', '系统打开历史'),
                ])
                  PopupMenuItem<String>(
                    value: v,
                    height: 46,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.centerLeft,
                      child: Text(label,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w800)),
                    ),
                  ),
              ],
            ),
        ],
      ),
      // 三态 FAB 共用同一枚白色 ＋：字面量在文件里只出现一次（本批加影音游分支时
      // 曾被各分支各抄一遍，深色观感棘轮按处数记账，收成一处才是真减少）。
      floatingActionButton: tab == 'note'
          ? const _NoteFab()
          : GradFab(
              tooltip: switch (tab) {
                'book' => '新增摘录',
                'media' => '新条目',
                _ => '写今天的日记',
              },
              icon: const Icon(Icons.add, color: Colors.white, size: 26),
              onTap: switch (tab) {
                'book' => () => readTabFabTap(context, ref),
                'media' => () => mediaTabFabTap(context, ref),
                _ => () => context.push('/journal/edit',
                    extra: const DiaryEditArg()),
              },
            ),
      // 批6①（工单 §2 · 2026-10-12）：四段（日记/笔记/阅读/影音游）切换＝180ms
      // 淡入＋微上移（〇B 微动档 120~180ms·easeOut；原 `switch(tab)` 是硬切）。
      // 每段带 key：阅读/影音游两个工作台若返回同型 widget，无 key 时 AnimatedSwitcher
      // 会判「同一件」而不补间。`layoutBuilder` 只留当前件＝只做入场、旧段立即移除。
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeOut,
        layoutBuilder: (cur, _) => cur ?? const SizedBox.shrink(),
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position:
                Tween(begin: const Offset(0, .012), end: Offset.zero).animate(a),
            child: c,
          ),
        ),
        child: switch (tab) {
          'diary' => const KeyedSubtree(
              key: ValueKey('rec-body-diary'), child: _DiaryTab()),
          'note' =>
            const KeyedSubtree(key: ValueKey('rec-body-note'), child: NoteTab()),
          'book' => KeyedSubtree(
              key: const ValueKey('rec-body-book'), child: readWorkbench()),
          _ => KeyedSubtree(
              key: const ValueKey('rec-body-media'), child: mediaWorkbench()),
        },
      ),
    );
  }
}

/// 日记 tab：心情月历卡 · 写今天入口 · 筛选 · 列表/INS 双布局 · 那年今日。
/// 轮13：长按条目/卡片进入批量选中（底部 已选N篇+删除+关闭 · 返回先退多选）。
class _DiaryTab extends ConsumerStatefulWidget {
  const _DiaryTab();

  @override
  ConsumerState<_DiaryTab> createState() => _DiaryTabState();
}

class _DiaryTabState extends ConsumerState<_DiaryTab> {
  bool _selMode = false;
  final Set<int> _sel = {};

  void _enterSel(int id) => setState(() {
        _selMode = true;
        _sel.add(id);
      });

  void _toggleSel(int id) => setState(() {
        _sel.contains(id) ? _sel.remove(id) : _sel.add(id);
        if (_sel.isEmpty) _selMode = false;
      });

  void _exitSel() => setState(() {
        _selMode = false;
        _sel.clear();
      });

  /// 批量删除：确认弹层 → 软删进回收站 → 刷新列表（语义断链批 2026-10-12）。
  Future<void> _batchDelete() async {
    final n = _sel.length;
    final yes = await showDialog<bool>(
      context: context,
      builder: (bc) => AlertDialog(
        title: Text('删除选中的 $n 篇日记？'),
        content: const Text('删除后进回收站，可随时恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(bc).pop(false),
              child: const Text('取消')),
          TextButton(
            key: const ValueKey('diary-del-batch-ok'),
            onPressed: () => Navigator.of(bc).pop(true),
            child:
                const Text('删除', style: TextStyle(color: Color(0xFFF43F5E))),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await ref.read(journalRepositoryProvider).removeAll(_sel);
    if (!mounted) return;
    _exitSel();
    ref.invalidate(journalsProvider);
    AppToast.show(context, '已删除 $n 篇 · 回收站可恢复');
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final tokens = context.tokens;
    final entriesAsync = ref.watch(journalsProvider);
    final streak = ref.watch(journalStreakProvider).valueOrNull ?? 0;
    final filter = ref.watch(journalFilterProvider);
    final insMode = ref.watch(journalInsProvider);
    final entries = entriesAsync.valueOrNull ?? const <JournalEntry>[];

    final tags = <String>{
      for (final e in entries) ...e.tags,
    }.take(4).map((t) => '#$t').toList();

    // #27：持久化的筛选键若指向已不存在的标签（改名/删除后冷启动）回落 'all'。
    final rawTags = <String>{for (final e in entries) ...e.tags};
    final effFilter = (filter == 'all' || filter == 'todo' || rawTags.contains(filter))
        ? filter
        : 'all';

    final shown = switch (effFilter) {
      'all' => entries,
      'todo' => entries.where((e) => e.todoLines().isNotEmpty).toList(),
      _ => entries
          .where((e) => e.tags.any((t) => t == effFilter || '#$t' == effFilter))
          .toList(),
    };

    final now = DateTime.now();
    final today = entries.where((e) => JournalEntry.sameDay(e.day, now)).firstOrNull;
    final monthEntries =
        entries.where((e) => e.day.year == now.year && e.day.month == now.month).toList();

    // UI/流畅批（2026-10-12）：月历逐日 O(31×N) 过滤 → 一次建 map
    //（monthEntries 新→旧，首见=当日最新篇；byDayAll 供点按打开该日全篇选择）。
    final byDayFirst = <int, JournalEntry>{};
    final byDayAll = <int, List<JournalEntry>>{};
    for (final e in monthEntries) {
      byDayAll.putIfAbsent(e.day.day, () => []).add(e);
      byDayFirst.putIfAbsent(e.day.day, () => e);
    }
    // 那年今日：原 FutureBuilder 在 build 里现建 future，每次 setState 重查 DB；
    // 改 provider 缓存（随列表失效刷新），此处只读值。
    final onThisDay = ref.watch(onThisDayProvider).valueOrNull;
    Widget tailItem() => onThisDay == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GestureDetector(
              onTap: () => context
                  .push('/journal/edit', extra: DiaryEditArg(entryId: onThisDay.id)),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: tokens.accent.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(16)),
                child: Text(
                  '🗓 那年今日 · ${onThisDay.day.year}-${_two(onThisDay.day.month)}-${_two(onThisDay.day.day)}\n'
                  '「${onThisDay.previewText.replaceAll('\n', ' ').clampText(24)}」点击查看',
                  style: const TextStyle(fontSize: 11, height: 1.6),
                ),
              ),
            ),
          );

    return PopScope(
      canPop: !_selMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitSel(); // 轮13：多选态返回=先退出多选
      },
      child: Column(
        children: [
          Expanded(
            child: ScrollPad(
              // T2-B：日记段长列表滚动垫（切栏回来原位）。
              id: 'journal-diary',
              // UI/流畅批（2026-10-12）：列表改懒构建（原 `ListView(children: […])` 全量
              // 建卡片·每卡含 Image，同笔记批1 定式；零视觉：padding 与间距不变）。
              // item 序：0 月历卡 / 1,3,5 间隙 / 2 入口卡 / 4 切换行 / 6.. 篇卡（空态占 6）/ 尾=那年今日。
              child: ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: shown.isEmpty ? 8 : 7 + shown.length,
      itemBuilder: (context, i) {
        final n = shown.length;
        if (i == 0) {
          return Container(
            // 渐变心情月历卡（原型 moodCard：标题+回顾钮+30 色条+脚注）
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              gradient: tokens.gradient,
              borderRadius: BorderRadius.circular(24),
              boxShadow: tokens.cardShadow),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('${now.month}月 · 已记录 ${monthEntries.length} 篇',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                  const Spacer(),
                  GestureDetector(
                    // 批2c：📊 回顾兑现=底部弹层（心情趋势柱+高频词云+去年本月）
                    onTap: () => openDiaryReview(context, month: now),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .2),
                          borderRadius: BorderRadius.circular(999)),
                      child: const Text('📊 回顾',
                          style: TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 36,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var d = 1; d <= DateTime(now.year, now.month + 1, 0).day; d++)
                      Expanded(
                        // UI/UX批（2026-10-12）：色条=「点色条看当天」对齐原型——有既有篇
                        // 直开（多篇弹选择）、无篇才新建（新建入口已有 FAB＋入口卡两处）；
                        // 热区垫满整格 36px（无心情日原 ~4px 点不中），bar 仍贴底零视觉差。
                        child: GestureDetector(
                          key: ValueKey('moodbar-$d'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            final dayList = byDayAll[d];
                            if (dayList == null || dayList.isEmpty) {
                              context.push('/journal/edit',
                                  extra: DiaryEditArg(day: DateTime(now.year, now.month, d)));
                            } else {
                              openDiaryPickSheet(
                                  context, '${now.month}-${_two(d)} 的日记', dayList);
                            }
                          },
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              height: 36 * _barHeightOf(byDayFirst[d]),
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                color: _barColorOf(byDayFirst[d]),
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(3)),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '连续记录 $streak 天 · '
                '${_dominantMoodText(monthEntries)} · 点色条看当天',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: .8), fontSize: 10),
              ),
            ],
          ),
        );
        }
        if (i == 1) return const SizedBox(height: 12);
        if (i == 2) {
          return _card(
            context,
            // 写今天的日记（原型入口卡）
          child: InkWell(
            borderRadius: BorderRadius.circular(tokens.cardRadius),
            onTap: () => context.push('/journal/edit', extra: const DiaryEditArg()),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: tokens.accent.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Text('✍️', style: TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('写今天的日记',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                        Text(
                          today == null
                              ? '开始今天的记录 · 输入 ☐ 可插入待办'
                              : '今日已写 ${today.plainBody.length} 字 · 继续编辑',
                          style: TextStyle(
                              fontSize: 11,
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const Text('›', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ),
        );
        }
        if (i == 3) return const SizedBox(height: 12);
        if (i == 4) {
          // V1.29轮9g：本行=列表⇄INS 切换钮 + 筛选钮（右）·筛选点击弹底部浮层 全部/☐待办/标签
          return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              key: const ValueKey('diary-view'),
              tooltip: insMode ? '切换到列表' : '切换到 INS 卡片流',
              // #27：布局写 settings（持久化，冷启动恢复）。
              onPressed: () => ref
                  .read(settingsControllerProvider.notifier)
                  .setJournalIns(!insMode),
              icon: Icon(insMode ? Icons.menu : Icons.grid_view, size: 22),
            ),
            IconButton(
              key: const ValueKey('diary-filter'),
              tooltip: '筛选',
              onPressed: () => _diaryFilterSheet(context, ref, filter, tags),
              icon: Icon(
                filter == 'all'
                    ? Icons.filter_alt_outlined
                    : Icons.filter_alt,
                size: 22,
                color: filter == 'all'
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : tokens.accent,
              ),
            ),
          ],
        );
        }
        if (i == 5) return const SizedBox(height: 2);
        if (shown.isEmpty) {
          if (i == 6) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text(
                  entries.isEmpty ? '还没有日记 · 点上方「写今天的日记」开始' : '该筛选下暂无日记',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            );
          }
          return tailItem(); // 空列表时尾卡仍兜底（无数据自然 shrink）
        }
        if (i >= 6 + n) return tailItem();
        final e = shown[i - 6];
        if (insMode) {
          return InsDiaryCard(
              entry: e,
              selected: _sel.contains(e.id),
              onLongPress: () => _enterSel(e.id!),
              onOpen: () => _selMode
                  ? _toggleSel(e.id!)
                  : context.push('/journal/edit',
                      extra: DiaryEditArg(entryId: e.id)));
        }
        return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _card(
                context,
                child: InkWell(
                  borderRadius: BorderRadius.circular(tokens.cardRadius),
                  onLongPress: () => _enterSel(e.id!),
                  onTap: () => _selMode
                      ? _toggleSel(e.id!)
                      : context.push('/journal/edit',
                          extra: DiaryEditArg(entryId: e.id)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Stack(
                      children: [
                        Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('${e.day.year}-${_two(e.day.month)}-${_two(e.day.day)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 14)),
                            const SizedBox(width: 6),
                            Text('周${_weekdays[e.day.weekday - 1]}',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                            // 批2e：天气快照副标题（晴 24°）
                            if (e.weatherCode != null) ...[
                              const SizedBox(width: 6),
                              Text(
                                  weatherText(e.weatherCode!,
                                      tmax: e.tempMax,
                                      tmin: e.tempMin,
                                      compact: true),
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                            ],
                            const Spacer(),
                            if (moodEmoji(e.mood) != null) ...[
                              Text(moodEmoji(e.mood)!,
                                  style: const TextStyle(fontSize: 18)),
                              const SizedBox(width: 4),
                              Text(moodLabel(e.mood) ?? '',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          e.content.isEmpty ? '（只打了心情卡）' : e.previewText,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, height: 1.6),
                        ),
                        // 批2a：有图篇在预览下挂 4 缩略（>4 末格 +N）
                        if (e.imagePaths.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _DiaryThumbs(entry: e),
                        ],
                        const SizedBox(height: 8),
                        // 轮12-11：关联信息=右下角小图标（保存时间左侧），点击展开
                        _DiaryMeta(entry: e),
                      ],
                        ),
                        // 轮13：多选态选中 ✓ 角标
                        if (_sel.contains(e.id))
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              key: ValueKey('jsel-${e.id}'),
                              width: 22,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: tokens.accent),
                              child: const Icon(Icons.check,
                                  size: 14, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
        }
            ),
            ),
          ),
          if (_selMode) _selBar(),
        ],
      ),
    );
  }

  /// 轮13 · 批量选中底栏：已选 N 篇 + 删除（玫红线性图标）+ 关闭 ✕（与笔记同款简约图标）。
  Widget _selBar() {
    final tokens = context.tokens;
    return Container(
      key: const ValueKey('diary-sel-bar'),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: tokens.card,
        border: Border(top: BorderSide(color: tokens.cardBorder)),
      ),
      child: Row(
        children: [
          Text('已选 ${_sel.length} 篇',
              key: const ValueKey('diary-sel-count'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          const Spacer(),
          IconButton(
            key: const ValueKey('diary-del-batch'),
            tooltip: '删除',
            onPressed: _batchDelete,
            icon: const Icon(Icons.delete_outline,
                size: 22, color: Color(0xFFF43F5E)),
          ),
          IconButton(
            key: const ValueKey('diary-sel-exit'),
            tooltip: '取消',
            onPressed: _exitSel,
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    );
  }

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// UI/流畅批：色条高度/颜色改收当日篇（build 侧已建 map，逐日 O(N) 过滤取消）。
  double _barHeightOf(JournalEntry? e) {
    if (e == null) return .12;
    final mood = e.mood;
    return mood == null ? .35 : 0.35 + mood / kJournalMoods.length * 0.65;
  }

  Color _barColorOf(JournalEntry? e) {
    if (e == null) return Colors.white.withValues(alpha: .22);
    const palette = [
      Color(0xFF6366F1), Color(0xFF2DD4BF), Color(0xFFF59E0B),
      Color(0xFFFB7185), Color(0xFF8B5CF6), Color(0xFF0EA5E9), Color(0xFFF43F5E),
    ];
    return palette[((e.mood ?? 1) - 1) % palette.length];
  }

  String _dominantMoodText(List<JournalEntry> monthEntries) {
    final counts = <int, int>{};
    for (final e in monthEntries) {
      if (e.mood != null) counts[e.mood!] = (counts[e.mood!] ?? 0) + 1;
    }
    if (counts.isEmpty) return '本月还没有心情记录';
    final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    return '本月心情以 ${moodEmoji(top)} ${moodLabel(top)} 居多';
  }

  /// V1.29轮9g：筛选=底部浮层选择（全部/☐待办/标签·当前项✓）。
  Future<void> _diaryFilterSheet(
      BuildContext context, WidgetRef ref, String cur, List<String> tags) async {
    final opts = ['全部', '☐ 待办', ...tags];
    String valOf(String o) => switch (o) {
          '全部' => 'all',
          '☐ 待办' => 'todo',
          _ => o,
        };
    String labelOf(String v) => switch (v) {
          'all' => '全部',
          'todo' => '☐ 待办',
          _ => v,
        };
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (bc) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text('筛选',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            for (final o in opts)
              ListTile(
                key: ValueKey('df-opt-$o'),
                title: Row(
                  children: [
                    Text(o,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: valOf(o) == cur
                                ? bc.tokens.accent
                                : null)),
                    if (valOf(o) == cur) ...[
                      const Spacer(),
                      Icon(Icons.check, size: 18, color: bc.tokens.accent),
                    ],
                  ],
                ),
                onTap: () => Navigator.of(bc).pop(o),
              ),
          ],
        ),
      ),
    );
    if (pick == null) return;
    // #27：筛选写 settings（持久化）。
    ref.read(settingsControllerProvider.notifier).setJournalFilter(valOf(pick));
    if (context.mounted) AppToast.show(context, '筛选：${labelOf(pick)}');
  }

  Widget _card(BuildContext context, {required Widget child}) {
    final tokens = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        border: Border.all(color: tokens.cardBorder),
        boxShadow: tokens.cardShadow,
      ),
      child: child,
    );
  }

}

/// 轮12-11 · 列表行底栏：标签 chips + 关联小图标（☑ N 收起态·点击展开明细）+ 保存时间。
/// 语义断链批（L5 · 2026-10-12）：关联块补当日阅读摘录（原型 ins-ref「📚 摘录…」行）。

/// 当日阅读摘录（按自然日分组；摘录变动随 readTick 失效）。
final dayQuotesProvider =
    FutureProvider<Map<int, List<({BookQuote q, String book})>>>((ref) async {
  ref.watch(readTickProvider);
  return ref.read(readRepositoryProvider).quotesGroupedByDay();
});

class _DiaryMeta extends ConsumerStatefulWidget {
  const _DiaryMeta({required this.entry});

  final JournalEntry entry;

  @override
  ConsumerState<_DiaryMeta> createState() => _DiaryMetaState();
}

class _DiaryMetaState extends ConsumerState<_DiaryMeta> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final n = e.todoLines().length;
    // L5：当日新建的阅读摘录（划线/感想）＝本页关联素材（原型关联块同口径）。
    final quotes = ref
            .watch(dayQuotesProvider)
            .valueOrNull?[JournalEntry.dayStart(e.day).millisecondsSinceEpoch] ??
        const <({BookQuote q, String book})>[];
    final qm = quotes.length;
    String two(int v) => v.toString().padLeft(2, '0');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final t in e.tags.take(3))
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: tokens.cardBorder),
                  ),
                  child: Text('#$t',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ),
            const Spacer(),
            if (n + qm > 0)
              IconButton(
                key: ValueKey('jref-${e.id}'),
                tooltip: '本页关联',
                visualDensity: VisualDensity.compact,
                constraints:
                    const BoxConstraints(minWidth: 40, minHeight: 28),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                onPressed: () => setState(() => _open = !_open),
                icon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.link,
                        size: 14,
                        color: _open ? tokens.accent : scheme.onSurfaceVariant),
                    const SizedBox(width: 3),
                    Text('${n + qm}',
                        style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            Text(
              '${two(e.updatedAt.hour)}:${two(e.updatedAt.minute)} 保存',
              style: TextStyle(
                  fontSize: 10, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        if (_open && n + qm > 0)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: tokens.accent.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border(left: BorderSide(color: tokens.accent, width: 3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (n > 0)
                  Text('本页关联 · ☑ $n 个待办同步',
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                // L5：摘录行（最多展示 3 条，全量去阅读模块看——不做第二入口）。
                for (final (:q, :book) in quotes.take(3))
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '📚 「${q.body.replaceAll('\n', ' ').clampText(20)}」'
                      '${book.isEmpty ? '' : ' · $book'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant),
                    ),
                  ),
                if (qm > 3)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text('📚 …共 $qm 条当日摘录',
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 批2a · 日记行缩略条：一行 4 枚 44×44（>4 末格盖 +N · 点图看大图）。
class _DiaryThumbs extends StatelessWidget {
  const _DiaryThumbs({required this.entry});

  final JournalEntry entry;

  @override
  Widget build(BuildContext context) {
    final paths = entry.imagePaths;
    final shown = paths.take(4).toList();
    return Row(
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          GestureDetector(
            key: ValueKey('jimg-${entry.id}-$i'),
            onTap: () => showImageLightbox(context, shown[i]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(File(shown[i]),
                        fit: BoxFit.cover,
                        // UI/流畅批：44px 缩略降采样（原整图解码，多图长列表滚动偏重）。
                        cacheWidth:
                            (MediaQuery.devicePixelRatioOf(context) * 96).round(),
                        errorBuilder: (_, _, _) => const ColoredBox(
                            color: Color(0x14000000),
                            child: Center(
                                child: Text('丢失',
                                    style: TextStyle(fontSize: 9))))),
                    if (i == 3 && paths.length > 4)
                      Positioned.fill(
                        child: ColoredBox(
                          color: const Color(0x73000000),
                          child: Center(
                              child: Text('+${paths.length - 4}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12))),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const Spacer(),
      ],
    );
  }
}

extension on String {
  String clampText(int n) => length <= n ? this : '${substring(0, n)}…';
}
