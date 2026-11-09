import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/health/data/health_repository.dart';
import 'package:lifeharness/features/health/domain/health_calc.dart';
import 'package:lifeharness/features/health/domain/health_models.dart';
import 'package:lifeharness/features/health/domain/health_vital.dart';
import 'package:lifeharness/features/health/presentation/health_providers.dart';
import 'package:lifeharness/features/health/presentation/health_routes.dart';
import 'package:lifeharness/features/health/presentation/health_vitals_page.dart';
import 'package:lifeharness/shared/widgets/ui_kit.dart';

import 'helpers.dart';

/// 健康批2.5 · 体征记录屏（原型 `tools/health/v2_pages.html#p-vitals`）。
///
/// 五条判定（工单执行面板第 3 项）：
/// · **无记录＝「未记录／—／暂无记录」＋空柱**，绝不拿 0 当读数（刀2 靶：把 null 分支改成 0 就红）；
/// · 曲线**两点起步**：0/1 条只出「不足 2 条 · 暂无曲线」，统计三格也不铺（刀3 靶：`>=2` 改 `>=1` 就红）；
/// · **周/月/季只是窗口**（7/30/90 天），四处区域吃同一份取数——窗口一变曲线与统计同步变；
/// · 参考区间只有一处出处：血氧的 999 是「无上限」哨兵，屏上只印「参考 ≥95 %」，不印 999；
/// · **跨档案不聚合**（刀1 的同一条口径在 UI 侧的落点）：切档案 chips 后读数整套换掉。
///
/// 独立文件（全 app/大页 pump 拆文件口径）；日期一律相对固定钟 `now` 构造，禁写死今天。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 19, 10, 30);
  late Database db;
  late HealthRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = HealthRepository(db);
  });

  tearDown(() => db.close());

  /// 体征屏 pump：建库＋固定钟＋模块真实路由（栈页一律 push）。
  Future<(ProviderContainer, GoRouter)> pumpVitals(WidgetTester tester) async {
    await useSurface(tester, const Size(420, 2400));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      healthRepositoryProvider.overrideWithValue(repo),
      healthClockProvider.overrideWithValue(() => now),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(initialLocation: '/root', routes: [
      GoRoute(path: '/root', builder: (_, _) => const Scaffold(body: SizedBox.shrink())),
      ...healthPageRoutes(),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle5(tester);
    router.push('/health/vitals');
    await settle5(tester);
    return (container, router);
  }

  Finder tile(String kind) => find.byKey(ValueKey('hvt-tile-$kind'));

  /// 键直接挂在 Text 上的读数（`find.descendant` 不含自身，这类键只能直取）。
  String keyText(WidgetTester t, String key) =>
      t.widget<Text>(find.byKey(ValueKey(key))).data ?? '';

  /// 屏上任意区域的实文本（曲线副注是「当前指标」的唯一读数出口）。
  String curveCaption(WidgetTester t) =>
      (t.widget<Text>(find.byKey(const ValueKey('hvt-cur-tx')))).data ?? '';

  /// 异常汇总行的键序（只取带 `hvt-abn-row-` 的那些，版头那行 Row 不算）。
  List<String> abnRowKeys(WidgetTester t) => t
      .widgetList<Row>(find.byType(Row))
      .map((r) => r.key)
      .whereType<ValueKey<String>>()
      .map((k) => k.value)
      .where((v) => v.startsWith('hvt-abn-row-'))
      .toList();

  testWidgets('空白档案：五枚全出「未记录／—／暂无记录」，曲线与统计都不铺', (tester) async {
    await pumpVitals(tester);
    for (final k in vitalOrder) {
      expect(tile(k), findsOneWidget, reason: '五枚瓦片常驻，缺类也要占位');
      expect(find.descendant(of: tile(k), matching: find.text('未记录')), findsOneWidget);
      expect(keyText(tester, 'hvt-tile-value-$k'), '—',
          reason: '空槽只出「—」，不写 0 杯式假读数');
      expect(find.descendant(of: tile(k), matching: find.text('暂无记录')), findsOneWidget);
      expect(find.descendant(of: tile(k), matching: find.byKey(ValueKey('hvt-tile-bars-$k'))),
          findsNothing,
          reason: '没记录就没有迷你柱，不画一排 0 高假柱');
    }
    expect(find.textContaining('0 mmHg'), findsNothing);
    expect(find.byKey(const ValueKey('hvt-curve-empty')), findsOneWidget);
    expect(keyText(tester, 'hvt-axis-lo'), '—');
    expect(find.byKey(const ValueKey('hvt-stat-均值')), findsNothing, reason: '数据不足不铺统计三格');
    expect(find.byKey(const ValueKey('hvt-abn-none')), findsOneWidget);
    expect(find.byKey(const ValueKey('hvt-abn')), findsNothing);
    expect(find.text('该档案暂无体征记录'), findsOneWidget);
    expect(find.byType(EmptyDashRow), findsOneWidget);
  });

  testWidgets('血压两值一起显示，主值只按收缩压判级（118/76＝正常）', (tester) async {
    await repo.saveVital(const HealthVital(
        profileId: 1, date: '2026-09-18', time: '07:30', kind: 'bp', sys: 118, dia: 76, hr: 62));
    await pumpVitals(tester);
    expect(find.descendant(of: tile('bp'), matching: find.text('118/76')), findsOneWidget);
    expect(find.descendant(of: tile('bp'), matching: find.text('正常')), findsOneWidget);
    // 单条＝曲线仍然不给（两点才画），但迷你柱与读数照给。
    expect(find.byKey(const ValueKey('hvt-curve-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('hvt-tile-bars-bp')), findsOneWidget);
    expect(find.text('该档案暂无体征记录'), findsNothing);
  });

  testWidgets('两条起曲线：均值/异常/记录三格与轴端、参考文案同源（刀3 靶）', (tester) async {
    await repo.saveVital(const HealthVital(
        profileId: 1, date: '2026-09-17', time: '07:30', kind: 'bp', sys: 118, dia: 76));
    await repo.saveVital(const HealthVital(
        profileId: 1, date: '2026-09-18', time: '20:10', kind: 'bp', sys: 132, dia: 88));
    await pumpVitals(tester);
    expect(find.byKey(const ValueKey('hvt-curve-empty')), findsNothing);
    expect(find.descendant(of: find.byKey(HealthVitalsPage.kCurve), matching: find.byType(CustomPaint)),
        findsWidgets);
    expect(find.descendant(of: find.byKey(const ValueKey('hvt-stat-均值')), matching: find.text('125mmHg')),
        findsOneWidget, reason: '主值（收缩压）均值，两值混算就会得 108');
    expect(
        find.descendant(of: find.byKey(const ValueKey('hvt-stat-异常')), matching: find.text('0 次')),
        findsOneWidget);
    expect(
        find.descendant(of: find.byKey(const ValueKey('hvt-stat-记录')), matching: find.text('2 条')),
        findsOneWidget);
    // 轴端＝min(实值,参考下界)−1 / max(实值,展示上限)+1，标签与画笔吃同一对数。
    expect(keyText(tester, 'hvt-axis-lo'), '89');
    expect(keyText(tester, 'hvt-axis-hi'), '140');
    expect(keyText(tester, 'hvt-ref-tx'), '参考 90 ~ 139 mmHg');
    expect(find.textContaining('999'), findsNothing, reason: '哨兵值不上屏');
  });

  testWidgets('周/月/季只是窗口：40 天前的两条在「月」不进曲线，切「季」当场入窗',
      (tester) async {
    final far1 = dayKey(now.subtract(const Duration(days: 45)));
    final far2 = dayKey(now.subtract(const Duration(days: 40)));
    await repo.saveVital(HealthVital(
        profileId: 1, date: far1, time: '07:00', kind: 'hr', val: 64));
    await repo.saveVital(HealthVital(
        profileId: 1, date: far2, time: '07:00', kind: 'hr', val: 70));
    await pumpVitals(tester);

    await tester.tap(tile('hr'));
    await settle5(tester);
    expect(curveCaption(tester), '心率 · 数据不足', reason: '月窗内 0 条＝副注说数据不足');
    expect(find.byKey(const ValueKey('hvt-curve-empty')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('hvt-seg-90')));
    await settle5(tester);
    expect(curveCaption(tester), '心率 · 次/分 · 近 90 天');
    expect(
        find.descendant(of: find.byKey(const ValueKey('hvt-stat-记录')), matching: find.text('2 条')),
        findsOneWidget, reason: '四处区域吃同一份取数：窗口一变统计跟着变');
    // 切回「月」立刻又空（防止只吃第一次的取数缓存）
    await tester.tap(find.byKey(const ValueKey('hvt-seg-30')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('hvt-curve-empty')), findsOneWidget);
  });

  testWidgets('异常只作提示：汇总出「偏低/偏高」＋条数，补记录那枚切到对应指标', (tester) async {
    final idBp = await repo.saveVital(const HealthVital(
        profileId: 1, date: '2026-09-16', time: '07:20', kind: 'bp', sys: 86, dia: 55));
    final idTemp = await repo.saveVital(const HealthVital(
        profileId: 1, date: '2026-09-18', time: '21:05', kind: 'temp', val: 38.5));
    await repo.saveVital(const HealthVital(
        profileId: 1, date: '2026-09-18', time: '08:00', kind: 'spo2', val: 97));
    await pumpVitals(tester);

    final abn = find.byKey(HealthVitalsPage.kAbn);
    expect(abn, findsOneWidget);
    expect(keyText(tester, 'hvt-abn-n'), '2 条待关注',
        reason: '血氧 97 在参考内，不跟着凑数');
    expect(find.descendant(of: abn, matching: find.text('偏低')), findsOneWidget);
    expect(find.descendant(of: abn, matching: find.text('偏高')), findsOneWidget);
    expect(find.textContaining('38.5 ℃'), findsWidgets);
    // 最近优先：09-18 的体温排在 09-16 的血压前面（原型取的是最旧八条，偏离记在工单 §3）
    expect(abnRowKeys(tester), ['hvt-abn-row-$idTemp', 'hvt-abn-row-$idBp']);

    // 只给提示不给结论（§11.3.1）
    expect(find.textContaining('建议就医'), findsNothing);
    expect(find.textContaining('高血压'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('hvt-abn-add-temp')));
    await settle5(tester);
    expect(curveCaption(tester), '体温 · 数据不足', reason: '补记录＝把当前指标换成那一类，好接着记');
  });

  testWidgets('血氧切上屏：参考上限是「无上限」哨兵，只印「参考 ≥95 %」', (tester) async {
    await repo.saveVital(const HealthVital(
        profileId: 1, date: '2026-09-17', time: '09:00', kind: 'spo2', val: 96));
    await repo.saveVital(const HealthVital(
        profileId: 1, date: '2026-09-18', time: '09:00', kind: 'spo2', val: 98));
    await pumpVitals(tester);
    await tester.tap(tile('spo2'));
    await settle5(tester);
    expect(keyText(tester, 'hvt-ref-tx'), '参考 ≥95 %');
    // 999 当刻度上界会把曲线压成贴底直线（哨兵不参与算轴）
    expect(keyText(tester, 'hvt-axis-hi'), '101');
    expect(find.descendant(of: tile('spo2'), matching: find.text('正常')), findsOneWidget);
  });

  testWidgets('切档案＝整套换读数：另一档案的血压不串进「本人」', (tester) async {
    final other = await repo.saveProfile(const HealthProfile(id: 0, name: '妈妈', rel: '母'));
    await repo.saveVital(const HealthVital(
        profileId: 1, date: '2026-09-18', time: '07:30', kind: 'bp', sys: 118, dia: 76));
    await repo.saveVital(HealthVital(
        profileId: other, date: '2026-09-18', time: '07:30', kind: 'bp', sys: 145, dia: 92));
    await pumpVitals(tester);
    expect(find.descendant(of: tile('bp'), matching: find.text('118/76')), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('hvt-profile-$other')));
    await settle5(tester);
    expect(find.descendant(of: tile('bp'), matching: find.text('145/92')), findsOneWidget);
    expect(find.text('118/76'), findsNothing, reason: '两档案的读数不同屏共存');
  });

  testWidgets('流水点行＝就地改（带删除钮），顶栏与卡内「＋记录」都开录入弹层', (tester) async {
    final id = await repo.saveVital(const HealthVital(
        profileId: 1, date: '2026-09-18', time: '07:30', kind: 'bp', sys: 118, dia: 76,
        slot: '晨起空腹'));
    await pumpVitals(tester);

    await tester.tap(find.byKey(ValueKey('hvt-row-$id')));
    await settle5(tester);
    expect(find.text('修改 09-18 的血压'), findsOneWidget);
    expect(find.byKey(const ValueKey('hv-save')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hv-cancel')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('hv-save')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('hvt-add')));
    await settle5(tester);
    expect(find.text('记录体征'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hv-cancel')));
    await settle5(tester);

    await tester.tap(find.byKey(const ValueKey('hvt-add-inline')));
    await settle5(tester);
    expect(find.text('记录体征'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hv-cancel')));
    await settle5(tester);
  });

  testWidgets('删除走二次确认：确认后流水与瓦片同帧收回', (tester) async {
    final id = await repo.saveVital(const HealthVital(
        profileId: 1, date: '2026-09-18', time: '07:30', kind: 'bp', sys: 118, dia: 76));
    await pumpVitals(tester);
    expect(find.byKey(ValueKey('hvt-row-$id')), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('hvt-del-$id')));
    await settle5(tester);
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    // 取消＝一行都不动
    await tester.tap(find.descendant(of: dialog, matching: find.text('取消')));
    await settle5(tester);
    expect(find.byKey(ValueKey('hvt-row-$id')), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('hvt-del-$id')));
    await settle5(tester);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('删除')));
    await settle5(tester);
    expect(find.byKey(ValueKey('hvt-row-$id')), findsNothing);
    expect(find.descendant(of: tile('bp'), matching: find.text('未记录')), findsOneWidget);
    expect(await repo.vitals(1, '2026-09-01', '2026-09-30'), isEmpty);
  });

  testWidgets('工作台体征条：五枚各取最近一条，点击直达对应指标的体征屏（push）', (tester) async {
    final (container, router) = await pumpVitals(tester);
    expect(router.canPop(), isTrue, reason: '体征屏是栈页，必须 push 才留得住返回');
    // 体征条 provider 与屏共用同一份仓储口径（无记录＝null，UI 出「—」）
    final strip = await container.read(healthVitalStripProvider.future);
    expect(strip.keys.toList(), vitalOrder);
    expect(strip.values.every((v) => v == null), isTrue);
    // `router.push` 返回的 Future 要等被推的那页 pop 才完成——测里 await 它就是死等（整只 isolate 挂住）。
    // 与 `pumpVitals` 同形：发出去就推帧，不 await。
    router.push('/health/vitals?kind=glu');
    await settle5(tester);
    expect(curveCaption(tester), '血糖 · 数据不足');
    expect(find.byKey(const ValueKey('hvt-ref-tx')), findsOneWidget);
  });
}
