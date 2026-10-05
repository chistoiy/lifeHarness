import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/ledger_repository.dart';
import '../domain/ledger_calc.dart';
import '../domain/ledger_models.dart';
import '../domain/ledger_txn.dart';
import 'ledger_assets_page.dart';
import 'ledger_date_sheet.dart';
import 'ledger_providers.dart';
import 'widgets/ledger_kit.dart';

/// L7 账户详情（原型 p-assetAcct · TITLES ['账户详情','']；renderAcctDetail 全量）。
/// 顺序：账户信息卡（图标/名称/大余额 + 调整余额/编辑/归档三钮）→ 信用卡账期模块
/// （已出/未出账单两值 + 出账·还款·额度·可用一行 + 就地内嵌滚轮改账期）→
/// 最近流水（该账户流水前 40 条·txRow·点击进 L3）。
/// 调整余额走 S5 滚轮 + 统一写路径生成差量 adjust；归档后返回 L6。
class LedgerAccountDetailPage extends ConsumerStatefulWidget {
  const LedgerAccountDetailPage({super.key, required this.accountId});

  final int accountId;

  @override
  ConsumerState<LedgerAccountDetailPage> createState() =>
      _LedgerAccountDetailPageState();
}

class _LedgerAccountDetailPageState
    extends ConsumerState<LedgerAccountDetailPage> {
  static const _slate = Color(0xFF94A3B8);
  static const _rose = Color(0xFFFB7185);

  LedgerRepository get _repo => ref.read(ledgerRepositoryProvider);

  void _tick() => ref.read(ledgerTickProvider.notifier).state++;

  Future<void> _adjust(LedgerAccount a) async {
    final v = await showLAmountWheel(
      context,
      title: '调整为',
      value: a.balanceCache,
    );
    if (v == null) return;
    await _repo.adjustBalance(a.id, v);
    _tick();
  }

  Future<void> _archive(LedgerAccount a) async {
    await _repo.setAccountArchived(a.id, true);
    _tick();
    if (mounted) context.pop();
  }

  Future<void> _setDay(int id, {required bool isBill, required int day}) async {
    await _repo.updateAccount(id, {isBill ? 'bill_day' : 'repay_day': day});
    _tick();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ledgerDataProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('账户详情'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) {
          final a = d.acctById[widget.accountId];
          if (a == null) {
            return const Center(
              child: Text('账户不存在', style: TextStyle(fontSize: 12)),
            );
          }
          return TabularNums(child: _body(d, a));
        },
      ),
    );
  }

  Widget _body(LedgerData d, LedgerAccount a) {
    final hide = d.hideAmounts;
    final scheme = Theme.of(context).colorScheme;
    final bal = a.balanceCache;
    final txnsAsync = ref.watch(ledgerAccountTxnsProvider(a.id));
    final all = txnsAsync.valueOrNull ?? const <LedgerTxn>[];
    final recent = all.take(40).toList();
    final expenses = all
        .where((t) => t.kind == LedgerTxn.kExpense && t.accountId == a.id)
        .toList();
    final bills = a.isCredit
        ? creditBills(
            expenses: expenses,
            finMonth: d.month,
            billDay: a.billDay ?? 1,
          )
        : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        // 账户信息卡
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
          decoration: context.cardDecoration,
          child: Column(
            children: [
              LTile(iconKey: a.icon, color: a.color, size: 44, radius: 16),
              const SizedBox(height: 6),
              Text(
                a.name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                amtText(bal, hide: hide),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: bal < 0 ? _rose : scheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _miniBtn(label: '调整余额', onTap: () => _adjust(a)),
                  const SizedBox(width: 8),
                  _miniBtn(label: '编辑', onTap: () => showLAcctForm(context, ref, editing: a)),
                  const SizedBox(width: 8),
                  _miniBtn(label: '归档', onTap: () => _archive(a)),
                ],
              ),
            ],
          ),
        ),
        // 信用卡账期模块
        if (a.isCredit && bills != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _billCard(
                        '已出账单 · ${a.billDay ?? 1}号',
                        amtText(bills.billed, hide: hide),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _billCard('未出账单', amtText(bills.unbilled, hide: hide)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '每月 ${a.billDay ?? 1} 日出账 · ${a.repayDay ?? 1} 日还款 · '
                  '额度 ${money(a.creditLimit ?? 0)} · 可用 ${money((a.creditLimit ?? 0) + bal)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 9, color: _slate),
                ),
                // 就地内嵌滚轮改账期（禁两段式弹层）
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  decoration: context.cardDecoration,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '账期设置',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface.withValues(alpha: .7),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '账单日',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: _slate,
                                  ),
                                ),
                                LInlinePicker(
                                  height: 106,
                                  labels: [
                                    for (var dd = 1; dd <= 28; dd++) '$dd 号',
                                  ],
                                  initialIndex:
                                      ((a.billDay ?? 1) - 1).clamp(0, 27),
                                  onSelect: (i) => _setDay(
                                    a.id,
                                    isBill: true,
                                    day: i + 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '还款日',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: _slate,
                                  ),
                                ),
                                LInlinePicker(
                                  height: 106,
                                  labels: [
                                    for (var dd = 1; dd <= 28; dd++) '$dd 号',
                                  ],
                                  initialIndex:
                                      ((a.repayDay ?? 1) - 1).clamp(0, 27),
                                  onSelect: (i) => _setDay(
                                    a.id,
                                    isBill: false,
                                    day: i + 1,
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
              ],
            ),
          ),
        // 最近流水
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '最近流水',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '仅本机存储',
                style: const TextStyle(fontSize: 9, color: _slate),
              ),
            ],
          ),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: context.cardDecoration,
          child: recent.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      '暂无流水',
                      style: TextStyle(fontSize: 11, color: _slate),
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (final t in recent)
                      LTxRow(
                        txn: t,
                        onTap: () => context.push('/ledger/tx/${t.id}'),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _billCard(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: context.cardDecoration,
    alignment: Alignment.center,
    child: Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: _slate),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );

  Widget _miniBtn({required String label, required VoidCallback onTap}) {
    final tokens = context.tokens;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
