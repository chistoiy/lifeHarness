import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';

/// 记账 P0 防护（2026-11-05 · 查漏补缺第二批）。
/// 独立文件防 isolate 污染；行为断言走真实内存库，不靠源码反推。
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
  });
  tearDown(() => db.close());

  LedgerTxn imported({double amt = 59, String note = '《测试》购书'}) => LedgerTxn(
        id: 0,
        kind: LedgerTxn.kExpense,
        amt: amt,
        catId: 114,
        accountId: 1,
        date: '2026-11-05',
        note: note,
        bk: 1,
        billHash: 'H-001',
        impBatch: 9,
        source: LedgerTxn.kSourceBill,
        createdAt: 1700000000000,
      );

  test('编辑导入流水不抹平溯源列（整包覆写防护）', () async {
    final id = await db.insert(DbSchema.tLedgerTxns, imported().toRow());

    // 模拟编辑页：整包重建 LedgerTxn（溯源字段全丢）→ toRow() 全字段 patch。
    final rebuilt = LedgerTxn(
      id: id,
      kind: LedgerTxn.kExpense,
      amt: 88,
      catId: 114,
      accountId: 1,
      date: '2026-11-05',
      note: '改过的备注',
      bk: 1,
    );
    await repo.editTxn(id, rebuilt.toRow()..remove('id'));

    final row = (await db.query(DbSchema.tLedgerTxns,
            where: 'id = ?', whereArgs: [id]))
        .single;
    expect(row['amt'], 88, reason: '表单字段照常更新，白名单不能误伤业务编辑');
    expect(row['note'], '改过的备注');
    expect(row['bill_hash'], 'H-001',
        reason: '单号丢失会让同一账单被重复导入（UNIQUE 索引失效）');
    expect(row['imp_batch'], 9,
        reason: '批次丢失会让整批撤销按 imp_batch 删不到这行');
    expect(row['source'], LedgerTxn.kSourceBill,
        reason: '来源不得被洗成 manual');
    expect(row['created_at'], 1700000000000,
        reason: '创建时间不得被重置为 0');
  });

  test('编辑后判重仍命中同一单号，撤销批次仍能定位该行', () async {
    final id = await db.insert(DbSchema.tLedgerTxns, imported().toRow());
    final rebuilt = LedgerTxn(
      id: id,
      kind: LedgerTxn.kExpense,
      amt: 60,
      catId: 114,
      accountId: 1,
      date: '2026-11-05',
      bk: 1,
    );
    await repo.editTxn(id, rebuilt.toRow()..remove('id'));

    expect(await repo.billHashExists('H-001'), isTrue,
        reason: '编辑过的导入行仍须参与重复判定');
    final byBatch = await db.query(DbSchema.tLedgerTxns,
        where: 'imp_batch = ?', whereArgs: [9]);
    expect(byBatch, hasLength(1),
        reason: '整批撤销的 where 条件必须仍能命中编辑过的行');
  });

  test('导入确认有 in-flight 锁，连点不会二次落库', () {
    final src = File(
            'lib/features/ledger/presentation/ledger_import_page.dart')
        .readAsStringSync();
    expect(src.contains('if (_saving) return;'), isTrue,
        reason: '缺少重入守卫会让确认钮连点执行两次 commitImport');
    expect(src.contains('setState(() => _saving = true);'), isTrue);
    expect(src.contains('onTap: _saving ? null : _next'), isTrue,
        reason: '提交期间确认钮须禁用，不能只靠逻辑锁');
  });
}
