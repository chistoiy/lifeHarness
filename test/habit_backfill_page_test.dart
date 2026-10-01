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
import 'package:lifeharness/features/habit/presentation/habit_providers.dart';
import 'package:lifeharness/features/habit/presentation/habits_page.dart';

/// 习惯批3a · 补卡弹层页面用例。独立文件防 isolate 污染。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late dynamic db;
  late HabitRepository repo;

  String key(int back) => dayKey(DateTime.now().subtract(Duration(days: back)));

  /// 补卡日历按月渲染（锚＝今天所在月；可 `btn-hbf-prev` 翻月）。
  /// 月初窗口里「昨天/前天」属上月——存在性检查式翻月，跨月/月内两种日历都成立。
  Future<void> tapDay(WidgetTester tester, String day) async {
    if (find.byKey(ValueKey('hbf-day-$day')).evaluate().isEmpty) {
      await tester.tap(find.byKey(const ValueKey('btn-hbf-prev')));
      await settle5(tester);
    }
    await tester.tap(find.byKey(ValueKey('hbf-day-$day')));
    await settle5(tester);
  }

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = HabitRepository(db);
  });
  tearDown(() async => db.close());

  ProviderContainer? captured;

  Future<void> pump(WidgetTester tester) async {
    captured = ProviderContainer(
      overrides: [habitRepositoryProvider.overrideWithValue(repo)],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: captured!,
        child: const MaterialApp(home: HabitsPage()),
      ),
    );
    await settle5(tester);
  }

  testWidgets('hero 补卡徽标计数 + 补卡弹层多选落库与撤销', (tester) async {
    final h = await repo.saveHabit(
      Habit(name: '晨跑', startDate: key(30)),
    );
    await repo.upsertEntry(
      h.id,
      day: key(3),
      checked: true,
      origin: HabitEntry.oBackfill,
      backfilled: true,
    );
    await useSurface(tester);
    await pump(tester);
    expect(find.text('补卡 1'), findsOneWidget);

    // 打开补卡弹层
    await tester.tap(find.text('补卡 1'));
    await settle5(tester);
    expect(find.text('补卡 · 晨跑'), findsOneWidget);
    expect(find.text('暂无补记'), findsNothing);
    expect(find.text('1 条'), findsOneWidget);

    // 选两个过去日 → 确认补卡（月初时先翻回上月）
    await tapDay(tester, key(2));
    await tapDay(tester, key(1));
    expect(find.text('已选 2 天'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('btn-hbf-save')));
    final okToast = await pollText(tester, '已为「晨跑」补记 2 天 · 时刻 08:00 · 已计入连续');
    expect(okToast, isTrue);
    final es = await repo.entriesOf(h.id);
    expect(es[key(2)]!.backfilled, isTrue);
    expect(es[key(2)]!.origin, HabitEntry.oBackfill);
    expect(es[key(1)]!.checkAt, '08:00');
    await clearToasts(tester);

    // 记录区 3 条 + 撤销一条
    await pump(tester);
    await tester.tap(find.text('补卡 3'));
    await settle5(tester);
    final undo = find.byKey(ValueKey('hbf-undo-${key(1)}'));
    await tester.scrollUntilVisible(undo, 80, scrollable: find.byType(Scrollable).last);
    await tester.tap(undo);
    expect(await pollText(tester, '已撤销 ${key(1).substring(5)} 的补卡'), isTrue);
    expect((await repo.entriesOf(h.id)).containsKey(key(1)), isFalse);
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('有量习惯：补记数值行随所选习惯出现并落库', (tester) async {
    final h = await repo.saveHabit(
      Habit(name: '喝水', unit: '杯', goal: 8, startDate: key(30)),
    );
    await useSurface(tester);
    await pump(tester);
    await tester.tap(find.text('补卡 0'));
    await settle5(tester);
    expect(find.text('补记数值'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('hbf-val-0')),
      '6',
    );
    await tapDay(tester, key(1));
    await tester.tap(find.byKey(const ValueKey('btn-hbf-save')));
    expect(
      await pollText(
        tester,
        '已为「喝水」补记 1 天 · 时刻 08:00 · 数值 6 · 已计入连续',
      ),
      isTrue,
    );
    final e = (await repo.entriesOf(h.id))[key(1)]!;
    expect(e.value, 6);
    expect(habitOkAt((await repo.habitById(h.id))!, e), isTrue);
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });
}
