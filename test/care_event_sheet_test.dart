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

/// 呵护批3 · sheetEventLog 统一录入 / 事件管理 / 速记排序用例。
/// 独立文件防 isolate 污染。周期 Timer 页禁 pumpAndSettle——统一小步 pump。
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

  Future<void> pumpBaby(WidgetTester tester) async {
    container = ProviderContainer(
      overrides: [careRepositoryProvider.overrideWithValue(repo)],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CarePage()),
      ),
    );
    await settle5(tester);
    if (container.read(careViewProvider) == 'cycle') {
      await tester.tap(find.byKey(const ValueKey('care-swap')));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> tapK(WidgetTester tester, Key key) async {
    Finder f = find.byKey(key);
    if (f.evaluate().length > 1) f = f.first;
    await tester.ensureVisible(f);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(f);
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> openEv(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey('ev-open-$key')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const ValueKey('el-save')));
    await tester.tap(find.byKey(const ValueKey('el-save')));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('瓶喂母乳：快选 150 → 入账 ml + 标题由数据生成', (tester) async {
    await useSurface(tester, const Size(800, 2800));
    await pumpBaby(tester);
    await openEv(tester, 'bmilk');
    expect(find.text('瓶喂母乳'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('el-quick-150')));
    await tester.pump(const Duration(milliseconds: 100));
    await save(tester);
    await pollText(tester, '瓶喂母乳已入账');
    final d = await repo.loadAll();
    expect(d.logs.single.ml, 150);
    expect(d.titleOf(d.logs.single), '瓶喂母乳 150ml');
    expect(find.text('瓶喂母乳 150ml'), findsWidgets); // 今日列表行
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('尿布臭臭：砖红触发就医参考 toast；粘稠默认糊状', (tester) async {
    await useSurface(tester, const Size(800, 2800));
    await pumpBaby(tester);
    await openEv(tester, 'diaper');
    await tapK(tester, const ValueKey('el-dia-poop'));
    await tester.pump();
    await tapK(tester, const ValueKey('el-color-砖红'));
    await tester.pump();
    await save(tester);
    await pollText(tester, '砖红色便建议拍照留档并咨询儿科');
    final r = (await repo.logs(babyId)).single;
    expect(r.dia, 'poop');
    expect(r.color, '砖红');
    expect(r.tex, '糊状');
    expect(r.vol, '中');
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('补剂两行一次入账多条 + chips 快填', (tester) async {
    await useSurface(tester, const Size(800, 2800));
    await pumpBaby(tester);
    await openEv(tester, 'supp');
    await tapK(tester, const ValueKey('el-supp-p-维生素D3'));
    await tester.pump();
    await tapK(tester, const ValueKey('el-supp-p-钙'));
    await tester.pump();
    await tapK(tester, const ValueKey('el-supp-amt-1'));
    await tester.enterText(find.byKey(const ValueKey('el-supp-amt-1')), '1袋');
    await save(tester);
    final logs = await repo.logs(babyId);
    expect(logs.length, 2);
    expect(logs.map((r) => r.name), containsAll(['维生素D3', '钙']));
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('辅食+过敏二级弹层：命中带反应同步入过敏史', (tester) async {
    await useSurface(tester, const Size(800, 2800));
    await pumpBaby(tester);
    await openEv(tester, 'solids');
    await tester.enterText(find.byKey(const ValueKey('el-solid-name')), '蛋黄泥');
    await tapK(tester, const ValueKey('el-ala-add'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    await tester.enterText(find.byKey(const ValueKey('ala-search')), '蛋黄');
    await tester.pump();
    await tapK(tester, const ValueKey('ala-food-蛋黄'));
    await tester.pump();
    await tapK(tester, const ValueKey('ala-sym-口周发红'));
    await tester.pump();
    await tapK(tester, const ValueKey('ala-confirm'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('蛋黄·口周发红'), findsOneWidget); // 命中 chip
    await save(tester);
    final d = await repo.loadAll();
    final r = d.logs.single;
    expect(r.name, '蛋黄泥');
    expect(r.ala!.single.f, '蛋黄');
    expect(d.allergies.single.food, '蛋黄'); // 反应非空→同步入档
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('自定义录入流：按摩/次数/固定速记区 → 宫格新增该事件', (tester) async {
    await useSurface(tester, const Size(800, 2800));
    await pumpBaby(tester);
    await openEv(tester, 'custom');
    await tester.enterText(find.byKey(const ValueKey('el-cus-name')), '按摩');
    await tapK(tester, const ValueKey('el-cus-pin'));
    await tester.pump();
    await save(tester);
    final d = await repo.loadAll();
    expect(d.logs.single.k, 'custom');
    expect(d.logs.single.name, '按摩');
    expect(d.customs.containsKey('cus:按摩'), isTrue);
    expect(d.evOrder.contains('cus:按摩'), isTrue);
    expect(find.text('按摩'), findsWidgets); // 速记宫格出现
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('二次编辑：改量后更新原行不新增；删除钮存在', (tester) async {
    await useSurface(tester, const Size(800, 2800));
    await repo.addLog(CareRecord(
        babyId: babyId,
        day: careDayKey(DateTime.now()),
        k: 'formula',
        s: '09:00',
        e: '09:10',
        ml: 120,
        rec: '妈妈'));
    await pumpBaby(tester);
    final d0 = await repo.loadAll();
    await tester.tap(find.byKey(ValueKey('today-rec-${d0.logs.single.id}')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    expect(find.text('配方奶 · 二次修改'), findsOneWidget);
    await tapK(tester, const ValueKey('el-quick-210'));
    await tester.pump();
    await save(tester);
    await pollText(tester, '已更新记录');
    final logs = await repo.logs(babyId);
    expect(logs.length, 1);
    expect(logs.single.ml, 210);
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('亲喂编辑：默认手动模式回填 seg + 最后使用提示', (tester) async {
    await useSurface(tester, const Size(800, 2800));
    await repo.addLog(CareRecord(
        babyId: babyId,
        day: careDayKey(DateTime.now()),
        k: 'nurse',
        s: '08:00',
        e: '08:14',
        dur: 14,
        seg: '左8′/右6′',
        rec: '妈妈'));
    await pumpBaby(tester);
    final d0 = await repo.loadAll();
    await tester.tap(find.byKey(ValueKey('today-rec-${d0.logs.single.id}')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    expect(find.text('最后使用：左8′ / 右6′'), findsOneWidget);
    expect(find.text('时长 14min（左8′/右6′）'), findsOneWidget);
    expect(find.text('手动输入'), findsOneWidget);
    expect(find.byKey(const ValueKey('el-nl')), findsOneWidget); // 手动双滚轮
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('速记区排序：⇅ 进入 → ▼ 移位 → 完成落库', (tester) async {
    await useSurface(tester, const Size(800, 2800));
    await pumpBaby(tester);
    await tester.tap(find.byKey(const ValueKey('ev-sort-toggle')));
    await tester.pump();
    await tapK(tester, const ValueKey('ev-move-▼'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ev-sort-toggle')));
    await pollText(tester, '事件顺序已保存');
    final d = await repo.loadAll();
    expect(d.evOrder.first, 'bmilk');
    expect(d.evOrder[1], 'nurse');
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('事件管理新建自定义（evf）→ 速记区与档案联动', (tester) async {
    await useSurface(tester, const Size(800, 2800));
    await pumpBaby(tester);
    await tester.tap(find.byKey(const ValueKey('ev-manage')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    expect(find.text('内置'), findsNWidgets(13));
    await tapK(tester, const ValueKey('evm-add'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byKey(const ValueKey('evf-name')), '抚触');
    await tapK(tester, const ValueKey('evf-unit-min'));
    await tester.pump();
    await tapK(tester, const ValueKey('evf-save'));
    await pollText(tester, '已新建「抚触」并加入速记区');
    await clearToasts(tester);
    final d = await repo.loadAll();
    expect(d.customs['cus:抚触']?.unit, 'min');
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('计时条：start → 卡内出现 → end 自动入账（不 pumpAndSettle）',
      (tester) async {
    await useSurface(tester, const Size(800, 2800));
    await pumpBaby(tester);
    container.read(feedTimerProvider.notifier).start('sleep');
    await tester.pump();
    expect(find.textContaining('睡眠计时'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byKey(const ValueKey('ft-end')));
    await tester.pump(const Duration(milliseconds: 300));
    await pollText(tester, '计时已存');
    final logs = await repo.logs(babyId);
    expect(logs.single.k, 'sleep');
    expect(logs.single.dur, 1); // 秒退化为至少 1 分钟（原型 Math.max(1,…)）
    expect(container.read(feedTimerProvider), isNull);
  });
}
