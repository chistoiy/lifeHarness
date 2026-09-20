import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/linkage/stats_providers.dart';
import '../domain/cal_event.dart';
import '../domain/event_repository.dart';
import '../domain/time_block.dart';
import 'calendar_providers.dart';
import 'widgets/event_detail_sheet.dart';
import 'widgets/grid_day_view.dart';
import 'widgets/time_pick_sheet.dart';
import 'widgets/wheel_date.dart';

/// 模块1 时间（V1.19~V1.24 · 原「日程」改名）。
/// 定位=记录用户在各个时间段做了什么事情：四视图（轴/块/日/周）同一数据不同投影，
/// 操作逻辑统一 CRUD；顶栏年月日轮式跳转 + 非今天显「今」；添加统一 sheetTimePick。
/// 当月天数（避开 DateTime(y,m+1,0)：day-0 归一化在 FakeAsync 时区解析下会挂死）。
int daysInMonthOf(int y, int m) {
  const dm = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (m != 2) return dm[m - 1];
  return (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) ? 29 : 28;
}
class CalendarPage extends ConsumerWidget {
  const CalendarPage({super.key});

  static const _wdHeaders = ['日', '一', '二', '三', '四', '五', '六'];
  static const _wds = ['日', '一', '二', '三', '四', '五', '六'];

  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static List<CalEvent> onDay(List<CalEvent> all, DateTime d) =>
      all.where((e) => sameDay(e.start, d)).toList();

  /// 某天圆点状态色（进行中红 > 计划主题色 > 完成绿）。
  static Color? dotColorFor(List<CalEvent> dayEvents, Color accent) {
    if (dayEvents.any((e) => e.status == EventStatus.active)) {
      return const Color(0xFFF43F5E);
    }
    if (dayEvents.any((e) => e.status == EventStatus.planning)) return accent;
    if (dayEvents.any((e) => e.status == EventStatus.done)) {
      return const Color(0xFF34D399);
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final selected = ref.watch(calSelectedProvider);
    final view = ref.watch(calViewModeProvider);
    final events = ref.watch(eventsProvider).valueOrNull ?? const [];
    final conflicts =
        EventRepository.conflictsOf(onDay(events, selected));
    final now = DateTime.now();
    final isToday = sameDay(selected, now);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
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
                    ref.read(monthExpandedProvider.notifier).state = false;
                  }
                  return false;
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
                  children: [
                    if (ref.watch(monthExpandedProvider))
                      _MonthPanel(selected: selected, events: events)
                    else
                      _WeekStrip(selected: selected, events: events),
                    if (conflicts.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF43F5E).withValues(alpha: .07),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: const Color(0xFFF43F5E).withValues(alpha: .3)),
                        ),
                        child: Text(
                          '⏱ 时间冲突：「${conflicts.first.a.title}」与「${conflicts.first.b.title}」'
                          '重叠 ${conflicts.first.overlapMin} 分钟',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 10),
                    if (view == 'block') const _BlockToolbar(),
                    if (view == 'block') const SizedBox(height: 8),
                    switch (view) {
                      'axis' => _AxisView(selected: selected, events: events),
                      'block' => GridDayView(day: selected),
                      'day' => _DayHoursView(selected: selected, events: events),
                      _ => _WeekBoard(selected: selected, events: events),
                    },
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: tokens.accent,
        heroTag: 'time-fab',
        onPressed: () => showTimePickSheet(context, ref, day: selected),
        child: const Icon(Icons.add, color: Colors.white),
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
    final view = ref.watch(calViewModeProvider);
    const labels = {'axis': '轴', 'block': '块', 'day': '日', 'week': '周'};

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
          GestureDetector(
            onTap: jump,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('${selected.year}',
                    style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w900, color: tokens.accent)),
                const Text('年', style: TextStyle(fontSize: 10, color: Colors.grey)),
                const SizedBox(width: 6),
                Text(selected.month.toString().padLeft(2, '0'),
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
          ),
          const Spacer(),
          if (!isToday)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                tooltip: '回到今天',
                onPressed: () {
                  final n = DateTime.now();
                  ref.read(calSelectedProvider.notifier).state =
                      DateTime(n.year, n.month, n.day);
                },
                icon: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: tokens.accent.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(12)),
                  child: Text('今',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w900, color: tokens.accent)),
                ),
              ),
            ),
          PopupMenuButton<String>(
            tooltip: '切换视图',
            icon: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12)),
              child: Text(labels[view] ?? '块',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w900, color: tokens.accent)),
            ),
            onSelected: (v) => ref.read(calViewModeProvider.notifier).state = v,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'axis', child: Text('☰ 轴 · 时间轴')),
              PopupMenuItem(value: 'block', child: Text('▦ 块 · 时间块')),
              PopupMenuItem(value: 'day', child: Text('◫ 日 · 小时')),
              PopupMenuItem(value: 'week', child: Text('▤ 周 · 7×24')),
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
  const _MonthPanel({required this.selected, required this.events});
  final DateTime selected;
  final List<CalEvent> events;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final monthStart = DateTime(selected.year, selected.month, 1);
    final daysInMonth = daysInMonthOf(selected.year, selected.month);
    final leading = monthStart.weekday % 7;
    final now = DateTime.now();

    void shiftMonth(int n) {
      final m = selected.month + n;
      ref.read(calSelectedProvider.notifier).state =
          DateTime(selected.year + (m - 1) ~/ 12, (m - 1) % 12 + 1, 1);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: context.cardDecoration,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_left, size: 18),
                  onPressed: () => shiftMonth(-1)),
              Text('${selected.year}年${selected.month}月',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_right, size: 18),
                  onPressed: () => shiftMonth(1)),
            ],
          ),
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
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7, childAspectRatio: 0.72),
              itemCount: 42,
              itemBuilder: (context, i) {
                final day = i - leading + 1;
                if (day < 1 || day > daysInMonth) return const SizedBox.shrink();
                final date = DateTime(selected.year, selected.month, day);
                final isSel = CalendarPage.sameDay(date, selected);
                final isToday = CalendarPage.sameDay(date, now);
                final dot = CalendarPage.dotColorFor(
                    CalendarPage.onDay(events, date), tokens.accent);
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    ref.read(calSelectedProvider.notifier).state = date;
                    if (isSel) {
                      ref.read(monthExpandedProvider.notifier).state =
                          !ref.read(monthExpandedProvider);
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
                );
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
            ],
          ),
        ],
      ),
    );
  }
}

