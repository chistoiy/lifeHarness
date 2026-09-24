import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../data/ledger_repository.dart';
import '../domain/ledger_calc.dart';
import '../domain/ledger_models.dart';
import '../domain/ledger_txn.dart';

/// 记账模块 providers（仿 habit_providers 范式：写库后 ledgerTick++ 全量重取，
/// 五处联动=列表/合计/预算/环图/余额随快照重建自动刷新）。

final ledgerRepositoryProvider = Provider<LedgerRepository>(
  (ref) => LedgerRepository(AppDatabase.instance.db),
);

final ledgerTickProvider = StateProvider<int>((ref) => 0);

/// 当前查看月份（L1 与顶部卡指标、报表共用；'YYYY-MM'）。
final ledgerMonthProvider =
    StateProvider<String>((ref) => monthKey(DateTime.now()));

/// 一帧记账域数据（L1/L2/弹层共用一次取齐）。
class LedgerData {
  const LedgerData({
    required this.books,
    required this.curBook,
    required this.accounts,
    required this.cats,
    required this.favs,
    required this.txns,
    required this.budget,
    required this.month,
    required this.hideAmounts,
    required this.defAcctId,
    required this.afterSave,
    required this.confirmDel,
    required this.monthStart,
    required this.whoDef,
    required this.quickCats,
    required this.heroBig,
    required this.heroSlots,
    required this.whos,
    required this.tagGroups,
    required this.merchants,
    required this.txnCounts,
    required this.dueRecurN,
  });

  final List<LedgerBook> books;
  final LedgerBook curBook;
  final List<LedgerAccount> accounts;

  /// 全部分类行（大类+子分类混排，UI 侧用 [majors]/[subsOf] 组树）。
  final List<LedgerCat> cats;
  final List<(int, String)> favs;

  /// 当前账本全部流水（date ASC, id ASC）。
  final List<LedgerTxn> txns;

  /// 当前查看月的月预算（bk 隔离）。
  final LedgerBudget budget;
  final String month;

  final bool hideAmounts;
  final int? defAcctId;
  final String afterSave;
  final bool confirmDel;
  final int monthStart;
  final String whoDef;
  final List<int> quickCats;
  final String heroBig;
  final List<String> heroSlots;
  final List<LedgerWho> whos;
  final List<LedgerTagGroup> tagGroups;
  final List<LedgerMerchant> merchants;

  /// 各账本流水数（S7 账本列表用；当前账本即 [txns].length）。
  final Map<int, int> txnCounts;

  /// 今日到期且未生成的周期账单条数（L1 到期横幅）。
  final int dueRecurN;

  int txnsOfBook(int bk) => bk == curBook.id ? txns.length : (txnCounts[bk] ?? 0);

  Map<int, LedgerAccount> get acctById => {for (final a in accounts) a.id: a};
  Map<int, LedgerCat> get catById => {for (final c in cats) c.id: c};

  LedgerAccount? acct(int? id) => id == null ? null : acctById[id];

  /// 大类列表（按 kind；hidden 不进选择器但保留给迁移显示）。
  List<LedgerCat> majors(String kind) =>
      cats.where((c) => c.isMajor && c.kind == kind).toList();

  List<LedgerCat> subsOf(int majorId) =>
      cats.where((c) => c.parentId == majorId).toList();

  /// 分类显示信息（图标键+色+名）；未知 id 回落「其他」灰。
  ({String name, String icon, String color}) catOf(int? id) {
    final c = id == null ? null : catById[id];
    return (
      name: c?.name ?? '其他',
      icon: c?.icon ?? 'dots',
      color: c?.color ?? '#94a3b8',
    );
  }

  List<LedgerTxn> get monthTxns =>
      txns.where((t) => t.date.startsWith(month)).toList();

  MStat get mStatOf => mStat(monthTxns);

  List<(int, double)> get catStatOf => catStat(monthTxns);

  /// 近 30 天流水（chips 高频窗口）。
  List<LedgerTxn> last30() {
    final from = dayKey(DateTime.now().subtract(const Duration(days: 29)));
    return txns.where((t) => t.date.compareTo(from) >= 0).toList();
  }

  /// 顶部卡指标上下文（九·补5：余额=账户 balance_cache 跨账本合并口径）。
  FinMetricCtx metricCtx({String? forMonth, LedgerBudget? budgetFor}) {
    final m = forMonth ?? month;
    return FinMetricCtx.build(
      bookTxns: txns,
      today: dayKey(DateTime.now()),
      month: m,
      budgetTotal: (budgetFor ?? budget).total,
      balances: [for (final a in accounts) if (!a.archived) a.balanceCache],
    );
  }

  bool isFav(int catId, String sub) => favs.contains((catId, sub));
}

final ledgerDataProvider = FutureProvider<LedgerData>((ref) async {
  ref.watch(ledgerTickProvider);
  final month = ref.watch(ledgerMonthProvider);
  final repo = ref.watch(ledgerRepositoryProvider);
  final books = await repo.books();
  final curId = await repo.curBookId();
  final cur = books.firstWhere(
    (b) => b.id == curId,
    orElse: () => books.isEmpty
        ? const LedgerBook(id: 1, name: '日常账本')
        : books.first,
  );
  return LedgerData(
    books: books,
    curBook: cur,
    accounts: await repo.accounts(),
    cats: await repo.cats(),
    favs: await repo.favs(),
    txns: await repo.bookTxns(cur.id),
    budget: await repo.budgetOf(cur.id, month),
    month: month,
    hideAmounts: await repo.hideAmounts(),
    defAcctId: await repo.defAcctId(),
    afterSave: await repo.afterSave(),
    confirmDel: await repo.confirmDel(),
    monthStart: await repo.monthStart(),
    whoDef: await repo.whoDefName(),
    quickCats: await repo.quickCats(),
    heroBig: await repo.heroBig(),
    heroSlots: await repo.heroSlots(),
    whos: await repo.whos(),
    tagGroups: await repo.tagGroups(),
    merchants: await repo.merchants(),
    txnCounts: await repo.bookTxnCounts(),
    dueRecurN: await repo.dueRecurCount(cur.id, dayKey(DateTime.now())),
  );
});

/// 便捷：触发全模块重取（等价原型 finTouch）。
void ledgerTouch(WidgetRef ref) => ref.read(ledgerTickProvider.notifier).state++;
