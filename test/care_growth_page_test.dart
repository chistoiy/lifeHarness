import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/care/data/care_repository.dart';
import 'package:lifeharness/features/care/domain/care_models.dart';
import 'package:lifeharness/features/care/presentation/care_page.dart';
import 'package:lifeharness/features/care/presentation/care_providers.dart';
import 'package:lifeharness/features/care/presentation/growth_page.dart';

/// 呵护批5 · p-growth 全屏 / sheetBabyMeasure / 宝宝页缩略卡用例。
/// DB 在 setUp 建表并 close，页面直接跑内存库。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late CareRepository repo;
  late ProviderContainer container;
  late int babyId;

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

  Future<void> seedMeasures() async {
    await repo.addMeasure(CareMeasure(
        babyId: babyId, day: '2026-06-19', w: 7.8, h: 68.5, head: 43, rec: '爸爸'));
    await repo.addMeasure(CareMeasure(
        babyId: babyId, day: '2026-09-19', w: 8.9, h: 71, head: 44.5, rec: '妈妈'));
  }

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    container = ProviderContainer(
      overrides: [careRepositoryProvider.overrideWithValue(repo)],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: page),
    ));
    await settle5(tester);
  }

  Future<void> tapK(WidgetTester tester, Key key) async {
    Finder f = find.byKey(key);
    if (f.evaluate().length > 1) f = f.first;
    await tester.ensureVisible(f);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(f);
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('p-growth：描点读数/预警未触发/测量历史行', (tester) async {
    await useSurface(tester, const Size(800, 2800));
    await seedMeasures();
    await pumpPage(tester, const GrowthPage());
    // 最新读数（女宝 8.4 月龄 8.9kg → P 档）
    expect(find.textContaining('8.9kg @ '), findsOneWidget);
    expect(find.textContaining('百分位'), findsWidgets);
    expect(find.textContaining('近 1 次增速正常'), findsOneWidget);
    // 预警卡未触发文案
    expect(find.textContaining('未触发预警'), findsOneWidget);
    // 测量历史两行 + 百分位列（爸爸/妈妈）
    expect(find.text('妈妈'), findsWidgets);
    expect(find.text('爸爸'), findsWidgets);
    expect(find.text('09-19'), findsOneWidget);
    expect(find.text('06-19'), findsOneWidget);
    // 图表标题（按性别）
    expect(find.textContaining('团子 · 女宝 WHO 参考带'), findsNothing); // 画布文字不断言
    // 切身高 + Z 模
    await tapK(tester, const ValueKey('gk-身高'));
    expect(find.textContaining('71.0cm @ '), findsOneWidget);
    await tapK(tester, const ValueKey('gm-2'));
    expect(find.textContaining('Z 分数'), findsOneWidget);
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('sheetBabyMeasure：缺项拦截 → 补全入账 + toast', (tester) async {
    await useSurface(tester, const Size(800, 2800));
    await seedMeasures();
    await pumpPage(tester, const GrowthPage());
    await tapK(tester, const ValueKey('g-measure-add'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    // 预填最近一次测量值
    expect(find.text('8.9'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('bm-w')), '');
    await tapK(tester, const ValueKey('bm-save'));
    await pollText(tester, '请填写三项测量值');
    // 补全 + 换记录人 → 保存
    await tester.enterText(find.byKey(const ValueKey('bm-w')), '9.1');
    await tapK(tester, const ValueKey('bm-rec-爸爸'));
    await tapK(tester, const ValueKey('bm-save'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    await pollText(tester, '已描点生长曲线');
    final ms = await repo.measures(babyId);
    expect(ms.length, 3);
    expect(ms.first.w, 9.1); // measures() 按日倒序，新行居首
    expect(ms.first.rec, '爸爸');
    // 页面刷新后历史三行
    expect(find.text('06-19'), findsOneWidget);
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('跨带样本 → 预警文案出现', (tester) async {
    await useSurface(tester, const Size(800, 2800));
    await repo.addMeasure(CareMeasure(
        babyId: babyId, day: '2026-08-20', w: 10.5, h: 74, head: 45, rec: '妈妈'));
    await repo.addMeasure(CareMeasure(
        babyId: babyId, day: '2026-09-05', w: 6.0, h: 66, head: 42, rec: '妈妈'));
    await pumpPage(tester, const GrowthPage());
    expect(find.textContaining('下跨 4 条主百分位带'), findsOneWidget);
    expect(find.textContaining('不构成医疗建议'), findsOneWidget);
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('宝宝页缩略卡：无实测文案 → P/SD/Z 钮轮换 + 入口', (tester) async {
    await useSurface(tester, const Size(800, 2800));
    container = ProviderContainer(
      overrides: [careRepositoryProvider.overrideWithValue(repo)],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: CarePage()),
    ));
    await settle5(tester);
    if (container.read(careViewProvider) == 'cycle') {
      await tester.tap(find.byKey(const ValueKey('care-swap')));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('尚无实测 · 保存测量后自动描点'), findsOneWidget);
    expect(find.text('体重 · 待首次测量'), findsOneWidget);
    await tapK(tester, const ValueKey('thumb-gmode'));
    expect(find.text('SD'), findsWidgets);
    // 落库后缩略卡出点与读数
    await seedMeasures();
    container.read(careTickProvider.notifier).state++;
    await tester.pump();
    await settle5(tester);
    expect(find.textContaining('2 次实测'), findsOneWidget);
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });
}
