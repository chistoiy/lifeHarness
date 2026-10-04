import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/shared/trash/trash_models.dart'
    show trashLeftDays, trashLeftTxt, trashDelStamp;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// V1.57 E 批 · 待办垃圾箱数据层（软删/恢复/彻底删除/到期清理 + 在册读数联动）。
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

  Future<Todo> seed({String title = '任务', Quadrant q = Quadrant.q1, DateTime? due, bool done = false}) =>
      repo.add(Todo(title: title, quadrant: q, dueAt: due, done: done));

  group('软删与在册读数联动（照抄 trash6check ③）', () {
    test('softRemove 后条目离开清单/象限/逾期计数，但行仍在表里', () async {
      final t = await seed(title: '救火', due: DateTime.now().subtract(const Duration(days: 3)));
      expect(await dao.list(), hasLength(1));
      expect(await dao.countOverdue(), 1);

      await repo.softRemove(t);

      expect(await dao.list(), isEmpty, reason: '垃圾箱条目不得进清单/四象限');
      expect(await dao.countOverdue(), 0, reason: '垃圾箱条目不得进今日逾期数字');
      // 未真删：整表仍在（软删只置 deleted_at）。
      final raw = await db.query(DbSchema.tTodos);
      expect(raw, hasLength(1));
      expect(raw.single['deleted_at'], isNotNull);
    });

    test('trashed() 只回垃圾箱条目，按删除时间倒序', () async {
      final a = await seed(title: '先删');
      final b = await seed(title: '后删');
      await repo.softRemove(a);
      await Future.delayed(const Duration(milliseconds: 5));
      await repo.softRemove(b);

      final trashed = await dao.trashed();
      expect(trashed.map((t) => t.title).toList(), ['后删', '先删']);
      expect(trashed.every((t) => t.trashed), isTrue);
    });

    test('恢复＝同一条目回原象限原截止（不新建、不改既有列）', () async {
      final due = DateTime(2026, 9, 20, 10);
      final t = await seed(title: '回归', q: Quadrant.q2, due: due);
      final id = t.id!;

      await repo.softRemove(t);
      expect(await dao.list(), isEmpty);

      await repo.restore(t);
      final back = await dao.list();
      expect(back, hasLength(1));
      expect(back.single.id, id, reason: '恢复必须是同一条目而非新行');
      expect(back.single.quadrant, Quadrant.q2, reason: '回原象限');
      expect(back.single.dueAt, due, reason: '回原截止');
      expect(back.single.deletedAt, isNull);
      expect(await dao.trashed(), isEmpty);
      // 表里始终只有一行。
      expect(await db.query(DbSchema.tTodos), hasLength(1));
    });

    test('purge 真删并返回条数；空列表不动表', () async {
      final a = await seed(title: 'A');
      final b = await seed(title: 'B');
      await repo.softRemove(a);
      await repo.softRemove(b);

      final n = await repo.purge([a.id!, b.id!]);
      expect(n, 2);
      expect(await db.query(DbSchema.tTodos), isEmpty);

      expect(await repo.purge(const []), 0);
    });

    test('remove() 仍是硬删（彻底删除通道不受软删影响）', () async {
      final t = await seed(title: '硬删');
      await repo.remove(t);
      expect(await db.query(DbSchema.tTodos), isEmpty);
    });
  });

  group('到期自动清理 purgeExpired', () {
    const day = 24 * 3600 * 1000;

    /// 造垃圾箱条目：[deletedAgoMs]＝删除至今的毫秒数。
    /// 边界用例带 1 分钟余量：purgeExpired 内部再取一次 DateTime.now()，
    /// 卡着整日数会因这几毫秒的推进而翻面（等号边界不可测）。
    Future<void> insertTrashed(String title, int deletedAgoMs) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert(DbSchema.tTodos, {
        'title': title,
        'created_at': now,
        'updated_at': now,
        'deleted_at': now - deletedAgoMs,
      });
    }

    test('超过保留期的被删，期内保留；未删的在册条目一律不动', () async {
      await insertTrashed('旧', 40 * day);
      await insertTrashed('新', 10 * day);
      final live = await seed(title: '在册');

      final n = await dao.purgeExpired(30);
      expect(n, 1);
      final left = await dao.trashed();
      expect(left.map((t) => t.title).toList(), ['新']);
      expect((await dao.list()).map((t) => t.title).toList(), ['在册']);
      expect((await dao.list()).single.id, live.id);
    });

    test('keepDays=0（不清理）→ 一条不删', () async {
      await insertTrashed('很久以前', 400 * day);
      expect(await dao.purgeExpired(0), 0);
      expect(await dao.trashed(), hasLength(1));
    });

    test('边界：界内 1 分钟保留 · 超界 1 分钟清理', () async {
      await insertTrashed('界内', 30 * day - 60 * 1000);
      expect(await dao.purgeExpired(30), 0, reason: '未过保留期不得清理');
      await insertTrashed('超界', 30 * day + 60 * 1000);
      expect(await dao.purgeExpired(30), 1, reason: '过保留期即清');
      expect((await dao.trashed()).map((t) => t.title).toList(), ['界内']);
    });
  });

  group('剩余天数纯函数（与档位设置同源）', () {
    final now = DateTime(2026, 9, 30, 12);

    test('档=30：刚删=剩30天，25天前删=剩5天（≤7 由 UI 标红）', () {
      expect(trashLeftDays(DateTime(2026, 9, 30, 1), 30, now), 30);
      expect(trashLeftDays(now.subtract(const Duration(days: 25)), 30, now), 5);
      expect(trashLeftTxt(now.subtract(const Duration(days: 25)), 30, now), '剩 5 天');
    });

    test('已过期＝待清理；未来（同一天多次删）不会为负', () {
      expect(trashLeftTxt(now.subtract(const Duration(days: 31)), 30, now), '待清理');
      expect(trashLeftTxt(now.add(const Duration(hours: 3)), 30, now), '剩 30 天');
    });

    test('不清理档：null + 「不清理」文案', () {
      expect(trashLeftDays(now, 0, now), isNull);
      expect(trashLeftTxt(now, 0, now), '不清理');
    });

    test('删于时间戳＝MM-dd HH:mm', () {
      expect(trashDelStamp(DateTime(2026, 9, 5, 7, 3)), '删于 09-05 07:03');
      expect(trashDelStamp(null), '删于 --');
    });
  });

  test('Todo.trashed 派生态与模型往返一致（toRow/fromRow 带 deleted_at）', () async {
    final t = await seed(title: '往返');
    await repo.softRemove(t);
    final row = (await db.query(DbSchema.tTodos, where: 'id = ?', whereArgs: [t.id!])).single;
    expect(row['deleted_at'], isNotNull);
    final parsed = Todo.fromRow(row);
    expect(parsed.trashed, isTrue);
    expect(parsed.deletedAt!.millisecondsSinceEpoch, row['deleted_at']);
    // copyWith 不清软删态（编辑不动垃圾箱归属）。
    expect(parsed.copyWith(title: '改名').deletedAt, parsed.deletedAt);
  });
}
