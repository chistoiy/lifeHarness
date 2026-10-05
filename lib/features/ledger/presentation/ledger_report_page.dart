import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/ledger_calc.dart';
import '../domain/ledger_txn.dart';
import 'ledger_date_sheet.dart';
import 'ledger_providers.dart';
import 'ledger_sheets.dart';
import 'widgets/ledger_kit.dart';

/// L4 统计报表（原型 p-report · TITLES ['统计报表','趋势 · 分类 · Top']）。
/// 周期 seg（周/月/年/自定义）+ 前后翻期 + 自定义两端日期滚轮；环比；趋势柱/曲线
/// （CustomPaint，堆叠归一+均值虚线+峰值气泡夹取）；收支概览；分类排行双维度+钻取；
/// Top 支出项目；消费洞察四规则。逐元素顺序对照 repSeg→repSum→repBars→repCurve→
/// repOverview→repCats(+repDrillWrap)→repTop→repInsights。
class LedgerReportPage extends ConsumerStatefulWidget {
  const LedgerReportPage({super.key});

  @override
  ConsumerState<LedgerReportPage> createState() => _LedgerReportPageState();
}

class _LedgerReportPageState extends ConsumerState<LedgerReportPage> {
  /// 原型 rep 状态（rep.p / rep.dim / rep.drill / rep.from / rep.to）。
  String _period = 'month';
  String _dim = 'cat';
  String? _drill;
  String? _from;
  String? _to;

  /// 周视图翻期偏移（月/年翻期走共享 finMonth=ledgerMonthProvider）。
  int _weekOff = 0;

  static const _rose = Color(0xFFFB7185);
  static const _emerald = Color(0xFF10B981);
  static const _slate = Color(0xFF94A3B8);

  void _setPeriod(String p) => setState(() {
    _period = p;
    _drill = null;
  });

  void _setDim(String s) => setState(() {
    _dim = s;
    _drill = null;
  });

  /// 前后翻期：周按 7 天平移；月/年步进 finMonth（报表与主页共用同月口径）；
  /// 自定义两端整体平移当前天数跨度。
  void _step(int delta) {
    setState(() {
      _drill = null;
      switch (_period) {
        case 'week':
          _weekOff += delta;
        case 'month':
        case 'year':
          ref.read(ledgerMonthProvider.notifier).state = monthStep(
            ref.read(ledgerMonthProvider),
            delta * (_period == 'year' ? 12 : 1),
          );
        default:
          final r = repRange(
            period: 'custom',
            today: dayKey(DateTime.now()),
            month: ref.read(ledgerMonthProvider),
            from: _from,
            to: _to,
          );
          final span = math.max(1, r.days) * delta;
          _from = shiftDays(r.s, span);
          _to = shiftDays(r.e, span);
      }
    });
  }

