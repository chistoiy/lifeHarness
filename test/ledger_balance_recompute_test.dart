import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';

/// 余额重算复杂度治理（2026-11-05 · 查漏补缺第四批）。
/// 核心要求：只改复杂度，不改一分钱语义。独立文件防 isolate 污染。
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
    // createStatements 会预置若干账户/流水，先清空保证 base 与 eff 完全可控。
    await db.delete(DbSchema.tLedgerTxns);
    await db.delete(DbSchema.tLedgerAccounts);
    for (var i = 1; i <= 3; i++) {
      await db.insert(DbSchema.tLedgerAccounts, {
        'id': i,
        'type': 'debit',
        'name': '账户$i',
        'base': 100.0 * i,
      });
    }
  });
  tearDown(() => db.close());

  LedgerTxn tx({
    required String kind,
    required double amt,
    required int acct,
    int? to,
    bool unpaid = false,
  }) =>
      LedgerTxn(
        id: 0,
        kind: kind,
        amt: amt,
        catId: 114,
        accountId: acct,
        toAccountId: to,
        date: '2026-11-05',
        bk: 1,
        unpaid: unpaid,
      );

  test('单次重算与既有口径逐账户一致（多账户 × 多类型流水）', () async {
    final samples = <LedgerTxn>[
      tx(kind: LedgerTxn.kExpense, amt: 30, acct: 1),
      tx(kind: LedgerTxn.kIncome, amt: 80, acct: 1),
      tx(kind: LedgerTxn.kTransfer, amt: 25, acct: 1, to: 2),
      tx(kind: LedgerTxn.kExpense, amt: 12.5, acct: 2),
      tx(kind: LedgerTxn.kAdjust, amt: 3.75, acct: 3),
      tx(kind: LedgerTxn.kRefund, amt: 9.99, acct: 2),
      tx(kind: LedgerTxn.kExpense, amt: 7, acct: 1, unpaid: true),
      tx(kind: LedgerTxn.kTransfer, amt: 4, acct: 3, to: 3), // 同账户自转
    ];
    for (final t in samples) {
      await db.insert(DbSchema.tLedgerTxns, t.toRow());
    }

    // 期望从既有口径推（余额 = base + Σ eff(id)，按 txns 查询顺序 fold），
    // 不是从新实现反推。
    final accts = await db.query(DbSchema.tLedgerAccounts, orderBy: 'id ASC');
    final rows = await db.query(DbSchema.tLedgerTxns);
    final models = [for (final r in rows) LedgerTxn.fromRow(r)];
    final expected = <int, double>{
      for (final a in accts)
        a['id']! as int: double.parse((((a['base']! as num).toDouble() +
                models.fold<double>(0, (s, t) => s + t.eff(a['id']! as int))))
            .toStringAsFixed(2)),
    };

    // 触发一次写路径重算（delTxn 删 0 行仍走 _recomputeBalances）。
    await repo.delTxn(999999);

    for (final a in accts) {
      final id = a['id']! as int;
      final got = (await db.query(DbSchema.tLedgerAccounts,
              where: 'id = ?', whereArgs: [id]))
          .single['balance_cache'];
      expect((got! as num).toDouble(), expected[id],
          reason: '账户 $id 余额与既有口径不一致：优化不得改动一分钱语义');
    }
  });

  test('新增/编辑/删除后余额仍随写路径同步', () async {
    await repo.addTxn(tx(kind: LedgerTxn.kExpense, amt: 20, acct: 1));
    var bal = (await db.query(DbSchema.tLedgerAccounts,
            where: 'id = ?', whereArgs: [1]))
        .single['balance_cache'] as num;
    expect(bal.toDouble(), 80.0, reason: 'base 100 - 支出 20');

    await repo.addTxn(tx(kind: LedgerTxn.kTransfer, amt: 30, acct: 1, to: 2));
    final a1 = (await db.query(DbSchema.tLedgerAccounts,
            where: 'id = ?', whereArgs: [1]))
        .single['balance_cache'] as num;
    final a2 = (await db.query(DbSchema.tLedgerAccounts,
            where: 'id = ?', whereArgs: [2]))
        .single['balance_cache'] as num;
    expect(a1.toDouble(), 50.0, reason: '转出 30');
    expect(a2.toDouble(), 230.0, reason: 'base 200 + 转入 30');
  });

  test('单次重算不再对每个账户 fold 全表（防回潮）', () {
    final src = File('lib/features/ledger/data/ledger_repository.dart')
        .readAsStringSync();
    expect(src.contains('models.fold<double>'), isFalse,
        reason: '每账户 fold 全表＝O(A×N)，会让每次写入随账户数线性变慢');
    expect(src.contains('sumByAcct'), isTrue);
  });
}
