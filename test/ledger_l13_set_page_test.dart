import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/domain/ledger_models.dart';
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_providers.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_set_page.dart';

/// 记账批3c · L13 记账设置页 widget 用例（原型 renderLset 5358~5378 全 16 行
/// 逐字：文案/控件形态/分组顺序）。开关即写 DB settings（`ledger.` 前缀），
/// 以新 [LedgerRepository] 实例读回=重开 provider 持久化口径。
/// 管理入口行断言弹层管理态（角色/标签/商家=对应半屏 mg 态；速记/顶部卡=
/// 配置弹层）；跳转行（分类/导入/导出）以文案守护，路由 push 无 GoRouter 树
/// 不可点（真实化收口见 ledgerNav done 表 + app_router '/ledger/set'）。
/// 撤销导入批次：原型 p-lset 无该行（不造行）→ 仅 repo 语义数据层用例。
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
  tearDown(() async => db.close());

  Future<void> pump(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [ledgerRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LedgerSetPage()),
      ),
    );
    await settle5(tester);
  }

  /// 关闭当前半屏（点顶部遮罩；bottom sheet 无返回键）。
  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(400, 40));
    await settle5(tester);
  }

  List<Switch> switches(WidgetTester tester) =>
      tester.widgetList<Switch>(find.byType(Switch)).toList();

  group('1 · 骨架：16 行文案逐字 + 控件形态', () {
    testWidgets('标题/行标题/副文案/chip/分段/Switch 计数', (tester) async {
      await useSurface(tester);
      await pump(tester);
      expect(find.text('记账设置'), findsOneWidget); // TITLES ['记账设置','']
      // 行标题（原型 5362~5377 序）
      for (final t in [
        '隐藏全部金额',
        '默认记账账户',
        '记一笔保存后',
        '删除流水二次确认',
        '预算月起始日',
        '预算超支提醒',
        '月度小结推送',
        '导入支付宝 / 微信账单',
        '分类管理',
        '角色管理',
        '标签管理',
        '商家管理',
        '快速记一笔',
        '自定义顶部卡片',
        '数据导出',
        '重置演示数据',
      ]) {
        expect(find.text(t), findsOneWidget, reason: '行标题缺失：$t');
      }
      // 副文案（原型 row 第三参逐字）
      expect(find.text('仪表盘与资产页同步生效'), findsOneWidget);
      expect(
        find.text('记一笔「角色」半屏同源数据 · 当前默认「自己」'),
        findsOneWidget,
      );
      expect(find.text('主页快速记一笔宫格展示的分类'), findsOneWidget);
      expect(
        find.text(
          '四处均可从今日/本周/本月/本年收支结余 · 预算 · 资产等 '
          '24 项指标中任选',
        ),
        findsOneWidget,
      );
      // chip 文案（含 › 逐字）
      for (final c in [
        '五步向导 · 账户匹配 + 勾选导入 ›',
        '两级分类 · 排序改名 ›',
        '排序 · 改名 · 设默认 ›',
        '分组 + 标签 · 添加排序 ›',
        '添加 · 改名 · 删除 ›',
        '自定义 4 个入口 ›',
        '大数字 + 3 小槽 ›',
        'CSV · JSON ›',
        '重新载入',
      ]) {
        expect(find.text(c), findsOneWidget, reason: 'chip 缺失：$c');
      }
      // 默认账户 chip=当前值（种子首账户 现金；§7 defAcct 首账户）
      expect(find.text('现金'), findsOneWidget);
      // 分段选项
      for (final s in ['回流水页', '继续记录', '每月 1 日', '每月 15 日']) {
        expect(find.text(s), findsOneWidget);
      }
      // 开关=4（隐藏/删除确认/超支提醒/月度小结）
      expect(find.byType(Switch), findsNWidgets(4));
      // 撤销导入批次：原型 renderLset 无该行 → 页面不造行（取证断言）
      expect(find.textContaining('撤销'), findsNothing);
    });
  });

  group('2 · 开关即时生效并持久化（新 repo 实例读回）', () {
    testWidgets('隐藏全部金额：off→on toast 金额已隐藏 + kv 落库', (tester) async {
      await useSurface(tester);
      await pump(tester);
      await tester.tap(find.byType(Switch).first); // 行1 hideAmounts
      expect(await pollText(tester, '金额已隐藏'), isTrue);
      await clearToasts(tester);
      final fresh = LedgerRepository(db);
      expect(await fresh.hideAmounts(), isTrue);
      expect(await fresh.kv('ledger.hideAmounts'), 'true');
      // 再切回
      await tester.tap(find.byType(Switch).first);
      expect(await pollText(tester, '金额已显示'), isTrue);
      await clearToasts(tester);
      expect(await fresh.hideAmounts(), isFalse);
    });

    testWidgets('删除二次确认：默认开（§7 confirmDel true）→ 关', (tester) async {
      await useSurface(tester);
      await pump(tester);
      expect(switches(tester)[1].value, isTrue);
      await tester.tap(find.byType(Switch).at(1));
      await settle5(tester);
      expect(await LedgerRepository(db).confirmDel(), isFalse);
    });

    testWidgets('超支提醒/月度小结：§7 默认 true/false + toast 逐字（演示）',
        (tester) async {
      await useSurface(tester);
      await pump(tester);
      expect(switches(tester)[2].value, isTrue); // budgetAlert 默认 true
      await tester.tap(find.byType(Switch).at(2));
      expect(
        await pollText(tester, '超支 80% / 100% 两档本地通知（演示）'),
        isTrue,
      );
      await clearToasts(tester);
      final fresh = LedgerRepository(db);
      expect(await fresh.budgetAlert(), isFalse);

      expect(switches(tester)[3].value, isFalse); // monthlyDigest 默认 false
      await tester.tap(find.byType(Switch).at(3));
      expect(
        await pollText(tester, '每月 1 日 09:00 本地推送（演示）'),
        isTrue,
      );
      await clearToasts(tester);
      expect(await fresh.monthlyDigest(), isTrue);
    });
  });

  group('3 · 默认记账账户（openLedgerAcctPick → setDefAcct + toast）', () {
    testWidgets('chip 弹账户半屏 → 选储蓄卡 → 默认账户已切换 + 键值读回',
        (tester) async {
      await useSurface(tester);
      final id = await repo.addAccount(
        const LedgerAccount(type: LedgerAccount.kDebit, name: '储蓄卡'),
      );
      await pump(tester);
      await tester.tap(find.text('现金'));
      await settle5(tester);
      expect(find.text('选择账户'), findsOneWidget); // 原型默认标题
      await tester.tap(find.text('储蓄卡').last);
      expect(await pollText(tester, '默认账户已切换'), isTrue);
      await clearToasts(tester);
      expect(await LedgerRepository(db).defAcctId(), id);
      expect(find.text('储蓄卡'), findsOneWidget); // chip 当前值即时更新
    });
  });

  group('4 · 分段选择落键（L2/L5 行为按键读取，本批只断键值）', () {
    testWidgets('afterSave=stay/back', (tester) async {
      await useSurface(tester);
      await pump(tester);
      await tester.tap(find.text('继续记录'));
      await settle5(tester);
      expect(await LedgerRepository(db).afterSave(), 'stay');
      await tester.tap(find.text('回流水页'));
      await settle5(tester);
      expect(await LedgerRepository(db).afterSave(), 'back');
    });

    testWidgets('monthStart 15 → toast 逐字；回 1 无 toast', (tester) async {
      await useSurface(tester);
      await pump(tester);
      await tester.tap(find.text('每月 15 日'));
      expect(
        await pollText(tester, '预算与日均分配将按 15 日周期重算（演示）'),
        isTrue,
      );
      await clearToasts(tester);
      expect(await LedgerRepository(db).monthStart(), 15);
      await tester.tap(find.text('每月 1 日'));
      await settle5(tester);
      expect(find.byType(SnackBar), findsNothing); // 选 1 原型不弹 toast
      expect(await LedgerRepository(db).monthStart(), 1);
    });
  });

  group('5 · 管理入口=对应弹层管理态（九·补5 设置页行是管理态入口）', () {
    testWidgets('角色：mg 开启（设默认/改名/删 直显）', (tester) async {
      await useSurface(tester);
      await pump(tester);
      await tester.tap(find.text('排序 · 改名 · 设默认 ›'));
      await settle5(tester);
      expect(find.text('角色'), findsOneWidget);
      expect(find.text('设默认'), findsWidgets); // mg 态即渲染管理钮
      await closeSheet(tester);
      expect(find.text('角色'), findsNothing);
    });

    testWidgets('标签：mg 开启（＋ 新分组/删组 直显）', (tester) async {
      await useSurface(tester);
      await pump(tester);
      await tester.tap(find.text('分组 + 标签 · 添加排序 ›'));
      await settle5(tester);
      expect(find.text('标签'), findsOneWidget);
      expect(find.text('＋ 新分组'), findsOneWidget);
      await closeSheet(tester);
      expect(find.text('标签'), findsNothing);
    });

    testWidgets('商家：mg 开启（添加行直显）', (tester) async {
      await useSurface(tester);
      await pump(tester);
      await tester.tap(find.text('添加 · 改名 · 删除 ›'));
      await settle5(tester);
      expect(find.text('商家'), findsOneWidget);
      expect(find.text('无商家'), findsOneWidget);
      expect(find.text('＋ 添加商家'), findsOneWidget);
      await closeSheet(tester);
      expect(find.text('商家'), findsNothing);
    });

    testWidgets('顶部卡：复用 S12 草稿制配置弹层', (tester) async {
      await useSurface(tester);
      await pump(tester);
      await tester.tap(find.text('大数字 + 3 小槽 ›'));
      await settle5(tester);
      // 行标题 + 弹层头同名（13/15px）：叠显即弹层已开
      expect(find.text('自定义顶部卡片'), findsNWidgets(2));
      expect(find.text('预览 · 实时反映草稿'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await settle5(tester);
      expect(find.text('预览 · 实时反映草稿'), findsNothing);
    });

    testWidgets('跳转行（分类/导入/导出）=文案守护，不路由不点', (tester) async {
      await useSurface(tester);
      await pump(tester);
      expect(find.text('两级分类 · 排序改名 ›'), findsOneWidget);
      expect(find.text('五步向导 · 账户匹配 + 勾选导入 ›'), findsOneWidget);
      expect(find.text('CSV · JSON ›'), findsOneWidget);
    });
  });

  group('6 · 快速记一笔配置（sheetLedgerQuick · 即时落库 + 1~4 守卫）', () {
    testWidgets('已选计数/守卫 toast/落库 quick_cats', (tester) async {
      await useSurface(tester);
      await pump(tester);
      await tester.tap(find.text('自定义 4 个入口 ›'));
      await settle5(tester);
      expect(find.text('快速记一笔入口'), findsOneWidget);
      expect(find.text('已选 4 / 4'), findsOneWidget);
      expect(find.text('点选切换 · 最多 4 个 · 主页快速记一笔按此渲染'), findsOneWidget);
      // 满 4 再点未选格 → 守卫 toast
      await tester.tap(find.text('娱乐'));
      expect(await pollText(tester, '最多 4 个快捷入口'), isTrue);
      await clearToasts(tester);
      // 移除 餐饮 → 3/4
      await tester.tap(find.text('餐饮'));
      await settle5(tester);
      expect(find.text('已选 3 / 4'), findsOneWidget);
      // 逐个移空至 1（交通/购物）再点最后一个（居住）→ 至少 1 守卫
      await tester.tap(find.text('交通'));
      await settle5(tester);
      await tester.tap(find.text('购物'));
      await settle5(tester);
      expect(find.text('已选 1 / 4'), findsOneWidget);
      await tester.tap(find.text('居住'));
      expect(await pollText(tester, '至少保留 1 个快捷入口'), isTrue);
      await clearToasts(tester);
      final fresh = LedgerRepository(db);
      expect(await fresh.quickCats(), [104]); // 仅剩 居住（末位不可再移）
      // 即时落库：主页宫格随 tick 联动（键值层断言即持久化读回）
      expect(await fresh.kv('ledger.quick'), '[104]');
    });
  });

  group('7 · 重置演示数据（原型 location.reload → 真实版=重新载入）', () {
    testWidgets('点重新载入不崩（数据重取，无清库）', (tester) async {
      await useSurface(tester);
      await pump(tester);
      await tester.tap(find.text('重新载入'));
      await settle5(tester);
      expect(find.text('记账设置'), findsOneWidget);
      expect(find.text('重置演示数据'), findsOneWidget);
      // 重载不改任何键
      expect(await LedgerRepository(db).hideAmounts(), isFalse);
    });
  });

  group('8 · 撤销导入批次（repo 既有语义 · 原型无 UI 行取证）', () {
    test('commitImport 造批次 → undoImportBatch → 流水消失+账户回收', () async {
      final res = await repo.commitImport(
        bk: 1,
        platform: '支付宝',
        fileName: 'alipay_record_202608.csv',
        newAccounts: const [
          LedgerAccount(type: LedgerAccount.kEwallet, name: '支付宝'),
        ],
        rows: [
          ImportRowSpec(
            LedgerTxn(
              kind: LedgerTxn.kExpense,
              amt: 12,
              catId: 101,
              accountId: 0, // 占位：commitImport 按 newAcctIndex 覆写
              date: '2026-09-01',
              source: LedgerTxn.kSourceBill,
              billHash: 'B1',
              bk: 1,
            ),
            newAcctIndex: 0,
          ),
          ImportRowSpec(
            LedgerTxn(
              kind: LedgerTxn.kExpense,
              amt: 30,
              catId: 101,
              accountId: 0,
              date: '2026-09-02',
              source: LedgerTxn.kSourceBill,
              billHash: 'B2',
              bk: 1,
            ),
            newAcctIndex: 0,
          ),
        ],
      );
      expect(res.written, 2);
      expect(await repo.importBatches(), hasLength(1));
      expect(await repo.bookTxns(1), hasLength(2));
      final deleted = await repo.undoImportBatch(
        res.batchId,
        reclaimAccounts: true,
      );
      final fresh = LedgerRepository(db);
      expect(deleted, 2);
      expect(await fresh.bookTxns(1), isEmpty);
      expect(await fresh.importBatches(), isEmpty);
      // 本批新建账户已无引用且 base=0 → 回收（现金种子账户保留）
      expect((await fresh.accounts()).map((a) => a.name), ['现金']);
    });
  });
}
