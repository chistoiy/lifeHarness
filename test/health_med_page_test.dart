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
import 'package:lifeharness/features/health/domain/health_drug.dart';
import 'package:lifeharness/features/health/domain/health_models.dart';
import 'package:lifeharness/features/health/presentation/health_providers.dart';
import 'package:lifeharness/features/health/presentation/health_routes.dart';
import 'package:lifeharness/shared/widgets/lh_wheel.dart';

import 'helpers.dart';

/// 健康批5 · 用药管理屏（原型 `index-health.html#p-med` ＋ `hRenderMeds`/`hMedTap`/`hDrugDel`/`tgMedAll`）。
///
/// 七条判定（工单执行面板第 3 项「常驻用例」）：
/// · 概览／卡列表／热力**同吃一份 `MedBundle`**：卡内点一次打卡，顶部「o/t 次」与依从率同帧改口
///   （两处各开各的查询就会有一帧对不上）；
/// · 计划位为 0 时读数出「—」，空档案屏不铺 0/0 与 0%；
/// · **已服与有交代分开**（刀1 靶）：`skipped` 流水既不进 `o`，也不再被叫成漏服——
///   两条判据在页面上同时可见才算真的分开；
/// · 删除＝归档：卡少一张、计划分母少一格，而 `health_drug_log` 一行不删；
/// · 近 7 天热力按单药算（刀2 靶）：没计划的日子上中性格，隔壁药吃满也不跟着变绿；
/// · 漏服宽限＝就地内嵌滚轮（LH-K39）：点行展开、选档当场写 prefs，卡头徽标当场增减；
/// · 免打扰时段文案从 `NotificationService.inDndWindow` 反推，不是写死的 `23:00 – 07:00` 字面量。
///
/// 独立文件（全 app/大页 pump 拆文件口径）；日期一律相对固定钟 `now` 构造，禁写死今天。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 19, 10, 30);
  late Database db;
  late HealthRepository repo;
  late SharedPreferences prefs;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = HealthRepository(db);
  });

  tearDown(() => db.close());

  final dk = dayKey(now);
  final y = dayKey(now.subtract(const Duration(days: 1)));

  Future<ProviderContainer> pumpMed(WidgetTester tester,
      {Map<String, Object> prefsValues = const {}}) async {
    await useSurface(tester, const Size(420, 2400));
    SharedPreferences.setMockInitialValues(prefsValues);
    prefs = await SharedPreferences.getInstance();
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
    router.push('/health/med');
    await settle5(tester);
    return container;
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

  /// 热力格的颜色就是三档判据的可见面（`MdHeat` → 域层两支色，无档吃 `scheme` 中性底）。
  Color? cellColor(WidgetTester t, String key) {
    final d = t.widget<Container>(find.byKey(ValueKey(key))).decoration;
    return d is BoxDecoration ? d.color : null;
  }

  Color neutral(WidgetTester t, String key) =>
      Theme.of(t.element(find.byKey(ValueKey(key)))).colorScheme.onSurface.withValues(alpha: .06);

  /// 滚轮往上拖 n 格＝档位 +n（`HealthGoalRow` 用 itemExtent 30）。
  Future<void> spin(WidgetTester t, String wheelKey, int steps) async {
    await t.drag(find.byKey(ValueKey(wheelKey)), Offset(0, -30.0 * steps));
    await settle5(t);
  }

  Future<int> drug(String name,
          {List<String> times = const ['08:00', '20:00'], bool remind = false}) =>
      repo.addDrug(DrugPlan(profileId: 1, name: name, times: times, remind: remind));

  Future<void> log(int id, String time, String state, {String? date}) => repo.logDrug(DrugLog(
      profileId: 1, drugId: id, date: date ?? dk, time: time, state: state));

  testWidgets('空白屏：档案空态＋读数不铺 0/0 与 0%＋脚注是医嘱那句', (tester) async {
    await pumpMed(tester);
    expect(find.byKey(const ValueKey('hmed-empty')), findsOneWidget);
    expect(find.text(medEmptyTx), findsOneWidget, reason: '空态句吃域层原话，卡片与屏不各写一遍');
    expect(keyText(tester, 'hmed-plan'), '—', reason: '没计划≠一次没吃，两回事');
    expect(keyText(tester, 'hmed-rate'), '依从 —');
    expect(keyText(tester, 'hmed-missed-none'), '今日无漏服', reason: 'n=0 不摆「漏服 0 次」');
    expect(keyText(tester, 'hmed-sym-tx'), '暂无用药相关症状');
    expect(keyText(tester, 'hmed-footnote'), medFootnoteTx);
    expect(find.byType(LHWheel), findsNothing, reason: '宽限滚轮收起态不占屏（点行才展开）');
  });

  testWidgets('卡内点一次打卡：概览、依从、行文案同帧改口；再点撤销回原状', (tester) async {
    final id = await drug('钙片');
    await pumpMed(tester);
    expect(keyText(tester, 'hmed-plan'), '0/2 次 · 今日');
    expect(keyText(tester, 'hmed-rate'), '依从 0%');
    expect(find.byKey(ValueKey('hmed-slot-$id-08:00')), findsOneWidget);

    await tapKey(tester, 'hmed-tap-$id-08:00');
    expect(keyText(tester, 'hmed-plan'), '1/2 次 · 今日', reason: '同一份 MedBundle，两处不会各算各的');
    expect(keyText(tester, 'hmed-rate'), '依从 50%');
    expect(find.text('08:00 · 钙片 打卡成功'), findsOneWidget);
    expect(find.text('已服用 · 可撤销'), findsOneWidget);
    expect(find.text('待服用'), findsOneWidget, reason: '20:00 那一行还没动');

    await clearToasts(tester);
    await tapKey(tester, 'hmed-tap-$id-08:00');
    expect(keyText(tester, 'hmed-plan'), '0/2 次 · 今日');
    expect(find.text('08:00 · 钙片 已撤销打卡'), findsOneWidget);
    expect(await repo.drugLogs(1, dk), isEmpty, reason: '撤销＝删行，不是留一行 pending');
    await clearToasts(tester);
  });

  testWidgets('skipped 流水不进 o、也不再被叫成漏服（刀1 靶：已服与有交代两条判据）',
      (tester) async {
    final id = await drug('降压药', times: const ['08:00']);
    await log(id, '08:00', 'skipped');
    await pumpMed(tester);

    expect(keyText(tester, 'hmed-plan'), '0/1 次 · 今日',
        reason: '把 slotTaken 换成 slotSettled 这里就变 1/1');
    expect(keyText(tester, 'hmed-missed-none'), '今日无漏服',
        reason: '08:00 早过了宽限，但用户交代过「跳过」，不该再被叫成漏服');
    expect(find.text('待服用'), findsOneWidget);
    expect(find.text('已服用 · 可撤销'), findsNothing);
    expect(find.byKey(ValueKey('hmed-card-missed-$id')), findsNothing);
  });

  testWidgets('漏服徽标：宽限滚轮改档当场写 prefs，补卡后徽标当场撤（设置必须当场生效）',
      (tester) async {
    final id = await drug('钙片', times: const ['08:00']);
    await pumpMed(tester); // now=10:30，08:00 过了 150 分钟，默认宽限 30
    expect(keyText(tester, 'hmed-missed'), '今日漏服 1 次');
    expect(find.text('超 30 分钟'), findsOneWidget);

    await tapKey(tester, 'hmed-grace-row');
    expect(find.byKey(const ValueKey('hmed-grace-wheel')), findsOneWidget,
        reason: '就地内嵌展开，不弹层');
    await spin(tester, 'hmed-grace-wheel', 2); // 15/30/60/120：30 档 +2 ＝ 120
    expect(prefs.getInt(HealthSettings.kMissedGrace), 120, reason: '选到哪档就当场写库，无保存钮');
    expect(find.text('超 120 分钟'), findsOneWidget);
    expect(keyText(tester, 'hmed-missed'), '今日漏服 1 次', reason: '150 > 120，四档里只有它豁免不了这条');

    // 反向：把 08:00 补上卡，漏服徽标当场消失（不是要退出重进才更新）。
    await clearToasts(tester);
    await tapKey(tester, 'hmed-tap-$id-08:00');
    expect(find.byKey(const ValueKey('hmed-missed')), findsNothing);
    expect(keyText(tester, 'hmed-missed-none'), '今日无漏服');
    await clearToasts(tester);
  });

  testWidgets('近 7 天热力按单药算：昨天服满＝绿、今天半格＝琥珀、隔壁药不受影响（刀2 靶）',
      (tester) async {
    final a = await drug('钙片'); // 08:00 · 20:00
    final b = await drug('铁剂', times: const ['09:00']);
    await log(a, '08:00', 'taken', date: y);
    await log(a, '20:00', 'taken', date: y);
    await log(a, '08:00', 'taken');
    await pumpMed(tester);

    // 七格＝旧→新，索引 5＝昨天，6＝今天。
    expect(cellColor(tester, 'hmed-heat-$a-5'), const Color(mdHeatFullHex),
        reason: '昨天两格计划两格都服了');
    expect(cellColor(tester, 'hmed-heat-$a-6'), const Color(mdHeatPartHex).withValues(alpha: .9),
        reason: '今天只打了 08:00，20:00 还没到点');
    expect(cellColor(tester, 'hmed-heat-$a-0'), neutral(tester, 'hmed-heat-$a-0'),
        reason: '六天前没有任何流水＝中性格，不是「全部服用」');
    // 另一支药（铁剂）昨天没有任何流水：它那一格不许跟钙片一起变绿。
    expect(cellColor(tester, 'hmed-heat-$b-5'), neutral(tester, 'hmed-heat-$b-5'),
        reason: '原型在每张卡里调全局 hMedPlan，同一行所有卡会一模一样＝假精确');
    expect(cellColor(tester, 'hmed-heat-$b-6'), neutral(tester, 'hmed-heat-$b-6'));
  });

  testWidgets('删除＝归档：卡少一张、计划分母少一格，流水一行不删', (tester) async {
    final keep = await drug('钙片', times: const ['08:00']);
    final gone = await drug('褪黑素', times: const ['21:00', '22:00']);
    await log(gone, '21:00', 'taken');
    await pumpMed(tester);
    expect(keyText(tester, 'hmed-plan'), '1/3 次 · 今日');

    await tapKey(tester, 'hmed-del-$gone');
    expect(find.text('删除「褪黑素」档案'), findsOneWidget, reason: '确认句吃域层原话');
    // 弹层按钮不在页面 ListView 的滚动范围内，ensureVisible 会找不到 Scrollable 而炸——直接 tap。
    await tester.tap(find.byKey(const ValueKey('d-confirm-ok')));
    await settle5(tester);
    expect(find.byKey(ValueKey('hmed-card-$gone')), findsNothing);
    expect(find.byKey(ValueKey('hmed-card-$keep')), findsOneWidget);
    expect(keyText(tester, 'hmed-plan'), '0/1 次 · 今日', reason: '归档档案退出今日计划');
    expect(find.text('已删除档案 · 历史打卡保留在流水'), findsOneWidget);
    expect((await repo.drugLogs(1, dk))[keep], isNull);
    final all = await repo.drugs(1, includeArchived: true);
    expect(all.where((d) => d.archived).map((d) => d.id), [gone]);
    expect((await repo.drugLogs(1, dk))[gone]!['21:00'], 'taken',
        reason: '删档案≠删历史（§五.8），批6 趋势还要读它');
    await clearToasts(tester);

    // 归档行不参与总开关的覆写行数。
    expect(await repo.setAllDrugRemind(1, false), 1, reason: '只剩在册那一支');
  });

  testWidgets('总开关覆写在册全部、归档不跟着改（偏离⑤＝全量覆写不记原状态）', (tester) async {
    final on = await drug('钙片', times: const ['08:00'], remind: true);
    final off = await drug('铁剂', times: const ['09:00']);
    final archived = await drug('旧药', times: const ['10:00']);
    await repo.archiveDrug(1, archived);
    await pumpMed(tester);
    expect(tester.widget<Switch>(find.byKey(const ValueKey('hmed-rem-all'))).value, isFalse,
        reason: '有一枚没开就不算「全开」');

    await tapKey(tester, 'hmed-rem-all');
    final byId = {for (final d in await repo.drugs(1, includeArchived: true)) d.id: d};
    expect(byId[on]!.remind, isTrue);
    expect(byId[off]!.remind, isTrue);
    expect(byId[archived]!.remind, isFalse, reason: '归档档案不参与总开关');
    expect(find.text('已全部开启提醒 · 排程随提醒中心上线生效'), findsOneWidget,
        reason: '排程批8 才接线，文案不许吹没做的事');
    await clearToasts(tester);

    // 开关读的是「是否已全开」，跟着档案列表走，不是独立偏好位。
    expect(tester.widget<Switch>(find.byKey(const ValueKey('hmed-rem-all'))).value, isTrue);
    expect(find.text('开关会覆写所有在册档案（不记得单药原状态）'), findsOneWidget);
  });

  testWidgets('空档案点总开关：给一句实话，不谎报「已全部开启」', (tester) async {
    await pumpMed(tester);
    expect(tester.widget<Switch>(find.byKey(const ValueKey('hmed-rem-all'))).value, isFalse);
    await tapKey(tester, 'hmed-rem-all');
    expect(find.text('还没有药品档案 · 先建档再开提醒'), findsOneWidget);
    expect(find.text('已全部开启提醒 · 排程随提醒中心上线生效'), findsNothing);
    await clearToasts(tester);
  });

  testWidgets('免打扰时段从判据反推：屏上是 23:00 – 07:00，不是写死的字面量', (tester) async {
    await pumpMed(tester);
    expect(keyText(tester, 'hmed-dnd-tx'), '23:00 – 07:00');
  });
}
