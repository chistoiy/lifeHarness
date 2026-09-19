import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/cal_event.dart';
import '../domain/event_repository.dart';
import 'calendar_providers.dart';
import 'widgets/event_sheet.dart';

/// 模块1 日程（M0 业务② · 对齐原型 p-calendar）。
/// 月历 42 格固定不跳版 / 三色圆点 / 智能折叠周行+滑动切天 / 日·周·月三视图 /
/// ▶开始·■结束两态流 / 冲突提示。格子时间块模式为 M0 业务②b（下一步）。
class CalendarPage extends ConsumerWidget {
  const CalendarPage({super.key});

  static const _wdHeaders = ['日', '一', '二', '三', '四', '五', '六'];
  static const _wds = ['日', '一', '二', '三', '四', '五', '六'];

  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final selected = ref.watch(calSelectedProvider);
    final expanded = ref.watch(monthExpandedProvider);
    final view = ref.watch(calViewModeProvider);
    final events = ref.watch(eventsProvider).valueOrNull ?? const [];
    final monthStart = DateTime(selected.year, selected.month, 1);
    final conflicts = EventRepository.conflictsOf(
        events.where((e) => sameDay(e.start, selected)).toList());

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 20),
                  onPressed: () => expanded
                      ? _shiftMonth(ref, selected, -1)
                      : _shiftDay(ref, selected, -1),
                ),
                Expanded(
                  child: Center(
                    child: Text('${selected.year}年${selected.month}月',
                        style: const TextStyle(fontSize: 16)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 20),
                  onPressed: () => expanded
                      ? _shiftMonth(ref, selected, 1)
                      : _shiftDay(ref, selected, 1),
                ),
              ],
            ),
            Center(
              child: Text(
                expanded ? '月视图展开 · 在下方开始操作将自动收起' : '已收起为周 · 左右滑动切换天',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.normal,
                    color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          // 智能折叠：页面向下滚动超阈收起月历为周行。
          if (expanded &&
              n.metrics.axis == Axis.vertical &&
              n.metrics.pixels > 24) {
            ref.read(monthExpandedProvider.notifier).state = false;
          }
          return false;
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
          children: [
            if (expanded)
              _MonthPanel(
                  headers: _wdHeaders,
                  monthStart: monthStart,
                  selected: selected,
                  events: events)
            else
              _WeekStrip(wds: _wds, selected: selected, events: events),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'day',
                    label: Text('日视图'),
                    icon: Icon(Icons.today_outlined, size: 16)),
                ButtonSegment(
                    value: 'week',
                    label: Text('周视图'),
                    icon: Icon(Icons.view_week_outlined, size: 16)),
                ButtonSegment(
                    value: 'month',
                    label: Text('月视图'),
                    icon: Icon(Icons.grid_on_outlined, size: 16)),
              ],
              selected: {view},
              onSelectionChanged: (s) =>
                  ref.read(calViewModeProvider.notifier).state = s.first,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => showEventSheet(context, ref, presetDay: selected),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                foregroundColor: tokens.accent,
              ),
              child: Text('+ 新建日程（${view == 'day' ? '${selected.month}月${selected.day}日' : '安排时间'}）',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            if (conflicts.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF43F5E).withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: const Color(0xFFF43F5E).withValues(alpha: .3)),
                ),
                child: Text(
                  '⏱ 时间冲突：「${conflicts.first.a.title}」与「${conflicts.first.b.title}」'
                  '重叠 ${conflicts.first.overlapMin} 分钟',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            const SizedBox(height: 12),
            switch (view) {
              'day' => _DayTimeline(selected: selected, events: events),
              'week' => _WeekLanes(wds: _wds, selected: selected, events: events),
              _ => _MonthList(monthStart: monthStart, events: events),
            },
          ],
        ),
      ),
    );
  }

  void _shiftDay(WidgetRef ref, DateTime sel, int n) {
    ref.read(calSelectedProvider.notifier).state =
        DateTime(sel.year, sel.month, sel.day + n);
  }

  void _shiftMonth(WidgetRef ref, DateTime sel, int n) {
    final m = sel.month + n;
    ref.read(calSelectedProvider.notifier).state =
        DateTime(sel.year + (m - 1) ~/ 12, (m - 1) % 12 + 1, 1);
  }
}

/// 某天圆点状态色（优先级：进行中红 > 计划蓝(主题色) > 完成绿，原型 dotCls）。
Color? dotColorFor(List<CalEvent> dayEvents, Color accent) {
  if (dayEvents.any((e) => e.status == EventStatus.active)) {
    return const Color(0xFFF43F5E);
  }
  if (dayEvents.any((e) => e.status == EventStatus.planning)) return accent;
  if (dayEvents.any((e) => e.status == EventStatus.done)) {
    return const Color(0xFF34D399);
  }
  return null;
}

