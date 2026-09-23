import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:lifeharness/features/habit/presentation/habit_auto_sheets.dart';
import 'package:lifeharness/features/habit/presentation/habit_edit_sheet.dart';
import 'package:lifeharness/features/habit/presentation/habits_page.dart';

/// 习惯批5 · hero 自动行 / 达成源 / 待确认队列 / 模板填充 页面用例。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late HabitRepository repo;

  String key(int back) => dayKey(DateTime.now().subtract(Duration(days: back)));

  setUp(() async {
    // 剪贴板通道在测试环境无实现：mock 掉让「复制文字版」链路可跑。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = HabitRepository(db);
  });
  tearDown(() => db.close());

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

  Future<Habit> seedBound({String name = '晨跑'}) => repo.saveHabit(
    Habit(
      name: name,
      sourceKinds: const ['待办勾选', '手动打卡'],
      startDate: key(30),
    ),
  );

  testWidgets('无绑定源：hero 行提示手动打卡可绑定', (tester) async {
    await useSurface(tester);
    await pump(tester);
    expect(find.text('全部为手动打卡 · 可绑定自动达成源'), findsOneWidget);
  });

  testWidgets('autoMode=0：pill 查看来源 → 达成源弹层含绑定数与说明', (tester) async {
    await seedBound();
    await useSurface(tester);
    await pump(tester);
    await tester.tap(find.text('今日自动达成 1 项 · 查看来源'));
    await settle5(tester);
    expect(find.text('自动达成源'), findsOneWidget);
    expect(find.text('勾选待办即打卡'), findsOneWidget);
    expect(find.text('绑定 1 个习惯'), findsNWidgets(2)); // 待办勾选 + 手动打卡
    expect(find.text('模拟一次自动达成'), findsNothing); // autoMode=0 隐藏
    await tester.tap(find.text('完成'));
    await settle5(tester);
  });

  testWidgets('autoMode=1：待确认 pill → 队列逐条确认落 auto-todo 流水', (tester) async {
    final h = await seedBound();
    await repo.setKv('habit.autoMode', '1');
    await repo.autoIngest(h, src: '待办勾选');
    await useSurface(tester);
    await pump(tester);
    await tester.tap(find.text('待确认 1 项 · 逐条确认'));
    await settle5(tester);
    expect(find.text('待确认打卡'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('hp-ok-${h.id}')));
    expect(await pollText(tester, '已确认「晨跑」· 来源 待办勾选'), true);
    final e = (await repo.entriesOf(h.id))[key(0)]!;
    expect(e.origin, HabitEntry.oAutoTodo);
    expect(await repo.pends(), isEmpty);
    await clearToasts(tester);
    // 队列清空后弹层显示空态
    expect(find.text('没有待确认的自动打卡'), findsOneWidget);
  });

  testWidgets('达成源弹层（autoMode=1）：模拟一次自动达成 → 入待确认队列', (tester) async {
    await seedBound();
    await repo.setKv('habit.autoMode', '1');
    captured = ProviderContainer(
      overrides: [habitRepositoryProvider.overrideWithValue(repo)],
    );
    await useSurface(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: captured!,
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showHabitSrcSheet(ctx),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('open'));
    await settle5(tester);
    expect(find.byKey(const ValueKey('btn-hs-sim')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('btn-hs-sim')));
    expect(await pollText(tester, '已模拟一次「待办勾选」达成'), true);
    final ps = await repo.pends();
    expect(ps.length, 1);
    expect(await repo.entriesOf((await repo.allHabits()).first.id), isEmpty);
  });

  testWidgets('模板库：编辑弹层「从模板填充」→ 选跑步带出周固定日', (tester) async {
    captured = ProviderContainer(
      overrides: [habitRepositoryProvider.overrideWithValue(repo)],
    );
    await useSurface(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: captured!,
        child: MaterialApp(
          home: Consumer(
            builder: (ctx, ref, _) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showHabitEditSheet(ctx, ref, null),
                  child: const Text('open-edit'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('open-edit'));
    expect(await pollText(tester, '从模板填充'), true);
    await settle5(tester); // 等弹层动画完全就位再点，避免 hitTest miss
    await tester.tap(find.byKey(const ValueKey('btn-he-tpl')));
    expect(await pollText(tester, '习惯模板'), true);
    await settle5(tester); // 弹层入场上滑中直接点行会 hitTest miss
    await tester.tap(find.byKey(const ValueKey('ht-跑步')));
    expect(await pollText(tester, '已按模板填充「跑步」· 可继续修改'), true);
    // 回填断言：名称与单位控件已带出（提醒时刻为滚轮控件，不断言字面文本）
    expect(find.text('跑步'), findsWidgets);
    expect(find.text('公里'), findsWidgets);
  });

  testWidgets('分享弹层：预览三数据位 + 复制文字版 toast', (tester) async {
    final h = await repo.saveHabit(
      Habit(name: '喝水', unit: '杯', goal: 8, startDate: key(3)),
    );
    await repo.upsertEntry(h.id, day: key(0), checked: true, value: 8);
    final snap = HabitShareSnapshot(
      title: '本周打卡报告',
      rangeTxt: '09-14 ~ 09-20 · 共 1 个习惯',
      cnt: 1,
      rate: 33,
      rec: 1,
      pos: const [HabitShareRow(icon: 'water', name: '喝水', cnt: 1, right: '8 杯')],
      neg: const [],
      habitCntLines: const ['喝水：1 次'],
    );
    captured = ProviderContainer(
      overrides: [habitRepositoryProvider.overrideWithValue(repo)],
    );
    await useSurface(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: captured!,
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showHabitShareSheet(ctx, snap),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('open'));
    await settle5(tester);
    expect(find.text('分享长图'), findsOneWidget);
    expect(find.text('LifeHarness · 习惯报告'), findsOneWidget);
    expect(find.text('达成率'), findsOneWidget);
    expect(find.text('数据仅存本机 · 导出不含账号信息'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('btn-hsh-copy')));
    expect(await pollText(tester, '文字版已复制'), true);
    expect(snap.copyText.contains('打卡 1 次 · 达成率 33% · 数值记录 1 条'), true);
  });
}
