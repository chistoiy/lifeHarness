import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/health/data/health_repository.dart';
import 'package:lifeharness/features/health/domain/health_calc.dart';
import 'package:lifeharness/features/health/domain/health_vital.dart';
import 'package:lifeharness/features/health/presentation/health_providers.dart';
import 'package:lifeharness/features/health/presentation/health_sheets.dart';

import 'helpers.dart';

/// 健康批2.5 · 体征录入弹层（原型 `tools/health/v2_sheets.html#sheetHVital` + `vt*` 行为）。
///
/// 四条判定（工单执行面板第 3 项＋AGENTS 红线）：
/// · 数值/时刻**全部就地内嵌滚轮**（LH-K39）：一张表单里时·分＋N 列数值，禁两段式、不拉系统选择器；
/// · 切类型＝字段组与时段整套换掉（原型 `vtSetType`），旧类的时段与题注不跨类残留；
/// · 参考区间只吃 `health_calc.vitalRef` 一处，**同一行不重复印两遍**（无基线时 `deltaText`
///   回落的就是那句参考文案）；血氧的 999 是「无上限」哨兵，只印「参考 ≥95 %」；
/// · 未填数值的默认档＝区间中点（原型 `(lo+hi)/2`）：算成「半程步数」会把收缩压顶到 205、
///   体温顶到 73.5，一开屏就报「超出参考范围」。
///
/// 弹层单独成文件（大页 pump 拆文件口径）；日期一律相对固定钟 `now` 构造。
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

  /// 宿主只给一枚开弹层的按钮：弹层吃模块真实 providers（仓储覆盖成内存库）。
  Future<void> pumpHost(WidgetTester tester, {String? kind, HealthVital? editing}) async {
    await useSurface(tester, const Size(420, 1400));
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
                  onPressed: () => showHealthVitalSheet(ctx, kind: kind, editing: editing),
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

  String preview(WidgetTester t) => t
      .widget<Text>(find.descendant(
          of: find.byKey(const ValueKey('hv-preview')), matching: find.byType(Text)))
      .data!;

  /// 时刻读数位（键直接挂在 Text 上，`find.descendant` 不含自身，只能直取）。
  String timeRead(WidgetTester t) =>
      t.widget<Text>(find.byKey(const ValueKey('hv-time'))).data ?? '';

  /// 第 i 根滚轮柱（弹层里的序＝时·分·字段 1..n），拖 n 档（正值＝往后一档）。
  Future<void> spin(WidgetTester t, int pickerIndex, int steps) async {
    await t.drag(find.byType(CupertinoPicker).at(pickerIndex), Offset(0, -28.0 * steps));
    await t.pump();
    await settle5(t);
  }

  Future<void> closeSheet(WidgetTester t) async {
    await t.tap(find.byKey(const ValueKey('hv-cancel')));
    await settle5(t);
  }

  testWidgets('开屏＝血压：三列数值滚轮就地内嵌，默认档取区间中点', (tester) async {
    await pumpHost(tester);
    // 时·分＋收缩压·舒张压·心率＝五根柱，全在弹层里，没有任何「点了再弹」的二段式。
    expect(find.byType(CupertinoPicker), findsNWidgets(5));
    expect(find.text('记录体征'), findsOneWidget);
    expect(preview(tester), contains('血压 135/85 mmHg'),
        reason: '默认＝中点（原型 (lo+hi)/2）；顶到 205 就是「半程」换算算错了');
    expect(preview(tester), contains('落在参考范围'));
    // 血压吃自己的六档时段，血糖那套档位在屏上不该出现
    expect(find.byKey(const ValueKey('hv-slot-晨起空腹')), findsOneWidget);
    expect(find.byKey(const ValueKey('hv-slot-空腹')), findsNothing);
    await closeSheet(tester);
  });

  testWidgets('参考区间同一行只印一遍（没基线就不编「较基线」）', (tester) async {
    await pumpHost(tester);
    final tx = preview(tester);
    // 数「区间整段」的出现次数，不是数「参考」二字——状态旗本身就叫「落在参考范围」，
    // 按二字计数会把 2 次当成重复印（真重复是 refLabel 与 deltaText 回落句各印一遍）。
    final ref = vitalSpecs['bp']!.refLabel;
    expect(tx.split(ref).length - 1, 1, reason: '区间只印一遍；实际文案：$tx');
    expect(tx, contains(ref));
    expect(tx, isNot(contains('较基线')), reason: '「本人」没有基线行，不编造比较');
    await closeSheet(tester);
  });

  testWidgets('切类型＝字段组与时段整套换（题注跟着换）', (tester) async {
    await pumpHost(tester);
    await tester.tap(find.byKey(const ValueKey('hv-type-temp')));
    await settle5(tester);
    expect(find.byType(CupertinoPicker), findsNWidgets(3), reason: '体温只有单值：时·分·体温三根柱');
    expect(find.byKey(const ValueKey('hv-slot-复测')), findsOneWidget);
    expect(find.byKey(const ValueKey('hv-slot-晨起空腹')), findsNothing);
    expect(find.text('测量时段'), findsOneWidget);
    expect(preview(tester), contains('体温 38.5 ℃'));

    await tester.tap(find.byKey(const ValueKey('hv-type-glu')));
    await settle5(tester);
    expect(find.text('血糖时段 · 饮食情况见备注'), findsOneWidget, reason: '原型按类型换题注');
    expect(find.byKey(const ValueKey('hv-slot-餐后2h')), findsOneWidget);
    // 小数位由步长决定（0.1 步长＝一位小数），别按指标名硬编码
    expect(preview(tester), contains('血糖 12.4 mmol/L'));
    await closeSheet(tester);
  });

  testWidgets('滚轮改收缩压→预览与判级同帧随动', (tester) async {
    await pumpHost(tester);
    // 第 2 根＝收缩压柱（时·分之后）；默认 135 在 index 65，往后 10 档＝145。
    await spin(tester, 2, 10);
    expect(preview(tester), contains('血压 145/85 mmHg'));
    expect(preview(tester), contains('高于参考值'));
    await spin(tester, 2, -20); // 145 → 125
    expect(preview(tester), contains('血压 125/85 mmHg'));
    expect(preview(tester), contains('落在参考范围'));
    await closeSheet(tester);
  });

  testWidgets('分钟＝5 分钟一档，时柱一动就地出读数（禁两段式）', (tester) async {
    await pumpHost(tester);
    expect(timeRead(tester), '07:30');
    // 第一下拖动就必须生效：LHWheel 过去把「首次回调」无条件当首帧噪音吞掉，
    // 而 CupertinoPicker 在时柱这类档上不保证首帧真的回调过——结果用户第一下改动被吞（读数不动）。
    await spin(tester, 0, 1); // 时柱 +1
    expect(timeRead(tester), '08:30');
    await spin(tester, 1, 2); // 分柱往后 2 档＝40 分
    expect(timeRead(tester), '08:40');
    await closeSheet(tester);
  });

  testWidgets('血氧：上限是「无上限」哨兵，预览只印「参考 ≥95 %」', (tester) async {
    await pumpHost(tester, kind: 'spo2');
    expect(preview(tester), contains('参考 ≥95 %'));
    expect(find.textContaining('999'), findsNothing);
    await closeSheet(tester);
  });

  testWidgets('保存＝落库两值＋所选日期，弹层关掉后统计口径立刻可读', (tester) async {
    await pumpHost(tester);
    await spin(tester, 2, 10); // 收缩压 145
    final twoDaysAgo = dayKey(now.subtract(const Duration(days: 2)));
    await tester.tap(find.byKey(ValueKey('hv-date-$twoDaysAgo')));
    await settle5(tester);

    await tester.tap(find.byKey(const ValueKey('hv-save')));
    expect(await pollText(tester, '已记录 血压 145/85 mmHg · 超出参考范围'), isTrue,
        reason: '跨弹层写库不能带发起页的 ref；toast 挂在关闭后的原页面 context 上');
    final rows = await repo.vitals(1, '2026-09-01', '2026-09-30');
    expect(rows.single.sys, 145);
    expect(rows.single.dia, 85, reason: '血压两值都要落库，只存收缩压就没法显示 145/85');
    expect(rows.single.date, twoDaysAgo);
    expect(rows.single.time, '07:30');
    expect(rows.single.slot, '晨起空腹');
    expect(container.read(healthTickProvider), 1, reason: '写库靠 tick 触发全模块重取');
    await clearToasts(tester);
  });

  testWidgets('改这一条＝就地覆盖同一行（回填时段与备注，不插第二行）', (tester) async {
    final id = await repo.saveVital(const HealthVital(
        profileId: 1, date: '2026-09-18', time: '21:05', kind: 'bp', sys: 118, dia: 76,
        slot: '晚间', note: '服药后两小时'));
    await pumpHost(tester, editing: (await repo.vitals(1, '2026-09-01', '2026-09-30')).single);

    expect(find.text('修改 09-18 的血压'), findsOneWidget);
    expect(find.text('21:05'), findsOneWidget, reason: '时·分滚轮回填到原时刻（分钟归到 5 分档）');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('hv-note'))).controller!.text,
        '服药后两小时');
    expect(preview(tester), contains('血压 118/76 mmHg'));

    await spin(tester, 2, 2); // 118 → 120
    await tester.tap(find.byKey(const ValueKey('hv-save')));
    expect(await pollText(tester, '已记录 血压 120/76 mmHg'), isTrue);
    final rows = await repo.vitals(1, '2026-09-01', '2026-09-30');
    expect(rows.length, 1, reason: '点行就地改：不许变成第二条');
    expect(rows.single.id, id);
    expect(rows.single.sys, 120);
    expect(rows.single.dia, 76, reason: '没动的舒张压保持原值');
    expect(rows.single.slot, '晚间', reason: '改数值不该把时段重置回第一档');
    expect(container.read(healthTickProvider), 1);
    await clearToasts(tester);
  });

  testWidgets('取消＝一行都不落', (tester) async {
    await pumpHost(tester, kind: 'hr');
    await spin(tester, 2, 5);
    await closeSheet(tester);
    expect(find.byKey(const ValueKey('hv-save')), findsNothing);
    expect(await repo.vitals(1, '2026-09-01', '2026-09-30'), isEmpty);
    expect(container.read(healthTickProvider), 0);
  });
}
