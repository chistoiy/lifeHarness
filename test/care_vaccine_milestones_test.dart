import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/care/data/care_repository.dart';
import 'package:lifeharness/features/care/domain/care_models.dart';
import 'package:lifeharness/features/care/presentation/care_page.dart';
import 'package:lifeharness/features/care/presentation/care_providers.dart';
import 'package:lifeharness/features/care/presentation/milestone_page.dart';
import 'package:lifeharness/features/care/presentation/vaccine_page.dart';

/// 呵护批6 · p-vaccine + sheetVaxAdd + p-milestones + sheetMilestone 用例。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late CareRepository repo;
  late ProviderContainer container;
  late int babyId;

  final today = DateTime.now().withoutTimeCare();
  String day(int offset) =>
      careDayKey(today.add(Duration(days: offset)));

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = CareRepository(db);
    babyId = await repo.addBaby(
        name: '团子', sex: '女', birth: '2026-01-07', color: 'sky');
  });

  tearDown(() async {
    await db.close();
    container.dispose();
  });

  Future<void> seedVax() async {
    await repo.addVaccine(CareVaccine(
        babyId: babyId, name: '手足口病灭活疫苗', dose: '第1剂', due: day(23), kind: '自费', lead: 7));
    await repo.addVaccine(CareVaccine(
        babyId: babyId, name: '麻腮风减毒', dose: '第1剂', due: day(-9), kind: '免规', lead: 7));
    await repo.addVaccine(CareVaccine(
        babyId: babyId, name: '乙脑减毒', dose: '第1剂', due: day(-20), kind: '免规', lead: 7, doneDay: day(-20)));
  }

  Future<void> seedMiles() async {
    for (final (n, c, d, done) in [
      ('独坐', '大运动', '2026-07-20', true),
      ('扶站', '大运动', '2026-08-28', true),
      ('捏取小丸', '精细动作', '2026-09-05', true),
      ('独立站立', '大运动', null, false),
      ('再见手势', '社交', null, false),
    ]) {
      await repo.addMilestone(CareMilestone(
          babyId: babyId, name: n, cat: c, day: d, done: done));
    }
  }

  Future<void> pump(WidgetTester tester, Widget page) async {
    container = ProviderContainer(
      overrides: [careRepositoryProvider.overrideWithValue(repo)],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: page),
    ));
    await settle5(tester);
  }

  Future<void> pumpRoot(WidgetTester tester) async {
    container = ProviderContainer(
      overrides: [careRepositoryProvider.overrideWithValue(repo)],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/x',
          routes: [
            GoRoute(path: '/x', builder: (_, _) => const CarePage()),
            GoRoute(path: '/care/growth', builder: (_, _) => const Scaffold(body: Text('曲线-STUB'))),
            GoRoute(path: '/care/vaccine', builder: (_, _) => const VaccinePage()),
            GoRoute(path: '/care/milestones', builder: (_, _) => const MilestonesPage()),
          ],
        ),
      ),
    ));
    await settle5(tester);
    if (container.read(careViewProvider) == 'cycle') {
      await tester.tap(find.byKey(const ValueKey('care-swap')));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> openSheetK(WidgetTester tester, Key key) async {
    await tester.tap(find.byKey(key));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
  }

  Future<void> tapK(WidgetTester tester, Key key) async {
    Finder f = find.byKey(key);
    if (f.evaluate().length > 1) f = f.first;
    await tester.ensureVisible(f);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(f);
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(400, 30));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
  }

  testWidgets('疫苗页：hero 汇总 + 三态切换 + late 行文案', (tester) async {
    await useSurface(tester, const Size(800, 2800));
    await seedVax();
    await pump(tester, const VaccinePage());
    expect(find.textContaining('待接种 2 剂 · 下一剂'), findsOneWidget);
    expect(find.textContaining('麻腮风减毒'), findsOneWidget);
    // 默认「计划中」：done 行不出现
    expect(find.text('乙脑减毒 第1剂'), findsNothing);
    expect(find.textContaining('已过计划日期 9 天 · 尽快补种'), findsOneWidget);
    expect(find.textContaining('还有 23 天 · 提前 7 天提醒'), findsOneWidget);
    await tapK(tester, const ValueKey('vax-t-done'));
    expect(find.text('已完成 · 凭证已归档'), findsOneWidget);
    await tapK(tester, const ValueKey('vax-t-all'));
    expect(find.textContaining('待接种 2 剂'), findsOneWidget);
    final all = find.byWidgetPredicate((w) =>
        w is Text && (w.data == '乙脑减毒 第1剂' || w.data == '麻腮风减毒 第1剂' || w.data == '手足口病灭活疫苗 第1剂'));
    expect(all, findsNWidgets(3));
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('完成钮 → done + L10 联动 toast；重新发起回落', (tester) async {
    await useSurface(tester, const Size(800, 2800));
    await seedVax();
    await pump(tester, const VaccinePage());
    final d0 = await repo.loadAll();
    final hf = d0.vaccines.firstWhere((v) => v.name == '手足口病灭活疫苗');
    await tapK(tester, ValueKey('vax-done-${hf.id}'));
    await pollText(tester, '已记录接种 · 下一针提醒已自动写入「重要日子」（联动 L10）');
    final v1 = (await repo.vaccines(babyId)).firstWhere((v) => v.name == '手足口病灭活疫苗');
    expect(v1.done, isTrue);
    await tapK(tester, const ValueKey('vax-t-done'));
    await tapK(tester, ValueKey('vax-undo-${hf.id}'));
    await pollText(tester, '已重新发起「手足口病灭活疫苗」接种计划');
    await settle5(tester);
    final v2 = (await repo.vaccines(babyId)).firstWhere((v) => v.name == '手足口病灭活疫苗');
    expect(v2.done, isFalse);
    // 凭证钮
    final y = d0.vaccines.firstWhere((v) => v.done);
    await tapK(tester, ValueKey('vax-cert-${y.id}'));
    await pollText(tester, '查看接种凭证照片（本地图档）');
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('sheetVaxAdd：空名拦截 → 新建自费/提前3天 → 编辑删除', (tester) async {
    await useSurface(tester, const Size(800, 2800));
    await pump(tester, const VaccinePage());
    await openSheetK(tester, const ValueKey('vx-add'));
    await tapK(tester, const ValueKey('va-save'));
    await pollText(tester, '先填疫苗名称');
    await tester.enterText(find.byKey(const ValueKey('va-name')), '13价肺炎');
    await tester.enterText(find.byKey(const ValueKey('va-dose')), '第2剂');
    await tapK(tester, const ValueKey('va-kind-自费'));
    await tapK(tester, const ValueKey('va-lead-3'));
    await tapK(tester, const ValueKey('va-save'));
    await tester.pump(const Duration(milliseconds: 400));
    await pollText(tester, '已加入「团子」计划 · 提前 3 天提醒已生成（联动 L10）');
    await settle5(tester);
    final vs = await repo.vaccines(babyId);
    final p = vs.firstWhere((v) => v.name == '13价肺炎');
    expect(p.kind, '自费');
    expect(p.lead, 3);
    expect(p.dose, '第2剂');
    // 编辑 → 删除
    await tapK(tester, ValueKey('vax-row-${p.id}'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    expect(find.text('编辑疫苗计划'), findsOneWidget);
    await tapK(tester, const ValueKey('va-del'));
    await pollText(tester, '计划已删除');
    expect((await repo.vaccines(babyId)).map((v) => v.id), isNot(contains(p.id)));
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('里程碑页：汇总/双区/达成钮/空名拦截/编辑删除', (tester) async {
    await useSurface(tester, const Size(800, 2800));
    await seedMiles();
    await pump(tester, const MilestonesPage());
    expect(find.textContaining('已达成 3 项 · 观察中 2 项 · 覆盖 3 个领域'), findsOneWidget);
    // 倒序：捏取小丸在首
    expect(find.text('捏取小丸'), findsOneWidget);
    // 观察中 → 达成
    final d0 = await repo.loadAll();
    final m = d0.milestones.firstWhere((x) => x.name == '独立站立');
    await tapK(tester, ValueKey('ms-done-${m.id}'));
    await pollText(tester, '已记录「独立站立」达成 · 同步到成长档案');
    await settle5(tester);
    final m1 = (await repo.milestones(babyId)).firstWhere((x) => x.name == '独立站立');
    expect(m1.done, isTrue);
    // 新建（空名拦截 + 语言域）
    await tapK(tester, const ValueKey('ms-add'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    await tapK(tester, const ValueKey('ms-save'));
    await pollText(tester, '先填里程碑名称');
    await tester.enterText(find.byKey(const ValueKey('ms-name')), '叫爸爸妈妈');
    await tapK(tester, const ValueKey('ms-cat-语言'));
    await tapK(tester, const ValueKey('ms-save'));
    await tester.pump(const Duration(milliseconds: 400));
    await pollText(tester, '✔ 里程碑已保存');
    await settle5(tester);
    expect((await repo.milestones(babyId)).where((x) => x.cat == '语言').length, 1);
    // 编辑 → 删除
    final j = (await repo.milestones(babyId)).firstWhere((x) => x.name == '叫爸爸妈妈');
    await tapK(tester, ValueKey('ms-row-${j.id}'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    expect(find.text('编辑里程碑'), findsOneWidget);
    await tapK(tester, const ValueKey('ms-del'));
    await pollText(tester, '里程碑已删除');
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('宝宝页迷你卡：疫苗 D-N / 里程碑 msSub + 入口跳转', (tester) async {
    await useSurface(tester, const Size(800, 2800));
    await seedVax();
    await seedMiles();
    await pumpRoot(tester);
    // 疫苗迷你卡：最近 3 针未完成（含 late ⚠️）
    expect(find.textContaining('D-23'), findsOneWidget);
    expect(find.textContaining('已到期'), findsOneWidget); // late 行（MM-DD · 已到期 合成串）
    expect(find.textContaining('独坐 ✓ · 扶站 ✓ · 下一个观察：捏取小丸'), findsNothing); // 达成序取最近两项
    expect(find.textContaining('下一个观察'), findsOneWidget);
    expect(find.textContaining('扶站 ✓'), findsOneWidget);
    await tapK(tester, const ValueKey('thumb-vax'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    expect(find.textContaining('团子 · 疫苗计划'), findsOneWidget);
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 400));
    await tapK(tester, const ValueKey('thumb-milestones'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    expect(find.textContaining('已达成 3 项'), findsOneWidget);
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });
}
