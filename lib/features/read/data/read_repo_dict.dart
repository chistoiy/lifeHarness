part of 'read_repository.dart';

// 治理G7d④：书架资料字典的引用计数与改名联动群移入同库 mixin（行为零改动·成员经 with 组合后仍是 ReadRepository 的实例成员）。
// dictOf/dictAdd 被摘录群跨群调用，留枢纽层。
mixin _RepoDict on _ReadRepoBase {
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

  /// 全值域批量引用计数（资料管理单类页 · 原型 bmCount 逐值口径）：
  /// 直列走 GROUP BY，标签展开 books.tags 逗号列累加。
  Future<Map<String, int>> dictRefCounts(String kind) async {
    if (kind == DictEntry.kTag) {
      final out = <String, int>{};
      for (final b in (await allBooks()).where((b) => !b.isDeleted)) {
        for (final t in b.tags) {
          out[t] = (out[t] ?? 0) + 1;
        }
      }
      return out;
    }
    final col = switch (kind) {
      DictEntry.kAuthor => 'author',
      DictEntry.kPublisher => 'publisher',
      DictEntry.kSource => 'source',
      _ => 'grp',
    };
    final rows = await db.rawQuery(
      'SELECT $col AS v, COUNT(*) AS n FROM ${DbSchema.tBooks} '
      'WHERE deleted_at IS NULL AND $col IS NOT NULL AND $col != \'\' '
      'GROUP BY $col',
    );
    return {
      for (final r in rows)
        r['v'] as String: (r['n'] as int?) ?? 0,
    };
  }

  /// 改名联动（事务内回写）：作者/出版社/来源/分组直列覆盖；标签走行内重算，
  /// 同步书摘 tags（笔记库按标签筛选口径一致）。
  /// e.id==null＝books 里已存在但字典缺行的合成项：只回写值域列并补登记字典。
  Future<void> dictRename(DictEntry e, String newName) async {
    final n = newName.trim();
    if (n.isEmpty || n == e.name) return;
    await db.transaction((txn) async {
      if (e.id != null) {
        await txn.update(
          DbSchema.tBookDict,
          {'name': n},
          where: 'id = ?',
          whereArgs: [e.id],
        );
      }
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
}
