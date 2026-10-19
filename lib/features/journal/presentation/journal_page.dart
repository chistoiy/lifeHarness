import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/grad_fab.dart';
import '../../../shared/linkage/media_mounts.dart';
import '../../../shared/linkage/read_mounts.dart';
import '../../../shared/weather/weather.dart';
import '../../../shared/widgets/ui_kit.dart' show AppToast;
import '../domain/diary_filter_kit.dart';
import '../domain/journal_entry.dart';
import '../domain/tag.dart';
import '../../read/domain/book_quote.dart';
import '../../read/presentation/read_providers.dart'
    show readRepositoryProvider, readTickProvider;
import 'diary_edit_page.dart';
import 'journal_providers.dart';
import 'note_edit_page.dart';
import 'note_search.dart';
import 'note_tab.dart';
import 'widgets/diary_fan_fab.dart';
import 'widgets/diary_filter_sheet.dart';
import 'widgets/diary_review_sheet.dart';
import '../../../shared/widgets/image_attach.dart' show showImageLightbox;
import '../../../shared/widgets/scroll_pad.dart';
import 'widgets/ins_card.dart';
import 'journal_page_track.dart';
import 'widgets/journal_layout_kit.dart';
import 'widgets/journal_wall.dart';
import 'widgets/note_tree_drawer.dart'
    show noteImportLocalAction, noteExportLocalAction, noteOpenHistoryAction;

part 'journal_page_card.dart';

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
  ConsumerState<JournalPage> createState() => JournalPageState();
}

class JournalPageState extends ConsumerState<JournalPage> {
  /// 日记段的状态外呼口（§4c-2：FAB 长按扇形里的筛选／设置两枚要调它）。
  final GlobalKey<DiaryTabState> _diaryKey = GlobalKey<DiaryTabState>();

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
      //
      // 日记段（§4c-2 产品令）：单击＝新建、**长按＝扇形（筛选／设置）**，
      // 且日记主页顶行那三枚图标已整行移除——FAB 是这三件事的唯一入口。
      floatingActionButton: tab == 'note'
          ? const _NoteFab()
          : tab == 'diary'
              ? DiaryFanFab(
                  // 测试与深链探针都按此 key 定位球体；丢了它整套扇形回归会「找不到元素」。
                  key: const ValueKey('diary-fan-fab'),
                  onNewDiary: () => context.push('/journal/edit',
                      extra: const DiaryEditArg()),
                  onFilter: () {
                    final st = _diaryKey.currentState;
                    if (st != null) st.openFilter();
                  },
                  onSettings: () {
                    final st = _diaryKey.currentState;
                    if (st != null) st.openSettings();
                  },
                )
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
          'diary' => KeyedSubtree(
              key: const ValueKey('rec-body-diary'),
              child: DiaryTab(key: _diaryKey)),
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
class DiaryTab extends ConsumerStatefulWidget {
  const DiaryTab({super.key});

  @override
  ConsumerState<DiaryTab> createState() => DiaryTabState();
}

class DiaryTabState extends ConsumerState<DiaryTab> {
  bool _selMode = false;
  final Set<int> _sel = {};

  /// 图墙查看月份的偏移（0＝本月，负数＝往前翻）。批1c：翻月是**纯视图态**，
  /// 不落 settings——用户翻到 3 月看两眼再回来，下次进来还是该看本月。
  int _wallMonthOff = 0;

  /// 图墙当前查看月（按偏移算出来，避免各处自己 `DateTime(now.year, now.month+k)` 算错）。
  DateTime wallMonthOf(DateTime now) =>
      DateTime(now.year, now.month + _wallMonthOff);

  /// §4c-2：FAB 长按扇形里的「筛选」入口。
  ///
  /// 顶行三枚图标已整行移除，筛选／设置只剩扇形这一条路，故两者做成**公开方法**
  /// 供外层 `JournalPage` 经 `GlobalKey` 调用（`ref`/`context` 都长在本 State 上）。
  Future<void> openFilter() {
    final entries =
        ref.read(journalsProvider).valueOrNull ?? const <JournalEntry>[];
    // 批2c：标签清单**全量**——原 `.take(4)` 等于把第 5 个以后的标签藏了，
    // 与「超一行折叠、点开看全量」直接冲突。排序只为让折叠次序稳定。
    // 批2b：以池为准（未使用的标签也要能筛，筛出 0 篇是合法结果）。
    final pool = ref.read(diaryTagPoolProvider).valueOrNull ?? const <Tag>[];
    final tags = <String>{
      for (final t in pool) t.name,
      for (final e in entries) ...e.tags,
    }.toList()
      ..sort();
    // 批2d：时间段与起止一并带进弹层——弹层里改的是 settings，关掉再开要能回显。
    final span = ref.read(journalSpanProvider);
    return showDiaryFilterSheet(
      context,
      cur: ref.read(journalFilterProvider),
      range: ref.read(journalRangeProvider),
      from: span.from,
      to: span.to,
      tags: tags,
      entries: entries,
    );
  }

