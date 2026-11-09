import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';

/// 记账批1a · v17→v18 迁移与建表种子（记账计划 §3/§8）。
/// 独立文件防 isolate 污染（既有踩坑）。
void main() {
  sqfliteFfiInit();

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    await db.execute(
        'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT)');
    for (final sql in DbSchema.migrations[17]!) {
      await db.execute(sql);
    }
  });

  tearDown(() => db.close());

  Future<List<String>> tablesLike(String like) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE ?",
      [like],
    );
    return rows.map((r) => r['name'] as String).toList()..sort();
  }

  group('1 · v18 建表与幂等', () {
    test('migrations[17] 建齐记账全部表', () async {
      final names = await tablesLike('ledger_%');
      expect(
        names,
        containsAll(<String>[
          DbSchema.tLedgerBooks,
          DbSchema.tLedgerTxns,
          DbSchema.tLedgerAccounts,
          DbSchema.tLedgerCategories,
          DbSchema.tLedgerBudgets,
          DbSchema.tLedgerFav,
          DbSchema.tLedgerRecur,
          DbSchema.tLedgerWishes,
          DbSchema.tLedgerDebts,
          DbSchema.tLedgerTagGroups,
          DbSchema.tLedgerTags,
          DbSchema.tLedgerWhos,
          DbSchema.tLedgerMerchants,
          DbSchema.tLedgerImportBatches,
        ]),
      );
    });

    test('迁移可重跑（幂等）', () async {
      for (final sql in DbSchema.migrations[17]!) {
        await db.execute(sql);
      }
      expect(await tablesLike('ledger_%'), hasLength(14));
    });

    test('建库全量段与迁移段同文（ledger 片段的构成一致）', () {
      final inCreate = DbSchema.createStatements
          .skipWhile((s) => !s.contains(DbSchema.tLedgerBooks))
          .toList();
      expect(inCreate, containsAll(DbSchema.migrations[17]!));
      expect(DbSchema.migrations[17]!.length,
          greaterThan(40)); // 14 表+索引+种子整体进入
    });
  });

  group('2 · 种子（原型 LCATS/whos/tagGroups 同序）', () {
    test('支出 14 大类 + 收入 7 大类；兜底分类 id 固定', () async {
      final majors = await db.query(DbSchema.tLedgerCategories,
          where: 'parent_id IS NULL');
      final exp = majors.where((r) => r['kind'] == 'expense').toList();
      final inc = majors.where((r) => r['kind'] == 'income').toList();
      expect(exp, hasLength(14));
      expect(inc, hasLength(7));
      final ids = majors.map((r) => r['id'] as int).toSet();
      expect(
          ids, containsAll([DbSchema.ledgerCatOtherExpense, DbSchema.ledgerCatOtherIncome]));
    });

    test('子分类种子（餐饮 6 子；订阅含自动续费）', () async {
      final subs = await db.query(DbSchema.tLedgerCategories,
          where: 'parent_id = 101');
      expect(subs, hasLength(6));
      final names = subs.map((r) => r['name'] as String).toList();
      expect(names, ['早餐', '午餐', '晚餐', '饮品', '外卖', '零食']);
      final sub = await db.query(DbSchema.tLedgerCategories,
          where: "parent_id = 113 AND name = '自动续费'");
      expect(sub, hasLength(1));
      // id 规则：大类*10+序。
      expect(sub.first['id'], 1133);
    });

    test('默认账本/现金账户/角色/标签分组种子齐', () async {
      expect(await db.query(DbSchema.tLedgerBooks), hasLength(1));
      final accts = await db.query(DbSchema.tLedgerAccounts);
      expect(accts, hasLength(1));
      expect(accts.first['name'], '现金');
      final whos = await db.query(DbSchema.tLedgerWhos,
          orderBy: 'sort ASC');
      expect(whos.map((r) => r['name']),
          ['自己', '家人', '伴侣', '同事', '朋友', '代付']);
      expect(whos.first['is_default'], 1);
      expect(await db.query(DbSchema.tLedgerTagGroups), hasLength(2));
      expect(await db.query(DbSchema.tLedgerTags), hasLength(8));
    });

    test('种子重复执行不复活用户已删数据（INSERT OR IGNORE 按 id 兜底）',
        () async {
      await db.delete(DbSchema.tLedgerBooks, where: 'id = 1', whereArgs: []);
      await db.insert(DbSchema.tLedgerBooks,
          {'id': 1, 'name': '我的账本', 'sort': 1, 'created_at': 1});
      for (final sql in DbSchema.migrations[17]!) {
        await db.execute(sql);
      }
      final rows = await db.query(DbSchema.tLedgerBooks);
      expect(rows.single['name'], '我的账本');
    });
  });

  test('3 · bill_hash UNIQUE 索引兜底去重', () async {
    final base = {
      'kind': 'expense',
      'amt': 10.0,
      'account_id': 1,
      'date': '2026-09-01',
      'bk': 1,
      'created_at': 1,
    };
    await db.insert(DbSchema.tLedgerTxns, {...base, 'bill_hash': 'H1'});
    expect(
      () => db.insert(DbSchema.tLedgerTxns, {...base, 'bill_hash': 'H1'}),
      throwsA(isA<DatabaseException>()),
    );
    // NULL 哈希互不冲突。
    await db.insert(DbSchema.tLedgerTxns, {...base, 'bill_hash': null});
    await db.insert(DbSchema.tLedgerTxns, {...base, 'bill_hash': null});
    final c = await db.rawQuery('SELECT COUNT(*) c FROM ${DbSchema.tLedgerTxns}');
    expect(c.first['c'], 3);
  });
}
