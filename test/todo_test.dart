import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/shared/linkage/linkage_events.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Database db;
  late TodoDao dao;
  late EventBus bus;
  late TodoRepository repo;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    dao = TodoDao(db);
    bus = EventBus();
    repo = TodoRepository(dao, bus);
  });

  tearDown(() async {
    await db.close();
    await bus.dispose();
  });

  group('TodoDao CRUD', () {
    test('新增默认第四象限，读取一致', () async {
      final t = await dao.insert(Todo(title: '写周报'));
      final list = await dao.list();
      expect(list, hasLength(1));
      expect(list.first.id, t.id);
      expect(list.first.quadrant, Quadrant.q4); // 表默认值
      expect(list.first.done, isFalse);
    });

    test('排序：未完成在前，逾期/近到期优先，已完成沉底', () async {
      final now = DateTime.now();
      await dao.insert(Todo(title: '已完成', quadrant: Quadrant.q1, done: true));
      await dao.insert(Todo(title: '后天到期', quadrant: Quadrant.q2, dueAt: now.add(const Duration(days: 2))));
      await dao.insert(Todo(title: '明天到期', quadrant: Quadrant.q3, dueAt: now.add(const Duration(days: 1))));
      final titles = (await dao.list()).map((t) => t.title).toList();
      expect(titles, ['明天到期', '后天到期', '已完成']);
    });

    test('setQuadrant / setDone / update / remove 持久化', () async {
      final t = await dao.insert(Todo(title: '任务', quadrant: Quadrant.q3));
      await dao.setQuadrant(t.id!, Quadrant.q2);
      await dao.setDone(t.id!, true);
      expect((await dao.list()).single.quadrant, Quadrant.q2);
      expect((await dao.list()).single.done, isTrue);

      await dao.update(t.copyWith(title: '改名', note: 'n1'));
      final after = (await dao.list()).single;
      expect(after.title, '改名');
      expect(after.note, 'n1');

      await dao.remove(t.id!);
      expect(await dao.list(), isEmpty);
    });

    test('逾期计数只统计未完成且过截止日当天（自然日粒度）', () async {
      final now = DateTime.now();
      await dao.insert(Todo(title: '逾期1', dueAt: now.subtract(const Duration(days: 1))));
      await dao.insert(Todo(title: '逾期2', dueAt: now.subtract(const Duration(days: 2))));
      await dao.insert(Todo(title: '未来', dueAt: now.add(const Duration(days: 1))));
      await dao.insert(Todo(title: '逾期但已完成', dueAt: now.subtract(const Duration(days: 1)), done: true));
      // 回归（2026-09-20 用户实测）：截止日=今天，即使隐藏时刻 18:00 已过也不算逾期
      await dao.insert(Todo(title: '今天18点', dueAt: DateTime(now.year, now.month, now.day, 18)));
      expect(await dao.countOverdue(), 2);
    });

    test('Todo.overdue 按日粒度：今天到期≠逾期，昨天到期=逾期', () {
      final now = DateTime.now();
      final today18 = Todo(title: 'a', dueAt: DateTime(now.year, now.month, now.day, 18));
      final today0 = Todo(title: 'b', dueAt: DateTime(now.year, now.month, now.day));
      final yesterday = Todo(title: 'c', dueAt: DateTime(now.year, now.month, now.day - 1, 23));
      expect(today18.overdue, isFalse);
      expect(today0.overdue, isFalse);
      expect(yesterday.overdue, isTrue);
      expect(Todo(title: 'd').overdue, isFalse); // 无截止日
    });
  });

  group('TodoRepository 与事件总线', () {
    test('勾选完成发布 TaskCompletedEvent', () async {
      final events = <Object>[];
      final sub = bus.on<TaskCompletedEvent>().listen(events.add);

      final t = await repo.add(Todo(title: '联动任务', quadrant: Quadrant.q1));
      await repo.toggleDone(t);
      await Future.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(events.first, isA<TaskCompletedEvent>());
      await sub.cancel();
    });

    test('新增发布 RecordAddedEvent(source=todo)', () async {
      final events = <RecordAddedEvent>[];
      final sub = bus.on<RecordAddedEvent>().listen(events.add);
      await repo.add(Todo(title: 'x'));
      await Future.delayed(Duration.zero);
      expect(events.single.source, 'todo');
      await sub.cancel();
    });

    test('moveQuadrant 即时生效（AC <300ms 持久化）', () async {
      final t = await repo.add(Todo(title: '拖拽', quadrant: Quadrant.q4));
      final sw = Stopwatch()..start();
      await repo.moveQuadrant(t, Quadrant.q1);
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(300));
      expect((await repo.list()).single.quadrant, Quadrant.q1);
    });
  });
}