  /// §4c-2：FAB 长按扇形里的「设置」入口（三档视图；FAB 开关已随本令下线，弹层里没有）。
  Future<void> openSettings() =>
      showSetSheet(context, ref, ref.read(journalLayoutProvider));

  /// 翻月：`-1` 上一月 / `+1` 下一月，范围 `[本月-24, 本月]`（不只是当月，未来没有日记）。
  void wallStep(BuildContext context, int delta) {
    final next = _wallMonthOff + delta;
    if (next > 0) return; // 不能翻到未来
    if (next < -kWallMaxMonthBack) return; // 下界与原型一致
    setState(() => _wallMonthOff = next);
  }

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
    // 批2d：时间段（8 档预设或自定义）与自定义起止。三维条件里它是**前提**——
    // 顺序照原型 `dwHit`：先 `dwInRange` 再判标签/标记。
    final range = ref.watch(journalRangeProvider);
    final span = ref.watch(journalSpanProvider);
    // 日记改版批1a：视图三档（track/list/ins）。原布尔 `journalIns` 已由 settings 层单向映射到三档，
    // 这里只读三档；`insMode` 仍从它派生，好让既有「列表/INS 两态」代码与断言继续成立。
    final layout = ref.watch(journalLayoutProvider);
    final insMode = layout == kJournalLayoutIns;
    final entries = entriesAsync.valueOrNull ?? const <JournalEntry>[];

    // §4c-2：原顶行三枚图标（含筛选钮）已移除，`tags` 在 build 里不再用——
    // 筛选弹层的标签清单改由 `openFilter()` 现算（见本类同名方法），避免两处各拼一份。
    // #27：持久化的筛选键若指向已不存在的标签（改名/删除后冷启动）回落 'all'。
    // 批2b：标签清单＝池（scopes 含 diary）∪ 篇内残留名字。
    // 只用篇内名字会出现「池里有、但还没人用」的标签在筛选里选不到；
    // 只用池会出现「标签已删、篇内快照未同步」的键被静默吞掉（后者兜底可见）。
    final poolTags = ref.watch(diaryTagPoolProvider).valueOrNull ?? const <Tag>[];
    final rawTags = <String>{
      for (final t in poolTags) t.name,
      for (final e in entries) ...e.tags,
    };
    // 批1a：新增两个固定键 starred（收藏）/ liked（点亮），与 todo 同族——不吃标签白名单。
    const fixedKeys = {'all', 'todo', 'starred', 'liked'};
    final effFilter = (fixedKeys.contains(filter) || rawTags.contains(filter))
        ? filter
        : 'all';

    // 批2c：改读 domain 的 `diaryHit`（弹层实时计数读的是同一个函数）。
    // 两处各写一份筛选式，出过「弹层说筛出 3 篇、关掉弹层只剩 1 篇」的偏。
    // 批2d：再加时间段前置条件（`diaryInRange`）——弹层的 `_count()` 用的也是这两行，
    // 改判据必须两处一起改，否则又是同一个「说 3 篇只剩 1 篇」的偏。
    final shown = entries
        .where((e) =>
            diaryInRange(e, range: range, from: span.from, to: span.to) &&
            diaryHit(e, effFilter))
        .toList();

    // 日期轨道（批1a）：按生效筛选后的 [shown] 折日期块，筛选变了块也跟着变（不放 entries，
    // 否则「筛出 1 篇」时左栏仍显示全部日期——那与筛选语义直接冲突）。
    final trackBlocks = layout == kJournalLayoutTrack
        ? buildTrackBlocks(shown,
            moodColorOf: (e) =>
                (e.mood == null) ? null : tokens.accent)
        : const <TrackDayBlock>[];

    final now = DateTime.now();
    // §4b-4：`today`（当日最新一篇）原为「写今天的日记」入口卡的副标题服务
    //（「今日已写 N 字」）；入口卡整行移除后它已无消费者，一并删掉。
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

