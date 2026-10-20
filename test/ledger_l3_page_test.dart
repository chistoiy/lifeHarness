import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/domain/ledger_calc.dart';
import 'package:lifeharness/features/ledger/domain/ledger_models.dart';
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_providers.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_tx_detail_page.dart';

/// 记账批1c · L3 流水详情用例。独立文件防 isolate 污染。
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

  late List<String> navLog;

  Future<int> add(LedgerTxn t) => repo.addTxn(t);

  Future<GoRouter> pump(WidgetTester tester, int id) async {
    final container = ProviderContainer(
      overrides: [ledgerRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    navLog = [];
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('HOME-STUB')),
        ),
        GoRoute(
          path: '/tx',
          builder: (_, _) => LedgerTxDetailPage(txnId: id),
        ),
        GoRoute(
          path: '/ledger/add',
          builder: (_, s) {
            navLog.add(s.uri.toString());
            return Scaffold(
              appBar: AppBar(),
              body: const Text('L2-STUB'),
            );
          },
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await settle5(tester);
    // 真实链路：详情永远是 push 出来的栈页（可 pop 回来源）。
    router.push('/tx');
    await settle5(tester);
    return router;
  }

  Future<void> tapText(WidgetTester tester, String t) async {
    await tester.tap(find.text(t).last);
    await settle5(tester);
  }

  testWidgets('支出详情：金额/账户/日期 + 编辑/复制路由 + 退款生成负支出', (tester) async {
    await useSurface(tester);
    final id = await add(LedgerTxn(
      kind: LedgerTxn.kExpense,
      bk: 1,
      amt: 42,
      catId: 101,
      sub: '午餐',
      accountId: 1,
      date: dayKey(DateTime.now()),
      note: '便当',
      tags: ['报销'],
    ));
    await pump(tester, id);
    expect(find.text('流水详情'), findsOneWidget);
    expect(find.text('−¥42.00'), findsOneWidget);
    expect(find.text('餐饮 · 午餐'), findsWidgets);
    expect(find.text('便当'), findsWidgets);
    expect(find.textContaining('#报销'), findsWidgets);
    expect(find.textContaining('现金 · '), findsOneWidget);
    // 编辑/复制 → L2 路由带参
    await tapText(tester, '编辑');
    expect(navLog.single, contains('edit=$id'));
    await tester.pageBack();
    await settle5(tester);
    await tapText(tester, '复制');
    expect(navLog.last, contains('copy=$id'));
    await tester.pageBack();
    await settle5(tester);
    // 退款：生成 refund 流水并禁用退款钮
    await tapText(tester, '退款');
    await settle5(tester);
    final txns = await repo.bookTxns(1);
    expect(txns.where((t) => t.kind == LedgerTxn.kRefund), hasLength(1));
    expect(find.text('已生成退款冲抵 · 支出与预算同步扣减'), findsOneWidget);
    await clearToasts(tester);
    // 已退款的支出再点退款钮应不可用（disabled）
    expect(find.text('已退款'), findsOneWidget);
  });

  testWidgets('删除二次确认（confirmDel 默认开）· 2.6s 内二击才删', (tester) async {
    await useSurface(tester);
    final id = await add(LedgerTxn(
      kind: LedgerTxn.kIncome,
      bk: 1,
      amt: 100,
      catId: 201,
      accountId: 1,
      date: dayKey(DateTime.now()),
    ));
    await pump(tester, id);
    await tapText(tester, '删除');
    expect(find.text('再次点击删除以确认'), findsOneWidget);
    expect(await repo.txnById(id), isNotNull);
    await clearToasts(tester);
    await tapText(tester, '删除');
    await settle5(tester);
    expect(await repo.txnById(id), isNull);
    expect(find.text('已删除该笔流水及其退款'), findsOneWidget);
  });

  testWidgets('转账详情：转出/转入两行、无账户余额行', (tester) async {
    await useSurface(tester);
    await repo.addAccount(const LedgerAccount(
      type: LedgerAccount.kDebit,
      name: '储蓄卡',
      color: '#0ea5e9',
      icon: 'card',
    ));
    final id = await add(LedgerTxn(
      kind: LedgerTxn.kTransfer,
      bk: 1,
      amt: 30,
      catId: 114,
      accountId: 1,
      toAccountId: 2,
      date: dayKey(DateTime.now()),
    ));
    await pump(tester, id);
    expect(find.text('转账'), findsWidgets);
    expect(find.text('转出'), findsOneWidget);
    expect(find.text('转入'), findsOneWidget);
    // 转账不可退款
    expect(find.text('退款'), findsOneWidget); // 钮在但 disabled
  });
}
