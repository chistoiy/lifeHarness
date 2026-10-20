import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/grad_fab.dart';
import '../../../shared/linkage/stats_providers.dart';
// UIUX批（2026-10-12）：搜索钮接全局搜索半屏（守 R1：经 shared/linkage 出口）。
import '../../../shared/linkage/search_mounts.dart';
import '../data/legacy_event_merge.dart';
import '../domain/block_ops.dart';
import '../domain/time_block.dart';
import '../domain/week_align.dart';
import '../../../shared/widgets/scroll_pad.dart';
import 'calendar_providers.dart';
import 'widgets/async_error_retry.dart';
import 'widgets/grid_day_view.dart';
import 'widgets/time_pick_sheet.dart';
import '../../../core/widgets/wheel_date.dart';

/// 模块1 时间（V1.19~V1.24 · 原「日程」改名）。
/// 定位=记录用户在各个时间段做了什么事情：四视图（轴/块/日/周）同一数据不同投影，
/// 操作逻辑统一 CRUD；顶栏年月日轮式跳转 + 非今天显「今」；添加统一 sheetTimePick。
/// 当月天数（避开 DateTime(y,m+1,0)：day-0 归一化在 FakeAsync 时区解析下会挂死）。

/// 计时/当前游标玫红（批2 提为文件级常量：轴/日视图与游标共用，色值棘轮净计数不升）。
const _kTimingRose = Color(0xFFF43F5E);

/// 定时待办紫罗兰（轴/日视图紫行同源色）。
const _kTodoViolet = Color(0xFF8B5CF6);

/// 定时待办紫行点击（轴/日视图同源 F4-1）：番茄待办先过单活约束再进番茄页；
/// 普通待办切换完成态（联动 L2）。
Future<void> schedTodoTap(BuildContext context, WidgetRef ref, Todo t) async {
  if (t.isPomo && !t.done) {
    final cur = ref.read(activePomoProvider);
    if (cur != null && cur.todoId != t.id) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已有番茄进行中 · 请先结束（单活约束）')));
      return;
    }
    final s = (cur != null && cur.todoId == t.id)
        ? cur
        : PomoSession(
            todoId: t.id!,
            title: t.title,
            mode: t.pomoMode ?? 'up',
            minutes: t.pomoMin);
    if (cur == null) ref.read(activePomoProvider.notifier).state = s;
    if (context.mounted) context.push('/pomo', extra: s);
    return;
  }
  final wasDone = t.done;
  await ref.read(todoRepositoryProvider).toggleDone(t);
  ref.invalidate(todosProvider);
  if (context.mounted && !wasDone) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✔ 定时待办完成 · 轴视图同步划线（联动 L2）')));
  }
}
int daysInMonthOf(int y, int m) {
  const dm = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (m != 2) return dm[m - 1];
  return (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) ? 29 : 28;
}
class CalendarPage extends ConsumerWidget {
  const CalendarPage({super.key});

  /// C7（冻结）一次性收口守卫：每进程只跑一次（避免每次重建都打两条 SELECT）。
  static bool _reconciled = false;

  /// C2/B9（冻结）：月历展开态统一写入口——改内存态并持久化（跨会话记住）。
  /// 切视图档**不经过**这里（解耦）；只有用户手动收/展才写盘。
  static void setMonthExpanded(WidgetRef ref, bool v) {
    ref.read(monthExpandedProvider.notifier).state = v;
    unawaited(
        ref.read(settingsControllerProvider.notifier).setCalMonthExpanded(v));
  }

  static const _wdHeaders = ['日', '一', '二', '三', '四', '五', '六'];
  static const _wds = ['日', '一', '二', '三', '四', '五', '六'];

  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(calSelectedProvider);
    final view = ref.watch(calViewModeProvider);
    final now = DateTime.now();
    final isToday = sameDay(selected, now);

