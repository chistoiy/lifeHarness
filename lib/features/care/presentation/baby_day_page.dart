import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../data/care_repository.dart';
import '../domain/care_agg.dart';
import '../domain/care_events.dart';
import '../domain/care_models.dart';
import 'care_kit.dart';
import 'care_providers.dart';
import 'event_sheet.dart';
import 'ev_sheets.dart';

/// p-babyDay 全天记录（原型 C7）：按日分组时间线 + 日汇总行 + 类型多选筛选 +
/// 快速记录宫格（sheetEvPanel）+ 「N分钟前」实时徽章。
class CareBabyDayPage extends ConsumerWidget {
  const CareBabyDayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(careDataProvider);
    final kinds = ref.watch(careDayFilterProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('全天记录'),
            Text('时间线 · 按类型筛选',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) {
          final days = d.logsByDay.keys.toList()..sort((a, b) => b.compareTo(a));
          final total = d.logs.length;
          // 同一帧共用一个「now」（时间源缝 careClockProvider，测试可固定）。
          final now = ref.watch(careClockProvider)();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: [
              Row(
                children: [
                  GestureDetector(
                    key: const ValueKey('bd-filter'),
                    onTap: () => showDayFilterSheet(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: kinds.isEmpty
                            ? tokensChip(context)
                            : careHex('#6366f1').withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('${bdFilterLabel(d, kinds)} ▾',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: kinds.isEmpty
                                  ? Colors.grey
                                  : const Color(0xFF6366F1))),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        key: const ValueKey('bd-range'),
                        '近 ${days.length} 天 · $total 条记录',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey),
                      ),
                    ),
                  ),
                  _RoundBtn(
                    key: const ValueKey('bd-stats'),
                    tip: '喂养分析',
                    icon: Icons.bar_chart,
                    onTap: () => context.push('/care/stats'),
                  ),
                  const SizedBox(width: 8),
                  _RoundBtn(
                    key: const ValueKey('bd-quick'),
                    tip: '快速记录',
                    icon: Icons.grid_view_rounded,
                    onTap: () async {
                      final k = await showEvPanel(context);
                      if (k != null && context.mounted) {
                        showEventLogSheet(context, kind: k);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              for (final day in days)
                if (_visible(d.logsOfDay(day), kinds).isNotEmpty)
                  _DayBlock(
                      day: day,
                      d: d,
                      now: now,
                      logs: _visible(d.logsOfDay(day), kinds)),
              if (days.every((day) => _visible(d.logsOfDay(day), kinds).isEmpty))
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                      child: Text('暂无该类型记录',
                          style: TextStyle(fontSize: 11, color: Colors.grey))),
                ),
            ],
          );
        },
      ),
    );
  }

  static List<CareRecord> _visible(List<CareRecord> logs, Set<String> kinds) =>
      kinds.isEmpty ? logs : logs.where((r) => kinds.contains(r.k)).toList();
}

Color tokensChip(BuildContext context) =>
    context.tokens.cardBorder.withValues(alpha: .8);

/// 筛选钮文案（bdLbl 同构：全部 / 单类名 / 已选 N 项）。
String bdFilterLabel(CareData d, Set<String> kinds) => kinds.length == 1
    ? d.evOf(kinds.first).name
    : kinds.isEmpty
        ? '全部'
        : '已选 ${kinds.length} 项';

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({super.key, required this.tip, required this.icon, required this.onTap});
  final String tip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Tooltip(
      message: tip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: tokens.card,
            shape: BoxShape.circle,
            border: Border.all(color: tokens.cardBorder),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 16, color: tokens.cardBorder),
        ),
      ),
    );
  }
}

