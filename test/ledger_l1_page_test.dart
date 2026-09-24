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

/// 记账批1b · L1 主页用例。独立文件防 isolate 污染。
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

  Future<LedgerTxn> add(LedgerTxn t) async {
    await repo.addTxn(t);
    return t;
  }

  Future<void> pump(WidgetTester tester) async {
    final container = ProviderContainer(
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

  testWidgets('hero 卡：账本/月份/大数字/三槽/预算条/五宫格 全渲染', (tester) async {
    await useSurface(tester);
    await add(LedgerTxn(
      kind: LedgerTxn.kExpense,
      bk: 1,
      amt: 120,
      catId: 101,
      accountId: 1,
      date: dayKey(DateTime.now()),
    ));
    await pump(tester);
    expect(find.text('记账'), findsOneWidget);
    expect(find.text('日常账本'), findsOneWidget);
    expect(find.text('仅本机存储'), findsOneWidget);
    // 默认 heroBig=balMonth / slots=[teMonth,tiMonth,avgTe]
    expect(find.text('本月结余'), findsWidgets);
    expect(find.text('本月支出'), findsWidgets);
    expect(find.text('日均支出'), findsWidgets);
    expect(find.text('未设置'), findsNothing); // 预算文案为「月度预算 未设置」子串
    expect(find.textContaining('月度预算'), findsOneWidget);
    expect(find.text('点击查看'), findsOneWidget);
    for (final f in ['资产', '预算', '报表', '周期', '更多']) {
      expect(find.text(f), findsOneWidget);
    }
    // 快速记一笔四格（默认 [101,102,103,104]）
    expect(find.text('快速记一笔'), findsOneWidget);
    expect(find.text('餐饮'), findsWidgets);
    // 流水一行
    expect(find.text('¥120.00'), findsWidgets);
  });

  testWidgets('环图 + top4 图例 + 日历视图切换 + 搜索/月份步进不崩', (tester) async {
    await useSurface(tester);
    await add(LedgerTxn(
      kind: LedgerTxn.kExpense,
      bk: 1,
      amt: 80,
      catId: 102,
      accountId: 1,
      date: dayKey(DateTime.now()),
    ));
    await add(LedgerTxn(
      kind: LedgerTxn.kIncome,
      bk: 1,
      amt: 500,
      catId: 201,
      accountId: 1,
      date: dayKey(DateTime.now()),
    ));
    await pump(tester);
    expect(find.text('分类占比'), findsOneWidget);
    expect(find.text('交通'), findsWidgets);
    expect(find.text('本月暂无支出流水'), findsNothing);
    // 切日历
    await tester.tap(find.text('日历'));
    await settle5(tester);
    expect(find.text('本月暂无流水，点下方按钮记一笔'), findsNothing);
    // 选中今天格子 → 出现当日流水段
    await tester.tap(find.text('${DateTime.now().day}').first);
    await settle5(tester);
    expect(find.textContaining('流水'), findsWidgets);
    // 回列表
    await tester.tap(find.text('列表'));
    await settle5(tester);
    // 月份步进（‹ ›）不崩
    await tester.tap(find.text('‹'));
    await settle5(tester);
    await tester.tap(find.text('›'));
    await settle5(tester);
  });

  testWidgets('金额隐藏 eye：全局金额打点', (tester) async {
    await useSurface(tester);
    await add(LedgerTxn(
      kind: LedgerTxn.kExpense,
      bk: 1,
      amt: 66,
      catId: 101,
      accountId: 1,
      date: dayKey(DateTime.now()),
    ));
    await pump(tester);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await settle5(tester);
    expect(find.textContaining('¥•••••'), findsWidgets);
    await clearToasts(tester);
  });

  testWidgets('S7 账本弹层：列表/新建守卫 + 更多弹层八宫格', (tester) async {
    await useSurface(tester);
    await pump(tester);
    await tester.tap(find.text('日常账本'));
    await settle5(tester);
    expect(find.text('我的账本'), findsOneWidget);
    expect(find.textContaining('账户共用'), findsWidgets);
    // 仅剩一本时删除 → 守卫提示
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await settle5(tester);
    expect(find.text('至少保留一个账本'), findsOneWidget);
    await clearToasts(tester);
    // 点弹层上方遮罩关闭（bottom sheet 无返回键）
    await tester.tapAt(const Offset(400, 40));
    await settle5(tester);
    expect(find.text('＋ 新建账本'), findsNothing);
    // 更多弹层
    await tester.tap(find.text('更多'));
    await settle5(tester);
    expect(find.text('记账管理'), findsOneWidget);
    for (final n in ['分类管理', '心愿单', '借出·借入', '搜索筛选', '账单导入', '数据导出', '年度总结', '记账设置']) {
      expect(find.text(n), findsOneWidget);
    }
    await tester.tap(find.text('记账设置'));
    await settle5(tester);
    expect(find.textContaining('即将开放'), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('S12 顶部卡配置：草稿制 + 预览 + 取消不生效 + 保存生效', (tester) async {
    await useSurface(tester);
    await pump(tester);
    // 点大数字区打开配置弹层
    await tester.tap(find.text('本月结余'));
    await settle5(tester);
    expect(find.text('自定义顶部卡片'), findsOneWidget);
    expect(find.text('预览 · 实时反映草稿'), findsOneWidget);
    expect(find.text('大数字 · 醒目位'), findsOneWidget);
    // 改选「今日支出」→ 仅草稿（.first＝大数字段内的 chips）
    await tester.tap(find.text('今日支出').first);
    await settle5(tester);
    // 取消 → 保持原样
    await tester.tap(find.text('取消'));
    await settle5(tester);
    expect(find.text('本月结余'), findsWidgets);
    // 再开 → 选择 → 保存
    await tester.tap(find.text('本月结余'));
    await settle5(tester);
    await tester.tap(find.text('今日支出').first);
    await settle5(tester);
    await tester.tap(find.text('保存'));
    await settle5(tester);
    // 大数字位换成今日支出后，醒目位标签不再显示「本月结余」
    expect(find.text('本月结余'), findsNothing);
    expect(find.text('今日支出'), findsWidgets);
    expect(find.text('顶部卡片已保存'), findsOneWidget);
    await clearToasts(tester);
  });
}
