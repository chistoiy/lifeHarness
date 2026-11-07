import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/domain/ledger_models.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_debt_page.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_providers.dart';

/// 记账批3a · L11 借出/借入页用例（renderDebt 全渲染 / 分段筛选 / 汇总双栏 /
/// 新建表单校验 toast / 记还款滚轮 + toast 逐字 + source=debt 流水 / 结清选账户
/// + toast + 达成态 / 删除）。手法照前批（drag 34px=100）。独立文件防 isolate 污染。
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

  Future<void> pump(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [ledgerRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LedgerDebtPage()),
      ),
    );
    await settle5(tester);
  }

  Future<int> mk(String side, String person, double total, {String note = ''}) =>
      repo.addDebt(bk: 1, side: side, person: person, total: total, note: note);

  Future<void> wheelPick(WidgetTester tester, double value) async {
    await settle5(tester);
    expect(find.byType(CupertinoPicker), findsOneWidget);
    await tester.drag(
        find.byType(CupertinoPicker), Offset(0, -34 * (value / 100)));
    await settle5(tester);
    await tester.tap(find.text('确定'));
    await settle5(tester);
  }

  group('1 · 骨架', () {
    testWidgets('标题/分段/汇总双栏/新建钮逐字', (tester) async {
      await useSurface(tester);
      await pump(tester);
      expect(find.text('借出 · 借入'), findsWidgets);
      expect(find.text('往来清晰'), findsOneWidget);
      expect(find.text('全部'), findsOneWidget);
      expect(find.text('借出 · 别人欠我'), findsOneWidget);
      expect(find.text('借入 · 我欠别人'), findsOneWidget);
      expect(find.text('借出未收'), findsOneWidget);
      expect(find.text('借入未还'), findsOneWidget);
      expect(find.text('＋ 记一笔借出 / 借入'), findsOneWidget);
    });
  });

  group('2 · 列表渲染（方向 / 状态 / 汇总 / 按钮）', () {
    Future<void> fixture() async {
      await mk(LedgerDebt.kLend, '张三', 1000);
      await mk(LedgerDebt.kBorrow, '李四', 500, note: '聚餐');
    }

    testWidgets('借出卡 / 借入卡元信息与结清前状态', (tester) async {
      await useSurface(tester);
      await fixture();
      await pump(tester);
      expect(find.textContaining('张三 借出'), findsOneWidget);
      expect(find.text('剩余 ¥1,000.00 未收'), findsOneWidget);
      expect(find.text('李四 借入 · 聚餐'), findsOneWidget);
      expect(find.text('剩余 ¥500.00 未还'), findsOneWidget);
      expect(find.text('记还款（收）'), findsOneWidget);
      expect(find.text('记还款（还）'), findsOneWidget);
      expect(find.text('结清'), findsNWidgets(2));
      expect(find.text('删'), findsNWidgets(2));
    });

    testWidgets('汇总双栏 Σleft（不随分段变）', (tester) async {
      await useSurface(tester);
      await fixture();
      await pump(tester);
      expect(find.text('¥1,000.00'), findsWidgets); // 借出未收 + 张三卡额
      expect(find.text('¥500.00'), findsWidgets); // 借入未还 + 李四卡额
    });

    testWidgets('分段筛选：只看借出隐藏借入', (tester) async {
      await useSurface(tester);
      await fixture();
      await pump(tester);
      await tester.tap(find.text('借出 · 别人欠我'));
      await settle5(tester);
      expect(find.textContaining('张三 借出'), findsOneWidget);
      expect(find.text('李四 借入 · 聚餐'), findsNothing);
    });
  });

  group('3 · 新建表单（校验落字段旁 + 落库互认）', () {
    testWidgets('空对方→对方字段旁报错；无金额→金额下方报错（均不挂提示条）',
        (tester) async {
      await useSurface(tester);
      await pump(tester);
      await tester.tap(find.text('＋ 记一笔借出 / 借入'));
      await settle5(tester);
      expect(find.text('记一笔借出 / 借入'), findsOneWidget);
      expect(find.text('对方'), findsOneWidget); // hint
      await tester.tap(find.text('保存'));
      await settle5(tester);
      // T9：对方＝框架 errorText；金额＝滚轮下方 FieldError 行；两条一次亮齐。
      expect(tester.widget<TextField>(find.byType(TextField))
          .decoration!
          .errorText, '请填写对方');
      expect(find.text('请输入金额'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      // 报错行使输入框变高，直接点 TextField 中心会落到错误行上，
      // 所以这里对着可编辑区（EditableText）聚焦再输入。
      await tester.enterText(find.byType(EditableText), '王五');
      await tester.pump();
      expect(find.text('请填写对方'), findsNothing); // 输入只撤自己那条
      await tester.tap(find.text('保存'));
      expect(await pollText(tester, '请输入金额'), isTrue);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('选借入 + 对方 + 滚轮金额 → 落 ledger_debts（同 L2 表）', (tester) async {
      await useSurface(tester);
      await pump(tester);
      await tester.tap(find.text('＋ 记一笔借出 / 借入'));
      await settle5(tester);
      await tester.tap(find.text('借入 · 我欠别人').last); // 表单方向（非顶部分段）
      await settle5(tester);
      await tester.enterText(find.byType(TextField), '王五');
      await tester.tap(find.text('金额'));
      await wheelPick(tester, 700);
      await tester.tap(find.text('保存'));
      await settle5(tester);
      final d = (await repo.debts(1)).last;
      expect(d.person, '王五');
      expect(d.side, LedgerDebt.kBorrow);
      expect(d.total, 700.0);
      expect(d.paid, 0.0);
      expect(find.textContaining('王五 借入'), findsOneWidget);
    });
  });

  group('4 · 记还款（滚轮 + toast 逐字 + source=debt 流水 + 进度）', () {
    testWidgets('借出记还款 → 已记还款流水 · 进度更新 + income 流水', (tester) async {
      await useSurface(tester);
      final id = await mk(LedgerDebt.kLend, '张三', 1000);
      await pump(tester);
      await tester.tap(find.text('记还款（收）'));
      await settle5(tester);
      expect(find.text('「张三」还款金额'), findsOneWidget); // 滚轮标题（原型）
      await wheelPick(tester, 300);
      expect(await pollText(tester, '已记还款流水 · 进度更新'), isTrue);
      await clearToasts(tester);
      expect((await repo.debtById(id))!.paid, 300.0);
      expect(find.text('剩余 ¥700.00 未收'), findsOneWidget);
      final t = (await db.query(DbSchema.tLedgerTxns,
              where: "source = 'debt'"))
          .single;
      expect(t['kind'], 'income');
      expect(t['note'], '张三 还款');
      final acct = await db.query(
          DbSchema.tLedgerAccounts, where: 'id = 1', limit: 1);
      expect((acct.single['balance_cache']! as num).toDouble(), 300.0);
    });

    testWidgets('借入记还款 → expense 还 p', (tester) async {
      await useSurface(tester);
      await mk(LedgerDebt.kBorrow, '李四', 500);
      await pump(tester);
      await tester.tap(find.text('记还款（还）'));
      await wheelPick(tester, 200);
      expect(await pollText(tester, '已记还款流水 · 进度更新'), isTrue);
      await clearToasts(tester);
      final t = (await db.query(DbSchema.tLedgerTxns,
              where: "source = 'debt'"))
          .single;
      expect(t['kind'], 'expense');
      expect(t['note'], '还 李四');
    });
  });

  group('5 · 结清（选账户 + toast + 达成态禁用）', () {
    testWidgets('结清 → 选账户 → 已结清 toast + 状态置已结清', (tester) async {
      await useSurface(tester);
      final id = await mk(LedgerDebt.kLend, '张三', 1000);
      await repo.payDebt(id, 400); // 剩 600
      await pump(tester);
      await tester.tap(find.text('结清'));
      await settle5(tester);
      expect(find.text('结清账户'), findsOneWidget); // 选择器标题
      await tester.tap(find.text('现金'));
      expect(await pollText(tester, '已结清'), isTrue);
      await clearToasts(tester);
      final d = (await repo.debtById(id))!;
      expect(d.paid, 1000.0);
      expect(find.text('已结清'), findsWidgets); // 卡状态 + toast
      final settle = (await db.query(DbSchema.tLedgerTxns,
              where: "source = 'debt'"))
          .last;
      expect(settle['note'], '张三 结清');
      expect((settle['amt']! as num).toDouble(), 600.0);
    });

    testWidgets('已结清行结清钮禁用（不弹账户选择）', (tester) async {
      await useSurface(tester);
      final id = await mk(LedgerDebt.kLend, '张三', 1000);
      await repo.settleDebt(id, accountId: 1);
      await pump(tester);
      await tester.tap(find.text('结清'));
      await settle5(tester);
      expect(find.text('结清账户'), findsNothing); // 禁用
    });
  });

  group('6 · 删除', () {
    testWidgets('点「删」移除借贷行（原型无确认）', (tester) async {
      await useSurface(tester);
      await mk(LedgerDebt.kBorrow, '李四', 500);
      await pump(tester);
      await tester.tap(find.text('删'));
      await settle5(tester);
      expect(find.textContaining('李四'), findsNothing);
      expect(await repo.debts(1), isEmpty);
    });
  });
}
