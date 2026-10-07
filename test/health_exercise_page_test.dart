import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/health/data/health_repository.dart';
import 'package:lifeharness/features/health/domain/health_models.dart';
import 'package:lifeharness/features/health/presentation/health_exercise_page.dart';
import 'package:lifeharness/features/health/presentation/health_providers.dart';
import 'package:lifeharness/features/health/presentation/health_routes.dart';
import 'package:lifeharness/shared/widgets/ui_kit.dart';

import 'helpers.dart';

/// 健康批4 · 运动记录屏（原型 `index-health.html#p-exLog`）。
///
/// 五条判定（工单执行面板第 4 项）：
/// · **四数据位＝窗口∩过滤**（原型 `hRenderExLog` 拿过滤后的 list 求和）：点「跑步」四枚一起换档，
///   不是只换流水（刀：把 cells 的数据源从 `shown` 改回 `win` 就红）；
/// · **本周/本月只是同一份取数的两种切片**：切窗口时四枚＋流水同步变，
///   而配速趋势吃「最近 12 次」（全量），不跟着窗口换档；
/// · 趋势**两点起步**且只收距离类：力量/瑜伽/其他永不进曲线（无距离类不糊配速）；
/// · 类型角标只给真出现过的类型——「全部」与零条类不写 0（写 0 会被读成「有 0 次」）；
/// · 单位只影响展示（§五.10）：mile 档下距离读数、配速、后缀整套换，流水与四枚同源。
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

  /// 运动屏 pump：建库＋固定钟＋模块真实路由（栈页一律 push）。
  Future<(ProviderContainer, GoRouter)> pumpEx(WidgetTester tester,
      {String kmUnit = 'km'}) async {
    await useSurface(tester, const Size(420, 2400));
    SharedPreferences.setMockInitialValues({'health.km_unit': kmUnit});
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
    router.push('/health/exercise');
    await settle5(tester);
    return (container, router);
  }

  /// 数据位＝同键 Container 下的两行文本（读数 + 标签），一次取全，免得数错列。
  List<String> cell(WidgetTester t, String key) => t
      .widgetList<Text>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text)))
      .map((x) => x.data ?? '')
      .toList();

  String keyText(WidgetTester t, String key) => (t.widget<Text>(find.byKey(ValueKey(key)))).data ?? '';

  /// 流水行的键序（最新在上）。
  List<String> rowKeys(WidgetTester t) => t
      .widgetList<InkWell>(find.byType(InkWell))
      .map((r) => r.key)
      .whereType<ValueKey<String>>()
      .map((k) => k.value)
      .where((v) => v.startsWith('hex-row-'))
      .toList();

  /// 四条种子：三条落本周（09-13~09-19），一条落月初＝只在本月窗内。
  /// A 跑步 5km/30 分（配速存 360）、B 骑行 20km/60 分（180）、C 力量 45 分（无距离）、D 步行 3km/40 分（配速留空）。
  Future<(int, int, int, int)> seedFour() async {
    final a = await repo.addExercise(const ExerciseRecord(
        profileId: 1, date: '2026-09-18', type: '跑步', distanceKm: 5.0, durationMin: 30, paceSec: 360, kcal: 315));
    final b = await repo.addExercise(const ExerciseRecord(
        profileId: 1, date: '2026-09-15', type: '骑行', distanceKm: 20.0, durationMin: 60, paceSec: 180, kcal: 500));
    final c = await repo.addExercise(
        const ExerciseRecord(profileId: 1, date: '2026-09-17', type: '力量', durationMin: 45, kcal: 225));
    final d = await repo.addExercise(const ExerciseRecord(
        profileId: 1, date: '2026-09-01', type: '步行', distanceKm: 3.0, durationMin: 40, kcal: 150));
    return (a, b, c, d);
  }

  testWidgets('空白档案：四枚出 0、流水空态、趋势不足 2 次不给曲线', (tester) async {
    await pumpEx(tester);
    expect(cell(tester, 'hex-cell-count'), ['0', '次数']);
    expect(cell(tester, 'hex-cell-min'), ['0', '总时长 · 分']);
    expect(cell(tester, 'hex-cell-km'), ['0', '总距离 · km'], reason: '0 km 出「0」而不是「0.0」，空就是空');
    expect(cell(tester, 'hex-cell-kcal'), ['0', '总消耗 · kcal']);
    expect(find.byType(EmptyDashRow), findsOneWidget);
    expect(find.text('该区间暂无运动记录'), findsOneWidget);
    expect(find.byKey(HealthExercisePage.kList), findsNothing);
    expect(find.byKey(const ValueKey('hex-trend-empty')), findsOneWidget);
    expect(keyText(tester, 'hex-trend-note'), '—', reason: '没有曲线就没有副注，不印「最近 0 次」');
    expect(find.byKey(const ValueKey('hex-add')), findsOneWidget);
  });

  testWidgets('本周/本月＝同一份取数的两种切片：四枚与流水同步换，趋势不跟窗口', (tester) async {
    final (a, b, c, d) = await seedFour();
    await pumpEx(tester);

    // 本周（09-13~09-19）＝A/B/C：3 次 135 分 25.0 km 1040 kcal。
    expect(cell(tester, 'hex-cell-count'), ['3', '次数']);
    expect(cell(tester, 'hex-cell-min'), ['135', '总时长 · 分']);
    expect(cell(tester, 'hex-cell-km'), ['25.0', '总距离 · km']);
    expect(cell(tester, 'hex-cell-kcal'), ['1040', '总消耗 · kcal']);
    expect(rowKeys(tester), ['hex-row-$a', 'hex-row-$c', 'hex-row-$b'], reason: '最新在上，同日保持原序');
    expect(find.byKey(ValueKey('hex-row-$d')), findsNothing);

    // 本月（08-21~09-19）多出 D：四枚一起抬，流水补一行。
    await tester.tap(find.byKey(const ValueKey('hex-seg-30')));
    await settle5(tester);
    expect(cell(tester, 'hex-cell-count'), ['4', '次数']);
    expect(cell(tester, 'hex-cell-min'), ['175', '总时长 · 分']);
    expect(cell(tester, 'hex-cell-km'), ['28.0', '总距离 · km']);
    expect(cell(tester, 'hex-cell-kcal'), ['1190', '总消耗 · kcal']);
    expect(find.byKey(ValueKey('hex-row-$d')), findsOneWidget);

    // 趋势口径＝距离类最近 12 次（全量），不跟着窗口换档：D 在两个窗口里都进曲线。
    expect(keyText(tester, 'hex-trend-note'), '最近 3 次 · 每 km');
    expect(find.descendant(of: find.byKey(HealthExercisePage.kTrend), matching: find.byType(CustomPaint)),
        findsWidgets);

    await tester.tap(find.byKey(const ValueKey('hex-seg-7')));
    await settle5(tester);
    expect(cell(tester, 'hex-cell-count'), ['3', '次数'], reason: '切回来立刻重算，不吃上一次的切片');
    expect(keyText(tester, 'hex-trend-note'), '最近 3 次 · 每 km');
  });

  testWidgets('类型过滤同步换四枚：次数/时长/距离/kcal 一起收窄，不是只换流水', (tester) async {
    final (a, b, c, _) = await seedFour();
    await pumpEx(tester);

    await tester.tap(find.byKey(const ValueKey('hex-filter-跑步')));
    await settle5(tester);
    expect(cell(tester, 'hex-cell-count'), ['1', '次数']);
    expect(cell(tester, 'hex-cell-min'), ['30', '总时长 · 分']);
    expect(cell(tester, 'hex-cell-km'), ['5.0', '总距离 · km']);
    expect(cell(tester, 'hex-cell-kcal'), ['315', '总消耗 · kcal']);
    expect(rowKeys(tester), ['hex-row-$a']);
    expect(find.byKey(ValueKey('hex-row-$b')), findsNothing);
    expect(find.byType(EmptyDashRow), findsNothing);

    // 切到本月再过滤：窗口与过滤两个维度叠起来算（4 条里跑步仍只有 A 一条）。
    await tester.tap(find.byKey(const ValueKey('hex-seg-30')));
    await settle5(tester);
    expect(cell(tester, 'hex-cell-count'), ['1', '次数']);

    // 回「全部」＝整套恢复。
    await tester.tap(find.byKey(const ValueKey('hex-filter-全部')));
    await settle5(tester);
    expect(cell(tester, 'hex-cell-count'), ['4', '次数']);
    expect(rowKeys(tester).length, 4);
    expect(find.byKey(ValueKey('hex-row-$c')), findsOneWidget);
  });

  testWidgets('过滤角标只给真出现过的类型：「全部」与零条类不写 0', (tester) async {
    await seedFour();
    await pumpEx(tester);
    final labels = tester.widgetList<PillChip>(find.byType(PillChip)).map((c) => c.label).toList();
    expect(labels, contains('全部'), reason: '「全部」不是类型名，不带条数角标');
    expect(labels, containsAll(<String>['跑步 1', '骑行 1', '力量 1']));
    expect(labels.where((l) => l.endsWith(' 0')), isEmpty);
    expect(labels.where((l) => l == '全部 4'), isEmpty, reason: '四枚数据位的次数才随窗口变，角标是全域条数');
    expect(labels.first, '全部');
  });

  testWidgets('无距离类不进趋势也不配速回显（力量只有时长）', (tester) async {
    await repo.addExercise(
        const ExerciseRecord(profileId: 1, date: '2026-09-18', type: '力量', durationMin: 45, kcal: 225));
    await repo.addExercise(const ExerciseRecord(
        profileId: 1, date: '2026-09-17', type: '瑜伽', durationMin: 60, kcal: 180));
    await pumpEx(tester);
    expect(find.byKey(const ValueKey('hex-trend-empty')), findsOneWidget,
        reason: '两条都在但都不是距离类——趋势不足 2 次，不拿时长糊一条配速曲线');
    expect(keyText(tester, 'hex-trend-note'), '—');
    expect(find.text('力量 · 45min'), findsOneWidget);
    expect(find.textContaining('均配速'), findsNothing);
    expect(cell(tester, 'hex-cell-km'), ['0', '总距离 · km']);
  });

  testWidgets('距离类只有一条：曲线仍不给（两点起步），流水照出', (tester) async {
    final id = await repo.addExercise(const ExerciseRecord(
        profileId: 1, date: '2026-09-18', type: '跑步', distanceKm: 5.0, durationMin: 30, kcal: 315));
    await pumpEx(tester);
    expect(find.byKey(const ValueKey('hex-trend-empty')), findsOneWidget);
    expect(find.byKey(ValueKey('hex-row-$id')), findsOneWidget);
    // 配速留空＝按 时长÷距离 现算回显（30 分 ÷5km ＝ 6′00″）。
    expect(keyText(tester, 'hex-pace-$id'), '6′00″');
  });

  testWidgets('删除走二次确认：取消不动一行，确认后四枚与趋势同帧收回', (tester) async {
    final (a, b, c, _) = await seedFour();
    await pumpEx(tester);
    expect(cell(tester, 'hex-cell-count'), ['3', '次数']);

    await tester.tap(find.byKey(ValueKey('hex-del-$a')));
    await settle5(tester);
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(find.text('删除 2026-09-18 的跑步记录？流水与统计会同步重算。'), findsOneWidget);
    await tester.tap(find.descendant(of: dialog, matching: find.text('取消')));
    await settle5(tester);
    expect(find.byKey(ValueKey('hex-row-$a')), findsOneWidget);
    expect(cell(tester, 'hex-cell-count'), ['3', '次数']);

    await tester.tap(find.byKey(ValueKey('hex-del-$a')));
    await settle5(tester);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('删除')));
    await settle5(tester);
    expect(find.byKey(ValueKey('hex-row-$a')), findsNothing);
    expect(cell(tester, 'hex-cell-count'), ['2', '次数']);
    expect(cell(tester, 'hex-cell-min'), ['105', '总时长 · 分'], reason: '135-30：四枚与流水同一份取数');
    expect(cell(tester, 'hex-cell-km'), ['20.0', '总距离 · km']);
    expect(cell(tester, 'hex-cell-kcal'), ['725', '总消耗 · kcal']);
    // 趋势同步收窄：距离类从 3 条掉到 2 条（B/D），仍够两点但副注得跟着改口。
    expect(keyText(tester, 'hex-trend-note'), '最近 2 次 · 每 km');
    expect(find.byKey(const ValueKey('hex-trend-empty')), findsNothing);
    expect(find.text('已删除 · 统计与趋势已重算'), findsOneWidget);
    expect(await repo.exerciseRange(1, '2026-09-18', '2026-09-18'), isEmpty);
    expect(rowKeys(tester), ['hex-row-$c', 'hex-row-$b'], reason: '剩下的两条按日期倒序，相对顺序不变');
  });

  testWidgets('点流水行＝就地改（带 id 与类型），顶栏与卡内「＋ 记一笔」都开录入弹层', (tester) async {
    final (a, _, _, _) = await seedFour();
    await pumpEx(tester);

    await tester.tap(find.byKey(ValueKey('hex-row-$a')));
    await settle5(tester);
    expect(find.text('修改 2026-09-18 的跑步'), findsOneWidget);
    expect(find.byKey(const ValueKey('hx-save')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hx-cancel')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('hx-save')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('hex-add')));
    await settle5(tester);
    expect(find.text('记录运动'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hx-cancel')));
    await settle5(tester);

    await tester.tap(find.byKey(const ValueKey('hex-add-inline')));
    await settle5(tester);
    expect(find.text('记录运动'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hx-cancel')));
    await settle5(tester);
    expect(rowKeys(tester).length, 3, reason: '三次开关弹层都不该改写流水');
  });

  testWidgets('弹层保存后当场回灌：四枚＋流水＋趋势同帧更新（tick 失效，不是各读各的）', (tester) async {
    await seedFour();
    await pumpEx(tester);
    await tester.tap(find.byKey(const ValueKey('hex-add')));
    await settle5(tester);

    await tester.enterText(find.byKey(const ValueKey('hx-min')), '20');
    await tester.enterText(find.byKey(const ValueKey('hx-km')), '4');
    await tester.tap(find.byKey(const ValueKey('hx-save')));
    await settle5(tester);

    expect(cell(tester, 'hex-cell-count'), ['4', '次数']);
    expect(cell(tester, 'hex-cell-min'), ['155', '总时长 · 分']);
    expect(cell(tester, 'hex-cell-km'), ['29.0', '总距离 · km']);
    // kcal 留空＝按 MET 现算（跑步 20 分 → 210），四枚与提示条同源。
    expect(cell(tester, 'hex-cell-kcal'), ['1250', '总消耗 · kcal']);
    expect(find.byKey(const ValueKey('hex-trend-empty')), findsNothing,
        reason: '新增一条距离类＝趋势 4 条，从空态起来');
    expect(keyText(tester, 'hex-trend-note'), '最近 4 次 · 每 km');
  });

  testWidgets('mile 档：距离读数、配速与后缀整套换档（存储恒公制）', (tester) async {
    final (a, _, _, _) = await seedFour();
    await pumpEx(tester, kmUnit: 'mile');
    expect(cell(tester, 'hex-cell-km'), ['15.5', '总距离 · mile'], reason: '25 km × 0.621371 ＝ 15.5');
    expect(find.text('跑步 · 3.1 mile · 30min'), findsOneWidget);
    expect(keyText(tester, 'hex-pace-$a'), '9′39″', reason: '360 秒/公里 → 每英里 579 秒');
    expect(keyText(tester, 'hex-trend-note'), '最近 3 次 · 每 mile');
    // 存储没被换档污染。
    final stored = await repo.exerciseRange(1, '2026-09-18', '2026-09-18');
    expect(stored.single.distanceKm, 5.0);
    expect(stored.single.paceSec, 360);
  });
}
