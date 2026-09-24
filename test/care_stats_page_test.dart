import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/care/data/care_repository.dart';
import 'package:lifeharness/features/care/domain/care_models.dart';
import 'package:lifeharness/features/care/presentation/care_providers.dart';
import 'package:lifeharness/features/care/presentation/care_stats_page.dart';

/// 呵护批7 · p-babyStats 喂养分析（四 tab 换肤 + 7×24 钟 + 三量卡 + 筛选）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late CareRepository repo;
  late ProviderContainer container;
  late int babyId;

  final today = DateTime.now().withoutTimeCare();
  String day(int back) => careDayKey(today.subtract(Duration(days: back)));

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = CareRepository(db);
    babyId = await repo.addBaby(
        name: '团子', sex: '女', birth: '2026-01-07', color: 'sky');
    // 今天：配方 120@10 时、瓶喂母乳 150@14 时；尿布 尿@08、混@12
    // 昨天：亲喂 15min 左8右7@14 时；睡眠 80min@13 时
    Future<void> log(String d, String k, String s,
        {double? ml, int? dur, String? seg, String? dia}) async {
      await repo.addLog(CareRecord(
          babyId: babyId,
          day: d,
          k: k,
          s: s,
          e: dur != null ? '${(int.parse(s.substring(0, 2)) + 1) % 24}:00' : null,
          ml: ml,
          dur: dur,
          seg: seg,
          dia: dia,
          rec: '妈妈'));
    }

    await log(day(0), 'formula', '10:00', ml: 120);
    await log(day(0), 'bmilk', '14:00', ml: 150);
    await log(day(0), 'diaper', '08:00', dia: 'pee');
    await log(day(0), 'diaper', '12:00', dia: 'mix');
    await log(day(1), 'nurse', '14:40', dur: 15, seg: '左8′/右7′');
    await log(day(1), 'sleep', '13:00', dur: 80);
  });

  tearDown(() async {
    await db.close();
    container.dispose();
  });

  Future<void> pump(WidgetTester tester) async {
    container = ProviderContainer(
      overrides: [careRepositoryProvider.overrideWithValue(repo)],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: CareStatsPage()),
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

  testWidgets('默认喂奶 tab：双分区行 + 均值徽标 + INS 文案', (tester) async {
    await useSurface(tester, const Size(800, 3400));
    await pump(tester);
    expect(find.text('时间规律'), findsOneWidget);
    expect(find.text('▎亲喂母乳'), findsOneWidget);
    expect(find.text('▎瓶喂（配方奶 + 瓶喂母乳）'), findsOneWidget);
    expect(find.text('近7天平均每天 39 ml'), findsOneWidget); // (120+150)/7
    expect(find.textContaining('瓶喂均值稳定'), findsOneWidget);
    expect(find.textContaining('规则引擎本地生成'), findsOneWidget);
    // 今天列高亮 + 日期行
    expect(find.textContaining('今天'), findsWidgets);
    // 睡眠/换尿布卡不出现
    expect(find.text('睡眠量'), findsNothing);
    expect(find.text('换尿布次数'), findsNothing);
  });

  testWidgets('睡眠 tab 换肤：时长格式化 + 均值；尿布 tab 点阵图例', (tester) async {
    await useSurface(tester, const Size(800, 3400));
    await pump(tester);
    await tapK(tester, const ValueKey('bst-sleep'));
    expect(find.text('睡眠量'), findsOneWidget);
    expect(find.text('近7天平均每天 11小时26分钟'), findsOneWidget); // 80/7 min→h/m
    expect(find.textContaining('睡前程序'), findsOneWidget);
    await tapK(tester, const ValueKey('bst-dia'));
    expect(find.text('换尿布次数'), findsOneWidget);
    expect(find.text('近7天平均每天 0.3次'), findsOneWidget); // 2/7
    expect(find.textContaining('嘘嘘+臭臭'), findsWidgets);
    expect(find.textContaining('砖红色、灰白色'), findsOneWidget);
  });

  testWidgets('全部 tab：筛选钮出现 → sheetBsFilter 只留睡眠', (tester) async {
    await useSurface(tester, const Size(800, 3400));
    await pump(tester);
    await tapK(tester, const ValueKey('bst-all'));
    expect(find.text('喂奶量'), findsOneWidget); // 三卡齐
    expect(find.text('睡眠量'), findsOneWidget);
    expect(find.text('换尿布次数'), findsOneWidget);
    expect(find.textContaining('喂养-排尿-睡眠链路节奏正常'), findsOneWidget);
    await tapK(tester, const ValueKey('bs-filter'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    expect(find.text('请筛选记录项'), findsOneWidget);
    await tapK(tester, const ValueKey('bsf-sleep'));
    await tapK(tester, const ValueKey('bsf-ok'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    // 仅剩睡眠：奶卡 0 次
    expect(find.text('近7天平均每天 0 ml'), findsOneWidget);
  });

  testWidgets('参考表钮 → V1.x 接入 toast；筛选不筛选回落', (tester) async {
    await useSurface(tester, const Size(800, 3400));
    await pump(tester);
    await tapK(tester, const ValueKey('bs-ref'));
    await pollText(tester, 'V1.x 接入');
    await tapK(tester, const ValueKey('bst-all'));
    await tapK(tester, const ValueKey('bs-filter'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    await tapK(tester, const ValueKey('bsf-water'));
    await tapK(tester, const ValueKey('bsf-clear'));
    await tapK(tester, const ValueKey('bsf-ok'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    expect(find.text('近7天平均每天 39 ml'), findsOneWidget);
  });
}