/// 单日分组：日标题 + 汇总行 + 记录行（bdRow 同构）。
/// `now` 由页面 build 一次取值注入（careClockProvider 时间源缝），
/// 同帧各分组共用，避免多次 DateTime.now() 跨分钟/日界互不一致。
class _DayBlock extends StatelessWidget {
  const _DayBlock(
      {required this.day, required this.d, required this.logs, required this.now});
  final String day;
  final CareData d;
  final List<CareRecord> logs;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final today = now.withoutTimeCare();
    final todayKey = careDayKey(today);
    final sum = careDaySummary(logs);
    final nowMin = now.hour * 60 + now.minute;
    final baby = d.currentBaby;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(careDayLabel(day, today),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Text(
                day == todayKey && baby != null
                    ? careAgeText(baby.birth, today)
                    : day,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            decoration: context.cardDecoration,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                if (sum.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: tokens.cardBorder)),
                    ),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        for (final s in sum)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                  width: 5,
                                  height: 5,
                                  decoration: const BoxDecoration(
                                      color: Color(0xFFF59E0B),
                                      shape: BoxShape.circle)),
                              const SizedBox(width: 5),
                              Text(s,
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.grey)),
                            ],
                          ),
                      ],
                    ),
                  ),
                for (final r in logs)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color: tokens.cardBorder.withValues(alpha: .5))),
                    ),
                    child: GestureDetector(
                      key: ValueKey('day-rec-${r.id}'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => showEventLogSheet(context, edit: r),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                              width: 42,
                              child: Text(r.s,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                      fontFeatures: [
                                        FontFeature.tabularFigures()
                                      ]))),
                          const SizedBox(width: 6),
                          Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.only(top: 6),
                              decoration: BoxDecoration(
                                  color: careHex(careDotColor(r.k)),
                                  shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Text(d.iconOf(r), style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(d.evOf(r.k).name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 150),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(careLogContent(r),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF64748B))),
                                if (careShowRange(r))
                                  Text('${r.s}-${r.e}',
                                      style: const TextStyle(
                                          fontSize: 9, color: Colors.grey)),
                                if (day == todayKey &&
                                    nowMin - careT2m(r.s) >= 0 &&
                                    nowMin - careT2m(r.s) < 60)
                                  Container(
                                    margin: const EdgeInsets.only(top: 3),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: const Color(0xFFFCE7F3),
                                        borderRadius: BorderRadius.circular(999)),
                                    child: Text(
                                        nowMin - careT2m(r.s) <= 0
                                            ? '刚刚'
                                            : '${nowMin - careT2m(r.s)}分钟前',
                                        style: const TextStyle(
                                            fontSize: 8,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFFEC4899))),
                                  ),
                              ],
                            ),
                          ),
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
}

/// sheetDayFilter 记录类型多选（EV_BASE 13 类 chip；点选即时生效，不筛选清空）。
Future<void> showDayFilterSheet(BuildContext context) {
  return showCareSheet<void>(context, builder: (bc) => const _DayFilter());
}

class _DayFilter extends ConsumerWidget {
  const _DayFilter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(careDataProvider).valueOrNull;
    final kinds = ref.watch(careDayFilterProvider);
    if (d == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('筛选记录项',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
            const cols = 3;
            const gap = 8.0;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final k in kEventBaseKeys)
                  SizedBox(
                    width: w,
                    child: CChip(
                      key: ValueKey('bdf-$k'),
                      label: '${d.evOf(k).icon} ${d.evOf(k).name}',
                      selected: kinds.contains(k),
                      onTap: () {
                        final next = {...kinds};
                        if (next.contains(k)) {
                          next.remove(k);
                        } else {
                          next.add(k);
                        }
                        ref
                            .read(careDayFilterProvider.notifier)
                            .state = next;
                      },
                    ),
                  ),
              ],
            );
          }),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('bdf-clear'),
                  onPressed: () => ref
                      .read(careDayFilterProvider.notifier)
                      .state = const {},
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13)),
                  child: const Text('不筛选',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  key: const ValueKey('bdf-ok'),
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: careGrad(
                          const ['#6366f1', '#8b5cf6', '#c084fc'],
                          begin: const Alignment(-1, 0),
                          end: const Alignment(1, 0)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text('确定',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
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
