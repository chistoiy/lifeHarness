import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/domain/ledger_calc.dart';
import 'package:lifeharness/features/ledger/domain/ledger_models.dart';
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';

/// 记账批3a · L11 借出/借入落库用例（debts 按 bk 隔离；payDebt 记还款走统一
/// addTxn：借出→income/其他收入(207)/「p 还款」、借入→expense/其他支出(114)/
/// 「还 p」、账户=默认账户、paid=min(total,paid+v)、余额联动、v≤0 拒绝；
/// settleDebt 选账户、left>0 补一笔「结清」流水、paid=total、left≤0 不补流水；
/// delDebt 删行不动流水；与 L2 addDebt 同表互认）。独立文件防 isolate 污染。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late LedgerRepository repo;

  final today = dayKey(DateTime.now());

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = LedgerRepository(db);
  });
  tearDown(() => db.close());

  Future<List<Map<String, Object?>>> debtTxns() =>
      db.query(DbSchema.tLedgerTxns, where: "source = 'debt'", orderBy: 'id ASC');

  Future<double> bal(int id) async {
    final a = await db.query(DbSchema.tLedgerAccounts,
        where: 'id = ?', whereArgs: [id], limit: 1);
    return (a.single['balance_cache']! as num).toDouble();
  }

  Future<int> txnCountTotal() =>
      db.query(DbSchema.tLedgerTxns).then((r) => r.length);

  group('1 · debts / addDebt（L2 同表互认 · 九·补1 表带 bk）', () {
    test('addDebt 落 ledger_debts(paid=0)；debts 按 bk 过滤、id 升序', () async {
      final d1 = await repo.addDebt(
          bk: 1, side: LedgerDebt.kLend, person: '张三', total: 1000);
      await repo.addDebt(
          bk: 1, side: LedgerDebt.kBorrow, person: '李四', total: 500, note: '聚餐');
      await repo.addDebt(bk: 2, side: LedgerDebt.kLend, person: '别家', total: 100);
      final l1 = await repo.debts(1);
      expect(l1.map((d) => d.person), ['张三', '李四']);
      expect(l1.first.id, d1);
      expect(l1.first.paid, 0.0);
      expect(l1.first.isLend, isTrue);
      expect(l1.last.isLend, isFalse);
      expect(l1.last.note, '聚餐');
      expect((await repo.debts(2)).single.bk, 2);
    });
  });

  group('2 · payDebt 记还款（income/expense 按 side，账户=默认）', () {
    test('借出收款 → income/其他收入(207)/「p 还款」，paid 回写，余额 +v', () async {
      final id = await repo.addDebt(
          bk: 1, side: LedgerDebt.kLend, person: '张三', total: 1000);
      final ok = await repo.payDebt(id, 300);
      expect(ok, isTrue);
      final t = (await debtTxns()).single;
      expect(t['kind'], LedgerTxn.kIncome);
      expect(t['cat_id'], DbSchema.ledgerCatOtherIncome); // 207
      expect((t['amt']! as num).toDouble(), 300.0);
      expect(t['account_id'], 1); // 默认账户
      expect(t['debt_id'], id);
      expect(t['bk'], 1);
      expect(t['date'], today);
      expect(t['note'], '张三 还款');
      expect((await repo.debtById(id))!.paid, 300.0);
      expect(await bal(1), 300.0); // 收款进账户
    });

    test('借入还款 → expense/其他支出(114)/「还 p」，余额 −v', () async {
      final id = await repo.addDebt(
          bk: 1, side: LedgerDebt.kBorrow, person: '李四', total: 500);
      expect(await repo.payDebt(id, 200), isTrue);
      final t = (await debtTxns()).single;
      expect(t['kind'], LedgerTxn.kExpense);
      expect(t['cat_id'], DbSchema.ledgerCatOtherExpense); // 114
      expect(t['note'], '还 李四');
      expect(t['account_id'], 1);
      expect((await repo.debtById(id))!.paid, 200.0);
      expect(await bal(1), -200.0); // 付款出账户
    });

    test('金额 ≤0 拒绝、不落库；重复记还款累计 paid 但不超 total', () async {
      final id = await repo.addDebt(
          bk: 1, side: LedgerDebt.kLend, person: '张三', total: 1000);
      expect(await repo.payDebt(id, 0), isFalse);
      expect(await repo.payDebt(id, -50), isFalse);
      expect(await debtTxns(), isEmpty);
      await repo.payDebt(id, 400);
      await repo.payDebt(id, 400);
      expect((await repo.debtById(id))!.paid, 800.0);
      expect((await debtTxns()).length, 2);
    });

    test('超额还款 paid 封顶 total（原型 Math.min(total,paid+v)）', () async {
      final id = await repo.addDebt(
          bk: 1, side: LedgerDebt.kBorrow, person: '李四', total: 500);
      await repo.payDebt(id, 800);
      expect((await repo.debtById(id))!.paid, 500.0); // 封顶
      expect((await repo.debtById(id))!.settled, isTrue);
    });

    test('bk 隔离：别家借贷不被本店还款影响', () async {
      final mine = await repo.addDebt(
          bk: 1, side: LedgerDebt.kLend, person: '张三', total: 100);
      final theirs = await repo.addDebt(
          bk: 2, side: LedgerDebt.kLend, person: '别家', total: 100);
      await repo.payDebt(mine, 50);
      expect((await repo.debtById(theirs))!.paid, 0.0);
    });
  });

  group('3 · settleDebt 结清（选账户 + 剩余补一笔 + paid=total）', () {
    test('left>0 → 所选账户生成「结清」流水(金额=left) + paid=total', () async {
      // 另建一账户以证明结清账户=所选（非默认）
      final acct2 = await repo.addAccount(const LedgerAccount(
          type: LedgerAccount.kDebit, name: '储蓄卡', base: 0));
      final id = await repo.addDebt(
          bk: 1, side: LedgerDebt.kLend, person: '张三', total: 1000);
      await repo.payDebt(id, 400); // 已收 400，剩 600
      final ok = await repo.settleDebt(id, accountId: acct2);
      expect(ok, isTrue);
      final flows = await debtTxns();
      expect(flows.length, 2); // 还款 + 结清
      final settle = flows.last;
      expect(settle['kind'], LedgerTxn.kIncome);
      expect(settle['cat_id'], DbSchema.ledgerCatOtherIncome);
      expect((settle['amt']! as num).toDouble(), 600.0); // left
      expect(settle['account_id'], acct2); // 所选账户
      expect(settle['note'], '张三 结清');
      final d = (await repo.debtById(id))!;
      expect(d.paid, 1000.0);
      expect(d.settled, isTrue);
      expect(await bal(acct2), 600.0);
    });

    test('借入结清 → expense「结清 p」，从所选账户付款', () async {
      final acct2 = await repo.addAccount(const LedgerAccount(
          type: LedgerAccount.kCash, name: '现金2', base: 0));
      final id = await repo.addDebt(
          bk: 1, side: LedgerDebt.kBorrow, person: '李四', total: 500);
      await repo.settleDebt(id, accountId: acct2);
      final t = (await debtTxns()).single;
      expect(t['kind'], LedgerTxn.kExpense);
      expect(t['note'], '结清 李四');
      expect((t['amt']! as num).toDouble(), 500.0);
      expect(t['account_id'], acct2);
      expect(await bal(acct2), -500.0);
    });

    test('已结清再点结清 → 不补流水、paid 维持 total', () async {
      final id = await repo.addDebt(
          bk: 1, side: LedgerDebt.kLend, person: '张三', total: 300);
      await repo.settleDebt(id, accountId: 1); // 首次结清 300
      expect((await debtTxns()).length, 1);
      await repo.settleDebt(id, accountId: 1); // 再次（left=0）
      final flows = await debtTxns();
      expect(flows.length, 1); // 不补第二笔
      expect((await repo.debtById(id))!.paid, 300.0);
    });
  });

  group('4 · delDebt 删除', () {
    test('删行不动已生成流水', () async {
      final id = await repo.addDebt(
          bk: 1, side: LedgerDebt.kLend, person: '张三', total: 100);
      await repo.payDebt(id, 40);
      expect(await txnCountTotal(), 1);
      await repo.delDebt(id);
      expect(await repo.debts(1), isEmpty);
      expect(await txnCountTotal(), 1); // 流水保留
    });
  });
}