/// 收起态：单周行（点当前日展开；左右滑动切天）。
class _WeekStrip extends ConsumerWidget {
  const _WeekStrip({required this.selected, required this.events});
  final DateTime selected;
  final List<CalEvent> events;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final days = List.generate(7, (i) => selected.add(Duration(days: i - 3)));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: context.cardDecoration,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => ref.read(monthExpandedProvider.notifier).state = true,
              child: Text('展开 ▾',
                  style: TextStyle(
                      fontSize: 9.5, fontWeight: FontWeight.w800, color: tokens.accent)),
            ),
          ),
          Row(
            children: [
              for (final d in days)
                Expanded(
                  child: GestureDetector(
                    onHorizontalDragEnd: (drag) {
                      final v = drag.primaryVelocity ?? 0;
                      if (v.abs() < 100) return;
                      ref.read(calSelectedProvider.notifier).state = DateTime(
                          selected.year,
                          selected.month,
                          selected.day + (v < 0 ? 1 : -1));
                    },
                    onTap: () {
                      if (CalendarPage.sameDay(d, selected)) {
                        ref.read(monthExpandedProvider.notifier).state = true;
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
                                  : (CalendarPage.dotColorFor(
                                          CalendarPage.onDay(events, d),
                                          tokens.accent) ??
                                      Colors.transparent),
                            ),
                          ),
                        ],
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

/// 轴视图：竖向时间轴（进行中脉冲卡 → 计划卡 → 已完成划线卡，全部可点=统一详情）。
class _AxisView extends ConsumerWidget {
  const _AxisView({required this.selected, required this.events});
  final DateTime selected;
  final List<CalEvent> events;

  static String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String _hm2(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final dayEvents = List<CalEvent>.from(CalendarPage.onDay(events, selected))
      ..sort((a, b) => a.start.compareTo(b.start));
    final todos = ref.watch(todosProvider).valueOrNull ?? const <Todo>[];
    final sched = todos
        .where((t) => t.timeMode != null && !t.dropped)
        .toList();
    final active =
        dayEvents.where((e) => e.status == EventStatus.active).toList();
    final planning =
        dayEvents.where((e) => e.status == EventStatus.planning).toList();
    final done = dayEvents.where((e) => e.status == EventStatus.done).toList();

    Widget card(CalEvent e, {required bool isLive, required bool isDone}) {
      final c = isDone
          ? const Color(0xFF34D399)
          : (isLive ? const Color(0xFFF43F5E) : e.colorOf(tokens.accent));
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => showEventDetailSheet(context, ref, e),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isLive
                  ? const Color(0xFFF43F5E).withValues(alpha: .06)
                  : scheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: isLive
                  ? Border.all(color: c.withValues(alpha: .6))
                  : Border(left: BorderSide(color: c, width: 4)),
              boxShadow: isLive ? null : tokens.cardShadow,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            decoration:
                                isDone ? TextDecoration.lineThrough : null,
                            color: isDone ? Colors.grey : scheme.onSurface,
                          )),
                      const SizedBox(height: 2),
                      Text(
                        isLive
                            ? '● 进行中 · ${_hm(e.start)} 开始 · 点卡片管理'
                            : (isDone
                                ? '✓ 已完成 · 实际 ${e.durationMin ?? '—'} 分钟 · 已回填 L1 · 入账本 L4 · 点卡片仍可编辑/删除'
                                : '${e.allDay ? '全天' : '${_hm(e.start)} – ${e.end == null ? '' : _hm(e.end!)}'}${e.crossDay ? ' · 跨天' : ''} · 点卡片查看/编辑/删除'),
                        style: TextStyle(
                            fontSize: 10.5,
                            color: isLive
                                ? const Color(0xFFF43F5E)
                                : (isDone
                                    ? const Color(0xFF10B981)
                                    : scheme.onSurfaceVariant)),
                      ),
                    ],
                  ),
                ),
                if (isLive)
                  FilledButton(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final repo = ref.read(eventRepositoryProvider);
                      final ended = await repo.endActive();
                      ref.invalidate(eventsProvider);
                      ref.invalidate(activeEventProvider);
                      if (ended != null) {
                        messenger.showSnackBar(SnackBar(
                            content: Text(
                                '✔ 耗时 ${ended.durationMin} 分钟 · 回填 L1 · 写入时间账本 L4')));
                      }
                    },
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF43F5E)),
                    child: const Text('■ 结束', style: TextStyle(fontSize: 12)),
                  ),
                const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
            '${selected.month}月${selected.day}日 · 周${CalendarPage._wds[selected.weekday % 7]}',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, color: tokens.accent)),
        const SizedBox(height: 8),
        for (final e in active) card(e, isLive: true, isDone: false),
        for (final e in planning) card(e, isLive: false, isDone: false),
        for (final e in done) card(e, isLive: false, isDone: true),
        for (final t in sched)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
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
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: .4)),
                ),
                child: Row(
                  children: [
                    Text(t.done ? '☑' : '☐',
                        style: const TextStyle(fontSize: 16, color: Color(0xFF8B5CF6))),
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
                            '${t.timeMode == 'all' ? '全天' : (t.timeMode == 'point' ? _hm2(t.startMin ?? 0) : '${_hm2(t.startMin ?? 0)} - ${_hm2(t.endMin ?? 0)}')} · 定时待办 · ${t.quadrant.label}',
                            style: const TextStyle(
                                fontSize: 10, color: Color(0xFF8B5CF6)),
                          ),
                        ],
                      ),
                    ),
                    if (t.isPomo && !t.done)
                      Text(
                          ref.watch(activePomoProvider)?.todoId == t.id ? '■ 番茄中' : '▶ 番茄',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFF43F5E))),
                  ],
                ),
              ),
            ),
          ),
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => showTimePickSheet(context, ref, day: selected, startMin: 17 * 60),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Center(
              child: Text(
                dayEvents.isEmpty
                    ? '当天暂无安排 · 点此处补录这段时间做了什么'
                    : '＋ 添加一段（点空白时段补录）',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 日视图：0-23 小时行（V1.19.2 定义迁移至此——点空行补录 / 点事件管理）。
class _DayHoursView extends ConsumerWidget {
  const _DayHoursView({required this.selected, required this.events});
  final DateTime selected;
  final List<CalEvent> events;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final blocks =
        ref.watch(dayBlocksProvider(selected)).valueOrNull ?? const <TimeBlock>[];
    final catColors = ref.watch(catColorsByNameProvider);
    final dayEvents = CalendarPage.onDay(events, selected);
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var h = 0; h < 24; h++)
          InkWell(
            onTap: () => showTimePickSheet(context, ref, day: selected, startMin: h * 60),
            child: Container(
              constraints: const BoxConstraints(minHeight: 40),
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: .5)))),
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
                                color: h == now.hour && CalendarPage.sameDay(selected, now)
                                    ? const Color(0xFFF43F5E)
                                    : scheme.onSurfaceVariant)),
                      )),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final e in dayEvents.where((e) => e.start.hour == h))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: InkWell(
                              onTap: () => showEventDetailSheet(context, ref, e),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 7),
                                decoration: BoxDecoration(
                                  color: e.status == EventStatus.done
                                      ? const Color(0xFF34D399).withValues(alpha: .8)
                                      : (e.status == EventStatus.active
                                          ? const Color(0xFFF43F5E)
                                          : e.colorOf(tokens.accent)),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${e.status == EventStatus.active ? '● ' : (e.status == EventStatus.done ? '✓ ' : '⚡ ')}${e.title}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        for (final b in blocks.where((b) => b.startMin ~/ 60 == h))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: InkWell(
                              onTap: () => showBlockDetailSheet(context, ref, selected, b),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 7),
                                decoration: BoxDecoration(
                                  color: blockColor(b, catColors, tokens.accent)
                                      .withValues(alpha: .85),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${b.catName} ${(b.startMin ~/ 60).toString().padLeft(2, '0')}:${(b.startMin % 60).toString().padLeft(2, '0')}-${(b.endMin ~/ 60).clamp(0, 23).toString().padLeft(2, '0')}:${(b.endMin % 60).toString().padLeft(2, '0')}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 周视图：7×24 网格（点格子 → 统一添加弹层预选该日该时）。
class _WeekBoard extends ConsumerWidget {
  const _WeekBoard({required this.selected, required this.events});
  final DateTime selected;
  final List<CalEvent> events;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final days = List.generate(7, (i) => DateTime(selected.year, selected.month, selected.day - 3 + i));
    final blocksByDay = <DateTime, List<TimeBlock>>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('点任意格子 → 添加那段时间（与块/轴/日视图同步）',
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
        for (var h = 0; h < 24; h++)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                SizedBox(
                    width: 26,
                    child: Text('$h',
                        style: TextStyle(
                            fontSize: 8,
                            fontFamily: 'monospace',
                            color: scheme.onSurfaceVariant))),
                for (final d in days)
                  Expanded(
                    child: Builder(builder: (context) {
                      final blocks = blocksByDay.putIfAbsent(
                          d, () => ref.watch(dayBlocksProvider(d)).valueOrNull ?? const []);
                      final m = h * 60;
                      final b = blocks.where((x) => x.covers(m)).firstOrNull;
                      final e = CalendarPage.onDay(events, d)
                          .where((x) => !x.allDay && x.start.hour == h)
                          .firstOrNull;
                      final color = e != null
                          ? (e.status == EventStatus.done
                              ? const Color(0xFF34D399)
                              : (e.status == EventStatus.active
                                  ? const Color(0xFFF43F5E)
                                  : tokens.accent))
                          : (b != null
                              ? blockColor(b, ref.watch(catColorsByNameProvider), tokens.accent)
                              : scheme.onSurface.withValues(alpha: .06));
                      return InkWell(
                        onTap: () => showTimePickSheet(
                            context, ref, day: d, startMin: h * 60),
                        child: Container(
                          height: 17,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                              color: color, borderRadius: BorderRadius.circular(4)),
                        ),
                      );
                    }),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
