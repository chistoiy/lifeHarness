import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/linkage/item_mounts.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/item_calc.dart';
import '../domain/item_models.dart';
import 'item_edit_page.dart';
import 'items_kit.dart';
import 'items_providers.dart';

/// P7a 物品详情（需求 V1.42 模块9 · 原型 renderItemDetail 3691-3743 对译）。
///
/// 口径：hero 当前日均实算 + 摊薄曲线 CustomPaint + 口径公式行；times 双口径卡；
/// stop 止损卡（stopInfoOf）；三生命周期钮全联动写库（item_mounts）→ itemsTouch
/// → 全页重算；toast 复述前后值；报废两击确认；冻结条目以「查看决算报告」入口卡
/// 替代 hero；时间轴仅追加（HG-D2）；来源徽标在购入行 note 呈现。
class ItemDetailPage extends ConsumerStatefulWidget {
  const ItemDetailPage({super.key, required this.itemId});

  final int itemId;

  @override
  ConsumerState<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends ConsumerState<ItemDetailPage> {

  ItemProfile? _find() {
    final d = ref.read(itemsDataProvider).valueOrNull;
    return d?.items.where((x) => x.id == widget.itemId).firstOrNull;
  }

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
            const Text('物品详情'),
            Text(async.valueOrNull?.items
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
    final billing = it.billing;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        // 头部：图标块 + 名称 + 元信息 + 状态 chip + 编辑档案
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(itemCatIcon(it.category), size: 40),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(it.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(
                    '${it.category} · ${it.buyDate} 购入'
                    '${it.warranty == null ? '' : ' · 保修至 ${it.warranty}'}',
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        key: const ValueKey('i-detail-status-chip'),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: billing
                              ? kItemMint.withValues(alpha: .15)
                              : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '● ${it.status} · ${billing ? '计费中' : '计费已停止'}',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: billing
                                  ? const Color(0xFF0D9488)
                                  : scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const ValueKey('i-detail-edit'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => context.push(
                          '/items/edit', extra: ItemEditArg(origin: it)),
                      child: Text('编辑档案',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: scheme.primary)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (!billing) ...[
          _settleEntryCard(it, now),
        ] else ...[
          _heroCard(it, now),
          if (it.mode == ItemMode.times) _timesCard(it, now),
          if (it.mode == ItemMode.stop) _stopCard(it, now),
          _lifeButtonsRow(),
        ],
        const SizedBox(height: 16),
        _timelineCard(it),
        const SizedBox(height: 12),
        _linkCard(it),
      ],
    );
  }

  /// 冻结条目：查看决算报告入口卡（替代 hero）。
  Widget _settleEntryCard(ItemProfile it, DateTime now) {
    final s = settleOf(it, now);
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      key: const ValueKey('i-detail-settle'),
      onTap: () => context.push('/items/settle?id=${it.id}'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: context.cardDecoration,
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.receipt_long_outlined, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('查看决算报告',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    '净持有 ${fmtY(s.netHold)} · 真实日均 '
                    '${itemMoney(s.realDaily)}/天 · 已冻结 ›',
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  /// hero：当前日均 + 摊薄曲线 CustomPaint + 口径公式行。
  Widget _heroCard(ItemProfile it, DateTime now) {
    final c = costPerDay(it, now) ?? 0;
    final pool = poolOf(it);
    final modeLabel = switch (it.mode) {
      ItemMode.times => '按次×近30天频次折算',
      ItemMode.stop => '直线基线 · 附止损预估',
      ItemMode.day => '直线法',
    };
    final divisor = it.mode == ItemMode.times
        ? '${(it.planUnits ?? 0).toStringAsFixed(0)} ${it.unit}'
        : '${daysHeld(it.buyDate, now)} 天';
    return Container(
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
                    Text('当前日均成本（$modeLabel）',
                        style: const TextStyle(
                            fontSize: 11, color: kItemMuted)),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(itemMoney(c),
                            key: const ValueKey('i-detail-cost'),
                            style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: kItemMint)),
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
                '持有 ${daysHeld(it.buyDate, now)} 天\n成本池 ${fmtY(pool)}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 11, height: 1.6, color: kItemMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            width: double.infinity,
            child: CustomPaint(
              key: const ValueKey('i-detail-curve'),
              painter: _DilutionCurvePainter(
                  tokens: context.tokens, todayCost: itemMoney(c)),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '购入价 ${fmtY(it.price)} ＋ 二次付费 ${fmtY(extraSum(it))} － 回收残值 '
            '${fmtY(recycleSum(it))} ＝ 成本池 ÷ $divisor · '
            '${it.mode == ItemMode.times ? '每次摊薄，用得越多摊得越快' : '每天自动摊薄'}',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 10, height: 1.5, color: kItemMuted),
          ),
        ],
      ),
    );
  }

  /// times 双口径卡。
  Widget _timesCard(ItemProfile it, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    final plan = it.planUnits ?? 0;
    final used = usedTotal(it);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('按次均摊口径',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('每次成本 ＝ 成本池 ÷ 计划 ${(plan).toStringAsFixed(0)} ${it.unit}',
                        style:
                            const TextStyle(fontSize: 11, color: kItemMuted)),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(itemMoney2(perUseCost(it)),
                            key: const ValueKey('i-detail-peruse'),
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: scheme.primary)),
                        Text('/${it.unit}',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: kItemMuted)),
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                '已用 ${used.toStringAsFixed(0)}/${plan.toStringAsFixed(0)}\n'
                '近 30 天 ${usedLast30(it, now).toStringAsFixed(0)} ${it.unit}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 11, height: 1.6, color: kItemMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              key: const ValueKey('i-detail-times-bar'),
              minHeight: 6,
              value:
                  plan <= 0 ? 0 : (used / plan).clamp(0.0, 1.0).toDouble(),
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
              '双口径并列：按次看「用得值不值」，折算日均看「今天背了多少」· 计划次数与单位在档案中可改',
              style: TextStyle(fontSize: 10, color: kItemMuted)),
        ],
      ),
    );
  }

  /// stop 止损卡（数值全走 stopInfoOf 实算）。
  Widget _stopCard(ItemProfile it, DateTime now) {
    final si = stopInfoOf(it, now);
    final scheme = Theme.of(context).colorScheme;
    final warn = si.near;
    final netPct = it.price <= 0 ? 0.0 : (si.net / it.price).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('预估止损',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '直线折旧净值（预期 ${it.expectedYears ?? 5} 年 · 止损线为购入价 ${it.stopPct}%）',
                        style:
                            const TextStyle(fontSize: 11, color: kItemMuted)),
                    const SizedBox(height: 2),
                    Text(fmtY(si.net.roundToDouble()),
                        key: const ValueKey('i-detail-stop-net'),
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: warn ? kItemSun : kItemMint)),
                  ],
                ),
              ),
              Text(
                '止损线 ${fmtY(si.line.roundToDouble())}\n'
                '预估触线 ${fmtYmd(si.lineDate)}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 11, height: 1.6, color: kItemMuted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            key: const ValueKey('i-detail-stop-bar'),
            builder: (bc, cs) => Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: netPct,
                    backgroundColor: scheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(
                        warn ? kItemSun : kItemMint),
                  ),
                ),
                Positioned(
                  left: (it.stopPct / 100 * cs.maxWidth).clamp(0.0, cs.maxWidth),
                  top: 0,
                  bottom: 0,
                  child: const SizedBox(
                      width: 2, child: ColoredBox(color: kItemPeach)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            si.net < si.line * 1.5
                ? '净值已接近止损线 · 建议尽快回收/转卖，残值将扣减成本池并生成决算'
                : '跌破止损线前择机回收 · 回收/报废均自动生成决算并冻结审计记录',
            style: const TextStyle(fontSize: 10, color: kItemMuted),
          ),
        ],
      ),
    );
  }

  /// 三生命周期钮（计费中条目）。
  Widget _lifeButtonsRow() {
    Widget btn(
            {required Key key,
            required IconData icon,
            required String label,
            required Color bg,
            required Color fg,
            required VoidCallback onTap}) =>
        Expanded(
          child: GestureDetector(
            key: key,
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(icon, size: 20, color: fg),
                  const SizedBox(height: 4),
                  Text(label,
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
                ],
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          btn(
              key: const ValueKey('i-life-extra'),
              icon: Icons.payments_outlined,
              label: '二次付费',
              bg: kItemSun.withValues(alpha: .10),
              fg: const Color(0xFFD97706),
              onTap: _openExtraSheet),
          const SizedBox(width: 12),
          btn(
              key: const ValueKey('i-life-recycle'),
              icon: Icons.recycling_outlined,
              label: '回收/出售',
              bg: kItemMint.withValues(alpha: .10),
              fg: const Color(0xFF0D9488),
              onTap: _openRecycleSheet),
          const SizedBox(width: 12),
          btn(
              key: const ValueKey('i-life-scrap'),
              icon: Icons.delete_outline,
              label: '报废',
              bg: kItemPeach.withValues(alpha: .10),
              fg: kItemPeach,
              onTap: _openScrapSheet),
        ],
      ),
    );
  }

  /// 成本流水时间轴（仅追加，HG-D2）。
  Widget _timelineCard(ItemProfile it) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('成本流水时间轴（审计记录）',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          ItemTimeline(events: it.events),
          const SizedBox(height: 10),
          const Text('时间轴仅追加不删除 · 每次二次付费/回收实时重算日均（联动 L12）',
              style: TextStyle(fontSize: 10, color: kItemMuted)),
        ],
      ),
    );
  }

  /// 关联卡（保修→日子提醒中心 L10；流水徽标说明 L12）。
  Widget _linkCard(ItemProfile it) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('关联（联动 L10/L12/L13）',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (it.warranty != null && it.warranty!.isNotEmpty)
            TextButton(
              key: const ValueKey('i-link-remind'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 6),
                alignment: Alignment.centerLeft,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: _goRemindCenter,
              child: const Text('保修到期提醒：已汇入「日子 · 提醒中心」›',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
            ),
          const Text('购入与养护支出：记账流水带「物品 L12」来源徽标',
              style: TextStyle(fontSize: 11, height: 1.6, color: kItemMuted)),
        ],
      ),
    );
  }

  void _goRemindCenter() {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      // push 压栈保留本页（go 会清空栈 → 返回键直接退出 app · 真机缺陷）。
      router.push('/days/remind');
    } else {
      // 模块外路由未接线（测试/独立壳）：登记差异，不阻塞。
      AppToast.show(context, '保修提醒已汇入提醒中心 · 跳转待路由接线');
    }
  }

  // ==================== 生命周期三弹层（写库全走 item_mounts，全联动重算） ====================

  InputDecoration _inp(String hint) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        hintStyle: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: context.tokens.accent)));
  }

  double? _amt(TextEditingController ctl) =>
      double.tryParse(ctl.text.trim().replaceAll(',', ''));

  Future<void> _openExtraSheet() async {
    final it = _find();
    if (it == null) return;
    final amtCtl = TextEditingController();
    final descCtl = TextEditingController();
    final now = ref.read(itemsClockProvider)();
    final before = costPerDay(it, now) ?? 0;
    await showItemsSheet<void>(
      context,
      title: '记录二次付费',
      builder: (bc) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text.rich(
              TextSpan(
                  text: '维修 / 配件 / 保养等追加支出，计入成本池 · 当前档案：',
                  children: [TextSpan(text: it.name)]),
              style: const TextStyle(fontSize: 11, height: 1.6),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('i-extra-amt'),
              controller: amtCtl,
              keyboardType: TextInputType.number,
              decoration: _inp('金额，如 399'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('i-extra-desc'),
              controller: descCtl,
              decoration: _inp('说明，如 Type-C 扩展坞'),
            ),
            const SizedBox(height: 12),
            // HG-D3 固定预览区：口径预览（功能信息，非教学文案）
            Container(
              key: const ValueKey('i-extra-preview'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kItemSun.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('成本计算方式：\n◉ 摊回全周期 · 日均立即回升\n○ 自本次起重新计算',
                  style: TextStyle(fontSize: 11.5, height: 1.7)),
            ),
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.check_circle_outline, size: 15, color: kItemMint),
                SizedBox(width: 6),
                Expanded(
                    child: Text('同步生成一条记账流水（联动 L12）',
                        style: TextStyle(fontSize: 11))),
              ],
            ),
            const SizedBox(height: 14),
            GradButton(
              key: const ValueKey('i-extra-save'),
              label: '保存',
              onTap: () async {
                final a = _amt(amtCtl);
                if (a == null || a <= 0) {
                  AppToast.show(bc, '先填写二次付费金额');
                  return;
                }
                final desc =
                    descCtl.text.trim().isEmpty ? '维修/配件' : descCtl.text.trim();
                Navigator.pop(bc);
                await itemExtraPay(ref, it, amount: a, desc: desc);
                if (!mounted) return;
                // 全联动重算：写库 → itemsTouch → 页面重建；toast 复述前后值。
                final data =
                    await ref.read(itemsRepositoryProvider).loadAll();
                final after = costPerDay(
                        data.items
                            .where((x) => x.id == it.id)
                            .firstOrNull ??
                            it,
                        ref.read(itemsClockProvider)()) ??
                    before;
                if (!mounted) return;
                itemsTouch(ref);
                AppToast.show(context,
                    '已计入成本池 ✓ 日均 ${itemMoney(before)} → ${itemMoney(after)}');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRecycleSheet() async {
    final it = _find();
    if (it == null) return;
    final amtCtl = TextEditingController();
    bool keep = false; // 默认「已转出」（原型 radio checked=out）
    await showItemsSheet<void>(
      context,
      title: '回收 / 出售',
      builder: (bc) => StatefulBuilder(
        builder: (sc, setSheet) => SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text.rich(
                TextSpan(
                    text: '残值将从总成本中扣减，生成净持有成本决算 · 当前档案：',
                    children: [TextSpan(text: it.name)]),
                style: const TextStyle(fontSize: 11, height: 1.6),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('i-recycle-amt'),
                controller: amtCtl,
                keyboardType: TextInputType.number,
                decoration: _inp('回收金额，如 4200（闲鱼/以旧换新）'),
              ),
              const SizedBox(height: 12),
              _radioRow(
                key: const ValueKey('i-recycle-out'),
                label: '已转出 — 停止计费，立即生成决算单',
                selected: !keep,
                onTap: () => setSheet(() => keep = false),
              ),
              _radioRow(
                key: const ValueKey('i-recycle-keep'),
                label: '残值抵扣后继续留用 — 以新净值继续每日摊薄',
                selected: keep,
                onTap: () => setSheet(() => keep = true),
              ),
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 15, color: kItemMint),
                  SizedBox(width: 6),
                  Expanded(
                      child: Text('生成收入记账流水（联动 L12）',
                          style: TextStyle(fontSize: 11))),
                ],
              ),
              const SizedBox(height: 14),
              GestureDetector(
                key: const ValueKey('i-recycle-save'),
                onTap: () async {
                  final a = _amt(amtCtl);
                  if (a == null || a <= 0) {
                    AppToast.show(sc, '先填写回收金额');
                    return;
                  }
                  Navigator.pop(sc);
                  await itemRecycle(ref, it, amount: a, keep: keep);
                  if (!mounted) return;
                  final data =
                      await ref.read(itemsRepositoryProvider).loadAll();
                  final fresh = data.items
                          .where((x) => x.id == it.id)
                          .firstOrNull ??
                      it;
                  final now2 = ref.read(itemsClockProvider)();
                  if (!mounted) return;
                  itemsTouch(ref);
                  if (keep) {
                    AppToast.show(context,
                        '净值已下调 · 日均重算为 ${itemMoney(costPerDay(fresh, now2) ?? 0)}/天');
                  } else {
                    AppToast.show(
                        context, '决算单已生成 · 净持有 ${fmtY(poolOf(fresh))}');
                    context.push('/items/settle?id=${it.id}');
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: kItemMint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text('生成决算并保存',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _radioRow(
      {required Key key,
      required String label,
      required bool selected,
      required VoidCallback onTap}) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        key: key,
        onTap: onTap,
        child: Row(
          children: [
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 17, color: selected ? tokens.accent : kItemMuted),
            const SizedBox(width: 8),
            Expanded(
                child: Text(label, style: const TextStyle(fontSize: 11.5))),
          ],
        ),
      ),
    );
  }

  Future<void> _openScrapSheet() async {
    final it = _find();
    if (it == null) return;
    await showItemsSheet<void>(
      context,
      title: '报废登记',
      builder: (bc) => _ScrapSheetForm(
        item: it,
        onExec: (reason) async {
          Navigator.pop(bc);
          await itemScrap(ref, it, reason);
          if (!mounted) return;
          itemsTouch(ref);
          AppToast.show(context, '已生成决算报告并归档 · 转入历史库');
          context.push('/items/settle?id=${it.id}');
        },
      ),
    );
  }
}

/// 报废弹层表单：原因 chips + 警示区 + 两击确认钮（HG-D2 scrapArm 同款）。
class _ScrapSheetForm extends StatefulWidget {
  const _ScrapSheetForm({required this.item, required this.onExec});

  final ItemProfile item;
  final Future<void> Function(String reason) onExec;

  @override
  State<_ScrapSheetForm> createState() => _ScrapSheetFormState();
}

class _ScrapSheetFormState extends State<_ScrapSheetForm> {
  static const _reasons = ['损坏', '丢失', '技术淘汰', '其他'];
  String _reason = '损坏';
  bool _armed = false;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('当前档案：${widget.item.name}',
              style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in _reasons)
                PillChip(
                  key: ValueKey('i-scrap-reason-$r'),
                  label: r,
                  selected: _reason == r,
                  onTap: () => setState(() => _reason = r),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kItemPeach.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kItemPeach.withValues(alpha: .30)),
            ),
            child: const Text(
                '报废将停止每日计费并冻结决算报告（总投入 / 总天数 / 最终日均 / 回收率），档案转入历史库。\n'
                '此操作需二次确认，且保留审计记录。',
                style: TextStyle(fontSize: 11.5, height: 1.7)),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            key: const ValueKey('i-scrap-confirm'),
            onTap: () async {
              if (!_armed) {
                setState(() => _armed = true);
                AppToast.show(context, '二次确认：报废不可撤销 · 审计记录将保留');
                return;
              }
              await widget.onExec(_reason);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: kItemPeach,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(_armed ? '再次点击 · 确认冻结决算' : '确认报废',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 摊薄曲线（原型 hero SVG 语义：下降曲线 + 面积渐变 + 今日点，主题 mint）。
class _DilutionCurvePainter extends CustomPainter {
  _DilutionCurvePainter({required this.tokens, required this.todayCost});

  final ThemeTokens tokens;
  final String todayCost;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height * .12)
      ..cubicTo(
          size.width * .13, size.height * .38,
          size.width * .3, size.height * .58,
          size.width * .5, size.height * .72)
      ..cubicTo(
          size.width * .7, size.height * .84,
          size.width * .87, size.height * .9,
          size.width, size.height * .92);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = kItemMint;
    canvas.drawPath(path, stroke);
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              kItemMint.withValues(alpha: .18),
              kItemMint.withValues(alpha: 0)
            ],
          ).createShader(Offset.zero & size));
    final p = Offset(size.width, size.height * .92);
    canvas.drawCircle(p, 4, Paint()..color = kItemMint);
    // 今日点标签（右下角小字，同原型 SVG text 语义）
    final tp = TextPainter(
        text: TextSpan(
            text: '今日 $todayCost',
            style: TextStyle(
                fontSize: 8.5, fontWeight: FontWeight.w700, color: kItemMint)),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(
        canvas,
        Offset(math.max(0, size.width - tp.width),
            size.height * .92 - tp.height - 8));
    final lp = TextPainter(
        text: const TextSpan(
            text: '摊薄曲线',
            style: TextStyle(fontSize: 8.5, color: kItemMuted)),
        textDirection: TextDirection.ltr)
      ..layout();
    lp.paint(canvas, Offset(2, size.height - lp.height - 2));
  }

  @override
  bool shouldRepaint(_DilutionCurvePainter old) =>
      old.todayCost != todayCost || old.tokens != tokens;
}
