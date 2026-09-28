part of 'read_repository.dart';

// 治理G7d④：目录（两级·手动微调与粘贴导入）与记进度群移入同库 mixin（行为零改动·成员经 with 组合后仍是 ReadRepository 的实例成员）。
mixin _RepoToc on _ReadRepoBase {
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
}
