import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/care_models.dart';
import '../domain/cycle_calc.dart';
import 'care_kit.dart';
import 'care_providers.dart';
import 'cycle_sheet.dart';

/// p-cycleCal 周期日历全屏补录（原型：月份翻切 + 大网格 + 图例规则 + 三数据卡）。
class CycleCalPage extends ConsumerStatefulWidget {
  const CycleCalPage({super.key});

  @override
  ConsumerState<CycleCalPage> createState() => _CycleCalPageState();
}

class _CycleCalPageState extends ConsumerState<CycleCalPage> {
  late DateTime _cur = DateTime(DateTime.now().year, DateTime.now().month);

  void _step(int d) => setState(() => _cur = DateTime(_cur.year, _cur.month + d));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(careDataProvider);
    final today = DateTime.now().withoutTimeCare();
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('周期日历'),
            Text('经期 · 易孕 · 排卵三区',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) {
          final now = cycleNow(d.cycleDays, today);
          final monthDays = d.cycleDays.keys
              .where((k) =>
                  k.startsWith('${_cur.year}-${_cur.month.toString().padLeft(2, '0')}') &&
                  _hasRecord(d.cycleDays[k]!))
              .length;
          final dim = DateTime(_cur.year, _cur.month + 1, 0).day;
          final showPred = !_cur.isBefore(DateTime(today.year, today.month));
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _stepBtn('‹', () => _step(-1)),
                  Column(
                    children: [
                      Text('${_cur.year} 年 ${_cur.month} 月',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800)),
                      Text('点击任意日期补录 / 修改',
                          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                  _stepBtn('›', () => _step(1)),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: context.cardDecoration,
                child: Column(
                  children: [
                    Row(
                      children: [
                        const _Lg(color: kCycP, label: '月经'),
                        const _Lg(color: kCycS, label: '点滴', gap: false),
                        const _Lg(color: kCycO, label: '排卵'),
                        const _Lg(color: kCycF, label: '易孕'),
                        const _Lg(color: kCycToday, label: '今天'),
                        if (showPred)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: careHex(kCycO).withValues(alpha: .13),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text('预测',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: careHex(kCycO))),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    CycleMonthGrid(
                      year: _cur.year,
                      month: _cur.month,
                      big: true,
                      days: d.cycleDays,
                      now: now,
                      onDay: (day) => showCycleDaySheet(context, day),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: context.cardDecoration,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('图例与规则',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    ...const [
                      '· 排卵日 = 预测下次月经前 14 天；易孕窗口 = 排卵前 5 天 ~ 排卵后 1 天',
                      '· 实色 = 已记录；虚线描边 = 系统预测，补录后以实际为准',
                      '· 每次修改经期起始，将重新预测并保留旧预测存档',
                    ].map((t) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.5),
                          child: Text(t,
                              style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        )),
                    const SizedBox(height: 4),
                    Text('（Flutter 呈现以低透明度色块代替虚线描边，语义一致）',
                        style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: _stat(
                          '$monthDays/$dim', '本月已记录天数', null)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _stat(
                          now?.ovDay == null ? '—' : _md(now!.ovDay!),
                          '预测排卵日',
                          kCycO)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _stat(
                          now == null ? '—' : _md(now.nextStart),
                          '预测下次月经',
                          kCycP)),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  bool _hasRecord(CycleDay c) =>
      c.state.isNotEmpty ||
      c.syms.isNotEmpty ||
      c.note != null ||
      c.temp != null ||
      c.ovu != null ||
      c.flow != null;

  String _md(DateTime x) =>
      '${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';

  Widget _stat(String v, String l, String? color) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: context.cardDecoration,
        alignment: Alignment.center,
        child: Column(
          children: [
            Text(v,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: color == null ? null : careHex(color))),
            const SizedBox(height: 2),
            Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      );

  Widget _stepBtn(String t, VoidCallback onTap) => GestureDetector(
        key: ValueKey('cy-step-$t'),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: context.tokens.cardBorder.withValues(alpha: .5),
              shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
      );
}

class _Lg extends StatelessWidget {
  const _Lg({required this.color, required this.label, this.gap = true});
  final String color;
  final String label;
  final bool gap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(right: gap ? 10 : 6),
        child: Row(
          children: [
            Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(color: careHex(color), shape: BoxShape.circle)),
            const SizedBox(width: 3),
            Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
          ],
        ),
      );
}
