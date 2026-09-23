import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/widgets/grad_fab.dart';
import 'package:lifeharness/features/habit/data/habit_repository.dart';
import 'package:lifeharness/features/habit/domain/habit.dart';
import 'package:lifeharness/features/habit/domain/habit_calc.dart';
import 'package:lifeharness/features/habit/presentation/habit_providers.dart';
import 'package:lifeharness/features/habit/presentation/habits_page.dart';

/// 习惯批1b · 主页三视图/打卡记量/日期速览 widget 测试。
/// 独立文件防 isolate 污染；DB 用内存 ffi（与 read_page_test 同法）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late HabitRepository repo;

  String key(int back) => dayKey(DateTime.now().subtract(Duration(days: back)));

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = HabitRepository(db);
  });
  tearDown(() => db.close());

  Future<Habit> seed({
    String name = '晨跑',
    String type = Habit.kPos,
    String cycle = Habit.kDay,
    List<int> weekDays = const [],
    String? unit,
    double? goal,
    int negLimit = 0,
    String? groupRule,
    List<HabitSub> subs = const [],
    List<String> src = const ['手动打卡'],
    bool arch = false,
  }) async {
    var h = await repo.saveHabit(
      Habit(
        name: name,
        type: type,
        cycle: cycle,
        weekDays: weekDays,
        unit: unit,
        goal: goal,
        negLimit: negLimit,
        groupRule: groupRule,
        subs: subs,
        sourceKinds: src,
        startDate: key(30),
      ),
    );
    if (arch) await repo.setArchived(h.id, true);
    return h;
  }

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

  /// 写库后经模块 tick 驱动页面重取（同 read 测试范式）。
  Future<void> refresh(WidgetTester tester) async {
    captured!.read(habitTickProvider.notifier).state++;
    await settle5(tester);
  }

  testWidgets('空态：hero 0/0 + 自动源提示 + 尾部虚线行', (tester) async {
    await useSurface(tester);
    await pump(tester);
    expect(find.text('习惯'), findsOneWidget);
    expect(find.text('0/0'), findsOneWidget);
    expect(find.text('今日待开始'), findsOneWidget);
    expect(
      find.text('全部为手动打卡 · 可绑定自动达成源'),
      findsOneWidget,
    );
    expect(find.text('＋ 新建习惯'), findsOneWidget);
  });

  testWidgets('12 条混合样例三视图渲染无溢出', (tester) async {
    for (var i = 0; i < 8; i++) {
      await seed(name: '习惯$i', unit: i.isEven ? '分钟' : null, goal: i.isEven ? 30 : null);
    }
    await seed(name: '组卡', groupRule: Habit.kRuleAll, subs: const [
      HabitSub(name: '深蹲', unit: '个', goal: 20),
      HabitSub(name: '跑步', unit: '分钟', goal: 20),
    ]);
    await seed(name: '奶茶', type: Habit.kNeg);
    await seed(name: '周写', cycle: Habit.kWeek, weekDays: const [4]);
    await seed(name: '月整', cycle: Habit.kMonth);
    await useSurface(tester);
    await pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('习惯0'), findsOneWidget);

    // 切紧凑
    await tester.tap(find.byKey(const ValueKey('btn-habit-view')));
    await settle5(tester);
    expect(tester.takeException(), isNull);
    // 切方块
    await tester.tap(find.byKey(const ValueKey('btn-habit-view')));
    await settle5(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('本周达成'), findsWidgets);
    // 偏好落 settings KV
    expect(await repo.kv('habit.view'), 'grid');
  });

  testWidgets('无量正向：打卡→toast→流水行；再点撤销', (tester) async {
    await seed(name: '冥想');
    await useSurface(tester);
    await pump(tester);
    await tester.tap(find.text('打卡'));
    await settle5(tester);
    expect(
      await pollText(tester, '冥想 已打卡 · 连续 1 天 · 计入周报与目标（L7）'),
      isTrue,
    );
    await clearToasts(tester);
    expect(Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM habit_entries')), 1);
    await tester.tap(find.text('已打卡 · 点击撤销'));
    await settle5(tester);
    expect(await pollText(tester, '已撤销今日打卡'), isTrue);
    expect(Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM habit_entries')), 0);
  });

  testWidgets('有量正向：打卡并记量弹层保存并打卡', (tester) async {
    await seed(name: '喝水', unit: '杯', goal: 8);
    await useSurface(tester);
    await pump(tester);
    await tester.tap(find.text('打卡并记量'));
    await settle5(tester);
    expect(find.text('打卡记量 · 喝水'), findsOneWidget);
    expect(find.text('保存并打卡'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('btn-hlog-save')));
    // 注意：save 后禁 settle——SnackBar 1.6s 会被 settle 掉，用 pollText 驱动出帧
    expect(await pollText(tester, '已记录 · 喝水 今日 8 杯 · 连续 1 天'), isTrue);
    final e = (await repo.entriesOf((await repo.allHabits()).first.id))[dayKey(DateTime.now())]!;
    expect(e.value, 8);
    expect(e.checked, isTrue);
  });

  testWidgets('组卡 all 规则未达 → 说明 toast 且不落库', (tester) async {
    final h = await seed(name: '健身组', groupRule: Habit.kRuleAll, subs: const [
      HabitSub(name: '深蹲', unit: '个', goal: 20),
      HabitSub(name: '跑步', unit: '分钟', goal: 20),
    ]);
    await useSurface(tester);
    await pump(tester);
    await tester.tap(find.text('打卡并记量'));
    await settle5(tester);
    // 清零两行 → 保存不达标
    await tester.tap(find.byKey(const ValueKey('btn-hlog-clear')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('btn-hlog-save')));
    await settle5(tester);
    expect(await pollText(tester, '未达组内达成条件（0/2 项达标）· 可改为「任一即达成」'), isTrue);
    expect((await repo.entriesOf(h.id)).length, 0);
  });

  testWidgets('负向：今天没做落流水 checked=1；记一次触发弹层落 slip 并断连', (tester) async {
    final h = await seed(name: '奶茶', type: Habit.kNeg, unit: '杯', goal: 1, negLimit: 2);
    await useSurface(tester);
    await pump(tester);
    await tester.tap(find.text('今天没做'));
    await settle5(tester);
    expect(await pollText(tester, '未触发 +1 · 已连续 1 天守住'), isTrue);
    final e0 = (await repo.entriesOf(h.id))[dayKey(DateTime.now())]!;
    expect(e0.checked, isTrue);
    await clearToasts(tester);
    await tester.tap(find.text('记一次触发'));
    await settle5(tester);
    expect(find.text('记一次触发 · 奶茶'), findsOneWidget);
    expect(find.text('如实记录即可 · 只统计，不评判'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('btn-htrig-save')));
    expect(
      await pollText(tester, '已记录 · 这次 1 杯 · 本周 1/2 · 还剩 1 次额度'),
      isTrue,
    );
    // 触发日是一等数据：流水行 checked=0，slip 落表，连续归零
    final e1 = (await repo.entriesOf(h.id))[dayKey(DateTime.now())]!;
    expect(e1.checked, isFalse);
    expect(await repo.slipsOf(h.id), hasLength(1));
    expect((await repo.habitById(h.id))!.streak, 0);
  });

  testWidgets('回看模式：‹ 回退一天出提示、动作区替换', (tester) async {
    await seed(name: '晨跑');
    await useSurface(tester);
    await pump(tester);
    await tester.tap(find.byIcon(Icons.chevron_left));
    await settle5(tester);
    expect(await pollText(tester, '回看模式 · 仅今天可打卡'), isTrue);
    await clearToasts(tester);
    expect(find.text('昨天 · ${dayKey(DateTime.now().subtract(const Duration(days: 1))).substring(5)} 周${'一二三四五六日'[DateTime.now().subtract(const Duration(days: 1)).weekday - 1]}'), findsOneWidget);
    expect(find.text('回看模式 · 修改这天请用「补卡」'), findsOneWidget);
    expect(find.text('打卡'), findsNothing);
  });

  testWidgets('日期速览弹层打开/月历/关闭', (tester) async {
    await seed(name: '晨跑');
    await useSurface(tester);
    await pump(tester);
    await tester.tap(find.textContaining('今天 · '));
    await settle5(tester);
    final now = DateTime.now();
    expect(find.text('${now.year} 年 ${now.month} 月'), findsOneWidget);
    expect(find.text('去补卡 / 补量'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('btn-hday-backfill')));
    await settle5(tester);
    // 速览 → 补卡弹层（预选当前日）
    expect(find.text('先选习惯 · 再点日期，可跨月补记'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('btn-hbf-save')));
    expect(await pollText(tester, '先选要补记的日期'), isTrue);
  });

  testWidgets('新建表单：无名校验 → 填写保存入列', (tester) async {
    await useSurface(tester);
    await pump(tester);
    await tester.tap(find.byType(GradFab));
    await settle5(tester);
    expect(find.text('新建习惯'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('btn-he-save')));
    await settle5(tester);
    expect(await pollText(tester, '先给习惯起个名字'), isTrue);
    await clearToasts(tester);
    await tester.enterText(find.byKey(const ValueKey('he-name')), '背单词');
    await tester.tap(find.byKey(const ValueKey('btn-he-save')));
    expect(await pollText(tester, '已保存「背单词」· 每天'), isTrue);
    await settle5(tester);
    expect(find.text('背单词'), findsOneWidget);
    final hs = await repo.allHabits();
    expect(hs.single.name, '背单词');
    expect(hs.single.startDate, dayKey(DateTime.now()));
  });

  testWidgets('筛选：负向下拉只剩负向', (tester) async {
    await seed(name: '晨跑');
    await seed(name: '奶茶', type: Habit.kNeg);
    await useSurface(tester);
    await pump(tester);
    // 打开状态筛选下拉选「负向」
    await tester.tap(find.text('全部 2'));
    await settle5(tester);
    await tester.tap(find.text('负向 1').last);
    await settle5(tester);
    expect(find.text('奶茶'), findsOneWidget);
    expect(find.text('晨跑'), findsNothing);
    expect(find.text('显示 1 / 2'), findsOneWidget);
  });

  testWidgets('hero 计数与全部达成横幅', (tester) async {
    final a = await seed(name: 'A');
    await seed(name: 'B');
    await useSurface(tester);
    await pump(tester);
    expect(find.text('0/2'), findsOneWidget);
    expect(find.text('今日待开始'), findsOneWidget);
    await repo.upsertEntry(a.id, day: dayKey(DateTime.now()));
    await refresh(tester);
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('今日进行中'), findsOneWidget);
  });
}
