import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/domain/ledger_calc.dart';
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_budget_page.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_providers.dart';

/// 记账批2b · L5 预算中心页用例（renderBudget 全渲染 / 总环超支态 / 分类条 >100%
/// 红+「已超支 x」与恰好 100% 边界 / 滚轮增改删分类预算 / L17 结转开关与立即结转 /
/// 月份步进 / monthStart 日均可用口径）。独立文件防 isolate 污染。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late LedgerRepository repo;

  final now = DateTime.now();
  final today = dayKey(now);
  final m = monthKey(now);
  final prevM = monthStep(m, -1);

  /// 当月支出=350（300−50 refund 冲抵 + 100；nb 999 与收入不计）。
  Future<void> fixture() async {
    Future<void> add(LedgerTxn t) => repo.addTxn(t);
    await add(LedgerTxn(
        kind: LedgerTxn.kExpense, bk: 1, amt: 300, catId: 101,
        accountId: 1, date: today, note: '聚餐'));
    await add(LedgerTxn(
        kind: LedgerTxn.kRefund, bk: 1, amt: 50, catId: 101,
        accountId: 1, date: today, note: '退部分'));
    await add(LedgerTxn(
        kind: LedgerTxn.kExpense, bk: 1, amt: 100, catId: 103,
        accountId: 1, date: today, note: '日用'));
    await add(LedgerTxn(
        kind: LedgerTxn.kExpense, bk: 1, amt: 999, catId: 102, nb: true,
        accountId: 1, date: today, note: '不计入'));
    await add(LedgerTxn(
        kind: LedgerTxn.kIncome, bk: 1, amt: 5000, catId: 201,
        accountId: 1, date: today, note: '工资'));
    await add(LedgerTxn(
        kind: LedgerTxn.kExpense, bk: 1, amt: 400, catId: 101,
        accountId: 1, date: '$prevM-10', note: '上月支出'));
    await repo.setBudgetTotal(1, m, 1000);
    await repo.setBudgetCat(1, m, 101, 200); // 餐饮 250/200 → 超支
    await repo.setBudgetCat(1, m, 103, 100); // 购物 100/100 → 恰好 100% 边界
    await repo.setBudgetTotal(1, prevM, 1000); // 上月剩余 600 = 结转基线
  }

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = LedgerRepository(db);
    await fixture();
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [ledgerRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LedgerBudgetPage()),
      ),
    );
    await settle5(tester);
  }

  testWidgets('全渲染：总环/剩余·日均可用/结转卡/分类条超支红与 100% 边界 + nb 剔除',
      (tester) async {
    await useSurface(tester);
    await pump(tester);
    // AppBar TITLES + 月份步进
    expect(find.text('预算中心'), findsOneWidget);
    expect(find.text('总额与分类预算'), findsOneWidget);
    expect(find.text(finLbl(m)), findsOneWidget);
    expect(find.text('‹'), findsOneWidget);
    expect(find.text('›'), findsOneWidget);
    // 总环：350/1000 → 35%；未超支副行=剩余+日均可用（monthStart=1 口径）
    final left = budLeftDays(month: m, today: today);
    expect(find.text('已用'), findsOneWidget);
    expect(find.text('35%'), findsOneWidget);
    expect(find.text('月度总预算 ¥1,000.00'), findsOneWidget);
    expect(
        find.text('剩余 ¥650.00 · 日均可用 ${amtText(650 / left)}'),
        findsOneWidget);
    expect(find.text('修改总预算'), findsOneWidget);
    // L17 结转卡（关态）：上月剩余=1000−400=600
    expect(find.text('月度结转'), findsOneWidget);
    expect(
        find.text('上月（${finLbl(prevM)}）剩余 ¥600.00 · 开启后滚入本月'),
        findsOneWidget);
    expect(find.text('立即结转 +¥600.00'), findsNothing);
    // 分类条：餐饮 250/200 → >100% 红 +「已超支 ¥50.00」；购物恰 100% 不红
    expect(find.text('分类预算'), findsOneWidget);
    expect(find.text('＋ 添加分类'), findsOneWidget);
    expect(find.text('餐饮'), findsOneWidget);
    expect(find.text('¥250.00 / ¥200.00'), findsOneWidget);
    expect(find.text('已超支 ¥50.00'), findsOneWidget); // 仅餐饮一行（100% 边界不触发）
    expect(find.text('购物'), findsOneWidget);
    expect(find.text('¥100.00 / ¥100.00'), findsOneWidget);
    // 无预算分类默认不列出；nb/收入不进任何聚合口径；空态提示隐藏
    expect(find.text('交通'), findsNothing);
    expect(find.text('¥999.00'), findsNothing); // nb 行金额不出现在任何口径
    expect(find.text('¥5,000.00'), findsNothing); // 收入与预算页无关
    expect(find.text('点击右上角「添加分类」为具体分类设限'), findsNothing);
  });

  testWidgets('L17 结转：开关 toast/文案切换/立即结转并入总额/关闭', (tester) async {
    await useSurface(tester);
    await pump(tester);
    expect(find.byType(Switch), findsOneWidget);
    await tester.tap(find.byType(Switch));
    // tick 后 family provider 先回 loading：以「刷新后文案」轮询驱动断言。
    expect(
        await pollText(tester,
            '上月（${finLbl(prevM)}）剩余 ¥600.00 · 将自动滚入本月预算'),
        isTrue);
    expect(await pollText(tester, '结转已开启：上月未用完滚入本月'), isTrue);
    await clearToasts(tester);
    // 立即结转：1000 + round(600) → 1600；pct=350/1600→22%
    expect(find.text('立即结转 +¥600.00'), findsOneWidget);
    await tester.tap(find.text('立即结转 +¥600.00'));
    expect(await pollText(tester, '月度总预算 ¥1,600.00'), isTrue);
    expect(await pollText(tester, '已结转 ¥600.00 至本月预算'), isTrue);
    expect(find.text('22%'), findsOneWidget);
    var b = await repo.budgetOf(1, m);
    expect(b.total, 1600);
    expect(b.carry, isTrue);
    await clearToasts(tester);
    // 关闭结转：按钮消失、提示回关态文案（关闭开关不动总额）
    await tester.tap(find.byType(Switch));
    expect(await pollText(tester, '结转已关闭'), isTrue);
    expect(
        await pollText(tester,
            '上月（${finLbl(prevM)}）剩余 ¥600.00 · 开启后滚入本月'),
        isTrue);
    expect(find.text('立即结转 +¥600.00'), findsNothing);
    b = await repo.budgetOf(1, m);
    expect(b.carry, isFalse);
    expect(b.total, 1600);
    await clearToasts(tester);
  });

  testWidgets('分类预算滚轮：改额生效→再回 0 即删除行', (tester) async {
    await useSurface(tester);
    await pump(tester);
    // 改：200 → 300（超支消失）
    await tester.tap(find.text('餐饮'));
    await settle5(tester);
    expect(find.text('「餐饮」分类预算'), findsOneWidget);
    expect(find.byType(CupertinoPicker), findsOneWidget);
    await tester.drag(find.byType(CupertinoPicker), const Offset(0, -34));
    await settle5(tester);
    await tester.tap(find.text('确定'));
    await settle5(tester);
    expect(find.text('¥250.00 / ¥300.00'), findsOneWidget);
    expect(find.text('已超支 ¥50.00'), findsNothing);
    expect((await repo.budgetOf(1, m)).perCat[101], 300);
    // 删：300 → 0（三格）→ 落库删行、行消失
    await tester.tap(find.text('餐饮'));
    await settle5(tester);
    await tester.drag(find.byType(CupertinoPicker), const Offset(0, 102));
    await settle5(tester);
    await tester.tap(find.text('确定'));
    await settle5(tester);
    expect(find.text('餐饮'), findsNothing);
    expect((await repo.budgetOf(1, m)).perCat.containsKey(101), isFalse);
    expect(find.text('购物'), findsOneWidget); // 其余分类行不受影响
  });

  testWidgets('＋ 添加分类：展开全部大类/设限后「完成」回落有预算行', (tester) async {
    await useSurface(tester);
    await repo.setBudgetCat(1, m, 101, 0); // 清空分类预算 → 空态
    await repo.setBudgetCat(1, m, 103, 0);
    await pump(tester);
    expect(find.text('点击右上角「添加分类」为具体分类设限'), findsOneWidget);
    await tester.tap(find.text('＋ 添加分类'));
    await settle5(tester);
    expect(find.text('完成'), findsOneWidget);
    // 交通仅 nb 流水 → 添加模式下列出且 used 为 ¥0.00（预算口径剔 nb）
    expect(find.text('交通'), findsOneWidget);
    expect(find.text('¥0.00 / 未设'), findsAtLeastNWidgets(10));
    // 给交通设 100 → 出行；完成后仅剩该行
    await tester.tap(find.text('交通'));
    await settle5(tester);
    expect(find.text('「交通」分类预算'), findsOneWidget);
    await tester.drag(find.byType(CupertinoPicker), const Offset(0, -34));
    await settle5(tester);
    await tester.tap(find.text('确定'));
    await settle5(tester);
    expect(find.text('¥0.00 / ¥100.00'), findsOneWidget);
    await tester.tap(find.text('完成'));
    await settle5(tester);
    expect(find.text('＋ 添加分类'), findsOneWidget);
    expect(find.text('交通'), findsOneWidget);
    expect(find.text('餐饮'), findsNothing);
    expect(find.text('购物'), findsNothing);
    expect((await repo.budgetOf(1, m)).perCat, {102: 100});
  });

  testWidgets('月份步进 ‹ ›：查看上月（结转基线月/剩 1 天日均）与回切', (tester) async {
    await useSurface(tester);
    await pump(tester);
    await tester.tap(find.text('‹'));
    await settle5(tester);
    expect(find.text(finLbl(prevM)), findsOneWidget);
    // 上月：总 1000 支出 400 → 40%；非当前月剩余恒 1 天（原型口径）
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('月度总预算 ¥1,000.00'), findsOneWidget);
    expect(find.text('剩余 ¥600.00 · 日均可用 ¥600.00'), findsOneWidget);
    // 上月的上月无预算 → 结转 0 + 分类空态
    expect(
        find.text('上月（${finLbl(monthStep(prevM, -1))}）剩余 ¥0.00 · 开启后滚入本月'),
        findsOneWidget);
    expect(find.text('点击右上角「添加分类」为具体分类设限'), findsOneWidget);
    await tester.tap(find.text('›'));
    await settle5(tester);
    expect(find.text(finLbl(m)), findsOneWidget);
    expect(find.text('35%'), findsOneWidget);
  });

  testWidgets('未设置总预算：滚轮「设置总预算」落库 + 超支态红文案', (tester) async {
    await useSurface(tester);
    await repo.setBudgetTotal(1, m, 0); // 总行清 0（分类行保留）
    await pump(tester);
    expect(find.text('月度总预算 未设置'), findsOneWidget);
    expect(find.text('设置总预算'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('剩余 ¥0.00 · 日均可用 ¥0.00'), findsOneWidget);
    // 滚轮 0 → 100（总支出 350 → 超支 250）
    await tester.tap(find.text('设置总预算'));
    await settle5(tester);
    expect(find.text('总预算金额'), findsOneWidget);
    await tester.drag(find.byType(CupertinoPicker), const Offset(0, -34));
    await settle5(tester);
    await tester.tap(find.text('确定'));
    await settle5(tester);
    expect(find.text('月度总预算 ¥100.00'), findsOneWidget);
    expect(find.text('修改总预算'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget); // pct 封顶 100
    expect(find.text('已超支 ¥250.00 · 建议调整'), findsOneWidget);
    expect((await repo.budgetOf(1, m)).total, 100);
  });

  testWidgets('monthStart=15 仅改「日均可用」剩余天数口径', (tester) async {
    await useSurface(tester);
    await repo.setMonthStart(15);
    await pump(tester);
    final left15 = budLeftDays(month: m, today: today, monthStart: 15);
    final left1 = budLeftDays(month: m, today: today);
    expect(
        find.text('剩余 ¥650.00 · 日均可用 ${amtText(650 / left15)}'),
        findsOneWidget);
    if (amtText(650 / left15) != amtText(650 / left1)) {
      expect(
          find.text('剩余 ¥650.00 · 日均可用 ${amtText(650 / left1)}'),
          findsNothing);
    }
  });
}
