import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../domain/book.dart';
import '../domain/book_quote.dart';
import '../domain/book_session.dart';
import '../domain/shelf_query.dart';

/// 阅读模块仓储（M1批3 · 计划 §2.1 三表）。
///
/// 口径：
/// - 软删除统一 deleted_at（记录管理回收站语义与其他模块一致）；
/// - 累计时长/次数不存列，由 book_sessions 聚合派生（sessionAggByBook）；
/// - last_read_at 为聚合索引列：开始/读完/摘录/会话结束四类活动取最大（§3.2）；
/// - 全局单活计时会话：开始新会话自动结束旧会话（L4 流水批2 接）。
class ReadRepository {
  ReadRepository(this.db);

  final Database db;
  final Random _rng = Random();

  String _newId() =>
      'b${DateTime.now().microsecondsSinceEpoch}${_rng.nextInt(9999)}';

  // ---- 书 ----

  Future<List<Book>> allBooks() async =>
      (await db.query(DbSchema.tBooks)).map(Book.fromRow).toList();

  Future<Book?> bookById(String id) async {
    final rows =
        await db.query(DbSchema.tBooks, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Book.fromRow(rows.first);
  }

  /// 新增（read.newPos 插入位置由 UI 层列表序承载，库内不排序）。
  Future<Book> addBook(Book b) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final row = b.toRow();
    if (b.id.isEmpty) row['id'] = _newId();
    row['created_at'] = b.createdAt == 0 ? now : b.createdAt;
    row['updated_at'] = now;
    row['last_read_at'] ??= now;
    final book = Book.fromRow(row);
    await db.insert(DbSchema.tBooks, book.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    return book;
  }

  Future<void> updateBook(Book b) => db.update(DbSchema.tBooks,
      b.copyWith(updatedAt: DateTime.now().millisecondsSinceEpoch).toRow(),
      where: 'id = ?', whereArgs: [b.id]);

  /// 分区流转落库值（单本与批量共用同一语义）。
  static Map<String, Object?> _stateValues(Book b, String state, int now) {
    final v = <String, Object?>{
      'state': state,
      'updated_at': now,
      'last_read_at': maxActivity(b, extra: now),
    };
    if (state == Book.kStateDone) {
      if (b.pages > 0) v['read_pages'] = b.pages;
      if (b.totalLoc != null) v['read_loc'] = b.totalLoc;
      v['ended_at'] = now;
      v['started_at'] = b.startedAt ?? now;
    } else if (state == Book.kStateReading) {
      v['started_at'] = b.startedAt ?? now;
      v['ended_at'] = null;
    }
    return v;
  }

  /// 分区流转（角标循环与批量移分区共用）：
  /// 已读 → 进度补满 + ended_at；在读 → started_at 补当下、清 ended_at。
  Future<void> setBookState(String id, String state) async {
    final b = await bookById(id);
    if (b == null) return;
    await db.update(DbSchema.tBooks,
        _stateValues(b, state, DateTime.now().millisecondsSinceEpoch),
        where: 'id = ?', whereArgs: [id]);
  }

  /// 批量移分区（管理底部条·与单本同语义：移入已读补满进度与读完时间）。
  Future<void> bulkSetState(List<String> ids, String state) =>
      db.transaction((txn) async {
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final id in ids) {
          final rows = await txn
              .query(DbSchema.tBooks, where: 'id = ?', whereArgs: [id], limit: 1);
          if (rows.isEmpty) continue;
          await txn.update(DbSchema.tBooks,
              _stateValues(Book.fromRow(rows.first), state, now),
              where: 'id = ?', whereArgs: [id]);
        }
      });

