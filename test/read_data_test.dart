import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/domain/book_quote.dart';
import 'package:lifeharness/features/read/domain/book_session.dart';

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
}
