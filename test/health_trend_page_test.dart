import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/health/data/health_repository.dart';
import 'package:lifeharness/features/health/data/health_settings.dart';
import 'package:lifeharness/features/health/domain/health_calc.dart';
import 'package:lifeharness/features/health/domain/health_models.dart';
import 'package:lifeharness/features/health/presentation/health_providers.dart';
import 'package:lifeharness/features/health/presentation/health_routes.dart';
import 'package:lifeharness/features/health/presentation/health_trend_page.dart';
import 'package:lifeharness/shared/widgets/ui_kit.dart';

import 'helpers.dart';

/// 健康批6a · 趋势屏（原型 `index-health.html#p-trends`，JS 段 `hTrends`/`hMonthAvg`/`hTrendDay`）。
///
/// 五条判定（工单执行面板第 3 项「常驻用例」）：
/// · 三档 seg × 六枚 chips：切换**只换读数与色**，跨度文案、格数、四数据位形态、目标线同帧跟；
/// · 点热力格出当日六指标明细行；换跨度后选中键作废（格序整段变了，指错日比不指更糟）；
/// · 年视图点行只给月均并明说「日明细请切『月』」；
/// · **缺记录日不出现假点**：空格不吃 0 档色（域层 -1 档的可见面）；
/// · 目标线读数当场跟设置（`ht-goal-tx` 吃 `healthTrGoalsProvider`，改档＋healthTouch 即换）。
///
/// 独立文件（全 app/大页 pump 拆文件口径）；日期一律相对固定钟 `now` 构造。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 8, 10, 0);
  String dk(int back) => dayKey(now.subtract(Duration(days: back)));

  late Database db;
  late HealthRepository repo;
  late SharedPreferences prefs;
  late ProviderContainer container;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = HealthRepository(db);
  });

  tearDown(() => db.close());

  Future<void> pumpTrend(WidgetTester tester,
      {Map<String, Object> prefsValues = const {}}) async {
    await useSurface(tester, const Size(420, 2600));
    SharedPreferences.setMockInitialValues(prefsValues);
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [
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
    router.push('/health/trend');
    await settle5(tester);
  }

  /// 种子面：14 天整段有记录（周档＝后 7 天），只有 3 个「近日」有睡眠；
  /// 4 天综合分 ≥80（满分日）、0 天 <40 → 百分比形态的「待改善天」出 0 而不是缺席。
  Future<void> seed() async {
    for (var i = 0; i < 14; i++) {
      await repo.bumpCups(1, dk(i), 6);
      await repo.addExercise(
          ExerciseRecord(profileId: 1, date: dk(i), type: '瑜伽', durationMin: 12));
    }
    for (final i in [0, 2, 4]) {
      await repo.saveSleep(SleepRecord(
          profileId: 1,
          date: dk(i),
          bedTime: '23:00',
          wakeTime: '07:00',
          durationMin: 0));
    }
    for (final i in [0, 2, 4, 6]) {
      await repo.logDrug(DrugLog(
          profileId: 1, drugId: 99, date: dk(i), time: '08:00', state: 'taken'));
    }
    await repo.saveBody(BodyRecord(profileId: 1, date: dk(3), kg: 61.0));
    await repo.saveBody(BodyRecord(profileId: 1, date: dk(0), kg: 60.0));
  }

  String keyText(WidgetTester t, String key) =>
      t.widget<Text>(find.byKey(ValueKey(key))).data ?? '';

  Future<void> tapKey(WidgetTester t, String key) async {
    final f = find.byKey(ValueKey(key));
    await t.ensureVisible(f);
    await settle5(t);
    await t.tap(f);
    await settle5(t);
  }

  int heatCells(WidgetTester t) => find.byWidgetPredicate((w) {
        final k = w.key;
        return k is ValueKey<String> &&
            k.value.startsWith('ht-heat-') &&
            k.value != 'ht-heat-tx';
      }).evaluate().length;

  /// 四数据位：值与 label 是同列两枚 Text，容器键 `ht-slot-i` 下点树取。
  String slotValue(WidgetTester t, int i) => t
      .widgetList<Text>(find.descendant(
          of: find.byKey(ValueKey('ht-slot-$i')), matching: find.byType(Text)))
      .first
      .data!;

  String slotLabel(WidgetTester t, int i) => t
      .widgetList<Text>(find.descendant(
          of: find.byKey(ValueKey('ht-slot-$i')), matching: find.byType(Text)))
      .last
      .data!;

  Color? cellFill(WidgetTester t, String key) {
    final g = t.widget<GestureDetector>(find.byKey(ValueKey(key)));
    final d = (g.child as Container).decoration;
    return d is BoxDecoration ? d.color : null;
  }

  BoxDecoration cellBox(WidgetTester t, String key) {
    final g = t.widget<GestureDetector>(find.byKey(ValueKey(key)));
    return (g.child as Container).decoration! as BoxDecoration;
  }

  Future<void> seg(WidgetTester t, int range) =>
      tapKey(t, 'ht-seg-$range');

  setUp(() => seed());

  testWidgets('周档默认＝综合达标：六段齐、格数 7、目标线吃判据常量 80%', (tester) async {
    await pumpTrend(tester);
    expect(keyText(tester, 'ht-heat-tx'), '达标热力 · 综合达标 · 近 7 天');
    expect(heatCells(tester), 7);
    expect(find.byKey(HealthTrendPage.kSeg), findsOneWidget);
    expect(find.byKey(HealthTrendPage.kChips), findsOneWidget);
    expect(find.byKey(HealthTrendPage.kCurve), findsOneWidget);
    expect(find.byKey(HealthTrendPage.kReport), findsOneWidget);
    expect(keyText(tester, 'ht-goal-tx'), '虚线 = 目标 80 %',
        reason: '综合 80 是达标判据常量，不是用户目标');
    expect(slotLabel(tester, 0), '平均达标');
    expect(slotLabel(tester, 3), '待改善天');
    expect(slotValue(tester, 3), '0', reason: '0 也是读数——不许缺席');
    expect(keyText(tester, 'ht-day-detail'), '未选日期');
  });

  testWidgets('chips 切换只换读数：四数据位换形态、热力标题换指标、选中态可辨', (tester) async {
    await pumpTrend(tester);
    PillChip chip(String k) => tester.widget<PillChip>(find.byKey(ValueKey('ht-chip-$k')));
    expect(chip('all').selected, isTrue, reason: '默认选中综合');
    expect(chip('water').selected, isFalse);

    await tapKey(tester, 'ht-chip-water');
    expect(keyText(tester, 'ht-heat-tx'), '达标热力 · 喝水 · 近 7 天');
    expect(slotLabel(tester, 0), '合计 杯');
    expect(slotLabel(tester, 3), '单日峰值');
    expect(slotValue(tester, 0), '42', reason: '6 杯 × 7 天（当前期）');
    expect(keyText(tester, 'ht-goal-tx'), '虚线 = 目标 8 杯', reason: '默认喝水目标 8');
    expect(chip('water').selected, isTrue, reason: '点了必须有看得见的变化');
    expect(chip('all').selected, isFalse);
    expect(heatCells(tester), 7, reason: '换指标不换取样，不重开查询');

    await tapKey(tester, 'ht-chip-body');
    expect(slotLabel(tester, 0), '期末 kg');
    expect(slotLabel(tester, 3), '距目标');
    expect(keyText(tester, 'ht-goal-tx'), '未设目标', reason: 'health_goal 没设体重＝虚线不画、读数说实话');
  });

  testWidgets('点热力格出当日六指标明细；换跨度后选中键作废', (tester) async {
    await pumpTrend(tester);
    await tapKey(tester, 'ht-heat-${dk(1)}');
    final tx = keyText(tester, 'ht-day-detail');
    expect(tx, startsWith('${dk(1).substring(5)} ${dayWd(dk(1))}'));
    expect(tx, contains('喝水 6/8 杯'));
    expect(tx, contains('睡眠 —h'), reason: '那天没记睡眠＝「—」不是 0');
    expect(tx, contains('运动 12 分钟'));
    expect(tx, contains('综合 55%'),
        reason: '现算：w 6/8→30 + s 420/480→30.625 + e 满格 25（dk(1) 无睡眠＝昨晚 10-07 那条）');

    // 选中态可辨：该格描边，隔壁格没有
    await tapKey(tester, 'ht-chip-water');
    expect(cellBox(tester, 'ht-heat-${dk(1)}').border, isNotNull,
        reason: '选中态＝描边（「点了必须有看得见的变化」）');
    expect(cellBox(tester, 'ht-heat-${dk(2)}').border, isNull);

    await seg(tester, 30);
    expect(keyText(tester, 'ht-day-detail'), '未选日期', reason: '格序整段变了，旧键必须作废');
    expect(heatCells(tester), 30);
    expect(keyText(tester, 'ht-heat-tx'), '达标热力 · 喝水 · 近 30 天');
  });

  testWidgets('缺记录日＝空格：不吃 0 档色，与有记录低档格可辨', (tester) async {
    await pumpTrend(tester);
    // 摘掉一天的全部记录 → 睡眠只有 0/2/4 天有，其它日综合分仍由水+瑜伽构成——
    // 要真空格得删水与运动；直接删 dk(5) 这天。
    await db.delete('health_water', where: "date='${dk(5)}'", whereArgs: []);
    await db.delete('health_exercise', where: "date='${dk(5)}'", whereArgs: []);
    container.read(healthTickProvider.notifier).state++;
    await settle5(tester);
    final empty = cellFill(tester, 'ht-heat-${dk(5)}');
    final schemeBg = Theme.of(tester.element(find.byKey(HealthTrendPage.kHeat)))
        .colorScheme
        .onSurface
        .withValues(alpha: .05);
    expect(empty, schemeBg, reason: 'lv=-1 空格吃中性底，不吃指标色 0 档（.25 alpha）');
    final low = cellFill(tester, 'ht-heat-${dk(4)}');
    expect(low, isNot(schemeBg), reason: '有记录日哪怕分低也带指标色——空格与低格必须可辨');
  });

  testWidgets('年视图＝近 12 个月按月聚合：点行给月均并明说切「月」', (tester) async {
    await pumpTrend(tester);
    await tapKey(tester, 'ht-chip-water');
    await seg(tester, 12);
    expect(keyText(tester, 'ht-heat-tx'), '达标热力 · 喝水 · 近 12 个月');
    expect(heatCells(tester), 12);
    expect(keyText(tester, 'ht-legend'), startsWith('按月 · 色阶'), reason: '年视图色阶前缀');
    expect(find.text('9月'), findsOneWidget, reason: '近 12 个月＝滚动窗口，去年 9 月在格序里');

    await tapKey(tester, 'ht-heat-2026-10');
    final tx = keyText(tester, 'ht-day-detail');
    expect(tx, contains('2026-10 月均'));
    expect(tx, contains('日明细请切「月」'));
  });

  testWidgets('目标线当场跟设置：改喝水目标＋healthTouch → 读数与虚线同帧换（真机门②的自动化腿）',
      (tester) async {
    await pumpTrend(tester);
    await tapKey(tester, 'ht-chip-water');
    expect(keyText(tester, 'ht-goal-tx'), '虚线 = 目标 8 杯');

    await prefs.setInt(HealthSettings.kWaterGoal, 10);
    container.read(healthTickProvider.notifier).state++;
    await settle5(tester);
    expect(keyText(tester, 'ht-goal-tx'), '虚线 = 目标 10 杯',
        reason: '刀3 靶的屏侧面：写死 30/8 不跟＝这例红');

    await prefs.setInt(HealthSettings.kWeekExGoal, 5);
    container.read(healthTickProvider.notifier).state++; // 真实写档路径必带 healthTouch，这里同式
    await tapKey(tester, 'ht-chip-ex');
    await settle5(tester);
    expect(keyText(tester, 'ht-goal-tx'), '虚线 = 目标 7 分钟',
        reason: '周次数 5 → 日参考线 50/7≈7.1，读数 decimals=0 取整');
  });

  testWidgets('环比脚注：上期有数出百分比，无数据出实话不除零', (tester) async {
    await pumpTrend(tester);
    expect(keyText(tester, 'ht-compare'), startsWith('环比上期'));
    expect(keyText(tester, 'ht-compare'), isNot(contains('NaN')));

    // 清空上一期（前 7 天）→ 上期均值 null → 实话分支
    await db.delete('health_water', where: "date<=?", whereArgs: [dk(7)]);
    await db.delete('health_exercise', where: "date<=?", whereArgs: [dk(7)]);
    await db.delete('health_sleep', where: "date<=?", whereArgs: [dk(7)]);
    await db.delete('health_drug_log', where: "date<=?", whereArgs: [dk(7)]);
    container.read(healthTickProvider.notifier).state++;
    await settle5(tester);
    expect(keyText(tester, 'ht-compare'), contains('环比上期 —（上期无记录）'));
  });
}
