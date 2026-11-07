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
import 'package:lifeharness/features/ledger/presentation/ledger_assets_page.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_providers.dart';

/// 记账批2c · L6 资产总览页用例（净资产三位全渲染 / 6 月走势 / 账户卡分组副行 /
/// 新建账户表单落库 / 删除守卫 toast 与恢复）。独立文件防 isolate 污染。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late LedgerRepository repo;

  final now = DateTime.now();
  final today = dayKey(now);

  Future<int> newAcct({
    String type = LedgerAccount.kDebit,
    required String name,
    double base = 0,
    double? limit,
  }) =>
      repo.addAccount(LedgerAccount(
          type: type, name: name, base: base, creditLimit: limit));

  Future<void> fixture() async {
    await repo.addTxn(LedgerTxn(
        kind: LedgerTxn.kExpense,
        bk: 1,
        amt: 250,
        catId: 101,
        accountId: 1,
        date: today,
        note: '本月吃饭')); // 种子现金账户本月 1 笔
    await newAcct(name: '招商储蓄', base: 1000);
    await newAcct(
        type: LedgerAccount.kCredit, name: '交行信用卡', base: -300, limit: 10000);
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
        child: const MaterialApp(home: LedgerAssetsPage()),
      ),
    );
    await settle5(tester);
  }

  testWidgets('全渲染：净资产三位 / 走势月份 / 账户卡副行与信用卡额度 / 新建入口',
      (tester) async {
    await useSurface(tester);
    await pump(tester);
    expect(find.text('资产'), findsOneWidget);
    expect(find.text('净资产 · 账户总览'), findsOneWidget);
    // 净资产 = 资产(1000+1000 现金含种子? seed 现金 base0 → 本月支出 250 → -250)
    // 资产=1000(储蓄)+ 0? seed 现金 balance=-250(负) → 非资产。
    final accounts = await repo.accounts();
    final nw = netWorthOf([for (final a in accounts) a.balanceCache]);
    expect(find.text('净资产'), findsOneWidget);
    expect(find.text(amtText(nw.net)), findsOneWidget);
    expect(find.text('资产 ${amtText(nw.assets)}'), findsOneWidget);
    expect(find.text('负债 ${amtText(nw.liab)}'), findsOneWidget);
    // 走势卡
    expect(find.text('近 6 月净资产'), findsOneWidget);
    expect(find.textContaining('月'), findsWidgets); // 月份标签
    expect(find.byType(CustomPaint), findsWidgets);
    // 账户卡：储蓄副行「储蓄卡 · 本月 0 笔」；信用卡额度进度条 + 已用/额度
    expect(find.text('招商储蓄'), findsOneWidget);
    expect(find.text('储蓄卡 · 本月 0 笔'), findsOneWidget);
    expect(find.text('交行信用卡'), findsOneWidget);
    expect(find.text('已用 ¥300.00 / ¥10,000.00'), findsOneWidget);
    // 种子现金账户本月 1 笔
    expect(find.text('现金 · 本月 1 笔'), findsOneWidget);
    // 新建入口
    expect(find.text('＋ 新建账户'), findsOneWidget);
    expect(find.text('导入支付宝 / 微信账单 ›'), findsOneWidget);
  });

  testWidgets('新建账户表单：类型/名称/余额落库 + toast', (tester) async {
    await useSurface(tester);
    await pump(tester);
    await tester.tap(find.text('＋ 新建账户'));
    await settle5(tester);
    expect(find.text('新建账户'), findsOneWidget);
    expect(find.text('储蓄卡'), findsWidgets); // 类型宫格
    // 默认 debit：仅名称 + 余额两输入
    expect(find.byType(TextField), findsNWidgets(2));
    await tester.enterText(find.byType(TextField).at(0), '零钱通');
    await tester.enterText(find.byType(TextField).at(1), '250');
    await tester.tap(find.text('保存'));
    await settle5(tester);
    expect(await pollText(tester, '已新建账户「零钱通」'), isTrue);
    final accts = await repo.accounts();
    final a = accts.firstWhere((x) => x.name == '零钱通');
    expect(a.balanceCache, 250);
    expect(a.type, LedgerAccount.kDebit);
    await clearToasts(tester);
    // 账户卡出现
    expect(find.text('零钱通'), findsOneWidget);
  });

  testWidgets('新建信用卡：额度/账单日/还款日内嵌滚轮出现', (tester) async {
    await useSurface(tester);
    await pump(tester);
    await tester.tap(find.text('＋ 新建账户'));
    await settle5(tester);
    await tester.tap(find.text('信用卡').last); // 类型宫格项
    await settle5(tester);
    expect(find.text('信用额度'), findsOneWidget);
    expect(find.text('账单日'), findsOneWidget);
    expect(find.text('还款日'), findsOneWidget);
    expect(find.byType(CupertinoPicker), findsNWidgets(2));
  });

  testWidgets('删除守卫 toast：归档账户余额未清零拒删；清零则删除', (tester) async {
    await useSurface(tester);
    final keep = await newAcct(name: '停用有钱', base: 99);
    await repo.setAccountArchived(keep, true);
    final gone = await newAcct(name: '停用清零', base: 0);
    await repo.setAccountArchived(gone, true);
    await pump(tester);
    expect(find.text('已归档'), findsOneWidget);
    // 删除未清零 → 守卫 toast，账户仍在
    await tester.tap(find.text('删除').first);
    expect(await pollText(tester, '余额未清零 · 先转账归零再删除'), isTrue);
    await clearToasts(tester);
    expect(await repo.account(keep), isNotNull);
    // 恢复有钱账户
    await tester.tap(find.text('恢复').first);
    await settle5(tester);
    expect(await pollText(tester, '已恢复账户'), isTrue);
    await clearToasts(tester);
    expect((await repo.account(keep))!.archived, isFalse);
    // 清零账户删除成功
    await tester.tap(find.text('删除').last);
    await settle5(tester);
    expect(await pollText(tester, '已删除账户'), isTrue);
    await clearToasts(tester);
    expect(await repo.account(gone), isNull);
  });
}
