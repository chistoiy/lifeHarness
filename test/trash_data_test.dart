import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/features/habit/data/habit_repository.dart';
import 'package:lifeharness/features/habit/domain/habit.dart';
import 'package:lifeharness/features/journal/data/note_dao.dart';
import 'package:lifeharness/features/journal/domain/note.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/domain/book_list.dart';
import 'package:lifeharness/features/read/domain/book_quote.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/shared/trash/trash_models.dart';
import 'package:lifeharness/shared/trash/trash_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// V1.60 全局回收站 · 数据层（六类全纳 / 恢复回原位 / 彻底删除连带 / 孤行判定 / 到期清理扩表）。
///
/// 规格来源＝需求清单 §四「全局回收站（V1.60 新增）」＋工单 §5 实现批工作面。
void main() {
  sqfliteFfiInit();

  late Database db;
  late TodoDao todoDao;
  late EventBus bus;
  late TodoRepository todoRepo;
  late NoteDao notes;
  late HabitRepository habits;
  late ReadRepository read;
  late TrashRepository trash;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    todoDao = TodoDao(db);
    bus = EventBus();
    todoRepo = TodoRepository(todoDao, bus);
    notes = NoteDao(db);
    habits = HabitRepository(db);
    read = ReadRepository(db);
    trash = TrashRepository(db);
  });

  tearDown(() async {
    await db.close();
    await bus.dispose();
  });

  // ---- 六类各造一条「已删除」内容 ----

  Future<TrashItem> seedOne(TrashKind kind) async {
    switch (kind) {
      case TrashKind.todo:
        final t = await todoRepo.add(Todo(
            title: '写周报',
            quadrant: Quadrant.q2,
            dueAt: DateTime.now().add(const Duration(days: 1)),
            tag: '工作'));
        await todoRepo.softRemove(t);
      case TrashKind.note:
        final n = await notes.save(Note(
            title: 'Drift 选型',
            content: '正文',
            folder: '技术',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now()));
        await notes.softDelete(n.id!);
      case TrashKind.habit:
        final h = await habits.saveHabit(Habit(
            name: '跑步', cycle: Habit.kDay, startDate: '2026-01-01'));
        await habits.deleteHabit(h.id);
      case TrashKind.book:
        final b = await read.addBook(Book(
            title: '思考，快与慢',
            pages: 100,
            readPages: 41,
            createdAt: 1,
            updatedAt: 1));
        await read.addQuote(BookQuote(
            bookId: b.id,
            kind: BookQuote.kKindMark,
            body: '系统一与系统二',
            createdAt: 1,
            updatedAt: 1));
        await read.softDeleteBooks([b.id]);
      case TrashKind.quote:
        final b = await read.addBook(
            Book(title: '孤立之书', createdAt: 1, updatedAt: 1));
        final q = await read.addQuote(BookQuote(
            bookId: b.id,
            kind: BookQuote.kKindMark,
            body: '这句要一起没',
            createdAt: 1,
            updatedAt: 1));
        await read.softDeleteQuote(q!);
        await read.purgeBook(b.id); // 父书彻底删除 → 该行成孤行
      case TrashKind.list:
        final b = await read.addBook(
            Book(title: '成员甲', createdAt: 1, updatedAt: 1));
        await read.addList(
            BookList(name: '主题单', createdAt: 1, updatedAt: 1),
            bookIds: [b.id]);
        final l = (await read.allLists()).first;
        await read.softDeleteList(l.id!);
    }
    final all = await trash.items();
    return all.firstWhere((e) => e.kind == kind);
  }

  group('六类全纳与行读数（需求 §四 全局回收站）', () {
    test('六类各一条全部进屏，按删除时间倒序', () async {
      for (final k in TrashKind.values) {
        await seedOne(k);
        // 让 deleted_at 有先后，避免同毫秒乱序
        await Future.delayed(const Duration(milliseconds: 3));
      }
      final items = await trash.items();
      expect(items.map((e) => e.kind).toSet(), TrashKind.values.toSet());
      expect(items, hasLength(TrashKind.values.length));
      for (final e in items) {
        expect(e.deletedAt, isNotNull, reason: '${e.kind.name} 行没有「删于」时间');
      }
      final stamps = items.map((e) => e.deletedAt!).toList();
      final sorted = [...stamps]..sort((a, b) => b.compareTo(a));
      expect(stamps, sorted, reason: '最新删除的排最前');
    });

    test('待办行带截止与标签，书籍行带连带读数，书单行带成员数', () async {
      final todo = await seedOne(TrashKind.todo);
      expect(todo.subs, containsAllInOrder(['⏰ 明天', '#工作']));
      expect(todo.title, '写周报');

      final book = await seedOne(TrashKind.book);
      expect(book.subs.single, contains('含划线·笔记 1 条'));
      expect(book.subs.single, contains('进度 41%'));
      expect(book.cascadeQuotes, 1);

      final list = await seedOne(TrashKind.list);
      expect(list.subs.single, '成员 1 本');
    });

    test('划线行：所属书名在，父书没了＝孤行并给原因', () async {
      final q = await seedOne(TrashKind.quote);
      expect(q.orphan, isTrue);
      expect(q.orphanHint, '所属书已彻底删除');

      // 父书只是进回收站（行还在）＝同样判孤，恢复出去就是幽灵摘录。
      final b = await read.addBook(Book(title: '在架的书', createdAt: 1, updatedAt: 1));
      final id = await read.addQuote(BookQuote(
          bookId: b.id,
          kind: BookQuote.kKindMark,
          body: '等书回来',
          createdAt: 1,
          updatedAt: 1));
      await read.softDeleteQuote(id!);
      var row = (await trash.items()).firstWhere((e) => e.rawId == id);
      expect(row.orphan, isFalse, reason: '父书在架＝可单独恢复');
      expect(row.subs, ['所属《在架的书》']);

      await read.softDeleteBooks([b.id]);
      row = (await trash.items()).firstWhere((e) => e.rawId == id);
      expect(row.orphan, isTrue);
      expect(row.orphanHint, '所属书还在回收站');
    });
  });

  group('恢复＝回原模块原位（不新建条目）', () {
    test('待办回原象限原截止，逾期计数不受影响', () async {
      final t = await todoRepo.add(Todo(
          title: '回原象限', quadrant: Quadrant.q2, tag: '家',
          dueAt: DateTime.now().add(const Duration(days: 2))));
      await todoRepo.softRemove(t);
      final row = (await trash.items()).single;
      await todoRepo.restore(row.src! as Todo);
      final back = (await todoDao.list()).single;
      expect(back.id, t.id, reason: '同一条记录，不是新建');
      expect(back.quadrant, Quadrant.q2);
      expect(back.tag, '家');
      expect(await trash.items(), isEmpty);
    });

    test('笔记回原文件夹；习惯回习惯列表；书单成员一行不少', () async {
      final n = await notes.save(Note(
          title: '回原夹',
          content: 'x',
          folder: '技术',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await notes.softDelete(n.id!);
      await notes.restore(n.id!);
      expect((await notes.list(folder: '技术')).map((e) => e.title), ['回原夹']);

      final h = await habits.saveHabit(
          Habit(name: '早睡', cycle: Habit.kDay, startDate: '2026-01-01'));
      await habits.deleteHabit(h.id);
      expect(await habits.trashedHabits(), hasLength(1));
      await habits.restoreHabit(h.id);
      expect((await habits.allHabits()).map((e) => e.name), ['早睡']);

      final b = await read.addBook(Book(title: '甲', createdAt: 1, updatedAt: 1));
      await read.addList(BookList(name: '保持者', createdAt: 1, updatedAt: 1),
          bookIds: [b.id]);
      final l = (await read.allLists()).single;
      await read.softDeleteList(l.id!);
      expect(await read.allLists(), isEmpty);
      final trashedList = (await trash.items()).single;
      expect(trashedList.subs, ['成员 1 本'], reason: '软删期成员行必须留着');
      await read.restoreList(l.id!);
      final back = (await read.allLists()).single;
      expect(await read.listMembers(back), hasLength(1));
    });

    test('书回书架后其垃圾箱划线仍判孤（父在架才放行）', () async {
      final b = await read.addBook(Book(title: '回来的书', createdAt: 1, updatedAt: 1));
      final q = await read.addQuote(BookQuote(
          bookId: b.id,
          kind: BookQuote.kKindMark,
          body: '句子',
          createdAt: 1,
          updatedAt: 1));
      await read.softDeleteQuote(q!);
      await read.softDeleteBooks([b.id]);
      expect((await trash.items()).where((e) => e.kind == TrashKind.quote).single.orphan,
          isTrue);
      await read.restoreBook(b.id);
      final row = (await trash.items())
          .firstWhere((e) => e.kind == TrashKind.quote);
      expect(row.orphan, isFalse);
      await read.restoreQuote(row.rawId as int);
      expect((await read.quotesOf(b.id)).map((e) => e.body), ['句子']);
    });
  });

  group('彻底删除（真 DELETE · 书籍连带）', () {
    test('删书＝清在库摘录/计时/目录/进度键，垃圾箱里的该书划线留作孤行',
        () async {
      final b = await read.addBook(Book(title: '被删的书', createdAt: 1, updatedAt: 1));
      final live = await read.addQuote(BookQuote(
          bookId: b.id,
          kind: BookQuote.kKindMark,
          body: '在库的一句',
          createdAt: 1,
          updatedAt: 1));
      final gone = await read.addQuote(BookQuote(
          bookId: b.id,
          kind: BookQuote.kKindMark,
          body: '已删的一句',
          createdAt: 1,
          updatedAt: 1));
      await read.softDeleteQuote(gone!);
      await read.softDeleteBooks([b.id]);
      await db.insert(DbSchema.tBookTocNodes, {
        'book_id': b.id,
        'level': 1,
        'idx': 0,
        'title': '第一章',
      });
      await db.insert(DbSchema.tBookSessions, {
        'book_id': b.id,
        'started_at': 1,
        'ended_at': 2,
        'minutes': 30,
        'source': 'timer',
      });

      final n = await read.purgeBook(b.id);
      expect(n, 1, reason: '连带清除一条在库划线');
      expect(await read.bookById(b.id), isNull);
      expect(await read.quoteById(live!), isNull);
      expect(await read.quotesOf(b.id), isEmpty);
      expect((await db.query(DbSchema.tBookSessions)), isEmpty);
      expect((await db.query(DbSchema.tBookReviews)), isEmpty);
      final orphan = (await trash.items())
          .firstWhere((e) => e.kind == TrashKind.quote);
      expect(orphan.rawId, gone);
      expect(orphan.orphan, isTrue);
      expect(orphan.orphanHint, '所属书已彻底删除');
      // 孤行仍可被彻底删除清走
      await read.purgeQuote(orphan.rawId as int);
      expect(await trash.items(), isEmpty);
    });

    test('删书单连带成员行；删习惯保留按日流水（计划 §2.1 口径）', () async {
      final b = await read.addBook(Book(title: '甲', createdAt: 1, updatedAt: 1));
      await read.addList(BookList(name: '要删的单', createdAt: 1, updatedAt: 1),
          bookIds: [b.id]);
      final l = (await read.allLists()).single;
      await read.softDeleteList(l.id!);
      await read.purgeList(l.id!);
      expect(await db.query(DbSchema.tBookLists), isEmpty);
      expect(await db.query(DbSchema.tBookListItems), isEmpty);
      expect(await read.bookById(b.id), isNotNull, reason: '书本身不动');

      final h = await habits.saveHabit(
          Habit(name: '喝水', cycle: Habit.kDay, startDate: '2026-01-01'));
      await habits.upsertEntry(h.id, day: '2026-01-02', checked: true);
      await habits.deleteHabit(h.id);
      await habits.purgeHabit(h.id);
      expect(await db.query(DbSchema.tHabits), isEmpty);
      expect(await db.query(DbSchema.tHabitSubs), isEmpty);
      expect(await db.query(DbSchema.tHabitEntries), hasLength(1),
          reason: '历史流水属于纪录墙，不随定义一起没');
    });

    test('删笔记连带快照；删待办即真删行', () async {
      final n = await notes.save(Note(
          title: '带快照',
          content: 'v1',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await notes.snapshot(n.id!, '旧版');
      await notes.softDelete(n.id!);
      await notes.purge(n.id!);
      expect(await db.query(DbSchema.tNotes), isEmpty);
      expect(await db.query(DbSchema.tNoteSnapshots), isEmpty);

      final t = await todoRepo.add(Todo(title: '真删', quadrant: Quadrant.q1));
      await todoRepo.softRemove(t);
      expect(await todoRepo.purge([t.id!]), 1);
      expect(await db.query(DbSchema.tTodos), isEmpty);
    });
  });

  group('冷启动到期清理扩到六表（需求：保留期沿用全局档位）', () {
    Future<void> stampDeletedAt(String table, Object? id, int daysAgo) =>
        db.update(
          table,
          {
            'deleted_at': DateTime.now()
                .subtract(Duration(days: daysAgo))
                .millisecondsSinceEpoch
          },
          where: 'id = ?',
          whereArgs: [id],
        );

    Future<void> seedSixExpired() async {
      final t = await todoRepo.add(Todo(title: '待办过期', quadrant: Quadrant.q1));
      await todoRepo.softRemove(t);
      await stampDeletedAt(DbSchema.tTodos, t.id, 31);

      final n = await notes.save(Note(
          title: '笔记过期',
          content: 'x',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await notes.softDelete(n.id!);
      await stampDeletedAt(DbSchema.tNotes, n.id, 31);

      final h = await habits.saveHabit(
          Habit(name: '习惯过期', cycle: Habit.kDay, startDate: '2026-01-01'));
      await habits.deleteHabit(h.id);
      await stampDeletedAt(DbSchema.tHabits, h.id, 31);

      final b = await read.addBook(Book(title: '书面包过期', createdAt: 1, updatedAt: 1));
      final q = await read.addQuote(BookQuote(
          bookId: b.id,
          kind: BookQuote.kKindMark,
          body: '划线过期',
          createdAt: 1,
          updatedAt: 1));
      await read.softDeleteQuote(q!);
      await read.softDeleteBooks([b.id]);
      await stampDeletedAt(DbSchema.tBooks, b.id, 31);
      await stampDeletedAt(DbSchema.tBookQuotes, q, 31);

      await read.addList(BookList(name: '书单过期', createdAt: 1, updatedAt: 1));
      final live = (await read.allLists()).single;
      await read.softDeleteList(live.id!);
      await stampDeletedAt(DbSchema.tBookLists, live.id, 31);
    }

    test('过保留期的六表软删行全部清走，未过期的一律不动', () async {
      await seedSixExpired();
      final keep = await todoRepo.add(Todo(title: '未过期', quadrant: Quadrant.q1));
      await todoRepo.softRemove(keep);

      final per = await trash.purgeExpiredByTable(30);
      expect(per['待办'], 1);
      expect(per['笔记'], 1);
      expect(per['习惯'], 1);
      expect(per['书籍'], 1, reason: '过期书行本身');
      expect(per['划线书摘'], 1, reason: '该书那条过期划线按自己的档位清');
      expect(per['书单'], 1);
      expect((await trash.items()).map((e) => e.title), ['未过期']);
      expect(await db.query(DbSchema.tBookLists), isEmpty);
      expect(await db.query(DbSchema.tHabitEntries), isEmpty);
    });

    test('档位＝不清理时一行都不删', () async {
      await seedSixExpired();
      expect(await trash.purgeExpiredByTable(0), isEmpty);
      expect(await trash.items(), hasLength(6));
    });

    test('书到期清理后其垃圾箱划线不会被同轮连带清走（孤行归孤行）', () async {
      final b = await read.addBook(Book(title: '过期书', createdAt: 1, updatedAt: 1));
      final q = await read.addQuote(BookQuote(
          bookId: b.id,
          kind: BookQuote.kKindMark,
          body: '还年轻的划线',
          createdAt: 1,
          updatedAt: 1));
      await read.softDeleteQuote(q!);
      await read.softDeleteBooks([b.id]);
      await stampDeletedAt(DbSchema.tBooks, b.id, 31); // 只书过期，划线仍 30 天内
      final per = await trash.purgeExpiredByTable(30);
      expect(per['书籍'], 1);
      expect(per['划线书摘'], 0, reason: '未过期孤行留下');
      final row = (await trash.items()).single;
      expect(row.kind, TrashKind.quote);
      expect(row.orphanHint, '所属书已彻底删除');
    });
  });

  group('期限读数（原型 ttLeftTxt）', () {
    test('剩 N 天 / 待清理 / 不清理 三态与标红判定', () {
      final now = DateTime(2026, 10, 4, 12);
      expect(trashLeftDays(now.subtract(const Duration(days: 25)), 30, now), 5);
      expect(trashLeftTxt(now.subtract(const Duration(days: 25)), 30, now),
          '剩 5 天');
      expect(trashLeftTxt(now.subtract(const Duration(days: 31)), 30, now),
          '待清理');
      expect(trashLeftTxt(now, 0, now), '不清理');
      expect(trashDelStamp(DateTime(2026, 9, 5, 7, 3)), '删于 09-05 07:03');
    });
  });
}
