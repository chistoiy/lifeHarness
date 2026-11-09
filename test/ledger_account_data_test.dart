import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/domain/ledger_calc.dart';
import 'package:lifeharness/features/ledger/domain/ledger_models.dart';
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';

/// 记账批2c · 账户数据层与口径用例（建/改/删、余额清零守卫、adjust 走统一写路径
/// 只动余额不动收支、归档、净资产三值与信用卡账期纯计算、6 月净资产走势）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late LedgerRepository repo;

  final now = DateTime.now();
  final today = dayKey(now);
  final m = monthKey(now);

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = LedgerRepository(db);
  });
  tearDown(() => db.close());

  Future<int> newAcct({
    String type = LedgerAccount.kDebit,
    required String name,
    double base = 0,
    double? limit,
    int? billDay,
    int? repayDay,
  }) =>
      repo.addAccount(LedgerAccount(
        type: type,
        name: name,
        base: base,
        creditLimit: limit,
        billDay: billDay,
        repayDay: repayDay,
      ));

  group('1 · 账户 CRUD', () {
    test('新建：base 落 balance_cache；种子现金账户仍在', () async {
      final id = await newAcct(name: '银行卡', base: 1000);
      final a = await repo.account(id);
      expect(a!.name, '银行卡');
      expect(a.balanceCache, 1000);
      // 种子：id=1 现金 base 0
      expect((await repo.accounts()).length, 2);
    });

    test('编辑：改名称/类型/图标（color 不动·原型 Object.assign 口径）', () async {
      final id = await newAcct(name: '旧名', base: 500);
      await repo.updateAccount(id, {
        'name': '新名',
        'type': LedgerAccount.kEwallet,
        'icon': 'chat',
      });
      final a = (await repo.account(id))!;
      expect(a.name, '新名');
      expect(a.type, LedgerAccount.kEwallet);
      expect(a.icon, 'chat');
      expect(a.balanceCache, 500); // base 不变
    });

    test('账期读写：bill_day/repay_day 落库并可回读', () async {
      final id = await newAcct(
        type: LedgerAccount.kCredit,
        name: '信用卡',
        base: -300,
        limit: 10000,
        billDay: 5,
        repayDay: 15,
      );
      await repo.updateAccount(id, {'bill_day': 8, 'repay_day': 18});
      final a = (await repo.account(id))!;
      expect(a.billDay, 8);
      expect(a.repayDay, 18);
      expect(a.creditLimit, 10000);
      expect(a.available, 9700);
    });
  });

  group('2 · 归档', () {
    test('归档后 accounts 默认排除，includeArchived 可见', () async {
      final id = await newAcct(name: '停用卡', base: 100);
      await repo.setAccountArchived(id, true);
      expect((await repo.accounts()).any((a) => a.id == id), isFalse);
      final all = await repo.accounts(includeArchived: true);
      expect(all.firstWhere((a) => a.id == id).archived, isTrue);
      // 恢复
      await repo.setAccountArchived(id, false);
      expect((await repo.accounts()).any((a) => a.id == id), isTrue);
    });
  });

  group('3 · 删除守卫（原型 delAccount：仅余额清零可删）', () {
    test('余额未清零 → 拒绝，账户仍在', () async {
      final id = await newAcct(name: '有钱', base: 88);
      final r = await repo.delAccountGuarded(id);
      expect(r.ok, isFalse);
      expect(r.bal, 88);
      expect(await repo.account(id), isNotNull);
    });

    test('转账归零后可硬删；历史流水保留', () async {
      final a = await newAcct(name: '转出户', base: 500);
      final b = await newAcct(name: '转入户', base: 0);
      await repo.addTxn(LedgerTxn(
        kind: LedgerTxn.kTransfer,
        amt: 500,
        accountId: a,
        toAccountId: b,
        date: today,
        bk: 1,
      ));
      expect((await repo.account(a))!.balanceCache, 0);
      final r = await repo.delAccountGuarded(a); // 余额 0，但有引用流水 → 仍删
      expect(r.ok, isTrue);
      expect(await repo.account(a), isNull);
      // 引用流水未被删除（原型 L.accounts.filter 仅摘账户，不动 txns）
      final txns = await repo.acctTxns(b);
      expect(
          txns.any((t) =>
              t.toAccountId == b && t.kind == LedgerTxn.kTransfer),
          isTrue);
    });
  });

  group('4 · adjust 调整余额：走统一写路径·只动余额不动收支', () {
    test('adjustBalance 生成差量流水、balance_cache 更新、mStat 收支不变', () async {
      final id = await newAcct(name: '现金袋', base: 0);
      await repo.addTxn(LedgerTxn(
        kind: LedgerTxn.kExpense,
        amt: 200,
        catId: 101,
        accountId: id,
        date: today,
        bk: 1,
      ));
      // 当前余额 -200；调整为 1000 → 生成 +1200 adjust
      await repo.adjustBalance(id, 1000);
      final a = (await repo.account(id))!;
      expect(a.balanceCache, 1000);
      final txns = await repo.bookTxns(1);
      final adjust =
          txns.where((t) => t.kind == LedgerTxn.kAdjust).toList();
      expect(adjust, hasLength(1));
      expect(adjust.first.amt, 1200);
      expect(adjust.first.note, '余额调整');
      // 收支口径（mStat）：adjust 不计入 → 支出仍 200、收入 0
      final st = mStat(txns);
      expect(st.exp, 200);
      expect(st.inc, 0);
      // 差量 <0.005 不落库（同值调整幂等）
      await repo.adjustBalance(id, 1000);
      expect(await repo.bookTxns(1), hasLength(2)); // 仍 expense + adjust
    });
  });

  group('5 · 纯计算：净资产三值 / 信用卡账期 / 6 月走势', () {
    test('netWorthOf：资产=Σ正、负债=Σ|负|、净=资产−负债', () {
      final nw = netWorthOf([1000.0, -300.0, 0.0, 50.0]);
      expect(nw.assets, 1050);
      expect(nw.liab, 300);
      expect(nw.net, 750);
    });

    test('creditBills：以查看月出账日前一天为界分已出/未出', () {
      // 查看月 2026-09，账单日 10 → 本期 [2026-08-10, 2026-09-09]，未出 (09-09, 09-30]。
      final exp = [
        LedgerTxn(
            kind: LedgerTxn.kExpense,
            amt: 100,
            accountId: 9,
            date: '2026-08-09',
            bk: 1), // 上期，不计
        LedgerTxn(
            kind: LedgerTxn.kExpense,
            amt: 200,
            accountId: 9,
            date: '2026-08-20',
            bk: 1), // 已出
        LedgerTxn(
            kind: LedgerTxn.kExpense,
            amt: 50,
            accountId: 9,
            date: '2026-09-09',
            bk: 1), // 已出（边界=前一天）
        LedgerTxn(
            kind: LedgerTxn.kExpense,
            amt: 80,
            accountId: 9,
            date: '2026-09-25',
            bk: 1), // 未出
      ];
      final r = creditBills(expenses: exp, finMonth: '2026-09', billDay: 10);
      expect(r.billed, 250);
      expect(r.unbilled, 80);
    });

    test('netWorthTrend：6 点、末点=全部账户（含归档）当前净资产', () async {
      final cash = await newAcct(name: '现金', base: 1000);
      final credit = await newAcct(
          type: LedgerAccount.kCredit, name: '信用卡', base: 0, limit: 5000);
      await repo.addTxn(LedgerTxn(
          kind: LedgerTxn.kExpense,
          amt: 400,
          catId: 101,
          accountId: credit,
          date: today,
          bk: 1));
      await newAcct(name: '归档', base: 700);
      await repo.setAccountArchived(
          (await repo.accounts(includeArchived: true))
              .firstWhere((a) => a.name == '归档')
              .id,
          true);
      final trend = await repo.netWorthTrend(endMonth: m);
      expect(trend, hasLength(6));
      expect(trend.last.label, '${int.parse(m.substring(5, 7))}月');
      // 末点=含归档全部账户净资产 = 1000 + (-400) + 700 = 1300
      expect(trend.last.value, closeTo(1300, 0.01));
      expect(cash, isNonZero);
    });
  });
}
