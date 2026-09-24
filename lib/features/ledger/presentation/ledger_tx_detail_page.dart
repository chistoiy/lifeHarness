import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/ledger_calc.dart';
import '../domain/ledger_txn.dart';
import 'ledger_providers.dart';
import 'widgets/ledger_kit.dart';

/// L3 流水详情/编辑（原型 p-txDetail · TITLES ['流水详情','']）。
/// 信息卡 + 四操作（编辑/复制/退款[仅未退支出]/删除[confirmDel 双击 2.6s]）。
class LedgerTxDetailPage extends ConsumerStatefulWidget {
  const LedgerTxDetailPage({super.key, required this.txnId});

  final int txnId;

  @override
  ConsumerState<LedgerTxDetailPage> createState() =>
      _LedgerTxDetailPageState();
}

class _LedgerTxDetailPageState extends ConsumerState<LedgerTxDetailPage> {
  /// 原型 _delArm：confirmDel 开时 2.6s 内二次点击才删。
  DateTime? _delArm;

  void _toast(String m) => AppToast.show(context, m);

  Future<void> _del(LedgerTxn t) async {
    final d = ref.read(ledgerDataProvider).valueOrNull;
    if (d != null && d.confirmDel) {
      final now = DateTime.now();
      if (_delArm == null || now.difference(_delArm!) > const Duration(milliseconds: 2600)) {
        _delArm = now;
        _toast('再次点击删除以确认');
        return;
      }
      _delArm = null;
    }
    final repo = ref.read(ledgerRepositoryProvider);
    await repo.delTxn(t.id);
    ledgerTouch(ref);
    if (!mounted) return;
    _toast('已删除该笔流水及其退款');
    context.pop();
  }

