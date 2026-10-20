import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/domain/ledger_calc.dart';
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';

/// 记账批3a · L10 心愿单落库用例（wishes/addWish 按 bk 隔离；bumpWishSaved 存入/
/// 取出仅改 saved、**不落流水**、不动余额 §10 U-2、取出下限 0；redeemWish 守卫
/// saved<target 拒绝不生成流水、达成走统一 addTxn 落 expense(source=wish,归类
/// 购物 103,金额=target,账户=所选,wish_id)+done/done_date/done_txn 回写+saved
/// 归零+余额联动；updateWish/delWish）。独立文件防 isolate 污染。
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

  Future<int> txnCount() async =>
      await db.query(DbSchema.tLedgerTxns).then((r) => r.length);

  Future<double> cashBal() async {
    final a = await db.query(DbSchema.tLedgerAccounts,
        where: 'id = 1', limit: 1);
    return (a.single['balance_cache']! as num).toDouble();
  }

  group('1 · wishes / addWish（九·补1 表带 bk）', () {
    test('新建 saved=0/done=false；按 bk 过滤、id 升序', () async {
      final w1 = await repo.addWish(bk: 1, name: '相机', target: 3000);
      await repo.addWish(bk: 1, name: '键盘', target: 500);
      await repo.addWish(bk: 2, name: '别家心愿', target: 100);
      final l1 = await repo.wishes(1);
      expect(l1.map((w) => w.name), ['相机', '键盘']);
      expect(l1.first.id, w1);
      expect(l1.first.saved, 0.0);
      expect(l1.first.done, isFalse);
      expect(l1.first.achieved, isFalse);
      expect((await repo.wishes(2)).single.bk, 2);
    });
  });

  group('2 · bumpWishSaved 存入/取出不落流水（§10 U-2）', () {
    test('存入 +v 仅改 saved，零流水、余额不动；取出 −v 且下限 0', () async {
      final id = await repo.addWish(bk: 1, name: '相机', target: 3000);
      await repo.bumpWishSaved(id, 1000);
      expect((await repo.wishById(id))!.saved, 1000.0);
      expect(await txnCount(), 0); // 不落流水
      expect(await cashBal(), 0.0); // 余额不动

      await repo.bumpWishSaved(id, 1500);
      expect((await repo.wishById(id))!.saved, 2500.0);

      // 取出超过已存 → 归 0（原型 Math.max(0,saved-v)）
      await repo.bumpWishSaved(id, -5000);
      expect((await repo.wishById(id))!.saved, 0.0);
      expect(await txnCount(), 0);
    });

    test('达成判定：saved≥target 时 achieved=true 且进度封顶 100', () async {
      final id = await repo.addWish(bk: 1, name: '键盘', target: 500);
      await repo.bumpWishSaved(id, 400);
      var w = (await repo.wishById(id))!;
      expect(w.achieved, isFalse);
      expect(w.progressPct, closeTo(80, 0.001));
      await repo.bumpWishSaved(id, 200); // saved=600 > target
      w = (await repo.wishById(id))!;
      expect(w.achieved, isTrue);
      expect(w.progressPct, 100.0); // 封顶（原型 Math.min(100,..)）
    });
  });

  group('3 · redeemWish 兑换（守卫 + expense(source=wish) + 归档）', () {
    test('saved<target → 拒绝、不生成流水、不归档', () async {
      final id = await repo.addWish(bk: 1, name: '相机', target: 3000);
      await repo.bumpWishSaved(id, 2000); // 未达成
      final ok = await repo.redeemWish(id, accountId: 1);
      expect(ok, isFalse);
      expect(await txnCount(), 0);
      final w = (await repo.wishById(id))!;
      expect(w.done, isFalse);
      expect(w.saved, 2000.0); // 未变
      expect(w.doneTxn, isNull);
    });

    test('saved≥target → expense/购物103/金额=target/账户=所选/wish_id，'
        'done+done_date+done_txn 回写、saved 归零、余额 -target', () async {
      final id = await repo.addWish(bk: 1, name: '相机', target: 3000);
      await repo.bumpWishSaved(id, 3000); // 恰好达成
      final ok = await repo.redeemWish(id, accountId: 1);
      expect(ok, isTrue);

      final rows = await db.query(DbSchema.tLedgerTxns,
          where: "source = 'wish'");
      expect(rows.length, 1);
      final t = rows.single;
      expect(t['kind'], LedgerTxn.kExpense);
      expect(t['cat_id'], 103); // 购物（原型 redeem cat:'shop'）
      expect((t['amt']! as num).toDouble(), 3000.0); // 金额=target（非 saved）
      expect(t['account_id'], 1);
      expect(t['wish_id'], id);
      expect(t['bk'], 1);
      expect(t['date'], today);
      expect(t['note'], '心愿兑现 · 相机');

      final w = (await repo.wishById(id))!;
      expect(w.done, isTrue);
      expect(w.doneDate, today);
      expect(w.doneTxn, t['id']);
      expect(w.saved, 0.0);

      expect(await cashBal(), -3000.0); // 统一写路径回算余额
    });

    test('超额存入仍按 target 出账（原型 amt:w.target）', () async {
      final id = await repo.addWish(bk: 1, name: '键盘', target: 500);
      await repo.bumpWishSaved(id, 800); // 超额
      expect(await repo.redeemWish(id, accountId: 1), isTrue);
      final t = (await db.query(DbSchema.tLedgerTxns,
              where: "source = 'wish'"))
          .single;
      expect((t['amt']! as num).toDouble(), 500.0); // 出账额恒 target
      expect((await repo.wishById(id))!.saved, 0.0);
    });

    test('bk 隔离：别家心愿不受本店兑换/列表影响', () async {
      final a = await repo.addWish(bk: 1, name: '本店', target: 100);
      final b = await repo.addWish(bk: 2, name: '别家', target: 100);
      await repo.bumpWishSaved(a, 100);
      await repo.bumpWishSaved(b, 100);
      expect(await repo.redeemWish(a, accountId: 1), isTrue);
      expect((await repo.wishById(a))!.done, isTrue);
      expect((await repo.wishById(b))!.done, isFalse); // 别家未动
      final wishTxns = await db.query(DbSchema.tLedgerTxns,
          where: "source = 'wish'");
      expect(wishTxns.single['bk'], 1);
    });
  });

  group('4 · updateWish / delWish', () {
    test('编辑名称/目标不动 saved/done；删除仅移行不动流水', () async {
      final id = await repo.addWish(bk: 1, name: '旧名', target: 500);
      await repo.bumpWishSaved(id, 300);
      await repo.updateWish(id, name: '新名', target: 800);
      final w = (await repo.wishById(id))!;
      expect(w.name, '新名');
      expect(w.target, 800.0);
      expect(w.saved, 300.0); // 编辑不动已存
      expect(w.done, isFalse);

      await repo.bumpWishSaved(id, 500); // 达成
      await repo.redeemWish(id, accountId: 1);
      expect(await txnCount(), 1);
      await repo.delWish(id);
      expect(await repo.wishes(1), isEmpty);
      expect(await txnCount(), 1); // 删除不连带删流水
    });
  });
}
