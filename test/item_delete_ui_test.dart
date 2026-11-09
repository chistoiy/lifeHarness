import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/days/data/days_repository.dart';
import 'package:lifeharness/features/days/presentation/days_providers.dart';
import 'package:lifeharness/features/days/presentation/days_routes.dart';
import 'package:lifeharness/features/items/data/items_repository.dart';
import 'package:lifeharness/features/items/domain/item_models.dart';
import 'package:lifeharness/features/items/presentation/item_detail_page.dart';
import 'package:lifeharness/features/items/presentation/items_providers.dart';
import 'package:lifeharness/features/items/presentation/items_routes.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// V1.61 批3 · 物品详情「删除」入口（工单 §4D：四钮＋LH-S31 二次确认＋撤销条）。
///
/// 独立文件＝全 app widget 测试拆文件防 isolate 污染（AGENTS 门禁条）。
/// 数据面（软删/恢复/彻底删除/流水不动）在 `item_delete_test.dart`，本文件只管屏。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 5);
  late Database db;
  late ItemsRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
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
      daysRepositoryProvider.overrideWithValue(DaysRepository(db)),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/root',
      routes: [
        GoRoute(
          path: '/root',
          builder: (_, _) => const Scaffold(body: SizedBox.shrink()),
        ),
        GoRoute(path: '/x', builder: (_, _) => home),
        ...itemsPageRoutes(),
        ...daysPageRoutes(),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    router.push('/x');
    await settle5(tester);
    await settle5(tester);
  }

  Future<int> seedItem({
    String name = '测试相机',
    String status = kItemStatusActive,
    bool billing = true,
  }) =>
      repo.addItem(ItemProfile(
        name: name,
        category: '数码',
        buyDate: '2026-01-01',
        price: 199,
        status: status,
        billing: billing,
      ));

  Future<int?> deletedAtOf(int id) async {
    final r = await db.query('item_profiles',
        columns: ['deleted_at'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (r.isEmpty) return -1; // 行已不在（彻底删除）
    return r.first['deleted_at'] as int?;
  }

  testWidgets('详情动作行＝四钮，第四钮是删除且与三个生命周期钮不同色底', (tester) async {
    final id = await seedItem();
    await pump(tester, ItemDetailPage(itemId: id));

    for (final k in ['i-life-extra', 'i-life-recycle', 'i-life-scrap', 'i-life-del']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: '动作行缺钮：$k');
    }
    // 破坏性一档：玫红描边、不吃三个生命周期钮的彩色底；图标也不与「报废」撞脸。
    final del = tester.widget<GestureDetector>(find.byKey(const ValueKey('i-life-del')));
    final box = (del.child as Container).decoration! as BoxDecoration;
    expect(box.border, isNotNull, reason: '删除钮必须是描边一档（区别于彩色底的生命周期钮）');
    expect(box.color, isNull, reason: '描边钮不该再有底色');
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.byIcon(Icons.delete_forever_outlined), findsOneWidget,
        reason: '报废与删除都用垃圾桶图标＝两钮看不出区别（本批把报废换成 delete_forever）');
  });

  testWidgets('冻结档案（已报废）也给删除钮：任意状态可删', (tester) async {
    final id = await seedItem(
        name: '旧显示器', status: kItemStatusScrapped, billing: false);
    await pump(tester, ItemDetailPage(itemId: id));

    expect(find.byKey(const ValueKey('i-detail-settle')), findsOneWidget,
        reason: '冻结档案应先有决算入口卡（三钮行整块不渲染）');
    expect(find.byKey(const ValueKey('i-life-del')), findsOneWidget,
        reason: '拍板③：已报废档案同样要能删——删除钮必须独立于三钮那个条件');
  });

  testWidgets('点删除＝先出二次确认，后果逐条带真实读数并明说流水保留', (tester) async {
    final id = await seedItem();
    await repo.addExtraPay(id, 39, '镜头维修', date: '2026-03-01');
    await pump(tester, ItemDetailPage(itemId: id));

    await tester.tap(find.byKey(const ValueKey('i-life-del')));
    await settle5(tester);

    expect(find.byKey(const ValueKey('d-confirm-cancel')), findsOneWidget);
    expect(find.byKey(const ValueKey('d-confirm-ok')), findsOneWidget);
    final msg = tester.widget<Text>(find.textContaining('删除「测试相机」')).data;
    expect(msg, contains('成本时间轴 2 条'), reason: '购入＋二次付费＝两条，读数要真');
    expect(msg, contains('按次用量 0 次'));
    expect(msg, contains('关联记账流水 0 条：保留在记账'),
        reason: '拍板②的承诺必须在确认里看得见，不是删完才说');
    expect(msg, contains('回收站保留期内可在「我的 · 回收站」找回'));
  });

  testWidgets('确认框点取消＝什么都不删', (tester) async {
    final id = await seedItem();
    await pump(tester, ItemDetailPage(itemId: id));

    await tester.tap(find.byKey(const ValueKey('i-life-del')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('d-confirm-cancel')));
    await settle5(tester);

    expect(await deletedAtOf(id), isNull, reason: '取消即一条不动（点遮罩/返回同口径）');
    expect(find.text('测试相机'), findsWidgets);
  });

  testWidgets('确认删除＝软删进回收站 · 离场 · 撤销条指路', (tester) async {
    final id = await seedItem();
    await pump(tester, ItemDetailPage(itemId: id));

    await tester.tap(find.byKey(const ValueKey('i-life-del')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('d-confirm-ok')));
    // SnackBar 的 action 在滑入动画中不可命中（既有教训），先等进场落定。
    await settleFrames(tester);

    expect(await deletedAtOf(id), isNotNull, reason: '删除＝软删打标记，不是真删行');
    expect(find.textContaining('已移入回收站'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);
    expect(find.byKey(const ValueKey('i-life-del')), findsNothing,
        reason: '确认后就该离开详情页，不该停在「档案不存在」那一帧');
    await clearToasts(tester);
  });

  testWidgets('点撤销＝当场清回标记，档案回在册继续计费', (tester) async {
    final id = await seedItem();
    await pump(tester, ItemDetailPage(itemId: id));

    await tester.tap(find.byKey(const ValueKey('i-life-del')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('d-confirm-ok')));
    await settleFrames(tester);
    expect(await deletedAtOf(id), isNotNull);

    await tester.tap(find.text('撤销'));
    await settle5(tester);
    await settle5(tester);

    expect(await deletedAtOf(id), isNull, reason: '撤销必须真的清掉 deleted_at');
    expect((await repo.loadAll()).items.map((e) => e.name), contains('测试相机'));
    await clearToasts(tester);
  });

  // 纯源码守护＝普通 test()：testWidgets 跑在 FakeAsync 里，真实文件异步读永不返回
  // （本条首跑就是挂满 10 分钟才超时报红的），一律同步读。
  test('删除走公共确认原语与撤销条原语（不许自造第二套版式）', () {
    final src = File('lib/features/items/presentation/item_detail_page.dart')
            .readAsStringSync()
        // 断代码行原文，不断注释：注释里出现「lhConfirm」不算接上。
        .split('\n')
        .where((l) => !l.trim().startsWith('//'))
        .join('\n');
    expect(src, contains('lhConfirm('), reason: '确认必须走 LH-S31 公共原语');
    expect(src, contains('AppToast.showUndoWith'),
        reason: '撤销条必须走批一 T4 的排他基建（含 4s 自动退场）');
    expect(src, contains('ProviderScope.containerOf'),
        reason: '跨 await 的写库与刷新不得带发起页 ref（弹层/离场后 ref 失效既定坑）');
    expect(src, isNot(contains('showDialog')), reason: '确认版式全仓只有一份');
    expect(src, isNot(contains('SnackBar(')), reason: '不许手挂 SnackBar（撤销条统一出口）');
  });
}
