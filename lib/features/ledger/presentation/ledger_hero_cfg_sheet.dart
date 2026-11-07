import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/ledger_calc.dart';
import 'ledger_providers.dart';
import 'widgets/ledger_kit.dart';

/// S12 自定义顶部卡片数据位（原型 sheetLedgerHero · 高 72%）。
///
/// 草稿制：面板内改的是本地 [heroDraft]，点「保存」才落库（九·补 已拍板）；
/// 「取消」= 原型 closePanel('sheetLedgerHero')，不落库、卡片保持原样。
/// 预览随草稿实时重算（同 24 指标口径）。
Future<void> showLedgerHeroCfgSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .72,
      ),
      builder: (_) => const _HeroCfg(),
    );

class _HeroCfg extends ConsumerStatefulWidget {
  const _HeroCfg();

  @override
  ConsumerState<_HeroCfg> createState() => _HeroCfgState();
}

class _HeroCfgState extends ConsumerState<_HeroCfg> {
  late String _big;
  late List<String> _slots;

  @override
  void initState() {
    super.initState();
    final d = ref.read(ledgerDataProvider).valueOrNull;
    _big = d?.heroBig ?? 'balMonth';
    _slots = [...?d?.heroSlots, 'teMonth', 'tiMonth', 'avgTe'].take(3).toList();
  }

  Future<void> _save() async {
    final repo = ref.read(ledgerRepositoryProvider);
    await repo.setHeroBig(_big);
    await repo.setHeroSlots(_slots);
    ref.read(ledgerTickProvider.notifier).state++;
    if (!mounted) return;
    Navigator.of(context).pop();
    AppToast.show(context, '顶部卡片已保存');
  }

  void _set(int i, String k) => setState(() {
    if (i == 0) {
      _big = k;
    } else {
      _slots[i - 1] = k;
    }
  });

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(ledgerDataProvider).valueOrNull;
    if (d == null) return const SizedBox.shrink();
    // 预览口径：用草稿位覆盖快照（其余聚合与主屏一致）。
    final ctx = d.metricCtx();
    final preview = (big: _big, slots: _slots);
    final groups = <(String, List<(String, String)>)>[
      ('收支 · 日 / 周', finMetrics.sublist(0, 6)),
      ('收支 · 月 / 年', finMetrics.sublist(6, 12)),
      ('预算与日均', finMetrics.sublist(12, 18)),
      ('资产与全部', finMetrics.sublist(18)),
    ];
    final rows = <(int, String, String)>[
      (0, '大数字 · 醒目位', preview.big),
      (1, '数据位 2', preview.slots[0]),
      (2, '数据位 3', preview.slots[1]),
      (3, '数据位 4', preview.slots[2]),
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(
            children: [
              const Text(
                '自定义顶部卡片',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                '选择后点保存生效',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: _HeroPreview(
            big: preview.big,
            slots: preview.slots,
            ctx: ctx,
            hide: d.hideAmounts,
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
            children: [
              for (final (i, nm, cur) in rows)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  decoration: context.cardDecoration,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            nm,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '· ${finMetricName(cur)} '
                              '${finMetricTxt(cur, ctx, hide: d.hideAmounts)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: context.tokens.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      for (final (gn, ms) in groups) ...[
                        const SizedBox(height: 10),
                        Text(
                          gn,
                          style: TextStyle(
                            fontSize: 9,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final (k, n) in ms)
                              LChip(
                                label: n,
                                small: true,
                                on: cur == k,
                                onTap: () => _set(i, k),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Row(
            children: [
              Expanded(
                child: _BarBtn(
                  label: '取消',
                  filled: false,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _BarBtn(label: '保存', filled: true, onTap: _save),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BarBtn extends StatelessWidget {
  const _BarBtn({
    required this.label,
    required this.onTap,
    required this.filled,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? null : scheme.surfaceContainerHighest,
          gradient: filled ? context.tokens.gradient : null,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: filled ? FontWeight.w800 : FontWeight.w700,
            color: filled ? Colors.white : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// 草稿预览（原型 heroPrevH：grad 卡 + 大数字 + 三数据位）。
class _HeroPreview extends StatelessWidget {
  const _HeroPreview({
    required this.big,
    required this.slots,
    required this.ctx,
    required this.hide,
  });

  final String big;
  final List<String> slots;
  final FinMetricCtx ctx;
  final bool hide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '预览 · 实时反映草稿',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: context.tokens.gradient,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                finMetricName(big),
                style: const TextStyle(fontSize: 9, color: Colors.white70),
              ),
              const SizedBox(height: 2),
              Text(
                finMetricTxt(big, ctx, hide: hide),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -.4,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final k in slots)
                    Expanded(
                      child: Container(
                        margin: EdgeInsets.only(
                          right: k == slots.last ? 0 : 6,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              finMetricName(k),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 8,
                                color: Colors.white70,
                              ),
                            ),
                            Text(
                              finMetricTxt(k, ctx, hide: hide),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
