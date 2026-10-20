part of 'read_repository.dart';

// 治理G7d④：导出群（MD 按书分组 / JSON 书架备份）与豆瓣元数据缓存群移入同库 mixin（行为零改动·成员经 with 组合后仍是 ReadRepository 的实例成员）。
mixin _RepoExport on _ReadRepoBase {
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

  /// 单本书摘录 MD（档案页「导出MD」· 批C）。
  Future<String> buildBookQuotesMd(Book b) async {
    final qs = await quotesOf(b.id);
    final sb = StringBuffer('# 《${b.title}》书摘（${b.author}）\n');
    for (final q in qs.reversed) {
      if (q.body.isNotEmpty) {
        sb.write('\n> ${q.body.replaceAll('\n', '\n> ')}\n');
      }
      if (q.thought != null && q.thought!.isNotEmpty) {
        sb.write('\n想法：${q.thought}\n');
      }
      final meta = [
        if ((q.chapter ?? '').isNotEmpty) q.chapter,
        if (q.page != null) 'P${q.page}',
        DateTime.fromMillisecondsSinceEpoch(q.createdAt)
            .toIso8601String()
            .substring(0, 10),
      ].join(' · ');
      sb.write('\n— $meta\n');
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

}

mixin _RepoDouban on _ReadRepoBase {
  // ---- 豆瓣元数据缓存（v23 douban_meta · 防封批 2026-09-26）----
  // 只存 App 在用的最小字段集（不存整页快照），控制库体积与云备份体积；
  // 手动清理由阅读设置「清除豆瓣缓存」触发（只清表行，不动已落盘封面文件，
  // 封面清理走记录管理的文件口径）。Cookie 不落本库（存 SharedPreferences，
  // 不进 DB 快照/书架备份导出）。

  Future<Map<String, Object?>?> doubanCacheRow(String code) => db.query(
    DbSchema.tDoubanMeta,
    where: 'code = ?',
    whereArgs: [code.trim()],
    limit: 1,
  ).then((r) => r.isEmpty ? null : r.first);

  Future<void> doubanCachePut(
    String code,
    IsbnBookMeta meta, {
    String? subject,
    String? coverPath,
    bool viaSuggest = false,
  }) => db.insert(DbSchema.tDoubanMeta, {
    'code': code.trim(),
    'subject': subject,
    'title': meta.title,
    'author': meta.author,
    'publisher': meta.publisher,
    'pub_date': meta.pubDate,
    'pages': meta.pages,
    'rating': meta.rating,
    'cover_url': meta.coverUrl,
    'cover_path': coverPath,
    'via_suggest': viaSuggest ? 1 : 0,
    'fetched_at': DateTime.now().millisecondsSinceEpoch,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<int> doubanCacheCount() async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) c FROM ${DbSchema.tDoubanMeta}',
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// 手动清理：整表清空（阅读设置入口 · 无按行删除需求）。
  Future<void> doubanCacheClear() => db.delete(DbSchema.tDoubanMeta);
}
