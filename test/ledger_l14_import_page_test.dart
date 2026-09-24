import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_import_page.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_providers.dart';

/// 记账批1d · L14 账单导入五步向导用例。独立文件防 isolate 污染。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  const csv = '''
交易时间,交易分类,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注
2026-08-03 12:01:59,餐饮美食,全家便利店,***,早餐,支出,"¥18.50",余额宝,交易成功,T001,M1,
2026-08-05 09:00:00,收入,***,,工资,收入,"¥8,000.00",支付宝账户余额,交易成功,T002,,
''';

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
            initialLocation: '/ledger/import',
            routes: [
              GoRoute(
                path: '/ledger/import',
                builder: (_, _) => const LedgerImportPage(),
              ),
              GoRoute(
                path: '/ledger',
                builder: (_, _) => const Scaffold(body: Text('L1-STUB')),
              ),
            ],
          ),
        ),
      ),
    );
    await settle5(tester);
  }

  Future<void> tapText(WidgetTester tester, String t) async {
    await tester.tap(find.text(t).last);
    await settle5(tester);
  }

  testWidgets('步骤1→2：平台卡与隐私承诺 · 解析选项开关', (tester) async {
    await useSurface(tester);
    await pump(tester);
    expect(find.text('选择账单平台'), findsOneWidget);
    expect(find.textContaining('仅在本机解析'), findsOneWidget);
    await tapText(tester, '支付宝');
    await tester.tap(find.text('下一步'));
    await settle5(tester);
    expect(find.text('支付宝 · 粘贴账单内容'), findsOneWidget);
    expect(find.textContaining('非支出流水'), findsOneWidget);
    expect(find.textContaining('GBK 兜底转码'), findsOneWidget);
  });

  testWidgets('空内容/无表头 → 提示；解析成功进账户匹配步', (tester) async {
    await useSurface(tester);
    await pump(tester);
    await tester.tap(find.text('下一步')); // 步骤1→2
    await settle5(tester);
    expect(find.text('支付宝 · 粘贴账单内容'), findsOneWidget);
    await tester.tap(find.text('下一步'));
    await settle5(tester);
    expect(find.text('请先粘贴账单 CSV 内容'), findsOneWidget);
    await clearToasts(tester);
    await tester.enterText(find.byType(TextField).first, 'hello,world\n1,2');
    await tester.tap(find.text('下一步'));
    await settle5(tester);
    expect(find.text('未识别到支付宝/微信账单表头 · 请粘贴完整导出内容'), findsOneWidget);
    await clearToasts(tester);
    await tester.enterText(find.byType(TextField).first, csv);
    await tester.tap(find.text('下一步'));
    await settle5(tester);
    // 步骤3 账户匹配
    expect(find.text('账户匹配'), findsOneWidget);
    expect(find.textContaining('将新建'), findsWidgets);
    expect(find.textContaining('出现 1 笔 · 来自付款方式列'), findsWidgets);
    // 下一步 → 预览
    await tester.tap(find.text('下一步'));
    await settle5(tester);
    expect(find.text('解析预览 · 勾选导入'), findsOneWidget);
    expect(find.textContaining('将写入'), findsWidgets);
    expect(find.text('确认导入 2 条'), findsOneWidget);
  });

  testWidgets('重复行默认不勾选 · 强制勾选计入将写入 · 确认后落库建户', (tester) async {
    await useSurface(tester);
    // 预置一条同单号流水 → T001 行判定重复（现金账户随之 -18.5）。
    await repo.addTxn(LedgerTxn(
      kind: LedgerTxn.kExpense,
      bk: 1,
      amt: 18.5,
      catId: 101,
      accountId: 1,
      date: '2026-08-03',
      billHash: 'T001',
      source: LedgerTxn.kSourceBill,
    ));
    await pump(tester);
    await tapText(tester, '支付宝');
    await tester.tap(find.text('下一步'));
    await settle5(tester);
    await tester.enterText(find.byType(TextField).first, csv);
    await tester.tap(find.text('下一步'));
    await settle5(tester);
    // 本地只种了「现金」→ 余额宝/支付宝账户余额两组都走新建。
    await tester.tap(find.text('下一步'));
    await settle5(tester);
    // 新组 1 条（工资），重复组 1 条默认折叠未勾。
    expect(find.text('确认导入 1 条'), findsOneWidget);
    // 展开重复组并勾选该行。
    await tapText(tester, '重复命中 · 1 条');
    await settle5(tester);
    await tester.tap(find.byType(Checkbox).last);
    await settle5(tester);
    expect(find.text('确认导入 2 条'), findsOneWidget);
    // 确认导入。
    await tester.tap(find.text('确认导入 2 条'));
    await settle5(tester);
    expect(find.text('导入完成'), findsOneWidget);
    expect(find.textContaining('已写入 2 条流水'), findsOneWidget);
    expect(find.textContaining('新建账户 2 个'), findsOneWidget);
    // 落库校验：bill 流水 + 批次 + 新建账户 + 余额回算。
    final txns = await repo.bookTxns(1);
    expect(txns.where((t) => t.source == LedgerTxn.kSourceBill).length, 3);
    final bills = await repo.importBatches();
    expect(bills, hasLength(1));
    expect(bills.first['written'], 2);
    final accts = await repo.accounts();
    final yuebao = accts.where((a) => a.name == '余额宝').toList();
    expect(yuebao, hasLength(1));
    expect(yuebao.first.type, 'invest');
    // 导入的 T001 支出由余额宝（新建）承担：base 0 → -18.5
    expect(yuebao.first.balanceCache, -18.5);
    // 工资 8000 落默认账户（现金），预置流水已让现金 -18.5。
    final cash = accts.firstWhere((a) => a.name == '现金');
    expect(cash.balanceCache, 7981.5);
    // 强制导入的重复行哈希带 #fN 变体
    final forced = txns.where(
      (t) => t.billHash != null && t.billHash!.contains('#f'),
    );
    expect(forced, hasLength(1));
  });

  testWidgets('完成页：查看账本回 L1 · 再导一份重置回步骤1', (tester) async {
    await useSurface(tester);
    await pump(tester);
    await tapText(tester, '支付宝');
    await tester.tap(find.text('下一步'));
    await settle5(tester);
    await tester.enterText(find.byType(TextField).first, csv);
    await tester.tap(find.text('下一步'));
    await settle5(tester);
    await tester.tap(find.text('下一步'));
    await settle5(tester);
    await tester.tap(find.text('确认导入 2 条'));
    await settle5(tester);
    expect(find.text('查看账本'), findsOneWidget);
    await tester.tap(find.text('再导一份'));
    await settle5(tester);
    expect(find.text('选择账单平台'), findsOneWidget);
  });
}
