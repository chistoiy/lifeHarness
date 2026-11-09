import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/settings/settings_repository.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo.dart';
import 'package:lifeharness/features/todo/domain/todo_insights.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_page.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// T9 防重入用例专用：把逐条改象限钉慢，才测得到「写入进行中」那一帧
/// （真 IO 在 FakeAsync 下的完成时机不可预测，慢仓才稳）。
class _SlowEscalateRepo extends TodoRepository {
  _SlowEscalateRepo(super.dao, super.bus);

  @override
  Future<void> moveQuadrant(Todo t, Quadrant q) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return super.moveQuadrant(t, q);
  }
}

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 20, 12);

  Todo t(
          {int id = 1,
          Quadrant q = Quadrant.q4,
          bool done = false,
          bool dropped = false,
          DateTime? dueAt,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      Todo(
          id: id,
          title: 'T$id',
          quadrant: q,
          done: done,
          dropped: dropped,
          dueAt: dueAt,
          createdAt: createdAt ?? now.subtract(const Duration(days: 10)),
          updatedAt: updatedAt ?? createdAt ?? now);

  group('q2EmptyDays 失衡判定', () {
    test('Q2 仍有未完成任务 → 不提醒（null）', () {
      expect(q2EmptyDays([t(q: Quadrant.q2)], now), isNull);
    });

    test('待办整体为空 → 不判断（null）', () {
      expect(q2EmptyDays([], now), isNull);
    });

    test('Q2 最近完成于 5 天前 → 空置 5 天', () {
      final list = [
        t(id: 1, q: Quadrant.q1),
        t(id: 2, q: Quadrant.q2, done: true, updatedAt: now.subtract(const Duration(days: 5))),
      ];
      expect(q2EmptyDays(list, now), 5);
    });

    test('从未完成过 Q2 → 自最早待办创建起算', () {
      final list = [
        t(id: 1, q: Quadrant.q3, createdAt: now.subtract(const Duration(days: 4))),
        t(id: 2, q: Quadrant.q4, createdAt: now.subtract(const Duration(days: 9))),
      ];
      expect(q2EmptyDays(list, now), 9);
    });

    test('Q2 任务已放弃不算活跃：空置天数从最早创建起算（放弃≠完成）', () {
      final list = [
        t(id: 1, q: Quadrant.q2, dropped: true,
            createdAt: now.subtract(const Duration(days: 3)),
            updatedAt: now.subtract(const Duration(days: 3))),
      ];
      expect(q2EmptyDays(list, now), 3);
    });
  });

  group('escalateSuggestions 临期升紧急候选', () {
    test('已逾期 / 24h 内的 Q2 入选；25h 外与 Q4 不选', () {
      final list = [
        t(id: 1, q: Quadrant.q2, dueAt: now.subtract(const Duration(hours: 2))), // 逾期
        t(id: 2, q: Quadrant.q2, dueAt: now.add(const Duration(hours: 23))), // 临期
        t(id: 3, q: Quadrant.q2, dueAt: now.add(const Duration(hours: 25))), // 尚早
        t(id: 4, q: Quadrant.q4, dueAt: now), // 不重要不升
        t(id: 5, q: Quadrant.q2, done: true, dueAt: now), // 已完成
        t(id: 6, q: Quadrant.q2, dueAt: null), // 无截止
      ];
      expect(escalateSuggestions(list, now).map((e) => e.id), [1, 2]);
    });
  });

  group('energyCaption 精力占比分级', () {
    test('≥60 状态不错 / 40~59 还能更聚焦 / <40 紧急事偏多（原型三档逐字）', () {
      expect(energyCaption(62), '，状态不错');
      expect(energyCaption(60), '，状态不错');
      expect(energyCaption(50), '，还能更聚焦');
      expect(energyCaption(40), '，还能更聚焦');
      expect(energyCaption(30), '，紧急事偏多');
    });
  });

  group('智能建议卡接线（TodoPage 组件级）', () {
    late Database db;
    late TodoRepository repo;
    late EventBus bus;
    late SharedPreferences prefs;

    setUp(() async {
      db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      bus = EventBus();
      repo = TodoRepository(TodoDao(db), bus);
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    tearDown(() async {
      await db.close();
      await bus.dispose();
    });

    Widget app({TodoRepository? data}) => ProviderScope(
          overrides: [
            todoRepositoryProvider.overrideWithValue(data ?? repo),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: const MaterialApp(home: TodoPage()),
        );

    testWidgets('四象限视图底部失衡提醒卡：≥3 天空置出现，去规划打开 Q2 预置新建',
        (tester) async {
      await repo.add(Todo(
          title: '旧任务',
          quadrant: Quadrant.q1,
          createdAt: DateTime.now().subtract(const Duration(days: 5)),
          updatedAt: DateTime.now().subtract(const Duration(days: 5))));
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('btn-view-toggle')));
      await tester.pumpAndSettle();
      expect(find.textContaining('失衡提醒：'), findsOneWidget);
      expect(find.textContaining('天空置'), findsOneWidget);

      await tester.tap(find.text('去规划'));
      await tester.pumpAndSettle();
      expect(find.text('新建待办'), findsOneWidget);
      // 预置两问答案：重要=是 ✓、紧急=否 → 落点即「重要不紧急」
      expect(find.text('是 ✓'), findsOneWidget);
      expect(find.text('否'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
    });

    testWidgets('Q2 有空置不足阈值任务时不显示提醒卡', (tester) async {
      await repo.add(Todo(
          title: '刚建的任务', quadrant: Quadrant.q1,
          createdAt: DateTime.now(), updatedAt: DateTime.now()));
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('btn-view-toggle')));
      await tester.pumpAndSettle();
      // 空置 <3 天（今日创建）→ 不提醒
      expect(find.textContaining('失衡提醒：'), findsNothing);
    });

    testWidgets('清单视图：临期 Q2 一键升紧急并持久化', (tester) async {
      final s = await repo.add(Todo(
          title: '写规划', quadrant: Quadrant.q2,
          dueAt: DateTime.now().add(const Duration(hours: 3))));
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('escalate-card')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('escalate-go')));
      await tester.pumpAndSettle();

      final saved = await repo.list();
      expect(saved.first.quadrant, Quadrant.q1);
      expect(find.text('已升入「重要且紧急」，先救最要紧的火'), findsOneWidget);
      expect(s.id, isNotNull);
      expect(find.byKey(const ValueKey('escalate-card')), findsNothing); // 升完即消失
    });

    testWidgets('T9 批三：一键升紧急写入期间禁用＋连点只执行一次', (tester) async {
      final slow = _SlowEscalateRepo(TodoDao(db), bus);
      await slow.add(Todo(
          title: '写规划', quadrant: Quadrant.q2,
          dueAt: DateTime.now().add(const Duration(hours: 3))));
      await tester.pumpWidget(app(data: slow));
      await tester.pumpAndSettle();
      await drainLogTimer(tester); // 先落定建页时留下的节流行
      int logged() => AppLog.lines
          .where((l) => l.text.contains('待办一键升紧急'))
          .length;
      final before = logged();

      await tester.tap(find.byKey(const ValueKey('escalate-go')));
      await tester.pump(const Duration(milliseconds: 100)); // 第一条还在 await
      expect(
          tester
              .widget<TextButton>(
                  find.byKey(const ValueKey('escalate-go')))
              .onPressed,
          isNull,
          reason: '批量改写进行中，按钮必须处于禁用帧（否则连点=重复写库）');
      await tester.tap(find.byKey(const ValueKey('escalate-go'))); // 点不动
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await drainLogTimer(tester);
      expect(logged() - before, 1, reason: '连点两次只许执行一次批量改写');
      expect((await slow.list()).single.quadrant, Quadrant.q1);
    });

    testWidgets('设置关闭升级建议后卡片不再出现', (tester) async {
      final settings = SettingsRepository(prefs).load();
      await SettingsRepository(prefs)
          .save(settings.copyWith(notify: settings.notify.copyWith(overdueEscalate: false)));
      await repo.add(Todo(
          title: '写规划', quadrant: Quadrant.q2,
          dueAt: DateTime.now().add(const Duration(hours: 3))));
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('escalate-card')), findsNothing);
    });
  });
}
