import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/health/data/health_repository.dart';
import 'package:lifeharness/features/health/domain/health_body.dart';
import 'package:lifeharness/features/health/domain/health_calc.dart';
import 'package:lifeharness/features/health/domain/health_models.dart';
import 'package:lifeharness/features/health/presentation/health_providers.dart';
import 'package:lifeharness/features/health/presentation/health_sheets.dart';
import 'package:lifeharness/shared/widgets/lh_wheel.dart';

import 'helpers.dart';

/// 健康批3 · 身体数据录入弹层（原型 `index-health.html#sheetHWeight` + `hRecOpen`/`hBodyPreview`/`hBodySave`）。
///
/// 六条判定（工单执行面板第 1、3 项）：
/// · **一张弹层七根就地内嵌滚轮**（体重整柱·小数柱·身高柱·四枚选填柱），零「点击→再弹一层」（红线 LH-K39）；
/// · **选填柱首档「—」＝不写入**（刀2 靶：把「—」当 0 或当最小档落库，屏上会凭空多出体脂 8%／腰围 50cm）；
/// · 同日重记＝整行覆盖（`saveBody` 按 (profile_id,date) 唯一索引 replace），所以编辑态的「—」
///   ＝**保留原值**：改体重不许把同行的腰围抹掉；
/// · 预览行的 BMI／距目标／周变化与落库后屏上读数是同一套数（不两处各算一遍）；
/// · 身高没填过 → BMI 出「—」，**不拿 170 兜底**（原型 `HT.height` 常开柱照抄就会造假）；
/// · 跨弹层写库不带发起页 ref（既定坑），保存后靠 tick 触发全模块重取。
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

  /// 宿主只给一枚开弹层的按钮：建档走真实仓储（内存库），弹层吃模块 providers。
  Future<void> pumpHost(WidgetTester tester, {BodyRecord? editing}) async {
    await useSurface(tester, const Size(420, 1600));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
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
                  onPressed: () => showHealthWeightSheet(ctx, editing: editing),
                  child: const Text('记一条'),
                )),
          ),
        ),
      ),
    ));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('open-sheet')));
    await settle5(tester);
  }

  String preview(WidgetTester t) => t
      .widget<Text>(find.descendant(
          of: find.byKey(const ValueKey('hw-preview')), matching: find.byType(Text)))
      .data!;

  String kgRead(WidgetTester t) => t.widget<Text>(find.byKey(const ValueKey('hw-kg'))).data ?? '';

  /// 第 i 根滚轮柱拖 n 档（正值＝往后一档）；单把不超过 8 档，免得惯性滑出目标档。
  Future<void> spin(WidgetTester t, int pickerIndex, int steps) async {
    var left = steps;
    while (left != 0) {
      final n = (left.abs() > 8 ? 8 : left.abs()) * left.sign;
      await t.drag(find.byType(CupertinoPicker).at(pickerIndex), Offset(0, -28.0 * n));
      await t.pump();
      await settle5(t);
      left -= n;
    }
  }

  Future<void> closeSheet(WidgetTester t) async {
    await t.tap(find.byKey(const ValueKey('hw-cancel')));
    await settle5(t);
  }

  /// 保存并等提示条（提示语＝回灌成句，逐字对上才继续）。
  Future<void> save(WidgetTester t, String toast, {String? reason}) async {
    await t.tap(find.byKey(const ValueKey('hw-save')));
    expect(await pollText(t, toast), isTrue, reason: reason ?? '保存提示语＝已记录＋读数＋BMI 分级');
  }

  testWidgets('开屏：七根滚轮就地内嵌＋八枚日期 chips，没有任何二段弹层', (tester) async {
    await pumpHost(tester);
    expect(find.byType(CupertinoPicker), findsNWidgets(7),
        reason: '体重整柱·小数柱·身高柱·四枚选填柱全在本层，禁「点击→弹层→再操作」');
    expect(find.byKey(const ValueKey('hw-dates')), findsOneWidget);
    // 日期行是横向**懒**列表：一屏只建得出前几枚，`findsNWidgets(8)` 数的是构建数不是可达数。
    // 判据按「滚到底，八枚都点得到」来钉（原型 `hDateRow`＝8 天 chips）。
    final chipKeys = [
      for (var i = 0; i < 8; i++) 'hw-date-${dayKey(now.subtract(Duration(days: i)))}'
    ];
    final seen = <String>{};
    void collect() {
      for (final k in chipKeys) {
        if (find.byKey(ValueKey(k)).evaluate().isNotEmpty) seen.add(k);
      }
    }

    collect();
    for (var round = 0; round < 4 && seen.length < chipKeys.length; round++) {
      await tester.drag(find.byKey(const ValueKey('hw-dates')), const Offset(-160, 0));
      await settle5(tester);
      collect();
    }
    expect(seen, hasLength(8), reason: '8 天 chips 逐枚可达，不是只给今天一枚');
    expect(seen, containsAll(<String>{chipKeys.first, chipKeys.last}),
        reason: '今天与第 8 天（最老那枚）都在行里');
    expect(find.text('记录身体数据'), findsOneWidget);
    expect(find.text('「—」＝不写入'), findsOneWidget);
    // 一条记录都没有 → 两柱落在种子档，四枚选填全停「—」
    expect(kgRead(tester), '69.0');
    for (final f in bodyOptionalFields) {
      expect(tester.widget<LHWheel>(find.byKey(ValueKey('hw-${f.col}'))).initialIndex, 0,
          reason: '${f.label} 新建默认不写入');
    }
    await closeSheet(tester);
  });

  testWidgets('新建：只体重落库，身高与四枚选填保持 null（刀2 靶：把「—」当最小档就红）',
      (tester) async {
    await pumpHost(tester);
    await save(tester, '已记录 ${dayKey(now)} · 69.0 kg · BMI —');
    final rec = (await repo.bodyRange(1, '2026-09-01', '2026-09-30')).single;
    expect(rec.kg, 69.0);
    expect(rec.heightCm, isNull);
    for (final f in bodyOptionalFields) {
      expect(bodyFieldValue(rec, f.col), isNull,
          reason: '${f.label} 停在「—」＝不写入，落 0/最小档就是凭空造读数');
    }
    expect(container.read(healthTickProvider), 1, reason: '写库靠 tick 触发全模块重取');
    await clearToasts(tester);
  });

  testWidgets('两柱合读＝录入值：整柱＋小数柱当场进读数与预览', (tester) async {
    await pumpHost(tester);
    expect(kgRead(tester), '69.0');
    await spin(tester, 0, 3); // 69 → 72
    expect(kgRead(tester), '72.0');
    expect(preview(tester), contains('预览 72.0 kg'));
    await spin(tester, 1, 4); // 小数 0 → 4
    expect(kgRead(tester), '72.4');
    expect(preview(tester), contains('预览 72.4 kg'));
    await closeSheet(tester);
    expect(await repo.bodyRange(1, '2026-09-01', '2026-09-30'), isEmpty, reason: '取消＝一行都不落');
  });

  testWidgets('身高柱带「—」：填了才出 BMI，没填出「—」而不是 170 兜底', (tester) async {
    await pumpHost(tester);
    expect(preview(tester), contains('BMI —'), reason: '身高停「—」＝算不出，不许假装正常');
    expect(preview(tester), isNot(contains('BMI — 正常')), reason: '算不出时不配分级');
    await spin(tester, 2, 1); // 「—」 → 140
    expect(preview(tester), contains('BMI ${bmi(kg: 69, cm: 140)!.toStringAsFixed(1)} 肥胖'));
    await spin(tester, 2, 32); // 140 → 172
    expect(kgRead(tester), '69.0');
    await save(tester, '已记录 ${dayKey(now)} · 69.0 kg · BMI ${bmi(kg: 69, cm: 172)!.toStringAsFixed(1)}（正常）');
    final rec = (await repo.bodyRange(1, '2026-09-01', '2026-09-30')).single;
    expect(rec.heightCm, 172, reason: '滚过的那一档才写入身高');
    await clearToasts(tester);
  });

  testWidgets('选填柱：只有滚过的那一枚落库，其余三枚仍不写入', (tester) async {
    await pumpHost(tester);
    await spin(tester, 3, 21); // 体脂「—」→ 第 21 档
    final fat = bodyField('fat').valueAt(21)!;
    await save(tester, '已记录 ${dayKey(now)} · 69.0 kg · BMI —');
    final rec = (await repo.bodyRange(1, '2026-09-01', '2026-09-30')).single;
    expect(rec.fatPct, fat);
    expect(rec.waistCm, isNull);
    expect(rec.hipCm, isNull);
    expect(rec.neckCm, isNull);
    expect(bodyExtrasTx(rec), '体脂${BodyField.trim(fat)}%', reason: '缺档不占位');
    await clearToasts(tester);
  });

  testWidgets('编辑＝整行覆盖下「—」保留原值：改体重不许抹掉腰围（刀2 的兄弟口径）',
      (tester) async {
    await repo.saveBody(const BodyRecord(
        profileId: 1, date: '2026-09-18', kg: 70, heightCm: 172, waistCm: 76, fatPct: 18));
    final editing = (await repo.bodyRange(1, '2026-09-01', '2026-09-30')).single;
    await pumpHost(tester, editing: editing);

    expect(find.text('修改 09-18 的记录'), findsOneWidget);
    expect(kgRead(tester), '70.0');
    expect(preview(tester), contains('BMI ${bmi(kg: 70, cm: 172)!.toStringAsFixed(1)}'));
    expect(preview(tester), contains('距目标 未设'), reason: '没设目标体重就不编差值');

    await spin(tester, 0, -2); // 70 → 68
    expect(preview(tester), contains('预览 68.0 kg'));
    await save(tester,
        '已记录 2026-09-18 · 68.0 kg · BMI ${bmi(kg: 68, cm: 172)!.toStringAsFixed(1)}（正常）');

    final rows = await repo.bodyRange(1, '2026-09-01', '2026-09-30');
    expect(rows.length, 1, reason: '同日重记＝覆盖，不许插第二行');
    expect(rows.single.kg, 68.0);
    expect(rows.single.waistCm, 76, reason: '腰围柱停在原档＝原值保留（整行 replace 下写 null 就抹掉了）');
    expect(rows.single.fatPct, 18);
    expect(rows.single.heightCm, 172);
    await clearToasts(tester);
  });

  testWidgets('日期 chips 选前天＝归属日跟着走（覆盖那天的同档案行）', (tester) async {
    await repo.saveBody(const BodyRecord(profileId: 1, date: '2026-09-17', kg: 71));
    await pumpHost(tester);
    await tester.tap(find.byKey(ValueKey('hw-date-2026-09-17')));
    await settle5(tester);
    await save(tester, '已记录 2026-09-17 · 71.0 kg · BMI —',
        reason: '新建种子＝档案最近一次实测 71.0，点前天那条就是覆盖它');
    final rows = await repo.bodyRange(1, '2026-09-01', '2026-09-30');
    expect(rows.length, 1, reason: '09-17 那行被覆盖，不是新增第二条');
    expect(rows.single.kg, 71.0);
    await clearToasts(tester);
  });

  testWidgets('预览的距目标／周变化与域层同一套数（目标进 prefs/DB 分治的 db 侧）', (tester) async {
    for (var i = 0; i < 8; i++) {
      await repo.saveBody(BodyRecord(
          profileId: 1,
          date: dayKey(now.subtract(Duration(days: 9 - i))),
          kg: 70 - i * 0.5,
          heightCm: 172));
    }
    await repo.setGoal(1, 'weight_goal', 65);
    await pumpHost(tester);
    final all = await repo.bodyRange(1, '2000-01-01', dayKey(now));
    final seed = latestKg(all)!;
    final baseline = bodyWeekBaseline(all)!;
    expect(all.length, 8);
    expect(kgRead(tester), seed.toStringAsFixed(1), reason: '录入起步＝最近一次实测');
    expect(preview(tester), contains('距目标 ${bodyGoalTx(seed - 65)}'));
    expect(preview(tester), contains('周变化 ${bodyDeltaTx(seed - baseline, 'kg')}'));
    await closeSheet(tester);
  });

  testWidgets('编辑态回填：身高与四枚选填停在原档，不重滚就不动', (tester) async {
    await repo.saveBody(const BodyRecord(
        profileId: 1, date: '2026-09-18', kg: 70, heightCm: 172, fatPct: 20, neckCm: 37));
    final editing = (await repo.bodyRange(1, '2026-09-01', '2026-09-30')).single;
    await pumpHost(tester, editing: editing);
    expect(tester.widget<LHWheel>(find.byKey(const ValueKey('hw-height'))).initialIndex,
        heightIndexOf(172));
    expect(tester.widget<LHWheel>(find.byKey(const ValueKey('hw-fat'))).initialIndex,
        bodyField('fat').indexOf(20));
    expect(tester.widget<LHWheel>(find.byKey(const ValueKey('hw-neck'))).initialIndex,
        bodyField('neck').indexOf(37));
    expect(tester.widget<LHWheel>(find.byKey(const ValueKey('hw-waist'))).initialIndex, 0,
        reason: '原本没记腰围＝回到「—」，不是最近档凑一个');
    await closeSheet(tester);
  });

  testWidgets('取消＝不落库、tick 不动', (tester) async {
    await pumpHost(tester);
    await spin(tester, 0, 5);
    await closeSheet(tester);
    expect(find.byKey(const ValueKey('hw-save')), findsNothing);
    expect(await repo.bodyRange(1, '2026-09-01', '2026-09-30'), isEmpty);
    expect(container.read(healthTickProvider), 0);
  });
}
