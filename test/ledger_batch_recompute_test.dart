import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';

/// 批量生成余额重算治理（2026-11-06 · 查漏补缺第五批）。
/// 要求：批量生成 N 条后余额与既有口径一致；逐条原子语义不变；
/// addTxn 默认行为不变；异常路径由 finally 兜底。独立文件防 isolate 污染。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late LedgerRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = LedgerRepository(db);
    // createStatements 会预置账户/流水，先清空保证 base 与 eff 完全可控。
    await db.delete(DbSchema.tLedgerTxns);
    await db.delete(DbSchema.tLedgerAccounts);
    await db.delete(DbSchema.tLedgerRecur);
    await db.insert(DbSchema.tLedgerAccounts,
        {'id': 1, 'type': 'debit', 'name': '主账户', 'base': 500.0});
    await db.insert(DbSchema.tLedgerAccounts,
        {'id': 2, 'type': 'debit', 'name': '备用', 'base': 100.0});
  });
  tearDown(() => db.close());

  Future<void> seedRecur(String name, double amt, int acct) async {
    await db.insert(DbSchema.tLedgerRecur, {
      'bk': 1,
      'name': name,
      'amt': amt,
      'cat_id': 114,
      'account_id': acct,
      'freq': 'monthly',
      'next_date': '2026-01-01',
      'active': 1,
    });
  }

  Future<double> bal(int id) async {
    final r = await db.query(DbSchema.tLedgerAccounts,
        where: 'id = ?', whereArgs: [id]);
    return (r.single['balance_cache']! as num).toDouble();
  }

  test('批量生成 N 条：余额与既有口径一致、流水数正确', () async {
    await seedRecur('房租', 100, 1);
    await seedRecur('会员', 25.5, 1);
    await seedRecur('备用扣款', 10, 2);

    final n = await repo.genDueRecur(1, '2026-11-06');
    expect(n, 3);

    final txns = await db.query(DbSchema.tLedgerTxns);
    expect(txns, hasLength(3), reason: '三条到期周期各落一笔');
    expect(
        txns.every((r) => r['source'] == LedgerTxn.kSourceRecurring), isTrue);

    // 期望从既有口径推：余额 = base + Σ eff(id)。
    final accts = await db.query(DbSchema.tLedgerAccounts, orderBy: 'id ASC');
    final models = [for (final r in txns) LedgerTxn.fromRow(r)];
    for (final a in accts) {
      final id = a['id']! as int;
      final expected = double.parse((((a['base']! as num).toDouble() +
              models.fold<double>(0, (s, t) => s + t.eff(id))))
          .toStringAsFixed(2));
      expect(await bal(id), expected,
          reason: '账户 $id 批量生成后余额须与既有口径一致');
    }
    expect(await bal(1), 374.5, reason: 'base 500 - 100 - 25.5');
    expect(await bal(2), 90.0, reason: 'base 100 - 10');

    final recurRows = await db.query(DbSchema.tLedgerRecur);
    expect(recurRows, hasLength(3), reason: '逐条原子：周期行不能被吞');
  });

  test('addTxn 默认仍逐条重算（其它调用方语义不变）', () async {
    await repo.addTxn(LedgerTxn(
      id: 0,
      kind: LedgerTxn.kExpense,
      amt: 30,
      catId: 114,
      accountId: 1,
      date: '2026-11-06',
      bk: 1,
    ));
    expect(await bal(1), 470.0, reason: 'base 500 - 30');
  });

  test('批量路径关闭逐条重算且 finally 兜底（防回潮）', () {
    final src = File('lib/features/ledger/data/ledger_repository.dart')
        .readAsStringSync();
    expect(src.contains('recompute: false'), isTrue,
        reason: '批量循环里必须关闭逐条重算，否则退回 O(N²)');
    expect(src.contains('if (recompute) await _recomputeBalances(txn);'),
        isTrue,
        reason: 'addTxn 默认重算开关必须保留，避免其它调用方余额滞后');
    expect(src.contains('} finally {'), isTrue);
    expect(src.contains('await _recomputeBalances(db);'), isTrue,
        reason: 'finally 统一重算：异常路径余额也不许滞后');
  });
}
