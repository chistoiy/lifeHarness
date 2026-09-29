import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/habit/data/habit_repository.dart';
import 'package:lifeharness/features/habit/domain/habit.dart';
import 'package:lifeharness/features/habit/domain/habit_calc.dart';
import 'package:lifeharness/features/habit/domain/habit_entry.dart';
import 'package:lifeharness/features/habit/presentation/habit_detail_page.dart';
import 'package:lifeharness/features/habit/presentation/habit_providers.dart';

/// 习惯批3b · 详情页页面用例。独立文件防 isolate 污染。
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

  Future<void> pump(WidgetTester tester, String id) async {
    final c = ProviderContainer(
      overrides: [habitRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(home: HabitDetailPage(habitId: id)),
      ),
    );
    await settle5(tester);
  }

  testWidgets('正向详情：四指标/日历/流水/里程碑/规则与绑定', (tester) async {
    final h = await repo.saveHabit(
      Habit(name: '晨跑', startDate: key(30)),
    );
    for (final back in [3, 2, 1]) {
      await repo.upsertEntry(h.id, day: key(back), checked: true);
    }
    await repo.upsertEntry(
      h.id,
      day: key(3),
      checked: true,
      origin: HabitEntry.oBackfill,
      backfilled: true,
    );
    await useSurface(tester);
    await pump(tester, h.id);
    expect(find.text('习惯详情'), findsOneWidget);
    // 四指标（3 天流水 → streak 3）
    expect(find.text('当前连续'), findsOneWidget);
    expect(find.text('3'), findsWidgets);
    expect(find.text('打卡次数'), findsOneWidget);
    expect(find.text('跟踪中'), findsOneWidget);
    // 日历与流水
    expect(find.text('打卡日历'), findsOneWidget);
    expect(find.text('绿点=已打卡'), findsOneWidget);
    expect(find.text('打卡流水 · 近 14 天'), findsOneWidget);
    expect(find.text('补记'), findsWidgets);
    // 里程碑
    expect(find.text('里程碑'), findsOneWidget);
    expect(find.textContaining('天 · 还差'), findsWidgets);
    // 规则与绑定
    expect(find.text('规则与绑定'), findsOneWidget);
    expect(find.textContaining('已跟踪'), findsOneWidget);
    expect(find.textContaining('张可用 · 本月已用'), findsOneWidget);
    // 维度切换
    await tester.tap(find.byKey(const ValueKey('hd-dim-m')));
    await settle5(tester);
    expect(find.text('近30天达成'), findsOneWidget);
    // 日历今日格 → 指引 toast
    await tester.tap(find.byKey(ValueKey('hd-cal-${key(0)}')));
    expect(await pollText(tester, '今天请在卡片上打卡或记量'), isTrue);
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('负向详情：触发统计/情境分布/明细删除', (tester) async {
    final h = await repo.saveHabit(
      Habit(name: '奶茶', type: Habit.kNeg, startDate: key(30), negLimit: 2),
    );
    await repo.recordTrigger(
      h.id,
      day: key(1),
      amount: 1,
      amountText: '1 杯',
      reasons: ['应酬'],
      note: '下午茶',
    );
    await useSurface(tester);
    await pump(tester, h.id);
    expect(find.text('触发统计'), findsOneWidget);
    expect(find.text('情境分布'), findsOneWidget);
    expect(find.text('应酬'), findsOneWidget);
    expect(find.text('触发明细'), findsOneWidget);
    expect(find.text('记一次触发'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('hd-slip-del-1')));
    expect(await pollText(tester, '已删除该条触发记录'), isTrue);
    expect(await repo.slipsOf(h.id), isEmpty);
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('组习惯详情：组内子项卡与达成规则文案', (tester) async {
    final h = await repo.saveHabit(
      Habit(
        name: '健身组',
        startDate: key(30),
        groupRule: Habit.kRuleHalf,
        subs: const [
          HabitSub(name: '深蹲', unit: '个', goal: 20),
          HabitSub(name: '跑步', unit: '分钟', goal: 20),
        ],
      ),
    );
    await useSurface(tester);
    await pump(tester, h.id);
    expect(find.text('组 · 2 项'), findsOneWidget);
    expect(find.text('组内子项'), findsOneWidget);
    expect(find.text('达成规则：过半子项达标'), findsOneWidget);
    expect(find.text('子项分别统计'), findsOneWidget);
    expect(find.text('编辑子项'), findsOneWidget);
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });
}
