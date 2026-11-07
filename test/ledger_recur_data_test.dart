import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/domain/ledger_calc.dart';
import 'package:lifeharness/features/ledger/domain/ledger_models.dart';
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';
import 'package:lifeharness/shared/linkage/ledger_mounts.dart';

/// 记账批2d · L9 周期账单落库用例（recurNext 推进含 1/31→2 月末截断、day/week/
/// year 频率、recurDaysLeft 倒计时；recurs/dueRecurs 按 bk 隔离；启停/编辑/删除；
/// genDueRecur 走统一 addTxn 写路径：source=recurring+recurring_id+余额联动+
/// next 推进；maybeGenerateDue 可注入调度入口）。独立文件防 isolate 污染。
void main() {
  late Database db;
  late LedgerRepository repo;

  final now = DateTime.now();
  final today = dayKey(now);
  final nextMonthToday = recurNext(today, 'month');

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = LedgerRepository(db);
  });
  tearDown(() => db.close());

  LedgerRecur rec({
    int bk = 1,
    String name = '爱奇艺会员',
    double amt = 25,
    int catId = 113,
    String sub = '会员',
    int accountId = 1,
    String freq = 'month',
    String? nextDate,
    bool active = true,
  }) =>
      LedgerRecur(
        bk: bk,
        name: name,
        amt: amt,
        catId: catId,
        sub: sub,
        accountId: accountId,
        freq: freq,
        nextDate: nextDate ?? today,
        active: active,
      );

  group('1 · recurNext 纯函数（§4 生成即 next=freq+1周期）', () {
    test('day/week 逐日逐周推进', () {
      expect(recurNext('2026-03-15', 'day'), '2026-03-16');
      expect(recurNext('2026-02-27', 'day'), '2026-02-28');
      expect(recurNext('2026-12-31', 'day'), '2027-01-01');
      expect(recurNext('2026-03-15', 'week'), '2026-03-22');
      expect(recurNext('2026-12-30', 'week'), '2027-01-06');
    });

    test('month 同日号；月末截断 1/31→2/28、闰年→2/29、3/31→4/30', () {
      expect(recurNext('2026-03-15', 'month'), '2026-04-15');
      expect(recurNext('2026-01-31', 'month'), '2026-02-28');
      expect(recurNext('2024-01-31', 'month'), '2024-02-29');
      expect(recurNext('2026-03-31', 'month'), '2026-04-30');
      expect(recurNext('2026-12-31', 'month'), '2027-01-31');
    });

    test('year 次年同日；闰日 2/29 截到 2/28', () {
      expect(recurNext('2026-05-01', 'year'), '2027-05-01');
      expect(recurNext('2024-02-29', 'year'), '2025-02-28');
    });

    test('recurFreqName 未知键回「每周」（原型 FREQS.find 回落）', () {
      expect(recurFreqName('month'), '每月');
      expect(recurFreqName('??'), '每周');
    });

    test('recurDaysLeft：负/0=已到期，正=还有 N 天', () {
      expect(recurDaysLeft('2026-03-15', '2026-03-15'), 0);
      expect(recurDaysLeft('2026-03-15', '2026-03-10'), -5);
      expect(recurDaysLeft('2026-03-15', '2026-03-25'), 10);
    });
  });

  group('2 · 周期行 CRUD 与到期查询（九·补1 表带 bk）', () {
    test('addRecur/recurs 按 bk 过滤、id 升序', () async {
      final a = await repo.addRecur(rec(name: '房租', amt: 2300, catId: 104));
      await repo.addRecur(rec(name: '健身', amt: 99, freq: 'week'));
      await repo.addRecur(rec(bk: 2, name: '酒店会员', catId: 109));
      final l1 = await repo.recurs(1);
      expect(l1.map((r) => r.name), ['房租', '健身']);
      expect((await repo.recurs(2)).single.id, isNot(a));
      expect((await repo.recurs(2)).single.bk, 2);
    });

    test('dueRecurs/dueRecurCount：active 且 next≤today，按 bk 隔离', () async {
      await repo.addRecur(rec(name: '到期A', nextDate: shiftDays(today, -3)));
      await repo.addRecur(rec(name: '到期B', nextDate: today));
      await repo.addRecur(rec(name: '未来', nextDate: shiftDays(today, 5)));
      await repo.addRecur(rec(name: '暂停的到期', nextDate: today, active: false));
      await repo.addRecur(rec(bk: 2, name: '别家到期', nextDate: today));
      final due = await repo.dueRecurs(1, today);
      expect(due.map((r) => r.name), ['到期A', '到期B']);
      expect(await repo.dueRecurCount(1, today), 2);
    });

    test('setRecurActive / updateRecur / delRecur', () async {
      final id = await repo.addRecur(rec());
      await repo.setRecurActive(id, false);
      expect((await repo.recurs(1)).single.active, isFalse);
      await repo.updateRecur(
          id, rec(name: '腾讯视频', amt: 30, freq: 'year').copyWithId(id));
      final r = (await repo.recurs(1)).single;
      expect(r.name, '腾讯视频');
      expect(r.freq, 'year');
      // updateRecur 整行覆盖：启停保留是页面语义（L9 编辑回传原行 active）。
      expect(r.active, isTrue);
      await repo.delRecur(id);
      expect(await repo.recurs(1), isEmpty);
    });
  });

  group('3 · genDueRecur 批量生成（统一 addTxn 写路径）', () {
    test('到期行落 expense/source=recurring/recurring_id/日期=next/备注=名称，'
        '余额同事务联动，next 推进一个周期；未到期/暂停/别家不生成', () async {
      final d1 = await repo.addRecur(rec(name: '爱奇艺会员', amt: 25, nextDate: today));
      final d2 = await repo.addRecur(
          rec(name: '房租', amt: 2300, catId: 104, sub: '房租', freq: 'month',
              nextDate: shiftDays(today, -10)));
      await repo.addRecur(rec(name: '未来', nextDate: shiftDays(today, 4)));
      await repo.addRecur(rec(name: '暂停', active: false));
      await repo.addRecur(rec(bk: 2, name: '别家'));

      final n = await repo.genDueRecur(1, today);
      expect(n, 2);

      final rows = await db.query(DbSchema.tLedgerTxns,
          where: "source = 'recurring'", orderBy: 'id ASC');
      expect(rows.length, 2);
      final t1 = rows.first;
      expect(t1['kind'], LedgerTxn.kExpense);
      expect(t1['cat_id'], 113);
      expect(t1['sub'], '会员');
      expect(t1['amt'], 25.0);
      expect(t1['account_id'], 1);
      expect(t1['date'], today);
      expect(t1['note'], '爱奇艺会员');
      expect(t1['bk'], 1);
      expect(t1['recurring_id'], d1);
      final t2 = rows.last;
      expect(t2['date'], shiftDays(today, -10)); // 记账日=到期日（原型 d:r.next）
      expect(t2['recurring_id'], d2);

      // 余额联动：现金 0 − 25 − 2300
      final acct = await db.query(
          DbSchema.tLedgerAccounts, where: 'id = 1', limit: 1);
      expect((acct.single['balance_cache']! as num).toDouble(), -2325.0);

      // next 推进：today→次月同日（月末截断内含）；过期行只推进一个周期
      final rs = {for (final r in await repo.recurs(1)) r.name: r};
      expect(rs['爱奇艺会员']!.nextDate, nextMonthToday);
      expect(rs['房租']!.nextDate, recurNext(shiftDays(today, -10), 'month'));
      expect(rs['未来']!.nextDate, shiftDays(today, 4)); // 未到期不动
      expect(rs['暂停']!.nextDate, today); // 暂停不生成不动
      expect((await repo.recurs(2)).single.nextDate, today); // 别家不动
    });

    test('生成后横幅计数清零；重复调用不双生成', () async {
      await repo.addRecur(rec(name: '订阅', nextDate: today));
      expect(await repo.genDueRecur(1, today), 1);
      expect(await repo.dueRecurCount(1, today), 0);
      expect(await repo.genDueRecur(1, today), 0);
      final rows =
          await db.query(DbSchema.tLedgerTxns, where: "source = 'recurring'");
      expect(rows.length, 1);
    });

    test('maybeGenerateDue 调度纯入口（now 注入 · 当前账本）', () async {
      await repo.addRecur(rec(name: '会员日', nextDate: '2026-03-05'));
      // 当前账本=种子 bk1；now 注入 2026-03-10 → 到期生成并推进。
      final n = await maybeGenerateDue(repo, now: DateTime(2026, 3, 10));
      expect(n, 1);
      final r = (await repo.recurs(1)).single;
      expect(r.nextDate, '2026-04-05');
    });
  });
}

/// 编辑保存需带原行 id（仓储 updateRecur 用）；模型不可变，测试侧薄封装。
extension on LedgerRecur {
  LedgerRecur copyWithId(int id) => LedgerRecur(
        id: id,
        bk: bk,
        name: name,
        amt: amt,
        catId: catId,
        sub: sub,
        accountId: accountId,
        freq: freq,
        nextDate: nextDate,
        active: active,
        note: note,
      );
}
