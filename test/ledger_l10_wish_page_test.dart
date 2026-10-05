import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/domain/ledger_calc.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_providers.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_wish_page.dart';

/// 记账批3a · L10 心愿单页用例（renderWish 全渲染 / 进度头 / 新建表单校验与落库 /
/// 存入·取出滚轮 + toast 逐字且不落流水 / 兑换按钮禁用态与达成 toast + 归档 /
/// 删除）。金额滚轮交互手法照批2b L5（drag 34px=100）。独立文件防 isolate 污染。
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

  Future<void> pump(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [ledgerRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LedgerWishPage()),
      ),
    );
    await settle5(tester);
  }

  Future<int> mkWish(String name, double target, {double saved = 0}) async {
    final id = await repo.addWish(bk: 1, name: name, target: target);
    if (saved > 0) await repo.bumpWishSaved(id, saved);
    return id;
  }

  /// 打开金额滚轮后拖动选中 value（value/100 × 34px）并确定。
  Future<void> wheelPick(WidgetTester tester, double value) async {
    await settle5(tester);
    expect(find.byType(CupertinoPicker), findsOneWidget);
    await tester.drag(
        find.byType(CupertinoPicker), Offset(0, -34 * (value / 100)));
    await settle5(tester);
    await tester.tap(find.text('确定'));
    await settle5(tester);
  }

  group('1 · 骨架与空态', () {
    testWidgets('标题/进度头/新建钮逐字', (tester) async {
      await useSurface(tester);
      await pump(tester);
      expect(find.text('心愿单'), findsWidgets);
      expect(find.text('为想要的攒一攒'), findsOneWidget);
      expect(find.text('心愿进度'), findsOneWidget);
      expect(find.text('＋ 新建心愿'), findsOneWidget);
      expect(find.text('已实现'), findsNothing); // 无归档不显分组
    });
  });

  group('2 · 列表渲染（进度条 / 达成态 / 兑换禁用）', () {
    testWidgets('未达成：目标 money + 百分比 + 兑换记账禁用', (tester) async {
      await useSurface(tester);
      await mkWish('相机', 1000, saved: 300);
      await pump(tester);
      expect(find.text('相机'), findsOneWidget);
      expect(find.text('目标 ¥1,000.00'), findsOneWidget); // money 恒显
      expect(find.text('¥300.00'), findsOneWidget); // 已存（AMT）
      expect(find.text('30%'), findsOneWidget);
      expect(find.text('已达成，可兑换'), findsNothing);
      expect(find.text('存入'), findsOneWidget);
      expect(find.text('取出'), findsOneWidget);
      expect(find.text('兑换记账'), findsOneWidget);
      // 进度头 Σ已存 / Σ目标（RichText 合并串）
      expect(
          find.byWidgetPredicate((w) =>
              w is RichText && w.text.toPlainText() == '¥300.00 / ¥1,000.00'),
          findsOneWidget);
    });

    testWidgets('达成：· 已达成，可兑换 + 兑换记账可点', (tester) async {
      await useSurface(tester);
      await mkWish('键盘', 500, saved: 500);
      await pump(tester);
      expect(find.text('目标 ¥500.00 · 已达成，可兑换'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('已实现分组：✓ + 名称 + doneDate', (tester) async {
      await useSurface(tester);
      final id = await mkWish('耳机', 300, saved: 300);
      await repo.redeemWish(id, accountId: 1);
      await pump(tester);
      expect(find.text('已实现'), findsOneWidget);
      expect(find.text('耳机'), findsOneWidget);
      expect(find.text(today), findsOneWidget); // done_date
    });
  });

  group('3 · 新建表单（校验落字段旁 + 金额滚轮落库）', () {
    testWidgets('空表单保存→名称与目标金额各自亮错；取消关闭', (tester) async {
      await useSurface(tester);
      await pump(tester);
      await tester.tap(find.text('＋ 新建心愿'));
      await settle5(tester);
      expect(find.text('新建心愿'), findsOneWidget);
      expect(find.text('心愿名称'), findsOneWidget); // hint
      await tester.tap(find.text('保存'));
      await settle5(tester);
      // T9：合并句拆成两枚字段旁错误，且不挂提示条。
      expect(tester.widget<TextField>(find.byType(TextField))
          .decoration!
          .errorText, '请填写心愿名称');
      expect(find.text('请填写目标金额'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await tester.tap(find.text('取消'));
      await settle5(tester);
      expect(find.text('新建心愿'), findsNothing);
    });

    testWidgets('填名称 + 滚轮目标 → 保存落库并渲染', (tester) async {
      await useSurface(tester);
      await pump(tester);
      await tester.tap(find.text('＋ 新建心愿'));
      await settle5(tester);
      await tester.enterText(find.byType(TextField), '手表');
      await tester.tap(find.text('目标金额'));
      await wheelPick(tester, 800);
      await tester.tap(find.text('保存'));
      await settle5(tester);
      expect((await repo.wishes(1)).single.name, '手表');
      expect((await repo.wishes(1)).single.target, 800.0);
      expect(find.text('手表'), findsOneWidget);
    });
  });

  group('4 · 存入 / 取出（滚轮 + toast 逐字，不落流水 U-2）', () {
    testWidgets('存入 → 已存入 ¥xx + saved 增 + 无流水', (tester) async {
      await useSurface(tester);
      await mkWish('相机', 1000);
      await pump(tester);
      await tester.tap(find.text('存入'));
      await settle5(tester);
      expect(find.text('「相机」存入'), findsOneWidget); // 滚轮标题（原型）
      await wheelPick(tester, 400);
      expect(await pollText(tester, '已存入 ¥400.00'), isTrue);
      await clearToasts(tester);
      expect((await repo.wishes(1)).single.saved, 400.0);
      // U-2：存入不落流水
      final wish = await db.query(DbSchema.tLedgerTxns);
      expect(wish, isEmpty);
    });

    testWidgets('取出 → 已取出 ¥xx + saved 减（下限 0）', (tester) async {
      await useSurface(tester);
      await mkWish('相机', 1000, saved: 300);
      await pump(tester);
      await tester.tap(find.text('取出'));
      await wheelPick(tester, 500); // 超出已存
      expect(await pollText(tester, '已取出 ¥500.00'), isTrue);
      await clearToasts(tester);
      expect((await repo.wishes(1)).single.saved, 0.0);
      expect(await db.query(DbSchema.tLedgerTxns), isEmpty);
    });
  });

  group('5 · 兑换（守卫禁用 + 达成弹账户选择 + 归档 toast）', () {
    testWidgets('未达成点兑换不弹账户选择器', (tester) async {
      await useSurface(tester);
      await mkWish('相机', 1000, saved: 100);
      await pump(tester);
      await tester.tap(find.text('兑换记账'));
      await settle5(tester);
      expect(find.text('兑换账户'), findsNothing); // 禁用，未弹层
    });

    testWidgets('达成 → 选账户生成 expense(source=wish) + 归档 toast', (tester) async {
      await useSurface(tester);
      await mkWish('相机', 1000, saved: 1000);
      await pump(tester);
      await tester.tap(find.text('兑换记账'));
      await settle5(tester);
      expect(find.text('兑换账户'), findsOneWidget); // 选择器标题
      await tester.tap(find.text('现金'));
      expect(await pollText(tester, '已生成支出流水并归档心愿'), isTrue);
      await clearToasts(tester);
      // 归档：进入已实现分组
      expect(find.text('已实现'), findsOneWidget);
      // 落库：expense / 购物(103) / source=wish / 金额=1000
      final rows = await db.query(
          DbSchema.tLedgerTxns, where: "source = 'wish'");
      expect(rows.single['kind'], 'expense');
      expect(rows.single['cat_id'], 103);
      expect((rows.single['amt']! as num).toDouble(), 1000.0);
      expect((await repo.wishes(1)).single.done, isTrue);
      final acct = await db.query(
          DbSchema.tLedgerAccounts, where: 'id = 1', limit: 1);
      expect((acct.single['balance_cache']! as num).toDouble(), -1000.0);
    });
  });

  group('6 · 删除', () {
    testWidgets('点垃圾桶删除心愿（原型无确认）', (tester) async {
      await useSurface(tester);
      await mkWish('相机', 1000);
      await pump(tester);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await settle5(tester);
      expect(find.text('相机'), findsNothing);
      expect(await repo.wishes(1), isEmpty);
    });
  });

  group('7 · 编辑（卡片点按回显 + 保存）', () {
    testWidgets('点卡片开编辑：回显 + 改目标落库', (tester) async {
      await useSurface(tester);
      await mkWish('相机', 1000);
      await pump(tester);
      await tester.tap(find.text('相机'));
      await settle5(tester);
      expect(find.text('编辑心愿'), findsOneWidget);
      // 回显芯片与卡片副标题同为「目标 ¥1,000.00」→ 用 .last 命中表单芯片。
      expect(find.text('目标 ¥1,000.00'), findsWidgets);
      // 编辑态滚轮起始=当前 1000，正向下移 4 格（136px）→ 600。
      await tester.tap(find.text('目标 ¥1,000.00').last);
      await settle5(tester);
      expect(find.byType(CupertinoPicker), findsOneWidget);
      await tester.drag(find.byType(CupertinoPicker), const Offset(0, 136));
      await settle5(tester);
      await tester.tap(find.text('确定'));
      await settle5(tester);
      await tester.tap(find.text('保存'));
      await settle5(tester);
      expect((await repo.wishes(1)).single.target, 600.0);
    });
  });
}
