import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/ledger_repository.dart';
import '../domain/ledger_calc.dart';
import '../domain/ledger_models.dart';
import 'ledger_date_sheet.dart';
import 'ledger_providers.dart';
import 'widgets/ledger_kit.dart';
import 'widgets/ledger_ring.dart';

/// L5 预算中心（原型 p-budget · TITLES ['预算中心','总额与分类预算']；renderBudget 全量）。
/// 月份步进（budMonth 独立于 finMonth）→ 总预算环卡（已用%/超支红态/剩余·日均可用/
/// 设置·修改总预算滚轮）→ 月度结转卡（L17：开关+上月剩余+立即结转）→
/// 分类预算卡（＋添加分类/完成 全类列表、分类滚轮、>100% 红条+「已超支 x」）。
/// 金额滚轮=S5 showLAmountWheel；日均可用天数=monthStart 口径（budLeftDays）。
class LedgerBudgetPage extends ConsumerStatefulWidget {
  const LedgerBudgetPage({super.key});

  @override
  ConsumerState<LedgerBudgetPage> createState() => _LedgerBudgetPageState();
}

class _LedgerBudgetPageState extends ConsumerState<LedgerBudgetPage> {
  /// 原型 budMonth（默认当月）/ budAddMode。
  late String _budMonth = monthKey(DateTime.now());
  bool _addMode = false;

  static const _slate = Color(0xFF94A3B8);
  static const _rose = Color(0xFFF43F5E); // 原型 #f43f5e（超支环/条填充）
  static const _roseTxt = Color(0xFFFB7185); // 原型 text-rose-400（已超支文案）
  static const _ringBase = '#e2e8f0'; // 原型底环 slate-200

  LedgerRepository get _repo => ref.read(ledgerRepositoryProvider);

  void _tick() => ref.read(ledgerTickProvider.notifier).state++;

  void _toast(String m) => AppToast.show(context, m);

  // ---- 写路径（一律当前 bk + tick 失效；等价原型「改 budOf → renderBudget+renderL1」） ----

  Future<void> _editTotal(LedgerData d, LedgerBudget b) async {
    final v = await showLAmountWheel(context, title: '总预算金额', value: b.total);
    if (v == null) return;
    await _repo.setBudgetTotal(d.curBook.id, _budMonth, v);
    _tick();
  }

  Future<void> _toggleCarry(LedgerData d, bool on) async {
    await _repo.setBudgetCarry(d.curBook.id, _budMonth, on);
    _tick();
    _toast(on ? '结转已开启：上月未用完滚入本月' : '结转已关闭');
  }

  Future<void> _carryNow(LedgerData d, LedgerBudget b, double carryAmt) async {
    // 原型：budOf(budMonth).total += Math.round(carryAmt)。
    await _repo.setBudgetTotal(
      d.curBook.id,
      _budMonth,
      b.total + carryAmt.roundToDouble(),
    );
    _tick();
    _toast('已结转 ${money(carryAmt)} 至本月预算');
  }

