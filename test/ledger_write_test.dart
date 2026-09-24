import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/domain/ledger_calc.dart';
import 'package:lifeharness/features/ledger/domain/ledger_models.dart';
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';

/// 记账批1a · 统一写路径与回算口径（计划 §3/§4 + 九·补1/4；原型回归蓝本）。
void main() {
  sqfliteFfiInit();

  late Database db;
  late LedgerRepository repo;
  final today = dayKey(DateTime.now());

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    await db.execute(
        'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT)');
    for (final sql in DbSchema.migrations[17]!) {
      await db.execute(sql);
    }
    repo = LedgerRepository(db);
    // 常用测试账户：储蓄卡 base 100、现金 base 0（种子已有 id=1 现金）。
    await repo.addAccount(const LedgerAccount(
        type: LedgerAccount.kDebit, name: '储蓄卡', base: 100, icon: 'card'));
  });

  tearDown(() => db.close());

  LedgerTxn tx({
    String kind = LedgerTxn.kExpense,
    double amt = 50,
    int? catId = 101,
    String sub = '',
    int account = 1,
    int? to,
    String? date,
    int bk = 1,
    bool unpaid = false,
    bool nb = false,
    String source = LedgerTxn.kSourceManual,
    int? refundOf,
    String? billHash,
    String? note = '',
  }) =>
      LedgerTxn(
        kind: kind,
        amt: amt,
        catId: catId,
        sub: sub,
        accountId: account,
        toAccountId: to,
        date: date ?? today,
        note: note ?? '',
        source: source,
        refundOf: refundOf,
        billHash: billHash,
        bk: bk,
        unpaid: unpaid,
        nb: nb,
      );

  Future<LedgerAccount> acct(int id) async => (await repo.account(id))!;

  group('1 · 统一写路径 → balance_cache 回算', () {
    test('支出/收入后账户余额=base+Σeff（现金 base0 扣、储蓄卡 base100 进出）',
        () async {
      await repo.addTxn(tx(amt: 30, account: 1));
      expect((await acct(1)).balanceCache, -30);
      await repo.addTxn(tx(kind: LedgerTxn.kIncome, amt: 100, account: 2));
      expect((await acct(2)).balanceCache, 200);
      await repo.addTxn(tx(amt: 20, account: 2));
      expect((await acct(2)).balanceCache, 180);
    });

    test('unpaid 未付款：计入收支但不动余额', () async {
      final id = await repo.addTxn(tx(amt: 99, unpaid: true));
      expect((await acct(1)).balanceCache, 0);
      final m = await repo.monthTxns(1, today.substring(0, 7));
      expect(mStat(m).exp, 99); // 仍计收支
      expect(id, greaterThan(0));
    });

    test('nb 不计入：收支/分类出口剔除（余额仍动）', () async {
      await repo.addTxn(tx(amt: 500, nb: true, account: 2));
      final m = await repo.monthTxns(1, today.substring(0, 7));
      expect(mStat(m).exp, 0);
      expect(catStat(m), isEmpty);
      expect((await acct(2)).balanceCache, 100 - 500);
    });

    test('转账只移动余额、不计收支', () async {
      await repo.addTxn(tx(
          kind: LedgerTxn.kTransfer, amt: 40, account: 2, to: 1, catId: null));
      expect((await acct(2)).balanceCache, 60);
      expect((await acct(1)).balanceCache, 40);
      final m = await repo.monthTxns(1, today.substring(0, 7));
      final s = mStat(m);
      expect(s.exp, 0);
      expect(s.inc, 0);
    });

    test('退款冲抵为负支出并回补余额；一笔仅退一次', () async {
      final id = await repo.addTxn(tx(amt: 329, catId: 103, account: 1));
      final r = await repo.refundTxn(id);
      expect(r, isNotNull);
      final m = await repo.monthTxns(1, today.substring(0, 7));
      expect(mStat(m).exp, 0);
      expect(catStat(m).where((e) => e.$1 == 103), isEmpty); // >0 过滤
      expect((await acct(1)).balanceCache, 0); // −329+329
      expect(await repo.refundTxn(id), isNull); // 不可重复退
      expect(await repo.refundTxn(r!), isNull); // 非支出生成不了退款
    });

    test('删除原支出连带删除其 refund', () async {
      final id = await repo.addTxn(tx(amt: 100, account: 1));
      final r = await repo.refundTxn(id);
      expect(r, isNotNull);
      await repo.delTxn(id);
      expect(await repo.txnById(id), isNull);
      expect(await repo.txnById(r!), isNull);
      expect((await acct(1)).balanceCache, 0);
    });

    test('adjust 允许负值，只动余额不计收支', () async {
      await repo.adjustBalance(2, 150);
      final t = (await repo.acctTxns(2)).first;
      expect(t.kind, LedgerTxn.kAdjust);
      expect(t.amt, 50);
      expect((await acct(2)).balanceCache, 150);
      await repo.adjustBalance(2, 120);
      expect((await acct(2)).balanceCache, 120);
      final m = await repo.monthTxns(1, today.substring(0, 7));
      expect(mStat(m).exp, 0);
      expect(mStat(m).inc, 0);
      // 与当前余额一致 → 不产生流水。
      final before = await repo.bookTxns(1);
      await repo.adjustBalance(2, 120);
      expect((await repo.bookTxns(1)).length, before.length);
    });

    test('编辑流水改账户/金额 → 双边余额回算', () async {
      final id = await repo.addTxn(tx(amt: 25, account: 1));
      await repo.editTxn(id, {'account_id': 2, 'amt': 60});
      expect((await acct(1)).balanceCache, 0);
      expect((await acct(2)).balanceCache, 100 - 60);
    });
  });

  group('2 · 多账本隔离', () {
    test('流水按 bk 过滤；账户余额跨账本合并', () async {
      await repo.addBook('旅行基金');
      final books = await repo.books();
      final bk2 = books.last.id;
      await repo.addTxn(tx(amt: 600, account: 2, catId: 109, bk: bk2));
      expect((await repo.monthTxns(1, today.substring(0, 7))).where((t) => t.bk == bk2), hasLength(0));
      expect(await repo.monthTxns(bk2, today.substring(0, 7)), hasLength(1));
      expect(mStat(await repo.monthTxns(bk2, today.substring(0, 7))).exp, 600);
      // 账户全局共用：bk2 支出同样动余额。
      expect((await acct(2)).balanceCache, 100 - 600);
      expect((await repo.bookTxns(1)), isEmpty);
      expect((await repo.bookTxns(bk2)), hasLength(1));
    });

    test('非空账本禁删；最后一个账本禁删；空账本可删', () async {
      final only = await repo.delBook(1);
      expect(only.txns, -1); // 唯一账本
      await repo.addTxn(tx(amt: 1)); // 账本1 有 1 笔流水。
      await repo.addBook('旅行基金');
      final bk2 = (await repo.books()).last.id;
      final guard = await repo.delBook(1);
      expect(guard.txns, 1); // 有流水 → 拒绝
      final ok = await repo.delBook(bk2);
      expect(ok.txns, 0);
      expect(ok.left, 1);
    });
  });

  group('3 · 分类守卫与同步', () {
    test('大类删除 → 流水整体迁移「其他」；兜底不可删', () async {
      await repo.addTxn(tx(amt: 10, catId: 105, sub: '电影'));
      final r = await repo.delCat(105);
      expect(r.migrated, 1);
      final t = (await repo.bookTxns(1)).first;
      expect(t.catId, DbSchema.ledgerCatOtherExpense);
      expect(t.sub, '');
      expect(await repo.delCat(DbSchema.ledgerCatOtherExpense),
          (migrated: -2));
    });

    test('子分类改名同步流水与收藏', () async {
      await repo.addTxn(tx(amt: 10, catId: 101, sub: '午餐'));
      await repo.toggleFav(101, '午餐');
      await repo.renameSubCat(101, '午餐', '中饭');
      expect((await repo.bookTxns(1)).first.sub, '中饭');
      expect(await repo.favs(), contains((101, '中饭')));
    });

    test('子分类新增按 大类*10+序 编号', () async {
      final id = await repo.addSubCat(114, '杂项');
      expect(id, 1141);
      final id2 = await repo.addSubCat(114, '停车其他');
      expect(id2, 1142);
    });
  });

  group('4 · 账单导入（五步向导落库口径）', () {
    test('hash：交易单号优先；缺失回退组合键', () {
      expect(
        LedgerRepository.billHashOf(tradeNo: 'T20260901', date: 'x', amt: 1),
        'T20260901',
      );
      expect(
        LedgerRepository.billHashOf(date: '2026-09-01', time: '12:30', amt: 23.5, counterparty: '张记'),
        '2026-09-01 12:30|23.50|张记',
      );
    });

    test('确认导入：建户+写 src=bill+批次登记；余额联动', () async {
      final exists = await repo.billHashExists('H1');
      expect(exists, isFalse);
      final newAcct = const LedgerAccount(
          type: LedgerAccount.kEwallet, name: '余额宝', base: 0, icon: 'chart', color: '#14b8a6');
      final r = await repo.commitImport(
        bk: 1,
        platform: '支付宝',
        fileName: 'alipay_record.csv',
        newAccounts: [newAcct],
        rows: [
          ImportRowSpec(
            tx(amt: 12.5, catId: 101, account: 0, billHash: 'H1', source: LedgerTxn.kSourceBill, note: '张记快餐 · 支付宝 · 09-01 12:30'),
            newAcctIndex: 0,
          ),
          ImportRowSpec(tx(amt: 20, catId: 102, account: 1, billHash: 'H2', source: LedgerTxn.kSourceBill)),
        ],
      );
      expect(r.written, 2);
      final rows = await repo.bookTxns(1);
      expect(rows.where((t) => t.source == LedgerTxn.kSourceBill), hasLength(2));
      final yue = (await repo.accounts()).firstWhere((a) => a.name == '余额宝');
      expect((await acct(yue.id)).balanceCache, -12.5);
      expect((await acct(1)).balanceCache, -20);
      final batches = await repo.importBatches();
      expect(batches.first['written'], 2);
    });

    test('强制导入重复行：哈希拼 #fN 变体绕开 UNIQUE，原键仍可查重', () async {
      await repo.addTxn(tx(billHash: 'H9', account: 1));
      expect(await repo.billHashExists('H9'), isTrue);
      final r = await repo.commitImport(
        bk: 1,
        platform: '微信支付',
        rows: [
          ImportRowSpec(tx(billHash: 'H9', account: 1, amt: 7), newAcctIndex: null),
        ],
      );
      expect(r.written, 1);
      final rows = await repo.bookTxns(1);
      expect(rows.map((t) => t.billHash), containsAll(['H9', 'H9#f1']));
    });

    test('整批撤销：删本批流水并回算；可选回收空账户', () async {
      final r = await repo.commitImport(
        bk: 1,
        platform: '支付宝',
        newAccounts: [
          const LedgerAccount(type: LedgerAccount.kInvest, name: '零钱通', base: 0),
        ],
        rows: [
          ImportRowSpec(tx(amt: 33, account: 1), newAcctIndex: 0), // 写入新建账户
        ],
      );
      final q = (await repo.accounts()).firstWhere((a) => a.name == '零钱通');
      expect(q.balanceCache, -33);
      final n = await repo.undoImportBatch(r.batchId, reclaimAccounts: true);
      expect(n, 1);
      expect(await repo.bookTxns(1), isEmpty);
      expect((await acct(1)).balanceCache, 0);
      // 零钱通被回收（无引用且 base=0）。
      expect((await repo.accounts(includeArchived: true)).where((a) => a.name == '零钱通'), isEmpty);
      expect(await repo.importBatches(), isEmpty);
    });
  });

  group('5 · 预算/设置键', () {
    test('budgetOf/set 总预算+分类预算+结转位（bk 隔离）', () async {
      final month = today.substring(0, 7);
      await repo.setBudgetTotal(1, month, 12000);
      await repo.setBudgetCat(1, month, 101, 2200);
      await repo.setBudgetCarry(1, month, true);
      var b = await repo.budgetOf(1, month);
      expect(b.total, 12000);
      expect(b.perCat[101], 2200);
      expect(b.carry, isTrue);
      expect((await repo.budgetOf(2, month)).total, 0); // 另一账本不受影响
      await repo.setBudgetCat(1, month, 101, 0); // ≤0 删除行
      b = await repo.budgetOf(1, month);
      expect(b.perCat, isEmpty);
      expect(b.total, 12000); // 总预算行保留
    });

    test('设置键默认值与回写（§7 + 九·补5/6）', () async {
      expect(await repo.hideAmounts(), isFalse);
      expect(await repo.afterSave(), 'back');
      expect(await repo.confirmDel(), isTrue);
      expect(await repo.monthStart(), 1);
      expect(await repo.defAcctId(), 1); // 首账户
      expect(await repo.heroBig(), 'balMonth');
      expect(await repo.heroSlots(), ['teMonth', 'tiMonth', 'avgTe']);
      expect(await repo.quickCats(), [101, 102, 103, 104]);
      expect(await repo.whoDefName(), '自己');
      await repo.setHideAmounts(true);
      expect(await repo.hideAmounts(), isTrue);
      await repo.setDefAcct(2);
      expect(await repo.defAcctId(), 2);
    });

    test('角色默认守卫 + 改名同步流水', () async {
      final id = await repo.addTxn(tx(amt: 5, catId: 101));
      await repo.editTxn(id, {'who': '家人'});
      final w = (await repo.whos()).firstWhere((e) => e.name == '家人');
      await repo.renameWho(w.id, '爸妈');
      expect((await repo.txnById(id))!.who, '爸妈');
      expect(await repo.delWho(w.id), isTrue);
      final def = (await repo.whos()).firstWhere((e) => e.isDefault);
      expect(await repo.delWho(def.id), isFalse); // 默认不可删
    });

    test('标签改名同步流水 tags；删组守卫', () async {
      final id = await repo.addTxn(tx(amt: 5));
      await repo.editTxn(id, {'tags': '["报销","必要"]'});
      await repo.renameTag('报销', '出差报销');
      expect((await repo.txnById(id))!.tags, ['出差报销', '必要']);
      final g = (await repo.tagGroups()).last;
      expect(await repo.delTagGroup(g.id), isTrue);
      final g2 = (await repo.tagGroups()).single;
      expect(await repo.delTagGroup(g2.id), isFalse); // 至少留一组
    });
  });
}