    // 批1c：图墙可翻月，故另建「年→月→日→全篇」的全量索引（不按月裁）。
    // 为什么不复用 byDayAll：它只装本月；翻到 3 月时直接用它，整屏都是空格。
    final wallDayAll = <int, Map<int, Map<int, List<JournalEntry>>>>{};
    for (final e in entries) {
      wallDayAll.putIfAbsent(e.day.year, () => {}).putIfAbsent(
          e.day.month, () => {}).putIfAbsent(e.day.day, () => []).add(e);
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
              // 轨道档整棵换掉列表树：条目按「日期块」分行，套不进「一篇一 item」的索引算式——
              // 硬塞会让 i-6 索引错位。两棵树共用同一 ScrollPad，切档滚动位置仍回到原位。
              child: layout == kJournalLayoutTrack
                  ? trackScroll(context, ref, now, trackBlocks,
                      wallAllEntries: entries, wallDayAll: wallDayAll)
                  : ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: shown.isEmpty ? 8 : 7 + shown.length,
      itemBuilder: (context, i) {
        final n = shown.length;
        if (i == 0) {
          // 批1a（工单 §2 硬口径 8）：彩色心情卡**只属于列表档**；轨道档同一位置换「月历图墙」，
          // INS 档整块不出（原卡内含渐变+30 色条，塞进 INS 显得很吵）。
          if (layout == kJournalLayoutTrack) {
            // 批2e：图墙自带卡片底（说明行在卡片外），不再外套 `card()`。
            return JournalWall(
              month: now,
              byDayFirst: byDayFirst,
              onTapDay: (day) {
                final list = byDayAll[day];
                if (list == null || list.isEmpty) {
                  context.push('/journal/edit',
                      extra: DiaryEditArg(
                          day: DateTime(now.year, now.month, day)));
                } else {
                  openDiaryPickSheet(
                      context, '${now.month}月$day日的日记', list);
                }
              },
            );
          }
          if (insMode) return const SizedBox.shrink();
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
        // §4b-4ï¼äº§åä»¤ï¼ï¼ãåä»å¤©çæ¥è®°ãå¥å£å¡
        // æ´è¡ç§»é¤ï¼å³ä¸è§ FAB å·²è¦çåä¸å¥å£ï¼åå¥å£åä½ï¼ã
        // ç©ºä½ä¿çï¼ä¸æ¹ç¯å¡ç i-6 ç´¢å¼ä¸å¾åã
        if (i == 2) return const SizedBox.shrink();
        if (i == 3) return const SizedBox(height: 12);
        // §4c-2产品令：顶行三枚图标（切换档／设置／筛选）整行移除，
        // 入口只留右下角 FAB（单击新建／长按扇形）。
        // 空位保留：下方篇卡的 i-6 索引不得变。
        if (i == 4) return const SizedBox.shrink();
        if (i == 5) return const SizedBox(height: 2);
        if (shown.isEmpty) {
          if (i == 6) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text(
                  entries.isEmpty ? '还没有日记 · 点右下角 ＋ 开始' : '该筛选下暂无日记',
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
        // 轨道档：条目区整段由 JournalTrackView 自己排（它按「日期块」而不是「篇」分行），
        // 这里只占一个位置，把余下空间让给它——见下方 `if (layout == track)` 的包装。
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
              child: card(
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
                            // 批2e：原型列表卡日期是 `10-17`（不带年）。本年省略年份，
                            // 跨年才补全 `YYYY-MM-DD`——否则去年同月的卡片与今年长得一样。
                            Text(
                                e.day.year == DateTime.now().year
                                    ? '${_two(e.day.month)}-${_two(e.day.day)}'
                                    : '${e.day.year}-${_two(e.day.month)}-${_two(e.day.day)}',
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
                            // 批1a：列表档补收藏/点亮标识——否则筛出「★ 点亮」后
                            // 一整屏都是同样的卡，看不出哪篇被收藏（轨道/INS 档早已有图标）。
                            if (e.starred) ...[
                              Icon(Icons.star,
                                  size: 13, color: tokens.accent),
                              const SizedBox(width: 3),
                            ],
                            if (e.liked) ...[
                              Icon(Icons.favorite,
                                  size: 13, color: tokens.accent),
                              const SizedBox(width: 3),
                            ],
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

  Widget card(BuildContext context, {required Widget child}) {
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