    // B10（冻结批 · 产品裁决 2026-10-13「搬，旧表不维护了」）：进模块时把旧
    // events 表一次性并入时间块后删行退役（幂等护栏=表空即空跑）。编辑自此
    // 一律走时间块；C7 reconcile（旧 active 收口）已并入搬移换算。
    if (!_reconciled) {
      _reconciled = true;
      unawaited(LegacyEventMerge.run(ref.read(legacyEventMergeDbProvider)));
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // V1.27 C1/C4：去「时间+搜索」标题行省一行；搜索下移到日期行工具区
            _TimeHeader(selected: selected, isToday: isToday),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  // 智能折叠：用户向下拖滚超阈收起月历为周行。
                  // 仅认 drag 驱动的通知——否则点「展开」后重建产生的 ScrollEnd（滚动位仍>24）会立刻再收起。
                  if (ref.read(monthExpandedProvider) &&
                      n.metrics.axis == Axis.vertical &&
                      n.metrics.pixels > 24 &&
                      n is ScrollUpdateNotification &&
                      n.dragDetails != null) {
                    // C2：用户手动收起=写盘（跨会话记住）。
                    CalendarPage.setMonthExpanded(ref, false);
                  }
                  return false;
                },
                child: ScrollPad(
                  // T2-B：时间主屏滚动垫；智能折叠通知照常穿层上抛。
                  id: 'cal',
                  child: Builder(builder: (context) {
                  // F6-1：主屏 builder 化——周视图 24 小时行铺进本列表，
                  // 视口内才构建（168 格禁全量）；其余视图仍为单件。
                  final isWeek =
                      view != 'axis' && view != 'block' && view != 'day';
                  final headCount = view == 'block' ? 4 : 2;
                  final itemCount = isWeek ? headCount + 1 + 24 : headCount + 1;
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
                    itemCount: itemCount,
                    itemBuilder: (context, i) {
                      if (i == 0) return _CalendarRegion(selected: selected);
                      if (i == 1) return const SizedBox(height: 10);
                      if (view == 'block') {
                        if (i == 2) return const _BlockToolbar();
                        if (i == 3) return const SizedBox(height: 8);
                      }
                      if (!isWeek) {
                        return switch (view) {
                          'axis' => _AxisView(selected: selected),
                          'block' => GridDayView(day: selected),
                          _ => _DayHoursView(selected: selected),
                        };
                      }
                      final body = i - headCount; // 0=头件，1..24=小时行
                      if (body == 0) {
                        return _WeekBoardHeader(selected: selected);
                      }
                      return _WeekRow(selected: selected, hour: body - 1);
                    },
                  );
                }),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: GradFab(
        tooltip: '添加时间块',
        icon: const Icon(Icons.add, color: Colors.white, size: 26),
        onTap: () => showTimePickSheet(context, ref, day: selected),
      ),
    );
  }
}

/// V1.28⑤ 日历区动画容器：
/// · 切月/切天（左右滑动）=横向滑入+淡入（原型 mshift 0.3s cubic-bezier(.22,.61,.36,1)）；
/// · 展开/收起（mexpand/wreveal）=AnimatedSize 高度过渡 + 月历↔周行交叉淡切。
class _CalendarRegion extends ConsumerStatefulWidget {
  const _CalendarRegion({required this.selected});
  final DateTime selected;

  @override
  ConsumerState<_CalendarRegion> createState() => _CalendarRegionState();
}

class _CalendarRegionState extends ConsumerState<_CalendarRegion>
    with SingleTickerProviderStateMixin {
  static const _curve = Cubic(0.22, 0.61, 0.36, 1.0);

  late final AnimationController _shift = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300))
    ..value = 1;
  int _dir = 1;
  late int _key;
  late bool _lastExpanded;

  static int _monthKey(DateTime d) => d.year * 12 + d.month;
  static int _dayKey(DateTime d) => d.year * 372 + d.month * 31 + d.day;

  @override
  void initState() {
    super.initState();
    _lastExpanded = ref.read(monthExpandedProvider);
    _key = _lastExpanded ? _monthKey(widget.selected) : _dayKey(widget.selected);
  }

  @override
  void didUpdateWidget(covariant _CalendarRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    final expanded = ref.read(monthExpandedProvider);
    if (expanded != _lastExpanded) {
      // 展开/收起由 AnimatedSize+Switcher 接管，不叠加横移动画。
      _lastExpanded = expanded;
      _key = expanded ? _monthKey(widget.selected) : _dayKey(widget.selected);
      return;
    }
    final nk = expanded ? _monthKey(widget.selected) : _dayKey(widget.selected);
    if (nk != _key) {
      _dir = nk > _key ? 1 : -1; // 向后翻=从右侧滑入
      _key = nk;
      _shift.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expanded = ref.watch(monthExpandedProvider);
    final anim = CurvedAnimation(parent: _shift, curve: _curve);
    final slide = Tween<Offset>(
            begin: Offset(_dir * .3, 0), end: Offset.zero)
        .animate(anim);
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: _curve,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.hardEdge,
      child: SlideTransition(
        position: slide,
        child: FadeTransition(
          opacity: Tween<double>(begin: .35, end: 1).animate(anim),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: _curve,
            switchOutCurve: _curve,
            child: expanded
                ? KeyedSubtree(
                    key: const ValueKey('region-month'),
                    child: _MonthPanel(selected: widget.selected))
                : KeyedSubtree(
                    key: const ValueKey('region-week'),
                    child: _WeekStrip(selected: widget.selected)),
          ),
        ),
      ),
    );
  }
}

/// 顶栏（V1.22/V1.22.1）：年月日分段轮式跳转 + 非今天显「今」+ 视图收进单按钮。
class _TimeHeader extends ConsumerWidget {
  const _TimeHeader({required this.selected, required this.isToday});
  final DateTime selected;
  final bool isToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final view = ref.watch(calViewModeProvider);

