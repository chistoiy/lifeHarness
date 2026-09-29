import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/care/data/care_repository.dart';
import 'package:lifeharness/features/care/presentation/care_page.dart';
import 'package:lifeharness/features/care/presentation/care_providers.dart';
import 'package:lifeharness/features/care/domain/care_models.dart';

/// 呵护批1 · 她·周期主视图用例（hero 推导 / 日记录弹层闭环 / 感受保存 / 视图互切）。
/// 独立文件防 isolate 污染。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late CareRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = CareRepository(db);
  });

  tearDown(() => db.close());

  Future<ProviderContainer> pump(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [careRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CarePage()),
      ),
    );
    await settle5(tester);
    return container;
  }

  testWidgets('空库首屏：周期视图空态 hero + 记录今天入口', (tester) async {
    await useSurface(tester);
    await pump(tester);
    expect(find.text('呵护 · 周期'), findsOneWidget);
    expect(find.text('开始记录你的周期'), findsOneWidget);
    expect(find.text('🩸 记录今天'), findsOneWidget);
    expect(find.text('今日感受'), findsOneWidget);
    expect(find.text('周期统计'), findsOneWidget);
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('日记录弹层闭环：标记经期第 1 天 → hero 出周期第 1 天 + 存档 toast',
      (tester) async {
    await useSurface(tester);
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('cy-record-today')));
    await settle5(tester);
    expect(find.text('🌸 日记录 · ${careDayKey(DateTime.now())}'), findsOneWidget);
    // 经期第 1 天 + 经量中 + 一个感受 + 备注
    await tester.tap(find.byKey(const ValueKey('cy-state-p1')));
    await tester.pump();
    await tester.tap(find.text('中').hitTestable());
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('cy-note')), '热敷后缓解');
    await tester.tap(find.byKey(const ValueKey('cy-save')));
    await pollText(tester, '旧预测已存档');
    await clearToasts(tester);
    expect(find.textContaining('周期进行中'), findsOneWidget);
    expect(find.text('1'), findsWidgets); // hero 大字=周期第 1 天
    final d = await repo.loadAll();
    final today = d.cycleDays[careDayKey(DateTime.now())]!;
    expect(today.state, 'p1');
    expect(today.flow, '中');
    expect(today.note, '热敷后缓解');
    // 预测存档行已落库
    expect(await repo.predictions(), isNotEmpty);
  });

  testWidgets('今日感受保存 → 覆盖当日行 + 提示 AI 聚合文案', (tester) async {
    await useSurface(tester);
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('sym-⚡ 精力旺')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sym-save')));
    await pollText(tester, '今日感受已存');
    final d = await repo.loadAll();
    expect(d.cycleDays[careDayKey(DateTime.now())]!.syms, ['⚡ 精力旺']);
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('周期/宝宝点标题互切不堆栈：无返回钮、汇总钮仅宝宝侧',
      (tester) async {
    await useSurface(tester);
    await repo.addBaby(name: '团子', sex: '女', birth: '2026-01-07', color: 'sky');
    await pump(tester);
    expect(find.text('呵护 · 周期'), findsOneWidget);
    expect(find.byKey(const ValueKey('care-stats-btn')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('care-swap')));
    await settle5(tester);
    expect(find.text('呵护 · 宝宝'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsNothing); // 两侧均无返回键
    expect(find.byKey(const ValueKey('care-stats-btn')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('care-swap')));
    await settle5(tester);
    expect(find.text('呵护 · 周期'), findsOneWidget);
  });
}
