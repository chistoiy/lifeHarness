import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/care/data/care_repository.dart';
import 'package:lifeharness/features/care/domain/care_models.dart';
import 'package:lifeharness/features/care/presentation/babies_page.dart';
import 'package:lifeharness/features/care/presentation/care_page.dart';
import 'package:lifeharness/features/care/presentation/care_providers.dart';

/// 呵护批2 · 宝宝档案与 hero 用例（建档/切换/记录人/过敏史/删除守卫）。
/// 独立文件防 isolate 污染。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late CareRepository repo;
  late ProviderContainer container;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = CareRepository(db);
  });

  tearDown(() async {
    await db.close(); // ffi-no-isolate 的 :memory: 跨 open 复用，必须关闭重建
    container.dispose();
  });

  Future<void> pumpCare(WidgetTester tester, {bool baby = true}) async {
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
    if (baby && container.read(careViewProvider) == 'cycle') {
      await tester.tap(find.byKey(const ValueKey('care-swap')));
      await settle5(tester);
    }
  }

  Future<void> pumpBabies(WidgetTester tester) async {
    container = ProviderContainer(
      overrides: [careRepositoryProvider.overrideWithValue(repo)],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: BabiesPage()),
      ),
    );
    await settle5(tester);
  }

  testWidgets('无档案：建档空态 → 创建后 hero 出昵称/性别/生日', (tester) async {
    await useSurface(tester);
    await pumpCare(tester);
    expect(find.textContaining('建立宝宝档案'), findsOneWidget);
    await tester.tap(find.textContaining('建立宝宝档案'));
    await settle5(tester);
    await tester.enterText(find.byKey(const ValueKey('ab-name')), '团子');
    await tester.tap(find.byKey(const ValueKey('ab-save')));
    await pollText(tester, '档案已创建');
    await clearToasts(tester);
    expect(find.text('团子'), findsOneWidget);
    expect(find.textContaining('女宝 · 生日'), findsOneWidget);
    expect(find.text('妈妈 · 记录中 ›'), findsOneWidget);
    final d = await repo.loadAll();
    expect(d.currentBaby?.name, '团子');
  });

  testWidgets('sheetBabySwitch：双宝列表 + 点选切换 + 记录人即时切换', (tester) async {
    await useSurface(tester);
    final a = await repo.addBaby(name: '团子', sex: '女', birth: '2026-01-07', color: 'sky');
    await repo.addBaby(name: '糯米', sex: '男', birth: '2025-04-19', color: 'amber');
    await repo.setCurBaby(a);
    await pumpCare(tester);
    await tester.tap(find.byKey(const ValueKey('hero-carer')));
    await settle5(tester);
    expect(find.text('切换宝宝 / 记录人'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bsw-carer-爸爸')));
    await tester.pump();
    final nb = (await repo.babies()).firstWhere((x) => x.name == '糯米');
    await tester.tap(find.byKey(ValueKey('bsw-${nb.id}')));
    await settle5(tester);
    final d = await repo.loadAll();
    expect(d.currentBaby?.name, '糯米');
    expect(d.curCarer, '爸爸');
    expect(find.text('糯米'), findsWidgets);
  });

  testWidgets('记录人规则：添加重名拦截 / 删除最后一个守卫', (tester) async {
    await useSurface(tester);
    await pumpBabies(tester);
    await tester.tap(find.byKey(const ValueKey('carer-add')));
    await settle5(tester);
    await tester.enterText(find.byType(TextField).last, '外婆');
    await tester.tap(find.byKey(const ValueKey('cr-save')));
    await pollText(tester, '已添加并设为默认记录人');
    await clearToasts(tester);
    expect((await repo.carers()).any((c) => c.name == '外婆'), isTrue);
    expect(await repo.curCarer(), '外婆');
    // 逐个删到只剩一个
    for (final c in [...await repo.carers()]) {
      if ((await repo.carers()).length <= 1) break;
      await repo.delCarer(c.id);
    }
    final last = (await repo.carers()).single;
    expect(await repo.delCarer(last.id), isNull); // 仓储层守卫
  });

  testWidgets('过敏史档案侧：搜索→选食→反应→确定；重复被拦', (tester) async {
    await useSurface(tester);
    await repo.addBaby(name: '团子', sex: '女', birth: '2026-01-07', color: 'sky');
    await pumpBabies(tester);
    await tester.tap(find.byKey(const ValueKey('ala-add')));
    await settle5(tester);
    await tester.enterText(find.byKey(const ValueKey('ala-search')), '鸡蛋');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ala-food-鸡蛋')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ala-sym-口周发红')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ala-confirm')));
    await pollText(tester, '已加入「团子」过敏史');
    await clearToasts(tester);
    final d = await repo.loadAll();
    expect(d.allergies.single.food, '鸡蛋');
    expect(d.allergies.single.reaction, contains('口周发红'));
    // 档案卡上直接可见
    expect(find.text('鸡蛋'), findsWidgets);
    // 重复添加被拦
    await tester.tap(find.byKey(const ValueKey('ala-add')));
    await settle5(tester);
    await tester.enterText(find.byKey(const ValueKey('ala-search')), '鸡蛋');
    await tester.pump();
    expect(find.textContaining('已录'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('ala-food-鸡蛋')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ala-confirm')));
    await pollText(tester, '该食物已在过敏史中');
    await clearToasts(tester);
    expect((await repo.allergies(d.currentBaby!.id)).length, 1);
  });

  testWidgets('删除档案：二次确认 + 至少保留一个', (tester) async {
    await useSurface(tester);
    final a = await repo.addBaby(name: '团子', sex: '女', birth: '2026-01-07', color: 'sky');
    final b = await repo.addBaby(name: '糯米', sex: '男', birth: '2025-04-19', color: 'amber');
    await repo.addLog(CareRecord(babyId: b, day: careDayKey(DateTime.now()), k: 'water', s: '10:00', ml: 30));
    await pumpBabies(tester);
    await tester.tap(find.byKey(ValueKey('edit-$b')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('ab-del'))); // 第一次=arm
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ab-del'))); // 第二次确认
    await settle5(tester);
    final d = await repo.loadAll();
    expect(d.babies.map((x) => x.id), [a]);
    expect(d.currentBaby?.id, a);
    expect(d.logs, isEmpty);
    // 最后一个不可删（档案页编辑入口）
    await tester.tap(find.byKey(ValueKey('edit-$a')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('ab-del')));
    await pollText(tester, '至少保留一个宝宝档案');
  });
}