    Future<void> jump() async {
      final d = await showWheelDatePick(context, selected);
      if (d != null && context.mounted) {
        ref.read(calSelectedProvider.notifier).state = d;
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
      child: Row(
        children: [
          // V1.27 C1：左上只显「月日」（跨年才显年份），点击仍开年月日三列滚轮可改
          Semantics(button: true, label: '选择日期', child: GestureDetector(
            onTap: jump,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (selected.year != now.year) ...[
                  Text('${selected.year}',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: tokens.accent)),
                  const Text('年', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  const SizedBox(width: 6),
                ],
                Text(selected.month.toString().padLeft(2, '0'),
                    key: const ValueKey('hd-month'),
                    style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w900, color: tokens.accent)),
                const Text('月', style: TextStyle(fontSize: 10, color: Colors.grey)),
                const SizedBox(width: 6),
                Text('${selected.day}',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: isToday ? scheme.onSurface : tokens.accent)),
                const Text('日', style: TextStyle(fontSize: 10, color: Colors.grey)),
                const SizedBox(width: 8),
                Icon(Icons.expand_more, size: 16, color: scheme.onSurfaceVariant),
              ],
            ),
          )),
          const Spacer(),
          // V1.52：时间账本（L4 分类时长统计）入口
          IconButton(
            tooltip: '时间账本',
            icon: const Icon(Icons.bar_chart_rounded),
            onPressed: () => context.push('/time-stats'),
          ),
          // V1.27 C4：搜索入口下移到本行（全局顶栏标题行已删）
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search),
            // UIUX批（2026-10-12）：僵尸钮兑现——接全局搜索半屏（笔记＋日记）。
            onPressed: () => showGlobalSearch(context, ref),
          ),
          if (!isToday)
            IconButton(
              tooltip: '回到今天',
              onPressed: () {
                final n = DateTime.now();
                ref.read(calSelectedProvider.notifier).state =
                    DateTime(n.year, n.month, n.day);
              },
              icon: Text('今',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w900, color: tokens.accent)),
            ),
          // V1.29轮6：与记录页同款 ⇄ 线性钮 + 菜单当前项高亮✓
          PopupMenuButton<String>(
            key: const ValueKey('cal-view-switch'),
            tooltip: '切换 轴/块/日/周',
            icon: const Icon(Icons.sync_alt),
            onSelected: (v) {
              ref.read(calViewModeProvider.notifier).state = v;
              // C2（冻结）：切档与月历展开态解耦——不再按档重推收/展。
            },
            itemBuilder: (_) => [
              for (final e in const {
                'axis': '☰ 轴 · 时间轴',
                'block': '▦ 块 · 时间块',
                'day': '◫ 日 · 小时',
                'week': '▤ 周 · 7×24',
              }.entries)
                PopupMenuItem(
                  value: e.key,
                  child: Row(
                    children: [
                      Text(e.value,
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: e.key == view ? tokens.accent : null)),
                      if (e.key == view) ...[
                        const Spacer(),
                        Icon(Icons.check, size: 18, color: tokens.accent),
                      ],
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

/// 块视图工具条：粒度下拉（V1.12 总面积固定规则保留）。
class _BlockToolbar extends ConsumerWidget {
  const _BlockToolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gran = ref.watch(granularityProvider);
    return Row(
      children: [
        const Spacer(),
        Text('粒度',
            style: TextStyle(
                fontSize: 10.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(width: 4),
        DropdownButton<int>(
          value: gran,
          isDense: true,
          underline: const SizedBox.shrink(),
          items: const [
            DropdownMenuItem(value: 1, child: Text('1 分钟', style: TextStyle(fontSize: 12))),
            DropdownMenuItem(value: 5, child: Text('5 分钟', style: TextStyle(fontSize: 12))),
            DropdownMenuItem(value: 10, child: Text('10 分钟', style: TextStyle(fontSize: 12))),
            DropdownMenuItem(value: 15, child: Text('15 分钟', style: TextStyle(fontSize: 12))),
            DropdownMenuItem(value: 30, child: Text('30 分钟', style: TextStyle(fontSize: 12))),
            DropdownMenuItem(value: 60, child: Text('60 分钟', style: TextStyle(fontSize: 12))),
          ],
          onChanged: (v) => ref.read(granularityProvider.notifier).state = v ?? 15,
        ),
      ],
    );
  }
}

/// 展开态：迷你月历（固定 42 格不跳版 · 三色圆点 · 内部上月/下月）。
class _MonthPanel extends ConsumerWidget {
  const _MonthPanel({required this.selected});
  final DateTime selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final monthStart = DateTime(selected.year, selected.month, 1);
    final daysInMonth = daysInMonthOf(selected.year, selected.month);
    final leading = monthStart.weekday % 7;
    final now = DateTime.now();
    // V1.27 C3：月历点=事件/块任一存在
    final blockDays = ref
            .watch(monthBlockDaysProvider((selected.year, selected.month)))
            .valueOrNull ??
        const <int>{};
    // V1.52：计时中块所在日=红脉冲点（最高优先级）
    final timingDays = ref
            .watch(monthTimingDaysProvider((selected.year, selected.month)))
            .valueOrNull ??
        const <int>{};

    // V1.27 C6：展开态左右滑动切月（保日序，超出目标月天数则夹到月末）。
    // 位移累计判定而非 primaryVelocity：合成手势速度恒 0，真机慢滑同样不该漏切。
    var swipeDx = 0.0;
    void swipeMonth(int dir) {
      final m = selected.month + dir;
      final y = selected.year + (m - 1) ~/ 12;
      final mm = (m - 1) % 12 + 1;
      ref.read(calSelectedProvider.notifier).state =
          DateTime(y, mm, selected.day.clamp(1, daysInMonthOf(y, mm)));
    }

    return GestureDetector(
      // key：拖拽手势落在月历卡上（外层 GridView.first 命中的是月历网格）
      key: const ValueKey('month-panel'),
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (d) => swipeDx = 0,
      onHorizontalDragUpdate: (d) => swipeDx += d.delta.dx,
      onHorizontalDragEnd: (d) {
        if (swipeDx.abs() > 40) swipeMonth(swipeDx < 0 ? 1 : -1);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: context.cardDecoration,
        child: Column(
          children: [
            // V1.27 C6：删「‹ 2026年9月 ›」切月行（切月=滑动 / 跳月=点左上日期轮）
            Row(
            children: [
              for (final h in CalendarPage._wdHeaders)
                Expanded(
                    child: Center(
                        child: Text(h,
                            style: TextStyle(
                                fontSize: 10, color: scheme.onSurfaceVariant))),
                ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 6 * 36,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              // 固定行高 36：若用 childAspectRatio 行高随屏宽放大（~62px），
              // 6 行超出容器被裁切，月历只显示 3.5 行（真机取证 2026-09-21）。
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7, mainAxisExtent: 36),
              itemCount: 42,
              itemBuilder: (context, i) {
                final day = i - leading + 1;
                if (day < 1 || day > daysInMonth) return const SizedBox.shrink();
                final date = DateTime(selected.year, selected.month, day);
                final isSel = CalendarPage.sameDay(date, selected);
                final isToday = CalendarPage.sameDay(date, now);
                final dot = timingDays.contains(day)
                    ? const Color(0xFFF43F5E)
                    : (blockDays.contains(day)
                        ? const Color(0xFF6366F1)
                        : null);
                return Semantics(button: true, label: '选择日期', child: InkWell(
                  // 测试钩子：选中格可点切换展开态（C2），给它稳定 key。
                  key: isSel ? const ValueKey('month-sel-cell') : null,
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    ref.read(calSelectedProvider.notifier).state = date;
                    if (isSel) {
                      // C2：用户手动收/展=写盘。
                      CalendarPage.setMonthExpanded(
                          ref, !ref.read(monthExpandedProvider));
                    }
                  },
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isSel ? tokens.accent : null,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text('$day',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSel || isToday
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: isSel
                                  ? Colors.white
                                  : isToday
                                      ? tokens.accent
                                      : scheme.onSurface,
                            )),
                        if (dot != null)
                          Positioned(
                            right: 4,
                            bottom: 4,
                            child: Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSel ? Colors.white : dot,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ));
              },
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final (label, c) in const [
                ('已完成', Color(0xFF34D399)),
                ('计划中', Color(0xFF6366F1)),
                ('进行中', Color(0xFFF43F5E)),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    children: [
                      Container(
                          width: 5,
                          height: 5,
                          decoration:
                              BoxDecoration(shape: BoxShape.circle, color: c)),
                      const SizedBox(width: 3),
                      Text(label,
                          style: TextStyle(
                              fontSize: 9, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              Text('· 同日多态取最高优先级',
                  style: TextStyle(
                      fontSize: 9, color: scheme.onSurfaceVariant)),
            ],
          ),
          ],
        ),
      ),
    );
  }
}

/// 收起态：单周行（点当前日展开；左右滑动切天）。
class _WeekStrip extends ConsumerWidget {
  const _WeekStrip({required this.selected});
  final DateTime selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final days = List.generate(7, (i) => selected.add(Duration(days: i - 3)));
    // V1.27 C3：周行圆点同样并入块存在性（跨月格按当月计）。
    final blockDays = ref
            .watch(monthBlockDaysProvider((selected.year, selected.month)))
            .valueOrNull ??
        const <int>{};
    // V1.52：计时中所在日=红点
    final timingDays = ref
            .watch(monthTimingDaysProvider((selected.year, selected.month)))
            .valueOrNull ??
        const <int>{};

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: context.cardDecoration,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Semantics(button: true, label: '展开月历', child: GestureDetector(
              onTap: () => CalendarPage.setMonthExpanded(ref, true),
              child: Text('展开 ▾',
                  style: TextStyle(
                      fontSize: 9.5, fontWeight: FontWeight.w800, color: tokens.accent)),
            )),
          ),
          // V1.27 C2：LayoutBuilder 7 格等宽自适应，小屏不裁切（轴视图周行显示全周）。
          // V1.27 C6：滑动切天=位移累计（与展开态切月同判定，慢滑不漏切）。
          Builder(builder: (context) {
            var dx = 0.0;
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (_) => dx = 0,
              onHorizontalDragUpdate: (d) => dx += d.delta.dx,
              onHorizontalDragEnd: (_) {
                if (dx.abs() <= 40) return;
                ref.read(calSelectedProvider.notifier).state = DateTime(
                    selected.year,
                    selected.month,
                    selected.day + (dx < 0 ? 1 : -1));
              },
              child: LayoutBuilder(
                builder: (context, c) {
                  final cellW = (c.maxWidth - 16 - 6) / 7;
                  return Row(
                    children: [
                      for (final d in days)
                        SizedBox(
                          width: cellW,
                          child: Semantics(button: true, label: '选择日期', child: GestureDetector(
                    onTap: () {
                      if (CalendarPage.sameDay(d, selected)) {
                        CalendarPage.setMonthExpanded(ref, true);
                      } else {
                        ref.read(calSelectedProvider.notifier).state = d;
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      decoration: BoxDecoration(
                        color: CalendarPage.sameDay(d, selected)
                            ? tokens.accent
                            : null,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Text(CalendarPage._wds[d.weekday % 7],
                              style: TextStyle(
                                  fontSize: 8.5,
                                  color: CalendarPage.sameDay(d, selected)
                                      ? Colors.white70
                                      : scheme.onSurfaceVariant)),
                          Text('${d.day}',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: CalendarPage.sameDay(d, selected)
                                      ? Colors.white
                                      : scheme.onSurface)),
                          Container(
                            width: 4,
                            height: 4,
                            margin: const EdgeInsets.only(top: 2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: CalendarPage.sameDay(d, selected)
                                  ? Colors.white
                                  : (timingDays.contains(d.day)
                                      ? const Color(0xFFF43F5E)
                                      : (d.month == selected.month &&
                                              blockDays.contains(d.day)
                                          ? const Color(0xFF6366F1)
                                          : Colors.transparent)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )),
                    ),
                    ],
                  );
                },
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// 轴视图：竖向时间轴（时间块卡＋定时待办紫行；B10 起 events 已并入块，单源）。
class _AxisView extends ConsumerWidget {
  const _AxisView({required this.selected});
  final DateTime selected;

  static String _hm2(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final todos = ref.watch(todosProvider).valueOrNull ?? const <Todo>[];
    // V1.27 C3：定时待办随所选日同步（归属日=截止日，无截止日=创建日）
    final selDay = DateTime(selected.year, selected.month, selected.day);
    final sched = todos.where((t) {
      if (t.timeMode == null || t.dropped) return false;
      final base = t.dueAt ?? t.createdAt ?? DateTime.now();
      return selDay == DateTime(base.year, base.month, base.day);
    }).toList();
    // V1.27 C3：轴视图并入手动标记块投影；B10：事件回填块（source=event）同列
    // ——旧 events 已整体并入块表，不再有「由事件卡表达」的另一份。
    // V1.52：计时中块（source=timing）同列，结束时间随当前时刻推进
    // F4-3：取数失败显错误卡＋重试（空态另有专属文案，两态不混）。
    final blocksAsync = ref.watch(dayBlocksProvider(selected));
    if (blocksAsync.hasError && blocksAsync.valueOrNull == null) {
      return AsyncErrorRetry(
          onRetry: () => ref.invalidate(dayBlocksProvider(selected)));
    }
    // F6-2：视图构建一次取时下传——同帧口径一致，循环内不再逐次 effEnd()。
    final frameNow = DateTime.now();
    final markBlocks = (blocksAsync.valueOrNull ?? const <TimeBlock>[])
        .toList()
      ..sort((a, b) => a.startMin.compareTo(b.startMin));
    // F5-3：有计时中块时接秒级心跳，「已 X 分钟」前台每秒刷新
    //（ticker 懒启动：无 watch 者/离屏自动停＝功耗口径）。
    if (markBlocks.any((b) => b.isTiming)) {
      ref.watch(calendarTickerProvider);
    }
    // 原型时间轴行：左时间列 + 轴上圆点 + 内容卡（竖线由外层 Stack 绘制）
    Widget rail(String time, Color dot, Widget child, {Color? timeColor}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                  width: 42,
                  child: Text(time,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: timeColor ?? scheme.onSurfaceVariant))),
              SizedBox(
                  width: 18,
                  child: Container(
                      width: 9,
                      height: 9,
                      margin: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                          shape: BoxShape.circle, color: dot))),
              Expanded(child: child),
            ],
          ),
        );

    Widget railContent(List<Widget> items) => Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
                left: 46,
                top: 4,
                bottom: 12,
                child: Container(
                    width: 1,
                    color: scheme.outlineVariant)),
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items),
          ],
        );

    final rose = const Color(0xFFF43F5E);
    final violet = const Color(0xFF8B5CF6);
    final catColors = ref.watch(catColorsByNameProvider);

    // ===== V1.52：块投影（点块=与添加同款编辑弹层）+ 每段空隙可点补录 =====
    Widget blockCard(TimeBlock b) {
      final col = blockColor(b, catColors, tokens.accent);
      final live = b.isTiming;
      final dur = b.durationMin();
      return Semantics(button: true, label: '编辑时间块', child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showTimePickSheet(context, ref, block: b),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: col.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: col.withValues(alpha: live ? .85 : .4), width: live ? 1.4 : 1),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.note == null || b.note!.isEmpty ? b.catName : b.note!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      live
                          ? '● 计时中 · 已 $dur 分钟 · 点卡片可结束/修改'
                          : '${b.catName} · $dur 分钟 · 点卡片修改起止/类型',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: live ? rose : scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (live)
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: rose, minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 12)),
                  onPressed: () async {
                    final dao = ref.read(timeBlockDaoProvider);
                    final n = DateTime.now();
                    await dao.endTiming(b.id, n.hour * 60 + n.minute);
                    ref.invalidate(dayBlocksProvider(selected));
                    ref.invalidate(timingBlockProvider);
                    ref.invalidate(monthTimingDaysProvider((selected.year, selected.month)));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(const SnackBar(content: Text('■ 结束计时 · 已落账（L4）')));
                    }
                  },
                  child: const Text('■ 结束计时', style: TextStyle(fontSize: 11.5)),
                ),
            ],
          ),
        ),
      ));
    }

    Widget gapRow(int a, int e) => Semantics(button: true, label: '添加时间段', child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => showTimePickSheet(context, ref, day: selected, startMin: a),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Center(
              child: Text('空闲 ${fmtMin(a)} – ${fmtMin(e)} · 点此补录',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ),
          ),
        ));

    final blockRails = <Widget>[];
    var cursor = 0;
    for (final b in markBlocks) {
      if (b.startMin - cursor >= kGapMinMin) blockRails.add(rail(fmtMin(cursor), scheme.surface, gapRow(cursor, b.startMin)));
      blockRails.add(rail(fmtMin(b.startMin),
          b.isTiming ? rose : blockColor(b, catColors, tokens.accent),
          blockCard(b),
          timeColor: b.isTiming ? rose : null));
      if (b.effEnd(frameNow) > cursor) {
        cursor = b.effEnd(frameNow);
      }
    }
    if (1440 - cursor >= kGapMinMin) blockRails.add(rail(fmtMin(cursor), scheme.surface, gapRow(cursor, 1440)));

    final items = <Widget>[...blockRails];

    for (final t in sched) {
      items.add(rail(
          t.timeMode == 'all'
              ? '全天'
              : (t.timeMode == 'point'
                  ? _hm2(t.startMin ?? 0)
                  : '${_hm2(t.startMin ?? 0)}-${_hm2(t.endMin ?? 0)}'),
          violet,
          Semantics(button: true, label: '打开定时待办', child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => schedTodoTap(context, ref, t),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: violet.withValues(alpha: .07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: violet.withValues(alpha: .4)),
              ),
              child: Row(
                children: [
                  Text(t.done ? '☑' : '☐',
                      style: TextStyle(fontSize: 16, color: violet)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${t.isPomo ? '🍅 ' : ''}${t.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                decoration:
                                    t.done ? TextDecoration.lineThrough : null,
                                color: t.done ? Colors.grey : scheme.onSurface)),
                        Text(
                          '定时待办 · ${t.quadrant.label}${t.pomoMode == 'down' ? ' · 番茄${t.pomoMin ?? 25}分倒计时' : (t.isPomo ? ' · 番茄正计时' : '')}',
                          style: TextStyle(
                              fontSize: 10, color: violet),
                        ),
                      ],
                    ),
                  ),
                  if (t.isPomo && !t.done)
                    Text(
                        ref.watch(activePomoProvider)?.todoId == t.id ? '■ 番茄中' : '▶ 番茄',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: rose)),
                ],
              ),
            ),
          )),
          timeColor: violet));
    }
    // V1.52：空隙补录条已由 blockRails 按实际空档生成（无块时整段 00:00-24:00），
    // 不再追加写死的「下一整点」单行。

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
            '${selected.month}月${selected.day}日 · 周${CalendarPage._wds[selected.weekday % 7]}',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, color: tokens.accent)),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Semantics(button: true, label: '添加时间段', child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => showTimePickSheet(context, ref, day: selected, startMin: 9 * 60),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Text('当天暂无安排 · 点此处补录这段时间做了什么',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ),
          ))
        else
          railContent(items),
      ],
    );
  }
}

