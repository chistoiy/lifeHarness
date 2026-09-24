import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/ledger_calc.dart';
import '../domain/ledger_models.dart';
import '../domain/ledger_search.dart';
import 'ledger_date_sheet.dart';
import 'ledger_providers.dart';
import 'widgets/ledger_kit.dart';

/// L12 搜索与筛选（原型 p-txSearch 1064~1073 行 + fs/renderFsPanel/fsResults/
/// fsRun/fsReset 5321~5355 行；TITLES ['搜索流水','多条件组合过滤'] 4674 行）。
/// 控件清单逐元素对照原型：关键词输入（备注/商户名·5342 命中备注或分类名）+
/// 重置钮（fsReset 5355）→ 条件卡：金额最低/最高（5326~5329）、分类下拉+账户
/// 下拉（5330~5333，仅列支出大类/全部账户）、日期起止（5334~5337，滚轮 S2）、
/// 标签单选 chips（5338~5339，再点取消）；任一条件变更即时 AND 重过滤（fsRun）。
/// 结果行复用 LTxRow（原型 txRow）点击进 L3；合计行口径见 [ledgerSearchTotals]
/// （fsRun 5352：仅 expense/income 两类求和、**不剔 nb**；隐藏金额开关生效）。
class LedgerSearchPage extends ConsumerStatefulWidget {
  const LedgerSearchPage({super.key});

  @override
  ConsumerState<LedgerSearchPage> createState() => _LedgerSearchPageState();
}

class _LedgerSearchPageState extends ConsumerState<LedgerSearchPage> {
  /// 原型 fs 状态对象（5322 行）逐字段对应。
  final _kw = TextEditingController();
  final _min = TextEditingController();
  final _max = TextEditingController();
  int? _catId;
  int? _acctId;
  String? _tag;
  String? _from;
  String? _to;

  @override
  void dispose() {
    _kw.dispose();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  /// 原型 fsReset（5355）：全条件清空 + 关键词框清空 + 重跑。
  void _reset() {
    setState(() {
      _kw.clear();
      _min.clear();
      _max.clear();
      _catId = null;
      _acctId = null;
      _tag = null;
      _from = null;
      _to = null;
    });
  }

  LedgerSearchQuery _query() => LedgerSearchQuery(
        kw: _kw.text,
        min: double.tryParse(_min.text.trim()),
        max: double.tryParse(_max.text.trim()),
        catId: _catId,
        acctId: _acctId,
        tag: _tag,
        from: _from,
        to: _to,
      );

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(ledgerDataProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('搜索流水'),
            Text(
              '多条件组合过滤',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : _body(d),
    );
  }

  Widget _body(LedgerData d) {
    final results = ledgerSearch(
      txns: d.txns,
      bk: d.curBook.id,
      q: _query(),
      catName: (id) => d.catOf(id).name,
    );
    final tot = ledgerSearchTotals(results);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: [
        _headRow(),
        const SizedBox(height: 12),
        _panelCard(d),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: Text(
            '共 ${tot.n} 条 · 支出 ${amtText(tot.exp, hide: d.hideAmounts)}'
            ' · 收入 ${amtText(tot.inc, hide: d.hideAmounts)}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
        ),
        const SizedBox(height: 4),
        if (results.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text('没有符合条件的流水',
                  style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
            ),
          )
        else
          for (final t in results)
            LTxRow(
              key: ValueKey(t.id),
              txn: t,
              onTap: () => context.push('/ledger/tx/${t.id}'),
            ),
      ],
    );
  }

  // ---- 头部：关键词输入 + 重置（原型 1065~1069 行） ----

  Widget _headRow() {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(LIcons.resolve('search'),
                    size: 16, color: const Color(0xFF94A3B8)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const ValueKey('fsKw'),
                    controller: _kw,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: '备注 / 商户名',
                      hintStyle: TextStyle(fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _reset,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              '重置',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: context.tokens.accent,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---- 条件卡（原型 renderFsPanel 5323~5340：四行控件逐行对应） ----

  Widget _panelCard(LedgerData d) {
    final scheme = Theme.of(context).colorScheme;
    Widget label(String text, {double width = 40, TextAlign? align}) => SizedBox(
          width: width,
          child: Text(text,
              textAlign: align,
              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
        );
    Widget dash() =>
        const Text('—', style: TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)));
    Widget numField(TextEditingController ctl, String hint, String key) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: TextField(
              key: ValueKey(key),
              controller: ctl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 11),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(fontSize: 11),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        );
    Widget dateField(String? value, String hint, ValueChanged<String> onPick) =>
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () async {
              final v = await showLDateSheet(context,
                  mode: 'day', value: value ?? dayKey(DateTime.now()));
              if (v != null) setState(() => onPick(v));
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Text(
                value ?? hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: value == null
                      ? const Color(0xFF94A3B8)
                      : scheme.onSurface,
                ),
              ),
            ),
          ),
        );

    final cats = d.majors(LedgerCat.kExpense).where((c) => !c.hidden).toList();
    final tags = [for (final g in d.tagGroups) ...g.tags];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: context.cardDecoration,
      child: Column(
        children: [
          Row(
            children: [
              label('金额'),
              numField(_min, '最低', 'fsMin'),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: dash()),
              numField(_max, '最高', 'fsMax'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              label('分类'),
              Expanded(
                child: DropdownButton<int>(
                  value: _catId,
                  isExpanded: true,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  items: [
                    const DropdownMenuItem<int>(
                        value: null, child: Text('全部分类', style: TextStyle(fontSize: 11))),
                    for (final c in cats)
                      DropdownMenuItem(
                          value: c.id,
                          child: Text(c.name, style: const TextStyle(fontSize: 11))),
                  ],
                  onChanged: (v) => setState(() => _catId = v),
                ),
              ),
              const SizedBox(width: 8),
              label('账户', align: TextAlign.right),
              Expanded(
                child: DropdownButton<int>(
                  value: _acctId,
                  isExpanded: true,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  items: [
                    const DropdownMenuItem<int>(
                        value: null, child: Text('全部账户', style: TextStyle(fontSize: 11))),
                    for (final a in d.accounts)
                      DropdownMenuItem(
                          value: a.id,
                          child: Text(a.name, style: const TextStyle(fontSize: 11))),
                  ],
                  onChanged: (v) => setState(() => _acctId = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              label('日期'),
              dateField(_from, '开始日期', (v) => _from = v),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: dash()),
              dateField(_to, '结束日期', (v) => _to = v),
            ],
          ),
          const SizedBox(height: 12),
          if (tags.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label('标签'),
                Expanded(
                  child: Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      for (final t in tags)
                        LChip(
                          key: ValueKey('tag-$t'),
                          label: '#$t',
                          small: true,
                          on: _tag == t,
                          onTap: () => setState(
                              () => _tag = _tag == t ? null : t),
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
