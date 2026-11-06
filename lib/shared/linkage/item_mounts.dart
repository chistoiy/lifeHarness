import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_log.dart';
import '../../features/items/domain/item_models.dart';
import '../../features/items/presentation/items_providers.dart';
import '../../features/ledger/domain/ledger_txn.dart';
import '../../features/ledger/presentation/ledger_providers.dart';

/// 物品 ↔ 记账（L12）联动门面（R1 守护：items/ledger 互不 import，
/// 两侧组合动作统一收敛本文件；仿 habit_mounts / ledger_mounts 先例）。
///
/// 真实联动三条：
/// - 手动建档 → 统一写路径落一笔支出流水（source='item'·link_id=物品id·
///   分类=购物·金额=购入价·日期=购入日），流水侧带「物品」来源徽标；
/// - 二次付费 → 追加支出流水（note 带物品名与说明）；
/// - 回收（留用/转出）→ 追加收入流水；报废不生流水（仅冻结决算）；
/// - 「从记账流水升级建档」→ 不新增流水，items repo 直接改挂来源徽标。
///
/// 联动失败（无账户/无账本）静默跳过，不阻塞物品操作（widget 测试零网络零权限）。

/// 建档（含同步支出流水·联动 L12；upgradeTxnId 非空＝升级建档路径：
/// 挂来源徽标、不重复生成流水）。返回新物品 id。
/// ref 收 WidgetRef（habit_mounts 同款签名先例，页面 ref 直通）。
Future<int> itemCreate(
  WidgetRef ref,
  ItemProfile it, {
  int? upgradeTxnId,
  bool syncTxn = true,
}) async {
  final repo = ref.read(itemsRepositoryProvider);
  final id = await repo.addItem(it.copyWith(
      source: upgradeTxnId != null ? 'ledger' : it.source,
      // 升级建档回挂 source_txn_id：来源徽标 + upgradeCandidates 去重依据
      sourceTxnId: upgradeTxnId ?? it.sourceTxnId));
  if (upgradeTxnId != null) {
    await repo.stampTxnUpgrade(upgradeTxnId, id);
    ref.read(ledgerTickProvider.notifier).state++;
  } else if (syncTxn && it.billing) {
    await _pushTxn(ref,
        itemId: id,
        itemName: it.name,
        amount: it.price,
        income: false,
        date: it.buyDate,
        note: '物品建档：${it.name}',
        sub: it.category);
  }
  return id;
}

/// 二次付费：事件 + 支出流水（联动 L12）。
/// 事件行回填 txn_id（迁移 50 起）：删记录时精确找到联动流水同删。
Future<void> itemExtraPay(
  WidgetRef ref,
  ItemProfile it, {
  required double amount,
  required String desc,
}) async {
  final repo = ref.read(itemsRepositoryProvider);
  final evId = await repo.addExtraPay(it.id!, amount, desc);
  final txnId = await _pushTxn(ref,
      itemId: it.id!,
      itemName: it.name,
      amount: amount,
      income: false,
      date: _todayKey(),
      note: '物品养护：${it.name} · $desc');
  if (txnId != null) await repo.backfillEventTxn(evId, txnId);
}

/// 删除二次付费记录（排障批 2026-11-06）：联动流水同删——
/// - 新事件（txn_id 已回填）：按 id 精确删；
/// - 老事件（txn_id=NULL·迁移 50 前）：按「物品链＋同日同额同备注」兜底匹配，
///   匹配不到（无账户环境未生流水/流水已被手动删）只删事件不碰账。
/// 删事件与删流水都失败即抛（调用方 UI 已二次确认，静默吞错会让账实背离）。
Future<void> itemExtraPayDelete(
  WidgetRef ref,
  ItemProfile it,
  ItemEvent e,
) async {
  final repo = ref.read(itemsRepositoryProvider);
  final ledger = ref.read(ledgerRepositoryProvider);
  var txnId = e.txnId;
  if (txnId == null) {
    // 老事件兜底：note = '物品养护：{name} · {desc}'，desc 在 label 里。
    const tag = '二次付费：';
    final desc = e.label.startsWith(tag) ? e.label.substring(tag.length) : '';
    txnId = await ledger.findItemLinkedTxn(
        itemId: it.id!,
        kind: LedgerTxn.kExpense,
        amt: e.amount,
        date: e.date,
        note: '物品养护：${it.name} · $desc');
  }
  if (txnId != null) {
    await ledger.delTxn(txnId); // 连带其退款冲抵行
    ref.read(ledgerTickProvider.notifier).state++;
  }
  await repo.deleteExtraEvent(e.id!);
  ref.read(itemsTickProvider.notifier).state++;
  AppLog.addKey('物品二次付费删除：${it.name} · −${e.amount} · ${e.date}'
      '${txnId != null ? ' · 联动流水 #$txnId 同删' : ' · 无关联流水'}');
}

/// 回收：事件（残值扣减）+ 收入流水；keep=false 转出停计费并冻结决算。
Future<void> itemRecycle(
  WidgetRef ref,
  ItemProfile it, {
  required double amount,
  required bool keep,
}) async {
  final repo = ref.read(itemsRepositoryProvider);
  await repo.recycle(it.id!, amount, keep: keep);
  await _pushTxn(ref,
      itemId: it.id!,
      itemName: it.name,
      amount: amount,
      income: true,
      date: _todayKey(),
      note: keep ? '物品残值抵扣：${it.name}' : '物品回收/出售：${it.name}');
}

/// 报废：仅事件 + 冻结（无流水）。
Future<void> itemScrap(WidgetRef ref, ItemProfile it, String reason) =>
    ref.read(itemsRepositoryProvider).scrap(it.id!, reason);

/// 返回新流水 id；无账户环境（测试/首启）静默跳过返回 null（widget 测试零网络零权限）。
Future<int?> _pushTxn(
  WidgetRef ref, {
  required int itemId,
  required String itemName,
  required double amount,
  required bool income,
  required String date,
  required String note,
  String? sub,
}) async {
  final ledger = ref.read(ledgerRepositoryProvider);
  final accts = await ledger.accounts();
  if (accts.isEmpty) return null; // 无账户环境（测试/首启）静默跳过
  final id = await ledger.addTxn(LedgerTxn(
    kind: income ? LedgerTxn.kIncome : LedgerTxn.kExpense,
    amt: amount,
    catId: income ? null : kLedgerCatShopping,
    sub: sub ?? '',
    accountId: accts.first.id,
    date: date,
    note: note,
    source: LedgerTxn.kSourceItem,
    linkId: '$itemId',
    bk: await ledger.curBookId(),
  ));
  ref.read(ledgerTickProvider.notifier).state++;
  return id;
}

/// 建档/事件同步流水归类「购物」（ledger 种子大类 id 103，同 wishRedeem 先例）。
const int kLedgerCatShopping = 103;

String _todayKey() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
      '${n.day.toString().padLeft(2, '0')}';
}
