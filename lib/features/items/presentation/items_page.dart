import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/grad_fab.dart';
import '../../../shared/linkage/linkage_events.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/items_repository.dart';
import '../domain/item_calc.dart';
import '../domain/item_models.dart';
import '../domain/items_csv.dart';
import '../domain/items_filter.dart';
import 'item_edit_page.dart';
import 'items_kit.dart';
import 'items_providers.dart';

/// P7 物品价值主页（需求 V1.42 模块9 · 原型 renderItems 3664-3690 对译）。
///
/// 口径：深色 hero 控制盘（HG-G1：今日合计大数字实算 + 四状态计数 + 本月 Top3 +
/// 成本统计入口）/ 分类 seg 胶囊行（计数徽标）/ 两入口（录入新物品=全屏表单
/// HG-H1、从记账流水升级=候选弹层点选预填）/ 列表行进度条按日均相对最大实算。
class ItemsPage extends ConsumerStatefulWidget {
  const ItemsPage({super.key});

  @override
  ConsumerState<ItemsPage> createState() => _ItemsPageState();
}

class _ItemsPageState extends ConsumerState<ItemsPage> {
  String _cat = '全部';

  /// 搜索 / 状态·价位筛选 / 排序（I02＋I04）；空值＝不限，默认日均↓。
  ItemFilter _filter = ItemFilter.empty;
  final TextEditingController _qCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 仪表盘 FAB「记物品」→ 本页自动展开建档表单（跨页经事件总线，守 R1）。
    ref.read(eventBusProvider).on<QuickAddEvent>().listen((e) {
      if (!mounted || e.target != 'items') return;
      context.push('/items/edit');
    });
  }


  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  /// I09：物品档案导出 CSV。生成走纯函数 [itemsToCsv]，出口用系统剪贴板
  /// （禁引新依赖：不落文件、不接分享插件），可粘贴到表格/对账单。
  Future<void> _exportCsv() async {
    final d = await ref.read(itemsRepositoryProvider).loadAll();
    final csv = itemsToCsv(d.items, ref.read(itemsClockProvider)());
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    AppToast.show(context,
        '已复制 ${d.items.length} 件档案 CSV · 含品牌/序列号/备注与成本池净值');
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(itemsClockProvider)();
    final async = ref.watch(itemsDataProvider);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('物品价值'),
            Text('每日摊薄 · 止损预估 · 决算归档',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.normal,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          // I09：物品档案导出 CSV（纯函数生成 + 系统剪贴板，禁引新依赖）。
          IconButton(
            key: const ValueKey('i-export-csv'),
            tooltip: '导出 CSV',
            icon: const Icon(Icons.download_outlined, size: 20),
            onPressed: _exportCsv,
          ),
        ],
      ),
      floatingActionButton: GradFab(
        key: const ValueKey('i-fab'),
        icon: const Icon(Icons.add, color: Colors.white, size: 26),
        tooltip: '录入新物品',
        onTap: () => context.push('/items/edit'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) => _body(d, now),
      ),
    );
  }

  Widget _body(ItemsData d, DateTime now) {
    final bill = d.active;
    final total = totalDailyCost(bill, now);
    int cnt(String p) => d.items.where((x) => x.status.startsWith(p)).length;
    final top = [...bill]
      ..sort((a, b) =>
          (costPerDay(b, now) ?? 0).compareTo(costPerDay(a, now) ?? 0));
    final top3 = top.take(3).toList();
    final catList = itemsByCat(d, _cat);
    // 三道闸＋排序只作用在列表上；hero 与 seg 计数始终按全量（筛选不改口径）。
    final list = filterItems(catList, _filter, now);
    final maxC =
        bill.isEmpty ? 0.0 : bill.map((x) => costPerDay(x, now) ?? 0).reduce(
            (a, b) => a > b ? a : b);
    final hist = _cat == '历史（决算）';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
      children: [
        _hero(total, cnt, top3, now),
        const SizedBox(height: 12),
        _searchRow(),
        const SizedBox(height: 12),
        _segRow(bill, d.items.length - bill.length),
        const SizedBox(height: 12),
        _entryRow(),
        const SizedBox(height: 12),
        if (list.isEmpty)
          _emptyHint(hasFilter: _filter.hasQuery || _filter.activeCount > 0)
        else
          for (final it in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _itemRow(it, maxC, now, hist),
            ),
      ],
    );
  }

