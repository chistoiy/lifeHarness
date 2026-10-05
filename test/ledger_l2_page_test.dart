import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_add_page.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_providers.dart';

/// T9 防重入用例专用：把落库钉慢，制造「写入进行中」这一帧
/// （真 IO 在 FakeAsync 下的完成时机不可预测，慢仓才稳）。
class _SlowLedgerRepo extends LedgerRepository {
  _SlowLedgerRepo(super.db);

  @override
  Future<int> addTxn(LedgerTxn t) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return super.addTxn(t);
  }
}

/// 记账批1c · L2 记一笔用例。独立文件防 isolate 污染。
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

  Future<void> pump(WidgetTester tester,
      {LedgerAddPage? page, LedgerRepository? data}) async {
    final container = ProviderContainer(
      overrides: [ledgerRepositoryProvider.overrideWithValue(data ?? repo)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/x',
            routes: [
              GoRoute(
                path: '/x',
                builder: (_, _) => page ?? const LedgerAddPage(),
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
    await tester.tap(find.widgetWithText(InkWell, t).last);
    await settle5(tester);
  }

  Future<void> tapKey(WidgetTester tester, String k) async {
    await tester.tap(find.text(k).last);
    await settle5(tester);
  }

  testWidgets('默认支出形态：四 tab/餐饮分类行/子分类 chips 轨/键盘渲染', (tester) async {
    await useSurface(tester);
    await pump(tester);
    for (final t in ['支出', '收入', '转账', '借贷']) {
      expect(find.text(t), findsWidgets);
    }
    expect(find.textContaining('餐饮'), findsWidgets);
    for (final s in ['早餐', '午餐', '晚餐']) {
      expect(find.text(s), findsOneWidget);
    }
    for (final k in ['1', '5', '9', '⌫', '再记', '保存', '⌗', '0', '.']) {
      expect(find.text(k), findsOneWidget, reason: k);
    }
    expect(find.text('付款账户'), findsOneWidget);
    expect(find.text('现金'), findsWidgets);
  });

  testWidgets('四则键盘：⌗ 轮插运算符（首个 +）12+3=15 落库', (tester) async {
    await useSurface(tester);
    await pump(tester);
    await tapKey(tester, '1');
    await tapKey(tester, '2');
    await tapKey(tester, '⌗'); // 轮插首个运算符 '+'
    await tapKey(tester, '3');
    expect(find.text('12+3 =', skipOffstage: false), findsOneWidget);
    expect(find.text('15.00'), findsOneWidget);
    await tapKey(tester, '保存');
    await settle5(tester);
    final txns = await repo.bookTxns(1);
    expect(txns.single.amt, 15);
  });

  testWidgets('小数点段内唯一 + 段长限 9', (tester) async {
    await useSurface(tester);
    await pump(tester);
    await tapKey(tester, '1');
    await tapKey(tester, '.');
    await tapKey(tester, '.'); // 第二个点被忽略
    await tapKey(tester, '5');
    expect(find.text('1.50'), findsOneWidget);
  });

  testWidgets('金额=0 保存 → 金额旁就地报错（T9·不走提示条）；输入后保存 → 落库并回 L1',
      (tester) async {
    await useSurface(tester);
    await pump(tester);
    await tapKey(tester, '保存');
    expect(find.text('请输入金额'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing); // 就地：不许再挂条
    await tapKey(tester, '8');
    expect(find.text('请输入金额'), findsNothing); // 金额一有值即撤错
    await tapKey(tester, '8');
    await tapKey(tester, '.');
    await tapKey(tester, '5');
    await tapKey(tester, '保存');
    await settle5(tester);
    expect(find.text('L1-STUB'), findsOneWidget);
    final txns = await repo.bookTxns(1);
    expect(txns, hasLength(1));
    expect(txns.first.amt, 88.5);
    expect(txns.first.kind, LedgerTxn.kExpense);
    expect(txns.first.catId, 101);
    expect(txns.first.source, LedgerTxn.kSourceManual);
    // 默认已付款+计入：unpaid/nb 均 false；who=默认角色 不写
    expect(txns.first.unpaid, false);
    expect(txns.first.nb, false);
    expect(txns.first.who, isNull);
  });

  testWidgets('保存连点两次只落一条（T9 防重入）', (tester) async {
    await useSurface(tester);
    final slow = _SlowLedgerRepo(db); // 写入钉慢，才测得到「进行中」那一帧
    await pump(tester, data: slow);
    await tapKey(tester, '6');
    await tester.tap(find.text('保存'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('L1-STUB'), findsNothing); // 还在写＝页面没跳走
    await tester.tap(find.text('保存')); // 第二次必须被 _saving 拦掉
    await tester.pump(const Duration(milliseconds: 600));
    await settle5(tester);
    expect(await slow.bookTxns(1), hasLength(1));
    expect(find.text('L1-STUB'), findsOneWidget);
  });

  testWidgets('未付款 chip：只计收支不动余额', (tester) async {
    await useSurface(tester);
    await pump(tester);
    await tapText(tester, '已付款'); // → 未付款
    expect(find.text('未付款'), findsWidgets);
    await tapKey(tester, '6');
    await tapKey(tester, '6');
    await tapKey(tester, '保存');
    await settle5(tester);
    final txns = await repo.bookTxns(1);
    expect(txns.single.unpaid, true);
    final accts = await repo.accounts();
    expect(accts.first.balanceCache, 0); // 现金余额未被扣减
  });

  testWidgets('chips 轨点「午餐」→ 标题带子分类并落库 sub', (tester) async {
    await useSurface(tester);
    await pump(tester);
    await tapKey(tester, '午餐');
    expect(find.textContaining('餐饮 · 午餐'), findsWidgets);
    await tapKey(tester, '2');
    await tapKey(tester, '保存');
    await settle5(tester);
    final txns = await repo.bookTxns(1);
    expect(txns.single.sub, '午餐');
  });

  testWidgets('转账 tab：两卡选择账户 + 同账户互斥校验', (tester) async {
    await useSurface(tester);
    await pump(tester);
    await tapText(tester, '转账');
    expect(find.textContaining('选出 · 余额'), findsOneWidget);
    expect(find.textContaining('转入 · 余额'), findsOneWidget);
    await tapKey(tester, '9');
    await tapKey(tester, '保存');
    expect(find.text('转出与转入账户不能相同'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing); // T9：互斥校验落账户卡下方
  });

  testWidgets('借贷 tab：对方必填，保存直写 ledger_debts', (tester) async {
    await useSurface(tester);
    await pump(tester);
    await tapText(tester, '借贷');
    await tapKey(tester, '5');
    await tapKey(tester, '0');
    await tapKey(tester, '保存');
    // T9：错误走框架 errorText 挂在「对方」字段旁，不挂提示条。
    expect(tester.widget<TextField>(find.byType(TextField).first)
        .decoration!
        .errorText, '请填写对方');
    expect(find.byType(SnackBar), findsNothing);
    await tester.enterText(find.byType(TextField).first, '老王');
    await tester.pump();
    expect(find.text('请填写对方'), findsNothing); // 输入即撤错
    await tapKey(tester, '保存');
    await settle5(tester);
    final rows = await db.query('ledger_debts');
    expect(rows.single['person'], '老王');
    expect((rows.single['total']! as num).toDouble(), 50);
    expect(rows.single['side'], 'lend');
    expect(find.text('L1-STUB'), findsOneWidget);
  });

  testWidgets('S6 分类半屏：左大类右子类 · 选择回传', (tester) async {
    await useSurface(tester);
    await pump(tester);
    // 点分类入口行（首个「餐饮」文本）打开 S6
    await tester.tap(find.text('餐饮').first);
    await settle5(tester);
    expect(find.text('支出'), findsWidgets);
    // 左列有全部支出大类；先切「交通」再选其子分类
    expect(find.text('交通'), findsWidgets);
    await tapText(tester, '交通');
    await settle5(tester);
    await tapText(tester, '打车');
    await settle5(tester);
    expect(find.textContaining('交通 · 打车'), findsWidgets);
  });

  testWidgets('meta chips：报销/未付款/不计入 状态切换与 toast', (tester) async {
    await useSurface(tester);
    await pump(tester);
    await tapText(tester, '非报销');
    expect(find.text('报销'), findsWidgets);
    await tapText(tester, '计入收支和预算'); // → 不计入
    expect(find.text('不计入收支预算'), findsWidgets);
    await tapText(tester, '无退款');
    expect(find.text('退款 · 在流水详情页对原支出操作'), findsOneWidget);
    await clearToasts(tester);
  });
}