/// 日视图：0-23 小时行（点空行补录 / 点块卡管理）。
/// F4-1（批2 · 原型 index-time.html renderDayHours）：①定时待办紫行按起始小时
/// 落位（与轴视图同源口径，仅今天）；②当前时间红线游标（当前小时红顶边＋浅红底
/// ＋「现在」标）；③秒级 HH:MM:SS 时钟（仅今天显示并每秒刷新，非今天不启定时器）。
class _DayHoursView extends ConsumerStatefulWidget {
  const _DayHoursView({required this.selected});
  final DateTime selected;

  @override
  ConsumerState<_DayHoursView> createState() => _DayHoursViewState();
}

class _DayHoursViewState extends ConsumerState<_DayHoursView> {
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  static bool _isToday(DateTime selected, DateTime now) =>
      CalendarPage.sameDay(selected, now);

  static String _hm2(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  static String _hmss(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _ensureClock();
  }

  @override
  void didUpdateWidget(covariant _DayHoursView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 同型 widget 复用 State：切日不重建 ⇒ 时钟随「是否今天」启停。
    _ensureClock();
  }

  void _ensureClock() {
    final want = _isToday(widget.selected, DateTime.now());
    if (want && _clockTimer == null) {
      _now = DateTime.now();
      _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    } else if (!want && _clockTimer != null) {
      _clockTimer?.cancel();
      _clockTimer = null;
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    // F4-3：取数失败显错误卡＋重试（空态另有专属文案，两态不混）。
    final blocksAsync = ref.watch(dayBlocksProvider(selected));
    if (blocksAsync.hasError && blocksAsync.valueOrNull == null) {
      return AsyncErrorRetry(
          onRetry: () => ref.invalidate(dayBlocksProvider(selected)));
    }
    final blocks =
        blocksAsync.valueOrNull ?? const <TimeBlock>[];
    final catColors = ref.watch(catColorsByNameProvider);
    final isToday = _isToday(selected, _now);
    final nowHour = _now.hour;
    // F4-1① 落位口径同轴视图：归属日=截止日，无截止日=创建日；非 all 才入行。
    final selDay = DateTime(selected.year, selected.month, selected.day);
    final schedTodos = (ref.watch(todosProvider).valueOrNull ?? const <Todo>[])
        .where((t) {
          if (t.timeMode == null || t.timeMode == 'all' || t.dropped) return false;
          final base = t.dueAt ?? t.createdAt ?? DateTime.now();
          return selDay == DateTime(base.year, base.month, base.day);
        })
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                    '${selected.month}月${selected.day}日${isToday ? ' · 今天' : ''}'
                    ' · 点空白小时补录 · 点块卡修改起止/类型',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10, color: scheme.onSurfaceVariant)),
              ),
              // F4-1③ 秒级时钟（仅今天）。
              if (isToday)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: _kTimingRose)),
                    const SizedBox(width: 4),
                    Text(_hmss(_now),
                        key: const ValueKey('day-clock'),
                        style: const TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w800,
                            color: _kTimingRose)),
                  ],
                ),
            ],
          ),
        ),
        for (var h = 0; h < 24; h++)
          _buildHourRow(
              context, ref, h, isToday: isToday, nowHour: nowHour,
              blocks: blocks, catColors: catColors,
              tokens: tokens, scheme: scheme, schedTodos: schedTodos),
      ],
    );
  }

  Widget _buildHourRow(
    BuildContext context,
    WidgetRef ref,
    int h, {
    required bool isToday,
    required int nowHour,
    required List<TimeBlock> blocks,
    required Map<String, Color> catColors,
    required ThemeTokens tokens,
    required ColorScheme scheme,
    required List<Todo> schedTodos,
  }) {
    final isNow = isToday && h == nowHour;
    return Semantics(button: true, label: '添加时间段', child: InkWell(
      onTap: () =>
          showTimePickSheet(context, ref, day: widget.selected, startMin: h * 60),
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        // F4-1② 当前小时=红顶边＋浅红底（红线游标落位当前小时）。
        decoration: BoxDecoration(
            color: isNow ? _kTimingRose.withValues(alpha: .06) : null,
            border: Border(
                top: isNow
                    ? const BorderSide(color: _kTimingRose, width: 2)
                    : BorderSide.none,
                bottom: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: .5)))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 40,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('$h:00',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          color: isNow
                              ? _kTimingRose
                              : scheme.onSurfaceVariant)),
                )),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // F4-1① 定时待办紫行（仅今天，落位起始小时）。
                  if (isToday)
                    for (final t in schedTodos
                        .where((t) => (t.startMin ?? 0) ~/ 60 == h))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Semantics(button: true, label: '打开定时待办', child: InkWell(
                          onTap: () => schedTodoTap(context, ref, t),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _kTodoViolet.withValues(alpha: .9),
                              borderRadius: BorderRadius.circular(10),
                              border: Border(
                                  left: BorderSide(
                                      color:
                                          _kTodoViolet.withValues(alpha: .6),
                                      width: 4)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                      '${t.timeMode == 'span' ? '${_hm2(t.startMin ?? 0)}-${_hm2(t.endMin ?? 0)}' : _hm2(t.startMin ?? 0)}'
                                      ' 定时待办 · ${t.title}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white)),
                                ),
                                Text(t.quadrant.hint,
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.white
                                            .withValues(alpha: .85))),
                              ],
                            ),
                          ),
                        )),
                      ),
                  // B10：旧 events 并入块表后，source=event 块照常在此列展示。
                  for (final b in blocks
                      .where((b) => b.startMin ~/ 60 == h))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Semantics(button: true, label: '编辑时间块', child: InkWell(
                        onTap: () => showTimePickSheet(context, ref, block: b),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: b.isTiming
                                ? _kTimingRose
                                : blockColor(b, catColors, tokens.accent)
                                    .withValues(alpha: .85),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${b.note == null || b.note!.isEmpty ? b.catName : b.note}'
                                  '${b.isTiming ? ' ●' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white),
                                ),
                              ),
                              Text('${b.durationMin()}分',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white70)),
                            ],
                          ),
                        ),
                      )),
                    ),
                ],
              ),
            ),
            // F4-1② 「现在」标（仅当前小时，右列占位对齐）。
            SizedBox(
                width: 44,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('现在',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 9,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w800,
                          color: isNow
                              ? _kTimingRose
                              : Colors.transparent)),
                )),
          ],
        ),
      ),
    ));
  }
}

