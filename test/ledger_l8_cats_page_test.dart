import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/domain/ledger_calc.dart';
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_cats_page.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_providers.dart';

/// 记账批2d · L8 分类管理页用例（renderLcats V2 全渲染 / 收支标题切换 /
/// 搜索·菜单·常用类别 toast 逐字 / ＋大类新增与编辑（复用 S3 showLCatSheet）/
/// 子分类改名同步 / 星标收藏 / 隐藏-恢复 / 删除两段守卫与兜底不可删 / ↑↓ 排序）。
/// 长按拖动=ReorderableListView 原型 drag 的 Flutter 等价物（用例走 ↑↓ 同持久化路径）。
/// 独立文件防 isolate 污染。
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
        child: const MaterialApp(home: LedgerCatsPage()),
      ),
    );
    await settle5(tester);
  }

  group('1 · 全渲染 + toast 占位', () {
    testWidgets('标题/常用类别卡/左栏大类/右栏子分类/＋大类/＋子分类', (tester) async {
      await useSurface(tester);
      await pump(tester);
      expect(find.text('分类管理'), findsOneWidget);
      expect(find.text('两级分类 · 图标与颜色'), findsOneWidget);
      expect(find.text('支出分类管理'), findsOneWidget);
      expect(find.text('常用类别'), findsOneWidget);
      expect(find.text('0'), findsOneWidget); // favCount（种子无收藏）
      for (final m in ['餐饮', '交通', '购物', '娱乐']) {
        expect(find.text(m), findsWidgets, reason: '左栏+右栏头 $m');
      }
      for (final s in ['早餐', '午餐', '晚餐']) {
        expect(find.text(s), findsOneWidget);
      }
      expect(find.text('＋ 大类'), findsOneWidget);
      expect(find.text('＋ 子分类'), findsOneWidget);
    });

    testWidgets('搜索/常用类别/菜单 toast 逐字 + 点标题切收入', (tester) async {
      await useSurface(tester);
      await pump(tester);
      await tester.tap(find.byTooltip('搜索'));
      expect(await pollText(tester, '搜索分类（模拟）'), isTrue);
      await clearToasts(tester);
      await tester.tap(find.text('常用类别'));
      expect(
          await pollText(tester, '常用类别 = 星标收藏的子分类 · 显示在记一笔快捷行'), isTrue);
      await clearToasts(tester);
      await tester.tap(find.byTooltip('菜单'));
      expect(await pollText(tester, '收入/支出切换 · 点标题「支出」处切换'), isTrue);
      await clearToasts(tester);
      // 点标题切换收支树（catMgmtTitle 语义）
      await tester.tap(find.text('支出分类管理'));
      await settle5(tester);
      expect(find.text('收入分类管理'), findsOneWidget);
      expect(find.text('工资'), findsWidgets);
      expect(find.text('餐饮'), findsNothing);
    });
  });

  group('2 · 新增/编辑大类（复用 S3 showLCatSheet，无第二套表单）', () {
    testWidgets('空名称保存→字段旁行内红字（T9·弹层内不借道提示条）',
        (tester) async {
      await useSurface(tester);
      await pump(tester);
      await tester.tap(find.text('＋ 大类'));
      await settle5(tester);
      expect(find.text('新增'), findsOneWidget);
      await tester.tap(find.byTooltip('保存'));
      await settle5(tester);
      expect(tester.widget<TextField>(find.byType(TextField))
          .decoration!
          .errorText, '请输入类别名称');
      expect(find.byType(SnackBar), findsNothing);
      // 输入即撤错（弹层保持打开）。报错行使输入框变高，
      // 对着可编辑区（EditableText）聚焦才点得准。
      await tester.enterText(find.byType(EditableText), '养猫');
      await settle5(tester);
      expect(tester.widget<TextField>(find.byType(TextField))
          .decoration!
          .errorText, isNull);
      expect(find.text('新增'), findsOneWidget);
    });

    testWidgets('＋ 大类 → 输入 → 保存 → toast 与左栏出现；编辑改名', (tester) async {
      await useSurface(tester);
      await pump(tester);
      await tester.tap(find.text('＋ 大类'));
      await settle5(tester);
      expect(find.text('新增'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '养猫');
      await tester.tap(find.byTooltip('保存'));
      expect(await pollText(tester, '已新建大类「养猫」'), isTrue);
      await clearToasts(tester);
      expect(find.text('养猫'), findsWidgets);
      final id =
          (await repo.cats()).firstWhere((c) => c.name == '养猫').id;
      // 编辑（右栏头 edit 钮 → S3 编辑态）
      await tester.tap(find.text('养猫').first); // 选中该大类
      await settle5(tester);
      await tester.tap(find.byKey(ValueKey('major-edit-$id')));
      await settle5(tester);
      expect(find.text('编辑'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '猫主子');
      await tester.tap(find.byTooltip('保存'));
      expect(await pollText(tester, '已更新大类'), isTrue);
      await clearToasts(tester);
      expect((await repo.cats()).firstWhere((c) => c.id == id).name, '猫主子');
    });
  });

  group('3 · 子分类改名 / 星标收藏 / 删除（无确认，原型 delSub）', () {
    testWidgets('点名称 prompt 改名同步流水；星标计入常用类别', (tester) async {
      await useSurface(tester);
      await repo.addTxn(LedgerTxn(
          kind: LedgerTxn.kExpense,
          amt: 8,
          catId: 101,
          sub: '早餐',
          accountId: 1,
          date: today,
          bk: 1));
      await pump(tester);
      await tester.tap(find.text('早餐'));
      await settle5(tester);
      expect(find.text('子分类名称'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '早点');
      await tester.tap(find.text('确定'));
      await settle5(tester);
      expect(find.text('早点'), findsOneWidget);
      final rows = await db.query(DbSchema.tLedgerTxns, where: 'cat_id = 101');
      expect(rows.single['sub'], '早点'); // 流水同步（九·补1）
      // 星标收藏 → favCount=1 + 落库（钮按子分类 id 定位）
      await tester.tap(find.byKey(const ValueKey('fav-1011')));
      await settle5(tester);
      expect(find.text('1'), findsWidgets);
      expect(await repo.favs(), contains((101, '早点')));
      // 删除子分类（delSub：无确认无 toast，流水回落未细分）
      await tester.tap(find.byKey(ValueKey('sub-del-1011')));
      await settle5(tester);
      expect(find.text('早点'), findsNothing);
      final rows2 = await db.query(DbSchema.tLedgerTxns, where: 'cat_id = 101');
      expect(rows2.single['sub'], '');
    });
  });

  group('4 · 删除大类两段守卫（§4 文案逐字）', () {
    testWidgets('有流水：首次 armed toast → 再点迁移「其他」；兜底不可删', (tester) async {
      await useSurface(tester);
      await repo.addTxn(LedgerTxn(
          kind: LedgerTxn.kExpense,
          amt: 66,
          catId: 105,
          accountId: 1,
          date: today,
          bk: 1));
      await pump(tester);
      // 选中大类「娱乐」（左栏第 5 项，默认可见）
      await tester.tap(find.text('娱乐'));
      await settle5(tester);
      final del = find.byKey(const ValueKey('major-del-105'));
      await tester.tap(del);
      expect(
          await pollText(tester, '该分类下有 1 笔流水 · 再点删除并迁移至「其他」'), isTrue);
      await clearToasts(tester);
      await tester.tap(del);
      expect(await pollText(tester, '已删除并迁移流水至「其他」'), isTrue);
      await clearToasts(tester);
      expect(find.text('娱乐'), findsNothing);
      expect(await repo.catTxnCount(DbSchema.ledgerCatOtherExpense, 1), 1);
      // 兜底「其他」：滚动到左栏底部再点删除
      await tester.dragUntilVisible(
          find.byKey(const ValueKey('major-114')),
          find.byType(ReorderableListView).first,
          const Offset(0, -40));
      await tester.tap(find.byKey(const ValueKey('major-114')));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('major-del-114')));
      expect(await pollText(tester, '兜底分类不可删除'), isTrue);
      expect((await repo.cats()).any((c) => c.id == 114), isTrue);
    });

    testWidgets('无流水大类：直接删 toast「已删除分类」', (tester) async {
      await useSurface(tester);
      await pump(tester);
      await tester.tap(find.text('宠物'));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('major-del-112')));
      expect(await pollText(tester, '已删除分类'), isTrue);
      await settle5(tester);
      expect(find.text('宠物'), findsNothing);
    });
  });

  group('5 · 隐藏/恢复 + 排序（↑↓ 与长按拖拽同持久化路径）', () {
    testWidgets('隐藏钮 → 出左栏 + 已隐藏组点按恢复', (tester) async {
      await useSurface(tester);
      await pump(tester);
      await tester.tap(find.text('运动'));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('major-hide-106')));
      await settle5(tester);
      // 左栏出列（右栏头回落首个可见大类），已隐藏组出现同名恢复行。
      expect(find.byKey(const ValueKey('major-106')), findsNothing);
      expect(find.text('运动'), findsOneWidget); // 已隐藏组的恢复条目
      expect(find.text('已隐藏 1 项 · 点按恢复'), findsOneWidget);
      expect(
          (await repo.cats()).firstWhere((c) => c.id == 106).hidden, isTrue);
      await tester.tap(find.byKey(const ValueKey('restore-106')));
      expect(await pollText(tester, '已恢复「运动」'), isTrue);
      await clearToasts(tester);
      expect(find.byKey(const ValueKey('major-106')), findsOneWidget);
      expect(
          (await repo.cats()).firstWhere((c) => c.id == 106).hidden, isFalse);
    });

    testWidgets('↑↓ 移动大类顺序持久化（cats() 重取新序）', (tester) async {
      await useSurface(tester);
      await pump(tester);
      await tester.tap(find.text('交通'));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('major-up-102')));
      await settle5(tester);
      final majors = [
        for (final c in await repo.cats())
          if (c.isMajor && c.kind == 'expense') c.id,
      ];
      expect(majors.first, 102);
      // 子分类 ↓
      await tester.tap(find.text('餐饮'));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('sub-down-1011')));
      await settle5(tester);
      final subs = [
        for (final c in await repo.cats())
          if (c.parentId == 101) c.id,
      ];
      expect(subs.first, 1012);
    });
  });
}
