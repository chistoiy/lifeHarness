import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/grad_fab.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/ledger_repository.dart';
import '../domain/ledger_calc.dart';
import '../domain/ledger_txn.dart';
import 'ledger_date_sheet.dart';
import 'ledger_hero_cfg_sheet.dart';
import 'ledger_providers.dart';
import 'ledger_sheets.dart';
import 'widgets/ledger_kit.dart';
import 'widgets/ledger_ring.dart';

/// L1 记账主页（原型 p-finance · TITLES ['记账','本地账本 · 全离线']）。
/// hero 顶部卡（账本/月份/大数字/三数据位/预算条/五宫格）+ 到期横幅 + 快速记一笔
/// + 分类占比环 + 流水列表/日历双视图。
class LedgerPage extends ConsumerStatefulWidget {
  const LedgerPage({super.key});

  @override
  ConsumerState<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends ConsumerState<LedgerPage> {
  /// 原型 finView / finCalSel。
  String _view = 'list';
  int? _calSel;

  void _toast(String m) => AppToast.show(context, m);

  void _stepMonth(LedgerRepository repo, int d) {
    ref.read(ledgerMonthProvider.notifier).state =
        monthStep(ref.read(ledgerMonthProvider), d);
    setState(() => _calSel = null);
  }

  Future<void> _pickMonth() async {
    final v = await showLDateSheet(
      context,
      mode: 'month',
      value: ref.read(ledgerMonthProvider),
    );
    if (v != null) {
      ref.read(ledgerMonthProvider.notifier).state = v;
      setState(() => _calSel = null);
    }
  }

  Future<void> _toggleHide(LedgerRepository repo) async {
    final d = ref.read(ledgerDataProvider).valueOrNull;
    if (d == null) return;
    await repo.setHideAmounts(!d.hideAmounts);
    ledgerTouch(ref);
    _toast(d.hideAmounts ? '金额已显示' : '金额已隐藏');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ledgerDataProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('记账'),
            Text(
              '本地账本 · 全离线',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.normal,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: GradFab(
        icon: const Icon(Icons.add, color: Colors.white),
        onTap: () => context.push('/ledger/add'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) => _body(d),
      ),
    );
  }

  Widget _body(LedgerData d) {
    final ctx = d.metricCtx();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
      children: [
        _HeroCard(
          d: d,
          ctx: ctx,
          onBook: () => showLedgerBooksSheet(context),
          onStep: (s) => _stepMonth(ref.read(ledgerRepositoryProvider), s),
          onMonthPick: _pickMonth,
          onHide: () => _toggleHide(ref.read(ledgerRepositoryProvider)),
          onCfg: () => showLedgerHeroCfgSheet(context),
          onOpenAdd: () => context.push('/ledger/add'),
        ),
        if (d.dueRecurN > 0) _DueBanner(n: d.dueRecurN),
        const SizedBox(height: 12),
        _QuickCard(d: d, onPick: (catId) => context.push('/ledger/add?cat=$catId')),
        const SizedBox(height: 12),
        _DonutCard(d: d),
        const SizedBox(height: 16),
        _ListHead(
          view: _view,
          onView: (v) => setState(() => _view = v),
          onSearch: () => ledgerNav(context, 'search'),
        ),
        const SizedBox(height: 8),
        if (_view == 'list')
          _TxList(d: d)
        else
          _CalView(
            d: d,
            sel: _calSel,
            onPick: (day) => setState(() => _calSel = day),
          ),
        if (_view == 'cal' && _calSel != null) ...[
          const SizedBox(height: 12),
          _CalDaySection(d: d, day: _calSel!),
        ],
      ],
    );
  }
}

// ---- hero 顶部卡 ----

class _HeroCard extends ConsumerWidget {
  const _HeroCard({
    required this.d,
    required this.ctx,
    required this.onBook,
    required this.onStep,
    required this.onMonthPick,
    required this.onHide,
    required this.onCfg,
    required this.onOpenAdd,
  });

