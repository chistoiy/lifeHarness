import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/domain/ledger_calc.dart';
import 'package:lifeharness/features/ledger/domain/ledger_models.dart';
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_account_detail_page.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_providers.dart';

/// 记账批2c · L7 账户详情页用例（信息卡+最近流水渲染 / 调整余额滚轮生效 /
/// 信用卡账期内嵌滚轮改值落库）。独立文件防 isolate 污染。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late LedgerRepository repo;

  final now = DateTime.now();
  final today = dayKey(now);

  Future<void> pump(WidgetTester tester, int id) async {
    final container = ProviderContainer(
      overrides: [ledgerRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: LedgerAccountDetailPage(accountId: id)),
      ),
    );
    await settle5(tester);
  }

  group('借记账户', () {
    late int acctId;
    setUp(() async {
      db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      repo = LedgerRepository(db);
      acctId = await repo.addAccount(const LedgerAccount(
          type: LedgerAccount.kDebit, name: '工资卡', base: 500));
      await repo.addTxn(LedgerTxn(
          kind: LedgerTxn.kExpense,
          bk: 1,
          amt: 200,
          catId: 101,
          accountId: acctId,
          date: today,
          note: '吃饭'));
    });
    tearDown(() => db.close());

    testWidgets('详情渲染：名称/余额/三操作钮/最近流水', (tester) async {
      await useSurface(tester);
      await pump(tester, acctId);
      expect(find.text('账户详情'), findsOneWidget);
      // 账户名：信息卡 + 最近流水行内均出现
      expect(find.text('工资卡'), findsWidgets);
      expect(find.text(amtText(300)), findsOneWidget); // 500-200
      expect(find.text('调整余额'), findsOneWidget);
      expect(find.text('编辑'), findsOneWidget);
      expect(find.text('归档'), findsOneWidget);
      expect(find.text('最近流水'), findsOneWidget);
      expect(find.text('仅本机存储'), findsOneWidget);
      expect(find.text('吃饭'), findsOneWidget);
      expect(find.text('暂无流水'), findsNothing);
    });

    testWidgets('调整余额：S5 滚轮改值 → 生成 adjust → balance_cache 更新',
        (tester) async {
      await useSurface(tester);
      await pump(tester, acctId);
      await tester.tap(find.text('调整余额'));
      await settle5(tester);
      expect(find.text('调整为'), findsOneWidget);
      expect(find.byType(CupertinoPicker), findsOneWidget);
      // 当前余额 300 → 上调 5 格（+500）→ 800
      await tester.drag(find.byType(CupertinoPicker), const Offset(0, -170));
      await settle5(tester);
      await tester.tap(find.text('确定'));
      await settle5(tester);
      final a = (await repo.account(acctId))!;
      expect(a.balanceCache, 800);
      expect(find.text(amtText(800)), findsOneWidget);
      // 收支不变：adjust 不进 mStat
      final st = mStat(await repo.bookTxns(1));
      expect(st.exp, 200);
    });
  });

  group('信用卡账户', () {
    late int creditId;
    setUp(() async {
      db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      repo = LedgerRepository(db);
      creditId = await repo.addAccount(const LedgerAccount(
        type: LedgerAccount.kCredit,
        name: '信用卡',
        base: -500,
        creditLimit: 20000,
        billDay: 5,
        repayDay: 15,
      ));
    });
    tearDown(() => db.close());

    testWidgets('账期模块：已出/未出账单卡 + 出账还款额度可用行 + 内嵌账期滚轮',
        (tester) async {
      await useSurface(tester);
      await pump(tester, creditId);
      expect(find.text('已出账单 · 5号'), findsOneWidget);
      expect(find.text('未出账单'), findsOneWidget);
      expect(
          find.text('每月 5 日出账 · 15 日还款 · 额度 ¥20,000.00 · 可用 ¥19,500.00'),
          findsOneWidget);
      expect(find.text('账期设置'), findsOneWidget);
      expect(find.text('账单日'), findsOneWidget);
      expect(find.text('还款日'), findsOneWidget);
      expect(find.byType(CupertinoPicker), findsNWidgets(2));
    });

    testWidgets('就地滚轮改账单日落库（禁两段式弹层·滚动即写）', (tester) async {
      await useSurface(tester);
      await pump(tester, creditId);
      // 账单日滚轮（第 0 个），初值 5 → index 4；下移 3 格 → index 1 → 2 号
      await tester.drag(find.byType(CupertinoPicker).first, const Offset(0, 96));
      await settle5(tester);
      final a = (await repo.account(creditId))!;
      expect(a.billDay, isNot(5));
      expect(a.billDay, inInclusiveRange(1, 8));
      expect(a.repayDay, 15); // 还款日不受影响
    });
  });
}
