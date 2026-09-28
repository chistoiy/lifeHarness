part of 'read_repository.dart';

// 治理G7d④：计时会话群自 _ReadRepoBase 移入同库 mixin（行为零改动·成员经 with 组合后仍是 ReadRepository 的实例成员）。
// 单活会话开始/结束/就地补位·关闭与门槛·明细增删改与 L4 流水回写·聚合重算·
// 今日/本周分钟与自然日列表。allSessions（被统计群跨群调用）与 dayStartMs（公开静态 API）留类内。
mixin _RepoSessions on _ReadRepoBase {
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
  /// [at]＝起始位置快照（阅读器进入即知 → 轮5.2② 自动记，不再手填）。
  Future<BookSession> startSession(String bookId, {BrLoc? at}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final old = await runningSession();
    if (old != null) {
      await _close(old, now);
    }
    final id = await db.insert(
      DbSchema.tBookSessions,
      BookSession(
        bookId: bookId,
        startedAt: now,
        fromPage: at?.page,
        fromPct: at?.pct,
        fromChapter: at?.chapter,
      ).toRow(),
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

  /// 结束计时（胶囊/计时页/退出阅读器共用）：返回已关闭会话供 L4 流水（批2）；
  /// 无在跑会话或不属于该书返回 null。
  /// [to]＝结束位置快照；[minSecs]＝短会话门槛（轮5.2②：不足门槛整条丢弃，
  /// 时长与会话都不入账，读页退出时按 read.brMinSecs 传入）。
  Future<BookSession?> endSession(
    String bookId, {
    BrLoc? to,
    int minSecs = 0,
  }) async {
    final old = await runningSession();
    if (old == null || old.bookId != bookId) return null;
    return _close(
      old,
      DateTime.now().millisecondsSinceEpoch,
      to: to,
      minSecs: minSecs,
    );
  }

  /// 就地补写进行中会话的起始位置快照（进阅读器时文档尚未就绪 → 就绪后回填）。
  Future<void> stampSessionStart(int sessionId, BrLoc at) => db.update(
    DbSchema.tBookSessions,
    {
      'from_page': at.page,
      'from_pct': at.pct,
      'from_chapter': at.chapter,
    },
    where: 'id = ?',
    whereArgs: [sessionId],
  );

  /// 关闭一条在跑会话：正常→落 ended_at/minutes/结束位置 + L4 流水；
  /// 回拨或未达门槛→删行不入账（§2.4 / 轮5.2②）。
  Future<BookSession?> _close(
    BookSession s,
    int nowMs, {
    BrLoc? to,
    int minSecs = 0,
  }) async {
    final closed = closeRunning(s, nowMs, minSecs: minSecs);
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
      {
        'ended_at': closed.endedAt,
        'minutes': closed.minutes,
        if (to != null) 'to_page': to.page,
        if (to != null) 'to_pct': to.pct,
        if (to != null) 'to_chapter': to.chapter,
      },
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
      'day': ReadRepository.dayStartMs(day),
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

  /// 今日累计入账分钟（含在跑会话的已耗时；倍速按 speedFold 口径在 billedMinutes）。
  Future<int> minutesOnDay(DateTime day) async {
    final from = ReadRepository.dayStartMs(day);
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
    final from = ReadRepository.dayStartMs(monday);
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
}
