import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/domain/ledger_calc.dart';
import 'package:lifeharness/features/ledger/domain/ledger_models.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_providers.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_recur_page.dart';

/// 记账批2d · L9 周期账单页用例（renderRecur 全渲染 / 空态 / 新建表单校验与
/// 保存 toast / 到期横幅「生成」批量落账 toast 逐字 / 启停 toast 与已暂停徽标 /
/// 行删除 / 编辑回显）。独立文件防 isolate 污染。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late LedgerRepository repo;

  final today = dayKey(DateTime.now());

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = LedgerRepository(db);
  });
  tearDown(() => db.close());

  Future<int> addRecur(LedgerRecur r) => repo.addRecur(r);

  Future<void> pump(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [ledgerRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LedgerRecurPage()),
      ),
    );
    await settle5(tester);
  }

  group('1 · 空态与骨架', () {
    testWidgets('标题/空态/新建钮/底部提示逐字', (tester) async {
      await useSurface(tester);
      await pump(tester);
      expect(find.text('周期账单'), findsWidgets);
      expect(find.text('订阅 · 房租 · 定投'), findsOneWidget);
      expect(find.text('暂无周期账单'), findsOneWidget);
      expect(find.text('＋ 新建周期账单'), findsOneWidget);
      expect(
          find.text('周期账单不预生成流水，扣日当天确认后入账（可整月回看）· '
              '自动关联续费提醒日程（L8）'),
          findsOneWidget);
      expect(find.text('生成'), findsNothing); // 无到期不显横幅
    });
  });

  group('2 · 新建表单（字段与校验 toast 逐字）', () {
    testWidgets('空表单保存→请填写名称与金额；取消关闭', (tester) async {
      await useSurface(tester);
      await pump(tester);
      await tester.tap(find.text('＋ 新建周期账单'));
      await settle5(tester);
      expect(find.text('新建周期账单'), findsOneWidget);
      expect(find.text('名称 · 如 爱奇艺会员'), findsOneWidget); // hint
      expect(find.text('保存'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      await tester.tap(find.text('保存'));
      expect(await pollText(tester, '请填写名称与金额'), isTrue);
      await clearToasts(tester);
      await tester.tap(find.text('取消'));
      await settle5(tester);
      expect(find.text('新建周期账单'), findsNothing);
    });
  });

  group('3 · 列表渲染 + 到期横幅批量生成', () {
    Future<void> fixture() async {
      await addRecur(LedgerRecur(
          bk: 1, name: '爱奇艺会员', amt: 25, catId: 113, sub: '会员',
          accountId: 1, freq: 'month', nextDate: today));
      await addRecur(LedgerRecur(
          bk: 1, name: '健身', amt: 99, catId: 106, accountId: 1,
          freq: 'week', nextDate: shiftDays(today, 10)));
    }

    testWidgets('行元信息（频率·子类·账户·下次日·倒计时）与横幅汇总', (tester) async {
      await useSurface(tester);
      await fixture();
      await pump(tester);
      expect(find.text('今日到期 1 笔 · 共 ¥25.00'), findsOneWidget);
      expect(find.text('爱奇艺会员'), findsNWidgets(2)); // 横幅名称行 + 列表行
      expect(find.text('生成'), findsOneWidget);
      expect(find.text('每月 · 会员 · 现金 · $today 已到期'), findsOneWidget);
      expect(
          find.text(
              '每周 · 现金 · ${shiftDays(today, 10)} 还有 10 天'),
          findsOneWidget);
      expect(find.text('¥99.00'), findsOneWidget);
    });

    testWidgets('「生成」钮：批量落账 toast 逐字 + 横幅消失 + next 推进', (tester) async {
      await useSurface(tester);
      await fixture();
      await pump(tester);
      await tester.tap(find.text('生成'));
      expect(await pollText(tester, '已批量生成 1 笔到期流水（L8 日程联动）'), isTrue);
      await clearToasts(tester);
      expect(find.text('今日到期 1 笔 · 共 ¥25.00'), findsNothing);
      // 统一写路径落库：source=recurring + recurring_id + 余额联动
      final rows = await db.query(
          DbSchema.tLedgerTxns, where: "source = 'recurring'");
      expect(rows.single['note'], '爱奇艺会员');
      expect(rows.single['date'], today);
      final acct = await db.query(
          DbSchema.tLedgerAccounts, where: 'id = 1', limit: 1);
      expect((acct.single['balance_cache']! as num).toDouble(), -25.0);
      final r = (await repo.recurs(1)).firstWhere((x) => x.name == '爱奇艺会员');
      expect(r.nextDate, recurNext(today, 'month'));
    });

    testWidgets('无到期点击兜底「今日无到期账单」（竞态口径）', (tester) async {
      await useSurface(tester);
      await addRecur(LedgerRecur(
          bk: 1, name: '定投', amt: 100, accountId: 1, freq: 'month',
          nextDate: shiftDays(today, 3)));
      await pump(tester);
      expect(find.text('生成'), findsNothing);
      expect(find.text('定投'), findsOneWidget);
    });
  });

  group('4 · 启停 / 删除 / 编辑', () {
    testWidgets('开关暂停 → toast 逐字 + 已暂停徽 + 横幅退场；恢复', (tester) async {
      await useSurface(tester);
      await addRecur(LedgerRecur(
          bk: 1, name: '爱奇艺会员', amt: 25, catId: 113, accountId: 1,
          freq: 'month', nextDate: today));
      await pump(tester);
      await tester.tap(find.byType(Switch));
      expect(await pollText(tester, '周期账单已暂停'), isTrue);
      await clearToasts(tester);
      expect(find.text('已暂停'), findsOneWidget);
      expect(find.text('生成'), findsNothing); // 暂停不再到期
      await tester.tap(find.byType(Switch));
      expect(await pollText(tester, '周期账单已恢复'), isTrue);
      await clearToasts(tester);
      expect(find.text('已暂停'), findsNothing);
    });

    testWidgets('删除行（原型 recDel 无确认）', (tester) async {
      await useSurface(tester);
      await addRecur(LedgerRecur(
          bk: 1, name: '房租', amt: 2300, catId: 104, accountId: 1,
          freq: 'month', nextDate: shiftDays(today, 5)));
      await pump(tester);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await settle5(tester);
      expect(find.text('房租'), findsNothing);
      expect(await repo.recurs(1), isEmpty);
    });

    testWidgets('点行开编辑表单：回显 + 保存「周期账单已更新」', (tester) async {
      await useSurface(tester);
      await addRecur(LedgerRecur(
          bk: 1, name: '视频会员', amt: 30, catId: 113, accountId: 1,
          freq: 'month', nextDate: shiftDays(today, 6)));
      await pump(tester);
      await tester.tap(find.text('视频会员'));
      await settle5(tester);
      expect(find.text('编辑周期账单'), findsOneWidget);
      expect(find.text('视频会员'), findsNWidgets(2)); // 行 + 输入框回显
      await tester.enterText(find.byType(TextField), '芒果TV');
      await tester.tap(find.text('保存'));
      expect(await pollText(tester, '周期账单已更新'), isTrue);
      await clearToasts(tester);
      expect((await repo.recurs(1)).single.name, '芒果TV');
    });
  });
}
