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
import 'package:lifeharness/features/health/domain/health_models.dart';
import 'package:lifeharness/features/health/domain/health_report.dart';
import 'package:lifeharness/features/health/presentation/health_providers.dart';
import 'package:lifeharness/features/health/presentation/health_sheets.dart';
import 'package:lifeharness/shared/widgets/lh_wheel.dart';
import 'package:lifeharness/shared/widgets/ui_kit.dart';

import 'helpers.dart';

/// 健康批3.5b · 检查报告两张弹层（原型 `v2_sheets.html#sheetHReportAdd`/`#sheetHMetric` ＋
/// `v2_js.js` 的 `rpa*`/`hmk*`）。
///
/// 七条判定（工单执行面板第 3、5 项）：
/// · 上传弹层起手是**空表**：三枚来源格、只有「＋」一格附件、日期默认今天、预览条说「附件 0 个」；
/// · 名称必填——缺名只出提示条、**不落库且弹层不关**（原型 `rpaSave` 同形），医院留空落 '—'；
/// · 附件 ≤6：第 7 次点来源只给「缩略位最多 6 格」，页面上「＋」也当场消失；
/// · `kind` 由附件内容派生（全 PDF 才记 pdf），保存后 0 检验项是设计而不是遗漏（预览条原话）；
/// · 检验项弹层**三柱就地内嵌**（禁两段式），点项目库芯片＝名字带入＋量程收窄＋默认档落参考中点，
///   判档预览当场改口（边界值算正常这条在域层）；
/// · 「加入本报告」后弹层不关（原型 `hmkAdd` 只刷新已录列表），位次按录入序追加，回读不插中间；
/// · 行末「删」＝按 id＋归属报告双闸，列表当场少一行。
///
/// PDF 走 `pickAndStorePdf` 注入缝（同 `BackupService.pickFilesImpl` 的做法）；
/// 拍照/相册会建真平台通道与文件解码器，**一律不点**（FakeAsync 不返回＝既定坑）。
///
/// 独立文件（全 app/大页 pump 拆文件口径）；日期一律相对固定钟 `now` 构造，禁写死今天。
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

  /// 宿主给两枚开弹层的按钮：建档与失效走真实仓储（内存库），弹层吃模块 providers。
  Future<void> pumpHost(WidgetTester tester,
      {bool metric = false, HealthReport? report, List<ReportMetric> metrics = const []}) async {
    await useSurface(tester, const Size(420, 1900));
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
                  onPressed: () => metric
                      ? showHealthMetricSheet(ctx, report: report!, metrics: metrics)
                      : showHealthReportSheet(ctx),
                  child: const Text('上传'),
                )),
          ),
        ),
      ),
    ));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('open-sheet')));
    await settle5(tester);
  }

  /// 表体比外壳的 640 上限高：底部那几块（预览条/按钮/已录列表）落在滚动视口外，
  /// 坐标会算到屏幕下方，必须先滚进视口再点/再输入，否则 tap 与 enterText 打空。
  Future<void> reveal(WidgetTester t, Key key) => t.ensureVisible(find.byKey(key));

  Future<void> tapKey(WidgetTester t, String key) async {
    final f = find.byKey(ValueKey(key));
    await reveal(t, ValueKey(key));
    await settle5(t);
    await t.tap(f);
    // tap 只派发指针事件，不推那一帧：不补 pump 就会读到 setState 之前的旧树。
    await settle5(t);
  }

  Future<void> typeKey(WidgetTester t, String key, String text) async {
    await reveal(t, ValueKey(key));
    await t.tap(find.byKey(ValueKey(key)));
    await settle5(t);
    await t.enterText(find.byKey(ValueKey(key)), text);
    await settle5(t);
  }

  String keyText(WidgetTester t, String key) =>
      (t.widget<Text>(find.byKey(ValueKey(key)))).data ?? '';

  /// key 挂在外层容器时取不到 Text：把带 key 子树里的所有 Text 拼起来读。
  String innerText(WidgetTester t, String key) => t
      .widgetList<Text>(find.descendant(
          of: find.byKey(ValueKey(key)), matching: find.byType(Text)))
      .map((x) => x.data ?? '')
      .join(' ');

  String inputText(WidgetTester t, String key) =>
      t.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

  int tiles(WidgetTester t, String prefix) => t
      .widgetList<GestureDetector>(find.byType(GestureDetector))
      .map((g) => g.key)
      .whereType<ValueKey<String>>()
      .map((k) => k.value)
      .where((v) => v.startsWith(prefix))
      .length;

  /// PDF 选择缝的替身：每次回一个递增路径，避开平台通道与真落盘。
  void stubPdf() {
    var calls = 0;
    final prev = pickAndStorePdf;
    pickAndStorePdf = (_) async => 'p${calls++}.pdf';
    addTearDown(() => pickAndStorePdf = prev);
  }

  Future<HealthReport> seededReport() async {
    await repo.addReport(const HealthReport(
        profileId: 1, date: '2026-09-19', name: '血常规', hospital: '市一院'));
    return (await repo.reports(1)).single;
  }

  // ==================== 上传检查报告 ====================

  testWidgets('起手空表：三枚来源格、只有「＋」一格附件、今天选中、预览条说附件 0 个', (tester) async {
    await pumpHost(tester);
    expect(find.text('上传检查报告'), findsOneWidget);
    for (final k in ['hra-src-cam', 'hra-src-img', 'hra-src-pdf']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget);
    }
    expect(tiles(tester, 'hra-file-'), 0);
    expect(find.byKey(const ValueKey('hra-pic-add')), findsOneWidget);
    expect(find.text('日期'), findsOneWidget);
    final chips = tester
        .widgetList<PillChip>(find.descendant(
            of: find.byKey(const ValueKey('hra-dates')), matching: find.byType(PillChip)))
        .toList();
    // 横向 ListView 是懒的：视口外那几枚根本没建，档数只能按 delegate 铺的 children 数。
    final dates = tester.widget<ListView>(find.descendant(
        of: find.byKey(const ValueKey('hra-dates')), matching: find.byType(ListView)));
    expect((dates.childrenDelegate as SliverChildListDelegate).children.length, 8,
        reason: '原型 rpaDates 铺 8 天');
    expect(chips.first.label, startsWith('今天'));
    expect(chips.first.selected, isTrue);
    expect(innerText(tester, 'hra-preview'), rpDraftTx(0));
    expect(inputText(tester, 'hra-name'), '');
    expect(find.byKey(const ValueKey('hra-save')), findsOneWidget);
  });

  testWidgets('缺名保存＝只出提示条、不落库、弹层不关（原型 rpaSave 同形）', (tester) async {
    await pumpHost(tester);
    await typeKey(tester, 'hra-hosp', '市一院');
    await tapKey(tester, 'hra-save');
    expect(find.text(rpNeedNameTx), findsOneWidget);
    expect(find.byKey(const ValueKey('hra-save')), findsOneWidget, reason: '不关窗，用户接着填');
    expect(await repo.reports(1), isEmpty);
    await clearToasts(tester);
  });

  testWidgets('填名保存：日期默认今天、医院留空落「—」、kind 按内容派生为 img', (tester) async {
    await pumpHost(tester);
    await typeKey(tester, 'hra-name', '血常规');
    await tapKey(tester, 'hra-save');
    await settle5(tester);

    final rows = await repo.reports(1);
    expect(rows, hasLength(1));
    final r = rows.single;
    expect([r.name, r.date, r.hospital, r.kind], ['血常规', dayKey(now), '—', 'img']);
    expect(r.files, isEmpty, reason: '没点来源格就是零附件建档（检验项要建档后逐条录，预览条原话）');
    expect(find.byKey(const ValueKey('hra-save')), findsNothing, reason: '保存成功就收窗');
    expect(find.text(rpSavedTx('血常规', 0)), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('PDF 注入缝：附件一格接一格、预览条跟着改口、全 PDF 才记 kind=pdf', (tester) async {
    stubPdf();
    await pumpHost(tester);
    await typeKey(tester, 'hra-name', '体检报告');

    await tapKey(tester, 'hra-src-pdf');
    expect(tiles(tester, 'hra-file-'), 1);
    expect(innerText(tester, 'hra-preview'), rpDraftTx(1));
    expect(find.text('已导入 PDF · 原文件仅存本机'), findsOneWidget);
    await clearToasts(tester);

    for (var i = 0; i < 5; i++) {
      await tapKey(tester, 'hra-src-pdf');
    }
    expect(tiles(tester, 'hra-file-'), 6, reason: 'rpAttachMax＝6');
    expect(find.byKey(const ValueKey('hra-pic-add')), findsNothing,
        reason: '第 7 格起不给「＋」（原型 rpaPics 的 <6 判据）');

    await tapKey(tester, 'hra-src-pdf');
    expect(tiles(tester, 'hra-file-'), 6, reason: '守卫在点格时就拦，不铺到第 7 格再报错');
    expect(find.text('缩略位最多 6 格'), findsOneWidget);
    await clearToasts(tester);

    await tapKey(tester, 'hra-save');
    final r = (await repo.reports(1)).single;
    expect(r.files, ['p0.pdf', 'p1.pdf', 'p2.pdf', 'p3.pdf', 'p4.pdf', 'p5.pdf']);
    expect(r.kind, 'pdf');
    expect(rpFmtTx(r), 'PDF ×6', reason: '附件读数由 files 内容派生，不另存一列');
  });

  testWidgets('点缩略格＝移除（原型 rpaRm），预览条当场少一个', (tester) async {
    stubPdf();
    await pumpHost(tester);
    await tapKey(tester, 'hra-src-pdf');
    await tapKey(tester, 'hra-src-pdf');
    expect(tiles(tester, 'hra-file-'), 2);

    await tapKey(tester, 'hra-file-0');
    expect(tiles(tester, 'hra-file-'), 1);
    expect(innerText(tester, 'hra-preview'), rpDraftTx(1));
    expect(inputText(tester, 'hra-name'), '', reason: '移除附件不该把名字也清了');
  });

  testWidgets('日期 chips 选 3 天前＝存进去的就是那天（相对固定钟构造）', (tester) async {
    await pumpHost(tester);
    final target = dk(const Duration(days: 3));
    await tapKey(tester, 'hra-date-$target');
    await typeKey(tester, 'hra-name', '复查');
    await tapKey(tester, 'hra-save');
    final r = (await repo.reports(1)).single;
    expect(r.date, target);
    expect(r.profileId, container.read(activeHealthProfileProvider),
        reason: '档案取当前活动档案，不写死 1');
  });

  // ==================== 录入检验项目 ====================

  testWidgets('起手：副注带项数、十枚项目库、三柱就地内嵌、tip 说「选项目」', (tester) async {
    final r = await seededReport();
    await pumpHost(tester, metric: true, report: r);

    expect(find.text('录入检验项目'), findsOneWidget);
    expect(keyText(tester, 'hmk-sub'), rpMetricSub(r, 0));
    for (final item in hkLib) {
      expect(find.byKey(ValueKey('hmk-lib-${item.name}')), findsOneWidget);
    }
    expect(find.text('常用项目库'), findsOneWidget);
    expect(keyText(tester, 'hmk-tip'), rpTipHintTx);
    expect(find.byType(CupertinoPicker), findsNWidgets(3), reason: '数值·下限·上限就地内嵌，禁两段式');
    expect(find.text(rpNoMetricTx), findsOneWidget);
    expect(find.byKey(const ValueKey('hmk-list')), findsNothing);
  });

  testWidgets('点「血红蛋白」＝名字带入＋量程收窄＋默认档落参考中点，tip 当场改口', (tester) async {
    final r = await seededReport();
    await pumpHost(tester, metric: true, report: r);

    await tapKey(tester, 'hmk-lib-血红蛋白');
    expect(inputText(tester, 'hmk-name'), '血红蛋白');
    final w = hkWheelsFor(refLo: 115, refHi: 150);
    expect(w.val.value, 132.5);
    expect(keyText(tester, 'hmk-tip'),
        '血红蛋白 132.5 g/L · 参考 115 ~ 150 正常',
        reason: '默认档是中点＝正常；边界算正常这条从域层来');
    expect(tester.widget<LHWheel>(find.byType(LHWheel).first).labels.length, w.val.count);
  });

  testWidgets('加入本报告：落库一行＋列表当场多一行＋弹层不关（原型 hmkAdd 只刷列表）', (tester) async {
    final r = await seededReport();
    await pumpHost(tester, metric: true, report: r);

    await tapKey(tester, 'hmk-lib-血红蛋白');
    await tapKey(tester, 'hmk-add');

    final ms = await repo.metrics(r.id!);
    expect(ms, hasLength(1));
    expect([ms.single.name, ms.single.value, ms.single.unit], ['血红蛋白', 132.5, 'g/L']);
    expect([ms.single.refLo, ms.single.refHi, ms.single.sort], [115.0, 150.0, 0]);
    expect(find.byKey(ValueKey('hmk-row-${ms.single.id}')), findsOneWidget);
    expect(find.text(rpNoMetricTx), findsNothing);
    expect(keyText(tester, 'hmk-sub'), rpMetricSub(r, 1));
    expect(find.byKey(const ValueKey('hmk-add')), findsOneWidget, reason: '录一项关一层＝把用户赶回卡片');
    expect(find.text(rpMetricAddedTx('血红蛋白')), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('连录两项按录入序追加，回读不插中间；空名点加入只出提示条', (tester) async {
    final r = await seededReport();
    await pumpHost(tester, metric: true, report: r);

    await tapKey(tester, 'hmk-add');
    expect(find.text(rpNeedMetricNameTx), findsOneWidget);
    expect(await repo.metrics(r.id!), isEmpty);
    await clearToasts(tester);

    await tapKey(tester, 'hmk-lib-血红蛋白');
    await tapKey(tester, 'hmk-add');
    await tapKey(tester, 'hmk-lib-白细胞');
    await tapKey(tester, 'hmk-add');

    final ms = await repo.metrics(r.id!);
    expect(ms.map((e) => e.name).toList(), ['血红蛋白', '白细胞']);
    expect(ms.map((e) => e.sort).toList(), [0, 1], reason: '原型 r.ms.push＝追加在尾');
    expect(ms[1].unit, '×10⁹/L');
    expect(ms[1].value, 6.5, reason: '白细胞中点 (3.5+9.5)/2＝6.5');
    expect(keyText(tester, 'hmk-sub'), rpMetricSub(r, 2));
    await clearToasts(tester);
  });

  testWidgets('行末「删」＝按 id＋归属报告双闸，列表当场少一行', (tester) async {
    final r = await seededReport();
    await pumpHost(tester, metric: true, report: r);
    await tapKey(tester, 'hmk-lib-血红蛋白');
    await tapKey(tester, 'hmk-add');
    final ms = await repo.metrics(r.id!);

    await tapKey(tester, 'hmk-del-${ms.single.id}');
    expect(find.byKey(ValueKey('hmk-row-${ms.single.id}')), findsNothing);
    expect(await repo.metrics(r.id!), isEmpty);
    expect(keyText(tester, 'hmk-sub'), rpMetricSub(r, 0));
    expect(find.text(rpNoMetricTx), findsOneWidget, reason: '删空了要回到「尚未录入检验项」而不是空白块');
  });

  testWidgets('自定义项目＝单位空、量程铺自适应全量程，滚一格读数当场改口（就地滚轮真在管）',
      (tester) async {
    final r = await seededReport();
    await pumpHost(tester, metric: true, report: r);

    await typeKey(tester, 'hmk-name', '甲胎蛋白');
    final w = hkWheelsFor();
    expect(keyText(tester, 'hmk-tip'), '甲胎蛋白 ${w.val.value.toInt()}  · 参考 0 ~ 400 正常',
        reason: '库外名没有单位（原型 `HK_LIB.find(...)?.[1] || \'\'`）');

    final f = find.byType(CupertinoPicker).first;
    await tester.ensureVisible(f);
    await settle5(tester);
    await tester.drag(f, const Offset(0, -28));
    await settle5(tester);
    expect(keyText(tester, 'hmk-tip'), '甲胎蛋白 ${w.val.value.toInt() + 1}  · 参考 0 ~ 400 正常',
        reason: '数值柱 1 一档（0..580 宽度 >80），滚一下 +1');

    await tapKey(tester, 'hmk-add');
    final ms = await repo.metrics(r.id!);
    expect([ms.single.name, ms.single.unit], ['甲胎蛋白', null]);
    expect([ms.single.value, ms.single.refLo, ms.single.refHi], [292.0, 0.0, 400.0]);
    await clearToasts(tester);
  });

  testWidgets('滚轮量程换了才换 State：点项目库把数值柱换成窄量程，key 随量程身份走',
      (tester) async {
    final r = await seededReport();
    await pumpHost(tester, metric: true, report: r);
    final before = tester.widget<LHWheel>(find.byType(LHWheel).first).labels;
    expect(before.length, hkValueRange(hkOpenLo, hkOpenHi).length);

    await tapKey(tester, 'hmk-lib-肌酐');
    final after = tester.widget<LHWheel>(find.byType(LHWheel).first).labels;
    expect(after.length, 421, reason: '40~82 每 0.1 一档（原型 hmkWheels 的窄段）');
    expect(after.first, '40');
    expect(after.last, '82');
    expect(keyText(tester, 'hmk-tip'), '肌酐 61 μmol/L · 参考 41 ~ 81 正常');
  });
}
