import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/nav/nav_module.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/grad_fab.dart';
import '../../../shared/linkage/health_mounts.dart';
import '../../../shared/linkage/linkage_events.dart';
import '../../../shared/linkage/search_mounts.dart';
import '../../../shared/linkage/stats_providers.dart';
import '../../../shared/widgets/scroll_pad.dart';
import '../../../shared/widgets/ui_kit.dart';
import 'dashboard_providers.dart';
import 'widgets/today_schedule_card.dart';

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

  // UIUX批（2026-10-12）：编排直达事件监听必须持有引用并在 dispose 取消——
  // 旧实现 listen() 返回值丢弃，切栏销毁重建一次就累积一个监听器（泄漏）。
  StreamSubscription<void>? _editSub;

  // ===== M0末C 主页卡片自由编排（原型 dashToggle/dashMove/drop 排序） =====
  // V1.28⑥：编排态上移 dashDraftProvider（非 null=编排中），壳层返回键可拦截为
  // 「退出编排并保存」而非退出 app；「✓ 完成」与返回键共用 commitDashEdit 落库。

  @override
  void initState() {
    super.initState();
    // V1.27 P3：设置页「主页编排直达」→ 本页直接进编排模式（事件总线，守 R1）。
    _editSub = ref.read(eventBusProvider).on<EnterDashEditEvent>().listen((_) {
      if (mounted) _enterEdit();
    });
  }

  @override
  void dispose() {
    _editSub?.cancel();
    // FAB 菜单开态不在 dispose 清：dispose 阶段 riverpod 禁用 ref，且同步
    // state= 会 markNeedsBuild 已 defunct 的订阅者（框架断言炸）。清态挂壳层
    // 路径变化处（app_router HomeShell：离开今天页即 close），语义等价。
    super.dispose();
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
    ref.read(dashFabOpenProvider.notifier).close();
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
        // V1.42 批4：记物品 → 直达物品页并自动打开建档表单（跨页经事件总线，守 R1）。
        context.go(NavModule.items.path);
        Future.delayed(const Duration(milliseconds: 350),
            () => ref.read(eventBusProvider).publish(const QuickAddEvent('items')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final hour = now.hour;
    final greet = hour < 11 ? '早上好' : hour < 14 ? '中午好' : hour < 18 ? '下午好' : '晚上好';
    // R14-12/14：问候语随「我的」页昵称联动，装饰 emoji 摘除（UI 禁 emoji）。
    final nickNow = ref.watch(settingsControllerProvider).nickOrFallback;
    final streak = ref.watch(streakDaysProvider).valueOrNull ?? 0;
    final tokens = context.tokens;

    final draft = ref.watch(dashDraftProvider);
    final editing = draft != null;
    final order =
        draft ?? ref.watch(settingsControllerProvider).homeCardOrder;

    // UIUX批（2026-10-12）：心情回填——当天日记里最新一次打卡（1..7）映射回
    // 表情标签；无打卡=null。旧实现是纯内存态，切栏回来必丢。
    final moodIdx = ref.watch(dashMoodOfTodayProvider).valueOrNull;
    final moodNow = moodIdx == null || moodIdx < 1 || moodIdx > _moods.length
        ? null
        : _moods[moodIdx - 1].$2;

    Widget card(String id) => switch (id) {
          'greeting' => _HeroCard(greet: '$greet，$nickNow'),
          'mood' => _MoodCard(mood: moodNow, onPick: (m) {
              // L4：心情写入今晚日记（经 shared/linkage 门面，守 R1）。
              // dashMoodOfTodayProvider watch journalsProvider，落库后自动回填。
              final idx = _moods.indexWhere((e) => e.$2 == m) + 1;
              if (idx > 0) {
                ref.read(journalRepositoryProvider).setMoodOfDay(DateTime.now(), idx);
                ref.invalidate(journalsProvider);
              }
            }),
          'events' => const TodayScheduleCard(),
          'inboxBar' => const _InboxBar(),
          // 健康批7：今日健康卡（环＋杯数＋运动分钟＋当前血压位）。卡体与读数装配在
          // shared/linkage/health_mounts.dart（R1：仪表盘不直连健康 feature）；
          // 开关 health.show_dash_card 关＝卡内整块不出现。
          'health' => const HealthDashCard(),
          'days' => const _RecentDaysCard(),
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
                      // UIUX批（2026-10-12）：编辑态卡片仍可点＝点「收集箱/健康」
                      // 直接跳走、编排半途被劫。盖一层只吞**点按**的透明层
                      // （无长按识别器 ⇒ 长按起拖 / ⠿ 把手不受影响）。
                      Positioned.fill(
                        child: GestureDetector(
                          key: ValueKey('card-eat-tap-$id'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () {},
                        ),
                      ),
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
        : ScrollPad(
            // T2-B：切栏销毁子路由，滚动位经常驻 provider 垫回。
            id: 'dash',
            child: ListView(
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
          ),
        );

    // UIUX批（2026-10-12）：FAB 菜单开态收进 dashFabOpenProvider（壳层返回键
    // 收菜单的唯一状态源）；菜单开着时 body 顶部盖半透明遮罩——点任意空白处
    // 收起。旧实现无遮罩、返回键直接退 app＝菜单收不掉。
    final fabOpen = ref.watch(dashFabOpenProvider);

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
          // UIUX批（2026-10-12）：僵尸钮兑现——全局搜索（笔记＋日记双源半屏，
          // 走 shared/linkage 出口守 R1）。旧实现只弹「即将开放」。
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search),
            onPressed: () => showGlobalSearch(context, ref),
          ),
        ],
      ),
      body: Stack(
        children: [
          body,
          if (fabOpen)
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('dash-fab-scrim'),
                behavior: HitTestBehavior.opaque,
                onTap: () => ref.read(dashFabOpenProvider.notifier).close(),
                child: const ColoredBox(color: Colors.black12),
              ),
            ),
        ],
      ),
      // 原型 p-dashboard FAB：＋ 点开快捷记录菜单
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (fabOpen)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // UIUX批（2026-10-12）：五项去 emoji 改线性图标（原型 fab-act 同批）。
                  for (final (i, ic, label) in const [
                    (0, Icons.bolt_outlined, '记一条想法'),
                    (1, Icons.check_box_outlined, '记待办'),
                    (2, Icons.menu_book_outlined, '记日记'),
                    (3, Icons.currency_yuan_outlined, '记一笔'),
                    (4, Icons.inventory_2_outlined, '记物品'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: FabActionCard(
                          label: label,
                          icon: ic,
                          onTap: () => _fabAction(i)),
                    ),
                ],
              ),
            ),
          AnimatedRotation(
            duration: const Duration(milliseconds: 180),
            turns: fabOpen ? 1 / 8 : 0,
            child: GradFab(
              tooltip: '快速记录',
              icon: const Icon(Icons.add, color: Colors.white, size: 26),
              onTap: () => ref.read(dashFabOpenProvider.notifier).toggle(),
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
          // UIUX批（2026-10-12）：28px < 44px 最小触达标准（编排钮是高频微操）。
          width: 44,
          height: 44,
          child: Center(
            child: Text(label,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
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
    // UIUX批（2026-10-12）：冷启动加载态不再显示「0 个待办」假数——数据未落位
    // （value 为 null 且 loading）显示「—」，落位后跳真数（重载沿用上帧数据不闪）。
    final todosAsync = ref.watch(todosProvider);
    final todosData = todosAsync.valueOrNull;
    final todosLoading = todosAsync.isLoading && todosData == null;
    final todos = todosData ?? const [];
    // V1.42 批4（L12/L13 挂载点）：今日持有成本由 items 计费引擎实算汇入。
    final itemsAsync = ref.watch(itemsDataProvider);
    final itemsData = itemsAsync.valueOrNull;
    final itemsLoading = itemsAsync.isLoading && itemsData == null;
    final itemsNow = ref.watch(itemsClockProvider)();
    final billingCount = itemsData?.active.length ?? 0;
    final dailyCost =
        itemsData == null ? 0.0 : totalDailyCost(itemsData.items, itemsNow);

    // R14-14：四个数字全部对齐已确认原型口径，且与「今日日程」卡同源。
    final now = DateTime.now();
    final day0 = DateTime(now.year, now.month, now.day);
    bool onToday(DateTime? d) => d != null &&
        d.year == now.year &&
        d.month == now.month &&
        d.day == now.day;
    // 今日待办＝截止日落在今天（逾期另有「已过期」入口，不混计）。
    final todayTodos = todos.where((t) => onToday(t.dueAt)).toList();
    final doneToday = todayTodos.where((t) => t.done).length;
    final total = todayTodos.length;
    final ratio = total == 0 ? 0.0 : doneToday / total;
    // 本周精力「重要」象限占比：只统计未完成待办（原型同款谓词）。
    final pending = todos.where((t) => !t.done && !t.dropped).toList();
    final important =
        pending.where((t) => t.quadrant.value <= 2).length;
    final impPct = pending.isEmpty
        ? null
        : (important * 100 / pending.length).round();
    // 场安排＝今日日程列表条数（时间块单源 · B10 起 events 并入块表，与 TodayScheduleCard 同一函数出数）。
    final blocksAsync = ref.watch(dayBlocksProvider(day0));
    final plansLoading = blocksAsync.isLoading && blocksAsync.valueOrNull == null;
    final plans = mergeTodayPlans(
      blocksAsync.valueOrNull ?? const <TimeBlock>[],
      catColors: const {},
      accent: tokens.accent,
    );

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
              // 真机反馈轮4②：数字可点直达对应列表页（LH-K15 虚线下划线语义）。
              GestureDetector(
                key: const ValueKey('hero-todo-tap'),
                behavior: HitTestBehavior.opaque,
                onTap: () => context.go(NavModule.todo.path),
                child: Text(todosLoading ? '—' : '$total',
                    key: const ValueKey('hero-todo-count'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        decoration: TextDecoration.underline,
                        decorationStyle: TextDecorationStyle.dashed,
                        decorationColor: Colors.white54)),
              ),
              const Text(' 个待办 · ',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              GestureDetector(
                key: const ValueKey('hero-plan-tap'),
                behavior: HitTestBehavior.opaque,
                onTap: () => context.go(NavModule.calendar.path),
                child: Text(plansLoading ? '—' : '${plans.length}',
                    key: const ValueKey('hero-plan-count'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        decoration: TextDecoration.underline,
                        decorationStyle: TextDecorationStyle.dashed,
                        decorationColor: Colors.white54)),
              ),
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
                  // 防御：Column 横向松约束，文案超长即溢出——Flexible＋单行省略兜底。
                  Flexible(
                    child: Text(
                      '本周 $impPct% 精力在「重要」象限${energyCaption(impPct)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  key: const ValueKey('dash-todo-card'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => context.go(NavModule.todo.path),
                  // UIUX批：按压缩放反馈（原型 active:scale-[.98] 对译）。
                  child: _Pressable(
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
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  key: const ValueKey('dash-cost-card'),
                  onTap: () => context.push('/items/stats'),
                  child: _Pressable(
                    child: _MiniGlass(
                      label: '今日持有成本',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(itemsLoading ? '¥ —' : '¥ ${dailyCost.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                              const Text('/天',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 11)),
                            ],
                          ),
                          // UIUX批：0 件计费不再是「0 件物品计费中」假口径，给空态话。
                          Text(itemsLoading
                                  ? '…'
                                  : billingCount == 0
                                      ? '暂无计费物品 ›'
                                      : '$billingCount 件物品计费中 ›',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
                ),
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

/// UIUX批：按压缩放反馈（原型 hero 小卡 active:scale-[.98] 对译）。
/// 只管按压视觉，点击行为仍由外层 GestureDetector 承担。
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child});

  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: _down ? 0.98 : 1,
        child: widget.child,
      ),
    );
  }
}

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

/// V1.42 批4 · 首页倒数卡「最近的日子」（联动 L10 · 原型 dashDayChips 3899-3905 对译）。
/// dashboardUpcoming 实算前三（置顶恒前 · 倒数升序 · 已过期不入），
/// 渐变迷你卡 = 图标+标题 / 大数字天数；点卡直达日子详情，「全部 ›」回日子主页。
class _RecentDaysCard extends ConsumerWidget {
  const _RecentDaysCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(daysDataProvider).valueOrNull;
    final now = ref.watch(daysClockProvider)();
    final top = data == null ? const <DayEntry>[] : dashboardUpcoming(data.days, now);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                  child: Text('最近的日子',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
              InkWell(
                key: const ValueKey('dash-days-all'),
                onTap: () => context.go(NavModule.days.path),
                child: Text('全部 ›',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.tokens.accent)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (top.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('暂无日子',
                  style: TextStyle(fontSize: 11, color: kDaysMuted)),
            )
          else
            Row(
              children: [
                for (final (i, d) in top.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      key: ValueKey('dash-day-${d.id}'),
                      onTap: () => context.push('/days/detail?id=${d.id}'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: dayGradientOf(d.colorKey),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(dayIconOf(d.iconId),
                                    size: 12,
                                    color: Colors.white.withValues(alpha: .85)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(d.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          // UIUX批：9px→10px（390 屏实测偏小）。
                                          fontSize: 10,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text('${countdownDays(d, now)}',
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white)),
                                const Text(' 天',
                                    style: TextStyle(
                                        fontSize: 9, color: Colors.white70)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
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
          // R14-8：未选时不留教学句（原型同款），选中后才出这一行状态提示。
          if (mood != null) ...[
            const SizedBox(height: 4),
            Center(
              child: Text(
                '已记录：$mood · ${_DashboardPageState._moodTips[mood]}（将进入今晚日记）',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: tokens.accent),
              ),
            ),
          ],
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
                  // UIUX批：0 条未整理不再是「0 条未整理」假口径，给清空态话（入口保留）。
                  Text(pending == 0 ? '收集箱 · 已清空' : '收集箱 · $pending 条未整理',
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
        // V1.52：计时中块按已耗时计入（原 endMin-startMin 对计时块恒为 0）
        minutesByCat[b.catName] =
            (minutesByCat[b.catName] ?? 0) + b.durationMin(now);
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

    return InkWell(
      // V1.52：点卡片直达时间账本（L4 全量统计）
      borderRadius: BorderRadius.circular(20),
      onTap: () => context.push('/time-stats'),
      child: Container(
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
          Text('合计 ${_fmtMin(totalMin)} · 点开看时间账本',
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        ],
      ),
      ),
    );
  }

  static String _fmtMin(int m) {
    final d = m ~/ 1440, h = (m % 1440) ~/ 60, r = m % 60;
    if (m <= 0) return '0 分';
    return [
      if (d > 0) '$d 天',
      if (h > 0) '$h 时',
      if (r > 0 || (d == 0 && h == 0)) '$r 分',
    ].join(' ');
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

/// 全部功能宫格（原型 D.grid：emoji + 浅灰圆角底块 14 项 · 未建灰显 + 版本角标）。
/// V1.58 反馈轮5：日记/笔记两枚摘除（与记录页 ⇄ 四段重复），
/// 「阅读」带段参深链 → 记录页自动切到阅读视图。
class _AllModulesCard extends StatelessWidget {
  const _AllModulesCard();

  /// AI批4-A：AI 验证已接线（图标位支持线性 IconData，替代 emoji 占位）。
  static const _aiVerifyRoute = '/settings/ai/verify';

  /// 非底栏栏目的栈页：进这些一律 push（go 清栈会让它成为栈底，返回键直接退 app）。
  static const _stackRoutes = {_aiVerifyRoute, '/media/shelf', '/health', '/mindmap'};

  /// UIUX批（2026-10-12）：宫格 emoji 图标全量迁线性 IconData（原型 D.grid 同批
  /// 去 emoji 改线性 SVG；影音游/健康/AI 三枚此前已线性）。
  static const _mods = <(IconData, String, String, String?)>[
    (Icons.check_box_outlined, '待办', '/todo', null),
    (Icons.schedule_outlined, '时间', '/calendar', null),
    (Icons.menu_book_outlined, '阅读', '/journal?tab=book', null),
    (Icons.movie_outlined, '影音游', '/media/shelf', null),
    (Icons.bolt_outlined, '收集箱', '/inbox', null),
    (Icons.currency_yuan_outlined, '记账', '/ledger', null),
    (Icons.inventory_2_outlined, '物品', '/items', null),
    (Icons.cake_outlined, '日子', '/days', null),
    (Icons.monitor_heart_outlined, '健康', '/health', null),
    (Icons.repeat_outlined, '习惯', '/habits', null),
    (Icons.explore_outlined, '目标', '/goals', null),
    (Icons.account_tree_outlined, '思维导图', '/mindmap', null),
    (Icons.child_care_outlined, '呵护', '/care', null),
    (Icons.smart_toy_outlined, 'AI 验证', _aiVerifyRoute, null),
    (Icons.settings_outlined, '设置', '/settings', null),
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
                  // UIUX批（2026-10-12）：14 枚全部已建（route 非空），灰位分支
                  // 随 emoji 迁移一并摘除；ver 角标位保留（后续新模块占位用）。
                  for (final (ic, label, route, ver) in _mods)
                    SizedBox(
                      width: w,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _stackRoutes.contains(route)
                            // 二级/模块栈页走 push 保留返回栈，栏目行仍 go。
                            ? context.push(route)
                            : context.go(route),
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
                                      // 图标位：UIUX批起全部线性 IconData（emoji 已迁）。
                                      child: Icon(ic, size: 20, color: scheme.onSurfaceVariant),
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
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