/// 周视图：7×24 网格。V1.28⑧：格子有块=点开详情（→编辑），空格子才开补录。
/// V1.46⑤：同小时格多个时间块并排分段显示，各段仍可点进自己的详情。
/// 周视图头件（说明行＋星期表头）——F6-1 拆分：24 小时行铺进主屏
/// ListView.builder，本件只承载不随滚动的头部两行。
class _WeekBoardHeader extends ConsumerWidget {
  const _WeekBoardHeader({required this.selected});
  final DateTime selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final days = naturalWeek(selected); // C6（冻结）：自然周（周日起算）
    String md(DateTime d) => '${d.month}/${d.day}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('🗓 ${md(days.first)} - ${md(days.last)} · 空格子 → 添加时间段 · 已添加 → 点进去修改/拆分/合并',
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        Row(
          children: [
            const SizedBox(width: 26),
            for (final d in days)
              Expanded(
                child: Center(
                  child: Text(CalendarPage.sameDay(d, DateTime.now()) ? '今' : CalendarPage._wds[d.weekday % 7],
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: CalendarPage.sameDay(d, DateTime.now())
                              ? tokens.accent
                              : scheme.onSurfaceVariant)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// 周视图单小时行（7 格）——F6-1：随主屏 builder 视口内构建；
/// F4-3 行级守卫：任一天取数失败（无旧值）⇒ 行显错误卡＋重试。
class _WeekRow extends ConsumerWidget {
  const _WeekRow({required this.selected, required this.hour});
  final DateTime selected;
  final int hour;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final days = naturalWeek(selected);
    final h = hour * 60;
    final blocksByDay = <DateTime, List<TimeBlock>>{};
    for (final d in days) {
      final a = ref.watch(dayBlocksProvider(d));
      if (a.hasError && a.valueOrNull == null) {
        return AsyncErrorRetry(
            onRetry: () => ref.invalidate(dayBlocksProvider), compact: true);
      }
      blocksByDay[d] = a.valueOrNull ?? const <TimeBlock>[];
    }
    final catColors = ref.watch(catColorsByNameProvider);
    // F6-2：构建一次取时下传，行内不再逐次 effEnd()。
    final frameNow = DateTime.now();

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          SizedBox(
              width: 26,
              child: Text('$hour',
                  style: TextStyle(
                      fontSize: 8,
                      fontFamily: 'monospace',
                      color: scheme.onSurfaceVariant))),
          for (var di = 0; di < days.length; di++)
            Expanded(
              child: Builder(builder: (context) {
                final d = days[di];
                final blocks = blocksByDay[d] ?? const <TimeBlock>[];
                final m = h;
                // V1.46⑤：同小时格命中的多个时间块并排分段，各段可点进自己详情。
                // B10：source=event 块（旧日程并入）同样入格。
                final items = <Object>[
                  ...blocks.where((x) =>
                      x.startMin < m + 60 &&
                      x.effEnd(frameNow) > m),
                ];
                final segs = weekCellSegments(items);
                Color segColor(Object it) =>
                    blockColor(it as TimeBlock, catColors, tokens.accent);
                int segDurMin(Object it) => (it as TimeBlock).durationMin();
                String segLabel(Object it) {
                  final b = it as TimeBlock;
                  return b.note == null || b.note!.isEmpty ? b.catName : b.note!;
                }

                void openItem(Object? it) {
                  // V1.52：点已有块=与添加同款编辑弹层；空格子才开添加。
                  if (it is TimeBlock) {
                    showTimePickSheet(context, ref, block: it);
                  } else {
                    showTimePickSheet(context, ref, day: d, startMin: m);
                  }
                }
                return Semantics(button: true, label: '添加时间段', child: InkWell(
                  key: ValueKey('wk-cell-$di-$hour'),
                  onTap: () =>
                      openItem(segs.isEmpty ? null : segs.first.item),
                  child: Container(
                    height: 17,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                        color: scheme.onSurface.withValues(alpha: .06),
                        borderRadius: BorderRadius.circular(4)),
                    child: segs.isEmpty
                        ? null
                        : Row(
                            children: [
                              for (var si = 0; si < segs.length; si++)
                                Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal:
                                            segs.length > 1 ? .5 : 0),
                                    child: Semantics(button: true, label: '查看时间段', child: InkWell(
                                      key: ValueKey('wk-seg-$di-$hour-$si'),
                                      onTap: () =>
                                          openItem(segs[si].item),
                                      child: Container(
                                        decoration: BoxDecoration(
                                            color: segColor(
                                                segs[si].item),
                                            borderRadius:
                                                BorderRadius.circular(
                                                    4)),
                                        child: segs[si]
                                                .badgeText
                                                .isNotEmpty
                                            ? Center(
                                                child: Text(
                                                    segs[si].badgeText,
                                                    style: const TextStyle(
                                                        fontSize: 7,
                                                        fontWeight:
                                                            FontWeight
                                                                .w800,
                                                        color:
                                                            Colors
                                                                .white,
                                                        height: 1)))
                                            : (segs.length > 1
                                                ? null
                                                : Padding(
                                                    padding: const EdgeInsets.symmetric(
                                                        horizontal: 2),
                                                    child: ClipRect(
                                                      child: Text(
                                                          '${segLabel(segs[si].item)} · ${segDurMin(segs[si].item)}分',
                                                          maxLines: 1,
                                                          overflow:
                                                              TextOverflow
                                                                  .clip,
                                                          textAlign:
                                                              TextAlign
                                                                  .center,
                                                          style: const TextStyle(
                                                              fontSize:
                                                                  6.5,
                                                              color: Colors
                                                                  .white,
                                                              height:
                                                                  17 /
                                                                      6.5)),
                                                    ),
                                                  )),
                                      ),
                                    )),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ));
              }),
            ),
        ],
      ),
    );
  }
}
