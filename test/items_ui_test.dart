import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/items/data/items_repository.dart';
import 'package:lifeharness/features/items/domain/item_models.dart';
import 'package:lifeharness/features/items/presentation/item_detail_page.dart';
import 'package:lifeharness/features/items/presentation/items_page.dart';
import 'package:lifeharness/features/items/presentation/items_providers.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_providers.dart';

/// 批2 · 物品六屏 UI（原型 P7 系对译断言 · HG-E1 全实算）。
/// 独立文件防 isolate 污染；固定钟 2026-09-19（itemsClockProvider 缝）。
/// ledgerRepositoryProvider 覆盖同一 ffi 库（createStatements 已播种
/// 账本/账户/购物分类），断言 L12 联动流水行数。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 19);
  late Database db;
  late ItemsRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    // v21 物品三表在 migrations[20]（createStatements 未含）：测试同 App 升级路径补齐。
    for (final sql in DbSchema.itemSchemaStatements) {
      await db.execute(sql);
    }
    repo = ItemsRepository(db);
  });

  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, Widget home) async {
    final container = ProviderContainer(overrides: [
      itemsRepositoryProvider.overrideWithValue(repo),
      ledgerRepositoryProvider.overrideWithValue(LedgerRepository(db)),
      itemsClockProvider.overrideWithValue(() => now),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: MaterialApp(home: home)));
    await settle5(tester);
  }

  Future<bool> pollContains(WidgetTester tester, String part) async {
    for (var i = 0; i < 15; i++) {
      if (find.textContaining(part).evaluate().isNotEmpty) return true;
      await tester.pump(const Duration(milliseconds: 80));
    }
    return find.textContaining(part).evaluate().isNotEmpty;
  }

  /// 原型样本 MacBook：9999 + 399 + 156 = 池 10554 · 556 天 → ¥18.98/天
  Future<int> seedMacbook() async {
    final id = await repo.addItem(const ItemProfile(
        name: 'MacBook Air M3',
        category: '数码',
        buyDate: '2025-03-12',
        price: 9999,
        warranty: '2026-03-12'));
    await repo.addExtraPay(id, 399, 'Type-C 扩展坞', date: '2025-06-02');
    await repo.addExtraPay(id, 156, '官方换电池（补差）', date: '2026-01-20');
    return id;
  }

  /// 原型样本 Nike 跑鞋：899 ÷ 300 次 × 近30天45次 → ¥4.50/天
  Future<int> seedShoes() async {
    final id = await repo.addItem(const ItemProfile(
        name: 'Nike 跑鞋',
        category: '服饰',
        buyDate: '2026-08-18',
        price: 899,
        mode: ItemMode.times,
        planUnits: 300,
        unit: '次'));
    await repo.addUsage(id, '2026-08-25', 20);
    await repo.addUsage(id, '2026-09-10', 25);
    return id;
  }

  Future<int> seedMonitor() => repo.addItem(const ItemProfile(
      name: '旧显示器',
      category: '数码',
      buyDate: '2023-05-30',
      price: 1499));

  Future<int> seedCamera() => repo.addItem(const ItemProfile(
      name: '相机镜头 35mm',
      category: '数码',
      buyDate: '2025-04-22',
      price: 1299,
      expectedYears: 5,
      status: '闲置',
      mode: ItemMode.stop,
      stopPct: 30));

  Future<void> openDetail(WidgetTester tester, int id) async {
    await pump(tester, const ItemsPage());
    await tester.tap(find.byKey(ValueKey('i-item-row-$id')));
    await settle5(tester);
  }

  group('P7 列表屏', () {
    testWidgets('hero 实算合计 ¥23.48 + 状态计数 + Top3 + seg 过滤',
        (tester) async {
      await useSurface(tester);
      final macId = await seedMacbook();
      final shoeId = await seedShoes();
      await pump(tester, const ItemsPage());

      // 今日合计持有成本（ΣcostPerDay 实算：18.98 + 4.50）
      expect(find.text('¥ 23.48'), findsOneWidget);
      expect(find.text('成本统计 ›'), findsOneWidget);
      // 四状态计数
      expect(find.text('使用中 2'), findsOneWidget);
      expect(find.text('闲置 0'), findsOneWidget);
      // 本月它花掉了你：Top3（costPerDay×30 取整）
      expect(find.textContaining('本月它花掉了你：MacBook ¥569 · Nike ¥135'),
          findsOneWidget);
      // 行右列日均 + meta 实算
      expect(find.text('¥18.98'), findsOneWidget);
      expect(find.text('¥4.50'), findsOneWidget);
      expect(find.textContaining('持有 556 天 · 成本池 ¥10,554 · 使用中'),
          findsOneWidget);

      // seg 分类过滤（计数徽标同 days 式样）
      expect(find.text('数码 1'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('i-cat-服饰')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('i-item-row-$shoeId')), findsOneWidget);
      expect(find.byKey(ValueKey('i-item-row-$macId')), findsNothing);

      // 点行 → 详情
      await tester.tap(find.byKey(const ValueKey('i-cat-全部')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('i-item-row-$macId')));
      await settle5(tester);
      expect(find.text('物品详情'), findsOneWidget);
    });

    testWidgets('两入口：录入全屏表单 / 升级弹层列表', (tester) async {
      await useSurface(tester);
      await db.insert(DbSchema.tLedgerTxns, {
        'kind': 'expense', 'amt': 899.0, 'cat_id': 103, 'account_id': 1,
        'date': '2026-09-15', 'note': '机械键盘', 'source': 'manual', 'bk': 1, 'created_at': 0,
      });
      await pump(tester, const ItemsPage());
      // 升级候选弹层
      await tester.tap(find.byKey(const ValueKey('i-from-ledger')));
      expect(await pollContains(tester, '机械键盘 −¥899'), isTrue);
      await settle5(tester); // 等弹层滑入动画结束
      await tester.ensureVisible(find.byKey(const ValueKey('i-upgrade-row-1')));
      await tester.tap(find.byKey(const ValueKey('i-upgrade-row-1')));
      await settle5(tester);
      // 全屏表单预填（HG-H1 同表单单版本）
      expect(find.text('录入物品'), findsOneWidget);
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('i-edit-name')))
              .controller!
              .text,
          '机械键盘');
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('i-edit-price')))
              .controller!
              .text,
          '899');
    });
  });

  group('P7a 详情屏', () {
    testWidgets('hero 日均 + 摊薄曲线 + 公式行 + 时间轴 + 保修关联 toast',
        (tester) async {
      await useSurface(tester);
      final id = await seedMacbook();
      await openDetail(tester, id);
      expect(find.text('¥18.98'), findsOneWidget); // hero 大数字
      expect(find.byKey(const ValueKey('i-detail-curve')), findsOneWidget);
      expect(find.textContaining('持有 556 天'), findsWidgets);
      expect(
          find.textContaining(
              '购入价 ¥9,999 ＋ 二次付费 ¥555 － 回收残值 ¥0 ＝ 成本池 ÷ 556 天'),
          findsOneWidget);
      // 时间轴（仅追加）三事件
      expect(find.textContaining('+¥399 二次付费：Type-C 扩展坞'), findsOneWidget);
      expect(find.textContaining('时间轴仅追加不删除'), findsOneWidget);
      // 状态 chip + 冻结无决算入口
      expect(find.textContaining('● 使用中 · 计费中'), findsOneWidget);
      expect(find.byKey(const ValueKey('i-detail-settle')), findsNothing);
      // 保修关联：无 go_router 环境 → toast 登记差异
      await tester.tap(find.byKey(const ValueKey('i-link-remind')));
      expect(await pollContains(tester, '保修提醒已汇入提醒中心'), isTrue);
    });

    testWidgets('times 双口径卡 + stop 止损卡 + 闲置建议回收', (tester) async {
      await useSurface(tester);
      final shoeId = await seedShoes();
      final camId = await seedCamera();
      await openDetail(tester, shoeId);
      expect(find.text('按次均摊口径'), findsOneWidget);
      expect(find.textContaining('每次成本 ＝ 成本池 ÷ 计划 300 次'), findsOneWidget);
      expect(find.text('¥3.00'), findsOneWidget); // 899÷300 → 展示 3.00
      expect(find.textContaining('已用 45/300'), findsOneWidget);
      expect(find.textContaining('近 30 天 45 次'), findsOneWidget);
      expect(find.textContaining('双口径并列'), findsOneWidget);

      await tester.pageBack();
      await settle5(tester);
      await openDetail(tester, camId);
      expect(find.text('预估止损'), findsOneWidget);
      // net=1299×(1-515/1825)≈¥932 · line=¥390 · 触线 2028-10-21
      expect(find.text('¥932'), findsOneWidget);
      expect(find.textContaining('止损线 ¥390'), findsOneWidget);
      expect(find.textContaining('预估触线 2028-10-21'), findsOneWidget);
      expect(find.textContaining('跌破止损线前择机回收'), findsOneWidget);
      // 闲置：列表行「建议回收」+ 状态 chip
      expect(find.textContaining('● 闲置 · 计费中'), findsOneWidget);
    });
  });

  group('生命周期全联动（item_mounts 写路径）', () {
    testWidgets('sheetExtra 录 200 → toast 复述前后日均 + 流水 +1',
        (tester) async {
      await useSurface(tester);
      final id = await seedMacbook();
      await openDetail(tester, id);
      await tester.tap(find.byKey(const ValueKey('i-life-extra')));
      await settle5(tester);
      await tester.enterText(
          find.byKey(const ValueKey('i-extra-amt')), '200');
      await tester.enterText(
          find.byKey(const ValueKey('i-extra-desc')), '屏幕换膜');
      // HG-D3 固定预览区（口径预览）
      expect(find.textContaining('摊回全周期 · 日均立即回升'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('i-extra-save')));
      // 10554→10754 ÷556：¥18.98 → ¥19.34（逐字实算）
      expect(await pollContains(tester, '已计入成本池 ✓ 日均 ¥18.98 → ¥19.34'),
          isTrue);
      await settle5(tester);
      expect(find.text('¥19.34'), findsOneWidget); // 页面全联动重算
      expect(find.textContaining('+¥200 二次付费：屏幕换膜'), findsOneWidget);
      // 联动 L12：建档 1 + 原二次付费 2（seed 直写 repo 不产流水）→ 此处仅本笔
      final txns = await db.query(DbSchema.tLedgerTxns,
          where: "source = 'item'");
      expect(txns.length, 1);
      expect(txns.single['note'], '物品养护：MacBook Air M3 · 屏幕换膜');
    });

    testWidgets('recycle 金额必填 + 默认转出 → 跳决算冻结 + 收入流水',
        (tester) async {
      await useSurface(tester);
      final id = await seedMacbook();
      await openDetail(tester, id);
      await tester.tap(find.byKey(const ValueKey('i-life-recycle')));
      await settle5(tester);
      // 默认选中「已转出」
      await tester.tap(find.byKey(const ValueKey('i-recycle-save')));
      expect(await pollContains(tester, '先填写回收金额'), isTrue);
      await clearToasts(tester);
      await tester.enterText(
          find.byKey(const ValueKey('i-recycle-amt')), '4200');
      await tester.tap(find.byKey(const ValueKey('i-recycle-save')));
      // 10554−4200=6354
      expect(await pollContains(tester, '决算单已生成 · 净持有 ¥6,354'), isTrue);
      await settle5(tester);
      // 自动进决算屏：六值 + 冻结徽标
      expect(find.text('决算报告'), findsOneWidget);
      expect(find.textContaining('计费已停止 · 决算为最终口径'), findsOneWidget);
      expect(find.text('¥6,354'), findsWidgets); // 净持有成本格
      expect(find.text('¥11.43'), findsOneWidget); // 真实日均 6354÷556
      expect(find.textContaining('回收率 40%'), findsOneWidget);
      expect(find.textContaining('审计记录 4 条'), findsOneWidget);
      final it = (await repo.loadAll()).items.firstWhere((x) => x.id == id);
      expect(it.billing, isFalse);
      expect(it.status, kItemStatusRecycleOut);
      final income = await db.query(DbSchema.tLedgerTxns,
          where: "kind = 'income' AND source = 'item'");
      expect(income.length, 1);
      // 回到档案 → 详情页显「查看决算报告」入口卡替代 hero
      await tester.tap(find.byKey(const ValueKey('i-settle-back')));
      await settle5(tester);
      expect(find.byKey(const ValueKey('i-detail-settle')), findsOneWidget);
      expect(find.textContaining('● 已回收(转出) · 计费已停止'), findsOneWidget);
    });

    testWidgets('recycle 留用：billing 仍 1 · toast 日均重算', (tester) async {
      await useSurface(tester);
      final id = await seedMacbook();
      await openDetail(tester, id);
      await tester.tap(find.byKey(const ValueKey('i-life-recycle')));
      await settle5(tester);
      await tester.enterText(
          find.byKey(const ValueKey('i-recycle-amt')), '4200');
      await tester.tap(find.byKey(const ValueKey('i-recycle-keep')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('i-recycle-save')));
      expect(await pollContains(tester, '净值已下调 · 日均重算为 ¥11.43/天'), isTrue);
      await settle5(tester);
      final it = (await repo.loadAll()).items.firstWhere((x) => x.id == id);
      expect(it.billing, isTrue);
      expect(it.status, kItemStatusRecycleKeep);
      // 仍在计费：详情 hero 未替换
      expect(find.byKey(const ValueKey('i-detail-settle')), findsNothing);
    });

    testWidgets('scrap 两击确认：变文案 → 冻结 + 自动跳决算', (tester) async {
      await useSurface(tester);
      final id = await seedMonitor();
      await openDetail(tester, id);
      await tester.tap(find.byKey(const ValueKey('i-life-scrap')));
      await settle5(tester);
      // 第一击：文案变 + 警示 toast（HG-D2）
      await tester.tap(find.byKey(const ValueKey('i-scrap-confirm')));
      expect(await pollContains(tester, '二次确认：报废不可撤销 · 审计记录将保留'),
          isTrue);
      expect(find.text('再次点击 · 确认冻结决算'), findsOneWidget);
      await clearToasts(tester);
      // 选原因第二击：执行 → 决算屏
      await tester.tap(find.byKey(const ValueKey('i-scrap-reason-技术淘汰')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('i-scrap-confirm')));
      expect(await pollContains(tester, '已生成决算报告并归档 · 转入历史库'), isTrue);
      await settle5(tester);
      expect(find.text('决算报告'), findsOneWidget);
      expect(find.textContaining('已报废 · 2023-05-30 建档'), findsOneWidget);
      expect(find.text('¥1,499'), findsWidgets); // 净持有＝总投入（无回收）
      final it = (await repo.loadAll()).items.firstWhere((x) => x.id == id);
      expect(it.billing, isFalse);
      expect(it.events.last.kind, kEvScrap);
      expect(it.events.last.note, contains('原因：技术淘汰'));
      // 报废不生流水（联动 L12 口径：仅冻结决算）
      final txns = await db.query(DbSchema.tLedgerTxns,
          where: "source = 'item'");
      expect(txns, isEmpty);
      // 回详情 → 列表 → 历史分组显「已归档」
      await tester.tap(find.byKey(const ValueKey('i-settle-back')));
      await settle5(tester);
      await tester.pageBack();
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('i-cat-历史（决算）')));
      await tester.pumpAndSettle();
      expect(find.text('历史（决算） 1'), findsOneWidget);
      expect(find.text('已归档'), findsOneWidget);
      expect(find.textContaining('已归档 · 决算已冻结 · 点看决算单'), findsOneWidget);
    });
  });

  group('P7b 建档表单', () {
    testWidgets('校验拦截 + 新建落库 toast + 同步生成流水（联动 L12）',
        (tester) async {
      await useSurface(tester);
      await pump(tester, const ItemsPage());
      await tester.tap(find.byKey(const ValueKey('i-add-item')));
      await settle5(tester);
      // 校验：名称 / 价格
      await tester.tap(find.byKey(const ValueKey('i-edit-save')));
      expect(await pollContains(tester, '先填物品名称'), isTrue);
      await clearToasts(tester);
      await tester.enterText(
          find.byKey(const ValueKey('i-edit-name')), '机械键盘');
      await tester.tap(find.byKey(const ValueKey('i-edit-save')));
      expect(await pollContains(tester, '先填购入价格'), isTrue);
      await clearToasts(tester);
      await tester.enterText(
          find.byKey(const ValueKey('i-edit-price')), '899');
      // 购入日期默认＝itemsClock 今天 → daysHeld 至少 1 → 今日成本 ¥899
      expect(find.textContaining('购入日期 2026-09-19'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('i-edit-save')));
      await tester.tap(find.byKey(const ValueKey('i-edit-save')));
      expect(await pollContains(tester, '物品已建档 · 今日成本 ¥899 起计'), isTrue);
      await settle5(tester);
      final d = await repo.loadAll();
      final it = d.items.firstWhere((x) => x.name == '机械键盘');
      expect(it.source, 'manual');
      expect(it.events.first.kind, kEvBuy);
      // 同步流水：支出 · 购物(103) · 挂 source=item + link_id
      final txns = await db.query(DbSchema.tLedgerTxns,
          where: "source = 'item'");
      expect(txns.length, 1);
      expect(txns.single['amt'], 899.0);
      expect(txns.single['cat_id'], 103);
      expect(txns.single['link_id'], '${it.id}');
      // 列表 hero 更新（899/1 天 + 23.48? 本页只建键盘无其他条目）
      expect(find.textContaining('¥ 899'), findsOneWidget);
    });

    testWidgets('编辑冻结态：状态转已报废 → billingForStatus 冻结',
        (tester) async {
      await useSurface(tester);
      final id = await seedMonitor();
      await openDetail(tester, id);
      await tester.tap(find.byKey(const ValueKey('i-detail-edit')));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('i-edit-status-已报废')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('i-edit-save')));
      await tester.tap(find.byKey(const ValueKey('i-edit-save')));
      expect(await pollContains(tester, '档案已更新 · 日均已重算'), isTrue);
      await settle5(tester);
      final it = (await repo.loadAll()).items.firstWhere((x) => x.id == id);
      expect(it.billing, isFalse);
      expect(it.status, kItemStatusScrapped);
      // 回详情：冻结 → 决算入口卡
      expect(find.byKey(const ValueKey('i-detail-settle')), findsOneWidget);
    });

    testWidgets('升级建档：source=ledger · 流水不重复 · 挂来源徽标 · 详情时间轴注源',
        (tester) async {
      await useSurface(tester);
      final txnId = await db.insert(DbSchema.tLedgerTxns, {
        'kind': 'expense', 'amt': 899.0, 'cat_id': 103, 'account_id': 1,
        'date': '2026-08-18', 'note': 'Nike 跑鞋升级', 'source': 'manual', 'created_at': 0,
        'bk': 1,
      });
      await pump(tester, const ItemsPage());
      final txnsBefore =
          (await db.query(DbSchema.tLedgerTxns)).length;
      await tester.tap(find.byKey(const ValueKey('i-from-ledger')));
      expect(await pollContains(tester, 'Nike 跑鞋升级 −¥899'), isTrue);
      await settle5(tester); // 等弹层滑入动画结束
      await tester.ensureVisible(find.byKey(ValueKey('i-upgrade-row-$txnId')));
      await tester.tap(find.byKey(ValueKey('i-upgrade-row-$txnId')));
      await settle5(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('i-edit-save')));
      await tester.tap(find.byKey(const ValueKey('i-edit-save')));
      expect(await pollContains(tester, '物品已建档'), isTrue);
      await settle5(tester);
      final d = await repo.loadAll();
      final it = d.items.firstWhere((x) => x.source == 'ledger');
      expect(it.sourceTxnId, txnId);
      expect(it.name, 'Nike 跑鞋升级');
      // 流水不重复生成，仅原行回挂来源徽标
      final rows = await db.query(DbSchema.tLedgerTxns,
          where: 'id = ?', whereArgs: [txnId]);
      expect(rows.single['source'], 'item');
      expect(rows.single['link_id'], '${it.id}');
      expect((await db.query(DbSchema.tLedgerTxns)).length, txnsBefore);
      // 详情时间轴购入行注来源；列表行副行不重复
      await tester.tap(find.byKey(ValueKey('i-item-row-${it.id}')));
      await settle5(tester);
      expect(find.textContaining('来源：记账流水升级建档（联动 L12）'), findsOneWidget);
    });
  });

  group('P7c 成本统计屏', () {
    testWidgets('hero 三格 + Top5 榜 + 环图图例 + 近6月柱钻取', (tester) async {
      await useSurface(tester);
      await seedMacbook();
      await seedShoes();
      await pump(tester, const ItemsPage());
      await tester.tap(find.byKey(const ValueKey('i-stats-btn')));
      await settle5(tester);
      expect(find.text('¥23.48'), findsOneWidget);
      expect(find.textContaining('今日合计持有成本（计费中 2 件）'), findsOneWidget);
      expect(find.text('¥704'), findsOneWidget); // 本月它花掉了 23.48×30
      expect(find.text('¥11,453'), findsOneWidget); // 成本池总额
      expect(find.text('¥11.74'), findsOneWidget); // 件均日均
      // Top5 榜
      expect(find.text('Top 5 · 日均成本榜'), findsOneWidget);
      expect(find.textContaining('¥18.98/天'), findsOneWidget);
      expect(find.textContaining('¥4.50/天'), findsOneWidget);
      // 甜甜圈 + 图例占比（catPoolShare 实算 92/8）
      expect(find.byKey(const ValueKey('i-stats-donut')), findsOneWidget);
      expect(find.byKey(const ValueKey('i-stats-legend-数码')), findsOneWidget);
      expect(find.text('92%'), findsOneWidget);
      expect(find.text('8%'), findsOneWidget);
      // 近 6 月柱：8 月跑鞋购入 899
      expect(find.byKey(const ValueKey('i-stats-bar-2026-08')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('i-stats-bar-2026-08')));
      expect(
          await pollContains(tester, '8月 购入/付费明细：¥899（跳转记账当月流水）'),
          isTrue);
      await clearToasts(tester);
      // 点 Top 行 → 详情
      await tester.tap(find.byKey(const ValueKey('i-stats-top-1')));
      await settle5(tester);
      expect(find.text('物品详情'), findsOneWidget);
    });
  });

  group('P7d 决算屏分享', () {
    testWidgets('分享决算卡片 toast（长图能力未接线·登记差异）', (tester) async {
      await useSurface(tester);
      final id = await seedMonitor();
      await repo.scrap(id, '损坏', date: '2026-09-10');
      await pump(tester, ItemDetailPage(itemId: id));
      await tester.tap(find.byKey(const ValueKey('i-detail-settle')));
      await settle5(tester);
      expect(find.textContaining('2026-09-10 冻结'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('i-settle-share')));
      expect(await pollContains(tester, '决算长图已生成（分享卡片）'), isTrue);
    });
  });
}