List<CalEvent> _onDay(List<CalEvent> all, DateTime d) =>
    all.where((e) => CalendarPage.sameDay(e.start, d)).toList();

/// 展开态：迷你月历（固定 6 行 42 格不跳版）。
class _MonthPanel extends ConsumerWidget {
  const _MonthPanel(
      {required this.headers,
      required this.monthStart,
      required this.selected,
      required this.events});

  final List<String> headers;
  final DateTime monthStart;
  final DateTime selected;
  final List<CalEvent> events;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final daysInMonth = DateTime(monthStart.year, monthStart.month + 1, 0).day;
    final leading = monthStart.weekday % 7; // 周日起
    final now = DateTime.now();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: context.cardDecoration,
      child: Column(
        children: [
          Row(
            children: [
              for (final h in headers)
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
                if (day < 1 || day > daysInMonth) {
                  return const SizedBox.shrink();
                }
                final date = DateTime(monthStart.year, monthStart.month, day);
                final isSel = CalendarPage.sameDay(date, selected);
                final isToday = CalendarPage.sameDay(date, now);
                final dot = dotColorFor(_onDay(events, date), tokens.accent);
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    ref.read(calSelectedProvider.notifier).state = date;
                    if (isSel) {
                      // 点当前日：展开/收起切换（原型 stripTap）。
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
                              fontWeight:
                                  isSel || isToday ? FontWeight.w800 : FontWeight.w500,
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
  const _WeekStrip(
      {required this.wds, required this.selected, required this.events});

  final List<String> wds;
  final DateTime selected;
  final List<CalEvent> events;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final days = List.generate(7, (i) => selected.add(Duration(days: i - 3)));

    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v.abs() < 100) return;
        ref.read(calSelectedProvider.notifier).state =
            DateTime(selected.year, selected.month, selected.day + (v < 0 ? 1 : -1));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: context.cardDecoration,
        child: Row(
          children: [
            for (final d in days)
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
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
                      color:
                          CalendarPage.sameDay(d, selected) ? tokens.accent : null,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Text(wds[d.weekday % 7],
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
                                : (dotColorFor(_onDay(events, d), tokens.accent) ??
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
      ),
    );
  }
}

/// 日视图时间轴：进行中脉冲卡 → 计划卡 → 已完成划线卡。
class _DayTimeline extends ConsumerWidget {
  const _DayTimeline({required this.selected, required this.events});

  final DateTime selected;
  final List<CalEvent> events;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final dayEvents = List<CalEvent>.from(_onDay(events, selected))
      ..sort((a, b) => a.start.compareTo(b.start));
    final active = dayEvents.where((e) => e.status == EventStatus.active).toList();
    final planning =
        dayEvents.where((e) => e.status == EventStatus.planning).toList();
    final done = dayEvents.where((e) => e.status == EventStatus.done).toList();

    if (dayEvents.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: context.cardDecoration,
        child: Center(
          child: Text('当天暂无安排 · 点上方「+ 新建日程」或试试「▶ 现在就开始」',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ),
      );
    }

    return Column(
      children: [
        for (final e in active) _ActiveCard(e: e),
        for (final e in planning) _EventCard(e: e, tokens: tokens),
        for (final e in done) _DoneCard(e: e, tokens: tokens),
      ],
    );
  }
}

class _EventCard extends ConsumerWidget {
  const _EventCard({required this.e, required this.tokens});

  final CalEvent e;
  final ThemeTokens tokens;

  static String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final c = e.colorOf(tokens.accent);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: c, width: 4)),
          boxShadow: tokens.cardShadow,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    e.allDay
                        ? '全天'
                        : '${_hm(e.start)} – ${e.end != null ? _hm(e.end!) : ''}${e.crossDay ? ' · 跨天' : ''}',
                    style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_horiz, size: 18),
              onPressed: () => _showActions(context, ref, e),
            ),
          ],
        ),
      ),
    );
  }

  void _showActions(BuildContext context, WidgetRef ref, CalEvent e) {
    showModalBottomSheet(
      context: context,
      builder: (bc) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
                title: Text(e.title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(e.allDay ? '全天 · 计划中' : '计划中')),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('▶ 现在就开始'),
              onTap: () async {
                Navigator.pop(bc);
                final repo = ref.read(eventRepositoryProvider);
                if (await repo.activeEvent() != null) {
                  if (bc.mounted) {
                    ScaffoldMessenger.of(bc).showSnackBar(
                        const SnackBar(content: Text('已有进行中的事项，请先结束当前事项')));
                  }
                  return;
                }
                await repo.update(e.copyWith(
                    status: EventStatus.active, start: DateTime.now()));
                ref.invalidate(eventsProvider);
                ref.invalidate(activeEventProvider);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
              title: const Text('删除', style: TextStyle(color: Color(0xFFEF4444))),
              onTap: () async {
                Navigator.pop(bc);
                await ref.read(eventRepositoryProvider).remove(e);
                ref.invalidate(eventsProvider);
                ref.invalidate(activeEventProvider);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 进行中脉冲卡（时间轴顶部，红框 + 实时耗时 + ■ 结束）。
class _ActiveCard extends ConsumerWidget {
  const _ActiveCard({required this.e});

  final CalEvent e;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(calendarTickerProvider); // 每秒刷新耗时
    final mins = DateTime.now().difference(e.start).inMinutes;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF43F5E).withValues(alpha: .06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF43F5E).withValues(alpha: .6)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  Text('● 进行中 · 已 $mins 分钟 · 做完点结束',
                      style: const TextStyle(
                          fontSize: 10.5, color: Color(0xFFF43F5E))),
                ],
              ),
            ),
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
                          '✔ 耗时 ${ended.durationMin} 分钟 · 实际耗时已回填（L1）· 写入时间账本（L4）'),
                      duration: const Duration(seconds: 3)));
                }
              },
              style:
                  FilledButton.styleFrom(backgroundColor: const Color(0xFFF43F5E)),
              child: const Text('■ 结束', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 已完成划线卡（绿框 + 实际耗时回填文案）。
class _DoneCard extends StatelessWidget {
  const _DoneCard({required this.e, required this.tokens});

  final CalEvent e;
  final ThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border:
              const Border(left: BorderSide(color: Color(0xFF34D399), width: 4)),
          boxShadow: tokens.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(e.title,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: Colors.grey)),
            Text(
              '✓ 已完成 · 实际耗时 ${e.durationMin ?? '—'} 分钟 · 已回填 L1 · 入时间账本 L4',
              style: const TextStyle(fontSize: 10.5, color: Color(0xFF10B981)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 周视图：选中日起 7 天真实安排条带。
class _WeekLanes extends ConsumerWidget {
  const _WeekLanes(
      {required this.wds, required this.selected, required this.events});

  final List<String> wds;
  final DateTime selected;
  final List<CalEvent> events;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final days = List.generate(7, (i) => DateTime(selected.year, selected.month, selected.day + i));
    return Column(
      children: [
        for (final d in days)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: context.cardDecoration,
              child: Row(
                children: [
                  Text('${d.day} ${wds[d.weekday % 7]}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final e in _onDay(events, d))
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: e.colorOf(tokens.accent).withValues(alpha: .15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${e.allDay ? '全天' : '${e.start.hour}点'} ${e.title}',
                              style: TextStyle(
                                  fontSize: 10.5, color: e.colorOf(tokens.accent)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_onDay(events, d).isEmpty)
                    Text('—',
                        style: TextStyle(fontSize: 11, color: scheme.outlineVariant)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 月视图：全月按天分组事件列表。
class _MonthList extends StatelessWidget {
  const _MonthList({required this.monthStart, required this.events});

  final DateTime monthStart;
  final List<CalEvent> events;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final daysInMonth = DateTime(monthStart.year, monthStart.month + 1, 0).day;
    final byDay = <DateTime, List<CalEvent>>{};
    for (final e in events) {
      if (e.start.year == monthStart.year && e.start.month == monthStart.month) {
        byDay
            .putIfAbsent(DateTime(e.start.year, e.start.month, e.start.day), () => [])
            .add(e);
      }
    }
    final keys = byDay.keys.toList()..sort();
    if (keys.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: context.cardDecoration,
        child: Center(
            child: Text('本月暂无安排（$daysInMonth 天）',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
      );
    }
    return Column(
      children: [
        for (final day in keys)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: context.cardDecoration,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${day.month}/${day.day} 周${['一', '二', '三', '四', '五', '六', '日'][day.weekday - 1]} · ${byDay[day]!.length} 项',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  for (final e in byDay[day]!)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: e.colorOf(tokens.accent))),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(e.title,
                                  style: const TextStyle(fontSize: 12.5),
                                  overflow: TextOverflow.ellipsis)),
                          Text(
                              e.allDay
                                  ? '全天'
                                  : '${e.start.hour}:${e.start.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                  fontSize: 11, color: scheme.onSurfaceVariant)),
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
