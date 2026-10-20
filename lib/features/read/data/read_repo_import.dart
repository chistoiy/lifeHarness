part of 'read_repository.dart';

// 治理G7d④：导入群（三级去重·整批事务·撤销本批·书单导入）移入同库 mixin（行为零改动·成员经 with 组合后仍是 ReadRepository 的实例成员）。
mixin _RepoImport on _ReadRepoBase {
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
}