  Future<void> _editCat(LedgerData d, int catId, String catName, double lim) async {
    final v = await showLAmountWheel(
      context,
      title: '「$catName」分类预算',
      value: lim,
    );
    if (v == null) return;
    // amt<=0 落库即删行（分类预算的「删」= 滚轮回 0）。
    await _repo.setBudgetCat(d.curBook.id, _budMonth, catId, v);
    _tick();
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
            const Text('预算中心'),
            Text(
              '总额与分类预算',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.normal,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: _body,
      ),
    );
  }

  Widget _body(LedgerData d) {
    final prev = monthStep(_budMonth, -1);
    final budA = ref.watch(ledgerBudgetOfMonthProvider(_budMonth));
    final prevA = ref.watch(ledgerBudgetOfMonthProvider(prev));
    if (budA.isLoading || prevA.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (budA.hasError || prevA.hasError) {
      return Center(child: Text('加载失败：${budA.error ?? prevA.error}'));
    }
    final b = budA.valueOrNull ?? LedgerBudget();
    final pb = prevA.valueOrNull ?? LedgerBudget();

    final hide = d.hideAmounts;
    final today = dayKey(DateTime.now());
    final monthTx = d.txns.where((t) => t.date.startsWith(_budMonth));
    final st = mStat(monthTx);
    final pct =
        b.total > 0 ? math.min(100.0, st.exp / b.total * 100) : 0.0;
    final over = b.total > 0 && st.exp > b.total;
    final leftDays = budLeftDays(
      month: _budMonth,
      today: today,
      monthStart: d.monthStart,
    );
    // L17：上月剩余=carryOf(上月总预算, 上月支出)（原型 prevB.total?max(0,total−exp):0）。
    final prevSt = mStat(d.txns.where((t) => t.date.startsWith(prev)));
    final carryAmt = carryOf(prevTotal: pb.total, prevExp: prevSt.exp);
    // 分类预算行：有预算的分类恒在；添加模式展开全部支出大类（原型 budAddMode）。
    final usedMap = {for (final (id, v) in catStat(monthTx)) id: v};
    final rows = [
      for (final c in d.majors(LedgerCat.kExpense))
        if (b.perCat.containsKey(c.id) || _addMode) c,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        // 月份步进（budMonthStep）
        Row(
          children: [
            _stepBtn('‹', () => setState(() => _budMonth = monthStep(_budMonth, -1))),
            Expanded(
              child: Center(
                child: Text(
                  finLbl(_budMonth),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            _stepBtn('›', () => setState(() => _budMonth = monthStep(_budMonth, 1))),
          ],
        ),
        _totalCard(d, b, st.exp, pct, over, leftDays, hide),
        _carryCard(d, b, prev, carryAmt, hide),
        _catCard(d, b, rows, usedMap, hide),
      ],
    );
  }

  // ---- 总预算环卡 ----

  Widget _totalCard(
    LedgerData d,
    LedgerBudget b,
    double exp,
    double pct,
    bool over,
    int leftDays,
    bool hide,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          LRing(
            size: 128,
            segs: b.total > 0
                ? [
                    (over ? '#f43f5e' : '#6366f1', pct / 100),
                    (_ringBase, (100 - pct) / 100),
                  ]
                : const [],
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('已用', style: TextStyle(fontSize: 10, color: _slate)),
                Text(
                  '${pct.round()}%',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: over ? _rose : scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '月度总预算 ${b.total > 0 ? amtText(b.total, hide: hide) : '未设置'}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            over
                ? '已超支 ${money(exp - b.total)} · 建议调整'
                : '剩余 ${amtText(math.max(0, b.total - exp), hide: hide)} · '
                      '日均可用 ${amtText(b.total > 0 ? math.max(0, (b.total - exp) / leftDays) : 0, hide: hide)}',
            style: const TextStyle(fontSize: 10, color: _slate),
          ),
          const SizedBox(height: 12),
          _miniBtn(
            label: b.total > 0 ? '修改总预算' : '设置总预算',
            onTap: () => _editTotal(d, b),
          ),
        ],
      ),
      center: true,
      vPad: 20,
    );
  }

  // ---- 月度结转卡（L17） ----

  Widget _carryCard(
    LedgerData d,
    LedgerBudget b,
    String prev,
    double carryAmt,
    bool hide,
  ) {
    final tokens = context.tokens;
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LIcons.resolve('repeat'), size: 16, color: tokens.accent),
              const SizedBox(width: 6),
              _cardTitle('月度结转'),
              const Spacer(),
              Switch(
                value: b.carry,
                onChanged: (v) => _toggleCarry(d, v),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '上月（${finLbl(prev)}）剩余 ${amtText(carryAmt, hide: hide)}'
            '${b.carry ? ' · 将自动滚入本月预算' : ' · 开启后滚入本月'}',
            style: const TextStyle(fontSize: 10, color: _slate),
          ),
          // 开启且有可结转额 → 一次性「立即结转」把上月剩余并入本月总额（原型口径）。
          if (b.carry && carryAmt > 0) ...[
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _carryNow(d, b, carryAmt),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  '立即结转 +${money(carryAmt)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: tokens.accent,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---- 分类预算卡 ----

  Widget _catCard(
    LedgerData d,
    LedgerBudget b,
    List<LedgerCat> rows,
    Map<int, double> usedMap,
    bool hide,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      clipBehavior: Clip.antiAlias,
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                _cardTitle('分类预算'),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _addMode = !_addMode),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Text(
                      _addMode ? '完成' : '＋ 添加分类',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: tokens.accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                '点击右上角「添加分类」为具体分类设限',
                style: TextStyle(fontSize: 11, color: _slate),
              ),
            )
          else
            for (final c in rows)
              () {
                final lim = b.perCat[c.id] ?? 0;
                final used = usedMap[c.id] ?? 0.0;
                final p = lim > 0 ? math.min(110.0, used / lim * 100) : 0.0;
                final cut = p > 100; // 恰好 100% 不算超支（原型口径）
                return InkWell(
                  onTap: () => _editCat(d, c.id, c.name, lim),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            LTile(
                              iconKey: c.icon,
                              color: c.color,
                              size: 24,
                              radius: 8,
                              iconSize: 14,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                c.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              '${amtText(used, hide: hide)} / '
                              '${lim > 0 ? money(lim) : '未设'}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: _slate,
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 32, top: 6),
                          child: SizedBox(
                            height: 6,
                            child: Container(
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: math.min(100, p) / 100,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: cut ? _rose : lColor(c.color),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (cut)
                          Padding(
                            padding: const EdgeInsets.only(left: 32, top: 4),
                            child: Text(
                              '已超支 ${money(used - lim)}',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: _roseTxt,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }(),
        ],
      ),
    );
  }

  // ---- 局部小件 ----

  Widget _card(Widget child, {bool center = false, double vPad = 14}) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: EdgeInsets.symmetric(horizontal: 16, vertical: vPad),
    decoration: context.cardDecoration,
    child: center
        ? Center(child: child)
        : child,
  );

  Widget _cardTitle(String t) => Text(
    t,
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .7),
    ),
  );

  Widget _stepBtn(String label, VoidCallback onTap) => InkWell(
    borderRadius: BorderRadius.circular(999),
    onTap: onTap,
    child: Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
    ),
  );

  /// .mini-btn（!text-[12px] !py-2 !px-4）：accent 12% 底 + accent 文字。
  Widget _miniBtn({required String label, required VoidCallback onTap}) {
    final tokens = context.tokens;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: tokens.accent.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: tokens.accent,
          ),
        ),
      ),
    );
  }
}
