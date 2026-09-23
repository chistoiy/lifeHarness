import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/habit/data/habit_repository.dart';
import 'package:lifeharness/features/habit/presentation/habit_providers.dart';
import 'package:lifeharness/features/habit/presentation/habit_settings_page.dart';

/// 习惯批5 · 打卡设置整页用例。独立文件防 isolate 污染。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late HabitRepository repo;

  setUp(() async {
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
        child: const MaterialApp(home: HabitSettingsPage()),
      ),
    );
    await settle5(tester);
  }

  testWidgets('13 项设置全量渲染 + 口径说明与恢复卡', (tester) async {
    await useSurface(tester);
    await pump(tester);
    for (final t in [
      '日均按开始跟踪日起算',
      '自动达成源直接打卡',
      '允许提醒',
      '达成率口径',
      '周起始日',
      '每月宽限次数',
      '自动达成方式',
      '晚间未打卡提醒',
      '晚间提醒时间',
      '免打扰时段',
      '已归档习惯',
      '分类管理',
      '单位管理',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('影响统计口径 · 提醒与日历分列 · 本机生效'), findsOneWidget);
    expect(find.text('恢复默认设置'), findsOneWidget);
    expect(find.text('设置仅作用于习惯模块'), findsOneWidget);
  });

  testWidgets('分段「周日」写入 habit.weekStart=1 并 toast 名称', (tester) async {
    await useSurface(tester);
    await pump(tester);
    await tester.tap(find.text('周日'));
    expect(await pollText(tester, '已更新设置 · 周起始日'), true);
    expect(await repo.kvInt('habit.weekStart', 0), 1);
    await clearToasts(tester);
  });

  testWidgets('开关「允许提醒」关闭写 KV（提醒静默口径）', (tester) async {
    await useSurface(tester);
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('hset-sw-remindAll')));
    expect(await pollText(tester, '已更新设置 · 允许提醒'), true);
    expect(await repo.kvBool('habit.remindAll', true), false);
    await clearToasts(tester);
  });

  testWidgets('恢复默认：口径/提醒/周起始日回初始，宽限与自动方式不动', (tester) async {
    await useSurface(tester);
    await pump(tester);
    await repo.setKv('habit.weekStart', '1');
    await repo.setKv('habit.spanFromStart', 'false');
    await repo.setKv('habit.grace', '3');
    await repo.setKv('habit.autoMode', '1');
    await tester.tap(find.text('恢复'));
    expect(await pollText(tester, '已更新设置 · 日均按开始跟踪日起算'), true);
    expect(await repo.kvInt('habit.weekStart', 0), 0);
    expect(await repo.kvBool('habit.spanFromStart', false), true);
    expect(await repo.kvInt('habit.grace', 1), 3); // 原型 hbSetReset 不含 grace
    expect(await repo.kvInt('habit.autoMode', 0), 1);
    await clearToasts(tester);
  });

  testWidgets('宽限档位切换即刻影响 grace KV（主页余额随 tick 重取）', (tester) async {
    await useSurface(tester);
    await pump(tester);
    await tester.tap(find.text('2 张'));
    expect(await pollText(tester, '已更新设置 · 每月宽限次数'), true);
    expect(await repo.kvInt('habit.grace', 1), 2);
    await clearToasts(tester);
  });
}
