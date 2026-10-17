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
import 'package:lifeharness/features/health/presentation/health_body_page.dart';
import 'package:lifeharness/features/health/presentation/health_providers.dart';
import 'package:lifeharness/features/health/presentation/health_routes.dart';

import 'helpers.dart';

/// 健康批3 · 身体数据屏（原型 `index-health.html#p-body` ＋ `hBodyChart`/`hPut('boWk'…)`）。
///
/// 五条判定（工单执行面板第 3 项＋§1 偏离登记）：
/// · **无实测的日子不画点**（刀1 靶：曲线取样摘掉 `r.kg != null` 就把「没测那天」连成趋势线，
///   屏上会出现用户从没测过的体重）；只填围度没填体重的那条同理；
/// · 30/90/365 **只是窗口**：副注、轴端、区间变化、计数行同帧跟着换，曲线与统计吃同一份取数；
/// · BMI 只由「体重＋身高」算，缺任一＝「—」，**不拿 170 兜底**；
/// · 单位（§五.10）只影响展示：斤档下体重读数与周变化/区间变化 ×2，**距目标恒按 kg**；
/// · 计数行如实说「窗口 30 天内仅 N 天有记录」，不写原型那句「超出区间按趋势补全」。
///
/// 独立文件（大页 pump 拆文件口径）；日期一律相对固定钟 `now` 构造。
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

  String dk(Duration ago) => dayKey(now.subtract(ago));

  Future<ProviderContainer> pumpBody(WidgetTester tester,
      {Map<String, Object> prefsValues = const {}}) async {
    await useSurface(tester, const Size(420, 2400));
    SharedPreferences.setMockInitialValues(prefsValues);
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
    router.push('/health/body');
    await settle5(tester);
    return container;
  }

  /// 键直挂在 Text 上的读数（轴端/副注/计数行/目标行）。
  String keyText(WidgetTester t, String key) =>
      t.widget<Text>(find.byKey(ValueKey(key))).data ?? '';

  /// 数据位/统计格：键挂在外层容器上，首个 Text＝读数，第二个＝标签。
  String firstText(WidgetTester t, String key) => t
      .widgetList<Text>(
          find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text)))
      .first
      .data ?? '';

  String labelText(WidgetTester t, String key) => t
      .widgetList<Text>(
          find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text)))
      .last
      .data ?? '';

  /// 八条连续实测（kg 逐条 −0.4，从 70.0 起）——周变化要满 8 条才算得出。
  Future<void> seedEight() async {
    for (var i = 0; i < 8; i++) {
      await repo.saveBody(BodyRecord(
          profileId: 1, date: dk(Duration(days: 9 - i)), kg: 70.0 - 0.4 * i));
    }
  }

  testWidgets('空白档案：四枚全「—」，曲线不铺、三统计不铺、计数行如实说 0 天', (tester) async {
    await pumpBody(tester);

    for (final k in ['hb-cell-kg', 'hb-cell-bmi', 'hb-cell-height', 'hb-cell-fat']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: '四枚数据位常驻');
      expect(firstText(tester, k), '—', reason: '$k 没读数只能出「—」，不补 0 也不补中位档');
    }
    expect(keyText(tester, 'hb-curve-empty'), '窗口内没有实测记录 · 暂无曲线');
    expect(find.descendant(
        of: find.byKey(HealthBodyPage.kCurve), matching: find.byType(CustomPaint)), findsNothing,
        reason: '没数据不画曲线层');
    expect(keyText(tester, 'hb-axis-lo'), '—');
    expect(keyText(tester, 'hb-axis-hi'), '—');
    for (final s in ['周变化', '区间变化', '距目标']) {
      expect(firstText(tester, 'hb-stat-$s'), '—');
    }
    expect(keyText(tester, 'hb-goal-tx'), '目标体重未设 · 在健康目标页设一档');
    expect(keyText(tester, 'hb-count'), '共 0 条实测 · 窗口 30 天内仅 0 天有记录');
    expect(find.text('该档案暂无身体数据'), findsOneWidget);
    expect(find.text('超出区间按趋势补全'), findsNothing, reason: '工单 §1：伪造补全的文案不搬进真机');
  });

  testWidgets('只填围度没填体重的那条不进曲线：两条记录仍「仅 1 条实测 · 连不成线」（刀1 靶）',
      (tester) async {
    await repo.saveBody(BodyRecord(profileId: 1, date: dk(const Duration(days: 3)), kg: 71.0));
    await repo.saveBody(BodyRecord(
        profileId: 1, date: dk(const Duration(days: 1)), waistCm: 76.0, fatPct: 18.0));
    await pumpBody(tester);

    expect(keyText(tester, 'hb-curve-empty'), '仅 1 条实测 · 连不成线',
        reason: '把 null 体重也当成点就连线＝画用户从没测过的读数');
    expect(firstText(tester, 'hb-stat-区间变化'), '—', reason: '实测点不足 2 个，区间变化算不出');
    // 流水行照实在列：那条体重位是「—」，围度摘要在位。
    expect(find.text('体脂18% · 腰76'), findsOneWidget);
    // 最新一条没体重 → 四枚读数回落到「最近一条」的缺项，不拿上一条的 71 冒充当前体重
    expect(firstText(tester, 'hb-cell-kg'), '—');
    expect(firstText(tester, 'hb-cell-bmi'), '—', reason: '体重都读不出，BMI 更不能凭空算');
    expect(firstText(tester, 'hb-cell-fat'), '18');

    await tester.tap(find.byKey(const ValueKey('hb-seg-365')));
    await settle5(tester);
    expect(keyText(tester, 'hb-curve-empty'), '仅 1 条实测 · 连不成线');
    expect(keyText(tester, 'hb-cur-tx'), '体重 · kg · 近 365 天');
    expect(keyText(tester, 'hb-count'), '共 2 条实测 · 窗口 365 天内仅 2 天有记录');
  });

  testWidgets('两条实测＝曲线铺开，轴端含目标线（原型 ±0.4 同式）', (tester) async {
    await repo.saveBody(BodyRecord(profileId: 1, date: dk(const Duration(days: 3)), kg: 71.0));
    await repo.saveBody(BodyRecord(profileId: 1, date: dk(const Duration(days: 1)), kg: 69.2));
    await repo.setGoal(1, GoalKeys.weightGoal, 65);
    await pumpBody(tester);

    expect(find.byKey(HealthBodyPage.kCurve), findsOneWidget);
    expect(keyText(tester, 'hb-axis-lo'), '64.6', reason: 'min(71.0,69.2,目标 65)−0.4＝目标线得落在校刻度内');
    expect(keyText(tester, 'hb-axis-hi'), '71.4');
    expect(keyText(tester, 'hb-goal-tx'), '目标 65.0 kg');
    expect(firstText(tester, 'hb-stat-区间变化'), '-1.8 kg');
    expect(firstText(tester, 'hb-stat-距目标'), '4.2 kg', reason: '最新 69.2 − 65；距目标恒按 kg');
    expect(keyText(tester, 'hb-count'), '共 2 条实测 · 窗口 30 天内仅 2 天有记录');
  });

  testWidgets('八条实测＝周变化按倒数第 8 条算；身高回落链让 BMI 算得出（不拿 170 兜底）',
      (tester) async {
    await seedEight();
    await repo.saveBody(BodyRecord(
        profileId: 1, date: dk(const Duration(days: 9)), kg: 70.0, heightCm: 175));
    await pumpBody(tester);

    // 第八档＝70.0-0.4×7＝67.2；基线＝倒数第 8 条＝70.0（同日覆盖：09-10 那次体重仍是 70.0）
    expect(firstText(tester, 'hb-stat-周变化'), '-2.8 kg');
    expect(firstText(tester, 'hb-stat-区间变化'), '-2.8 kg');
    expect(firstText(tester, 'hb-cell-kg'), '67.2');
    expect(labelText(tester, 'hb-cell-kg'), 'kg 体重');
    expect(firstText(tester, 'hb-cell-height'), '175');
    expect(firstText(tester, 'hb-cell-bmi'), '21.9', reason: '67.2 / 1.75² 实算，档案最近身高回填');
    expect(labelText(tester, 'hb-cell-bmi'), 'BMI 正常');
    expect(firstText(tester, 'hb-stat-距目标'), '—', reason: '没设目标体重＝距目标算不出，不拿 0 当差值');
  });

  testWidgets('记录不足 8 条＝周变化出「—」（原型 all[len-8] 的 NaN 不搬进真机）', (tester) async {
    for (var i = 0; i < 7; i++) {
      await repo.saveBody(BodyRecord(
          profileId: 1, date: dk(Duration(days: 8 - i)), kg: 70.0 - 0.4 * i));
    }
    await pumpBody(tester);
    expect(firstText(tester, 'hb-stat-周变化'), '—');
    expect(firstText(tester, 'hb-stat-区间变化'), '-2.4 kg', reason: '区间变化只看窗口首末，七条够算');
  });

  testWidgets('斤档：读数与周变化整套 ×2 带「斤」，距目标与目标行仍是 kg（§五.10）', (tester) async {
    await seedEight();
    await repo.setGoal(1, GoalKeys.weightGoal, 65);
    await pumpBody(tester, prefsValues: const {'health.kg_unit': '斤'});

    expect(firstText(tester, 'hb-cell-kg'), '134.4', reason: '67.2×2');
    expect(labelText(tester, 'hb-cell-kg'), '斤 体重');
    expect(keyText(tester, 'hb-cur-tx'), '体重 · 斤 · 近 30 天');
    expect(firstText(tester, 'hb-stat-周变化'), '-5.6 斤', reason: '变化量随单位换算（原型 boWk 同式）');
    expect(firstText(tester, 'hb-stat-区间变化'), '-5.6 斤');
    expect(firstText(tester, 'hb-stat-距目标'), '2.2 kg', reason: '原型 boG 就是 +" kg"，切单位不动它');
    expect(keyText(tester, 'hb-goal-tx'), '目标 65.0 kg');
  });

  testWidgets('切窗口：90 天把窗口外的首条纳进来，区间变化与计数行同帧重算', (tester) async {
    await repo.saveBody(BodyRecord(profileId: 1, date: dk(const Duration(days: 45)), kg: 74.0));
    await repo.saveBody(BodyRecord(profileId: 1, date: dk(const Duration(days: 3)), kg: 71.0));
    await repo.saveBody(BodyRecord(profileId: 1, date: dk(const Duration(days: 1)), kg: 69.2));
    await pumpBody(tester);

    expect(firstText(tester, 'hb-stat-区间变化'), '-1.8 kg', reason: '30 天窗口够不着 45 天前那条');
    expect(keyText(tester, 'hb-count'), '共 3 条实测 · 窗口 30 天内仅 2 天有记录');

    await tester.tap(find.byKey(const ValueKey('hb-seg-90')));
    await settle5(tester);
    expect(keyText(tester, 'hb-cur-tx'), '体重 · kg · 近 90 天');
    expect(firstText(tester, 'hb-stat-区间变化'), '-4.8 kg', reason: '74.0 → 69.2');
    expect(keyText(tester, 'hb-count'), '共 3 条实测 · 窗口 90 天内仅 3 天有记录');
    expect(keyText(tester, 'hb-axis-lo'), '68.8');
  });

  testWidgets('点行就地改（弹层回填原读数），＋记录走同一张弹层', (tester) async {
    final d2 = dk(const Duration(days: 2));
    await repo.saveBody(BodyRecord(profileId: 1, date: d2, kg: 71.0, heightCm: 175));
    final id = (await repo.bodyRange(1, '0000-01-01', dk(Duration.zero))).single.id!;
    await pumpBody(tester);

    await tester.tap(find.byKey(ValueKey('hb-row-$id')));
    // 弹层入场动画没走完时，屏上的按钮仍在屏幕下方（实测 hw-cancel 落在 y=3006），
    // pollText 只看文案在不在树里（离屏也算）会提前返回 → 先推完动画再点。
    await settle5(tester);
    expect(await pollText(tester, '修改 ${d2.substring(5)} 的记录'), isTrue);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('hw-save')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hw-cancel')));
    await settle5(tester);

    await tester.tap(find.byKey(const ValueKey('hb-add')));
    await settle5(tester);
    expect(await pollText(tester, '记录身体数据'), isTrue);
    expect(find.byKey(const ValueKey('hw-cancel')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hw-cancel')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('hw-save')), findsNothing);
  });

  testWidgets('删除＝确认门后落库，曲线与统计当场收回（取消一行都不动）', (tester) async {
    final d2 = dk(const Duration(days: 2));
    await repo.saveBody(BodyRecord(profileId: 1, date: d2, kg: 71.0));
    await repo.saveBody(BodyRecord(profileId: 1, date: dk(const Duration(days: 1)), kg: 69.2));
    Future<List<BodyRecord>> all() => repo.bodyRange(1, '0000-01-01', dk(Duration.zero));
    final id = (await all()).firstWhere((r) => r.date == d2).id!;
    final container = await pumpBody(tester);

    await tester.tap(find.byKey(ValueKey('hb-del-$id')));
    expect(await pollText(tester, '删除 $d2 的测量记录？曲线与统计会同步重算。'), isTrue);
    await tester.tap(find.byKey(const ValueKey('d-confirm-cancel')));
    await settle5(tester);
    expect(await all(), hasLength(2), reason: '取消就是取消');

    await tester.tap(find.byKey(ValueKey('hb-del-$id')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('d-confirm-ok')));
    expect(await pollText(tester, '已删除 · 曲线与 BMI 已重算'), isTrue);
    await settle5(tester);
    expect(await all(), hasLength(1));
    expect(find.byKey(ValueKey('hb-row-$id')), findsNothing);
    expect(container.read(healthTickProvider), 1, reason: '删完靠 tick 触发全模块重取');
    expect(keyText(tester, 'hb-curve-empty'), '仅 1 条实测 · 连不成线',
        reason: '曲线收回一格＝当场重画，不是留着已删那条的线段');
    await clearToasts(tester);
  });

  testWidgets('跨档案不聚合：另一档案的测量不进本档案的读数与曲线', (tester) async {
    final other = await repo.saveProfile(const HealthProfile(id: 0, name: '妈妈', rel: '母'));
    await repo.saveBody(BodyRecord(profileId: 1, date: dk(const Duration(days: 2)), kg: 71.0));
    await repo.saveBody(BodyRecord(profileId: other, date: dk(const Duration(days: 1)), kg: 55.0));
    await pumpBody(tester);

    expect(firstText(tester, 'hb-cell-kg'), '71.0', reason: '本档案最新一条，不是另一档案的 55');
    expect(keyText(tester, 'hb-count'), '共 1 条实测 · 窗口 30 天内仅 1 天有记录');
    expect(find.text('55.00'), findsNothing);
  });
}
