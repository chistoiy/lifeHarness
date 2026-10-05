import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../../shared/widgets/share_card.dart';
import '../domain/ledger_calc.dart';
import '../domain/ledger_txn.dart';
import 'ledger_providers.dart';
import 'widgets/ledger_kit.dart';

/// L16 年度总结（原型 p-yearly · TITLES ['年度总结','']；renderYearly 逐段对照）。
/// 年份 ‹ › 步进 + 渐变英雄卡 + 月度收支柱 + 年度分类 Top + 年度最大单笔 +
/// 生成分享图（V1.57 走 share_card 公共通道真渲染）/ 看明细 ›（跳 L4）。
class LedgerYearlyPage extends ConsumerStatefulWidget {
  const LedgerYearlyPage({super.key});

  @override
  ConsumerState<LedgerYearlyPage> createState() => _LedgerYearlyPageState();
}

class _LedgerYearlyPageState extends ConsumerState<LedgerYearlyPage> {
  int _year = DateTime.now().year;

  static const _rose = Color(0xFFFB7185);
  static const _slate = Color(0xFF94A3B8);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ledgerDataProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('年度总结'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) => TabularNums(child: _body(d)),
      ),
    );
  }

  /// 年度分享卡（原型 yrData/yrShareRender 同构：hero 三格 + 12 月柱 + 分类 Top5 + 最大单笔；
  /// 金额一律走 amtText(hide)，隐藏金额态不泄漏真实数字）。
  ShareCardModel _yearShareCard(LedgerData d, YearStat ys, bool hide, String y) {
    final big = ys.big;
    String txName(LedgerTxn t) =>
        t.note.isNotEmpty ? t.note : d.catOf(t.catId).name;
    final rank = [
      for (final (i, e) in ys.rank.indexed)
        ShareCardRow('${i + 1} · ${d.catOf(e.$1).name}',
            amtText(e.$2, hide: hide)),
    ];
    return ShareCardModel(
      file: '$y年记账总结',
      eyebrow: 'LifeHarness · 本地账本',
      title: '$y 年收支总结',
      line: '${ys.cnt} 笔流水 · 记账 ${ys.actDays} 天 · '
          '日均 ${amtText(ys.avgDaily, hide: hide)}',
      big: amtText(ys.exp, hide: hide),
      unit: '全年支出',
      tiles: [
        ShareCardTile('全年收入', amtText(ys.inc, hide: hide)),
        ShareCardTile('全年结余', amtText(ys.inc - ys.exp, hide: hide)),
        ShareCardTile('最大单笔',
            big == null ? '—' : amtText(big.amt, hide: hide)),
      ],
      sections: [
        ShareCardSection(
          head: '月度支出',
          bars: [for (final b in ys.months) b.exp],
          barLabels: [for (final b in ys.months) '${b.m}'],
        ),
        ShareCardSection(
          head: '年度分类 Top ${ys.rank.length}',
          rows: rank.isEmpty ? const [ShareCardRow('本年暂无支出')] : rank,
        ),
        if (big != null)
          ShareCardSection(head: '最大单笔', rows: [
            ShareCardRow('${big.date} · ${txName(big)}',
                amtText(big.amt, hide: hide)),
          ]),
      ],
      textVersion: [
        '$y 年收支总结',
        '全年支出 ${amtText(ys.exp, hide: hide)} · 收入 ${amtText(ys.inc, hide: hide)} · '
            '结余 ${amtText(ys.inc - ys.exp, hide: hide)}',
        '${ys.cnt} 笔流水 · 记账 ${ys.actDays} 天',
        if (big != null)
          '最大单笔 ${big.date} ${txName(big)} ${amtText(big.amt, hide: hide)}',
        '〔年度分类 Top〕',
        for (final e in ys.rank)
          '${d.catOf(e.$1).name}：${amtText(e.$2, hide: hide)}',
      ].join('\n'),
    );
  }

  Widget _body(LedgerData d) {
    final scheme = Theme.of(context).colorScheme;
    final hide = d.hideAmounts;
    final y = '$_year';
    final ys = yearStat(d.txns, y);
    final big = ys.big;

    String txName(LedgerTxn t) =>
        t.note.isNotEmpty ? t.note : d.catOf(t.catId).name;

    // 月度收支柱：按 max(支出, 收入) 归一（原型 renderYearly 口径）。
    final mx = ys.months.fold<double>(
      1,
      (a, b) => math.max(a, math.max(b.exp, b.inc)),
    );

    Widget stepBtn(String label, VoidCallback onTap) => InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
    );

    Widget bar(Widget child) => Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: context.cardDecoration,
      child: child,
    );

    Widget cardTitle(String t) => Text(
      t,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: scheme.onSurface.withValues(alpha: .7),
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        Row(
          children: [
            stepBtn('‹', () => setState(() => _year--)),
            Expanded(
              child: Center(
                child: Text(
                  '$y 年',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            stepBtn('›', () => setState(() => _year++)),
          ],
        ),
        // 英雄卡（grad · 全年支出大数字）
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: context.tokens.gradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: context.tokens.g1.withValues(alpha: .2),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                '$y 年 · 本地账本',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: .8),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                amtText(ys.exp, hide: hide),
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '全年支出 · 收入 ${amtText(ys.inc, hide: hide)} · '
                '结余 ${amtText(ys.inc - ys.exp, hide: hide)}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: .8),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${ys.cnt} 笔流水',
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                  const SizedBox(width: 24),
                  Text(
                    '记账 ${ys.actDays} 天',
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                  const SizedBox(width: 24),
                  Text(
                    '日均 ${amtText(ys.avgDaily, hide: hide)}',
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                ],
              ),
            ],
          ),
        ),
        // 月度收支（12 组双柱 + 月号）
        bar(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cardTitle('月度收支'),
              const SizedBox(height: 12),
              SizedBox(
                height: 110,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final b in ys.months)
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              width: 12,
                              height: (b.inc / mx * 90)
                                  .round()
                                  .clamp(0, 90)
                                  .toDouble(),
                              decoration: const BoxDecoration(
                                color: Color(0xB334D399),
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(2),
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              width: 12,
                              height: (b.exp / mx * 90)
                                  .round()
                                  .clamp(0, 90)
                                  .toDouble(),
                              decoration: const BoxDecoration(
                                color: _rose,
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(2),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  for (final b in ys.months)
                    Expanded(
                      child: Text(
                        '${b.m}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 8, color: _slate),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        // 年度分类 Top5
        bar(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cardTitle('年度分类 Top'),
              const SizedBox(height: 8),
              if (ys.rank.isEmpty)
                const Text(
                  '暂无数据',
                  style: TextStyle(fontSize: 11, color: _slate),
                )
              else
                for (var i = 0; i < math.min(5, ys.rank.length); i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(fontSize: 12, color: _slate),
                          ),
                        ),
                        const SizedBox(width: 8),
                        LTile(
                          iconKey: d.catOf(ys.rank[i].$1).icon,
                          color: d.catOf(ys.rank[i].$1).color,
                          size: 24,
                          radius: 8,
                          iconSize: 14,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            d.catOf(ys.rank[i].$1).name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          amtText(ys.rank[i].$2, hide: hide),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
        // 年度最大单笔
        if (big != null)
          bar(
            Row(
              children: [
                const LTile(
                  iconKey: 'star',
                  color: '#F59E0B',
                  size: 36,
                  iconSize: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '年度最大单笔',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${big.date} · ${txName(big)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: _slate),
                      ),
                    ],
                  ),
                ),
                Text(
                  amtText(big.amt, hide: hide),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _rose,
                  ),
                ),
              ],
            ),
          ),
        // 分享 / 看明细
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: context.tokens.gradient,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: TextButton(
                      onPressed: () => showShareCardSheet(
                          context, _yearShareCard(d, ys, hide, y),
                          src: '记账'),
                      child: const Text(
                        '生成分享图',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 48,
                child: GestureDetector(
                  onTap: () => context.push('/ledger/report'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      '看明细 ›',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