  final LedgerData d;
  final FinMetricCtx ctx;
  final VoidCallback onBook;
  final ValueChanged<int> onStep;
  final VoidCallback onMonthPick;
  final VoidCallback onHide;
  final VoidCallback onCfg;
  final VoidCallback onOpenAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final st = d.mStatOf;
    final b = d.budget;
    final pct = b.total > 0 ? (st.exp * 100 / b.total).clamp(0, 100) : 0.0;
    final over = b.total > 0 && st.exp > b.total;
    final budgetR = over
        ? '已超支 ${money(st.exp - b.total)}'
        : b.total > 0
        ? '已用 ${pct.round()}% · 日均可用 '
              '${amtText((b.total - st.exp).clamp(0, 1e12) / ctx.leftDays, hide: d.hideAmounts)}'
        : '点击查看';
    Widget wBtn(String label, VoidCallback onTap, {double size = 32}) =>
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        );
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: tokens.gradient,
        boxShadow: [
          BoxShadow(
            color: tokens.g1.withValues(alpha: .2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onBook,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    children: [
                      Text(
                        d.curBook.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const Icon(
                        Icons.expand_more,
                        size: 14,
                        color: Colors.white70,
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              const Text(
                '仅本机存储',
                style: TextStyle(fontSize: 9, color: Colors.white38),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              wBtn('‹', () => onStep(-1)),
              const SizedBox(width: 4),
              Expanded(
                child: Center(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: onMonthPick,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        finLbl(d.month),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onHide,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    LIcons.resolve(d.hideAmounts ? 'eyeoff' : 'eye'),
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              wBtn('›', () => onStep(1)),
            ],
          ),
          InkWell(
            onTap: onCfg,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 12, 2, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    finMetricName(d.heroBig),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    finMetricTxt(d.heroBig, ctx, hide: d.hideAmounts),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final k in d.heroSlots)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: k == d.heroSlots.last ? 0 : 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: onCfg,
                      child: Container(
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
                                fontSize: 9,
                                color: Colors.white70,
                              ),
                            ),
                            Text(
                              finMetricTxt(k, ctx, hide: d.hideAmounts),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          InkWell(
            onTap: () => ledgerNav(context, 'budget'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 14, 2, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: SizedBox(
                      height: 8,
                      child: Stack(
                        children: [
                          Container(color: Colors.white.withValues(alpha: .2)),
                          FractionallySizedBox(
                            widthFactor: pct / 100,
                            child: Container(
                              color: over
                                  ? const Color(0xFFFCA5A5)
                                  : Colors.white.withValues(alpha: .9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '月度预算 ${b.total > 0 ? money(b.total) : '未设置'}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                      Text(
                        budgetR,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final (k, ic, n) in const [
                ('assets', 'pie', '资产'),
                ('budget', 'target', '预算'),
                ('report', 'bars', '报表'),
                ('recur', 'repeat', '周期'),
              ])
                Expanded(
                  child: LFuncBtn(
                    iconKey: ic,
                    label: n,
                    onTap: () => ledgerNav(context, k),
                  ),
                ),
              Expanded(
                child: LFuncBtn(
                  iconKey: 'grid2',
                  label: '更多',
                  onTap: () => showLedgerMoreSheet(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---- 周期到期横幅（renderFinDue） ----

class _DueBanner extends StatelessWidget {
  const _DueBanner({required this.n});

  final int n;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: context.cardDecoration,
      child: Row(
        children: [
          Icon(
            LIcons.resolve('bell'),
            size: 16,
            color: const Color(0xFFF59E0B),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '今日 $n 笔周期账单到期',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
          GestureDetector(
            onTap: () => ledgerNav(context, 'recur'),
            child: Text(
              '去生成 ›',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: context.tokens.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- 快速记一笔四格 ----

class _QuickCard extends StatelessWidget {
  const _QuickCard({required this.d, required this.onPick});

  final LedgerData d;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cats = [
      for (final id in d.quickCats)
        if (d.catById[id] != null) d.catById[id]!,
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '快速记一笔',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                '入口可在记账设置自定义',
                style: TextStyle(
                  fontSize: 9,
                  color: scheme.onSurfaceVariant.withValues(alpha: .8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < cats.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => onPick(cats[i].id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: [
                          LTile(
                            iconKey: cats[i].icon,
                            color: cats[i].color,
                            size: 42,
                            radius: 14,
                            iconSize: 20,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            cats[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              for (var i = cats.length; i < 4; i++)
                const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ),
    );
  }
}

// ---- 分类占比环（环 + top4 图例） ----

class _DonutCard extends ConsumerWidget {
  const _DonutCard({required this.d});

  final LedgerData d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final cs = d.catStatOf;
    final tot = cs.fold<double>(0, (a, e) => a + e.$2);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '分类占比',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => ledgerNav(context, 'report'),
                child: Text(
                  '查看报表 ›',
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              LRing(
                segs: [
                  for (final (id, v) in cs) (d.catOf(id).color, v / (tot > 0 ? tot : 1)),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: cs.isEmpty
                    ? Text(
                        '本月暂无支出流水',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    : Column(
                        children: [
                          for (final (id, v) in cs.take(4))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: lColor(d.catOf(id).color),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      d.catOf(id).name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    amtText(v, hide: d.hideAmounts),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 36,
                                    child: Text(
                                      '${(v * 100 / tot).round()}%',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
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
    );
  }
}

// ---- 流水头部（列表/日历切换 + 搜索） ----

class _ListHead extends StatelessWidget {
  const _ListHead({
    required this.view,
    required this.onView,
    required this.onSearch,
  });

  final String view;
  final ValueChanged<String> onView;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget seg(String v, String label) {
      final on = view == v;
      return GestureDetector(
        onTap: () => onView(v),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: on ? scheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: on
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .06),
                      blurRadius: 3,
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: on ? scheme.onSurface : scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        const Text(
          '流水',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            children: [seg('list', '列表'), seg('cal', '日历')],
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onSearch,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              LIcons.resolve('search'),
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

// ---- 列表视图（按日分组卡片 · 日内 id 倒序） ----

class _TxList extends ConsumerWidget {
  const _TxList({required this.d});

  final LedgerData d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final groups = <String, List<LedgerTxn>>{};
    for (final t in d.monthTxns) {
      (groups[t.date] ??= []).add(t);
    }
    final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    if (days.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 48),
        alignment: Alignment.center,
        child: Text(
          '本月暂无流水，点下方按钮记一笔',
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      );
    }
    return Column(
      children: [
        for (final day in days)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Container(
                decoration: context.cardDecoration,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                      child: Row(
                        children: [
                          Text(
                            '${day.substring(5)} 周${wdOf(day)}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _daySummary(groups[day]!, d.hideAmounts),
                            style: TextStyle(
                              fontSize: 10,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (final t in groups[day]!.reversed)
                      LTxRow(
                        key: ValueKey(t.id),
                        txn: t,
                        onTap: () => context.push('/ledger/tx/${t.id}'),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _daySummary(List<LedgerTxn> ts, bool hide) {
    final (exp: dayExp, inc: dayInc) = dayTotals(ts);
    final parts = <String>[
      if (dayInc > 0) '收 ${amtText(dayInc, hide: hide)}',
      if (dayExp > 0) '支 ${amtText(dayExp, hide: hide)}',
    ];
    return parts.join(' · ');
  }
}

// ---- 日历视图（周日起 · 金额+≤3类点 · 选中日流水段） ----

class _CalView extends ConsumerWidget {
  const _CalView({required this.d, required this.sel, required this.onPick});

  final LedgerData d;
  final int? sel;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final y = int.parse(d.month.substring(0, 4));
    final m = int.parse(d.month.substring(5, 7));
    final last = DateTime(y, m + 1, 0).day;
    final firstWd = DateTime(y, m, 1).weekday % 7; // 周日=0（原型 WD 序）
    final dm = dayMap(d.monthTxns);
    final today = dayKey(DateTime.now());
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: context.cardDecoration,
      child: Column(
        children: [
          Row(
            children: [
              for (final w in wdBrief)
                Expanded(
                  child: Text(
                    w,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var wi = 0; wi * 7 < firstWd + last; wi++)
            Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(
                    child: _calCell(
                      context,
                      wi * 7 + c - firstWd + 1,
                      last,
                      dm,
                      sel,
                      today,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _calCell(
    BuildContext context,
    int day,
    int last,
    Map<int, DayAgg> dm,
    int? sel,
    String today,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    if (day < 1 || day > last) return const AspectRatio(aspectRatio: 1, child: SizedBox());
    final k = day.toString().padLeft(2, '0');
    final v = dm[day];
    final isToday = today == '${d.month}-$k';
    final on = sel == day;
    return GestureDetector(
      onTap: () => onPick(day),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: on ? tokens.accent.withValues(alpha: .08) : null,
          borderRadius: BorderRadius.circular(10),
          border: on ? Border.all(color: tokens.accent) : null,
        ),
        child: Column(
          children: [
            Text(
              '$day',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: isToday ? tokens.accent : scheme.onSurface,
              ),
            ),
            if (v != null && (v.exp > 0 || v.inc > 0)) ...[
              Text(
                v.exp > 0
                    ? amtText(v.exp, hide: d.hideAmounts).replaceFirst('¥', '')
                    : '+${amtText(v.inc, hide: d.hideAmounts).replaceFirst('¥', '')}',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 8,
                  height: 1.2,
                  color: v.exp > 0
                      ? const Color(0xFFFB7185)
                      : const Color(0xFF10B981),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final cid in v.cats.take(3))
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: .5),
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: lColor(d.catOf(cid).color),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ] else
              const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// 日历选中日段（原型 renderFinCal 尾段：日标题 + ＋记一笔 + 当日流水）。
class _CalDaySection extends ConsumerWidget {
  const _CalDaySection({required this.d, required this.day});

  final LedgerData d;
  final int day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final dayK = '${d.month}-${day.toString().padLeft(2, '0')}';
    final ts = d.txns.where((t) => t.date == dayK).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Text(
                '${dayK.substring(5)} 周${wdOf(dayK)} 流水',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.push('/ledger/add?date=$dayK'),
                child: Text(
                  '＋ 记一笔',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: context.tokens.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        if (ts.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            alignment: Alignment.center,
            child: Text(
              '当天暂无流水',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Container(
              decoration: context.cardDecoration,
              child: Column(
                children: [
                  for (final t in ts)
                    LTxRow(
                      key: ValueKey(t.id),
                      txn: t,
                      onTap: () => context.push('/ledger/tx/${t.id}'),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