/// 搜索框 + 筛选入口（原型 p-items：hero 之下、分类胶囊之上）。
  Widget _searchRow() {
    final tokens = context.tokens;
    final n = _filter.activeCount;
    final onSurface = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: tokens.cardBorder.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, size: 15, color: kItemMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const ValueKey('i-search'),
                    controller: _qCtrl,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: '搜名称 / 品牌 / 序列号 / 状态',
                      hintStyle: TextStyle(
                          fontSize: 12.5,
                          color: kItemMuted,
                          fontWeight: FontWeight.w600),
                    ),
                    onChanged: (v) => setState(() =>
                        _filter = _filter.copyWith(
                            keyword: normalizeItemKeyword(v))),
                  ),
                ),
                if (_filter.hasQuery)
                  GestureDetector(
                    key: const ValueKey('i-search-clear'),
                    onTap: () {
                      _qCtrl.clear();
                      setState(() => _filter = _filter.copyWith(keyword: ''));
                    },
                    child: Text('清除',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: tokens.accent)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          key: const ValueKey('i-filter-btn'),
          onTap: _openFilterSheet,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: n > 0 ? tokens.accent.withValues(alpha: .10) : tokens.card,
              border: Border.all(
                  color: n > 0 ? tokens.accent : tokens.cardBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.tune,
                    size: 14, color: n > 0 ? tokens.accent : kItemMuted),
                const SizedBox(width: 5),
                Text('筛选',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: n > 0 ? tokens.accent : onSurface)),
                if (n > 0)
                  Container(
                    key: const ValueKey('i-filter-badge'),
                    margin: const EdgeInsets.only(left: 5),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        color: tokens.accent,
                        borderRadius: BorderRadius.circular(999)),
                    child: Text('$n',
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 筛选与排序弹层（草稿态：改动只在点「应用」后落到列表，与原型同口径）。
  Future<void> _openFilterSheet() async {
    final tokens = context.tokens;
    final onSurface = Theme.of(context).colorScheme.onSurfaceVariant;
    var draft = _filter;

    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(t,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        );

    Widget pill(String text, bool on, VoidCallback tap, {Key? key}) =>
        GestureDetector(
          key: key,
          onTap: tap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: on ? tokens.accent : tokens.cardBorder,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(text,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: on ? Colors.white : kItemMuted)),
          ),
        );

    final r = await showModalBottomSheet<ItemFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bc) => StatefulBuilder(
        builder: (bc, setSheet) {
          final n = draft.activeCount;
          return Container(
            decoration: BoxDecoration(
                color: tokens.card,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24))),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                          color: tokens.cardBorder,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('筛选与排序',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  const Text('条件作用在分类胶囊之后的列表上 · 顶部合计不受影响',
                      style: TextStyle(fontSize: 10.5, color: kItemMuted)),
                  label('状态'),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final s in kItemFilterStatuses)
                        pill(
                          s,
                          draft.statuses.contains(s),
                          () => setSheet(() {
                            final set = {...draft.statuses};
                            set.contains(s) ? set.remove(s) : set.add(s);
                            draft = draft.copyWith(statuses: set);
                          }),
                          key: ValueKey('i-fst-$s'),
                        ),
                    ],
                  ),
                  label('成本池价位'),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final b in ItemPoolBand.values)
                        pill(
                          b.label,
                          draft.band == b,
                          () => setSheet(
                              () => draft = draft.copyWith(band: b)),
                          key: ValueKey('i-fband-${b.name}'),
                        ),
                    ],
                  ),
                  label('排序'),
                  Container(
                    decoration: BoxDecoration(
                        border: Border.all(color: tokens.cardBorder),
                        borderRadius: BorderRadius.circular(14)),
                    child: Column(
                      children: [
                        for (var i = 0; i < ItemSort.values.length; i++)
                          Builder(builder: (_) {
                            final s = ItemSort.values[i];
                            final on = draft.sort == s;
                            return InkWell(
                              key: ValueKey('i-fsort-${s.name}'),
                              onTap: () =>
                                  setSheet(() => draft = draft.copyWith(sort: s)),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 11),
                                decoration: BoxDecoration(
                                  color: on
                                      ? tokens.accent.withValues(alpha: .08)
                                      : null,
                                  border: i == 0
                                      ? null
                                      : Border(
                                          top: BorderSide(
                                              color: tokens.cardBorder)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(s.label,
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: on
                                                  ? FontWeight.w800
                                                  : FontWeight.w600,
                                              color: on
                                                  ? tokens.accent
                                                  : onSurface)),
                                    ),
                                    Container(
                                      width: 15,
                                      height: 15,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: on
                                              ? tokens.accent
                                              : tokens.cardBorder,
                                          width: on ? 4.5 : 1.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          key: const ValueKey('i-filter-reset'),
                          onPressed: () => setSheet(() => draft =
                              draft.copyWith(
                                  statuses: {},
                                  band: ItemPoolBand.all,
                                  sort: ItemSort.dailyCostDesc)),
                          child: const Text('重置'),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: FilledButton(
                          key: const ValueKey('i-filter-apply'),
                          onPressed: () => Navigator.pop(bc, draft),
                          child: Text(n > 0 ? '应用（$n 个条件）' : '应用'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (r != null && mounted) setState(() => _filter = r);
  }

  /// 空列表提示：无条件走分类空态；有条件时给「清除」出口，不留死胡同。
  Widget _emptyHint({required bool hasFilter}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text(
              hasFilter ? '没有匹配的物品' : '该分类下暂无物品 · 可切换分类或录入新物品',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: kItemMuted),
            ),
            if (hasFilter) ...[
              const SizedBox(height: 10),
              TextButton(
                key: const ValueKey('i-filter-clear-all'),
                onPressed: () {
                  _qCtrl.clear();
                  setState(() => _filter = ItemFilter.empty);
                },
                child: const Text('清除搜索与筛选',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              ),
            ],
          ],
        ),
      );

  /// 深色 hero 控制盘（HG-G1）。
  Widget _hero(
      double total, int Function(String) cnt, List<ItemProfile> top3, DateTime now) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kItemHeroBg,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            bottom: -14,
            child: Icon(Icons.inventory_2_outlined,
                size: 110, color: Colors.white.withValues(alpha: .06)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Text('我的物品 · 今日合计持有成本',
                        style: TextStyle(fontSize: 11, color: kItemMuted)),
                  ),
                  GestureDetector(
                    key: const ValueKey('i-stats-btn'),
                    onTap: () => context.push('/items/stats'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text('成本统计 ›',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('¥ ${total.toStringAsFixed(2)}',
                      key: const ValueKey('i-hero-cost'),
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: kItemMint)),
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Text('/天',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: kItemMuted)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _cntChip('使用中', cnt('使用中')),
                  _cntChip('闲置', cnt('闲置')),
                  _cntChip('已回收', cnt('已回收')),
                  _cntChip('已报废', cnt('已报废')),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '本月它花掉了你：${top3.isEmpty ? '—' : top3.map((x) {
                    final c = (costPerDay(x, now) ?? 0) * 30;
                    return '${x.name.split(' ').first} ${fmtY(c.roundToDouble())}';
                  }).join(' · ')}',
                  style: const TextStyle(
                      fontSize: 11, height: 1.5, color: kItemMuted)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cntChip(String k, int n) => Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Text.rich(
          TextSpan(text: '$k ', children: [
            TextSpan(
                text: '$n',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800)),
          ]),
          style: const TextStyle(fontSize: 11, color: kItemMuted),
        ),
      );

  Widget _segRow(List<ItemProfile> bill, int histCount) {
    final counts = {
      for (final c in itemSegCats.skip(1).take(5))
        c: bill.where((x) => x.category == c).length,
    };
    return SizedBox(
      height: 30,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final c in itemSegCats)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: PillChip(
                key: ValueKey('i-cat-$c'),
                label: c == '全部'
                    ? c
                    : '$c ${c == '历史（决算）' ? histCount : (counts[c] ?? 0)}',
                selected: _cat == c,
                onTap: () => setState(() => _cat = c),
              ),
            ),
        ],
      ),
    );
  }

  Widget _entryRow() {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: EmptyDashRow(
            key: const ValueKey('i-add-item'),
            text: '＋ 录入新物品',
            onTap: () => context.push('/items/edit'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            key: const ValueKey('i-from-ledger'),
            onTap: _openUpgradeSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Center(
                child: Text('从记账流水升级',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurfaceVariant)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 升级候选弹层（原型 sheetAddItem#aiBill tab）：点选 → pop → 全屏表单预填。
  Future<void> _openUpgradeSheet() async {
    final candidates =
        await ref.read(itemsRepositoryProvider).upgradeCandidates();
    if (!mounted) return;
    final picked = await showItemsSheet<LedgerCandidate>(
      context,
      title: '从记账流水升级',
      builder: (bc) => candidates.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('暂无可升级的大额支出流水（≥¥50 · 购物类）',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: kItemMuted)),
            )
          : ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('选择一笔大额支出流水升级为物品档案（联动记账 L3 详情「转为物品」同款）：',
                      style: TextStyle(fontSize: 11, color: kItemMuted)),
                ),
                for (final c in candidates)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      key: ValueKey('i-upgrade-row-${c.txnId}'),
                      onTap: () => Navigator.pop(bc, c),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: context.tokens.card,
                          borderRadius: BorderRadius.circular(16),
                          border:
                              Border.all(color: context.tokens.cardBorder),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: Theme.of(bc)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.receipt_long_outlined,
                                  size: 17),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${c.title} −${fmtY(c.amount)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700)),
                                  Text('${c.date} · ${c.catName ?? '支出'}',
                                      style: const TextStyle(
                                          fontSize: 10, color: kItemMuted)),
                                ],
                              ),
                            ),
                            const MiniBtn(label: '升级建档'),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                const Text('升级后流水挂来源徽标「物品 L12」，购入记录写入成本时间轴且不可删除。',
                    style: TextStyle(fontSize: 10, color: kItemMuted)),
              ],
            ),
    );
    if (picked != null && mounted) {
      context.push('/items/edit', extra: ItemEditArg(prefill: picked));
    }
  }

  Widget _itemRow(ItemProfile it, double maxC, DateTime now, bool hist) {
    final scheme = Theme.of(context).colorScheme;
    final c = costPerDay(it, now);
    final pool = poolOf(it);
    return GestureDetector(
      key: ValueKey('i-item-row-${it.id}'),
      onTap: () => context.push('/items/detail?id=${it.id}'),
      child: Opacity(
        opacity: hist ? .6 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: context.cardDecoration,
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(itemCatIcon(it.category), size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(it.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      hist
                          ? '已归档 · 决算已冻结 · 点看决算单'
                          : '持有 ${daysHeld(it.buyDate, now)} 天 · 成本池 ${fmtY(pool)} · ${it.status}'
                              '${it.mode == ItemMode.times ? ' · 按次 ${itemMoney(perUseCost(it))}/${it.unit}' : ''}'
                              '${it.mode == ItemMode.stop ? ' · 含止损预估' : ''}'
                              '${idleWarn(it) ? ' · 建议回收' : ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 128,
                      height: 4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          key: ValueKey('i-item-bar-${it.id}'),
                          value: hist || maxC <= 0 || c == null
                              ? 1
                              : (c / maxC).clamp(0.0, 1.0),
                          minHeight: 4,
                          backgroundColor: scheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(
                              hist ? kItemMuted : (idleWarn(it) ? kItemSun : kItemMint)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (hist)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('已归档',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurfaceVariant)),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(itemMoney(c ?? 0),
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: kItemMint)),
                    const Text('/天 · 每日摊薄↓',
                        style: TextStyle(fontSize: 9, color: kItemMuted)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
