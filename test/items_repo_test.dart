import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/items/data/items_repository.dart';
import 'package:lifeharness/features/items/domain/item_calc.dart';
import 'package:lifeharness/features/items/domain/item_models.dart';
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';

/// 批2 · 物品仓储：审计时间轴仅追加（HG-D2）+ 生命周期落库 + 升级建档。
///
/// 「events 无改删口」为类型级保证：[ItemsRepository] 公开 API 只有
/// addItem/updateItem/addExtraPay/recycle/scrap/addUsage/upgradeCandidates/
/// stampTxnUpgrade/loadAll——不存在任何针对 item_events 的 update/delete 方法，
/// 时间轴改删在编译期即不可能（反射断言无必要，此注释即口径记录）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ItemsRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    // v21 物品三表在 migrations[20]（createStatements 未含）：测试同 App 升级路径补齐。
    for (final sql in DbSchema.itemSchemaStatements) {
      await db.execute(sql);
    }
    repo = ItemsRepository(db);
  });

  tearDown(() => db.close());

  final sample = const ItemProfile(
      name: 'MacBook Air M3',
      category: '数码',
      buyDate: '2025-03-12',
      price: 9999,
      warranty: '2026-03-12');

  Future<ItemProfile> reload(int id) async =>
      (await repo.loadAll()).items.firstWhere((x) => x.id == id);

  group('建档', () {
    test('addItem 同事务生成「购入」首条审计', () async {
      final id = await repo.addItem(sample);
      final it = await reload(id);
      expect(it.billing, isTrue);
      expect(it.status, kItemStatusActive);
      expect(it.events.length, 1);
      final buy = it.events.single;
      expect(buy.kind, kEvBuy);
      expect(buy.label, '购入');
      expect(buy.amount, 9999);
      expect(buy.date, '2025-03-12');
      expect(buy.note, contains('联动 L12'));
    });

    test('updateItem 不改 events（仅追加保证）', () async {
      final id = await repo.addItem(sample);
      await repo.updateItem(
          (await reload(id)).copyWith(name: 'MacBook Air M3 15寸'));
      final it = await reload(id);
      expect(it.name, 'MacBook Air M3 15寸');
      expect(it.events.length, 1);
    });
  });

  group('二次付费（仅追加 · 成本池实算变化）', () {
    test('addExtraPay 追加事件 → poolOf 上升，档案无 extra 列直写', () async {
      final id = await repo.addItem(sample);
      final before = poolOf(await reload(id));
      await repo.addExtraPay(id, 399, 'Type-C 扩展坞', date: '2025-06-02');
      final it = await reload(id);
      expect(poolOf(it), before + 399);
      expect(it.events.length, 2);
      expect(it.events.last.kind, kEvExtra);
      expect(it.events.last.label, '二次付费：Type-C 扩展坞');
      // 购入首审计原样保留（不可改删）
      expect(it.events.first.kind, kEvBuy);
    });
  });

  group('回收（留用/转出）', () {
    test('keep=true → 状态已回收(抵扣留用) · billing 仍 1', () async {
      final id = await repo.addItem(sample);
      await repo.recycle(id, 1800, keep: true, date: '2026-07-15');
      final it = await reload(id);
      expect(it.status, kItemStatusRecycleKeep);
      expect(it.billing, isTrue);
      expect(poolOf(it), 9999 - 1800);
      expect(it.events.last.kind, kEvRecycle);
    });
    test('keep=false → 状态已回收(转出) · billing 0 冻结', () async {
      final id = await repo.addItem(sample);
      await repo.recycle(id, 4200, keep: false, date: '2026-09-19');
      final it = await reload(id);
      expect(it.status, kItemStatusRecycleOut);
      expect(it.billing, isFalse);
      expect(costPerDay(it, DateTime(2026, 9, 19)), isNull);
      expect(settleOf(it, DateTime(2026, 9, 19)).netHold, 9999 - 4200);
    });
  });

  group('报废', () {
    test('scrap → billing 0 + scrap 事件含原因', () async {
      final id = await repo.addItem(sample);
      await repo.scrap(id, '技术淘汰', date: '2026-09-10');
      final it = await reload(id);
      expect(it.status, kItemStatusScrapped);
      expect(it.billing, isFalse);
      final ev = it.events.last;
      expect(ev.kind, kEvScrap);
      expect(ev.note, contains('原因：技术淘汰'));
      expect(ev.note, contains('审计记录已保留'));
    });
  });

  group('记账流水升级建档（联动 L12）', () {
    Future<int> addTxn({
      String kind = LedgerTxn.kExpense,
      double amt = 899,
      String date = '2026-09-15',
      String? note = '机械键盘',
      String source = LedgerTxn.kSourceManual,
    }) =>
        db.insert(DbSchema.tLedgerTxns, {
          'kind': kind,
          'amt': amt,
          'cat_id': 103,
          'account_id': 1,
          'date': date,
          'note': note,
          'source': source,
          'bk': 1,
          'tags': '[]',
          'created_at': 0,
        });

    test('upgradeCandidates：正金额≥50 · 排除已升级/收入/非候选来源', () async {
      final big = await addTxn(amt: 899);
      await addTxn(amt: 20); // <50 排除
      await addTxn(kind: LedgerTxn.kIncome, amt: 500); // 收入排除
      await addTxn(source: 'item', amt: 700); // 已挂物品来源排除
      final itemId = await repo.addItem(
          sample.copyWith(source: 'ledger', sourceTxnId: big));
      // big 已被 itemId 升级占用 → 再排除
      final small = await addTxn(amt: 60, note: '灯泡');
      final list = await repo.upgradeCandidates();
      expect(list.map((c) => c.txnId), isNot(contains(big)));
      expect(list.map((c) => c.txnId), contains(small));
      expect(list.single.txnId, small);
      expect(list.single.amount, 60);
      expect((await reload(itemId)).source, 'ledger');
    });

    test('stampTxnUpgrade 回写 source=item + link_id=物品id', () async {
      final txnId = await addTxn(amt: 499, note: '空气炸锅');
      final itemId = await repo.addItem(sample.copyWith(
          name: '空气炸锅', source: 'ledger', sourceTxnId: txnId));
      await repo.stampTxnUpgrade(txnId, itemId);
      final row = (await db.query(DbSchema.tLedgerTxns,
          where: 'id = ?', whereArgs: [txnId]))
          .single;
      expect(row['source'], 'item');
      expect(row['link_id'], '$itemId');
      expect(row['amt'], 499); // 金额不改
    });
  });
}