  Future<void> _refund(LedgerTxn t) async {
    final repo = ref.read(ledgerRepositoryProvider);
    final id = await repo.refundTxn(t.id, date: dayKey(DateTime.now()));
    ledgerTouch(ref);
    if (!mounted) return;
    if (id == null) {
      _toast('仅未退款的支出可生成退款');
    } else {
      _toast('已生成退款冲抵 · 支出与预算同步扣减');
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ledgerDataProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('流水详情'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) {
          final hits = d.txns.where((x) => x.id == widget.txnId).toList();
          if (hits.isEmpty) {
            // 已删除（或属其它账本）：回落 L1。
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) context.go('/ledger');
            });
            return const SizedBox.shrink();
          }
          return _body(d, hits.first);
        },
      ),
    );
  }

  Widget _body(LedgerData d, LedgerTxn t) {
    final scheme = Theme.of(context).colorScheme;
    final isTr = t.kind == LedgerTxn.kTransfer;
    final cat = switch (t.kind) {
      LedgerTxn.kTransfer => (
          name: '转账',
          icon: 'switch',
          color: '#64748b',
        ),
      LedgerTxn.kRefund => (
          name: '退款',
          icon: 'undo',
          color: '#10b981',
        ),
      LedgerTxn.kAdjust => (
          name: '余额调整',
          icon: 'scale',
          color: '#94a3b8',
        ),
      _ => d.catOf(t.catId),
    };
    final sign = t.kind == LedgerTxn.kExpense
        ? '−'
        : (t.kind == LedgerTxn.kIncome || t.kind == LedgerTxn.kRefund)
        ? '+'
        : t.amt < 0
        ? '−'
        : '+';
    final relHits = t.refundOf == null
        ? const <LedgerTxn>[]
        : d.txns.where((x) => x.id == t.refundOf).toList();
    final rel = relHits.isEmpty ? null : relHits.first;
    final refunds = t.kind == LedgerTxn.kExpense
        ? d.txns.where((x) => x.refundOf == t.id).toList()
        : const <LedgerTxn>[];
    final hide = d.hideAmounts;

    Widget kv(String k, Widget v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              SizedBox(
                width: 76,
                child: Text(
                  k,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ),
              Expanded(child: v),
            ],
          ),
        );
    Widget kvt(String k, String v, {Color? color}) => kv(
          k,
          Text(
            v,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: context.cardDecoration,
          child: Column(
            children: [
              LTile(iconKey: cat.icon, color: cat.color, size: 48, radius: 18, iconSize: 26),
              const SizedBox(height: 8),
              Text(
                cat.name + (t.sub.isNotEmpty ? ' · ${t.sub}' : ''),
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(
                '$sign${amtText(t.amt, hide: hide)}',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.6,
                  color: t.kind == LedgerTxn.kIncome ||
                          t.kind == LedgerTxn.kRefund
                      ? const Color(0xFF10B981)
                      : scheme.onSurface,
                ),
              ),
              if (t.note.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  t.note,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: context.cardDecoration,
          child: Column(
            children: [
              if (isTr) ...[
                kvt('转出', d.acct(t.accountId)?.name ?? '?'),
                kvt('转入', d.acct(t.toAccountId)?.name ?? '?'),
              ] else if (t.kind != LedgerTxn.kAdjust)
                kvt(
                  '账户',
                  '${d.acct(t.accountId)?.name ?? '?'} · '
                  '${amtText(d.acct(t.accountId)?.balanceCache ?? 0, hide: hide)}',
                ),
              kvt('日期', '${t.date} 周${wdOf(t.date)}${t.time != null && t.time!.isNotEmpty ? ' ${t.time}' : ''}'),
              if (t.tags.isNotEmpty)
                kvt('标签', t.tags.map((x) => '#$x').join(' ')),
              if (t.who != null && t.who!.isNotEmpty) kvt('角色', t.who!),
              if (t.merchant != null && t.merchant!.isNotEmpty)
                kvt('商家', t.merchant!),
              if (t.unpaid) kvt('付款状态', '未付款 · 不计入余额'),
              if (t.nb) kvt('收支口径', '不计入收支和预算'),
              if (rel != null)
                kv(
                  '退回至',
                  InkWell(
                    onTap: () => context.push('/ledger/tx/${rel.id}'),
                    child: Text(
                      '${rel.note.isNotEmpty ? rel.note : d.catOf(rel.catId).name} '
                      '${money(rel.amt)} ›',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: context.tokens.accent,
                      ),
                    ),
                  ),
                ),
              if (refunds.isNotEmpty)
                kv(
                  '已退款',
                  InkWell(
                    onTap: () => context.push('/ledger/tx/${refunds.first.id}'),
                    child: Text(
                      '${money(refunds.fold<double>(0, (a, x) => a + x.amt))} ›',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ),
                ),
              if (t.source == LedgerTxn.kSourceRecurring)
                kvt('来源', '周期账单自动生成 · 已同步续费提醒日程'),
              if (t.source == LedgerTxn.kSourceBill)
                kvt('来源', '账单导入 · ${t.note}'),
              if (t.source == LedgerTxn.kSourceWish) kvt('来源', '心愿单兑换'),
              if (t.linkId != null && t.linkId!.isNotEmpty)
                kvt('关联', t.source == LedgerTxn.kSourceItem ? '物品档案 · ${t.linkId}' : t.linkId!),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _ActBtn(
              icon: 'edit',
              label: '编辑',
              onTap: () => context.push('/ledger/add?edit=${t.id}'),
            ),
            const SizedBox(width: 8),
            _ActBtn(
              icon: 'copy',
              label: '复制',
              onTap: () => context.push('/ledger/add?copy=${t.id}'),
            ),
            const SizedBox(width: 8),
            _ActBtn(
              icon: 'undo',
              label: '退款',
              disabled: t.kind != LedgerTxn.kExpense || refunds.isNotEmpty,
              onTap: () => _refund(t),
            ),
            const SizedBox(width: 8),
            _ActBtn(
              icon: 'trash',
              label: '删除',
              danger: true,
              onTap: () => _del(t),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActBtn extends StatelessWidget {
  const _ActBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.disabled = false,
    this.danger = false,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;
  final bool disabled;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = danger
        ? const Color(0xFFFB7185)
        : scheme.onSurface;
    return Expanded(
      child: Opacity(
        opacity: disabled ? .35 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: disabled ? null : onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: context.cardDecoration,
            child: Column(
              children: [
                Icon(LIcons.resolve(icon), size: 20, color: fg),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
