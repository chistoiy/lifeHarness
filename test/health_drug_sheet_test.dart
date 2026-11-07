import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/health/data/health_repository.dart';
import 'package:lifeharness/features/health/domain/health_drug.dart';
import 'package:lifeharness/features/health/presentation/health_providers.dart';
import 'package:lifeharness/features/health/presentation/health_sheets.dart';
import 'package:lifeharness/shared/widgets/lh_wheel.dart';

import 'helpers.dart';

/// 健康批5 · 建档弹层（原型 `index-health.html#sheetHDrug` ＋ `v2_js.js` 的 `hDrugOpen`/`hdAddT`/`hDrugSave`）。
///
/// 六条判定（工单执行面板第 3 项「常驻用例」）：
/// · **只有新增，没有编辑**（原型 `hDrugOpen()` 不带 id、保存走 push）：标题就钉「新增药品」，
///   弹层里不许出现任何改档承诺（工单 §2 偏离④）；
/// · 新增默认档整套＝原型可见态：时刻 chips 已含 `08:00`、时刻滚轮停在 08:00（96 档里的第 32 档）、
///   剂量滚轮停在 **1 片**（index 1，不是 0.5）、单位固定「片 · 每次」、提醒开关默认**开**；
/// · 时刻＝**就地滚轮 →「+ 加入」进 chips**，重复当场拒（`该时刻已存在`），chips 点一下摘掉；
///   全摘光后保存**回落 08:00**（空 `times` 永远判不出漏服，不许写空数组进档案）；
/// · 疗程日自校验：越界月份与 2 月 30 日当场拒收并留在弹层（`DateTime.tryParse` 会把越界值归一成
///   另一天，那条日期一旦落库漏服判定就永远对不上）；
/// · 规格／疗程留空写侧折成 **null**（原型把 `'—'` 存进 `spec` 列，本实现不占数据面＝偏离⑥）；
/// · 提示条原话吃域层 `medSavedTx`，且**不吹「已排程到通知中心」**（排程批8 才接线）。
///
/// 独立文件（全 app/大页 pump 拆文件口径）；日期一律相对固定钟 `now` 构造，禁写死今天。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 19, 10, 30);
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

  /// 宿主只给一枚开弹层的按钮：建档与 tick 走真实仓储（内存库）＋模块 providers。
  Future<void> pumpHost(WidgetTester tester) async {
    await useSurface(tester, const Size(420, 1900));
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
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
                  onPressed: () => showHealthDrugSheet(ctx),
                  child: const Text('建档入口'),
                )),
          ),
        ),
      ),
    ));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('open-sheet')));
    await settle5(tester);
  }

  /// 弹层体比外壳 640 上限高：底部那块（开关/疗程日/按钮）落在视口外，先滚进再点。
  Future<void> tapKey(WidgetTester t, String key) async {
    final f = find.byKey(ValueKey(key));
    await t.ensureVisible(f);
    await settle5(t);
    await t.tap(f);
    await settle5(t);
  }

  Future<void> typeKey(WidgetTester t, String key, String text) async {
    final f = find.byKey(ValueKey(key));
    await t.ensureVisible(f);
    await settle5(t);
    await t.enterText(f, text);
    await settle5(t);
  }

  String keyText(WidgetTester t, String key) =>
      (t.widget<Text>(find.byKey(ValueKey(key)))).data ?? '';

  int chipCount(WidgetTester t) => find
      .descendant(of: find.byKey(const ValueKey('hdrug-times')), matching: find.byType(InkWell))
      .evaluate()
      .length;

  /// 滚轮往上拖 n 格＝档位 +n（`_wheel` 用 itemExtent 28）。
  Future<void> spin(WidgetTester t, String wheelKey, int steps) async {
    await t.ensureVisible(find.byKey(ValueKey(wheelKey)));
    await settle5(t);
    await t.drag(find.byKey(ValueKey(wheelKey)), Offset(0, -28.0 * steps));
    await settle5(t);
  }

  Future<void> save(WidgetTester t) => tapKey(t, 'hdrug-save');

  testWidgets('新增默认档整套＝原型可见态：08:00 已在 chips、滚轮停第 32 档、剂量 1 片、提醒开',
      (tester) async {
    await pumpHost(tester);
    expect(find.text('新增药品'), findsOneWidget, reason: '只有新增：弹层不承诺改档（偏离④）');
    expect(find.byKey(const ValueKey('hdrug-time-08:00')), findsOneWidget);
    expect(chipCount(tester), 1);
    expect(tester.widget<LHWheel>(find.byKey(const ValueKey('hdrug-time-wheel'))).initialIndex, 32,
        reason: '96 档＝24 小时 ×4 刻，08:00 是第 32 档；刀口：把 medDefaultTime 改成 07:00 就红');
    expect(tester.widget<LHWheel>(find.byKey(const ValueKey('hdrug-dose-wheel'))).initialIndex, 1,
        reason: '原型新增默认 1 片（index 1），不是量程起点 0.5');
    expect(keyText(tester, 'hdrug-dose-unit'), '片 · 每次', reason: '单位＝原型硬编码，表单没有输入位');
    expect(tester.widget<Switch>(find.byKey(const ValueKey('hdrug-rem'))).value, isTrue,
        reason: '原型 toggle on');
    expect(find.byKey(const ValueKey('hs-date')), findsOneWidget, reason: '疗程日就地文本＋自校验，不拉系统选择器');
    expect(find.text('保存药品'), findsOneWidget);
    expect(find.text('名称'), findsOneWidget);
    expect(find.text('规格'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('hdrug-name'))).controller!.text,
        isEmpty, reason: '新增＝空表单：原型预填的 2026-10-19 是演示数据，不搬');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('hs-date'))).controller!.text, isEmpty);
  });

  testWidgets('空名保存：只出提示不建档、弹层不关（名称是档案唯一的必填位）', (tester) async {
    await pumpHost(tester);
    await save(tester);
    expect(find.text(medNameRequiredTx), findsOneWidget);
    expect(await repo.drugs(1), isEmpty);
    expect(find.byKey(const ValueKey('hdrug-save')), findsOneWidget, reason: '拒收就留在弹层，别把用户填的丢掉');
    await clearToasts(tester);
  });

  testWidgets('时刻重复当场拒；滚档加入两枚后 chips 升序、点一下摘掉', (tester) async {
    await pumpHost(tester);
    // 滚轮还停在 08:00 就点加入＝重复，原型 `hdAddT` 原话拒收，不长出第二枚。
    await tapKey(tester, 'hdrug-time-add');
    expect(find.text(medDupTimeTx), findsOneWidget);
    expect(chipCount(tester), 1);
    await clearToasts(tester);

    await spin(tester, 'hdrug-time-wheel', 4); // 08:00 → 09:00
    await tapKey(tester, 'hdrug-time-add');
    expect(find.text('已加入 09:00'), findsOneWidget);
    await clearToasts(tester);
    expect(chipCount(tester), 2);

    await spin(tester, 'hdrug-time-wheel', -8); // 09:00 → 07:00
    await tapKey(tester, 'hdrug-time-add');
    await clearToasts(tester);
    expect(find.byKey(const ValueKey('hdrug-time-07:00')), findsOneWidget);
    expect(chipCount(tester), 3, reason: '加入即升序排（原型 push 后 sort），不是 append-only');

    await tapKey(tester, 'hdrug-time-08:00'); // 再点＝摘掉
    expect(find.byKey(const ValueKey('hdrug-time-08:00')), findsNothing);
    expect(chipCount(tester), 2);
  });

  testWidgets('chips 全摘光后保存回落 08:00：空时刻的档案永远判不出漏服', (tester) async {
    await pumpHost(tester);
    await tapKey(tester, 'hdrug-time-08:00');
    expect(find.byKey(const ValueKey('hdrug-times-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('hdrug-times')), findsNothing);

    await typeKey(tester, 'hdrug-name', '维生素 D3');
    await save(tester);
    await settle5(tester);
    final d = (await repo.drugs(1)).single;
    expect(d.times, [medDefaultTime], reason: '域层兜底而不是让空数组进库');
    await clearToasts(tester);
  });

  testWidgets('疗程日非法当场拒收（越界月份／2 月 30 日都不许被 tryParse 归一成另一天）',
      (tester) async {
    await pumpHost(tester);
    await typeKey(tester, 'hdrug-name', '钙片');

    await typeKey(tester, 'hs-date', '2026-13-01');
    await save(tester);
    expect(find.text('疗程日期月份不合法'), findsOneWidget);
    expect(await repo.drugs(1), isEmpty, reason: '拒收＝不落库也不关窗');
    await clearToasts(tester);

    await typeKey(tester, 'hs-date', '2026-02-30');
    await save(tester);
    expect(find.text('疗程日期不存在'), findsOneWidget);
    expect(await repo.drugs(1), isEmpty);
    await clearToasts(tester);

    await typeKey(tester, 'hs-date', '2026-10-19');
    await save(tester);
    await settle5(tester);
    expect((await repo.drugs(1)).single.endDate, '2026-10-19');
    await clearToasts(tester);
  });

  testWidgets('保存落库整套：规格空＝null 不占数据列、剂量吃滚轮档、提醒随开关', (tester) async {
    await pumpHost(tester);
    await typeKey(tester, 'hdrug-name', '布洛芬');
    await spin(tester, 'hdrug-dose-wheel', 1); // 1 → 1.5
    await save(tester);
    await settle5(tester);
    final d = (await repo.drugs(1)).single;
    expect(d.name, '布洛芬');
    expect(d.spec, isNull, reason: '留空折成 null（原型把「—」存进 spec 列＝偏离⑥）');
    expect(d.unit, medUnit);
    expect(d.dose, 1.5, reason: '剂量吃滚轮当前档，不是写死 1');
    expect(d.times, ['08:00']);
    expect(d.remind, isTrue);
    expect(d.archived, isFalse);
    expect(container.read(healthTickProvider), greaterThan(0),
        reason: '写完必须 tick++：工作台卡与管理屏同帧长出新档案');
    expect(find.text('新增药品'), findsNothing, reason: '保存成功就关窗，不留一张已落库的表单');
    await clearToasts(tester);
  });

  testWidgets('提醒关掉再保存：文案说实话（不吹已排程），库里 remind=false', (tester) async {
    await pumpHost(tester);
    await typeKey(tester, 'hdrug-name', '益生菌');
    await tapKey(tester, 'hdrug-rem');
    expect(tester.widget<Switch>(find.byKey(const ValueKey('hdrug-rem'))).value, isFalse);
    await save(tester);
    await settle5(tester);
    expect(find.text('已建档 益生菌 · 未开启提醒'), findsOneWidget);
    expect(find.textContaining('已排程'), findsNothing, reason: '排程批8 才接线，文案不许吹没做的事');
    final d = (await repo.drugs(1)).single;
    expect(d.remind, isFalse);
    expect(d.profileId, 1, reason: '档案归属吃当前档案，不是写死 1 之外的谁');
    await clearToasts(tester);
  });
}
