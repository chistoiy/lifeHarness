import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_providers.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_search_page.dart';

/// 记账批3b · L12 搜索页 widget 用例（原型 p-txSearch 1064~1073 / fsPanel 控件 /
/// fsRun 即时 AND / fsStat 合计 / 标签单选切换 / fsReset / 空态 / 双账本回归 /
/// 隐藏金额开关）。手法照前批（sqflite ffi 真库 + ProviderContainer 覆盖 repo）。
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

  /// bk1 种子流水：t1 餐饮¥30·报销 / t2 工资¥8000 / t3 交通¥50·出差 /
  /// t4 adjust（kind 白名单外）；另 bk2 一笔「奶粉」。
  Future<void> seed({bool bk2 = true}) async {
    Future<void> add(LedgerTxn Function() f) => repo.addTxn(f());
    await add(() => LedgerTxn(
        kind: 'expense', amt: 30, catId: 101, accountId: 1,
        date: '2026-09-10', note: '午餐', tags: ['报销'], bk: 1));
    await add(() => LedgerTxn(
        kind: 'income', amt: 8000, catId: 201, accountId: 1,
        date: '2026-09-05', note: '工资', bk: 1));
    await add(() => LedgerTxn(
        kind: 'expense', amt: 50, catId: 102, accountId: 1,
        date: '2026-09-12', note: '打车', tags: ['出差'], bk: 1));
    await add(() => LedgerTxn(
        kind: 'adjust', amt: -20, accountId: 1,
        date: '2026-09-11', note: '余额调整', bk: 1));
    if (bk2) {
      final b2 = await repo.addBook('宝宝账本');
      await add(() => LedgerTxn(
          kind: 'expense', amt: 200, catId: 101, accountId: 1,
          date: '2026-09-09', note: '奶粉', bk: b2));
    }
  }

  Future<void> pump(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [ledgerRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LedgerSearchPage()),
      ),
    );
    await settle5(tester);
  }

  Future<void> type(WidgetTester tester, String key, String text) async {
    await tester.enterText(find.byKey(ValueKey(key)), text);
    await settle5(tester);
  }

  const statAll = '共 3 条 · 支出 ¥80.00 · 收入 ¥8,000.00';

  group('1 · 骨架（控件清单逐元素对照原型）', () {
    testWidgets('标题/关键词框/重置/四行条件/合计/标签 chips', (tester) async {
      await useSurface(tester);
      await seed();
      await pump(tester);
      expect(find.text('搜索流水'), findsOneWidget);
      expect(find.text('多条件组合过滤'), findsOneWidget);
      expect(find.text('备注 / 商户名'), findsOneWidget); // hint 5342/1067
      expect(find.text('重置'), findsOneWidget);
      expect(find.text('金额'), findsOneWidget);
      expect(find.text('最低'), findsOneWidget);
      expect(find.text('最高'), findsOneWidget);
      expect(find.text('分类'), findsWidgets); // 行标签 + 分类行文本
      expect(find.text('全部分类'), findsOneWidget);
      expect(find.text('账户'), findsOneWidget);
      expect(find.text('全部账户'), findsOneWidget);
      expect(find.text('日期'), findsOneWidget);
      expect(find.text('开始日期'), findsOneWidget);
      expect(find.text('结束日期'), findsOneWidget);
      expect(find.text('标签'), findsOneWidget);
      expect(find.byKey(const ValueKey('tag-报销')), findsOneWidget);
      expect(find.byKey(const ValueKey('tag-必要')), findsOneWidget);
      // 合计（fsRun 5353 逐字）+ 结果行（adjust 不进 · 他账本不进）
      expect(find.text(statAll), findsOneWidget);
      expect(find.text('午餐'), findsOneWidget);
      // 收入行：标题备注=分类名「工资」，行内出现两处（标题+类目副行）
      expect(find.text('工资'), findsNWidgets(2));
      expect(find.text('打车'), findsOneWidget);
      expect(find.text('余额调整'), findsNothing);
      expect(find.text('奶粉'), findsNothing);
    });
  });

  group('2 · 即时 AND 过滤', () {
    testWidgets('关键词命中 → 合计实时；无命中 → 空态逐字', (tester) async {
      await useSurface(tester);
      await seed();
      await pump(tester);
      await type(tester, 'fsKw', '午餐');
      expect(find.text('共 1 条 · 支出 ¥30.00 · 收入 ¥0.00'), findsOneWidget);
      expect(find.text('打车'), findsNothing);
      await type(tester, 'fsKw', 'zz不存在');
      expect(find.text('没有符合条件的流水'), findsOneWidget);
      expect(find.text('共 0 条 · 支出 ¥0.00 · 收入 ¥0.00'), findsOneWidget);
    });

    testWidgets('最低金额 100：剔 30/50 支出、收入 8000 保留（abs 口径）',
        (tester) async {
      await useSurface(tester);
      await seed();
      await pump(tester);
      await type(tester, 'fsMin', '100');
      expect(find.text('共 1 条 · 支出 ¥0.00 · 收入 ¥8,000.00'), findsOneWidget);
    });

    testWidgets('分类下拉（餐饮）+ 关键词 AND 交集', (tester) async {
      await useSurface(tester);
      await seed();
      await pump(tester);
      await tester.tap(find.text('全部分类'));
      await settle5(tester);
      await tester.tap(find.text('餐饮').last); // overlay 项（后入树）
      await settle5(tester);
      expect(find.text('共 1 条 · 支出 ¥30.00 · 收入 ¥0.00'), findsOneWidget);
      await type(tester, 'fsKw', 'zz');
      expect(find.text('没有符合条件的流水'), findsOneWidget);
    });

    testWidgets('日期条件：点开始日期弹滚轮 S2 · 取消不改结果', (tester) async {
      await useSurface(tester);
      await seed();
      await pump(tester);
      await tester.tap(find.text('开始日期'));
      await settle5(tester);
      expect(find.text('选择日期'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await settle5(tester);
      expect(find.text(statAll), findsOneWidget);
    });
  });

  group('3 · 标签单选切换（5339 · §4「标签单选切换」）', () {
    testWidgets('选中报销→切出差→再点取消', (tester) async {
      await useSurface(tester);
      await seed();
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('tag-报销')));
      await settle5(tester);
      expect(find.text('共 1 条 · 支出 ¥30.00 · 收入 ¥0.00'), findsOneWidget);
      // 再点另一标签 = 单选切换（非多选叠加）
      await tester.tap(find.byKey(const ValueKey('tag-出差')));
      await settle5(tester);
      expect(find.text('共 1 条 · 支出 ¥50.00 · 收入 ¥0.00'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tag-出差')));
      await settle5(tester);
      expect(find.text(statAll), findsOneWidget);
    });
  });

  group('4 · 重置（fsReset 5355）', () {
    testWidgets('多条件后重置：全清空回全量', (tester) async {
      await useSurface(tester);
      await seed();
      await pump(tester);
      await type(tester, 'fsKw', '午餐');
      await type(tester, 'fsMin', '10');
      await tester.tap(find.byKey(const ValueKey('tag-报销')));
      await settle5(tester);
      await tester.tap(find.text('重置'));
      await settle5(tester);
      expect(find.text(statAll), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('fsKw')))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('fsMin')))
            .controller!
            .text,
        isEmpty,
      );
    });
  });

  group('5 · 双账本回归（九·补1）与隐藏金额', () {
    testWidgets('他账本「奶粉」不进结果（关键词亦不穿账本）', (tester) async {
      await useSurface(tester);
      await seed();
      await pump(tester);
      await type(tester, 'fsKw', '奶粉');
      expect(find.text('没有符合条件的流水'), findsOneWidget);
    });

    testWidgets('隐藏金额开关生效（amtText ¥•••••）', (tester) async {
      await useSurface(tester);
      await seed();
      await repo.setHideAmounts(true);
      await pump(tester);
      expect(find.text('共 3 条 · 支出 ¥••••• · 收入 ¥•••••'), findsOneWidget);
    });
  });
}
