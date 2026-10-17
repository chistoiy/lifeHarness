import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/dashboard/presentation/dashboard_page.dart';
import 'package:lifeharness/features/days/data/days_repository.dart';
import 'package:lifeharness/features/days/domain/day_models.dart';
import 'package:lifeharness/features/days/presentation/days_providers.dart';
import 'package:lifeharness/features/items/data/items_repository.dart';
import 'package:lifeharness/features/items/domain/item_models.dart';
import 'package:lifeharness/features/items/presentation/items_providers.dart';

/// 批4 · 仪表盘联动卡（L10 倒数卡 + L12/L13 持有成本卡）。
/// 独立文件防 isolate 污染；固定钟 2026-09-19（days/items 双时钟缝）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 19);
  late Database db;
  late DaysRepository days;
  late ItemsRepository items;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    days = DaysRepository(db);
    items = ItemsRepository(db);
  });

  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    // 全高视口：仪表盘 7 张卡在 800×2400 下全部构建，免 ListView 懒建漏检。
    await useSurface(tester);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      daysRepositoryProvider.overrideWithValue(days),
      daysClockProvider.overrideWithValue(() => now),
      itemsRepositoryProvider.overrideWithValue(items),
      itemsClockProvider.overrideWithValue(() => now),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DashboardPage())));
    await settle5(tester); // 内含排空 AppLog 节流 Timer（未 override 待办仓储 → 读取失败会落日志）
  }

  /// 空态：倒数卡占位 + 持有成本 ¥0 + 空态话（UIUX批 2026-10-12：
  /// 「0 件物品计费中」假口径改「暂无计费物品」）。
  testWidgets('空态：暂无日子 · ¥ 0 · 暂无计费物品', (tester) async {
    await pump(tester);
    expect(find.text('最近的日子'), findsOneWidget);
    expect(find.text('暂无日子'), findsOneWidget);
    expect(find.text('¥ 0.00'), findsOneWidget);
    expect(find.text('暂无计费物品 ›'), findsOneWidget);
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('倒数卡：置顶恒前 + 倒数升序取三 + 过期不入', (tester) async {
    await days.addDay(DayEntry(
        title: '结婚纪念日',
        iconId: 'heart',
        colorKey: 'rose',
        category: '纪念',
        repeat: DayRepeat.once,
        targetDate: DateTime(2026, 10, 7),
        pinned: true));
    await days.addDay(DayEntry(
        title: '体检',
        iconId: 'medical',
        colorKey: 'sky',
        category: '倒数',
        repeat: DayRepeat.once,
        targetDate: DateTime(2026, 12, 31)));
    await days.addDay(DayEntry(
        title: '护照到期',
        iconId: 'id',
        colorKey: 'amber',
        category: '证件',
        repeat: DayRepeat.once,
        targetDate: DateTime(2026, 9, 26)));
    await days.addDay(DayEntry(
        title: '已过期倒数',
        iconId: 'alert',
        colorKey: 'slate',
        category: '倒数',
        repeat: DayRepeat.once,
        targetDate: DateTime(2026, 9, 1)));
    await pump(tester);

    expect(find.text('结婚纪念日'), findsOneWidget);
    expect(find.text('体检'), findsOneWidget);
    expect(find.text('护照到期'), findsOneWidget);
    // 一次性已过期不入卡（days_page 另有过期分流）。
    expect(find.text('已过期倒数'), findsNothing);
    expect(find.text('18'), findsOneWidget, reason: '结婚纪念日 10-07 倒数 18 天');
    expect(find.text('7'), findsOneWidget, reason: '护照到期 9-26 倒数 7 天');
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('持有成本卡：MacBook 直线法 ¥18.98 + 跑鞋按次 ¥4.50 实算',
      (tester) async {
    final macId = await items.addItem(const ItemProfile(
        name: 'MacBook Air M3',
        category: '数码',
        buyDate: '2025-03-12',
        price: 9999,
        warranty: '2026-03-12'));
    await items.addExtraPay(macId, 399, 'Type-C 扩展坞', date: '2025-06-02');
    await items.addExtraPay(macId, 156, '官方换电池（补差）', date: '2026-01-20');
    final shoesId = await items.addItem(const ItemProfile(
        name: 'Nike 跑鞋',
        category: '服饰',
        buyDate: '2026-08-18',
        price: 899,
        mode: ItemMode.times,
        planUnits: 300,
        unit: '次'));
    await items.addUsage(shoesId, '2026-08-25', 20);
    await items.addUsage(shoesId, '2026-09-10', 25);
    await pump(tester);

    // 18.98 + 4.50 = 23.48（计费引擎双口径合计，仪表盘同口径）。
    expect(find.text('¥ 23.48'), findsOneWidget);
    expect(find.text('2 件物品计费中 ›'), findsOneWidget);
    expect(find.byKey(const ValueKey('dash-cost-card')), findsOneWidget);
  });

  testWidgets('倒数卡：公历循环实算 + 「全部 ›」入口', (tester) async {
    await days.addDay(DayEntry(
        title: '女儿生日',
        iconId: 'cake',
        colorKey: 'violet',
        category: '纪念',
        repeat: DayRepeat.solarYear,
        targetDate: DateTime(2018, 5, 16)));
    await pump(tester);
    expect(find.text('女儿生日'), findsOneWidget);
    expect(find.text('全部 ›'), findsOneWidget);
    // 2026-09-19 → 下一次 2027-05-16 = 239 天（引擎实算）。
    expect(find.text('239'), findsOneWidget);
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });
}
