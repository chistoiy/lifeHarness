import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/domain/ledger_calc.dart';
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_providers.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_yearly_page.dart';

/// 记账批2a · L16 年度总结页用例（renderYearly 断言 + 看明细跳转 L4 + 分享占位）。
/// 独立文件防 isolate 污染。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late LedgerRepository repo;

  final year = DateTime.now().year;
  final today = dayKey(DateTime.now());

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = LedgerRepository(db);
    Future<void> add(LedgerTxn t) => repo.addTxn(t);
    await add(LedgerTxn(
        kind: LedgerTxn.kExpense,
        bk: 1,
        amt: 120,
        catId: 101,
        accountId: 1,
        date: today,
        note: '聚餐'));
    await add(LedgerTxn(
        kind: LedgerTxn.kExpense,
        bk: 1,
        amt: 60,
        catId: 102,
        accountId: 1,
        date: today,
        note: '充电'));
    await add(LedgerTxn(
        kind: LedgerTxn.kRefund,
        bk: 1,
        amt: 20,
        catId: 101,
        accountId: 1,
        date: today,
        note: '退外卖'));
    await add(LedgerTxn(
        kind: LedgerTxn.kIncome,
        bk: 1,
        amt: 5000,
        catId: 201,
        accountId: 1,
        date: today,
        note: '工资'));
    await add(LedgerTxn(
        kind: LedgerTxn.kExpense,
        bk: 1,
        amt: 999,
        catId: 103,
        nb: true,
        accountId: 1,
        date: today,
        note: '不计入测试'));
    // 上一年一笔（步进 ‹ 后可见）
    await add(LedgerTxn(
        kind: LedgerTxn.kExpense,
        bk: 1,
        amt: 700,
        catId: 101,
        accountId: 1,
        date: '${year - 1}-06-10',
        note: '去年支出'));
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
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/ledger/yearly',
            routes: [
              GoRoute(
                path: '/ledger/yearly',
                builder: (_, _) => const LedgerYearlyPage(),
              ),
              GoRoute(
                path: '/ledger/report',
                builder: (_, _) => const Scaffold(body: Text('REPORT')),
              ),
            ],
          ),
        ),
      ),
    );
    await settle5(tester);
  }

  testWidgets('年度总结全渲染：英雄卡/月度收支/分类 Top/最大单笔 + nb 与别年剔除',
      (tester) async {
    await useSurface(tester);
    await pump(tester);
    expect(find.text('年度总结'), findsOneWidget);
    expect(find.text('$year 年'), findsOneWidget);
    // 英雄卡：exp=120+60−20=160 inc=5000 bal=4840 cnt=3 actDays=1 日均=160/365
    expect(find.text('$year 年 · 本地账本'), findsOneWidget);
    expect(find.text('¥160.00'), findsOneWidget);
    expect(
        find.text('全年支出 · 收入 ¥5,000.00 · 结余 ¥4,840.00'), findsOneWidget);
    expect(find.text('3 笔流水'), findsOneWidget);
    expect(find.text('记账 1 天'), findsOneWidget);
    expect(find.text('日均 ¥0.44'), findsOneWidget);
    // 段卡
    expect(find.text('月度收支'), findsOneWidget);
    expect(find.text('年度分类 Top'), findsOneWidget);
    expect(find.text('餐饮'), findsOneWidget);
    expect(find.text('¥100.00'), findsOneWidget);
    expect(find.text('¥60.00'), findsOneWidget);
    // 年度最大单笔
    expect(find.text('年度最大单笔'), findsOneWidget);
    expect(find.text('$today · 聚餐'), findsOneWidget);
    expect(find.text('¥120.00'), findsOneWidget);
    // 分享与明细按钮；nb/别年金额不出现
    expect(find.text('生成分享图'), findsOneWidget);
    expect(find.text('看明细 ›'), findsOneWidget);
    expect(find.text('不计入测试'), findsNothing);
    expect(find.text('¥999.00'), findsNothing);
    expect(find.text('去年支出'), findsNothing);
    expect(find.text('¥700.00'), findsNothing);
  });

  testWidgets('年份步进 ‹ ›：切年数据重算并切回', (tester) async {
    await useSurface(tester);
    await pump(tester);
    await tester.tap(find.text('‹'));
    await settle5(tester);
    expect(find.text('${year - 1} 年'), findsOneWidget);
    expect(find.text('¥700.00'), findsWidgets);
    expect(find.text('1 笔流水'), findsOneWidget);
    expect(find.text('¥160.00'), findsNothing); // 无跨年串数据
    await tester.tap(find.text('›'));
    await settle5(tester);
    expect(find.text('$year 年'), findsOneWidget);
    expect(find.text('¥160.00'), findsOneWidget);
  });

  testWidgets('生成分享图（模拟 toast）与 看明细 › 跳 L4', (tester) async {
    await useSurface(tester);
    await pump(tester);
    await tester.tap(find.text('生成分享图'));
    expect(await pollText(tester, '已生成年度分享图（模拟）'), isTrue);
    await clearToasts(tester);
    await tester.tap(find.text('看明细 ›'));
    await settle5(tester);
    expect(find.text('REPORT'), findsOneWidget);
  });
}