  Future<void> _pickRangeEnd({required bool isFrom, required String def}) async {
    final v = await showLDateSheet(
      context,
      mode: 'day',
      value: isFrom ? _from ?? def : _to ?? def,
    );
    if (v != null) {
      setState(() {
        if (isFrom) {
          _from = v;
        } else {
          _to = v;
        }
      });
    }
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
            const Text('统计报表'),
            Text(
              '趋势 · 分类 · Top',
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
        data: (d) => TabularNums(child: _body(d)),
      ),
    );
  }

  Widget _body(LedgerData d) {
    final scheme = Theme.of(context).colorScheme;
    final hide = d.hideAmounts;
    final today = dayKey(DateTime.now());
    final r = repRange(
      period: _period,
      today: today,
      month: d.month,
      from: _from,
      to: _to,
      weekOffset: _weekOff,
    );
    final all = txnsBetween(d.txns, r.s, r.e);
    final st = mStat(all);
    final exp = st.exp, inc = st.inc;
    final days = r.days;
    final cnt = all
        .where((t) =>
            !t.nb &&
            (t.kind == LedgerTxn.kExpense || t.kind == LedgerTxn.kIncome))
        .length;
    LedgerTxn? big;
    for (final t in all) {
      if (t.nb || t.kind != LedgerTxn.kExpense) continue;
      if (big == null || t.amt > big.amt) big = t;
    }
    final (ps, pe) = repPrevWindow(r);
    final prev = mStat(txnsBetween(d.txns, ps, pe));
    final cmp = momPct(exp, prev.exp);
    final bs = repTrend(d.txns, r);
    final bySub = _dim == 'sub';
    final rank = rankAgg(all, bySub: bySub);

    String txName(LedgerTxn t) =>
        t.note.isNotEmpty ? t.note : d.catOf(t.catId).name;
    String rankLabel(String k) {
      final cid = int.tryParse(k.split('|').first);
      final nm = d.catOf(cid).name;
      if (!bySub) return nm;
      final sub = k.split('|').length > 1 ? k.split('|').last : '';
      return '$nm · ${sub.isEmpty ? '未细分' : sub}';
    }

    // 消费洞察（九·补3 四规则，输入=当前区间聚合值）。
    final insights = spendingInsights(
      cur: st,
      prevExp: prev.exp,
      topRank: rank.isEmpty ? null : (rankLabel(rank.first.$1), rank.first.$2),
      totalExp: exp,
      budgetTotal: d.budget.total,
      biggest: big == null ? null : (txName(big), big.amt),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        // repSeg：周 / 月 / 年 / 自定义
        _pillSeg(
          items: const [
            ('week', '周'),
            ('month', '月'),
            ('year', '年'),
            ('custom', '自定义'),
          ],
          on: _period,
          fontSize: 11,
          flex: true,
          onSelect: _setPeriod,
        ),
        // 前后翻期 + 当前周期标签
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              _stepBtn('‹', () => _step(-1)),
              Expanded(
                child: Center(
                  child: Text(
                    r.label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              _stepBtn('›', () => _step(1)),
            ],
          ),
        ),
        // repCustom：自定义区间两端日期滚轮（U-1：仅日期两端）
        if (_period == 'custom')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                LChip(
                  label: '起 ${(_from ?? r.s).substring(5)}',
                  onTap: () => _pickRangeEnd(isFrom: true, def: r.s),
                ),
                const SizedBox(width: 8),
                LChip(
                  label: '止 ${(_to ?? r.e).substring(5)}',
                  onTap: () => _pickRangeEnd(isFrom: false, def: r.e),
                ),
              ],
            ),
          ),
        // repSum：区间汇总 + 环比上期 + 导出
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${r.label} · 日均支出 ${amtText(days > 0 ? exp / days : 0, hide: hide)}',
                style: const TextStyle(fontSize: 10, color: _slate),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _bigCell('支出', amtText(exp, hide: hide), _rose),
                  const SizedBox(width: 20),
                  _bigCell('收入', amtText(inc, hide: hide), _emerald),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        '环比上期',
                        style: TextStyle(fontSize: 10, color: _slate),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${cmp > 0 ? '↑' : '↓'} ${cmp.abs().toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: cmp > 0 ? _rose : _emerald,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '共 $cnt 笔',
                    style: const TextStyle(fontSize: 10, color: _slate),
                  ),
                  if (big != null) ...[
                    const SizedBox(width: 16),
                    Flexible(
                      child: Text(
                        '最大单笔 ${txName(big)} ${amtText(big.amt, hide: hide)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: _slate),
                      ),
                    ),
                  ],
                  const Spacer(),
                  GestureDetector(
                    onTap: () => ledgerNav(context, 'export'),
                    child: Text(
                      '导出 ›',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: context.tokens.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // repBars：收支趋势柱（按 max(支出+收入) 堆叠归一，九·补3）
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cardTitle('收支趋势'),
              const SizedBox(height: 12),
              SizedBox(
                height: 132,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final b in bs)
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 14,
                              height: (b.inc / mxOf(bs) * 106)
                                  .round()
                                  .clamp(0, 106)
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
                              width: 14,
                              height: (b.exp / mxOf(bs) * 106)
                                  .round()
                                  .clamp(0, 106)
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
              SizedBox(
                height: 12,
                child: Row(
                  children: [
                    for (var i = 0; i < bs.length; i++)
                      Expanded(
                        child: Text(
                          i % _xStep(bs.length) == 0 ? bs[i].label : '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 8, color: _slate),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // repCurve：支出趋势曲线（与柱共用同一 buckets；均值虚线 + 峰值气泡夹取）
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _cardTitle('支出趋势曲线'),
                  const Spacer(),
                  Text(
                    bs.length > 1
                        ? '${r.monthlyAvg ? '月均' : '日均'} '
                              '${amtText(exp / bs.length, hide: hide)} · '
                              '峰值 ${bs[_pkOf(bs)].label}'
                        : '',
                    style: const TextStyle(fontSize: 9, color: _slate),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (bs.length < 2)
                const Text(
                  '数据点不足',
                  style: TextStyle(fontSize: 11, color: _slate),
                )
              else
                SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _CurvePainter(
                      pts: [for (final b in bs) (b.label, b.exp)],
                      total: exp,
                      monthlyAvg: r.monthlyAvg,
                      hide: hide,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // repOverview：收支概览（收入/结余/支出三列 + 环比）
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cardTitle('收支概览'),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ovCell('本期收入', amtText(inc, hide: hide), _emerald,
                      _mom(inc, prev.inc)),
                  _ovCell(
                    '本期结余',
                    '${inc - exp < 0 ? '-' : ''}${amtText((inc - exp).abs(), hide: hide)}',
                    context.tokens.accent,
                    '收入 − 支出',
                  ),
                  _ovCell('本期支出', amtText(exp, hide: hide), _rose,
                      prev.exp > 0
                          ? '较上期 ${cmp > 0 ? '↑' : '↓'} ${cmp.abs().toStringAsFixed(0)}%'
                          : '上期无数据'),
                ],
              ),
            ],
          ),
        ),
        // repCats：分类排行双维度（九·补2④）+ 钻取
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _cardTitle('分类排行'),
                  const SizedBox(width: 8),
                  _pillSeg(
                    items: const [('cat', '大类'), ('sub', '小类')],
                    on: _dim,
                    fontSize: 9,
                    padH: 10,
                    padV: 4,
                    onSelect: _setDim,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _drill != null ? '钻取中 · 再点收起' : (bySub ? '按小类' : '按大类'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 9, color: _slate),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (rank.isEmpty)
                const Text(
                  '该区间暂无支出',
                  style: TextStyle(fontSize: 11, color: _slate),
                )
              else
                for (final (k, v) in rank)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      onTap: () => setState(
                        () => _drill = _drill == k ? null : k,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              () {
                                final c = d.catOf(
                                  int.tryParse(k.split('|').first),
                                );
                                return LTile(
                                  iconKey: c.icon,
                                  color: c.color,
                                  size: 24,
                                  radius: 8,
                                  iconSize: 14,
                                );
                              }(),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  rankLabel(k),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Text(
                                exp > 0
                                    ? '${(v / exp * 100).toStringAsFixed(0)}%'
                                    : '0%',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _slate,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                amtText(v, hide: hide),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 32, top: 4),
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
                                  widthFactor: (v / rank.first.$2).clamp(0.0, 1.0),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: lColor(
                                        d.catOf(
                                          int.tryParse(k.split('|').first),
                                        ).color,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
        // repDrillWrap：钻取流水列表（再次点击收起）
        if (_drill != null)
          _drillCard(
            all,
            _drill!,
            bySub,
            rankLabel(_drill!),
          ),
        // repTop：Top 支出项目
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cardTitle('Top 支出项目'),
              const SizedBox(height: 8),
              ...(() {
                final tops =
                    topNotes(all, nameOf: (t) => d.catOf(t.catId).name);
                return tops.isEmpty
                    ? [
                        const Text(
                          '暂无',
                          style: TextStyle(fontSize: 11, color: _slate),
                        ),
                      ]
                    : [
                        for (final (k, v) in tops)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    k,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                Text(
                                  amtText(v, hide: hide),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ];
              })(),
            ],
          ),
        ),
        // repInsights：消费洞察四规则（合理/优秀/注意三档标签）
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cardTitle('消费洞察'),
              const SizedBox(height: 8),
              if (insights.isEmpty)
                const Text(
                  '该区间数据不足',
                  style: TextStyle(fontSize: 11, color: _slate),
                )
              else
                for (final (tg, ic, t, s) in insights)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        LTile(
                          iconKey: ic,
                          color: switch (tg) {
                            '优秀' => '#10B981',
                            '注意' => '#F59E0B',
                            _ => '#6366F1',
                          },
                          size: 28,
                          radius: 10,
                          iconSize: 16,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                s,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: _slate,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: switch (tg) {
                              '优秀' => const Color(0x1F10B981),
                              '注意' => const Color(0x1FF59E0B),
                              _ => const Color(0x1F6366F1),
                            },
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            tg,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: switch (tg) {
                                '优秀' => const Color(0xFF10B981),
                                '注意' => const Color(0xFFF59E0B),
                                _ => const Color(0xFF6366F1),
                              },
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
    );
  }

  // ---- 局部小件 ----

  double mxOf(List<({String label, double exp, double inc})> bs) =>
      bs.fold<double>(1, (a, b) => math.max(a, b.exp + b.inc));

  int _pkOf(List<({String label, double exp, double inc})> bs) {
    var pk = 0;
    for (var i = 0; i < bs.length; i++) {
      if (bs[i].exp > bs[pk].exp) pk = i;
    }
    return pk;
  }

  int _xStep(int n) => n > 14 ? (n / 8).ceil() : 1;

  String _mom(double v, double pv) => pv > 0
      ? '较上期 ${v >= pv ? '↑' : '↓'} ${((v - pv) / pv * 100).abs().toStringAsFixed(0)}%'
      : '上期无数据';

  Widget _card(Widget child) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: context.cardDecoration,
    child: child,
  );

  Widget _cardTitle(String t) => Text(
    t,
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .7),
    ),
  );

  Widget _bigCell(String label, String v, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 10, color: _slate)),
      const SizedBox(height: 2),
      Text(
        v,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    ],
  );

  Widget _ovCell(String label, String v, Color color, String sub) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: _slate)),
        const SizedBox(height: 2),
        Text(
          v,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          sub,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 9, color: _slate),
        ),
      ],
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
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ),
  );

  Widget _pillSeg({
    required List<(String, String)> items,
    required String on,
    required double fontSize,
    double padH = 12,
    double padV = 6,
    bool flex = false,
    required ValueChanged<String> onSelect,
  }) {
    final scheme = Theme.of(context).colorScheme;
    Widget cell(String k, String n) {
      final w = GestureDetector(
        onTap: () => onSelect(k),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: k == on ? scheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: k == on
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .06),
                      blurRadius: 3,
                    ),
                  ]
                : null,
          ),
          child: Text(
            n,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: k == on ? context.tokens.accent : scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
      return flex ? Expanded(child: w) : w;
    }

    return Container(
      padding: EdgeInsets.all(flex ? 4 : 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: flex ? MainAxisSize.max : MainAxisSize.min,
        children: [for (final (k, n) in items) cell(k, n)],
      ),
    );
  }

  Widget _drillCard(
    List<LedgerTxn> all,
    String key,
    bool bySub,
    String title,
  ) {
    final ts = drillTxns(all, key: key, bySub: bySub);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      clipBehavior: Clip.antiAlias,
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$title · ${ts.length} 笔',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _drill = null),
                  child: Text(
                    '收起 ✕',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final t in ts)
            LTxRow(txn: t, onTap: () => context.push('/ledger/tx/${t.id}')),
        ],
      ),
    );
  }
}

