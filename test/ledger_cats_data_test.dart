import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/domain/ledger_calc.dart';
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';

/// 记账批2d · L8 分类管理落库用例（排序持久化/隐藏恢复/删除两段守卫链路的
/// 数据层：delCat 有流水→同事务整体迁移「其他」+兜底不可删(-2)+子分类行与收藏
/// 连带清理、delSubCat 流水回落未细分、renameSubCat 同步流水 sub 与 fav、
/// catTxnCount 按 bk 口径）。独立文件防 isolate 污染。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late LedgerRepository repo;

  final now = DateTime.now();
  final today = dayKey(now);

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = LedgerRepository(db);
  });
  tearDown(() => db.close());

  Future<void> add(LedgerTxn t) => repo.addTxn(t);

  LedgerTxn tx({
    required double amt,
    int? catId = 101,
    String sub = '',
    int bk = 1,
  }) =>
      LedgerTxn(
        kind: LedgerTxn.kExpense,
        amt: amt,
        catId: catId,
        sub: sub,
        accountId: 1,
        date: today,
        bk: bk,
      );

  group('1 · 排序持久化（九·补2 ③ 同列表内重排）', () {
    test('reorderMajors 按给定序回写 sort，cats() 重取即新序', () async {
      final before = [
        for (final c in await repo.cats())
          if (c.isMajor && c.kind == 'expense') c.id,
      ];
      expect(before.first, 101);
      // 把首个（餐饮）挪到第 3 位。
      final ids = [...before];
      ids.insert(2, ids.removeAt(0));
      await repo.reorderMajors('expense', ids);
      final after = [
        for (final c in await repo.cats())
          if (c.isMajor && c.kind == 'expense') c.id,
      ];
      expect(after[2], 101);
      expect(after.sublist(0, 2), [102, 103]);
    });

    test('reorderSubs 仅重排该大类下兄弟行，不动他类', () async {
      final subs = [for (final c in await repo.cats()) if (c.parentId == 101) c.id];
      expect(subs.length, greaterThan(2));
      await repo.reorderSubs(101, [...subs.reversed]);
      final after = [for (final c in await repo.cats()) if (c.parentId == 101) c.id];
      expect(after, subs.reversed.toList());
      // 其它大类不受影响
      final other = [for (final c in await repo.cats()) if (c.parentId == 102) c.id];
      expect(other.first, 1021);
    });
  });

  group('2 · 隐藏/恢复（hidden 列）', () {
    test('setCatHidden 落库与恢复；cats() 仍可见（管理页恢复入口数据源）', () async {
      await repo.setCatHidden(105, true);
      var rows = await repo.cats();
      expect(rows.firstWhere((c) => c.id == 105).hidden, isTrue);
      await repo.setCatHidden(105, false);
      rows = await repo.cats();
      expect(rows.firstWhere((c) => c.id == 105).hidden, isFalse);
      // 子分类同样可隐藏
      await repo.setCatHidden(1011, true);
      rows = await repo.cats();
      expect(rows.firstWhere((c) => c.id == 1011).hidden, isTrue);
    });
  });

  group('3 · 删除守卫 + 迁移「其他」（§4 同事务）', () {
    test('大类有流水 → 全部迁 114+sub 清空，子分类行/收藏连带删', () async {
      await add(tx(amt: 30, catId: 105, sub: '电影'));
      await add(tx(amt: 20, catId: 105));
      await add(tx(amt: 99, catId: 106, bk: 2));
      await db.insert(DbSchema.tLedgerFav, {'cat_id': 105, 'sub': '电影'});

      final r = await repo.delCat(105);
      expect(r.migrated, 2);

      final moved = await db.query(DbSchema.tLedgerTxns,
          where: 'cat_id = ? AND bk = 1', whereArgs: [DbSchema.ledgerCatOtherExpense]);
      expect(moved.length, 2);
      for (final m in moved) {
        expect((m['sub'] as String?) ?? '', isEmpty);
      }
      // 其它账本/其它分类不动
      expect(await repo.catTxnCount(106, 2), 1);
      // 分类行（大类+子）与收藏删除
      final cats = await repo.cats();
      expect(cats.where((c) => c.id == 105 || c.parentId == 105), isEmpty);
      expect(await db.query(DbSchema.tLedgerFav, where: 'cat_id = 105'), isEmpty);
    });

    test('兜底分类不可删：支出 114 / 收入 207 均返回 migrated=-2', () async {
      await add(tx(amt: 10, catId: DbSchema.ledgerCatOtherExpense));
      expect((await repo.delCat(DbSchema.ledgerCatOtherExpense)).migrated, -2);
      expect((await repo.delCat(DbSchema.ledgerCatOtherIncome)).migrated, -2);
      // 流水与分类原样保留
      expect(await repo.catTxnCount(DbSchema.ledgerCatOtherExpense, 1), 1);
      expect((await repo.cats()).any((c) => c.id == 114), isTrue);
    });

    test('无流水大类：migrated=0 直接删', () async {
      expect((await repo.delCat(112)).migrated, 0);
      expect((await repo.cats()).any((c) => c.id == 112), isFalse);
    });

    test('delSubCat：流水回落未细分（sub 置空），行与收藏删', () async {
      await add(tx(amt: 8, catId: 101, sub: '早餐'));
      await db.insert(DbSchema.tLedgerFav, {'cat_id': 101, 'sub': '早餐'});
      await repo.delSubCat(101, '早餐');
      final rows = await db.query(
          DbSchema.tLedgerTxns, where: "sub = '' AND cat_id = 101");
      expect(rows.length, 1);
      expect((await repo.cats()).any((c) => c.name == '早餐' && c.parentId == 101),
          isFalse);
      expect(await db.query(DbSchema.tLedgerFav), isEmpty);
    });

    test('catTxnCount 按当前账本口径（bk 隔离，原型 delCat 同式）', () async {
      await add(tx(amt: 5, catId: 108, bk: 1));
      await add(tx(amt: 6, catId: 108, bk: 2));
      expect(await repo.catTxnCount(108, 1), 1);
      expect(await repo.catTxnCount(108, 2), 1);
      expect(await repo.catTxnCount(108, 3), 0);
    });
  });

  group('4 · 子分类改名同步流水（九·补1 已列口径）', () {
    test('renameCat(分类行) + renameSubCat(流水/收藏) 两调用三同步', () async {
      await add(tx(amt: 12, catId: 101, sub: '午餐'));
      await db.insert(DbSchema.tLedgerFav, {'cat_id': 101, 'sub': '午餐'});
      final subId = (await repo.cats())
          .firstWhere((c) => c.parentId == 101 && c.name == '午餐')
          .id;
      await repo.renameCat(subId, '午饭');
      await repo.renameSubCat(101, '午餐', '午饭');
      final rows = await db.query(DbSchema.tLedgerTxns, where: 'cat_id = 101');
      expect(rows.single['sub'], '午饭');
      final favs = await repo.favs();
      expect(favs, contains((101, '午饭')));
      expect((await repo.cats()).any((c) => c.id == subId && c.name == '午饭'),
          isTrue);
    });
  });
}
