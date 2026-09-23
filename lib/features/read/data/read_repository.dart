import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../domain/book.dart';
import '../domain/book_dict.dart';
import '../domain/book_list.dart';
import '../domain/book_progress.dart';
import '../domain/book_quote.dart';
import '../domain/book_session.dart';
import '../domain/book_toc.dart';
import '../domain/shelf_query.dart';
import 'read_import.dart';

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
    final rows = await db.query(
      DbSchema.tBooks,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Book.fromRow(rows.first);
  }

  /// 新增：read.newPos=末尾 时以 last_read_at 沉底实现插入位置（§6）。
  Future<Book> addBook(Book b) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final row = b.toRow();
    if (b.id.isEmpty) row['id'] = _newId();
    row['created_at'] = b.createdAt == 0 ? now : b.createdAt;
    row['updated_at'] = now;
    // read.newPos（§6 显示与排序）：末尾＝新书面包沉到最近阅读表下方。
    row['last_read_at'] ??=
        ((await kv('read.newPos')) == '末尾' && b.lastReadAt == null)
            ? (row['created_at'] as int) - 1
            : now;
    final book = Book.fromRow(row);
    await db.insert(
      DbSchema.tBooks,
      book.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _registerDictFor(book);
    await _syncFeeTxn(book);
    return book;
  }

  Future<void> updateBook(Book b) async {
    await db.update(
      DbSchema.tBooks,
      b.copyWith(updatedAt: DateTime.now().millisecondsSinceEpoch).toRow(),
      where: 'id = ?',
      whereArgs: [b.id],
    );
    await _registerDictFor(b);
    await _syncFeeTxn(b);
  }

  /// 作者/出版社自动登记字典（计划 §4 批2；INSERT OR IGNORE 依唯一索引去重）。
  Future<void> _registerDictFor(Book b) async {
    for (final (kind, name) in [
      (DictEntry.kAuthor, b.author),
      (DictEntry.kPublisher, b.publisher ?? ''),
    ]) {
      if (name.trim().isEmpty) continue;
      final exists = await db.query(
        DbSchema.tBookDict,
        where: 'kind = ? AND name = ?',
        whereArgs: [kind, name.trim()],
        limit: 1,
      );
      if (exists.isEmpty) {
        final maxSort =
            Sqflite.firstIntValue(
              await db.rawQuery(
                'SELECT COALESCE(MAX(sort),0) FROM ${DbSchema.tBookDict} WHERE kind = ?',
                [kind],
              ),
            ) ??
            0;
        await db.insert(
          DbSchema.tBookDict,
          DictEntry(kind: kind, name: name.trim(), sort: maxSort + 1).toRow(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
  }

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
    await db.update(
      DbSchema.tBooks,
      _stateValues(b, state, DateTime.now().millisecondsSinceEpoch),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 批量移分区（管理底部条·与单本同语义：移入已读补满进度与读完时间）。
  Future<void> bulkSetState(List<String> ids, String state) =>
      db.transaction((txn) async {
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final id in ids) {
          final rows = await txn.query(
            DbSchema.tBooks,
            where: 'id = ?',
            whereArgs: [id],
            limit: 1,
          );
          if (rows.isEmpty) continue;
          await txn.update(
            DbSchema.tBooks,
            _stateValues(Book.fromRow(rows.first), state, now),
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      });

  /// 批量加标签（并集去重，保原序）。
  Future<void> bulkAddTags(List<String> ids, List<String> tags) =>
      db.transaction((txn) async {
        for (final id in ids) {
          final rows = await txn.query(
            DbSchema.tBooks,
            columns: ['tags'],
            where: 'id = ?',
            whereArgs: [id],
          );
          if (rows.isEmpty) continue;
          final cur = splitTags(rows.first['tags'] as String?);
          final merged = [...cur, ...tags.where((t) => !cur.contains(t))];
          await txn.update(
            DbSchema.tBooks,
            {
              'tags': merged.join(','),
              'updated_at': DateTime.now().millisecondsSinceEpoch,
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      });

  /// 软删除（会话与摘录保留归档，一致性自检口径 §2.4）。
  Future<void> softDeleteBooks(List<String> ids) => db.update(
    DbSchema.tBooks,
    {
      'deleted_at': DateTime.now().millisecondsSinceEpoch,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    },
    where: 'id IN (${ids.map((_) => '?').join(',')})',
    whereArgs: ids,
  );

  /// 活动类写入后统一刷 last_read_at（摘录新增/会话结束/状态变更）。
  Future<void> touchLastRead(String bookId, [int? ms]) async {
    final b = await bookById(bookId);
    if (b == null) return;
    final now = ms ?? DateTime.now().millisecondsSinceEpoch;
    if ((b.lastReadAt ?? 0) >= now) return;
    await db.update(
      DbSchema.tBooks,
      {
        'last_read_at': now,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  // ---- 计时会话 ----

  Future<BookSession?> runningSession() async {
    final rows = await db.query(
      DbSchema.tBookSessions,
      where: 'ended_at IS NULL',
      orderBy: 'started_at DESC',
      limit: 1,
    );
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
    final id = await db.insert(
      DbSchema.tBookSessions,
      BookSession(bookId: bookId, startedAt: now).toRow(),
    );
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
        whereArgs: [bookId],
      );
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

  /// 关闭一条在跑会话：正常→落 ended_at/minutes + L4 流水；回拨→删行不入账（§2.4）。
  Future<BookSession?> _close(BookSession s, int nowMs) async {
    final closed = closeRunning(s, nowMs);
    if (closed == null) {
      await db.delete(
        DbSchema.tBookSessions,
        where: 'id = ?',
        whereArgs: [s.id],
      );
      await touchLastRead(s.bookId, nowMs);
      return null;
    }
    await db.update(
      DbSchema.tBookSessions,
      {'ended_at': closed.endedAt, 'minutes': closed.minutes},
      where: 'id = ?',
      whereArgs: [s.id],
    );
    await touchLastRead(s.bookId, nowMs);
    await _syncTxn(closed);
    return closed;
  }

  Future<List<BookSession>> sessionsOf(String bookId) async => (await db.query(
    DbSchema.tBookSessions,
    where: 'book_id = ?',
    whereArgs: [bookId],
    orderBy: 'started_at ASC',
  )).map(BookSession.fromRow).toList();

  Future<List<BookSession>> allSessions() async => (await db.query(
    DbSchema.tBookSessions,
    orderBy: 'started_at ASC',
  )).map(BookSession.fromRow).toList();

  /// 手工补记一次（计时明细「＋ 补记一次」· source=manual · 计划 §7 补记标 origin）。
  Future<int> addManualSession({
    required String bookId,
    required DateTime day,
    required int minutes,
    int? fromPage,
    int? toPage,
  }) async {
    final start = day.millisecondsSinceEpoch;
    final id = await db.insert(
      DbSchema.tBookSessions,
      BookSession(
        bookId: bookId,
        startedAt: start,
        endedAt: start + minutes * 60000,
        minutes: minutes,
        fromPage: fromPage,
        toPage: toPage,
        source: BookSession.kSrcManual,
      ).toRow(),
    );
    await touchLastRead(bookId, start + minutes * 60000);
    await _syncTxn(
      BookSession(
        id: id,
        bookId: bookId,
        startedAt: start,
        endedAt: start + minutes * 60000,
        minutes: minutes,
        fromPage: fromPage,
        toPage: toPage,
        source: BookSession.kSrcManual,
      ),
    );
    await syncBookAgg(bookId);
    return id;
  }

  /// 计时明细行内修改（§3.3 累计时长可下钻可改）：
  /// 改起始时间/时长直接重排 ended_at；页码随行更新；
  /// 差量回写同一条 L4 流水（txn_id 复用不新建）并重算 books 聚合。
  Future<void> editSession(
    int id, {
    int? startedAtMs,
    int? minutes,
    int? fromPage,
    int? toPage,
  }) async {
    final rows = await db.query(
      DbSchema.tBookSessions,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final s = BookSession.fromRow(rows.first);
    final start = startedAtMs ?? s.startedAt;
    final mins = minutes ?? s.minutes;
    final values = <String, Object?>{
      'started_at': start,
      'minutes': mins,
      'ended_at': start + mins * 60000,
      'from_page': ?fromPage,
      'to_page': ?toPage,
    };
    await db.update(
      DbSchema.tBookSessions,
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
    await _syncTxn(
      BookSession(
        id: id,
        bookId: s.bookId,
        startedAt: start,
        endedAt: start + mins * 60000,
        minutes: mins,
        speed: s.speed,
        fromPage: fromPage ?? s.fromPage,
        toPage: toPage ?? s.toPage,
        source: s.source,
        txnId: s.txnId,
      ),
    );
    await syncBookAgg(s.bookId);
  }

  /// 删除一次计时记录：同事务删 L4 流水（计划 §7），并重算聚合。
  Future<void> deleteSession(int id) async {
    final rows = await db.query(
      DbSchema.tBookSessions,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final s = BookSession.fromRow(rows.first);
    if (s.txnId != null) {
      await db.delete(
        DbSchema.tTimeBlocks,
        where: 'id = ?',
        whereArgs: [s.txnId],
      );
    }
    await db.delete(DbSchema.tBookSessions, where: 'id = ?', whereArgs: [id]);
    await syncBookAgg(s.bookId);
  }

  /// L4 时间账本差量写入（计划 §7）：分类=阅读，note=《书名》；
  /// 跨天时块记在结束日、起点钳 0；不足 1 分钟不入账。
  Future<void> _syncTxn(BookSession s) async {
    if (s.id == null || s.endedAt == null || s.minutes <= 0) return;
    final b = await bookById(s.bookId);
    final start = DateTime.fromMillisecondsSinceEpoch(s.startedAt);
    final end = DateTime.fromMillisecondsSinceEpoch(s.endedAt!);
    final day = DateTime(end.year, end.month, end.day);
    final endMin = end.hour * 60 + end.minute;
    final sameDay =
        start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    final startMin = sameDay
        ? (start.hour * 60 + start.minute).clamp(0, 1439)
        : 0;
    final row = {
      'day': dayStartMs(day),
      'start_min': startMin,
      'end_min': endMin.clamp(startMin + 1, 1440),
      'category': '阅读',
      'note': '《${b?.title ?? ''}》',
      'source': 'mark',
      'cat_id': DbSchema.catReadingId,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
    if (s.txnId == null) {
      final txnId = await db.insert(DbSchema.tTimeBlocks, {
        ...row,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await db.update(
        DbSchema.tBookSessions,
        {'txn_id': txnId},
        where: 'id = ?',
        whereArgs: [s.id],
      );
    } else {
      await db.update(
        DbSchema.tTimeBlocks,
        row,
        where: 'id = ?',
        whereArgs: [s.txnId],
      );
    }
  }

  /// 会话集合变化后重算 books 聚合（§3.3 bsSessSync 口径）：
  /// started_at=最早会话起点；last_read_at=最晚入账结束；
  /// 最新一次 to_page 回写 read_pages（已读不回落）。
  Future<void> syncBookAgg(String bookId) async {
    final b = await bookById(bookId);
    if (b == null) return;
    final closed = (await sessionsOf(
      bookId,
    )).where((s) => s.endedAt != null && s.endedAt! >= s.startedAt).toList();
    if (closed.isEmpty) return;
    final minStart = closed
        .map((s) => s.startedAt)
        .reduce((a, c) => a < c ? a : c);
    final latest = closed.fold<BookSession>(
      closed.first,
      (a, c) => (c.endedAt ?? 0) >= (a.endedAt ?? 0) ? c : a,
    );
    final values = <String, Object?>{
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
    if (b.startedAt == null || minStart < b.startedAt!) {
      values['started_at'] = minStart;
    }
    if ((b.lastReadAt ?? 0) < (latest.endedAt ?? 0)) {
      values['last_read_at'] = latest.endedAt;
    }
    if (latest.toPage != null &&
        b.state != Book.kStateDone &&
        b.readPages != latest.toPage) {
      values['read_pages'] = b.pages > 0
          ? latest.toPage!.clamp(0, b.pages)
          : latest.toPage;
    }
    if (values.length > 1) {
      await db.update(
        DbSchema.tBooks,
        values,
        where: 'id = ?',
        whereArgs: [bookId],
      );
    }
  }

  static int dayStartMs(DateTime d) =>
      DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;

  /// 今日累计入账分钟（含在跑会话的已耗时；倍速按 speedFold 口径在 billedMinutes）。
  Future<int> minutesOnDay(DateTime day) async {
    final from = dayStartMs(day);
    final to = from + 86400000;
    final rows = await db.query(
      DbSchema.tBookSessions,
      where: 'ended_at >= ? AND ended_at < ?',
      whereArgs: [from, to],
    );
    var sum = rows
        .map(BookSession.fromRow)
        .where((s) => s.endedAt != null && s.endedAt! >= s.startedAt)
        .fold<int>(0, (t, s) => t + s.billedMinutes);
    final run = await runningSession();
    if (run != null && run.startedAt >= from && run.startedAt < to) {
      sum += ((DateTime.now().millisecondsSinceEpoch - run.startedAt) / 60000)
          .floor();
    }
    return sum;
  }

  /// 本周（周一起算）累计分钟。
  Future<int> minutesThisWeek() async {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final from = dayStartMs(monday);
    final rows = await db.query(
      DbSchema.tBookSessions,
      where: 'ended_at >= ?',
      whereArgs: [from],
    );
    return rows
        .map(BookSession.fromRow)
        .where((s) => s.endedAt != null && s.endedAt! >= s.startedAt)
        .fold<int>(0, (t, s) => t + s.billedMinutes);
  }

  /// 有阅读入账的自然日列表（倒序·连续天数计算）。
  Future<List<DateTime>> readingDays() async =>
      (await db.query(DbSchema.tBookSessions))
          .map(BookSession.fromRow)
          .where((s) => s.endedAt != null)
          .map((s) {
            final d = DateTime.fromMillisecondsSinceEpoch(s.endedAt!);
            return DateTime(d.year, d.month, d.day);
          })
          .toSet()
          .toList()
        ..sort((a, b) => b.compareTo(a));

  // ---- 摘录（批3 全量：查重入账 / 标签字典 / 复习档位 / L5 分流）----

  static const int _dayMs = 24 * 60 * 60 * 1000;

  /// 艾宾浩斯复习间隔（天 · 计划批3「1/3/7 天」）：入账次日 1 天，其后 3/7，
  /// 走完 7 天档 next 置空＝已掌握。
  static const List<int> reviewGapsMs = [1, 3, 7];

  /// 新增摘录并刷新该书 last_read_at（摘录活动 §3.2）；标签自动登记字典；
  /// 同步行写入复习档位（stage 0 · 次日到期）。
  /// dedup：正文归一化哈希撞已有摘录 → 返回 null 不入账（调用方提示「已存在」）。
  Future<int?> addQuote(BookQuote q) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final created = q.createdAt == 0 ? now : q.createdAt;
    final key = (q.dedupHash?.isNotEmpty ?? false)
        ? q.dedupHash!
        : (q.body.trim().isEmpty
              ? ''
              : quoteDedupKey(q.bookId, q.chapter, q.page, q.body));
    if (key.isNotEmpty) {
      final dup = await db.query(
        DbSchema.tBookQuotes,
        where: 'dedup_hash = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (dup.isNotEmpty) return null;
    }
    final row = q.copyWith(dedupHash: key.isEmpty ? null : key).toRow();
    row['created_at'] = created;
    row['updated_at'] = now;
    final id = await db.insert(DbSchema.tBookQuotes, row);
    for (final t in q.tags) {
      await dictAdd(DictEntry.kTag, t);
    }
    await db.insert(
      DbSchema.tBookReviews,
      {'quote_id': id, 'stage': 0, 'next_at': created + _dayMs},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await touchLastRead(q.bookId, created);
    return id;
  }

  /// 编辑既有摘录（表单全字段回写；创建时间可改 §3.3）。
  /// 查重键变化且撞别行 → 返回 false 不落库（调用方提示「已存在」）。
  Future<bool> updateQuote(BookQuote q) async {
    final key = q.body.trim().isEmpty
        ? ''
        : quoteDedupKey(q.bookId, q.chapter, q.page, q.body);
    if (key.isNotEmpty) {
      final dup = await db.query(
        DbSchema.tBookQuotes,
        where: 'dedup_hash = ? AND id <> ?',
        whereArgs: [key, q.id],
        limit: 1,
      );
      if (dup.isNotEmpty) return false;
    }
    final row = q.copyWith(dedupHash: key.isEmpty ? null : key).toRow();
    row['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      DbSchema.tBookQuotes,
      row,
      where: 'id = ?',
      whereArgs: [q.id],
    );
    for (final t in q.tags) {
      await dictAdd(DictEntry.kTag, t);
    }
    return true;
  }

  Future<BookQuote?> quoteById(int id) async {
    final rows = await db.query(
      DbSchema.tBookQuotes,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : BookQuote.fromRow(rows.first);
  }

  Future<void> setQuoteStarred(int id, bool starred) => db.update(
    DbSchema.tBookQuotes,
    {'starred': starred ? 1 : 0},
    where: 'id = ?',
    whereArgs: [id],
  );

  /// 软删（回收语义与书籍一致）；同步清复习档位行。
  Future<void> softDeleteQuote(int id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      DbSchema.tBookQuotes,
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    await db.delete(
      DbSchema.tBookReviews,
      where: 'quote_id = ?',
      whereArgs: [id],
    );
  }

  Future<List<BookQuote>> quotesOf(String bookId) async => (await db.query(
    DbSchema.tBookQuotes,
    where: 'book_id = ? AND deleted_at IS NULL',
    whereArgs: [bookId],
    orderBy: 'created_at DESC',
  )).map(BookQuote.fromRow).toList();

  Future<int> quoteCount() async =>
      Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM ${DbSchema.tBookQuotes} WHERE deleted_at IS NULL',
        ),
      ) ??
      0;

  Future<List<BookQuote>> recentQuotes(int limit) async => (await db.query(
    DbSchema.tBookQuotes,
    where: 'deleted_at IS NULL',
    orderBy: 'created_at DESC',
    limit: limit,
  )).map(BookQuote.fromRow).toList();

  Future<List<BookQuote>> allQuotes() async => (await db.query(
    DbSchema.tBookQuotes,
    where: 'deleted_at IS NULL',
    orderBy: 'created_at ASC',
  )).map(BookQuote.fromRow).toList();

  /// 书架搜索（原型 shFiltered 4549：匹配范围含该书摘录原文）：
  /// kw 命中的 book_id 集合（原文/想法/多选标签 LIKE，未软删行）。
  Future<Set<String>> quoteBookIdsMatching(String kw) async {
    final k = kw.trim();
    if (k.isEmpty) return const {};
    final like = '%$k%';
    final rows = await db.rawQuery(
      'SELECT DISTINCT book_id FROM ${DbSchema.tBookQuotes} '
      'WHERE deleted_at IS NULL '
      'AND (body LIKE ? OR thought LIKE ? OR tags LIKE ?)',
      [like, like, like],
    );
    return rows.map((r) => r['book_id'] as String).toSet();
  }

  /// 全部标签（笔记库筛选 chip 与表单多选共用）：字典优先、按使用频次排序兜底。
  Future<List<String>> quoteTags() async =>
      (await dictOf(DictEntry.kTag)).map((e) => e.name).toList();

  // ---- 复习（艾宾浩斯 1/3/7/30 天 · book_reviews 档位表）----

  Future<({int stage, int? nextAt})?> reviewOf(int quoteId) async {
    final rows = await db.query(
      DbSchema.tBookReviews,
      where: 'quote_id = ?',
      whereArgs: [quoteId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (
      stage: rows.first['stage'] as int,
      nextAt: rows.first['next_at'] as int?,
    );
  }

  /// 全量档位快照（复习弹层翻面「下次复习」展示用）。
  Future<Map<int, ({int stage, int? nextAt})>> reviewMap() async {
    final rows = await db.query(DbSchema.tBookReviews);
    return {
      for (final r in rows)
        r['quote_id'] as int: (
          stage: r['stage'] as int,
          nextAt: r['next_at'] as int?,
        ),
    };
  }

  Future<int> dueReviewCount([int? nowMs]) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM ${DbSchema.tBookQuotes} q '
            'JOIN ${DbSchema.tBookReviews} r ON r.quote_id = q.id '
            'WHERE q.deleted_at IS NULL AND r.next_at IS NOT NULL AND r.next_at <= ?',
            [now],
          ),
        ) ??
        0;
  }

  /// 到期队列（到期最早的在前）；无档位行的老摘录（批1/2 存量）按次日已到期兜底进入。
  Future<List<BookQuote>> dueReviews({int? nowMs, int? limit}) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final rows = await db.rawQuery(
      'SELECT q.* FROM ${DbSchema.tBookQuotes} q '
      'LEFT JOIN ${DbSchema.tBookReviews} r ON r.quote_id = q.id '
      'WHERE q.deleted_at IS NULL AND (r.next_at IS NOT NULL AND r.next_at <= ?'
      ' OR r.quote_id IS NULL) '
      'ORDER BY COALESCE(r.next_at, q.created_at) ASC'
      '${limit == null ? '' : ' LIMIT $limit'}',
      [now],
    );
    return rows.map(BookQuote.fromRow).toList();
  }

  /// 复习打卡：stage+1，按档位表取下一间隔；走完 30 天档 next 置空＝已掌握。
  Future<void> bumpReview(int quoteId, [int? nowMs]) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final cur = await reviewOf(quoteId);
    final stage = (cur?.stage ?? -1) + 1;
    final next = stage < reviewGapsMs.length
        ? now + reviewGapsMs[stage] * _dayMs
        : null;
    await db.insert(
      DbSchema.tBookReviews,
      {'quote_id': quoteId, 'stage': stage, 'next_at': next},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 没记住：回到第一档（次日再来）。
  Future<void> resetReview(int quoteId, [int? nowMs]) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      DbSchema.tBookReviews,
      {'quote_id': quoteId, 'stage': 0, 'next_at': now + _dayMs},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 模糊：档位不动，仅把下次到期推后 [days] 天（复习三档「忘了/模糊/记得」中间态）。
  Future<void> holdReview(int quoteId, int days, [int? nowMs]) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final cur = await reviewOf(quoteId);
    await db.insert(
      DbSchema.tBookReviews,
      {
        'quote_id': quoteId,
        'stage': cur?.stage ?? 0,
        'next_at': now + days * _dayMs,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---- L5 跨模块分流（R1 守护：经 DbSchema 常量裸 SQL，不 import 其它 feature）----

  String _quoteText(BookQuote q, Book b) =>
      '《${b.title}》${q.chapter == null ? '' : ' · ${q.chapter}'}'
      '${q.page == null ? '' : ' · ${q.page} 页'}\n${q.body}'
      '${(q.thought == null || q.thought!.isEmpty) ? '' : '\n— 感想：${q.thought}'}';

  /// 摘录 → 今日日记（一天多篇 journal_entries 直插一条纯文篇 · 计划 §4 批3）。
  Future<int> quoteToDiary(BookQuote q, Book b) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final d = DateTime.now();
    return db.insert(DbSchema.tJournal, {
      'entry_date': DateTime(d.year, d.month, d.day).millisecondsSinceEpoch,
      'content': _quoteText(q, b),
      'created_at': now,
      'updated_at': now,
    });
  }

  /// 摘录 → 待办：默认无截止日、非紧急象限（计划 §4 批3 口径）。
  Future<int> quoteToTodo(BookQuote q, Book b) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final t = q.body.length > 40 ? '${q.body.substring(0, 40)}…' : q.body;
    return db.insert(DbSchema.tTodos, {
      'title': t.isEmpty ? '重读《${b.title}》摘录' : t,
      'note': '来自书摘 · ${_quoteText(q, b)}',
      'quadrant': 2,
      'due_at': null,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// 摘录 → 笔记：MD 引用块成篇，落笔记库。
  Future<int> quoteToNote(BookQuote q, Book b) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.insert(DbSchema.tNotes, {
      'title': '书摘 · 《${b.title}》',
      'content': '> ${q.body.replaceAll('\n', '\n> ')}\n\n'
          '${(q.thought == null || q.thought!.isEmpty) ? '' : '${q.thought}\n\n'}'
          '—— 《${b.title}》${q.page == null ? '' : ' · 第 ${q.page} 页'}',
      'kind': 'md',
      'created_at': now,
      'updated_at': now,
    });
  }

  // ---- 目录（两级 · 计划 §2.2 / §3.3 手动微调与粘贴导入）----

  Future<List<TocNode>> tocOf(String bookId) async => (await db.query(
    DbSchema.tBookTocNodes,
    where: 'book_id = ?',
    whereArgs: [bookId],
    orderBy: 'level ASC, idx ASC, id ASC',
  )).map(TocNode.fromRow).toList();

  /// 粘贴导入 / 文件解析确认后整册替换（覆盖该书 book_toc_nodes）。
  Future<void> replaceToc(String bookId, List<ParsedTocPart> parts) =>
      db.transaction((txn) async {
        await txn.delete(
          DbSchema.tBookTocNodes,
          where: 'book_id = ?',
          whereArgs: [bookId],
        );
        var pi = 0;
        for (final p in parts) {
          final pid = await txn.insert(
            DbSchema.tBookTocNodes,
            TocNode(
              bookId: bookId,
              level: TocNode.kLevelPart,
              idx: pi++,
              title: p.title,
            ).toRow(),
          );
          for (var si = 0; si < p.sections.length; si++) {
            await txn.insert(
              DbSchema.tBookTocNodes,
              TocNode(
                bookId: bookId,
                parentId: pid,
                level: TocNode.kLevelSection,
                idx: si,
                title: p.sections[si],
              ).toRow(),
            );
          }
        }
      });

  Future<void> renameToc(int id, String title) => db.update(
    DbSchema.tBookTocNodes,
    {'title': title, 'confirmed': 1},
    where: 'id = ?',
    whereArgs: [id],
  );

  /// 同级内上移/下移（delta=-1/+1），换位后重写全部同级 idx。
  Future<void> moveToc(int id, int delta) async {
    final rows = await db.query(
      DbSchema.tBookTocNodes,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final node = TocNode.fromRow(rows.first);
    final sibs = (await db.query(
      DbSchema.tBookTocNodes,
      where: node.isPart
          ? 'book_id = ? AND level = 1'
          : 'book_id = ? AND level = 2 AND parent_id = ?',
      whereArgs: node.isPart ? [node.bookId] : [node.bookId, node.parentId],
      orderBy: 'idx ASC, id ASC',
    )).map(TocNode.fromRow).toList();
    final i = sibs.indexWhere((s) => s.id == id);
    final j = (i + delta).clamp(0, sibs.length - 1);
    if (i == j) return;
    final moved = [...sibs];
    final mover = moved.removeAt(i);
    moved.insert(j, mover);
    await db.transaction((txn) async {
      for (var k = 0; k < moved.length; k++) {
        await txn.update(
          DbSchema.tBookTocNodes,
          {'idx': k},
          where: 'id = ?',
          whereArgs: [moved[k].id],
        );
      }
    });
  }

  /// 删节点（部分连同其小节）；其下摘录 chapter 置空回落未分章，不删摘录。
  Future<void> deleteToc(int id) async {
    final rows = await db.query(
      DbSchema.tBookTocNodes,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final node = TocNode.fromRow(rows.first);
    final titles = <String>[node.title];
    if (node.isPart) {
      final children = await db.query(
        DbSchema.tBookTocNodes,
        columns: ['title'],
        where: 'parent_id = ?',
        whereArgs: [id],
      );
      titles.addAll(children.map((r) => r['title'] as String));
    }
    await db.transaction((txn) async {
      if (node.isPart) {
        await txn.delete(
          DbSchema.tBookTocNodes,
          where: 'parent_id = ?',
          whereArgs: [id],
        );
      }
      await txn.delete(
        DbSchema.tBookTocNodes,
        where: 'id = ?',
        whereArgs: [id],
      );
      for (final t in titles) {
        await txn.update(
          DbSchema.tBookQuotes,
          {'chapter': null},
          where: 'book_id = ? AND chapter = ?',
          whereArgs: [node.bookId, t],
        );
      }
    });
  }

  Future<int> addTocPart(String bookId, {String title = '新部分'}) async {
    final rows = await db.query(
      DbSchema.tBookTocNodes,
      columns: ['MAX(idx) AS m'],
      where: 'book_id = ? AND level = 1',
      whereArgs: [bookId],
    );
    final m = (rows.first['m'] as int?) ?? -1;
    return db.insert(
      DbSchema.tBookTocNodes,
      TocNode(
        bookId: bookId,
        level: TocNode.kLevelPart,
        idx: m + 1,
        title: title,
      ).toRow(),
    );
  }

  Future<int> addTocSection(int partId) async {
    final rows = await db.query(
      DbSchema.tBookTocNodes,
      where: 'id = ?',
      whereArgs: [partId],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    final part = TocNode.fromRow(rows.first);
    final maxIdx = await db.query(
      DbSchema.tBookTocNodes,
      columns: ['MAX(idx) AS m'],
      where: 'parent_id = ?',
      whereArgs: [partId],
    );
    final m = (maxIdx.first['m'] as int?) ?? -1;
    return db.insert(
      DbSchema.tBookTocNodes,
      TocNode(
        bookId: part.bookId,
        parentId: partId,
        level: TocNode.kLevelSection,
        idx: m + 1,
        title: '新小节',
      ).toRow(),
    );
  }

  /// 退出编辑自动清理空部分（§3.3 目录空部分治理）。
  Future<int> tocPrune(String bookId) async => db.delete(
    DbSchema.tBookTocNodes,
    where:
        'book_id = ? AND level = 1 AND id NOT IN (SELECT DISTINCT parent_id FROM ${DbSchema.tBookTocNodes} WHERE parent_id IS NOT NULL)',
    whereArgs: [bookId],
  );

  // ---- 记进度（openProgress 四方式真实回写 · 计划 §3.4）----

  /// 记进度落库：想读→自动转在读并补 started_at；刷新 last_read_at。
  Future<void> saveProgress(
    String bookId,
    String way,
    double? value, {
    String? chapterTitle,
    int? chapterStartPage,
  }) async {
    final b = await bookById(bookId);
    if (b == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final patch = progressPatch(
      b,
      way,
      value,
      chapterTitle: chapterTitle,
      chapterStartPage: chapterStartPage,
    );
    patch['updated_at'] = now;
    patch['last_read_at'] = maxActivity(b, extra: now);
    if (b.state == Book.kStateWant) {
      patch['state'] = Book.kStateReading;
      patch['started_at'] = b.startedAt ?? now;
    } else if (b.state == Book.kStateReading && b.startedAt == null) {
      patch['started_at'] = now;
    }
    await db.update(
      DbSchema.tBooks,
      patch,
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  // ---- 书架资料字典（§3.4 五类 CRUD · 改名事务内回写 books）----

  Future<List<DictEntry>> dictOf(String kind) async => (await db.query(
    DbSchema.tBookDict,
    where: 'kind = ?',
    whereArgs: [kind],
    orderBy: 'sort ASC, id ASC',
  )).map(DictEntry.fromRow).toList();

  Future<void> dictAdd(String kind, String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    await db.insert(
      DbSchema.tBookDict,
      DictEntry(kind: kind, name: n).toRow(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// 引用计数（删除前守卫）：books 直列 + tags/quotes 多值列。
  Future<int> dictRefCount(DictEntry e) async {
    switch (e.kind) {
      case DictEntry.kAuthor:
        return Sqflite.firstIntValue(
              await db.rawQuery(
                'SELECT COUNT(*) FROM ${DbSchema.tBooks} WHERE deleted_at IS NULL AND author = ?',
                [e.name],
              ),
            ) ??
            0;
      case DictEntry.kPublisher:
        return Sqflite.firstIntValue(
              await db.rawQuery(
                'SELECT COUNT(*) FROM ${DbSchema.tBooks} WHERE deleted_at IS NULL AND publisher = ?',
                [e.name],
              ),
            ) ??
            0;
      case DictEntry.kSource:
        return Sqflite.firstIntValue(
              await db.rawQuery(
                'SELECT COUNT(*) FROM ${DbSchema.tBooks} WHERE deleted_at IS NULL AND source = ?',
                [e.name],
              ),
            ) ??
            0;
      case DictEntry.kGroup:
        return Sqflite.firstIntValue(
              await db.rawQuery(
                'SELECT COUNT(*) FROM ${DbSchema.tBooks} WHERE deleted_at IS NULL AND grp = ?',
                [e.name],
              ),
            ) ??
            0;
      default:
        var n = 0;
        for (final b in (await allBooks()).where((b) => !b.isDeleted)) {
          if (b.tags.contains(e.name)) n++;
        }
        return n;
    }
  }

  /// 改名联动（事务内回写）：作者/出版社/来源/分组直列覆盖；标签走行内重算，
  /// 同步书摘 tags（笔记库按标签筛选口径一致）。
  Future<void> dictRename(DictEntry e, String newName) async {
    final n = newName.trim();
    if (e.id == null || n.isEmpty || n == e.name) return;
    await db.transaction((txn) async {
      await txn.update(
        DbSchema.tBookDict,
        {'name': n},
        where: 'id = ?',
        whereArgs: [e.id],
      );
      final col = switch (e.kind) {
        DictEntry.kAuthor => 'author',
        DictEntry.kPublisher => 'publisher',
        DictEntry.kSource => 'source',
        DictEntry.kGroup => 'grp',
        _ => null,
      };
      if (col != null) {
        await txn.rawUpdate(
          'UPDATE ${DbSchema.tBooks} SET $col = ?, updated_at = ? WHERE $col = ?',
          [n, DateTime.now().millisecondsSinceEpoch, e.name],
        );
        return;
      }
      final rows = await txn.query(
        DbSchema.tBooks,
        columns: ['id', 'tags'],
        where: "tags LIKE ?",
        whereArgs: ['%${e.name}%'],
      );
      for (final r in rows) {
        final tags = splitTags(
          r['tags'] as String?,
        ).map((t) => t == e.name ? n : t).toList();
        await txn.update(
          DbSchema.tBooks,
          {'tags': tags.join(',')},
          where: 'id = ?',
          whereArgs: [r['id']],
        );
      }
      final qs = await txn.query(
        DbSchema.tBookQuotes,
        columns: ['id', 'tags'],
        where: "tags LIKE ?",
        whereArgs: ['%${e.name}%'],
      );
      for (final r in qs) {
        final tags = splitTags(
          r['tags'] as String?,
        ).map((t) => t == e.name ? n : t).toList();
        await txn.update(
          DbSchema.tBookQuotes,
          {'tags': tags.join(',')},
          where: 'id = ?',
          whereArgs: [r['id']],
        );
      }
    });
  }

  Future<void> dictDelete(DictEntry e) async {
    if (e.id == null) return;
    await db.delete(DbSchema.tBookDict, where: 'id = ?', whereArgs: [e.id]);
  }

  // ---- 书单（批4 · 计划 §2.3：手动 items / 年度 auto_year 动态成员）----

  Future<List<BookList>> allLists() async => (await db.query(
    DbSchema.tBookLists,
    where: 'deleted_at IS NULL',
    orderBy: 'sort ASC, id DESC',
  )).map(BookList.fromRow).toList();

  Future<BookList?> findAutoYear(int year) async {
    final rows = await db.query(
      DbSchema.tBookLists,
      where: 'deleted_at IS NULL AND auto_year = ?',
      whereArgs: [year],
      limit: 1,
    );
    return rows.isEmpty ? null : BookList.fromRow(rows.first);
  }

  /// 新建书单；[autoYear] 非空时该年已读成员无需写 items（动态求）。
  Future<BookList> addList(
    BookList l, {
    List<String> bookIds = const [],
    int? autoYear,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final maxSort =
        Sqflite.firstIntValue(
              await db.rawQuery(
                'SELECT COALESCE(MAX(sort),0) FROM ${DbSchema.tBookLists} WHERE deleted_at IS NULL',
              ),
            ) ??
            0;
    final id = await db.insert(DbSchema.tBookLists, {
      'name': l.name,
      'note': l.note,
      'auto_year': autoYear,
      'sort': maxSort + 1,
      'created_at': now,
      'updated_at': now,
    });
    if (bookIds.isNotEmpty) await setListBooks(id, bookIds);
    return (await listById(id))!;
  }

  Future<BookList?> listById(int id) async {
    final rows = await db.query(
      DbSchema.tBookLists,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : BookList.fromRow(rows.first);
  }

  Future<void> updateList(BookList l) => db.update(
    DbSchema.tBookLists,
    {
      'name': l.name,
      'note': l.note,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    },
    where: 'id = ?',
    whereArgs: [l.id],
  );

  /// 整体重排成员（选书弹层保存共用；年度自动单不调用）。
  Future<void> setListBooks(int listId, List<String> bookIds) => db.transaction(
    (txn) async {
      await txn.delete(
        DbSchema.tBookListItems,
        where: 'list_id = ?',
        whereArgs: [listId],
      );
      for (var i = 0; i < bookIds.length; i++) {
        await txn.insert(
          DbSchema.tBookListItems,
          {'list_id': listId, 'book_id': bookIds[i], 'pos': i},
        );
      }
      await txn.update(
        DbSchema.tBookLists,
        {'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [listId],
      );
    },
  );

  Future<void> addBookToList(int listId, String bookId) async {
    final maxPos =
        Sqflite.firstIntValue(
              await db.rawQuery(
                'SELECT COALESCE(MAX(pos),-1) FROM ${DbSchema.tBookListItems} WHERE list_id = ?',
                [listId],
              ),
            ) ??
            -1;
    await db.insert(
      DbSchema.tBookListItems,
      {'list_id': listId, 'book_id': bookId, 'pos': maxPos + 1},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// 移出书单＝只删成员行，书本身保留（原型 blRm 文案口径）。
  Future<void> removeBookFromList(int listId, String bookId) => db.delete(
    DbSchema.tBookListItems,
    where: 'list_id = ? AND book_id = ?',
    whereArgs: [listId, bookId],
  );

  Future<void> softDeleteList(int id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      DbSchema.tBookLists,
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    await db.delete(
      DbSchema.tBookListItems,
      where: 'list_id = ?',
      whereArgs: [id],
    );
  }

  /// 成员解析：年度单按「已读 && ended_at∈该年」动态求（[desc]＝read.yearSort）；
  /// 手动单按 items.pos 序，跳过已软删书。
  Future<List<Book>> listMembers(BookList l, {bool desc = false}) async {
    final books = await allBooks();
    if (l.autoYear != null) {
      final y = l.autoYear!;
      final done = books.where((b) {
        if (b.state != Book.kStateDone || b.isDeleted) return false;
        if (b.endedAt == null) return false;
        return DateTime.fromMillisecondsSinceEpoch(b.endedAt!).year == y;
      }).toList()
        ..sort(
          (a, b) => desc
              ? b.endedAt!.compareTo(a.endedAt!)
              : a.endedAt!.compareTo(b.endedAt!),
        );
      return done;
    }
    final rows = await db.query(
      DbSchema.tBookListItems,
      where: 'list_id = ?',
      whereArgs: [l.id],
      orderBy: 'pos ASC',
    );
    final byId = {for (final b in books) b.id: b};
    return rows
        .map((r) => byId[r['book_id'] as String])
        .whereType<Book>()
        .where((b) => !b.isDeleted)
        .toList();
  }

  // ---- 统计聚合（批4 · p-readstat 数据源）----

  /// 全年逐日分钟账（缺失日补 0）。
  Future<List<({DateTime day, int minutes})>> dayLogYear(int year) async {
    final byDay = <DateTime, int>{};
    for (final s in await allSessions()) {
      if (s.endedAt == null) continue; // 在跑的会话不入历史账
      final d = DateTime.fromMillisecondsSinceEpoch(s.startedAt);
      if (d.year != year) continue;
      final key = DateTime(d.year, d.month, d.day);
      byDay[key] = (byDay[key] ?? 0) + s.minutes;
    }
    final first = DateTime(year);
    final days = DateTime(year, 12, 31).difference(first).inDays + 1;
    return [
      for (var i = 0; i < days; i++)
        (
          day: first.add(Duration(days: i)),
          minutes:
              byDay[first.add(Duration(days: i))] ?? 0,
        ),
    ];
  }

  /// 逐日摘录条数（当年）。
  Future<Map<DateTime, int>> dayQuotesYear(int year) async {
    final out = <DateTime, int>{};
    for (final q in await allQuotes()) {
      final d = DateTime.fromMillisecondsSinceEpoch(q.createdAt);
      if (d.year != year) continue;
      final key = DateTime(d.year, d.month, d.day);
      out[key] = (out[key] ?? 0) + 1;
    }
    return out;
  }

  /// 时段分布（24 桶；会话分钟整体记在开始时段，原型 hrs 口径）。
  Future<List<int>> hourHistogram(int year) async {
    final hrs = List<int>.filled(24, 0);
    for (final s in await allSessions()) {
      if (s.endedAt == null) continue;
      final d = DateTime.fromMillisecondsSinceEpoch(s.startedAt);
      if (d.year != year) continue;
      hrs[d.hour] += s.minutes;
    }
    return hrs;
  }

  /// 购书支出合计（未删书 fee 求和）。
  Future<({double fee, int paid})> feeTotals() async {
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(fee),0) s, COUNT(*) c FROM ${DbSchema.tBooks} '
      'WHERE deleted_at IS NULL AND fee > 0',
    );
    final m = rows.first;
    return (fee: (m['s'] as num).toDouble(), paid: m['c'] as int);
  }

  /// 完读书字数（页数折算 · 原型 pg*520）与完读书累计分钟。
  Future<({int words, int rdMin})> doneWords() async {
    var words = 0;
    var min = 0;
    final agg = sessionAggByBook(await allSessions());
    for (final b in await allBooks()) {
      if (b.isDeleted || b.state != Book.kStateDone) continue;
      words += b.pages * 520;
      min += agg[b.id]?.minutes ?? 0;
    }
    return (words: words, rdMin: min);
  }

  /// 本月摘录数（L7 目标第五路）。
  Future<int> quotesThisMonth() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month).millisecondsSinceEpoch;
    return Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM ${DbSchema.tBookQuotes} WHERE deleted_at IS NULL AND created_at >= ?',
            [start],
          ),
        ) ??
        0;
  }

  /// 本年读完本数（ended_at 落在今年）。
  Future<int> doneThisYear() async {
    final y = DateTime.now().year;
    return (await allBooks())
        .where(
          (b) =>
              !b.isDeleted &&
              b.state == Book.kStateDone &&
              b.endedAt != null &&
              DateTime.fromMillisecondsSinceEpoch(b.endedAt!).year == y,
        )
        .length;
  }

  // ---- 购书费用 → L4/记账流水（read.feeTxn 默认开 · §9.5 已拍板③）----

  /// 书保存后同步「阅读-购书」支出流水：新增或改费用→同条更新；清零→删行。
  Future<void> _syncFeeTxn(Book b) async {
    final enabled = ((await kv('read.feeTxn')) ?? 'true') == 'true';
    if (b.fee <= 0) {
      if (b.feeTxnId != null) {
        await db.delete(
          DbSchema.tFinance,
          where: 'id = ?',
          whereArgs: [b.feeTxnId],
        );
        await db.update(
          DbSchema.tBooks,
          {'fee_txn_id': null},
          where: 'id = ?',
          whereArgs: [b.id],
        );
      }
      return;
    }
    final note = '《${b.title}》购书';
    if (!enabled) return; // 关闭后只保留费用字段不出账
    if (b.feeTxnId == null) {
      final id = await db.insert(DbSchema.tFinance, {
        'amount': b.fee,
        'direction': '支出',
        'category': '阅读',
        'occurred_at': DateTime.now().millisecondsSinceEpoch,
        'source': 'read',
        'note': note,
      });
      await db.update(
        DbSchema.tBooks,
        {'fee_txn_id': id},
        where: 'id = ?',
        whereArgs: [b.id],
      );
    } else {
      await db.update(
        DbSchema.tFinance,
        {'amount': b.fee, 'note': note},
        where: 'id = ?',
        whereArgs: [b.feeTxnId],
      );
    }
  }

  // ---- 导入（计划 §5 · 三级去重 isbn→作者+书名归一→摘录等价键 · 整批事务 · 撤销本批）----

  /// 一、二级去重：先 ISBN 归一命中，再「作者+书名归一」；书名相同作者不同的
  /// 记为 loose（导入时优先精确、无精确才认 loose），都不中返回 null。
  Future<Book?> findBookFor({String? isbn, String? title, String? author}) async {
    final ni = normIsbn(isbn);
    final nt = normTitle(title);
    if (ni.isEmpty && nt.isEmpty) return null;
    final books = await allBooks();
    if (ni.isNotEmpty) {
      for (final b in books) {
        if (!b.isDeleted && normIsbn(b.isbn) == ni) return b;
      }
    }
    if (nt.isEmpty) return null;
    final na = normTitle(author);
    Book? loose;
    for (final b in books) {
      if (b.isDeleted || normTitle(b.title) != nt) continue;
      if (na.isEmpty || normTitle(b.author) == na) return b;
      loose ??= b;
    }
    return loose;
  }

  /// 解析 + 标注（不落库）；调用方逐行显示「新增 / 已存在 · 跳过」。
  Future<List<ImportRow>> previewImport(ImportChannel ch, String raw) async {
    final seen = <String>{};
    final rows = <ImportRow>[];
    for (final c in parseClips(ch, raw)) {
      final b = await findBookFor(isbn: c.isbn, title: c.book, author: c.author);
      var dup = false;
      if (b != null) {
        final key = quoteDedupKey(b.id, c.chapter, c.page, c.body);
        dup = !seen.add(key) ||
            (await db.query(
              DbSchema.tBookQuotes,
              where: 'dedup_hash = ? AND deleted_at IS NULL',
              whereArgs: [key],
              limit: 1,
            )).isNotEmpty;
      }
      rows.add(ImportRow(c, b?.id, dup));
    }
    return rows;
  }

  /// 整批事务落库：命中已有书补摘录；未建档的按「想读 · 来源=渠道名」自动建档；
  /// origin 记渠道便于二次清洗；导入不改 last_read_at（不挤占「最近阅读」序）。
  Future<ImportOutcome> commitImport(ImportChannel ch, String raw) async {
    final rows = await previewImport(ch, raw);
    var added = 0, skipped = 0;
    final ids = <int>[];
    final created = <Book>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    final newBookCache = <String, String>{}; // 批内同书复用新建档
    await db.transaction((txn) async {
      for (final r in rows) {
        if (r.dup) {
          skipped++;
          continue;
        }
        final c = r.clip;
        var bookId = r.bookId ?? newBookCache[normTitle(c.book)];
        if (bookId == null) {
          final nb = Book(
            id: _newId(),
            title: c.book,
            author: c.author.isEmpty ? '佚名' : c.author,
            isbn: (normIsbn(c.isbn).isEmpty) ? null : c.isbn,
            source: ch.name,
            state: Book.kStateWant,
            createdAt: now,
            updatedAt: now,
            lastReadAt: now,
          );
          await txn.insert(DbSchema.tBooks, nb.toRow());
          created.add(nb);
          bookId = nb.id;
          newBookCache[normTitle(c.book)] = bookId;
        }
        final createdMs = c.at?.millisecondsSinceEpoch ?? now;
        final q = BookQuote(
          bookId: bookId,
          kind: c.body.isEmpty
              ? BookQuote.kKindThought
              : BookQuote.kKindMark,
          tag: BookQuote.kTagReso,
          body: c.body,
          thought: c.thought,
          chapter: c.chapter,
          page: c.page,
          loc: c.loc,
          origin: ch.name,
          dedupHash: quoteDedupKey(bookId, c.chapter, c.page, c.body),
          createdAt: createdMs,
          updatedAt: now,
        );
        // 事务内显式查重：唯一索引撞软删残留时 INSERT OR IGNORE 会返回
        // 陈旧 lastInsertRowId，直接吞行会让「撤销本批」删错，故先查后插。
        final clash = await txn.query(
          DbSchema.tBookQuotes,
          where: 'dedup_hash = ?',
          whereArgs: [q.dedupHash],
          limit: 1,
        );
        if (clash.isNotEmpty) {
          skipped++;
          continue;
        }
        final id = await txn.insert(DbSchema.tBookQuotes, q.toRow());
        ids.add(id);
        await txn.insert(
          DbSchema.tBookReviews,
          {'quote_id': id, 'stage': 0, 'next_at': createdMs + _dayMs},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        added++;
      }
    });
    for (final b in created) {
      await _registerDictFor(b);
    }
    return (
      added: added,
      skipped: skipped,
      booksCreated: created.length,
      ids: ids,
    );
  }

  /// 撤销本批：硬删导入行与其复习档位（撤销≠用户删除，不留回收站残骸）。
  Future<int> undoImportBatch(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final ph = List.filled(ids.length, '?').join(',');
    await db.transaction((txn) async {
      await txn.delete(
        DbSchema.tBookReviews,
        where: 'quote_id IN ($ph)',
        whereArgs: ids,
      );
      await txn.delete(
        DbSchema.tBookQuotes,
        where: 'id IN ($ph)',
        whereArgs: ids,
      );
    });
    return ids.length;
  }

  /// 按清单建书（原型 impAll）：CSV 渠道走表头别名，其余按
  /// `书名 [作者] [ISBN]` 行式解析；一、二级去重命中即跳过；
  /// 新档＝想读 · 来源「导入清单」· 缺资料提示补齐。
  Future<({int created, int skipped})> importBookList(
    String raw, {
    ImportChannel? ch,
  }) async {
    var created = 0, skipped = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final made = <Book>[];
    final cache = <String, String>{};
    final rows = ch != null && ch.parser == 'csv'
        ? parseCsvBookList(ch, raw)
        : parseBookList(raw);
    for (final r in rows) {
      final exist = await findBookFor(isbn: r.isbn, title: r.title, author: r.author);
      if (exist != null || cache.containsKey(normTitle(r.title))) {
        skipped++;
        continue;
      }
      final b = Book(
        id: _newId(),
        title: r.title,
        author: r.author.isEmpty ? '待补' : r.author,
        isbn: r.isbn,
        source: '导入清单',
        state: Book.kStateWant,
        intro: '由书架清单导入，缺少作者与封面 · 点编辑补齐。',
        createdAt: now,
        updatedAt: now,
        lastReadAt: now,
      );
      await db.insert(DbSchema.tBooks, b.toRow());
      cache[normTitle(r.title)] = b.id;
      made.add(b);
      created++;
    }
    for (final b in made) {
      await _registerDictFor(b);
    }
    return (created: created, skipped: skipped);
  }

  // ---- 导出（计划 §6 数据与存储 · MD 按书分组 / JSON 书架备份）----

  Future<String> buildQuotesMd() async {
    final books = await allBooks();
    books.sort(
      (a, b) => (b.lastReadAt ?? b.createdAt).compareTo(
        a.lastReadAt ?? a.createdAt,
      ),
    );
    final sb = StringBuffer('# 全部书摘\n');
    for (final b in books) {
      final qs = await quotesOf(b.id);
      if (qs.isEmpty) continue;
      sb.write('\n## 《${b.title}》（${b.author}）\n');
      for (final q in qs) {
        if (q.body.isNotEmpty) sb.write('\n> ${q.body.replaceAll('\n', '\n> ')}\n');
        if (q.thought != null && q.thought!.isNotEmpty) {
          sb.write('\n想法：${q.thought}\n');
        }
        final meta = [
          if ((q.chapter ?? '').isNotEmpty) q.chapter,
          if (q.page != null) 'P${q.page}',
          DateTime.fromMillisecondsSinceEpoch(q.createdAt).toIso8601String().substring(0, 10),
          if ((q.origin ?? '').isNotEmpty) q.origin,
        ].join(' · ');
        sb.write('\n— $meta\n');
      }
    }
    return sb.toString();
  }

  Future<String> buildBackupJson() async {
    final books = await allBooks();
    final quotes = await db.query(DbSchema.tBookQuotes);
    final lists = await allLists();
    final settings = await db.query(
      DbSchema.tSettings,
      where: "key LIKE 'read.%'",
    );
    return const JsonEncoder.withIndent(' ').convert({
      'app': 'LifeHarness',
      'kind': 'bookshelf',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'books': [for (final b in books) b.toRow()],
      'quotes': [...quotes],
      'lists': [for (final l in lists) l.toRow()],
      'settings': {for (final s in settings) s['key'] as String: s['value']},
    });
  }

  // ---- read.* 设置（settings 表 KV · 计划 §6）----

  Future<String?> kv(String key) async {
    final rows = await db.query(
      DbSchema.tSettings,
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setKv(String key, String value) => db.insert(
    DbSchema.tSettings,
    {'key': key, 'value': value},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<int> kvInt(String key, int def) async =>
      int.tryParse(await kv(key) ?? '') ?? def;
}