/// 支出趋势曲线（原型 V1.35 SVG 逐元素：面积+折线+均值虚线+峰值气泡夹取 [54, W-54]）。
class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.pts,
    required this.total,
    required this.monthlyAvg,
    required this.hide,
  });

  /// (桶标签, 桶支出)——与趋势柱共用同一 buckets 数组。
  final List<(String, double)> pts;
  final double total;
  final bool monthlyAvg;
  final bool hide;

  static const _line = Color(0xFFFB7185);
  static const _grid = Color(0xFF94A3B8);
  static const _h = 120.0, _pad = 12.0, _bottom = 20.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final n = pts.length;
    if (n == 0) return;
    final emx = math.max(1.0, pts.fold<double>(1, (a, p) => math.max(a, p.$2)));
    double px(int i) => n < 2 ? (_pad + (w - 2 * _pad) / 2) : _pad + i * (w - 2 * _pad) / (n - 1);
    double py(double v) => _h - _bottom - (v / emx) * (_h - _bottom - 16);

    final line = Path();
    for (var i = 0; i < n; i++) {
      if (i == 0) {
        line.moveTo(px(i), py(pts[i].$2));
      } else {
        line.lineTo(px(i), py(pts[i].$2));
      }
    }
    final area = Path.from(line)
      ..lineTo(px(n - 1), _h - _bottom)
      ..lineTo(px(0), _h - _bottom)
      ..close();
    canvas.drawPath(area, Paint()..color = const Color(0x1FFB7185));
    canvas.drawPath(
      line,
      Paint()
        ..color = _line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // 均值虚线 = 区间总额 / 桶数（年=月均，其余=日均）
    final avg = total / n;
    final ay = py(math.min(avg, emx));
    final dash = Paint()
      ..color = _grid
      ..strokeWidth = 0.8;
    for (double x = _pad; x < w - _pad; x += 6.0) {
      canvas.drawLine(
          Offset(x, ay), Offset(math.min(x + 3, w - _pad), ay), dash);
    }
    _text(canvas, '${monthlyAvg ? '月均' : '日均'} ${amtText(avg, hide: hide)}',
        size: 7, color: _grid, rightAt: Offset(w - _pad, ay - 3 - 7));

    // 峰值点 + 气泡（x 夹取 [54, W-54] · y 顶部夹取 12）
    var pk = 0;
    for (var i = 0; i < n; i++) {
      if (pts[i].$2 > pts[pk].$2) pk = i;
    }
    canvas.drawCircle(Offset(px(pk), py(pts[pk].$2)), 3, Paint()..color = _line);
    final bx = px(pk).clamp(54.0, math.max(54.0, w - 54)).toDouble();
    final byTop = math.max(py(pts[pk].$2) - 16.0, 12.0) - 11;
    final rect = Rect.fromLTWH(bx - 54, byTop, 108, 16);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()..color = _line,
    );
    _text(
      canvas,
      '${pts[pk].$1} · ${amtText(pts[pk].$2, hide: hide)}',
      size: 8,
      color: Colors.white,
      bold: true,
      centerAt: Offset(bx, rect.center.dy - 4),
    );

    // x 轴两端标签
    _text(canvas, pts.first.$1, size: 7, color: _grid,
        at: Offset(_pad, _h - 6 - 7));
    _text(canvas, pts.last.$1, size: 7, color: _grid,
        rightAt: Offset(w - _pad, _h - 6 - 7));
  }

  void _text(
    Canvas canvas,
    String s, {
    required double size,
    required Color color,
    bool bold = false,
    Offset? at,
    Offset? rightAt,
    Offset? centerAt,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final p = at ??
        (rightAt != null
            ? Offset(rightAt.dx - tp.width, rightAt.dy)
            : Offset(centerAt!.dx - tp.width / 2, centerAt.dy));
    tp.paint(canvas, p);
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.pts != pts || old.total != total || old.hide != hide;
}
