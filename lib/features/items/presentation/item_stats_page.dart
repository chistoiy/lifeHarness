import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/share_card.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/item_calc.dart';
import '../domain/item_models.dart';
import 'item_detail_page.dart';
import 'items_kit.dart';
import 'items_providers.dart';

/// P7c 持有成本统计（需求 V1.42 模块9 · 原型 renderItemStats 3769-3792 对译）。
///
/// 口径：hero 三格 + Top5 日均榜（点行进详情）+ 分类占比甜甜圈（catPoolShare
/// 实算）+ 近 6 月净额柱（monthlyItemCashflow，点柱 toast 钻取当月流水口径）。
/// 数值全部由 item_calc 走 itemsClockProvider 的 now 实算（HG-E1）。
class ItemStatsPage extends ConsumerStatefulWidget {
  const ItemStatsPage({super.key});

  @override
  ConsumerState<ItemStatsPage> createState() => _ItemStatsPageState();
}

class _ItemStatsPageState extends ConsumerState<ItemStatsPage> {
  @override
  Widget build(BuildContext context) {
    final now = ref.watch(itemsClockProvider)();
    final async = ref.watch(itemsDataProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('成本统计'),
            Text('摊薄 · 占比 · 近 6 月支出',
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) => _body(d, now),
      ),
    );
  }

  Widget _body(ItemsData d, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    final bill = d.active;
    final total = totalDailyCost(bill, now);
    final poolAll =
        d.items.fold<double>(0, (s, x) => s + poolOf(x)); // 含冻结＝全周期口径
    final top = [...bill]
      ..sort(
          (a, b) => (costPerDay(b, now) ?? 0).compareTo(costPerDay(a, now) ?? 0));
    final top5 = top.take(5).toList();
    final maxC = top5.isEmpty ? 0.0 : costPerDay(top5.first, now) ?? 0;
    final shares = catPoolShare(d);
    final months = monthlyItemCashflow(d, now);
    final maxM =
        months.map((m) => m.$2.abs()).fold<double>(0, (a, b) => a > b ? a : b);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        // hero 卡：大数字 + 分享钮 + 三格
        Container(
          padding: const EdgeInsets.all(16),
          decoration: context.cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('今日合计持有成本（计费中 ${bill.length} 件）',
                            style: const TextStyle(
                                fontSize: 11, color: kItemMuted)),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(itemMoney(total),
                                key: const ValueKey('i-stats-total'),
                                style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    color: kItemMint)),
                            const Text('/天',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: kItemMuted)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  MiniBtn(
                    key: const ValueKey('i-stats-share'),
                    icon: Icons.ios_share,
                    label: '分享',
                    onTap: () => showShareCardSheet(context,
                        _shareStatsCard(d, now), src: '物品'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _grid3('本月它花掉了', fmtY((total * 30).roundToDouble())),
                  _grid3('成本池总额', fmtY(poolAll.roundToDouble())),
                  _grid3('件均日均',
                      bill.isEmpty ? '—' : itemMoney(total / bill.length)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Top 5 日均成本榜
        Container(
          padding: const EdgeInsets.all(16),
          decoration: context.cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Top 5 · 日均成本榜',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              if (top5.isEmpty)
                const Text('暂无计费中物品',
                    style: TextStyle(fontSize: 11, color: kItemMuted))
              else
                for (final x in top5)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GestureDetector(
                      key: ValueKey('i-stats-top-${x.id}'),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => ItemDetailPage(itemId: x.id!))),
                      child: Row(
                        children: [
                          Icon(itemCatIcon(x.category), size: 16),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 92,
                            child: Text(x.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700)),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                minHeight: 7,
                                value: maxC <= 0
                                    ? 0
                                    : ((costPerDay(x, now) ?? 0) / maxC)
                                        .clamp(0.0, 1.0)
                                        .toDouble(),
                                backgroundColor:
                                    scheme.surfaceContainerHighest,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('${itemMoney2(costPerDay(x, now) ?? 0)}/天',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: kItemMint)),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 分类占比 · 按成本池（甜甜圈 + 图例）
        Container(
          padding: const EdgeInsets.all(16),
          decoration: context.cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('分类占比 · 按成本池',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 96,
                    height: 96,
                    child: CustomPaint(
                      key: const ValueKey('i-stats-donut'),
                      painter: _DonutPainter(
                        fractions: [
                          for (final s in shares)
                            poolAll <= 0 ? 0.0 : s.$2 / poolAll
                        ],
                        colors: [
                          for (var i = 0; i < shares.length; i++)
                            kItemChartColors[i % kItemChartColors.length]
                        ],
                        trackColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < shares.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: kItemChartColors[
                                        i % kItemChartColors.length],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                    child: Text(shares[i].$1,
                                        style:
                                            const TextStyle(fontSize: 11.5))),
                                Text(
                                  '${(shares[i].$2 / (poolAll <= 0 ? 1 : poolAll) * 100).round()}%',
                                  key: ValueKey(
                                      'i-stats-legend-${shares[i].$1}'),
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 近 6 月合计支出柱
        Container(
          padding: const EdgeInsets.all(16),
          decoration: context.cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('近 6 月合计支出（购入 + 二次付费 − 残值）',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              SizedBox(
                height: 96,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final (key, v) in months)
                      Expanded(
                        child: GestureDetector(
                          key: ValueKey('i-stats-bar-$key'),
                          onTap: () => AppToast.show(
                              context,
                              '${int.parse(key.split('-')[1])}月 购入/付费明细：'
                              '${v.abs() < 0.005 ? '无' : '${fmtY(v.roundToDouble())}（跳转记账当月流水）'}'),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                  v.abs() < 0.005 ? '' : fmtY(v.roundToDouble()),
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: v.abs() < 0.005
                                          ? kItemMuted
                                          : scheme.primary)),
                              const SizedBox(height: 2),
                              Container(
                                width: double.infinity,
                                height: v.abs() < 0.005
                                    ? 3
                                    : math
                                        .max(8.0, v.abs() / (maxM <= 0 ? 1 : maxM) * 64),
                                decoration: BoxDecoration(
                                  gradient: v.abs() < 0.005
                                      ? null
                                      : context.tokens.gradient,
                                  color: v.abs() < 0.005
                                      ? scheme.surfaceContainerHighest
                                      : null,
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(8)),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text('${int.parse(key.split('-')[1])}月',
                                  style: const TextStyle(
                                      fontSize: 9, color: kItemMuted)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              const Text('点柱可钻取当月流水（联动记账 L4 报表口径）',
                  style: TextStyle(fontSize: 10, color: kItemMuted)),
            ],
          ),
        ),
      ],
    );
  }

  /// 今日持有成本分享卡（原型 scData('stats') 同构：大数字+三格+Top5+分类占比）。
  ShareCardModel _shareStatsCard(ItemsData d, DateTime now) {
    final bill = d.active;
    final total = totalDailyCost(bill, now);
    final poolAll = d.items.fold<double>(0, (s, x) => s + poolOf(x));
    final top = [...bill]
      ..sort(
          (a, b) => (costPerDay(b, now) ?? 0).compareTo(costPerDay(a, now) ?? 0));
    final shares = [...catPoolShare(d)]
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return ShareCardModel(
      file: '物品价值统计',
      eyebrow: 'LifeHarness · 物品价值',
      title: '今日持有成本',
      line: '计费中 ${bill.length} 件 · 已归档决算 ${d.items.length - bill.length} 件',
      big: '¥ ${total.toStringAsFixed(2)}',
      unit: '/天',
      tiles: [
        ShareCardTile('本月花掉', fmtY((total * 30).roundToDouble())),
        ShareCardTile('成本池', fmtY(poolAll.roundToDouble())),
        ShareCardTile('件均日均',
            bill.isEmpty ? '¥0.00' : '¥${(total / bill.length).toStringAsFixed(2)}'),
      ],
      sections: [
        ShareCardSection(
          head: '日均成本 Top 5',
          rows: [
            for (final x in top.take(5))
              ShareCardRow(
                  x.name, '¥${(costPerDay(x, now) ?? 0).toStringAsFixed(2)}/天'),
          ],
        ),
        ShareCardSection(
          head: '分类占比 · 按成本池',
          rows: [
            for (final s in shares)
              ShareCardRow(
                  s.$1, '${(s.$2 / (poolAll <= 0 ? 1 : poolAll) * 100).round()}%'),
          ],
        ),
      ],
    );
  }

  Widget _grid3(String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(fontSize: 9, color: kItemMuted)),
          ],
        ),
      ),
    );
  }
}

/// 分类占比甜甜圈（原型 stDonut SVG stroke-dasharray 语义 → sweep 弧段）。
class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.fractions,
    required this.colors,
    required this.trackColor,
  });

  final List<double> fractions;
  final List<Color> colors;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 5;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..color = trackColor;
    canvas.drawCircle(c, r, track);
    if (fractions.every((f) => f <= 0)) return;
    final rect = Rect.fromCircle(center: c, radius: r);
    var start = -math.pi / 2;
    for (var i = 0; i < fractions.length; i++) {
      final f = fractions[i];
      if (f <= 0) continue;
      final sweep = f * 2 * math.pi;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 11
        ..color = colors[i % colors.length];
      canvas.drawArc(rect, start, sweep, false, p);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.fractions != fractions || old.colors != colors;
}
