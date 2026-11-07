import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/health/data/health_repository.dart';
import 'package:lifeharness/features/health/domain/health_calc.dart';
import 'package:lifeharness/features/health/domain/health_models.dart';
import 'package:lifeharness/features/health/presentation/health_providers.dart';
import 'package:lifeharness/features/health/presentation/health_sheets.dart';

import 'helpers.dart';

/// 健康批4 · 运动录入弹层（原型 `index-health.html#sheetHEx` + `hExMode`/`hExCalc`/`hExSave`）。
///
/// 七条判定（工单执行面板第 1、3 项）：
/// · 三模 seg＝**哪一项被算出来**：被算那列转成只读回显（不回写输入框），一填够两项就当场覆盖成算出来的值；
///   算不出时保留用户填的原值（`deriveExercise` 的「不悄悄清空」），原型是往输入框里写回，
///   偏离登记见批4 工单 §3；
/// · 无距离四类型（刀2 靶：`hasDistance` 摘成恒真 → 力量也长出一只距离框、落库带 km）
///   ＝距离/配速整列「不计」＋ seg 不铺，保存两列 null；
/// · 时长是唯一必填项：缺时长＝提示条「至少填一个时长」且**不落库**、弹层不关；
/// · 「再记一条」＝同日第二条并存（运动不按日期唯一，与身体数据的同日覆盖相反）；
/// · 编辑态＝按 id 行覆盖（跨档案那道 `profile_id=?` 闸由 `health_dao_test` 常驻钉，此处不重铺）；
/// · 来源「设备导入」灰位点了不生效（§九.6 只留字段）；计时预置带分钟数与来源；
/// · 距离单位只影响展示与录入解释，存储恒公制（§五.10）。
///
/// 独立文件（全 app/大页 pump 拆文件口径）；日期一律相对固定钟 `now` 构造。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 19, 10, 30);
  late Database db;
  late HealthRepository repo;
  late ProviderContainer container;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = HealthRepository(db);
  });

  tearDown(() => db.close());

  String dk(Duration ago) => dayKey(now.subtract(ago));

  /// 宿主只给一枚开弹层的按钮：建档走真实仓储（内存库），弹层吃模块 providers。
  Future<void> pumpHost(WidgetTester tester,
      {ExerciseRecord? editing,
      int? presetMinutes,
      String? presetSource,
      Map<String, Object> prefs = const {}}) async {
    await useSurface(tester, const Size(420, 1900));
    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      healthRepositoryProvider.overrideWithValue(repo),
      healthClockProvider.overrideWithValue(() => now),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(builder: (ctx) => FilledButton(
                  key: const ValueKey('open-sheet'),
                  onPressed: () => showHealthExerciseSheet(ctx,
                      editing: editing,
                      presetMinutes: presetMinutes,
                      presetSource: presetSource),
                  child: const Text('记一笔'),
                )),
          ),
        ),
      ),
    ));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('open-sheet')));
    await settle5(tester);
  }

  String calc(WidgetTester t) =>
      t.widget<Text>(find.byKey(const ValueKey('hx-calc'))).data ?? '';

  /// 同一 key 两种形态：可编辑＝TextField，只读回显＝Container。
  bool editable(WidgetTester t, String key) =>
      t.widget(find.byKey(ValueKey(key))) is TextField;

  String readout(WidgetTester t, String key) => t
      .widgetList<Text>(
          find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text)))
      .single
      .data ??
      '';

  Future<void> type(WidgetTester t, String key, String value) async {
    await t.tap(find.byKey(ValueKey(key)));
    await t.enterText(find.byKey(ValueKey(key)), value);
    await settle5(t);
  }

  Future<void> pick(WidgetTester t, String key) async {
    await t.tap(find.byKey(ValueKey(key)));
    await settle5(t);
  }

  /// 点保存/再记，返回提示条全文（提示语＝回灌成句，取全文再断言关键字段，不靠半句猜）。
  Future<String> press(WidgetTester t, String key) async {
    await t.tap(find.byKey(ValueKey(key)));
    for (var i = 0; i < 15 && find.byType(SnackBar).evaluate().isEmpty; i++) {
      await t.pump(const Duration(milliseconds: 80));
    }
    expect(find.byType(SnackBar), findsWidgets, reason: '$key 之后必须有提示条');
    final out = t
        .widgetList<Text>(
            find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)))
        .map((e) => e.data ?? '')
        .join(' ');
    await clearToasts(t);
    return out;
  }

  Future<String> save(WidgetTester t) => press(t, 'hx-save');

  Future<List<ExerciseRecord>> rows() => repo.exerciseRange(1, '2026-01-01', '2026-12-31');

  testWidgets('开屏：默认「跑步＋按距离」，配速列只读、距离与时长可填', (tester) async {
    await pumpHost(tester);
    expect(find.text('记录运动'), findsOneWidget);
    expect(find.byKey(const ValueKey('hx-mode')), findsOneWidget);
    expect(editable(tester, 'hx-km'), isTrue);
    expect(editable(tester, 'hx-min'), isTrue);
    expect(editable(tester, 'hx-pace'), isFalse, reason: 'pace 档＝配速是被算出来的那一列');
    expect(readout(tester, 'hx-pace'), '—');
    expect(calc(tester), '还需填一项');
    expect(find.byType(TextField), findsNWidgets(4),
        reason: '距离/时长/kcal/备注四只输入框，配速是回显框；零二段弹层');
    await pick(tester, 'hx-cancel');
  });

  testWidgets('填距离＋时长 → 配速当场回显并进提示条（三值闭合）', (tester) async {
    await pumpHost(tester);
    await type(tester, 'hx-km', '5');
    await type(tester, 'hx-min', '30');
    expect(readout(tester, 'hx-pace'), '6′00″');
    expect(calc(tester), '三值闭合 · 均配速 6′00″ /km · 估算消耗 315 kcal');

    expect(await save(tester),
        '已存 2026-09-19 · 跑步 30 分钟 · 5.0 km · 均配速 6′00″ · 315 kcal');
    final r = (await rows()).single;
    expect(r.type, '跑步');
    expect(r.distanceKm, 5);
    expect(r.durationMin, 30);
    expect(r.paceSec, 360);
    expect(r.kcal, 315, reason: '用户没填 kcal → 落库按 MET 估（§五.6）');
    expect(r.source, '手动');
    expect(r.date, dayKey(now));
  });

  testWidgets('切「按时长」：距离列转只读，填配速当场按 时长÷配速 覆盖（算不出就保留原输入，不悄悄清空）', (tester) async {
    await pumpHost(tester);
    await type(tester, 'hx-km', '5');
    await type(tester, 'hx-min', '30');
    await pick(tester, 'hx-mode-distance');
    expect(editable(tester, 'hx-km'), isFalse, reason: 'distance 档＝距离是被算出来的那一列');
    expect(editable(tester, 'hx-pace'), isTrue);
    expect(readout(tester, 'hx-km'), '5.0',
        reason: '配速没填＝算不出，按 `deriveExercise` 口径保留用户填的原值（悄悄清空才是坑）');
    await type(tester, 'hx-pace', "4'30\"");
    expect(readout(tester, 'hx-km'), '6.7', reason: '30 分 ÷ 4′30″/km ＝ 6.67 km，覆盖上一档的 5');
    await pick(tester, 'hx-cancel');
  });

  testWidgets('无距离类型（刀2 靶）：seg 不铺、距离/配速整列「不计」、落库两列 null',
      (tester) async {
    await pumpHost(tester);
    await type(tester, 'hx-km', '5');
    await pick(tester, 'hx-type-力量');
    expect(find.byKey(const ValueKey('hx-mode')), findsNothing,
        reason: '不计距离的类型没有三模可选，seg 整块不铺');
    expect(editable(tester, 'hx-km'), isFalse);
    expect(editable(tester, 'hx-pace'), isFalse);
    expect(readout(tester, 'hx-km'), '不计');
    expect(readout(tester, 'hx-pace'), '不计');
    expect(calc(tester), '该类型不计距离 · 只需填时长');
    await type(tester, 'hx-min', '45');
    expect(await save(tester), '已存 2026-09-19 · 力量 45 分钟 · 225 kcal');
    final r = (await rows()).single;
    expect(r.distanceKm, isNull);
    expect(r.paceSec, isNull);
    expect(r.kcal, 225, reason: '力量 MET 5.0 × 45 分');
  });

  testWidgets('缺时长＝不落库，只出提示条、弹层不关（不静默写 0 分钟）', (tester) async {
    await pumpHost(tester);
    await type(tester, 'hx-km', '5');
    expect(await save(tester), '至少填一个时长');
    expect(await rows(), isEmpty);
    expect(find.byKey(const ValueKey('hx-save')), findsOneWidget, reason: '用户还能补填');
    expect(find.text('记录运动'), findsOneWidget);
  });

  testWidgets('「再记一条」＝同日第二条并存（运动不按日期唯一）', (tester) async {
    await pumpHost(tester);
    await type(tester, 'hx-km', '5');
    await type(tester, 'hx-min', '30');
    expect(await press(tester, 'hx-again'),
        '已存 2026-09-19 · 跑步 30 分钟 · 5.0 km · 均配速 6′00″ · 315 kcal');
    expect(find.byKey(const ValueKey('hx-save')), findsOneWidget, reason: '再记＝弹层留在原地');
    await type(tester, 'hx-km', '3');
    await type(tester, 'hx-min', '20');
    expect(await save(tester),
        '已存 2026-09-19 · 跑步 20 分钟 · 3.0 km · 均配速 6′40″ · 210 kcal');
    final r = await rows();
    expect(r.length, 2, reason: '§五.9 同日多条各计一次，不许互相覆盖');
    expect(r.map((e) => e.durationMin).toSet(), {30, 20});
  });

  testWidgets('编辑态：标题带日期与类型，保存＝按 id 覆盖一条（不插第二条、不抹备注）', (tester) async {
    final id = await repo.addExercise(ExerciseRecord(
        profileId: 1,
        date: dk(Duration(days: 1)),
        type: '骑行',
        distanceKm: 20,
        durationMin: 60,
        paceSec: 180,
        kcal: 450,
        note: '河边'));
    final seeded = (await repo.exerciseRange(1, '2026-01-01', '2026-12-31')).single;
    await pumpHost(tester, editing: seeded);
    expect(find.text('修改 2026-09-18 的骑行'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('hx-km'))).controller!.text, '20.0');
    await type(tester, 'hx-min', '50');
    expect(await save(tester),
        '已存 2026-09-18 · 骑行 50 分钟 · 20.0 km · 均配速 2′30″ · 450 kcal');
    final r = await rows();
    expect(r.length, 1);
    expect(r.single.id, id);
    expect(r.single.durationMin, 50);
    expect(r.single.note, '河边', reason: '编辑没动备注就不许抹掉它');
  });

  testWidgets('来源：「设备导入」点了不生效；计时预置带分钟数与来源', (tester) async {
    await pumpHost(tester, presetMinutes: 25, presetSource: '计时');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('hx-min'))).controller!.text, '25');
    await type(tester, 'hx-km', '5');
    await pick(tester, 'hx-src-设备导入');
    await save(tester);
    final r = (await rows()).single;
    expect(r.source, '计时', reason: '灰位不许把来源改成「设备导入」（§九.6 只留字段）');
    expect(r.durationMin, 25);
    expect(r.startedAt, isNull);
  });

  testWidgets('mile 档：标签与配速后缀跟着换，存储仍折回公制（§五.10）', (tester) async {
    await pumpHost(tester, prefs: const {'flutter.health.km_unit': 'mile'});
    expect(find.text('距离 · mile'), findsOneWidget);
    expect(find.text('配速 /mile'), findsOneWidget);
    await type(tester, 'hx-km', '3.1');
    await type(tester, 'hx-min', '30');
    expect(calc(tester), contains('/mile'));
    expect(await save(tester), contains('3.1 mile'));
    final r = (await rows()).single;
    expect(r.distanceKm, closeTo(5.0, 0.05), reason: '录入按 mile 读数，库里恒 km');
  });
}
