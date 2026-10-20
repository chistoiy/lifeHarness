import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/care_events.dart';
import '../data/care_repository.dart';
import '../domain/care_models.dart';
import '../domain/cycle_calc.dart';
import 'care_kit.dart';
import 'care_providers.dart';
import 'cycle_sheet.dart';

/// 她·周期主视图（原型 p-care：hero 渐变卡 / 迷你月历 / 今日感受 / 周期统计 / 提醒入口）。
class CareCycleView extends ConsumerWidget {
  const CareCycleView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(careDataProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败：$e')),
      data: (d) {
        final today = DateTime.now().withoutTimeCare();
        final now = cycleNow(d.cycleDays, today);
        final runs = periodRuns(d.cycleDays);
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
          children: [
            _Hero(now: now, consecutive: runs.length),
            const SizedBox(height: 12),
            _MiniCal(d: d, now: now),
            const SizedBox(height: 12),
            _TodaySymCard(d: d),
            const SizedBox(height: 12),
            _StatsCard(runs: runs),
            const SizedBox(height: 12),
            _RemindEntry(d: d),
          ],
        );
      },
    );
  }
}

/// hero：周期进行中 · 相位 / 大字 D/len / 进度条 / 下次月经与排卵 / chips。
class _Hero extends ConsumerWidget {
  const _Hero({required this.now, required this.consecutive});
  final CycleNow? now;
  final int consecutive;

  String _md(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = now;
    final today = DateTime.now().withoutTimeCare();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: careGrad(kCycleHeroStops,
            begin: const Alignment(-.7, -1), end: const Alignment(.7, 1)),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: careHex('#f472b6').withValues(alpha: .22),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -38,
            child: _blob(140, .10),
          ),
          Positioned(
            right: -8,
            top: 52,
            child: _blob(80, .10),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          n == null ? '开始记录你的周期' : '周期进行中 · ${n.phase}',
                          style: const TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.8,
                              color: Colors.white70),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(n == null ? '—' : '${n.cycleDay}',
                                style: const TextStyle(
                                    fontSize: 40,
                                    height: 1,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white)),
                            const SizedBox(width: 6),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(n == null ? '记录经期第 1 天开始' : '/ ${n.cycleLen} 天',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white70)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    key: const ValueKey('cy-record-today'),
                    onTap: () =>
                        showCycleDaySheet(context, DateTime.now().withoutTimeCare()),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(999)),
                      child: const Text('🩸 记录今天',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: n == null ? 0 : n.cycleDay / n.cycleLen,
                  minHeight: 6,
                  backgroundColor: Colors.white30,
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                ),
              ),
              if (n != null) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('下次月经 ${_md(n.nextStart)} · 还 ${n.daysToNext(today)} 天',
                        style: const TextStyle(fontSize: 10, color: Color(0xE6FFFFFF))),
                    if (n.ovDay != null)
                      Text('排卵日 ${_md(n.ovDay!)} · 还 ${n.daysToOv(today)} 天',
                          style: const TextStyle(fontSize: 10, color: Color(0xE6FFFFFF))),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (n.fertileStart != null && n.fertileEnd != null)
                      _pill('易孕期 ${_md(n.fertileStart!)} ~ ${_md(n.fertileEnd!)}'),
                    const SizedBox(width: 6),
                    if (consecutive > 1) _pill('已连续记录 $consecutive 个周期'),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _blob(double size, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            shape: BoxShape.circle, color: Colors.white.withValues(alpha: alpha)),
      );

  Widget _pill(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
        decoration: BoxDecoration(
            color: Colors.white24, borderRadius: BorderRadius.circular(999)),
        child: Text(t,
            style: const TextStyle(
                fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
      );
}

/// 迷你周期日历卡（标题月份 + 图例 + 补录入口）。
class _MiniCal extends StatelessWidget {
  const _MiniCal({required this.d, required this.now});
  final CareData d;
  final CycleNow? now;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final today = DateTime.now();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${today.month} 月 · 周期日历',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              ),
              const _LegendDot(color: kCycP, label: '月经'),
              const SizedBox(width: 8),
              const _LegendDot(color: kCycO, label: '排卵'),
              const SizedBox(width: 8),
              const _LegendDot(color: kCycF, label: '易孕'),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => context.push('/care/cycle/cal'),
                child: Text('补录 ›',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: tokens.accent)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          CycleMonthGrid(
            year: today.year,
            month: today.month,
            days: d.cycleDays,
            now: now,
            onDay: (day) => showCycleDaySheet(context, day),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final String color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: careHex(color), shape: BoxShape.circle)),
          const SizedBox(width: 3),
          Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
        ],
      );
}

