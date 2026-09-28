part of 'read_repository.dart';

// 治理G7d④：书籍状态群与购书费用流水群自 _ReadRepoBase 移入同库 mixin（行为零改动·成员经 with 组合后仍是 ReadRepository 的实例成员）。
// 新增/更新/分区流转（单本与批量同语义）·批量加标签·软删；
// 「购书费用 → L4/记账流水」整段随本群外提（唯一调用者 addBook/updateBook 在同群）。
// 群内自用 static _stateValues 随迁；枢纽 allBooks/bookById/touchLastRead/_registerDictFor 留类内。
mixin _RepoBooks on _ReadRepoBase {
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
}
