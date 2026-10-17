import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/health/data/health_repository.dart';
import 'package:lifeharness/features/health/data/health_settings.dart';
import 'package:lifeharness/features/health/domain/health_calc.dart';
import 'package:lifeharness/features/health/domain/health_models.dart';
import 'package:lifeharness/features/health/domain/health_symptom.dart';
import 'package:lifeharness/features/health/presentation/health_providers.dart';
import 'package:lifeharness/features/health/presentation/health_sheets.dart';
import 'package:lifeharness/shared/widgets/image_attach.dart';
import 'package:lifeharness/shared/widgets/lh_wheel.dart';
import 'package:lifeharness/shared/widgets/ui_kit.dart';

import 'helpers.dart';

/// 健康批3.5a · 症状录入弹层（原型 `v2_sheets.html#sheetHSymptom` + `v2_js.js` 的
/// `syOpen`/`syNames`/`syPainRow`/`syPartPick`/`sySave`）。
///
/// 六条判定（工单执行面板第 3、5 项）：
/// · 新增的**可见默认档**整套钉住：症状名＝种子第一枚、疼痛 0、部位空、时刻 20:00、
///   **持续 10 分钟**（原型 `hWheel('syDur',…,1)`）——需求外的「猜 30」在这里会当场红；
/// · 疼痛条点一下即选（就地 11 段，禁两段式），读数同时改两套口径：色档六档 + 文案三档
///   （6 分＝中度、8 分＝重度、3 分＝轻度）；
/// · 部位**多选全量存**（原型只取第一枚，本实现不丢其余），再点一次取消；
/// · 自定义症状名写 prefs 后**同一张弹层里当场多一枚并选中**（设置当场生效，不「下次进屏才有」），
///   空输入＝只出提示条不占位；
/// · 改档＝带原读数回来（标题/选中态/开关/滚轮档/`created_at`），保存走 UPDATE 不多出一行；
///   存量分钟不在 5 分钟档上时**就近归档**（47→45），不假装滚轮能选中间值；
/// · 提示条原话吃域层 `symSavedTx`（`已记录 头痛 6 分 · 已标为用药相关`），文案不在弹层里各写一遍。
///
/// 照片链路只断「＋格在／上限守卫」（`symCanAddPhoto` 已由 spec 钉死）：
/// `ImageSquareCard` 会建真文件解码器，FakeAsync 下不返回（既定坑），故改档用例一律不带 photos。
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

  String dk(Duration ago) => dayKey(now.subtract(ago));

  /// 宿主只给一枚开弹层的按钮：建档与失效走真实仓储（内存库），弹层吃模块 providers。
  Future<void> pumpHost(WidgetTester tester,
      {SymptomRecord? editing, Map<String, Object> seedPrefs = const {}}) async {
    await useSurface(tester, const Size(420, 1900));
    SharedPreferences.setMockInitialValues(seedPrefs);
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
                  onPressed: () => showHealthSymptomSheet(ctx, editing: editing),
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

  /// 表体比外壳的 640 上限高：底部那几块（照片/开关/按钮）落在滚动视口外，
  /// 坐标会算到屏幕下方，必须先滚进视口再点/再输入，否则 tap 与 enterText 打空。
  Future<void> reveal(WidgetTester t, Key key) => t.ensureVisible(find.byKey(key));

  Future<void> tapKey(WidgetTester t, String key) async {
    final f = find.byKey(ValueKey(key));
    await reveal(t, ValueKey(key));
    await settle5(t);
    await t.tap(f);
    // tap 只派发指针事件，不推那一帧：不补 pump 就会读到 setState 之前的旧树（疼痛条/部位 chips 当场踩到）。
    await settle5(t);
  }

  Future<void> typeKey(WidgetTester t, String key, String text) async {
    final f = find.byKey(ValueKey(key));
    await reveal(t, ValueKey(key));
    await settle5(t);
    await t.enterText(f, text);
    await settle5(t);
  }

  String keyText(WidgetTester t, String key) =>
      (t.widget<Text>(find.byKey(ValueKey(key)))).data ?? '';

  /// `_chip` 没有布尔字段可读，选中态就写在自己的底色上（未选＝onSurface 6% 的灰）。
  bool chipOn(WidgetTester t, String key) {
    final box = t.widget<Container>(
        find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Container)).first);
    final d = box.decoration;
    return d is BoxDecoration &&
        d.color == Theme.of(t.element(find.byKey(ValueKey(key)))).colorScheme.primary;
  }

  /// 疼痛段是 `AnimatedContainer`（不是 `_chip` 那层 Container），选中段吃域层的六档原色。
  bool painOn(WidgetTester t, int i) {
    final w = t.widget<AnimatedContainer>(find.descendant(
        of: find.byKey(ValueKey('hsy-pain-$i')), matching: find.byType(AnimatedContainer)));
    final d = w.decoration;
    return d is BoxDecoration && d.color == Color(symColorHex(i));
  }

  int chipCount(WidgetTester t, String rowKey) => find
      .descendant(of: find.byKey(ValueKey(rowKey)), matching: find.byType(InkWell))
      .evaluate()
      .length;

  /// 三柱并排＝时(0)·分(1)·持续(2)；往上拖 n 格＝档位 +n（itemExtent 28）。
  Future<void> roll(WidgetTester t, int pickerIndex, int steps) async {
    final f = find.byType(CupertinoPicker).at(pickerIndex);
    await t.ensureVisible(f);
    await settle5(t);
    await t.drag(f, Offset(0, -28.0 * steps));
    await settle5(t);
  }

  Future<List<SymptomRecord>> saved({int pid = 1}) => repo.symptoms(pid);

  testWidgets('新增默认档整套＝原型可见态：种子首枚选中、疼痛 0、部位空、20:00 · 持续 10 分钟',
      (tester) async {
    await pumpHost(tester);
    expect(find.text('记录症状'), findsOneWidget);
    expect(chipOn(tester, 'hsy-name-头痛'), isTrue, reason: '原型 `_sySel.name = HP.syNames[0]`');
    expect(chipOn(tester, 'hsy-name-头晕'), isFalse);
    expect(keyText(tester, 'hsy-pain-tx'), '0 分 · 轻度');
    for (final x in symParts) {
      expect(chipOn(tester, 'hsy-part-$x'), isFalse, reason: '新增不预选部位，用户自己点');
    }
    // 刀口：把 _newDurIdx 改成 5（＝30 分钟）这行立刻红——需求没写过 30，原型写的是 index 1。
    expect(keyText(tester, 'hsy-when'), '开始 ${dayKey(now)} 20:00 · 持续 10 分钟');
    expect(tester.widget<LHWheel>(find.byKey(ValueKey('hsyDur-$symDurCount-1'))).initialIndex, 1);
    expect(find.byType(CupertinoPicker), findsNWidgets(3), reason: '时·分·持续三柱就地内嵌');
    final switches = tester.widgetList<Switch>(find.byType(Switch)).map((s) => s.value).toList();
    expect(switches, [false, false]);
    expect(find.byKey(const ValueKey('hsy-pic-add')), findsOneWidget);
    expect(find.byType(ImageSquareCard), findsNothing);
  });

  testWidgets('疼痛条点一下即选：色档六档与文案三档同时改口，再点别的档跟着换', (tester) async {
    await pumpHost(tester);
    await tapKey(tester, 'hsy-pain-6');
    expect(keyText(tester, 'hsy-pain-tx'), '6 分 · 中度');
    expect(chipOn(tester, 'hsy-name-头痛'), isTrue, reason: '点疼痛条不该顺手改症状名选中态');

    await tapKey(tester, 'hsy-pain-8');
    expect(keyText(tester, 'hsy-pain-tx'), '8 分 · 重度');
    await tapKey(tester, 'hsy-pain-3');
    expect(keyText(tester, 'hsy-pain-tx'), '3 分 · 轻度');
    // 段与段之间互斥：只有 3 这一段上色。
    expect(painOn(tester, 3), isTrue);
    expect(painOn(tester, 6), isFalse);
  });

  testWidgets('部位多选全量存、再点取消；保存落到流水就是两枚一起显示', (tester) async {
    await pumpHost(tester);
    await tapKey(tester, 'hsy-part-头部');
    await tapKey(tester, 'hsy-part-胸腹');
    expect(chipOn(tester, 'hsy-part-头部'), isTrue);
    expect(chipOn(tester, 'hsy-part-胸腹'), isTrue);

    await tapKey(tester, 'hsy-part-头部'); // 再点＝取消
    expect(chipOn(tester, 'hsy-part-头部'), isFalse);

    await tapKey(tester, 'hsy-save');
    await settle5(tester);
    final r = (await saved()).single;
    expect(r.parts, ['胸腹'], reason: '取消掉的那枚不残留（不是 append-only）');
    expect(r.name, '头痛');
    expect(r.date, dayKey(now));
  });

  testWidgets('自定义症状名：空输入只出提示不占位；写入后同一张弹层当场多一枚并选中',
      (tester) async {
    await pumpHost(tester);
    expect(chipCount(tester, 'hsy-names'), symSeedNames.length);

    await tapKey(tester, 'hsy-name-add');
    await settle5(tester);
    expect(find.text('请先填写症状名'), findsOneWidget);
    expect(chipCount(tester, 'hsy-names'), symSeedNames.length, reason: '空名不占位');

    await typeKey(tester, 'hsy-name-in', '牙痛');
    await tapKey(tester, 'hsy-name-add');
    await settle5(tester);
    expect(find.text('已加入常用症状'), findsOneWidget);
    expect(chipCount(tester, 'hsy-names'), symSeedNames.length + 1);
    expect(chipOn(tester, 'hsy-name-牙痛'), isTrue, reason: '加完就用：当场选中，不让用户再点一次');
    expect(prefs.getStringList(HealthSettings.kSymNames), ['牙痛'], reason: ' prefs 落库，重开弹层还在');
    await clearToasts(tester);

    // 同名重复加＝不长出第二枚（种子名同理），列表仍是 11 枚。
    await typeKey(tester, 'hsy-name-in', '牙痛');
    await tapKey(tester, 'hsy-name-add');
    await settle5(tester);
    expect(chipCount(tester, 'hsy-names'), symSeedNames.length + 1);
  });

  testWidgets('时刻与日期就地滚：滚三柱、点昨天，读数与落库同源', (tester) async {
    await pumpHost(tester);
    // 时柱 20→22（+2 档）、分柱 00→30（+6 档）、持续 10→30（+4 档）。
    await roll(tester, 0, 2);
    await roll(tester, 1, 6);
    await roll(tester, 2, 4);
    expect(keyText(tester, 'hsy-when'), '开始 ${dayKey(now)} 22:30 · 持续 30 分钟');

    final y = dk(const Duration(days: 1));
    expect(tester.widget<PillChip>(find.byKey(ValueKey('hsy-date-${dayKey(now)}'))).selected, isTrue,
        reason: '默认今天');
    await tapKey(tester, 'hsy-date-$y');
    await settle5(tester);
    expect(keyText(tester, 'hsy-when'), '开始 $y 22:30 · 持续 30 分钟');

    await tapKey(tester, 'hsy-save');
    await settle5(tester);
    final r = (await saved()).single;
    expect(r.date, y);
    expect(r.time, '22:30');
    expect(r.durationMin, 30);
  });

  testWidgets('保存新增：两开关与三个文本一起落库，提示条原话后弹层收起', (tester) async {
    await pumpHost(tester);
    await tapKey(tester, 'hsy-pain-6');
    await typeKey(tester, 'hsy-desc', '右侧太阳穴跳痛');
    await typeKey(tester, 'hsy-trig', '熬夜后');
    await typeKey(tester, 'hsy-relief', '休息后好转');
    await tapKey(tester, 'hsy-on');
    await tapKey(tester, 'hsy-drug');
    await settle5(tester);

    await tapKey(tester, 'hsy-save');
    await settle5(tester);
    expect(find.text('已记录 头痛 6 分 · 已标为用药相关'), findsOneWidget,
        reason: '原型 `sySave` 原话，用药相关时才追加这一句');
    expect(find.byKey(const ValueKey('hsy-save')), findsNothing, reason: '保存即收，不留半张表');

    final r = (await saved()).single;
    expect(r.name, '头痛');
    expect(r.level, 6);
    expect(r.desc, '右侧太阳穴跳痛');
    expect(r.trig, '熬夜后');
    expect(r.relief, '休息后好转');
    expect(r.ongoing, isTrue);
    expect(r.drugRelated, isTrue);
    expect(r.photos, isEmpty);
    expect(r.createdAt, greaterThan(0), reason: '新增行由 toRow 补建档时间');
  });

  testWidgets('改档＝带原读数回来，保存走 UPDATE 不多一行、不冲建档时间', (tester) async {
    final id = await repo.addSymptom(SymptomRecord(
        profileId: 1,
        date: dayKey(now),
        time: '08:00',
        name: '头痛',
        level: 6,
        parts: ['头部', '四肢'],
        durationMin: 47, // 不在 5 分钟档上：滚轮就近归到 45
        desc: '右侧太阳穴跳痛',
        ongoing: true));
    final loaded = (await saved()).firstWhere((s) => s.id == id);
    await pumpHost(tester, editing: loaded);

    expect(find.text('修改 ${dayKey(now)} 的症状'), findsOneWidget);
    expect(chipOn(tester, 'hsy-name-头痛'), isTrue);
    expect(keyText(tester, 'hsy-pain-tx'), '6 分 · 中度');
    expect(chipOn(tester, 'hsy-part-头部'), isTrue);
    expect(chipOn(tester, 'hsy-part-四肢'), isTrue);
    expect(chipOn(tester, 'hsy-part-胸腹'), isFalse);
    expect(keyText(tester, 'hsy-when'), '开始 ${dayKey(now)} 08:00 · 持续 45 分钟',
        reason: '47 分归档到 45＝滚轮的档位集合就是可选集合，不假装能选中间值');
    final switches = tester.widgetList<Switch>(find.byType(Switch)).map((s) => s.value).toList();
    expect(switches, [true, false], reason: '发作中回显、用药相关没开');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('hsy-desc'))).controller!.text,
        '右侧太阳穴跳痛');

    await tapKey(tester, 'hsy-pain-2');
    await tapKey(tester, 'hsy-drug');
    await tapKey(tester, 'hsy-save');
    await settle5(tester);

    final after = await saved();
    expect(after.length, 1, reason: '同日多条是靠 INSERT，改档这一路必须走 UPDATE');
    expect(after.single.id, id);
    expect(after.single.level, 2);
    expect(after.single.drugRelated, isTrue);
    expect(after.single.ongoing, isTrue, reason: '没碰那个开关就保持原样');
    expect(after.single.createdAt, loaded.createdAt, reason: '编辑不该把建档时间冲成现在');
  });

  testWidgets('取消＝整张表作废：不落库也不改存量行', (tester) async {
    await repo.addSymptom(SymptomRecord(
        profileId: 1, date: dayKey(now), name: '头痛', level: 6, durationMin: 30));
    await pumpHost(tester);
    await tapKey(tester, 'hsy-pain-10');
    await typeKey(tester, 'hsy-desc', '别写进库');
    await tapKey(tester, 'hsy-cancel');
    await settle5(tester);
    expect(find.byKey(const ValueKey('hsy-save')), findsNothing);
    final r = (await saved()).single;
    expect(r.level, 6, reason: '点了 10 但没保存，存量还是 6');
    expect(r.desc, isNull);
  });
}
