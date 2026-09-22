import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/domain/book_quote.dart';
import 'package:lifeharness/features/read/domain/book_session.dart';
import 'package:lifeharness/features/read/domain/shelf_query.dart';
import 'package:lifeharness/features/read/domain/book_dict.dart';
import 'package:lifeharness/features/read/domain/book_progress.dart';
import 'package:lifeharness/features/read/domain/book_toc.dart';

/// M1批3 阅读 · 数据层（计划 §2.1 / §8）。独立文件防 isolate 污染（既有踩坑）。
void main() {
  sqfliteFfiInit();

  group('批3-1 · v12 建表与迁移', () {
    late Database db;

    setUp(() async {
      db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    });
    tearDown(() => db.close());

    test('1-0 migrations[11] 建三表且幂等可重跑', () async {
      for (final sql in DbSchema.migrations[11]!) {
        await db.execute(sql);
      }
      // 重跑一遍：IF NOT EXISTS 全段幂等
      for (final sql in DbSchema.migrations[11]!) {
        await db.execute(sql);
      }
      final names = (await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'book%'"))
          .map((r) => r['name'] as String)
          .toList();
      expect(names, containsAll(['books', 'book_sessions', 'book_quotes']));
      // 建库段与迁移段同文（两处共用 bookSchemaStatements）
      expect(DbSchema.bookSchemaStatements, isNotEmpty);
    });

    test('1-0b books 补列齐（tags/last_read_at/sum_*）· isbn 空串落 NULL 不撞唯一索引',
        () async {
      // 只跑 books 段（建表+全部索引，含 isbn 部分唯一索引）
      for (final sql in DbSchema.bookSchemaStatements
          .takeWhile((s) => !s.contains('book_sessions'))) {
        await db.execute(sql);
      }
      final cols = (await db.rawQuery('PRAGMA table_info(books)'))
          .map((c) => c['name'] as String)
          .toList();
      expect(
          cols,
          containsAll(['tags', 'last_read_at', 'sum_quote', 'sum_view',
              'sum_gain', 'color_idx', 'progress_way', 'fee_txn_id']));
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final t in ['A', 'B']) {
        await db.insert('books',
            Book(id: t, title: t, createdAt: now, updatedAt: now, isbn: '').toRow());
      }
      // 两本空 isbn 共存（'' → NULL），非空重复才互斥
      expect(await db.query('books'), hasLength(2));
      await db.insert('books',
          Book(id: 'C', title: 'C', createdAt: now, updatedAt: now, isbn: '978X').toRow());
      await expectLater(
          db.insert('books',
              Book(id: 'D', title: 'D', createdAt: now, updatedAt: now, isbn: '978X').toRow()),
          throwsA(isA<DatabaseException>()));
    });
  });

  group('批3-1 · 域模型', () {
    final now = DateTime(2026, 9, 22).millisecondsSinceEpoch;

    test('1-1 Book 往返：tags 逗号列 / null 列 / colorIdx 越界回绕', () {
      final b = Book(
        id: 'b1',
        title: '思考，快与慢',
        author: '丹尼尔·卡尼曼',
        state: Book.kStateReading,
        pages: 532,
        readPages: 330,
        tags: const ['心理学', '经济'],
        colorIdx: 10, // 8 色板回绕 → 2
        sumQuote: '手动金句',
        createdAt: now,
        updatedAt: now,
      );
      final r = Book.fromRow(b.toRow());
      expect(r.id, 'b1');
      expect(r.tags, ['心理学', '经济']);
      expect(r.paletteIdx, 2);
      expect(r.sumQuote, '手动金句');
      expect(r.sumView, isNull);
      expect(r.percent, 62); // 330/532 = 62.03% → 62
    });

    test('1-2 percent 派生边界：pages=0 用位置比 / 全 0 回 0 / 越界夹取', () {
      final loc = Book(
          id: 'x',
          title: 'x',
          format: Book.kFormatEbook,
          progressWay: Book.kWayPos,
          totalLoc: 2876,
          readLoc: 59,
          createdAt: now,
          updatedAt: now);
      expect(loc.percent, 2);
      final zero = Book(id: 'z', title: 'z', createdAt: now, updatedAt: now);
      expect(zero.percent, 0);
      final over = Book(
          id: 'o', title: 'o', pages: 100, readPages: 130, createdAt: now, updatedAt: now);
      expect(over.percent, 100);
    });

    test('1-3 format→默认进度方式映射（纸质=page · 电子书=pos · 有声=min）', () {
      expect(Book.defaultWayFor(Book.kFormatPaper), Book.kWayPage);
      expect(Book.defaultWayFor(Book.kFormatEbook), Book.kWayPos);
      expect(Book.defaultWayFor(Book.kFormatAudio), Book.kWayMin);
    });

    test('1-4 BookSession 往返 + running + 倍速折算 billedMinutes', () {
      final s = BookSession(
          id: 1,
          bookId: 'b1',
          startedAt: now,
          endedAt: now + 30 * 60000,
          minutes: 30,
          speed: 1.5,
          fromPage: 100,
          toPage: 118,
          source: BookSession.kSrcManual);
      final r = BookSession.fromRow(s.toRow());
      expect(r.running, isFalse);
      expect(r.billedMinutes, 45); // 30×1.5
      expect(r.toPage, 118);
      final run = BookSession(bookId: 'b1', startedAt: now);
      expect(run.running, isTrue);
      expect(run.billedMinutes, 0); // 无倍速=原样
    });

    test('1-5 BookQuote 往返：原文感想同行 · tag/tags 分列 · imagePaths JSON', () {
      final q = BookQuote(
        id: 7,
        bookId: 'b1',
        kind: BookQuote.kKindMark,
        tag: BookQuote.kTagAct,
        tags: const ['方法论', '行动'],
        body: '原文内容',
        thought: '我的想法',
        page: 120,
        imagePaths: const ['read/img/a.png', 'read/img/b.png'],
        starred: true,
        origin: '微信读书',
        dedupHash: 'h1',
        createdAt: now,
        updatedAt: now,
      );
      final r = BookQuote.fromRow(q.toRow());
      expect(r.body, '原文内容');
      expect(r.thought, '我的想法'); // 同行两字段（硬约束）
      expect(r.tag, BookQuote.kTagAct);
      expect(r.tags, ['方法论', '行动']);
      expect(r.imagePaths, ['read/img/a.png', 'read/img/b.png']);
      expect(r.starred, isTrue);
      expect(r.colorInt, 0xF59E0B);
      final bad = BookQuote.fromRow({
        'book_id': 'b1', 'kind': '划线', 'body': '', 'image_paths': '{坏JSON',
        'created_at': now, 'updated_at': now,
      });
      expect(bad.imagePaths, isEmpty); // 坏值回空不崩
    });
  });

  group('批3-2 · 仓储层与书架查询', () {
    late Database db;
    late ReadRepository repo;
    final t0 = DateTime(2026, 9, 22).millisecondsSinceEpoch;

    Book mk(String id,
            {String state = Book.kStateWant,
            int? last,
            String? title,
            List<String> tags = const [],
            int pages = 0,
            int readPages = 0}) =>
        Book(
          id: id,
          title: title ?? '书$id',
          author: '作者$id',
          state: state,
          tags: tags,
          pages: pages,
          readPages: readPages,
          lastReadAt: last ?? t0,
          createdAt: t0,
          updatedAt: t0,
        );

    setUp(() async {
      db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      repo = ReadRepository(db);
    });
    tearDown(() => db.close());

    test('2-1 addBook：空 id 自动生成 · 默认想读/纸质/page · last_read_at 兜底', () async {
      final b = await repo.addBook(Book(
          title: '新书', createdAt: 0, updatedAt: 0, tags: const ['小说']));
      expect(b.id, isNotEmpty);
      expect(b.state, Book.kStateWant);
      expect(b.format, Book.kFormatPaper);
      expect(b.lastReadAt, isNotNull);
      final r = (await repo.allBooks()).single;
      expect(r.title, '新书');
      expect(r.tags, ['小说']);
    });

    test('2-2 setBookState 四态流转：已读补满进度与 ended · 回在读清 ended 补 started', () async {
      await repo.addBook(mk('x1',
          state: Book.kStateReading, pages: 320, readPages: 99, title: '原子习惯'));
      await repo.setBookState('x1', Book.kStateDone);
      var b = await repo.bookById('x1');
      expect(b!.state, Book.kStateDone);
      expect(b.readPages, 320); // 标记读完 → 进度补满
      expect(b.endedAt, isNotNull);
      await repo.setBookState('x1', Book.kStateDropped);
      b = await repo.bookById('x1');
      expect(b!.state, Book.kStateDropped); // 弃读不动进度
      expect(b.readPages, 320);
    });

    test('2-3 ShelfQuery：软删排除 · recent 倒序 · kw/分区/标签维度过滤 · 计数', () async {
      await repo.addBook(mk('a', state: Book.kStateReading, last: t0 + 3000, tags: const ['经济']));
      await repo.addBook(mk('b', state: Book.kStateReading, last: t0 + 1000));
      await repo.addBook(mk('c', state: Book.kStateDone, last: t0 + 2000, tags: const ['经济']));
      final all = await repo.allBooks();
      final q = ShelfQuery(sort: 'recent');
      expect(q.apply(all).map((e) => e.id), ['a', 'c', 'b']);
      expect(ShelfQuery(state: Book.kStateReading).apply(all).length, 2);
      expect(ShelfQuery(kw: '书b').apply(all).map((e) => e.id), ['b']);
      final tagQ = ShelfQuery(dim: 'tag', dimVal: '经济');
      expect(tagQ.apply(all).map((e) => e.id), ['a', 'c']);
      expect(ShelfQuery.countsByState(all),
          {'在读': 2, '想读': 0, '已读': 1, '弃读': 0});
      expect(ShelfQuery.dimValues('tag', all), ['经济']);
      //  prog/pages 排序
      await repo.addBook(mk('d', pages: 900, readPages: 450, last: t0 - 9999));
      expect(ShelfQuery(sort: 'prog').apply(await repo.allBooks()).first.id, 'd');
      expect(ShelfQuery(sort: 'pages').apply(await repo.allBooks()).first.id, 'd');
      // 软删后全链路排除
      await repo.softDeleteBooks(['d']);
      expect(ShelfQuery().apply(await repo.allBooks()).map((e) => e.id), isNot(contains('d')));
    });

    test('2-4 批量操作：移分区 · 加标签并集去重', () async {
      await repo.addBook(mk('a', tags: const ['小说']));
      await repo.addBook(mk('b', tags: const ['小说', '历史']));
      await repo.bulkSetState(['a', 'b'], Book.kStateWant);
      await repo.bulkAddTags(['a', 'b'], const ['小说', '新标签']);
      final all = await repo.allBooks();
      expect(all.every((e) => e.state == Book.kStateWant), isTrue);
      expect(all.firstWhere((e) => e.id == 'a').tags, ['小说', '新标签']);
      expect(all.firstWhere((e) => e.id == 'b').tags, ['小说', '历史', '新标签']);
    });

    test('2-5 计时起停：单活会话 · 换书自动结旧 · endSession 书守卫', () async {
      await repo.addBook(mk('r1', state: Book.kStateReading));
      await repo.addBook(mk('r2', state: Book.kStateReading));
      await repo.startSession('r1');
      expect((await repo.runningSession())!.bookId, 'r1');
      await repo.startSession('r2'); // 换书 → r1 自动结束
      var rs = await repo.runningSession();
      expect(rs!.bookId, 'r2');
      final r1s = await repo.sessionsOf('r1');
      expect(r1s.single.endedAt, isNotNull);
      expect(await repo.endSession('r1'), isNull); // 不是它在跑 → 守卫
      final closed = await repo.endSession('r2');
      expect(closed, isNotNull);
      expect(closed!.minutes, 1); // 不足 1 分钟按 1 入账
      expect(await repo.runningSession(), isNull);
      expect((await repo.bookById('r2'))!.lastReadAt! >= closed.endedAt!, isTrue);
    });

    test('2-6 时钟回拨：closeRunning 返 null · endSession 删行不入账', () async {
      await repo.addBook(mk('w', state: Book.kStateReading));
      final s = await repo.startSession('w');
      // 模拟回拨：把 started_at 推到未来
      await db.update(DbSchema.tBookSessions,
          {'started_at': DateTime.now().millisecondsSinceEpoch + 3600000},
          where: 'id = ?', whereArgs: [s.id]);
      expect(await repo.endSession('w'), isNull);
      expect(await repo.allSessions(), isEmpty); // 行已删
      expect(closeRunning(BookSession(bookId: 'w', startedAt: 2000), 1000), isNull);
    });

    test('2-7 聚合：minutesOnDay/ThisWeek · sessionAggByBook 排除回拨行 · 补记入账', () async {
      await repo.addBook(mk('g1', state: Book.kStateReading));
      await repo.addBook(mk('g2', state: Book.kStateReading));
      final today = DateTime.now();
      await repo.addManualSession(
          bookId: 'g1', day: DateTime(today.year, today.month, today.day, 8), minutes: 25);
      await repo.addManualSession(
          bookId: 'g2', day: DateTime(today.year, today.month, today.day, 9), minutes: 10);
      expect(await repo.minutesOnDay(today), 35);
      expect(await repo.minutesThisWeek(), greaterThanOrEqualTo(35));
      // 手工塞一条回拨脏行：不入聚合
      await db.insert(DbSchema.tBookSessions,
          BookSession(bookId: 'g1', startedAt: 9000, endedAt: 8000, minutes: 500).toRow());
      final agg = sessionAggByBook(await repo.allSessions());
      expect(agg['g1']!.minutes, 25);
      expect(agg['g1']!.times, 1);
      expect(agg['g2']!.minutes, 10);
      final days = await repo.readingDays();
      expect(days.first, DateTime(today.year, today.month, today.day));
    });

    test('2-8 摘录聚合：quoteCountByBook 排除软删 · recentQuotes 倒序', () async {
      final q = BookQuote(
          bookId: 'b1',
          kind: BookQuote.kKindMark,
          body: '原文',
          createdAt: t0,
          updatedAt: t0);
      await db.insert(DbSchema.tBookQuotes, q.toRow());
      await db.insert(DbSchema.tBookQuotes,
          {...q.toRow(), 'body': '第二条', 'created_at': t0 + 100, 'deleted_at': t0 + 200});
      final qs = await repo.allQuotes();
      expect(qs, hasLength(1)); // 软删被 where 排除
      expect(quoteCountByBook([...qs, BookQuote(
            bookId: 'b1',
            kind: BookQuote.kKindMark,
            body: 'x',
            createdAt: t0,
            updatedAt: t0,
            deletedAt: t0)]), {'b1': 1});
      expect((await repo.recentQuotes(5)).first.body, '原文');
    });
  });

  group('批3-2 · v13 目录字典与计时明细', () {
    late Database db;
    late ReadRepository repo;
    final t0 = DateTime(2026, 9, 22).millisecondsSinceEpoch;

    setUp(() async {
      db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      repo = ReadRepository(db);
    });
    tearDown(() => db.close());

    test('3-0 migrations[12] 幂等 · 建 book_toc_nodes/book_dict · 阅读分类唯一',
        () async {
      for (var i = 0; i < 2; i++) {
        for (final sql in DbSchema.migrations[12]!) {
          await db.execute(sql);
        }
      }
      final names = (await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('book_toc_nodes','book_dict')"))
          .length;
      expect(names, 2);
      final rows = await db.query('categories', where: 'name = ?', whereArgs: ['阅读']);
      expect(rows, hasLength(1)); // 全量段与迁移段同 INSERT OR IGNORE
      expect(rows.single['id'], DbSchema.catReadingId);
    });

    test('3-1 parseTocText：第X部/Part/罗马数字=部分 · 缩进与编号行=小节', () {
      final parts = parseTocText('第一部 混沌\n'
          '  1.1 开端的失序\n'
          '    第二章的暗线\n'
          '第二篇 秩序\n'
          'Part III 尾声\n'
          'IV\n'
          '未分章的独白\n'
          '1.2 小节编号也归当前部分\n');
      expect(parts.map((p) => p.title).toList(),
          ['第一部 混沌', '第二篇 秩序', 'Part III 尾声', 'IV']);
      expect(parts[0].sections, ['1.1 开端的失序', '第二章的暗线']);
      expect(parts[3].sections, ['未分章的独白', '1.2 小节编号也归当前部分']);
    });

    test('3-2 parseTocText：小节先于部分 → 未命名部分承载不丢行', () {
      final parts = parseTocText('前言\n第一章 起风\n');
      expect(parts, hasLength(1));
      expect(parts.single.title, '');
      expect(parts.single.sections, ['前言', '第一章 起风']);
    });

    test('3-3 progressPatch 边界：pages=0 不折页 · pos>tot 夹 100% · pct 反写 loc', () {
      final b0 = Book(id: 'x', title: 'x', createdAt: t0, updatedAt: t0);
      expect(progressPatch(b0, Book.kWayPage, 50)['read_pages'], 50); // 无总页也收数值
      final b = Book(
          id: 'y',
          title: 'y',
          pages: 100,
          totalLoc: 2000,
          progressWay: Book.kWayPos,
          createdAt: t0,
          updatedAt: t0);
      final pos = progressPatch(b, Book.kWayPos, 9999);
      expect(pos['read_loc'], 2000); // 钳到总位置
      expect(pos['read_pages'], 100);
      final pct = progressPatch(b, Book.kWayPct, 37.5);
      expect(pct['read_pages'], 38);
      expect(pct['read_loc'], 750);
      final chap = progressPatch(b, Book.kWayChap, null,
          chapterTitle: '第三章', chapterStartPage: 60);
      expect(chap['chapter'], '第三章');
      expect(chap['read_pages'], 60);
      // 位置↔页折算边界
      expect(pageFromLoc(b, 1000), 50);
      expect(locFromPage(b, 50), 1000);
      expect(pageFromLoc(b0, 100), isNull);
      expect(locFromPage(b0, 100), isNull);
    });

    test('3-4 saveProgress：想读自动转在读 · started_at 补当下 · 刷 last_read_at', () async {
      final b = await repo.addBook(
          Book(title: '进度书', pages: 100, createdAt: t0, updatedAt: t0));
      await repo.saveProgress(b.id, Book.kWayPage, 42);
      final nb = await repo.bookById(b.id);
      expect(nb!.readPages, 42);
      expect(nb.state, Book.kStateReading);
      expect(nb.startedAt, isNotNull);
      expect(nb.percent, 42);
    });

    test('3-5 结束计时入 L4：分类=阅读 cat_id=22 note=《书名》 txn_id 回填', () async {
      final b = await repo.addBook(Book(
          title: '入账书',
          pages: 100,
          state: Book.kStateReading,
          createdAt: t0,
          updatedAt: t0));
      final s = await repo.startSession(b.id);
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.update('book_sessions', {'started_at': now - 3600000},
          where: 'id = ?', whereArgs: [s.id]);
      final closed = await repo.endSession(b.id);
      expect(closed, isNotNull);
      final rows = await db.query('time_blocks',
          where: 'cat_id = ?', whereArgs: [DbSchema.catReadingId]);
      expect(rows, hasLength(1));
      expect(rows.single['category'], '阅读');
      expect(rows.single['note'], '《入账书》');
      final sess = (await repo.sessionsOf(b.id)).single;
      expect(sess.txnId, rows.single['id']);
    });

    test('3-6 计时明细改时长：同一条流水差量更新不新建 · 聚合回算', () async {
      final b = await repo.addBook(Book(
          title: '改时长',
          pages: 100,
          state: Book.kStateReading,
          createdAt: t0,
          updatedAt: t0));
      final s = await repo.startSession(b.id);
      await repo.endSession(b.id);
      final before = await db.query('time_blocks',
          where: 'cat_id = ?', whereArgs: [DbSchema.catReadingId]);
      final txnId = before.single['id'] as int;
      await repo.editSession(s.id!, minutes: 999, toPage: 40);
      final after = await db.query('time_blocks',
          where: 'cat_id = ?', whereArgs: [DbSchema.catReadingId]);
      expect(after, hasLength(1)); // 复用不新建
      expect(after.single['id'], txnId);
      expect((await repo.sessionsOf(b.id)).single.minutes, 999);
      final agg = sessionAggByBook(await repo.allSessions());
      expect(agg[b.id]!.minutes, 999);
      final nb = await repo.bookById(b.id);
      expect(nb!.readPages, 40); // 最新 to_page 回写
    });

    test('3-7 删除计时：同流水删行 · 补记走 manual 且入账', () async {
      final b = await repo.addBook(Book(title: '删流水', createdAt: t0, updatedAt: t0));
      await repo.addManualSession(
          bookId: b.id, day: DateTime(2026, 9, 20), minutes: 25, toPage: 9);
      final manual = (await repo.sessionsOf(b.id)).single;
      expect(manual.source, BookSession.kSrcManual);
      expect(
          await db.query('time_blocks',
              where: 'cat_id = ?', whereArgs: [DbSchema.catReadingId]),
          hasLength(1));
      await repo.deleteSession(manual.id!);
      expect(await repo.sessionsOf(b.id), isEmpty);
      expect(
          await db.query('time_blocks',
              where: 'cat_id = ?', whereArgs: [DbSchema.catReadingId]),
          isEmpty);
    });

    test('3-8 字典自动登记：addBook 落作者与出版社 · 改名联动书目与摘录标签', () async {
      final b = await repo.addBook(Book(
          title: '字典书',
          author: '张三',
          publisher: '某某社',
          tags: ['经济'],
          createdAt: t0,
          updatedAt: t0));
      final authors = await repo.dictOf(DictEntry.kAuthor);
      expect(authors.map((e) => e.name), ['张三']);
      expect((await repo.dictOf(DictEntry.kPublisher)).map((e) => e.name),
          contains('某某社'));
      await repo.dictRename(
          authors.firstWhere((e) => e.name == '张三'), '李四');
      expect((await repo.bookById(b.id))!.author, '李四');
      // 标签改名联动 books.tags 与摘录 tags
      await repo.dictAdd(DictEntry.kTag, '经济');
      await repo.addQuote(BookQuote(
          bookId: b.id,
          kind: BookQuote.kKindMark,
          body: '原文',
          tags: ['经济'],
          createdAt: t0,
          updatedAt: t0));
      final tags = await repo.dictOf(DictEntry.kTag);
      await repo.dictRename(tags.firstWhere((e) => e.name == '经济'), '经济学');
      expect((await repo.bookById(b.id))!.tags, ['经济学']);
      expect((await repo.allQuotes()).single.tags, ['经济学']);
      final cnt = await repo.dictRefCount(
          DictEntry(kind: DictEntry.kAuthor, name: '李四'));
      expect(cnt, 1);
    });

    test('3-9 目录 CRUD：替换/删节回落未分章/改名调序/空部分治理', () async {
      final b = await repo.addBook(Book(title: '目录书', createdAt: t0, updatedAt: t0));
      await repo.replaceToc(b.id, parseTocText('第一部\n  甲\n  乙\n第二部\n  丙'));
      var nodes = await repo.tocOf(b.id);
      expect(nodes.where((n) => n.isPart).length, 2);
      expect(nodes.where((n) => !n.isPart).length, 3);
      // 摘录挂在「甲」，删小节 → chapter 置空不删摘录
      await repo.addQuote(BookQuote(
          bookId: b.id,
          kind: BookQuote.kKindMark,
          body: 'x',
          chapter: '甲',
          createdAt: t0,
          updatedAt: t0));
      final jia = nodes.firstWhere((n) => n.title == '甲');
      await repo.deleteToc(jia.id!);
      nodes = await repo.tocOf(b.id);
      expect(nodes.any((n) => n.title == '甲'), isFalse);
      expect((await repo.allQuotes()).single.chapter, isNull);
      // 改名 + 树序
      final yi = nodes.firstWhere((n) => n.title == '乙');
      await repo.renameToc(yi.id!, '乙改');
      nodes = await repo.tocOf(b.id);
      expect(tocTree(nodes).first.sections.single.title, '乙改');
      // 加部分不治理时为空 → tocPrune 清掉
      await repo.addTocPart(b.id);
      expect((await repo.tocOf(b.id)).where((n) => n.isPart).length, 3);
      await repo.tocPrune(b.id);
      expect((await repo.tocOf(b.id)).where((n) => n.isPart).length, 2);
      // 只读渲染不出现无小节部分
      expect(tocTree(await repo.tocOf(b.id), hideEmptyParts: true).length, 2);
    });

    test('3-10 moveToc 同级调序 · deleteToc 部分连子节', () async {
      final b = await repo.addBook(Book(title: '调序书', createdAt: t0, updatedAt: t0));
      await repo.replaceToc(b.id, parseTocText('第一部\n  A\n  B\n  C\n'));
      var nodes = await repo.tocOf(b.id);
      final c = nodes.firstWhere((n) => n.title == 'C');
      await repo.moveToc(c.id!, -1); // C 上移一位到 B 前
      nodes = await repo.tocOf(b.id);
      final part = nodes.firstWhere((n) => n.isPart);
      expect(
          tocTree(nodes).first.sections.map((s) => s.title).toList(),
          ['A', 'C', 'B']);
      await repo.deleteToc(part.id!); // 删部分连小节
      expect(await repo.tocOf(b.id), isEmpty);
      expect((await repo.allQuotes()), isEmpty);
    });
  });
}
