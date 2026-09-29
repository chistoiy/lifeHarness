import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/nav/nav_module.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/linkage/stats_providers.dart';
import '../../../calendar/domain/time_block.dart';
import '../../../calendar/presentation/calendar_providers.dart';

/// 今日安排（原型 p-dashboard 的 dashEvents 卡 · R14-14 自 dashboard_page 拆出）。
///
/// 口径与日历轴视图同源：**日程事件 + 手动/计时时间块**（事件回填的块由事件本身
/// 表达，不重复列示），按开始分钟排序。问候卡上的「N 场安排」直接取这份列表长度，
/// 保证「数字＝列表条数」这条不变式（原型同款断言）。

/// 一条今日安排（事件或时间块的统一展示投影）。
class TodayPlan {
  const TodayPlan({
    required this.title,
    required this.startMin,
    this.endMin,
    this.color,
    this.allDay = false,
    this.timing = false,
  });

  final String title;
  final int startMin;
  final int? endMin;
  final Color? color;
  final bool allDay;

  /// 计时中块（source=timing）：结束时间未定，显示状态而不是时间。
  final bool timing;

  static String _hm(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  String get timeLabel => allDay
      ? '全天'
      : timing
          ? '计时中'
          : '${_hm(startMin)}-${endMin == null ? '' : _hm(endMin!)}';
}

/// 事件 + 时间块 → 单一今日安排列表（与日历轴视图同源谓词）。
List<TodayPlan> mergeTodayPlans(
  List<CalEvent> events,
  List<TimeBlock> blocks, {
  required DateTime now,
  required Map<String, Color> catColors,
  required Color accent,
}) {
  bool dayOf(DateTime d) =>
      d.year == now.year && d.month == now.month && d.day == now.day;
  final out = <TodayPlan>[
    for (final e in events.where((e) => dayOf(e.start)))
      TodayPlan(
        title: e.title,
        startMin: e.start.hour * 60 + e.start.minute,
        endMin: e.end == null ? null : e.end!.hour * 60 + e.end!.minute,
        allDay: e.allDay,
        color: e.colorOf(accent),
      ),
    // 事件回填块随事件卡已表达（calendar_page 轴视图同款过滤）。
    for (final b in blocks.where((b) => b.source != kSrcEvent))
      TodayPlan(
        title: (b.note == null || b.note!.isEmpty) ? b.catName : b.note!,
        startMin: b.startMin,
        endMin: b.endMin,
        timing: b.source == kSrcTiming,
        color: catColors[b.catName],
      ),
  ]..sort((a, b) => a.startMin.compareTo(b.startMin));
  return out;
}

/// 「今日日程」卡：合并列表 + 空态一行 + 超出 4 条折叠。
class TodayScheduleCard extends ConsumerWidget {
  const TodayScheduleCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final day0 = DateTime(now.year, now.month, now.day);
    final events = ref.watch(eventsProvider).valueOrNull ?? const <CalEvent>[];
    final blocks =
        ref.watch(dayBlocksProvider(day0)).valueOrNull ?? const <TimeBlock>[];
    final plans = mergeTodayPlans(events, blocks,
        now: now,
        catColors: ref.watch(catColorsByNameProvider),
        accent: tokens.accent);

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
          if (plans.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('今天还没有安排',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ),
          for (final (i, p) in plans.take(4).indexed)
            Container(
              key: ValueKey('plan-row-$i'),
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
                      color: p.color ?? tokens.accent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(p.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w600))),
                  Text(p.timeLabel,
                      style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          if (plans.length > 4)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('还有 ${plans.length - 4} 项…',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }
}
