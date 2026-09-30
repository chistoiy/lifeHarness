import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/share_card.dart';
import '../domain/item_calc.dart';
import '../domain/item_models.dart';
import 'items_kit.dart';
import 'items_providers.dart';

/// P7d 决算报告（需求 V1.42 模块9 · 原型 renderItemSettle 3795-3824 对译）。
///
/// 口径：冻结条目最终决算——六值全走 settleOf 实算（总投入/持有天数/残值回收/
/// 净持有/真实日均/回收率）+ 审计条数；审计时间轴不可删改（HG-D2）；
/// 冻结日＝末条事件日期；分享走 V1.57 长图公共通道（share_card 弹层）。
class ItemSettlePage extends ConsumerStatefulWidget {
  const ItemSettlePage({super.key, required this.itemId});

  final int itemId;

  @override
  ConsumerState<ItemSettlePage> createState() => _ItemSettlePageState();
}

class _ItemSettlePageState extends ConsumerState<ItemSettlePage> {
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
            const Text('决算报告'),
            Text(
                async.valueOrNull?.items
                    .where((x) => x.id == widget.itemId)
                    .firstOrNull
                    ?.name ??
                    '',
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) {
          final it =
              d.items.where((x) => x.id == widget.itemId).firstOrNull;
          if (it == null) {
            return const Center(
                child: Text('档案不存在或已删除',
                    style: TextStyle(fontSize: 12, color: kItemMuted)));
          }
          return _body(it, now);
        },
      ),
    );
  }

  Widget _body(ItemProfile it, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    final s = settleOf(it, now);
    final events = it.events;
    final freezeDate =
        events.isEmpty ? fmtYmd(now) : events.last.date;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        // 冻结卡头
        Container(
          key: const ValueKey('i-settle-head'),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: context.cardDecoration,
          child: Column(
            children: [
              Icon(itemCatIcon(it.category), size: 40, color: kItemMuted),
              const SizedBox(height: 6),
              Text(it.name,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text('${it.status} · ${it.buyDate} 建档 · $freezeDate 冻结',
                  style: const TextStyle(fontSize: 11, color: kItemMuted)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('计费已停止 · 决算为最终口径',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurfaceVariant)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 总投入 / 持有天数 / 残值回收 / 净持有成本 2×2
        Row(
          children: [
            Expanded(
                child: _metricCard('总投入（含二次付费）', fmtY(s.invested), null)),
            const SizedBox(width: 12),
            Expanded(
                child: _metricCard('持有天数', '${s.days} 天', null)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _metricCard('残值回收', fmtY(s.residue), kItemMint)),
            const SizedBox(width: 12),
            Expanded(
                child: _metricCard('净持有成本', fmtY(s.netHold), kItemPeach)),
          ],
        ),
        const SizedBox(height: 12),
        // 真实日均 + 回收率 + 审计条数
        Container(
          padding: const EdgeInsets.all(16),
          decoration: context.cardDecoration,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('真实日均（全周期）',
                        style: TextStyle(fontSize: 11, color: kItemMuted)),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(itemMoney(s.realDaily),
                            key: const ValueKey('i-settle-daily'),
                            style: const TextStyle(
                                fontSize: 28, fontWeight: FontWeight.w800)),
                        const Text('/天',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: kItemMuted)),
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                '回收率 ${s.recoverRate}%\n审计记录 ${s.auditCount} 条',
                textAlign: TextAlign.right,
                key: const ValueKey('i-settle-side'),
                style: const TextStyle(
                    fontSize: 11, height: 1.6, color: kItemMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 审计时间轴（不可删改）
        Container(
          padding: const EdgeInsets.all(16),
          decoration: context.cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('审计时间轴（不可删改）',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              ItemTimeline(events: events),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: GradButton(
                key: const ValueKey('i-settle-share'),
                label: '分享决算卡片',
                icon: Icons.ios_share,
                onTap: () => showShareCardSheet(
                    context, _shareSettleCard(it, now, freezeDate), src: '物品'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                key: const ValueKey('i-settle-back'),
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: const Text('回到档案',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 决算分享卡（原型 scData('settle') 同构：真实日均大数字+三格+决算口径+审计时间轴）。
  ShareCardModel _shareSettleCard(ItemProfile it, DateTime now, String freezeDate) {
    final s = settleOf(it, now);
    final daily = '¥${s.realDaily.toStringAsFixed(2)}/天';
    return ShareCardModel(
      file: '决算-${it.name}',
      eyebrow: 'LifeHarness · 物品决算',
      title: '${it.name} 决算报告',
      line: '${it.status} · ${it.buyDate} 建档 · $freezeDate 冻结',
      big: '¥ ${s.realDaily.toStringAsFixed(2)}',
      unit: '/天',
      tiles: [
        ShareCardTile('总投入', fmtY(s.invested)),
        ShareCardTile('持有', '${s.days} 天'),
        ShareCardTile('净持有', fmtY(s.netHold)),
      ],
      sections: [
        ShareCardSection(head: '决算口径', rows: [
          ShareCardRow('残值回收', fmtY(s.residue)),
          ShareCardRow('回收率', '${s.recoverRate}%'),
          ShareCardRow('真实日均', daily),
        ]),
        ShareCardSection(head: '审计时间轴', rows: [
          for (final e in it.events) ShareCardRow(e.label, e.date),
        ]),
      ],
    );
  }

  Widget _metricCard(String label, String value, Color? valueColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 10, color: kItemMuted)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: valueColor)),
        ],
      ),
    );
  }
}
