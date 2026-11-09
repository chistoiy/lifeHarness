import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/domain/ledger_calc.dart';
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_page.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_providers.dart';

/// 记账批2b · L5 预算落库与口径用例（set/get/carry 行级落库 + bk 隔离 +
/// 删除分类预算后 L1 预算条回落 + budLeftDays/carryOf 纯计算）。独立文件。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late LedgerRepository repo;

  final now = DateTime.now();
  final today = dayKey(now);
  final m = monthKey(now);
  final prevM = monthStep(m, -1);

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
    String kind = LedgerTxn.kExpense,
    required double amt,
    int? catId = 101,
    String? date,
    int bk = 1,
    bool nb = false,
  }) =>
      LedgerTxn(
        kind: kind,
        amt: amt,
        catId: catId,
        accountId: 1,
        date: date ?? today,
        bk: bk,
        nb: nb,
      );

  group('1 · 预算行 set/get/carry 落库（PK bk+month+cat_id）', () {
    test('总预算行(cat_id=0)+分类行+结转位 全部落库并可回读', () async {
      await repo.setBudgetTotal(1, m, 1000);
      await repo.setBudgetCat(1, m, 101, 200);
      await repo.setBudgetCat(1, m, 103, 100);
      await repo.setBudgetCarry(1, m, true);
      final b = await repo.budgetOf(1, m);
      expect(b.total, 1000);
      expect(b.carry, isTrue);
      expect(b.perCat, {101: 200, 103: 100});
      final rows = await db.query(DbSchema.tLedgerBudgets, orderBy: 'cat_id ASC');
      expect(rows, hasLength(3));
      // carry 位仅存于 cat_id=0 总预算行（结转=按预算行存 §7）。
      final zero = rows.firstWhere((r) => r['cat_id'] == 0);
      expect(zero['carry'], 1);
      expect(zero['amt'], 1000);
      expect(
        rows.where((r) => r['cat_id'] != 0).map((r) => r['carry']).toSet(),
        {0},
      );
    });

    test('bk 隔离：他账本同月为空行；写互不串扰；按 curBook 读取', () async {
      await repo.setBudgetTotal(1, m, 1000);
      await repo.setBudgetCat(1, m, 101, 200);
      var b2 = await repo.budgetOf(2, m);
      expect(b2.total, 0);
      expect(b2.carry, isFalse);
      expect(b2.perCat, isEmpty);
      await repo.addBook('账本二'); // curBookId 仍=1（未切换）
      await repo.setBudgetTotal(2, m, 50);
      expect((await repo.budgetOf(1, m)).total, 1000); // bk1 不受 bk2 写影响
      await repo.setCurBook(2);
      final cur = await repo.curBookId();
      expect((await repo.budgetOf(cur, m)).total, 50); // L5 provider 同路径
    });

    test('结转位随总预算改写存续；先行 carry 后设总额亦存续（读-改-写）', () async {
      await repo.setBudgetCarry(1, m, true); // 无总行时建行 amt=0 carry=1
      var b = await repo.budgetOf(1, m);
      expect(b.total, 0);
      expect(b.carry, isTrue);
      await repo.setBudgetTotal(1, m, 800);
      b = await repo.budgetOf(1, m);
      expect(b.total, 800);
      expect(b.carry, isTrue); // setBudgetTotal 保留原 carry
      await repo.setBudgetCarry(1, m, false);
      b = await repo.budgetOf(1, m);
      expect(b.total, 800); // setBudgetCarry 保留原 amt
      expect(b.carry, isFalse);
    });

    test('月份隔离：本月预算行读写不影响他月', () async {
      await repo.setBudgetTotal(1, m, 1000);
      await repo.setBudgetTotal(1, prevM, 700);
      await repo.setBudgetCat(1, m, 101, 200);
      final cur = await repo.budgetOf(1, m);
      final pre = await repo.budgetOf(1, prevM);
      expect(cur.total, 1000);
      expect(cur.perCat, {101: 200});
      expect(pre.total, 700);
      expect(pre.perCat, isEmpty);
    });

    test('分类预算删除（amt<=0 删行）：perCat 回落、total/carry 与他行不动',
        () async {
      await repo.setBudgetTotal(1, m, 1000);
      await repo.setBudgetCarry(1, m, true);
      await repo.setBudgetCat(1, m, 101, 200);
      await repo.setBudgetCat(1, m, 103, 100);
      await repo.setBudgetCat(1, m, 101, 0); // 滚轮回 0 = 删除
      final b = await repo.budgetOf(1, m);
      expect(b.perCat, {103: 100});
      expect(b.total, 1000);
      expect(b.carry, isTrue);
      final n = await db.query(
        DbSchema.tLedgerBudgets,
        where: 'bk = 1 AND month = ? AND cat_id = ?',
        whereArgs: [m, 101],
      );
      expect(n, isEmpty);
    });
  });

  group('2 · L5 纯计算（下沉 ledger_calc：结转额/日均可用剩余天数）', () {
    test('carryOf：上月未设总额恒 0；剩余=max(0,总−支出) 不为负', () {
      expect(carryOf(prevTotal: 0, prevExp: 500), 0);
      expect(carryOf(prevTotal: 1000, prevExp: 400), 600);
      expect(carryOf(prevTotal: 1000, prevExp: 1600), 0);
    });

    test('budLeftDays：monthStart=1 与原型 renderBudget 口径一致', () {
      expect(budLeftDays(month: '2026-03', today: '2026-03-10'), 22); // 31-10+1
      expect(budLeftDays(month: '2026-02', today: '2026-02-28'), 1); // 月末
      expect(budLeftDays(month: '2026-02', today: '2026-03-10'), 1); // 历史月
      expect(budLeftDays(month: '2026-04', today: '2026-03-10'), 1); // 未来月同原型按月末
    });

    test('budLeftDays：monthStart=15 按 15 日周期（本月15日~次月14日）', () {
      // 2026-03：周期 3/15~4/14 共 17+14=31 天。
      expect(
          budLeftDays(month: '2026-03', today: '2026-03-10', monthStart: 15), 31);
      expect(
          budLeftDays(month: '2026-03', today: '2026-03-15', monthStart: 15), 31);
      expect(
          budLeftDays(month: '2026-03', today: '2026-03-20', monthStart: 15), 26);
      // 2月周期 2/15~3/14：14+14=28 天，2/20 起剩 23。
      expect(
          budLeftDays(month: '2026-02', today: '2026-02-20', monthStart: 15), 23);
      // 非当前查看月恒 1（原型口径不变）。
      expect(
          budLeftDays(month: '2026-01', today: '2026-03-10', monthStart: 15), 1);
    });

    test('budLeftDays：monthStart 大于当月天数截断（2月31日号→末日）', () {
      // 2026-01 ms=31：周期 1/31~2/28 共 1+28=29 天。
      expect(
          budLeftDays(month: '2026-01', today: '2026-01-31', monthStart: 31), 29);
      expect(
          budLeftDays(month: '2026-01', today: '2026-01-20', monthStart: 31), 29);
    });
  });

  group('3 · 删除分类预算后 L1 预算条回落口径（bar 只读总行+mStat）', () {
    late ProviderContainer container;

    Future<void> pump(WidgetTester tester) async {
      container = ProviderContainer(
        overrides: [ledgerRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LedgerPage()),
        ),
      );
      await settle5(tester);
    }

    testWidgets('分类预算行删除前后：L1 预算条文案不变（总额+月支出驱动）', (tester) async {
      await useSurface(tester);
      await repo.setBudgetTotal(1, m, 1000);
      await repo.setBudgetCat(1, m, 101, 200);
      await add(tx(amt: 400));
      await add(tx(amt: 999, catId: 102, nb: true)); // nb 不入预算口径
      await pump(tester);
      final left = budLeftDays(month: m, today: today);
      final bar = '已用 40% · 日均可用 ${amtText(600 / left)}';
      expect(find.text('月度预算 ¥1,000.00'), findsOneWidget);
      expect(find.text(bar), findsOneWidget);
      // 删除分类预算行 + tick 失效重取：预算条口径不变。
      await repo.setBudgetCat(1, m, 101, 0);
      container.read(ledgerTickProvider.notifier).state++;
      await settle5(tester);
      expect(find.text('月度预算 ¥1,000.00'), findsOneWidget);
      expect(find.text(bar), findsOneWidget);
      // nb 行仍在流水列表展示（带「不计入」徽标）但不进预算/收支口径。
      expect(find.text('不计入'), findsOneWidget);
    });

    testWidgets('总预算回落 0（未设置）后：L1 预算条回「月度预算 未设置 · 点击查看」',
        (tester) async {
      await useSurface(tester);
      await repo.setBudgetTotal(1, m, 1000);
      await repo.setBudgetCarry(1, m, true);
      await repo.setBudgetCat(1, m, 101, 200);
      await add(tx(amt: 400));
      await repo.setBudgetCat(1, m, 101, 0);
      await repo.setBudgetTotal(1, m, 0); // 总行清 0 → 未设置
      final b = await repo.budgetOf(1, m);
      expect(b.total, 0);
      expect(b.perCat, isEmpty);
      expect(b.carry, isTrue); // carry 存于总行、总额回 0 不阻碍后续重设
      await pump(tester);
      expect(find.text('月度预算 未设置'), findsOneWidget);
      expect(find.text('点击查看'), findsOneWidget);
    });
  });
}
