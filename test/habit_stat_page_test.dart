import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/habit/data/habit_repository.dart';
import 'package:lifeharness/features/habit/domain/habit.dart';
import 'package:lifeharness/features/habit/domain/habit_calc.dart';
import 'package:lifeharness/features/habit/presentation/habit_providers.dart';
import 'package:lifeharness/features/habit/presentation/habit_stat_page.dart';

/// 习惯批4 · 统计页用例。独立文件防 isolate 污染。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late dynamic db;
  late HabitRepository repo;

  String key(int back) => dayKey(DateTime.now().subtract(Duration(days: back)));

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = HabitRepository(db);
  });
  tearDown(() async => db.close());

  Future<void> pump(WidgetTester tester) async {
    final c = ProviderContainer(
      overrides: [habitRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: HabitStatPage()),
      ),
    );
    await settle5(tester);
  }

  testWidgets('hero 三卡 + 同期对比 + 周期前后翻', (tester) async {
    final h = await repo.saveHabit(
      Habit(name: '晨跑', startDate: key(30)),
    );
    for (final back in [2, 1]) {
      await repo.upsertEntry(h.id, day: key(back), checked: true);
    }
    await useSurface(tester);
    await pump(tester);
    expect(find.text('本周总达成率'), findsOneWidget);
    expect(find.text('打卡次数'), findsWidgets);
    expect(find.text('日均打卡'), findsOneWidget);
    expect(find.textContaining('2 个跟踪中习惯'), findsNothing);
    expect(find.textContaining('1 个跟踪中习惯（正向 1 · 负向 0）'), findsOneWidget);
    expect(find.text('同期对比'), findsOneWidget);
    // 已是当期再往前翻 → toast
    await tester.tap(find.byKey(const ValueKey('hs-next')));
    expect(await pollText(tester, '已是当前周期'), isTrue);
    await clearToasts(tester);
    await tester.tap(find.byKey(const ValueKey('hs-prev')));
    await settle5(tester);
    expect(find.text('第 1 期前'), findsOneWidget);
  });

  testWidgets('口径开关：日均分母按开始跟踪日 vs 按周期天数', (tester) async {
    final h = await repo.saveHabit(
      Habit(name: '晚起', startDate: key(2)),
    );
    await repo.upsertEntry(h.id, day: key(2), checked: true);
    await repo.upsertEntry(h.id, day: key(1), checked: true);
    await useSurface(tester);
    await pump(tester);
    // 开：分母=实际跟踪 3 天 → 日均 0.7
    expect(find.text('按开始跟踪日'), findsOneWidget);
    expect(find.text('0.7'), findsOneWidget);
    // 关：分母=整周 7 天 → 日均 0.3
    await repo.setKv('habit.spanFromStart', 'false');
    await pump(tester);
    expect(find.text('按周期天数'), findsOneWidget);
    expect(find.text('0.3'), findsOneWidget);
  });

  testWidgets('统计范围收窄 + 展开更多：时段/热力三模式', (tester) async {
    final a = await repo.saveHabit(Habit(name: '甲', startDate: key(30)));
    final b = await repo.saveHabit(Habit(name: '乙', startDate: key(30)));
    await repo.saveHabit(Habit(name: '丙', type: Habit.kNeg, startDate: key(30), negLimit: 2));
    await repo.upsertEntry(a.id, day: key(1), checked: true, checkAt: '07:10');
    await repo.upsertEntry(b.id, day: key(1), checked: true, checkAt: '20:00');
    await useSurface(tester);
    await pump(tester);
    expect(find.textContaining('3 个跟踪中习惯'), findsOneWidget);
    // 范围只选 2 个正向
    await tester.tap(find.byKey(const ValueKey('hs-scope')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('hs-scope-pos')));
    await settle5(tester);
    expect(find.text('已选 2 个'), findsOneWidget);
    expect(find.textContaining('正向 2 · 负向 0'), findsOneWidget);
    // 展开更多
    await tester.tap(find.byKey(const ValueKey('hs-more')));
    await settle5(tester);
    expect(find.text('打卡时段分析'), findsOneWidget);
    expect(find.text('样本 2 次 · 平均 13:30'), findsOneWidget);
    expect(find.text('打卡热力图'), findsOneWidget);
    expect(find.text('近 17 周 · 每格为一天达成习惯数'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hs-heat-1')));
    await settle5(tester);
    expect(find.text('近 17 周 · 深浅为一天记录量'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hs-heat-2')));
    await settle5(tester);
    expect(find.text('近 17 周 · 颜色为一天主要打卡时段'), findsOneWidget);
    expect(find.text('习惯排行'), findsOneWidget);
    expect(find.text('负向控制'), findsOneWidget);
    expect(find.text('连续纪录墙'), findsOneWidget);
  });
}
