import 'package:flutter/cupertino.dart';
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
import 'package:lifeharness/features/ledger/presentation/ledger_report_page.dart';

/// 记账批2a · L4 统计报表页用例（p-report 全渲染 / 翻期 / 钻取 / 自定义滚轮）。
/// 独立文件防 isolate 污染。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late LedgerRepository repo;

  final now = DateTime.now();
  final today = dayKey(now);
  final m = monthKey(now);

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = LedgerRepository(db);
    Future<void> add(LedgerTxn t) => repo.addTxn(t);
    // 本期（全部落在今天，周/月/年视图窗口均可覆盖）。
    await add(LedgerTxn(
        kind: LedgerTxn.kExpense,
        bk: 1,
        amt: 30,
        catId: 101,
        sub: '早餐',
        accountId: 1,
        date: today,
        note: '包子'));
    await add(LedgerTxn(
        kind: LedgerTxn.kExpense,
        bk: 1,
        amt: 120,
        catId: 101,
        accountId: 1,
        date: today,
        note: '请客吃饭'));
    await add(LedgerTxn(
        kind: LedgerTxn.kExpense,
        bk: 1,
        amt: 50,
        catId: 102,
        accountId: 1,
        date: today,
        note: '地铁充值'));
    await add(LedgerTxn(
        kind: LedgerTxn.kRefund,
        bk: 1,
        amt: 10,
        catId: 101,
        sub: '早餐',
        accountId: 1,
        date: today,
        note: '退包子'));
    await add(LedgerTxn(
        kind: LedgerTxn.kIncome,
        bk: 1,
        amt: 1000,
        catId: 201,
        accountId: 1,
        date: today,
        note: '工资'));
    // nb 不计入 · 不应在任何聚合出现。
    await add(LedgerTxn(
        kind: LedgerTxn.kExpense,
        bk: 1,
        amt: 999,
        catId: 103,
        nb: true,
        accountId: 1,
        date: today,
        note: '不计入测试'));
    // 上期（月视图环比窗口恒含：起于月首前 6~37 天；且不会泄进「近 7 天」）。
    await add(LedgerTxn(
        kind: LedgerTxn.kExpense,
        bk: 1,
        amt: 100,
        catId: 101,
        accountId: 1,
        date: shiftDays('$m-01', -10),
        note: '上月支出'));
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
            initialLocation: '/ledger/report',
            routes: [
              GoRoute(
                path: '/ledger/report',
                builder: (_, _) => const LedgerReportPage(),
              ),
              GoRoute(
                path: '/ledger/tx/:id',
                builder: (_, _) =>
                    const Scaffold(body: Text('TX-STUB')),
              ),
              GoRoute(
                path: '/ledger/export',
                builder: (_, _) =>
                    const Scaffold(body: Text('EXPORT-STUB')),
              ),
            ],
          ),
        ),
      ),
    );
    await settle5(tester);
  }

  testWidgets('月视图全渲染：seg/汇总/趋势/概览/排行/Top/洞察 + 环比 + nb 剔除',
      (tester) async {
    await useSurface(tester);
    await pump(tester);
    // AppBar TITLES + 四周期 seg + 翻期钮
    expect(find.text('统计报表'), findsOneWidget);
    expect(find.text('趋势 · 分类 · Top'), findsOneWidget);
    for (final s in ['周', '月', '年', '自定义']) {
      expect(find.text(s), findsOneWidget);
    }
    expect(find.text('‹'), findsOneWidget);
    expect(find.text('›'), findsOneWidget);
    // repSum：日均支出/环比上期/共 N 笔/导出占位入口
    expect(find.textContaining('${finLbl(m)} · 日均支出'), findsOneWidget);
    expect(find.text('环比上期'), findsOneWidget);
    expect(find.text('↑ 90%'), findsOneWidget); // (190-100)/100
    expect(find.text('共 4 笔'), findsOneWidget);
    expect(find.text('最大单笔 请客吃饭 ¥120.00'), findsOneWidget);
    expect(find.text('导出 ›'), findsOneWidget);
    // 五张卡标题
    for (final c in ['收支趋势', '支出趋势曲线', '收支概览', '分类排行', 'Top 支出项目', '消费洞察']) {
      expect(find.text(c), findsOneWidget);
    }
    expect(find.text('数据点不足'), findsNothing);
    expect(find.textContaining('日均'), findsWidgets); // 曲线 tag 均值
    expect(find.textContaining('峰值'), findsOneWidget);
    // 收支概览三列（exp=190 inc=1000 bal=810；refund 冲抵；收入同时出现在汇总卡）
    expect(find.text('本期收入'), findsOneWidget);
    expect(find.text('¥1,000.00'), findsWidgets);
    expect(find.text('本期结余'), findsOneWidget);
    expect(find.text('¥810.00'), findsOneWidget);
    expect(find.text('收入 − 支出'), findsOneWidget);
    expect(find.text('较上期 ↑ 90%'), findsOneWidget);
    // 分类排行（大类维度默认）：餐饮 140=74% / 交通 50=26%
    expect(find.text('按大类'), findsOneWidget);
    expect(find.text('餐饮'), findsWidgets);
    expect(find.text('¥140.00'), findsWidgets);
    expect(find.text('74%'), findsOneWidget);
    expect(find.text('26%'), findsOneWidget);
    expect(find.text('该区间暂无支出'), findsNothing);
    // Top 支出项目（nb 行不得出现）
    expect(find.text('请客吃饭'), findsWidgets);
    expect(find.text('地铁充值'), findsOneWidget);
    expect(find.text('包子'), findsOneWidget);
    expect(find.text('不计入测试'), findsNothing);
    expect(find.text('¥999.00'), findsNothing);
    // 消费洞察：规则1 占比≥40→注意 · 规则2 +90% · 规则4 最大单笔（预算缺失无规则3）
    expect(find.text('餐饮是主要支出'), findsOneWidget);
    expect(find.text('占比 74% · 共 ¥140.00'), findsOneWidget);
    expect(find.text('支出较上期增加 90%'), findsOneWidget);
    expect(find.text('最大单笔 请客吃饭'), findsOneWidget);
    expect(find.text('预算已用'), findsNothing);
    expect(find.text('该区间数据不足'), findsNothing);
    // 导出入口（批3b · ledgerNav 真实化 → 路由到 /ledger/export，本壳用桩页验证跳转）
    await tester.tap(find.text('导出 ›'));
    await settle5(tester);
    expect(find.text('EXPORT-STUB'), findsOneWidget);
  });

  testWidgets('分类排行双维度：小类 cat|sub 聚合 · 钻取展开与收起', (tester) async {
    await useSurface(tester);
    await pump(tester);
    // 切小类维度（九·补2④）：sub 空归「未细分」
    await tester.tap(find.text('小类'));
    await settle5(tester);
    expect(find.text('按小类'), findsOneWidget);
    expect(find.text('餐饮 · 未细分'), findsOneWidget);
    expect(find.text('交通 · 未细分'), findsOneWidget);
    expect(find.text('餐饮 · 早餐'), findsOneWidget);
    // 钻取「餐饮 · 早餐」：含退款冲抵两笔
    await tester.tap(find.text('餐饮 · 早餐'));
    await settle5(tester);
    expect(find.text('钻取中 · 再点收起'), findsOneWidget);
    expect(find.text('餐饮 · 早餐 · 2 笔'), findsOneWidget);
    expect(find.text('收起 ✕'), findsOneWidget);
    expect(find.text('包子'), findsWidgets); // 钻取行 + Top 项目行
    expect(find.text('退包子'), findsOneWidget);
    expect(find.text('不计入测试'), findsNothing);
    // 「收起 ✕」关闭
    await tester.tap(find.text('收起 ✕'));
    await settle5(tester);
    expect(find.text('收起 ✕'), findsNothing);
    expect(find.text('按小类'), findsOneWidget);
    // 再次点击钻取 + 再点同行收起（repDrill toggle）
    await tester.tap(find.text('餐饮 · 未细分'));
    await settle5(tester);
    expect(find.text('餐饮 · 未细分 · 1 笔'), findsOneWidget);
    await tester.tap(find.text('餐饮 · 未细分'));
    await settle5(tester);
    expect(find.text('钻取中 · 再点收起'), findsNothing);
    // 切维度清空钻取
    await tester.tap(find.text('餐饮 · 早餐'));
    await settle5(tester);
    expect(find.text('收起 ✕'), findsOneWidget);
    await tester.tap(find.text('大类'));
    await settle5(tester);
    expect(find.text('收起 ✕'), findsNothing);
    expect(find.text('按大类'), findsOneWidget);
  });

  testWidgets('翻期与年视图：月均口径 · 空区间回落文案', (tester) async {
    await useSurface(tester);
    await pump(tester);
    await tester.tap(find.text('周'));
    await settle5(tester);
    expect(find.text('近 7 天 · 日均支出 ¥27.14'), findsOneWidget); // 190/7
    await tester.tap(find.text('年'));
    await settle5(tester);
    expect(find.textContaining('${now.year}年 · 日均支出'), findsOneWidget);
    expect(find.textContaining('月均'), findsWidgets); // 曲线 tag=月均
    // 翻到下一年（步进共享 finMonth 口径）：空区间
    await tester.tap(find.text('›'));
    await settle5(tester);
    expect(find.textContaining('${now.year + 1}年 · 日均支出 ¥0.00'),
        findsOneWidget);
    expect(find.text('共 0 笔'), findsOneWidget);
    expect(find.text('该区间暂无支出'), findsOneWidget);
    // 翻回
    await tester.tap(find.text('‹'));
    await settle5(tester);
    expect(find.textContaining('${now.year}年 · 日均支出'), findsOneWidget);
  });

  testWidgets('自定义区间：两端日期 chips + 就地滚轮改值生效', (tester) async {
    await useSurface(tester);
    await pump(tester);
    await tester.tap(find.text('自定义'));
    await settle5(tester);
    expect(find.text('起 ${'$m-01'.substring(5)}'), findsOneWidget);
    expect(find.text('止 ${today.substring(5)}'), findsOneWidget);
    // 打开「起」滚轮（S2 就地内嵌三列），年列上滑一格 → 明年 → 区间变空
    await tester.tap(find.text('起 ${'$m-01'.substring(5)}'));
    await settle5(tester);
    expect(find.text('选择日期'), findsOneWidget);
    expect(find.byType(CupertinoPicker), findsNWidgets(3));
    await tester.drag(find.byType(CupertinoPicker).at(0), const Offset(0, -34));
    await settle5(tester);
    await tester.tap(find.text('确定'));
    await settle5(tester);
    expect(find.text('共 0 笔'), findsOneWidget);
    expect(find.text('该区间暂无支出'), findsOneWidget);
    // 区间标签变为 自定义（MM-DD ~ MM-DD）
    expect(find.textContaining('${'$m-01'.substring(5)} ~ '), findsWidgets);
  });
}
