import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/habit/data/habit_repository.dart';
import 'package:lifeharness/features/habit/domain/habit.dart';
import 'package:lifeharness/features/habit/domain/habit_calc.dart';
import 'package:lifeharness/features/habit/domain/habit_dict.dart';
import 'package:lifeharness/features/habit/presentation/habit_providers.dart';
import 'package:lifeharness/features/habit/presentation/habits_page.dart';

/// 习惯批2 · 触发/宽限/字典管理页面用例。独立文件防 isolate 污染。
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
    String? unit,
    double? goal,
    int negLimit = 0,
  }) => repo.saveHabit(
    Habit(
      name: name,
      type: type,
      unit: unit,
      goal: goal,
      negLimit: negLimit,
      startDate: key(30),
    ),
  );

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

  Future<void> refresh(WidgetTester tester) async {
    captured!.read(habitTickProvider.notifier).state++;
    await settle5(tester);
  }

  testWidgets('宽限钮「宽限 N」：用一张落 frozen 并 toast 剩余', (tester) async {
    final h = await seed(name: '跑步');
    for (final back in [3, 2, 1]) {
      await repo.upsertEntry(h.id, day: key(back), checked: true);
    }
    await useSurface(tester);
    await pump(tester);
    expect(find.text('宽限 1'), findsOneWidget);
    await tester.tap(find.text('宽限 1'));
    expect(
      await pollText(tester, '已用一张宽限 · 连续 4 天未中断 · 本月剩 0 张'),
      isTrue,
    );
    await clearToasts(tester);
    final e = (await repo.entriesOf(h.id))[key(0)]!;
    expect(e.frozen, isTrue);
    expect(e.checked, isFalse);
    expect(e.note, '使用宽限卡');
    // 余额 0 → 钮消失（原型条件 !ok && gl>0 && streak>0）
    await refresh(tester);
    expect(find.text('宽限 1'), findsNothing);
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('负向卡「记一次触发」开弹层并落库', (tester) async {
    final h = await seed(name: '奶茶', type: Habit.kNeg, negLimit: 2);
    await useSurface(tester);
    await pump(tester);
    await tester.tap(find.text('记一次触发'));
    await settle5(tester);
    expect(find.text('记一次触发 · 奶茶'), findsOneWidget);
    expect(find.text('熬夜'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('htrig-reason-熬夜')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('btn-htrig-save')));
    expect(
      await pollText(tester, '已记录 · 这次 1 次 · 本周 1/2 · 还剩 1 次额度'),
      isTrue,
    );
    final slips = await repo.slipsOf(h.id);
    expect(slips, hasLength(1));
    expect(slips.first.reasons, ['熬夜']);
    // 触发日 checked=0 一等数据保留（§5-10）
    final e = (await repo.entriesOf(h.id))[key(0)]!;
    expect(e.checked, isFalse);
    expect(h.isNeg, isTrue);
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('字典管理弹层：改名 toast · 引用守卫 · 迁移并删除', (tester) async {
    final h = await seed(name: '晨跑');
    final withCat = (await repo.habitById(h.id))!.copyWith(cat: '健康');
    await repo.saveHabit(withCat);
    await useSurface(tester);
    await pump(tester);
    // 主页无直接管理入口 → 打开新建表单再点分类「＋ 自定义」
    await tester.tap(find.text('＋ 新建习惯'));
    await settle5(tester);
    await tester.tap(find.text('＋ 自定义').first);
    await settle5(tester);
    expect(find.text('习惯分类'), findsOneWidget);
    expect(find.text('改名即时同步到已归属习惯 · 删除前需先安置其下习惯'), findsOneWidget);
    // 改名：健康 → 体能（unfocus 触发就地提交；点遮罩会把弹层关掉）
    await tester.enterText(find.byKey(const ValueKey('hm-row-健康')), '体能');
    FocusManager.instance.primaryFocus?.unfocus();
    await settle5(tester);
    expect(await pollText(tester, '「健康」已改为「体能」· 同步 1 处'), isTrue);
    await clearToasts(tester);
    expect((await repo.habitById(h.id))!.cat, '体能');
    // 删除被引用项 → 守卫：弹迁移面板
    await tester.tap(find.byKey(const ValueKey('btn-hm-del-体能')));
    expect(await pollText(tester, '「体能」仍被使用 · 选择去向后可删除'), isTrue);
    await clearToasts(tester);
    expect(find.text('迁移并删除'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hm-mv-sel')));
    await settle5(tester);
    await tester.tap(find.text('学习').last);
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('btn-hm-merge')));
    expect(
      await pollText(tester, '已把 1 处迁到「学习」· 并删除「体能」'),
      isTrue,
    );
    expect((await repo.habitById(h.id))!.cat, '学习');
    final cats = (await repo.dictOf(HabitDict.kCat)).map((c) => c.name);
    expect(cats, isNot(contains('体能')));
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });
}
