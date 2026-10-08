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
import 'package:lifeharness/features/health/domain/health_report.dart';
import 'package:lifeharness/features/health/presentation/health_providers.dart';
import 'package:lifeharness/features/health/presentation/health_report_page.dart';
import 'package:lifeharness/features/health/presentation/health_routes.dart';
import 'package:lifeharness/shared/widgets/ui_kit.dart';

import 'helpers.dart';

/// 健康批3.5b · 检查报告屏（原型 `tools/health/v2_pages.html#p-report` ＋ `v2_js.js` 的
/// `rpRender`/`rpYear`/`rpToggle`/`rpDel`）。
///
/// 六条判定（工单执行面板第 4、6 项）：
/// · **统计三位吃全量**：点月份 chips 只筛下面的卡，「报告 3 份」跟着少一张就是两处各取各的数；
/// · 卡片**默认折叠**（原型 `rpBody` 起手带 `hidden`）——明细里的附件、检验项、按钮在未展开时不该在树里；
/// · 展开后检验项的偏高/偏低旗**按行内参考范围实时算**（表里没有状态列），边界值算正常；
/// · 流水序＝最新在上（偏离原型插入序，登记工单 §3）；同日按 id 倒排；
/// · 档案 chips 切换＝跨档案不聚合（§11.1），别人档案的一份都不出；
/// · 删除走二次确认，确认后父行与它的检验项一起清（不留孤儿行），附件文件不碰（归清理服务）。
///
/// 附件缩略只种 `.pdf` 路径：`Image.file` 会建真文件解码器，FakeAsync 下不返回（既定坑，
/// 同批3.5a 症状照片链路的做法）；图片链路由弹层用例与 R5b 既有服务覆盖。
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

  /// 报告屏 pump：建库＋固定钟＋模块真实路由（栈页一律 push）。
  Future<(ProviderContainer, GoRouter)> pumpRp(WidgetTester tester) async {
    await useSurface(tester, const Size(420, 2400));
    SharedPreferences.setMockInitialValues({});
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
    router.push('/health/report');
    await settle5(tester);
    return (container, router);
  }

  String keyText(WidgetTester t, String key) =>
      (t.widget<Text>(find.byKey(ValueKey(key)))).data ?? '';

  /// 统计格里 label 与 value 是两枚 Text，取值那枚（上面一行）才是读数。
  String statTx(WidgetTester t, String label) => (t.widgetList<Text>(
          find.descendant(
              of: find.byKey(ValueKey('hrpt-stat-$label')), matching: find.byType(Text)))
      .first
      .data ?? '');

  /// 徽标 key 挂在外壳 Container 上，读数要往里面取那枚 Text。
  String badgeTx(WidgetTester t, String key) => (t.widget<Text>(
          find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text))))
      .data ?? '';

  List<String> cardKeys(WidgetTester t) => t
      .widgetList<Container>(find.byType(Container))
      .map((c) => c.key)
      .whereType<ValueKey<String>>()
      .map((k) => k.value)
      .where((v) => v.startsWith('hrpt-card-'))
      .toList();

  List<String> monthLabels(WidgetTester t) => t
      .widgetList<PillChip>(find.descendant(
          of: find.byKey(HealthReportPage.kMonths), matching: find.byType(PillChip)))
      .map((c) => c.label)
      .toList();

  /// 三份在本档案（9 月两份·8 月一份），一份在别人档案。
  /// 返回值：血常规（1 项偏低 1 项正常·1 张 PDF）／血脂（1 项偏高·无附件）／尿常规（0 项·2 张 PDF）／别人档案。
  Future<(int, int, int, int)> seedFour() async {
    final r1 = await repo.addReport(const HealthReport(
        profileId: 1,
        date: '2026-09-19',
        name: '血常规',
        hospital: '市一院',
        doctorAdvice: '一周后复查',
        files: ['a.pdf'],
        kind: 'pdf'));
    await repo.addMetric(ReportMetric(
        reportId: r1, name: '血红蛋白', value: 100, unit: 'g/L', refLo: 115, refHi: 150));
    await repo.addMetric(ReportMetric(
        reportId: r1, name: '白细胞', value: 6.5, unit: '×10⁹/L', refLo: 3.5, refHi: 9.5));
    final r2 = await repo.addReport(const HealthReport(
        profileId: 1,
        date: '2026-09-05',
        name: '血脂四项',
        doctorAdvice: '',
        files: []));
    await repo.addMetric(ReportMetric(
        reportId: r2, name: '低密度脂蛋白', value: 4.1, unit: 'mmol/L', refLo: 0, refHi: 3.4));
    final r3 = await repo.addReport(const HealthReport(
        profileId: 1,
        date: '2026-08-02',
        name: '尿常规',
        files: ['b.pdf', 'c.pdf'],
        kind: 'pdf'));
    final r4 = await repo.addReport(const HealthReport(
        profileId: 2, date: '2026-09-20', name: '别人的报告', files: ['d.pdf'], kind: 'pdf'));
    return (r1, r2, r3, r4);
  }

  testWidgets('空白档案：空态原话、三读数归零、只有「全部」一枚 chips、底栏上传条在', (tester) async {
    await pumpRp(tester);
    expect(find.text('检查报告'), findsOneWidget);
    expect([statTx(tester, '报告'), statTx(tester, '异常项'), statTx(tester, '图片/PDF')],
        ['0 份', '0 条', '0 个']);
    expect(monthLabels(tester), ['全部']);
    expect(find.text(rpEmptyTx), findsOneWidget);
    expect(find.byKey(const ValueKey('hrpt-add')), findsOneWidget,
        reason: '操作条挂 bottomNavigationBar，FAB 会压住末行卡片按钮（真机踩过同形）');
    expect(find.text('报告图片与 PDF 仅存本机 · 随本地备份导出'), findsOneWidget);
  });

  testWidgets('四份种子：三读数吃全量、倒序成卡、默认全折叠、别人档案一枚不出', (tester) async {
    final (r1, r2, r3, _) = await seedFour();
    await pumpRp(tester);

    expect([statTx(tester, '报告'), statTx(tester, '异常项'), statTx(tester, '图片/PDF')],
        ['3 份', '2 条', '3 个']);
    expect(monthLabels(tester), ['全部', '8 月', '9 月'],
        reason: 'chips 序＝取数序（date ASC），不是卡片序');
    expect(cardKeys(tester), ['hrpt-card-$r1', 'hrpt-card-$r2', 'hrpt-card-$r3'],
        reason: '卡片倒序＝最新在上；第 4 份属别人档案');

    // 副注四段：日期 · 医院 · 附件读数 · 项数（医院缺失的那份落「—」）。
    expect(find.text('2026-09-19 · 市一院 · PDF · 2 项'), findsOneWidget);
    expect(find.text('2026-09-05 · — · 未附 · 1 项'), findsOneWidget);
    expect(find.text('2026-08-02 · — · PDF ×2 · 0 项'), findsOneWidget);
    // 角标两态。
    expect(badgeTx(tester, 'hrpt-badge-$r1'), '1 项异常');
    expect(badgeTx(tester, 'hrpt-badge-$r3'), '全部正常');

    // 折叠态：明细三块（附件／检验项／两个按钮）都不该在树里。
    expect(find.byKey(ValueKey('hrpt-metrics-$r1')), findsNothing);
    expect(find.byKey(ValueKey('hrpt-metric-add-$r1')), findsNothing);
    expect(find.byKey(ValueKey('hrpt-del-$r1')), findsNothing);
    expect(find.text('医生建议：一周后复查'), findsNothing);
    expect(find.text(rpArrow(false)), findsNWidgets(3));
  });

  testWidgets('点行头展开：附件格、检验项行与实时判档旗、建议行、两枚按钮同场', (tester) async {
    final (r1, r2, _, _) = await seedFour();
    await pumpRp(tester);

    await tester.tap(find.byKey(ValueKey('hrpt-toggle-$r1')));
    await settle5(tester);
    expect(keyText(tester, 'hrpt-arrow-$r1'), '⌄', reason: '箭头改口');
    expect(find.byKey(ValueKey('hrpt-files-$r1')), findsOneWidget);
    expect(find.byKey(const ValueKey('hrpt-file-0')), findsOneWidget);
    expect(find.text('PDF'), findsWidgets, reason: 'PDF 缩略位只作留档标记，点了不给假预览');

    final ms = await repo.metrics(r1);
    expect(ms.map((e) => e.name).toList(), ['血红蛋白', '白细胞'], reason: '回读按录入序');
    expect(find.byKey(ValueKey('hrpt-metric-${ms[0].id}')), findsOneWidget);
    expect(find.text('100 g/L'), findsOneWidget);
    expect(find.text('115 ~ 150'), findsOneWidget);
    expect(badgeTx(tester, 'hrpt-flag-${ms[0].id}'), '偏低');
    expect(badgeTx(tester, 'hrpt-flag-${ms[1].id}'), '正常');
    expect(find.text('医生建议：一周后复查'), findsOneWidget);
    expect(find.byKey(ValueKey('hrpt-metric-add-$r1')), findsOneWidget);
    expect(find.byKey(ValueKey('hrpt-del-$r1')), findsOneWidget);

    // 展开第二份：两份明细同场，第一份不动（折叠是个别状态，不是手风琴）。
    await tester.tap(find.byKey(ValueKey('hrpt-toggle-$r2')));
    await settle5(tester);
    expect(find.byKey(ValueKey('hrpt-metrics-$r1')), findsOneWidget);
    expect(find.byKey(ValueKey('hrpt-metric-empty-$r2')), findsNothing,
        reason: '血脂那份有 1 项，不该出「尚未录入检验项」');
    expect(find.text('医生建议：—'), findsOneWidget, reason: '空建议走「—」而不是空白行');

    await tester.tap(find.byKey(ValueKey('hrpt-toggle-$r2')));
    await settle5(tester);
    expect(find.byKey(ValueKey('hrpt-metrics-$r2')), findsNothing);
  });

  testWidgets('无检验项的卡展开后出「尚未录入检验项」而不是空块', (tester) async {
    final (_, _, r3, _) = await seedFour();
    await pumpRp(tester);
    await tester.tap(find.byKey(ValueKey('hrpt-toggle-$r3')));
    await settle5(tester);
    expect(find.text(rpNoMetricTx), findsOneWidget);
    expect(find.byKey(ValueKey('hrpt-metrics-$r3')), findsNothing);
    expect(find.byKey(ValueKey('hrpt-files-$r3')), findsOneWidget);
  });

  testWidgets('月份 chips 只筛卡不筛统计；删到该月没货就回落「全部」', (tester) async {
    final (r1, r2, r3, _) = await seedFour();
    await pumpRp(tester);

    await tester.tap(find.byKey(const ValueKey('hrpt-month-08')));
    await settle5(tester);
    expect(cardKeys(tester), ['hrpt-card-$r3'], reason: '8 月只剩尿常规一张');
    expect([statTx(tester, '报告'), statTx(tester, '异常项'), statTx(tester, '图片/PDF')],
        ['3 份', '2 条', '3 个'], reason: '原型 rpRender 先算 stat 再 filter，读数跟着筛就错了');

    await tester.tap(find.byKey(const ValueKey('hrpt-month-09')));
    await settle5(tester);
    expect(cardKeys(tester), ['hrpt-card-$r1', 'hrpt-card-$r2']);
    expect(find.text('2026-08-02 · — · PDF ×2 · 0 项'), findsNothing);

    // 把 9 月这两张删掉（删除钮在展开的明细里）→ 月份 chip 本身消失、选择回落「全部」，
    // 不然屏上是一片空白加一枚点不掉的 chips。
    for (final id in [r1, r2]) {
      await tester.tap(find.byKey(ValueKey('hrpt-toggle-$id')));
      await settle5(tester);
      await tester.tap(find.byKey(ValueKey('hrpt-del-$id')));
      await settle5(tester);
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('删除')));
      await settle5(tester);
      await clearToasts(tester);
    }
    expect(find.byKey(const ValueKey('hrpt-month-09')), findsNothing);
    expect(monthLabels(tester), ['全部', '8 月']);
    expect([statTx(tester, '报告'), statTx(tester, '异常项'), statTx(tester, '图片/PDF')],
        ['1 份', '0 条', '2 个']);
    expect(cardKeys(tester), ['hrpt-card-$r3']);
  });

  testWidgets('档案 chips 切换＝整屏重取，跨档案不聚合（§11.1）', (tester) async {
    await repo.saveProfile(const HealthProfile(id: 0, name: '小明', rel: '子'));
    await seedFour();
    final (_, _) = await pumpRp(tester);
    final fam = (await repo.profiles()).firstWhere((p) => p.rel == '子');

    await tester.tap(find.byKey(ValueKey('hrpt-profile-${fam.id}')));
    await settle5(tester);
    expect(find.text('2026-09-19 · 市一院 · PDF · 2 项'), findsNothing);
    expect(find.text('别人的报告'), findsOneWidget);
    expect([statTx(tester, '报告'), statTx(tester, '异常项'), statTx(tester, '图片/PDF')],
        ['1 份', '0 条', '1 个'], reason: '切档案后三读数按新档案重算，不能还是 3 份');
  });

  testWidgets('删除＝先确认；确认后父行与检验项一起清、附件不碰、提示条原话', (tester) async {
    final (r1, _, _, _) = await seedFour();
    await pumpRp(tester);
    // 删除钮在展开的明细里：先点开这张卡。
    await tester.tap(find.byKey(ValueKey('hrpt-toggle-$r1')));
    await settle5(tester);

    await tester.tap(find.byKey(ValueKey('hrpt-del-$r1')));
    await settle5(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(rpDelTx('血常规')), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('取消')));
    await settle5(tester);
    expect(cardKeys(tester), hasLength(3), reason: '取消不该动数据');

    await tester.tap(find.byKey(ValueKey('hrpt-del-$r1')));
    await settle5(tester);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('删除')));
    await settle5(tester);

    expect(find.byKey(ValueKey('hrpt-card-$r1')), findsNothing);
    expect(cardKeys(tester), hasLength(2));
    expect(find.text(rpDeletedTx), findsOneWidget);
    expect(await repo.reports(1), hasLength(2));
    expect(await repo.metrics(r1), isEmpty, reason: '不留「报告没了、检验项还在表里」的孤儿行');
    await clearToasts(tester);
  });

  testWidgets('底栏上传钮开弹层、取消关掉且不落库', (tester) async {
    await pumpRp(tester);
    await tester.tap(find.byKey(const ValueKey('hrpt-add')));
    await settle5(tester);
    // 底栏按钮与弹层标题同名（原型就是这句）：两处都在才说明窗真开了。
    expect(find.text('上传检查报告'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('hra-save')), findsOneWidget);

    final f = find.byKey(const ValueKey('hra-cancel'));
    await tester.ensureVisible(f);
    await settle5(tester);
    await tester.tap(f);
    await settle5(tester);
    expect(find.byKey(const ValueKey('hra-save')), findsNothing);
    expect(await repo.reports(1), isEmpty);
  });
}
