part of 'read_repository.dart';

// 治理G7d④：书单群（手动 items / 年度 auto_year 动态成员）移入同库 mixin（行为零改动·成员经 with 组合后仍是 ReadRepository 的实例成员）。
// allLists 被导出群跨群调用，留枢纽层。
mixin _RepoLists on _ReadRepoBase {
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

  /// 书单进回收站（V1.60 全局回收站）：**成员行保留**——需求口径＝恢复回原位，
  /// 成员表跟着删就恢复不出原书单（旧实装随手删 items，本批翻案，用例 5-1 同步改断言）。
  Future<void> softDeleteList(int id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      DbSchema.tBookLists,
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---- V1.60 全局回收站：书单垃圾箱三件套 + 到期清理 ----

  /// 垃圾箱里的书单（按删除时间倒序）。
  Future<List<BookList>> trashedLists() async => (await db.query(
    DbSchema.tBookLists,
    where: 'deleted_at IS NOT NULL',
    orderBy: 'deleted_at DESC, id DESC',
  )).map(BookList.fromRow).toList();

  /// 恢复书单＝deleted_at 置空（成员行软删期一直保留，原位原成员回来）。
  Future<void> restoreList(int id) => db.update(
    DbSchema.tBookLists,
    {'deleted_at': null, 'updated_at': DateTime.now().millisecondsSinceEpoch},
    where: 'id = ?',
    whereArgs: [id],
  );

  /// 回收站「彻底删除」书单：行与成员一起真删（成员指向的书本身不动）。
  Future<void> purgeList(int id) async {
    await db.delete(
      DbSchema.tBookListItems,
      where: 'list_id = ?',
      whereArgs: [id],
    );
    await db.delete(DbSchema.tBookLists, where: 'id = ?', whereArgs: [id]);
  }

  /// 手动单的成员条数（回收站书单行副信息「成员 N 本」；年度单成员动态求）。
  Future<int> listItemCount(int listId) async => Sqflite.firstIntValue(
    await db.rawQuery(
      'SELECT COUNT(*) FROM ${DbSchema.tBookListItems} WHERE list_id = ?',
      [listId],
    ),
  ) ?? 0;

  /// 到期自动清理：真删过早于保留期的垃圾箱书单（含成员行）。
  Future<int> purgeExpiredTrashLists(int keepDays) async {
    if (keepDays <= 0) return 0;
    final cutoff =
        DateTime.now()
            .subtract(Duration(days: keepDays))
            .millisecondsSinceEpoch;
    final ids = (await db.query(
      DbSchema.tBookLists,
      columns: ['id'],
      where: 'deleted_at IS NOT NULL AND deleted_at < ?',
      whereArgs: [cutoff],
    )).map((r) => r['id'] as int).toList();
    for (final id in ids) {
      await purgeList(id);
    }
    return ids.length;
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
}
