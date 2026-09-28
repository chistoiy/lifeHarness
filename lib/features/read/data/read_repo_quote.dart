part of 'read_repository.dart';

// 治理G7d④：摘录群（查重入账/标签字典/复习档位/L5 跨模块分流）移入同库 mixin（行为零改动·成员经 with 组合后仍是 ReadRepository 的实例成员）。
// 群内自用 static reviewGapsMs 随迁（全仓无 ReadRepository.reviewGapsMs 外部调用，已核实）；
// quotesOf/allQuotes 被导出群与统计群跨群调用，留类内。
mixin _RepoQuotes on _ReadRepoBase {
  // ---- 摘录（批3 全量：查重入账 / 标签字典 / 复习档位 / L5 分流）----

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

  /// V1.46④ 笔记库「删除＋撤销」：撤销即恢复 deleted_at（复习档位不重建，
  /// 从新开始复习，与既有档位表语义无冲突）。
  Future<void> restoreQuote(int id) => db.update(
    DbSchema.tBookQuotes,
    {'deleted_at': null, 'updated_at': DateTime.now().millisecondsSinceEpoch},
    where: 'id = ?',
    whereArgs: [id],
  );

  Future<int> quoteCount() async =>
      Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM ${DbSchema.tBookQuotes} WHERE deleted_at IS NULL',
        ),
      ) ??
      0;

  /// 指定时刻之后新增的摘录条数（统计页周报 toast · 批D）。
  Future<int> quoteCountSince(int startMs) async =>
      Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM ${DbSchema.tBookQuotes} '
          'WHERE deleted_at IS NULL AND created_at >= ?',
          [startMs],
        ),
      ) ??
      0;

  Future<List<BookQuote>> recentQuotes(int limit) async => (await db.query(
    DbSchema.tBookQuotes,
    where: 'deleted_at IS NULL',
    orderBy: 'created_at DESC',
    limit: limit,
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

  /// 全书摘录 → 一条笔记（档案页「转存笔记」· 批C · 同 quoteToNote 裸 SQL 通道）。
  Future<int> bookToNote(Book b) async {
    final qs = await quotesOf(b.id);
    final now = DateTime.now().millisecondsSinceEpoch;
    final body = qs.isEmpty
        ? ''
        : qs.reversed.map((q) =>
              '> ${q.body.replaceAll('\n', '\n> ')}'
              '${(q.thought == null || q.thought!.isEmpty) ? '' : '\n\n想法：${q.thought}'}'
              '\n\n—— ${q.chapter ?? ''}${q.page == null ? '' : ' · 第 ${q.page} 页'}').join('\n\n');
    return db.insert(DbSchema.tNotes, {
      'title': '书摘 · 《${b.title}》',
      'content': body.isEmpty ? '《${b.title}》还没有摘录' : '$body\n',
      'kind': 'md',
      'created_at': now,
      'updated_at': now,
    });
  }
}
