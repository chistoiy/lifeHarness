import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/health_calc.dart';
import '../domain/health_models.dart';
import 'health_providers.dart';
import 'health_sheets.dart';

/// 睡眠记录（原型 `p-sleepLog` · 路由 `/health/sleep` · 批2）。
///
/// 口径三条写在最近处：
/// - **归属日＝醒来日**（跨天由 `sleepDurationMin` 补 1440，屏上不另算一遍）；
/// - 柱状按「是否达到当日目标」着色，目标分母只吃 `HealthSettings`，不写死 8 小时；
/// - 无记录的日期＝空槽，不拿 0 当读数；点流水行＝就地改这一晚（复用录入弹层，不另造表单）。
class HealthSleepPage extends ConsumerWidget {
  const HealthSleepPage({super.key});

  static const Key kBars = ValueKey('hsl-bars');
  static const Key kList = ValueKey('hsl-list');
  static const Key kAdd = ValueKey('hsl-add');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(healthTickProvider);
    final pid = ref.watch(activeHealthProfileProvider);
    final st = ref.watch(healthSettingsProvider);
    final now = ref.watch(healthClockProvider)();
    final goalMin = st.sleepGoalHours() * 60;
    final from = dayKey(now.subtract(const Duration(days: 29)));
    final to = dayKey(now);
    final records = ref.watch(_sleepRangeProvider((pid, from, to))).valueOrNull ?? const <SleepRecord>[];
    final byDate = {for (final r in records) r.date: r};

    return Scaffold(
      appBar: AppBar(
        title: const Text('睡眠记录'),
        actions: [
          IconButton(
            key: kAdd,
            tooltip: '记一晚',
            icon: const Icon(Icons.add),
            onPressed: () => showHealthSleepSheet(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('hsl-fab'),
        // 本屏只有睡眠一件事：FAB 直达睡眠录入，不再让用户在「喝水／睡眠」里二选一。
        onPressed: () => showHealthSleepSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('记一晚'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 84),
        children: [
          _weekChart(context, now, byDate, goalMin, st.bedLine()),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('流水', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
              const Spacer(),
              Text('目标 ${goalMin ~/ 60} 小时 · 界线 ${st.bedLine()}',
                  style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 6),
          if (records.isEmpty)
            const EmptyDashRow(text: '还没有睡眠记录 · 点右上记一晚')
          else
            Column(
              key: kList,
              children: [
                for (final r in records)
                  _row(context, r, goalMin, st.bedLine(), onEdit: () => showHealthSleepSheet(context, editing: r)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _weekChart(BuildContext context, DateTime now, Map<String, SleepRecord> byDate, int goalMin, String line) {
    final scheme = Theme.of(context).colorScheme;
    final days = [for (var i = 6; i >= 0; i--) dayKey(now.subtract(Duration(days: i)))];
    final maxMin = <int>[goalMin, ...days.map((d) => byDate[d]?.durationMin ?? 0)].reduce((a, b) => a > b ? a : b);
    return Container(
      decoration: context.cardDecoration,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('近 7 天', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('达标线 ${goalMin ~/ 60} 小时', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            key: kBars,
            height: 96,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final d in days)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            key: ValueKey('hsl-bar-$d'),
                            height: (byDate[d] == null ? 2 : (byDate[d]!.durationMin / maxMin * 74).clamp(4, 74)).toDouble(),
                            decoration: BoxDecoration(
                              color: byDate[d] == null
                                  ? scheme.outlineVariant
                                  : (byDate[d]!.durationMin >= goalMin ? scheme.primary : scheme.tertiary),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(d.substring(8),
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, SleepRecord r, int goalMin, String line, {required VoidCallback onEdit}) {
    final scheme = Theme.of(context).colorScheme;
    final onTime = fellAsleepOnTime(r.bedTime, line);
    return InkWell(
      key: ValueKey('hsl-row-${r.date}'),
      borderRadius: BorderRadius.circular(12),
      onTap: onEdit,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: context.cardDecoration,
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Text(r.date.substring(5).replaceAll('-', '.'),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${r.bedTime} → ${r.wakeTime}', style: const TextStyle(fontSize: 12)),
                  if (r.hasStages)
                    Text('深 ${r.deepMin ?? 0}′ · 浅 ${r.lightMin ?? 0}′ · REM ${r.remMin ?? 0}′ · 醒 ${r.awakeMin ?? 0}′',
                        style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_hm(r.durationMin), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                Text(onTime ? '按时' : '晚睡',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: onTime ? scheme.onSurfaceVariant : scheme.error)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 一段窗口的睡眠读数（按档案隔离，跨档案一律不聚合）。
final _sleepRangeProvider = FutureProvider.family<List<SleepRecord>, (int, String, String)>((ref, a) async {
  ref.watch(healthTickProvider);
  final list = await ref.watch(healthRepositoryProvider).sleepRange(a.$1, a.$2, a.$3);
  return list..sort((x, y) => y.date.compareTo(x.date));
});

String _hm(int m) {
  final h = m ~/ 60, mm = m % 60;
  if (h == 0) return '$mm 分';
  return mm == 0 ? '$h 小时' : '$h 小时 $mm 分';
}
