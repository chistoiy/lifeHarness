import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/care_models.dart';
import '../domain/cycle_calc.dart';
import 'care_kit.dart';
import 'care_providers.dart';
import 'cycle_sheet.dart';

/// p-symHistory 感受历史（按 tag 筛选 + 日卡片流 + 补录入口）。
class SymHistoryPage extends ConsumerStatefulWidget {
  const SymHistoryPage({super.key});

  @override
  ConsumerState<SymHistoryPage> createState() => _SymHistoryPageState();
}

class _SymHistoryPageState extends ConsumerState<SymHistoryPage> {
  String _filter = '全部';

  /// 原型口径：症状含「痛」→ 不适；食欲 → 消化；其余 → 情绪。
  static String tagOf(List<String> syms) =>
      syms.any((s) => s.contains('痛')) ? '不适' : (syms.any((s) => s.contains('食欲')) ? '消化' : '情绪');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(careDataProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('感受历史'),
            Text('每日记录 · 趋势解读',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) {
          final today = DateTime.now().withoutTimeCare();
          final now = cycleNow(d.cycleDays, today);
          final entries = d.cycleDays.values
              .where((c) => c.syms.isNotEmpty || (c.note?.isNotEmpty ?? false))
              .toList()
            ..sort((a, b) => b.day.compareTo(a.day));
          final filtered = entries.where((c) {
            if (_filter == '全部') return true;
            return c.syms.isNotEmpty && tagOf(c.syms) == _filter;
          }).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: [
              Row(
                children: [
                  for (final f in const ['全部', '不适', '情绪', '消化'])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: CChip(
                        key: ValueKey('symf-$f'),
                        label: f,
                        dense: true,
                        selected: _filter == f,
                        onTap: () => setState(() => _filter = f),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                      child: Text('该筛选下暂无记录',
                          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant))),
                ),
              for (final c in filtered)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _card(c, now),
                ),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                key: const ValueKey('sym-append'),
                onPressed: () => showCycleDaySheet(context, DateTime.now().withoutTimeCare()),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(
                      color: scheme.outlineVariant,
                      style: BorderStyle.solid),
                ),
                icon: const Text('+', style: TextStyle(fontSize: 14)),
                label: const Text('补录某一天的感受', style: TextStyle(fontSize: 13)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _card(CycleDay c, CycleNow? now) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final dt = DateTime.parse(c.day);
    final kind = switch (c.state) {
      'p1' || 'p' => '月经期',
      's' => '点滴',
      _ => switch (dayMarkKind(c, now)) {
          'o' => '排卵期',
          'f' => '易孕期',
          _ => '—',
        },
    };
    return GestureDetector(
      onTap: () => showCycleDaySheet(context, dt),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: context.cardDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(c.day.substring(5),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                  decoration: BoxDecoration(
                      color: careHex(kCycP).withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(999)),
                  child: Text(
                    kind == '—' ? '—' : '$kind${c.flow != null && kind == '月经期' ? ' · 经量${c.flow}' : ''}',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: careHex(kCycP)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (c.syms.isEmpty)
              Text('未选感受', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant))
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in c.syms)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                      decoration: BoxDecoration(
                          color: tokens.cardBorder,
                          borderRadius: BorderRadius.circular(999)),
                      child: Text(s, style: const TextStyle(fontSize: 10)),
                    ),
                ],
              ),
            if (c.note?.isNotEmpty ?? false) ...[
              const SizedBox(height: 6),
              Text('📝 ${c.note}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 单日推导标记类别（供感受历史相位标签）。
String? dayMarkKind(CycleDay c, CycleNow? now) {
  final ov = now?.ovDay;
  if (ov != null && careDayKey(ov) == c.day) return 'o';
  final fs = now?.fertileStart;
  final fe = now?.fertileEnd;
  if (fs != null && fe != null) {
    final dt = DateTime.parse(c.day);
    if (!dt.isBefore(fs) && !dt.isAfter(fe)) return 'f';
  }
  return null;
}