  /// 批量加标签（并集去重，保原序）。
  Future<void> bulkAddTags(List<String> ids, List<String> tags) =>
      db.transaction((txn) async {
        for (final id in ids) {
          final rows = await txn
              .query(DbSchema.tBooks, columns: ['tags'], where: 'id = ?', whereArgs: [id]);
          if (rows.isEmpty) continue;
          final cur = splitTags(rows.first['tags'] as String?);
          final merged = [...cur, ...tags.where((t) => !cur.contains(t))];
          await txn.update(
              DbSchema.tBooks,
              {'tags': merged.join(','), 'updated_at': DateTime.now().millisecondsSinceEpoch},
              where: 'id = ?',
              whereArgs: [id]);
        }
      });

  /// 软删除（会话与摘录保留归档，一致性自检口径 §2.4）。
  Future<void> softDeleteBooks(List<String> ids) => db.update(
      DbSchema.tBooks,
      {'deleted_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id IN (${ids.map((_) => '?').join(',')})',
      whereArgs: ids);

  /// 活动类写入后统一刷 last_read_at（摘录新增/会话结束/状态变更）。
  Future<void> touchLastRead(String bookId, [int? ms]) async {
    final b = await bookById(bookId);
    if (b == null) return;
    final now = ms ?? DateTime.now().millisecondsSinceEpoch;
    if ((b.lastReadAt ?? 0) >= now) return;
    await db.update(DbSchema.tBooks,
        {'last_read_at': now, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [bookId]);
  }

  // ---- 计时会话 ----

  Future<BookSession?> runningSession() async {
    final rows = await db.query(DbSchema.tBookSessions,
        where: 'ended_at IS NULL', orderBy: 'started_at DESC', limit: 1);
    return rows.isEmpty ? null : BookSession.fromRow(rows.first);
  }

  /// 开始计时（工作台右上/详情页顶栏）：先结束任何在跑会话，再落新行；
  /// 想读/已读外的状态不变，started_at 为空时补当下。
  Future<BookSession> startSession(String bookId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final old = await runningSession();
    if (old != null) {
      await _close(old, now);
    }
    final id = await db.insert(DbSchema.tBookSessions,
        BookSession(bookId: bookId, startedAt: now).toRow());
    final b = await bookById(bookId);
    if (b != null) {
      await db.update(
          DbSchema.tBooks,
          {
            'started_at': b.startedAt ?? now,
            'last_read_at': maxActivity(b, extra: now),
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [bookId]);
    }
    return BookSession(id: id, bookId: bookId, startedAt: now);
  }

  /// 结束计时（胶囊/计时页共用）：返回已关闭会话供 L4 流水（批2）；
  /// 无在跑会话或不属于该书返回 null。
  Future<BookSession?> endSession(String bookId) async {
    final old = await runningSession();
    if (old == null || old.bookId != bookId) return null;
    return _close(old, DateTime.now().millisecondsSinceEpoch);
  }

  /// 关闭一条在跑会话：正常→落 ended_at/minutes；回拨→删行不入账（§2.4）。
  Future<BookSession?> _close(BookSession s, int nowMs) async {
    final closed = closeRunning(s, nowMs);
    if (closed == null) {
      await db.delete(DbSchema.tBookSessions, where: 'id = ?', whereArgs: [s.id]);
      await touchLastRead(s.bookId, nowMs);
      return null;
    }
    await db.update(DbSchema.tBookSessions,
        {'ended_at': closed.endedAt, 'minutes': closed.minutes},
        where: 'id = ?', whereArgs: [s.id]);
    await touchLastRead(s.bookId, nowMs);
    return closed;
  }

  Future<List<BookSession>> sessionsOf(String bookId) async => (await db.query(
        DbSchema.tBookSessions,
        where: 'book_id = ?',
        whereArgs: [bookId],
        orderBy: 'started_at ASC',
      ))
      .map(BookSession.fromRow)
      .toList();

  Future<List<BookSession>> allSessions() async =>
      (await db.query(DbSchema.tBookSessions, orderBy: 'started_at ASC'))
          .map(BookSession.fromRow)
          .toList();

  /// 手工补记一次（计时明细「＋ 补记一次」· source=manual）。
  Future<void> addManualSession(
      {required String bookId,
      required DateTime day,
      required int minutes,
      int? fromPage,
      int? toPage}) async {
    final start = day.millisecondsSinceEpoch;
    await db.insert(
        DbSchema.tBookSessions,
        BookSession(
          bookId: bookId,
          startedAt: start,
          endedAt: start + minutes * 60000,
          minutes: minutes,
          fromPage: fromPage,
          toPage: toPage,
          source: BookSession.kSrcManual,
        ).toRow());
    await touchLastRead(bookId, start + minutes * 60000);
  }

  static int dayStartMs(DateTime d) =>
      DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;

  /// 今日累计入账分钟（含在跑会话的已耗时；倍速按 speedFold 口径在 billedMinutes）。
  Future<int> minutesOnDay(DateTime day) async {
    final from = dayStartMs(day);
    final to = from + 86400000;
    final rows = await db.query(DbSchema.tBookSessions,
        where: 'ended_at >= ? AND ended_at < ?', whereArgs: [from, to]);
    var sum = rows
        .map(BookSession.fromRow)
        .where((s) => s.endedAt != null && s.endedAt! >= s.startedAt)
        .fold<int>(0, (t, s) => t + s.billedMinutes);
    final run = await runningSession();
    if (run != null && run.startedAt >= from && run.startedAt < to) {
      sum += ((DateTime.now().millisecondsSinceEpoch - run.startedAt) / 60000).floor();
    }
    return sum;
  }

  /// 本周（周一起算）累计分钟。
  Future<int> minutesThisWeek() async {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final from = dayStartMs(monday);
    final rows = await db.query(DbSchema.tBookSessions,
        where: 'ended_at >= ?', whereArgs: [from]);
    return rows
        .map(BookSession.fromRow)
        .where((s) => s.endedAt != null && s.endedAt! >= s.startedAt)
        .fold<int>(0, (t, s) => t + s.billedMinutes);
  }

  /// 有阅读入账的自然日列表（倒序·连续天数计算）。
  Future<List<DateTime>> readingDays() async => (await db
          .query(DbSchema.tBookSessions))
      .map(BookSession.fromRow)
      .where((s) => s.endedAt != null)
      .map((s) {
        final d = DateTime.fromMillisecondsSinceEpoch(s.endedAt!);
        return DateTime(d.year, d.month, d.day);
      })
      .toSet()
      .toList()
    ..sort((a, b) => b.compareTo(a));

  // ---- 摘录（批3 全量；批1 仅工作台最近摘录）----

  /// 新增摘录并刷新该书 last_read_at（摘录活动 §3.2）。
  Future<void> addQuote(BookQuote q) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final row = q.toRow();
    row['created_at'] = q.createdAt == 0 ? now : q.createdAt;
    row['updated_at'] = now;
    await db.insert(DbSchema.tBookQuotes, row);
    await touchLastRead(q.bookId, q.createdAt == 0 ? now : q.createdAt);
  }

  Future<List<BookQuote>> recentQuotes(int limit) async => (await db.query(
        DbSchema.tBookQuotes,
        where: 'deleted_at IS NULL',
        orderBy: 'created_at DESC',
        limit: limit,
      ))
      .map(BookQuote.fromRow)
      .toList();

  Future<List<BookQuote>> allQuotes() async => (await db.query(
        DbSchema.tBookQuotes,
        where: 'deleted_at IS NULL',
        orderBy: 'created_at ASC',
      ))
      .map(BookQuote.fromRow)
      .toList();

  // ---- read.* 设置（settings 表 KV · 计划 §6）----

  Future<String?> kv(String key) async {
    final rows = await db.query(DbSchema.tSettings,
        where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setKv(String key, String value) => db.insert(
      DbSchema.tSettings,
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<int> kvInt(String key, int def) async =>
      int.tryParse(await kv(key) ?? '') ?? def;
}