/// 今日感受卡：chips 多选 + 备注 + 保存（saveSym 同构，二次保存覆盖当日）。
class _TodaySymCard extends ConsumerStatefulWidget {
  const _TodaySymCard({required this.d});
  final CareData d;

  @override
  ConsumerState<_TodaySymCard> createState() => _TodaySymCardState();
}

class _TodaySymCardState extends ConsumerState<_TodaySymCard> {
  final Set<String> _syms = {};
  final _noteCtl = TextEditingController();

  @override
  void dispose() {
    _noteCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_syms.isEmpty && _noteCtl.text.trim().isEmpty) {
      AppToast.show(context, '先选感受或写点什么');
      return;
    }
    await ref
        .read(careRepositoryProvider)
        .saveTodaySymptoms(DateTime.now(), _syms.toList(), _noteCtl.text.trim());
    careTouch(ref);
    if (!mounted) return;
    setState(() {
      _syms.clear();
      _noteCtl.clear();
    });
    AppToast.show(context, '✔ 今日感受已存 · 周期趋势可生成 AI 解读（本地聚合，不上传原始记录）');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('今日感受',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              GestureDetector(
                onTap: () => context.push('/care/sym'),
                child: Text('历史 ›',
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700, color: tokens.accent)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final s in kSymPool)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: CChip(
                      key: ValueKey('sym-$s'),
                      label: s,
                      dense: true,
                      selected: _syms.contains(s),
                      onTap: () => setState(
                          () => _syms.contains(s) ? _syms.remove(s) : _syms.add(s)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _noteCtl,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: '写点什么…',
                    hintStyle:
                        TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: tokens.cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: tokens.cardBorder),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('sym-save'),
                onPressed: _save,
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                child: const Text('保存', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 周期统计卡：平均周期 / 平均经期 / 规律度（趋势 › 进全屏统计页）。
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.runs});
  final List<PeriodRun> runs;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final avgC = avgCycleLen(runs);
    final avgP = avgPeriodLen(runs);
    final reg = regularity(runs);
    Widget cell(String v, String l, {Color? color}) => Column(
          children: [
            Text(v,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color ?? Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 2),
            Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('周期统计',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              GestureDetector(
                onTap: () => context.push('/care/cycle/stats'),
                child: Text('趋势 ›',
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700, color: tokens.accent)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: cell(avgC == null ? '—' : '${avgC.round()}天', '平均周期')),
              Container(width: 1, height: 30, color: tokens.cardBorder),
              Expanded(
                  child: cell(avgP == null ? '—' : '${avgP.round()}天', '平均经期')),
              Container(width: 1, height: 30, color: tokens.cardBorder),
              Expanded(
                  child: cell(runs.length < 3 ? '—' : reg.label, '规律度',
                      color: careHex('#fb7185'))),
            ],
          ),
        ],
      ),
    );
  }
}

/// 周期提醒入口卡（副行摘要按 KV 实时生成）。
class _RemindEntry extends StatelessWidget {
  const _RemindEntry({required this.d});
  final CareData d;

  bool _on(String k, bool def) => (d.reminders[k] ?? (def ? 'true' : 'false')) == 'true';

  @override
  Widget build(BuildContext context) {
    final lead = int.tryParse(d.reminders['care.rm.mensLead'] ?? '2') ?? 2;
    String zh(bool v) => v ? '已开' : '已关';
    return GestureDetector(
      onTap: () => context.push('/care/remind'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: context.cardDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('🔔 周期提醒',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                const Text('›', style: TextStyle(color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '月经${lead == 0 ? '当天' : '提前 $lead 天'} ${zh(_on('care.rm.mens', true))} · '
              '排卵日当天 ${zh(_on('care.rm.ovu', true))} · '
              '易孕期开始 ${zh(_on('care.rm.fertile', false))}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
