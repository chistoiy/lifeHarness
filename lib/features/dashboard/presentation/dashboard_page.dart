import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/nav/nav_module.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/grad_fab.dart';
import '../../../shared/linkage/linkage_events.dart';
import '../../../shared/linkage/stats_providers.dart';
import '../../../shared/widgets/ui_kit.dart';
import 'dashboard_providers.dart';

/// 模块6 今日仪表盘（对齐原型 p-dashboard）。
/// 真数据：待办数/进度环/今日日程列表/收集箱未整理/连续记录天/本周时间分布。
class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  /// 心情（原型 moodRow：emoji + data-m 标签）。
  static const _moods = [
    ('😄', '开心'), ('😌', '平静'), ('😐', '一般'), ('😪', '疲惫'),
    ('😰', '焦虑'), ('😢', '低落'), ('😡', '愤怒'),
  ];

  static const _moodTips = {
    '开心': '状态满分，继续保持 ✨',
    '平静': '平稳的一天，也很珍贵',
    '一般': '没什么波澜，记录就是意义',
    '疲惫': '辛苦了，今晚早点休息',
    '焦虑': '把担心的事写进收集箱，拆小它',
    '低落': '允许自己低落一会儿，会过去的',
    '愤怒': '深呼吸，晚点再处理这件事',
  };

  String? _mood;
  bool _fabMenu = false;

  // ===== M0末C 主页卡片自由编排（原型 dashToggle/dashMove/drop 排序） =====
  // V1.28⑥：编排态上移 dashDraftProvider（非 null=编排中），壳层返回键可拦截为
  // 「退出编排并保存」而非退出 app；「✓ 完成」与返回键共用 commitDashEdit 落库。

  @override
  void initState() {
    super.initState();
    // V1.27 P3：设置页「主页编排直达」→ 本页直接进编排模式（事件总线，守 R1）。
    ref.read(eventBusProvider).on<EnterDashEditEvent>().listen((_) {
      if (mounted) _enterEdit();
    });
  }

  /// V1.27 H1：长按卡片 / P3 编排直达 共用入口。
  void _enterEdit() {
    if (ref.read(dashDraftProvider) != null) return;
    ref.read(dashDraftProvider.notifier)
        .enter([...ref.read(settingsControllerProvider).homeCardOrder]);
    if (mounted) _toastOf(context, '已进入编排模式 · 拖动或 ↑↓ 调整');
  }

  void _finishEdit() {
    if (ref.read(dashDraftProvider.notifier).commit() && mounted) {
      _toastOf(context, '主页布局已保存 · 下次启动保持此顺序');
    }
  }

  void _moveCard(int i, int dir) {
    final draft = [...ref.read(dashDraftProvider)!];
    final to = i + dir;
    if (to < 0 || to >= draft.length) {
      _toastOf(context, dir < 0 ? '已在第一位' : '已在最后一位');
      return;
    }
    draft.insert(to, draft.removeAt(i));
    ref.read(dashDraftProvider.notifier).set(draft);
  }

  void _reorder(int oldI, int newI) {
    final draft = [...ref.read(dashDraftProvider)!];
    if (newI > oldI) newI--;
    draft.insert(newI, draft.removeAt(oldI));
    ref.read(dashDraftProvider.notifier).set(draft);
  }

  /// FAB 菜单动作（原型 fabGo：跳转目标模块；未开放模块给出版本提示）。
  void _fabAction(int i) {
    setState(() => _fabMenu = false);
    switch (i) {
      case 0:
        context.go(NavModule.inbox.path);
        // 到达收集箱后聚焦输入框（原型 fabGo 行为；跨页经事件总线，守 R1）。
        Future.delayed(const Duration(milliseconds: 350),
            () => ref.read(eventBusProvider).publish(const QuickAddEvent('inbox')));
      case 1:
        context.go(NavModule.todo.path);
        // 到达待办页后自动展开其 FAB 类型菜单（同款行卡；跨模块经事件总线，守 R1）。
        Future.delayed(const Duration(milliseconds: 350),
            () => ref.read(eventBusProvider).publish(const QuickAddEvent('todo')));
      case 2:
        context.push('/journal/edit');
      case 3:
        // 记账批1：直达记一笔全屏页（原型 fabGo→openL2）。
        context.push('/ledger/add');
      case 4:
        _toastOf(context, '「物品」· 规划 V1.0');
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final hour = now.hour;
    final greet = hour < 11 ? '早上好' : hour < 14 ? '中午好' : hour < 18 ? '下午好' : '晚上好';
    final emoji = hour < 18 ? '☀️' : '🌙';
    final streak = ref.watch(streakDaysProvider).valueOrNull ?? 0;
    final tokens = context.tokens;

    final draft = ref.watch(dashDraftProvider);
    final editing = draft != null;
    final order =
        draft ?? ref.watch(settingsControllerProvider).homeCardOrder;

    Widget card(String id) => switch (id) {
          'greeting' => _HeroCard(greet: '$greet，CHIST $emoji'),
          'mood' => _MoodCard(mood: _mood, onPick: (m) {
              setState(() => _mood = m);
              // L4：心情写入今晚日记（经 shared/linkage 门面，守 R1）。
              final idx = _moods.indexWhere((e) => e.$2 == m) + 1;
              if (idx > 0) {
                ref.read(journalRepositoryProvider).setMoodOfDay(DateTime.now(), idx);
                ref.invalidate(journalsProvider);
              }
            }),
          'events' => const _TodayScheduleCard(),
          'inboxBar' => const _InboxBar(),
          'chart' => const _TimeDistCard(),
          'grid' => const _AllModulesCard(),
          _ => const SizedBox.shrink(),
        };

    // 编排模式：长按卡片拖拽 + 右侧 ⠿ 把手即拖 + ↑↓ 微调；「完成」落盘（原型 dash-edit）
    final body = editing
        ? ReorderableListView(
            key: const ValueKey('dash-reorder'),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            onReorder: _reorder,
            header: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: tokens.accent.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: tokens.accent.withValues(alpha: .3)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('⇅ 编排模式：拖动卡片调整顺序，或用 ↑↓ 微调',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                  // V1.27 H1：✓ 完成从 AppBar 移进提示条（AppBar 编排钮已删，长按进入）
                  InkWell(
                    key: const ValueKey('dash-done-btn'),
                    borderRadius: BorderRadius.circular(20),
                    onTap: _finishEdit,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                          color: tokens.accent,
                          borderRadius: BorderRadius.circular(20)),
                      child: const Text('✓ 完成',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
            children: [
              for (final (i, id) in order.indexed)
                Padding(
                  key: ValueKey('card-$id'),
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Stack(
                    children: [
                      card(id),
                      Positioned(
                        right: 2,
                        top: 34,
                        child: Column(
                          children: [
                            // V1.28⑥ ⠿ 把手=按下即拖（ReorderableDragStartListener）；
                            // 卡片任意处长按 300ms 也可起拖（默认 mobile 拖拽柄）。
                            ReorderableDragStartListener(
                              index: i,
                              child: _ArrowBtn(
                                  key: ValueKey('grip-$id'),
                                  label: '⠿',
                                  onTap: null),
                            ),
                            const SizedBox(height: 6),
                            _ArrowBtn(
                                key: ValueKey('up-$id'),
                                label: '↑',
                                onTap: () => _moveCard(i, -1)),
                            const SizedBox(height: 6),
                            _ArrowBtn(
                                key: ValueKey('down-$id'),
                                label: '↓',
                                onTap: () => _moveCard(i, 1)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          )
        : ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              // V1.27 H1：长按任意卡片 550ms → 进入编排模式（原型 dashLongPress）
              for (final id in order) ...[
                GestureDetector(
                  key: ValueKey('card-press-$id'),
                  onLongPress: _enterEdit,
                  child: card(id),
                ),
                const SizedBox(height: 14),
              ],
              Center(
                child: Text(
                  'LifeHarness · 纯本地 · 离线可用',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                ),
              ),
            ],
          );

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('今天'),
            Text(
              '${now.month}月${now.day}日 周${_weekdays[now.weekday - 1]} · 第 $streak 天记录',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.normal,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          // V1.27 H1：右上角「⇄ 编排」按钮移除（长按卡片进入编排，✓完成在提示条内）
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search),
            onPressed: () => _toastOf(context, '全局搜索 · 即将开放'),
          ),
        ],
      ),
      body: body,
      // 原型 p-dashboard FAB：＋ 点开快捷记录菜单
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_fabMenu)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final (i, label) in const [
                    (0, '⚡ 记一条想法'),
                    (1, '✅ 记待办'),
                    (2, '📔 记日记'),
                    (3, '💰 记一笔'),
                    (4, '📦 记物品'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: FabActionCard(
                          label: label, onTap: () => _fabAction(i)),
                    ),
                ],
              ),
            ),
          AnimatedRotation(
            duration: const Duration(milliseconds: 180),
            turns: _fabMenu ? 1 / 8 : 0,
            child: GradFab(
              tooltip: '快速记录',
              icon: const Icon(Icons.add, color: Colors.white, size: 26),
              onTap: () => setState(() => _fabMenu = !_fabMenu),
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      extendBody: false,
      backgroundColor: tokens.page,
    );
  }
}

/// 编排模式右侧圆钮（↑↓ 微调 / ⠿ 拖拽把手，原型 .mv-btn）。
class _ArrowBtn extends StatelessWidget {
  const _ArrowBtn({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.card,
      shape: CircleBorder(side: BorderSide(color: tokens.cardBorder)),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Center(
            child: Text(label,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          ),
        ),
      ),
    );
  }
}

/// 旋转角度等共享组件见 core/widgets/grad_fab.dart。

/// 问候卡：今日待办/安排真数 + 重要象限精力胶囊 + 进度环 x/y + 持有成本占位。
class _HeroCard extends ConsumerWidget {
  const _HeroCard({required this.greet});

  final String greet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final todos = ref.watch(todosProvider).valueOrNull ?? const [];
    final todayEvents = ref.watch(todayEventCountProvider).valueOrNull ?? 0;

    final pending = todos.where((t) => !t.done).toList();
    final doneToday = todos.where((t) => t.done).length;
    final total = todos.length;
    final ratio = total == 0 ? 0.0 : doneToday / total;
    // 本周精力「重要」象限占比（原型 62% 胶囊 · 用真实象限分布计算）
    final counted = todos.where((t) => !t.dropped).toList();
    final important =
        counted.where((t) => t.quadrant.value <= 2).length;
    final impPct = counted.isEmpty
        ? null
        : (important * 100 / counted.length).round();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: tokens.gradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: tokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(greet, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              const Text('今天有 ',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              Text('${pending.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
              const Text(' 个待办 · ',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              Text('$todayEvents',
                  style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
              const Text(' 场安排',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            ],
          ),
          if (impPct != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: Color(0xFF6EE7B7))),
                  const SizedBox(width: 8),
                  Text(
                      '本周 $impPct% 精力在「重要」象限${energyCaption(impPct)}',
                      style: const TextStyle(color: Colors.white, fontSize: 11.5)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MiniGlass(
                  label: '今日待办',
                  child: Row(
                    children: [
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: ratio,
                              strokeWidth: 4.5,
                              color: Colors.white,
                              backgroundColor: Colors.white24,
                            ),
                            Text('${(ratio * 100).round()}%',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('$doneToday/$total\n已完成',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11, height: 1.35)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniGlass(
                  label: '今日持有成本',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('¥ —',
                          style: TextStyle(
                              color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                      Text('物品模块规划 V1.0',
                          style: TextStyle(color: Colors.white70, fontSize: 10)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // V1.27 H1：删「⇄ 编排」按钮，长按任意卡片进入编排（原型同款提示行）
          const Row(
            children: [
              Expanded(
                child: Text('长按任意卡片可编排顺序',
                    style: TextStyle(color: Colors.white70, fontSize: 10.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

void _toastOf(BuildContext context, String msg) =>
    AppToast.show(context, msg, ms: 1500);

class _MiniGlass extends StatelessWidget {
  const _MiniGlass({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

/// 今日心情（原型 moodRow：点选放大 + 记录反馈文案）。
class _MoodCard extends StatelessWidget {
  const _MoodCard({required this.mood, required this.onPick});

  final String? mood;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('今日心情', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final (e, label) in _DashboardPageState._moods)
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => onPick(label),
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 150),
                    scale: mood == label ? 1.25 : 1,
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Opacity(
                        opacity: mood == null || mood == label ? 1 : .45,
                        child: Text(e, style: const TextStyle(fontSize: 23)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              mood == null
                  ? '点一下，记录今天的心情'
                  : '已记录：$mood · ${_DashboardPageState._moodTips[mood]}（将进入今晚日记）',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11,
                  color: mood == null ? Colors.grey.shade400 : tokens.accent),
            ),
          ),
        ],
      ),
    );
  }
}

/// 今日日程（原型 dashEvents：色条 + 标题 + 起止时间卡列表）。
class _TodayScheduleCard extends ConsumerWidget {
  const _TodayScheduleCard();

  static String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final events = (ref.watch(eventsProvider).valueOrNull ?? const <CalEvent>[])
        .where((e) =>
            e.start.year == now.year && e.start.month == now.month && e.start.day == now.day)
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                  child: Text('今日日程',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
              TextButton(
                onPressed: () => context.go(NavModule.calendar.path),
                child: Text('查看全部 ›',
                    style: TextStyle(
                        fontSize: 12,
                        color: tokens.accent,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('今天还没有安排',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ),
          for (final e in events.take(4))
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: .04),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 30,
                    decoration: BoxDecoration(
                      color: e.colorOf(tokens.accent),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(e.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
                  Text(
                      e.allDay
                          ? '全天'
                          : '${_hm(e.start)}-${e.end == null ? '' : _hm(e.end!)}',
                      style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          if (events.length > 4)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('还有 ${events.length - 4} 项…',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }
}

/// 收集箱快捷条（真实未整理计数）。
class _InboxBar extends ConsumerWidget {
  const _InboxBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(inboxPendingCountProvider).valueOrNull ?? 0;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => context.go(NavModule.inbox.path),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: context.cardDecoration,
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: .15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('⚡', style: TextStyle(fontSize: 15)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('收集箱 · $pending 条未整理',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  Text('快速记下，稍后再分类',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ],
              ),
            ),
            const Text('›', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

/// 本周时间分布（原型四色 donut + 图例；数据=近 7 天时间块按分类聚合）。
class _TimeDistCard extends ConsumerWidget {
  const _TimeDistCard();

  static const _palette = [
    Color(0xFF6366F1), // 随主题的 brand 位（实际用 accent 覆盖第一个）
    Color(0xFF2DD4BF),
    Color(0xFFF59E0B),
    Color(0xFFFB7185),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();

    // 近 7 天（含今日）时间块聚合：分类 → 分钟
    final minutesByCat = <String, int>{};
    var loading = false;
    for (var i = 6; i >= 0; i--) {
      final d = DateTime(now.year, now.month, now.day - i);
      final blocks = ref.watch(dayBlocksProvider(d)).valueOrNull;
      if (blocks == null) {
        loading = true;
        continue;
      }
      for (final TimeBlock b in blocks) {
        minutesByCat[b.catName] =
            (minutesByCat[b.catName] ?? 0) + math.max(0, b.endMin - b.startMin);
      }
    }
    final entries = minutesByCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    var top = [for (final e in entries.take(4)) (e.key, e.value)];
    final restMin = entries.skip(4).fold<int>(0, (s, e) => s + e.value);
    if (restMin > 0) top = [...top, ('其他', restMin)];
    final totalMin = top.fold<int>(0, (s, e) => s + e.$2);

    final colors = [
      tokens.accent,
      for (final c in _palette.skip(1)) c,
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('本周时间分布',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 96,
                height: 96,
                child: CustomPaint(
                  painter: _DonutPainter(
                    values: totalMin == 0 ? const [] : [for (final e in top) e.$2],
                    colors: colors,
                    empty: totalMin == 0 && !loading,
                    emptyColor: scheme.onSurface.withValues(alpha: .08),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: totalMin == 0
                    ? Text(
                        loading ? '加载中…' : '暂无时间记录\n在「时间」块视图滑选标记后自动统计',
                        style: TextStyle(
                            fontSize: 11.5, height: 1.5, color: scheme.onSurfaceVariant))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < top.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: colors[i % colors.length])),
                                  const SizedBox(width: 6),
                                  Expanded(
                                      child: Text(top[i].$1,
                                          style: const TextStyle(fontSize: 12))),
                                  Text(
                                      '${(top[i].$2 * 100 / totalMin).round()}%',
                                      style: const TextStyle(
                                          fontSize: 12, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(
      {required this.values, required this.colors, required this.empty, required this.emptyColor});

  final List<int> values;
  final List<Color> colors;
  final bool empty;
  final Color emptyColor;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 8;
    final total = values.fold<int>(0, (s, v) => s + v);
    if (empty || total == 0) {
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 14
            ..color = emptyColor);
      return;
    }
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * 2 * math.pi;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        start,
        math.max(0.001, sweep - 0.03), // 分段留细缝（原型 dasharray 间效果）
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..color = colors[i % colors.length],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.values != values || old.colors != colors || old.empty != empty;
}

/// 全部功能宫格（原型 D.grid：emoji + 浅灰圆角底块 17 项 · 未建灰显 + 版本角标）。
class _AllModulesCard extends StatelessWidget {
  const _AllModulesCard();

  /// AI批4-A：AI 验证已接线（图标位支持线性 IconData，替代 emoji 占位）。
  static const _aiVerifyRoute = '/settings/ai/verify';

  static const _mods = <(Object, String, String?, String?)>[
    ('✅', '待办', '/todo', null),
    ('⏱️', '时间', '/calendar', null),
    ('📔', '日记', '/journal', null),
    ('📝', '笔记', null, 'V0.5'),
    ('📚', '阅读', null, 'V0.5'),
    ('⚡', '收集箱', '/inbox', null),
    ('💰', '记账', '/ledger', null),
    ('📦', '物品', null, 'V1.0'),
    ('🎂', '日子', null, 'V1.0'),
    ('🏃', '健康', null, 'V1.0'),
    ('🔁', '习惯', '/habits', null),
    ('🧭', '目标', null, 'V1.0'),
    ('🧰', '小工具', null, 'V1.x'),
    ('🍼', '呵护', '/care', null),
    ('🧩', '插件中心', null, 'V1.x'),
    (Icons.smart_toy_outlined, 'AI 验证', _aiVerifyRoute, null),
    ('⚙️', '设置', '/settings', null),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('全部功能', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              const cols = 4;
              const gap = 8.0;
              final w = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final (ic, label, route, ver) in _mods)
                    SizedBox(
                      width: w,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: route == null
                            ? () => _toastOf(context, '「$label」· 规划 $ver')
                            : () => route == _aiVerifyRoute
                                // AI批4-A：二级工具页走 push 保留返回栈，其余行机制不变。
                                ? context.push(route)
                                : context.go(route),
                        child: Opacity(
                          opacity: route == null ? .45 : 1,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              children: [
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: scheme.onSurface.withValues(alpha: .06),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      // 图标位：emoji 或线性 IconData（AI批4-A 最小扩展）。
                                      child: ic is IconData
                                          ? Icon(ic, size: 20, color: scheme.onSurfaceVariant)
                                          : Text(ic as String,
                                              style: const TextStyle(fontSize: 20)),
                                    ),
                                    if (ver != null)
                                      Positioned(
                                        right: -6,
                                        top: -4,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: scheme.onSurface.withValues(alpha: .08),
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          child: Text(ver,
                                              style: TextStyle(
                                                  fontSize: 7,
                                                  color: scheme.onSurfaceVariant)),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Text(label,
                                    style: TextStyle(
                                        fontSize: 11, color: scheme.onSurface)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
