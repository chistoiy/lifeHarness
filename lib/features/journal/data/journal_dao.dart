import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../domain/journal_entry.dart';

/// journal_entries 表数据访问对象（V1.28 起一天可多篇；分节存 journal_sections）。
class JournalDao {
  JournalDao(this.db);

  final Database db;

  String get table => DbSchema.tJournal;

  JournalEntry fromRow(Map<String, Object?> row) => JournalEntry.fromRow(row);

  /// 全部条目（新→旧：同日按创建倒序，最新篇在前）。
  /// 语义断链批（2026-10-12）：回收站行不参与业务读（同 note_dao 先例）。
  Future<List<JournalEntry>> list() => _tagged(db.query(table,
      where: 'deleted_at IS NULL',
      orderBy: 'entry_date DESC, created_at DESC, id DESC'));

  /// 当日全部篇（新→旧）。
  Future<List<JournalEntry>> listByDay(DateTime day) => _tagged(db.query(
        table,
        where: 'entry_date = ? AND deleted_at IS NULL',
        whereArgs: [JournalEntry.dayStart(day).millisecondsSinceEpoch],
        orderBy: 'created_at DESC, id DESC',
      ));

  Future<JournalEntry?> byDay(DateTime day) async {
    final rows = await db.query(table,
        where: 'entry_date = ? AND deleted_at IS NULL',
        whereArgs: [JournalEntry.dayStart(day).millisecondsSinceEpoch],
        orderBy: 'created_at DESC, id DESC',
        limit: 1);
    if (rows.isEmpty) return null;
    return (await _withTags([fromRow(rows.first)])).first;
  }

  Future<JournalEntry?> byId(int id) async {
    final rows = await db.query(table,
        where: 'id = ? AND deleted_at IS NULL', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return (await _withTags([fromRow(rows.first)])).first;
  }

  /// 区间 [from, to)（月历色条用）。
  Future<List<JournalEntry>> range(DateTime from, DateTime to) => _tagged(db.query(
        table,
        where: 'entry_date >= ? AND entry_date < ? AND deleted_at IS NULL',
        whereArgs: [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
        orderBy: 'entry_date ASC',
      ));

  /// UI/流畅批（2026-10-12）· 关键词搜索（新→旧）：正文（自由书写=Delta JSON，
  /// 中文按字面存即可命中）＋ 结构化分节 body（EXISTS 子查询）。
  /// 对齐 note_dao.list(query:) 的 LIKE 口径；篇目无标题列，展示侧用日期。
  Future<List<JournalEntry>> search(String query) => _tagged(db.query(
        table,
        where:
            '(content LIKE ? OR EXISTS (SELECT 1 FROM ${DbSchema.tJournalSections} s'
            ' WHERE s.entry_id = $table.id AND s.body LIKE ?)) AND deleted_at IS NULL',
        whereArgs: ['%$query%', '%$query%'],
        orderBy: 'entry_date DESC, created_at DESC, id DESC',
      ));

  /// 查询 → 条目列表 → 标签真源覆盖（所有读路径统一走这一条）。
  Future<List<JournalEntry>> _tagged(
          Future<List<Map<String, Object?>>> query) async =>
      _withTags((await query).map(fromRow).toList());

  /// 标签真源覆盖（批2b）。
  ///
  /// `journal_entries.tags` 列自 v50 起**降级为快照**：关联表有该篇行就以
  /// `tag_links`（按 id 引用）为准，否则回落到列内 JSON（老库尚未懒导入时的兜底）。
  ///
  /// 为什么不在 SQL 里 JOIN：一篇可挂多标签，JOIN 会把行数乘开再要调用方聚合；
  /// 一次 IN 查询 + 内存归并更省，也让「回收站/搜索」等所有读路径共用同一处口径
  /// （分两份写过一次就会出「列表有标签、回收站没有」）。
  Future<List<JournalEntry>> _withTags(List<JournalEntry> list) async {
    if (list.isEmpty) return list;
    final ids = [for (final e in list) if (e.id != null) e.id!];
    if (ids.isEmpty) return list;
    final holes = List.filled(ids.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT l.item_id i, t.name n FROM ${DbSchema.tTagLinks} l'
      ' JOIN ${DbSchema.tTags} t ON t.id = l.tag_id'
      " WHERE l.module = 'diary' AND l.item_id IN ($holes) ORDER BY t.sort, t.id",
      ids,
    );
    final map = <int, List<String>>{};
    for (final r in rows) {
      map.putIfAbsent(r['i'] as int, () => []).add(r['n'] as String);
    }
    if (map.isEmpty) return list;
    return [
      for (final e in list)
        if (e.id != null && map.containsKey(e.id)) e.copyWith(tags: map[e.id]) else e,
    ];
  }

  Future<int> insert(JournalEntry e) => db.insert(table, e.toRow());

  /// 篇的分节（按 idx 升序）。
  Future<List<DiarySection>> sectionsOf(int entryId) async => (await db.query(
        DbSchema.tJournalSections,
        where: 'entry_id = ?',
        whereArgs: [entryId],
        orderBy: 'idx ASC',
      ))
          .map((r) => DiarySection(
              title: r['title'] as String, body: (r['body'] as String?) ?? ''))
          .toList();

  /// 重写分节（delete + insert，随保存调用）。
  Future<void> replaceSections(
      int entryId, List<DiarySection> secs, int nowMs) async {
    final batch = db.batch();
    batch.delete(DbSchema.tJournalSections,
        where: 'entry_id = ?', whereArgs: [entryId]);
    for (var i = 0; i < secs.length; i++) {
      batch.insert(DbSchema.tJournalSections, {
        'entry_id': entryId,
        'idx': i,
        'title': secs[i].title,
        'body': secs[i].body,
        'updated_at': nowMs,
      });
    }
    await batch.commit(noResult: true);
  }

  /// 条目 + 分节装配（结构化篇渲染/编辑用）。
  Future<JournalEntry?> hydrate(JournalEntry e) async {
    if (e.templateId == null) return e;
    final secs = await sectionsOf(e.id!);
    return e.copyWith(sections: secs);
  }

  Future<void> updateById(int id, Map<String, Object?> values) =>
      db.update(table, values, where: 'id = ?', whereArgs: [id]);

  /// 轮13 → 语义断链批（2026-10-12）：remove 改软删（回收站第八类）。
  /// 分节行不删（随父行判在册）；图片文件保留（恢复零损耗）。
  Future<void> softDelete(int id) => updateById(
      id, {'deleted_at': DateTime.now().millisecondsSinceEpoch});

  Future<void> softDeleteMany(List<int> ids) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final id in ids) {
      batch.update(table, {'deleted_at': now},
          where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> restore(int id) =>
      updateById(id, {'deleted_at': null});

  /// 垃圾箱行（新→旧·含分节装配供连带读数）。
  Future<List<JournalEntry>> trash() => _tagged(db.query(table,
      where: 'deleted_at IS NOT NULL', orderBy: 'deleted_at DESC, id DESC'));

  /// 彻底删除＝真 DELETE（分节连带清）。返回连带分节行数供回执读数。
  Future<int> purge(int id) async {
    final secs = await db.query(DbSchema.tJournalSections,
        where: 'entry_id = ?', whereArgs: [id]);
    await _hardRemove(id); // 分节+主行连删（原硬删路径复用）
    return secs.length;
  }

  /// 真删（仅彻底删除/到期清理内部用；业务侧删除一律走软删）。
  /// 批2b：标签关联一并清（软删**不清**——回收站恢复后标签要跟着回来）。
  Future<void> _hardRemove(int id) async {
    await db.delete(DbSchema.tJournalSections,
        where: 'entry_id = ?', whereArgs: [id]);
    await db.delete(DbSchema.tTagLinks,
        where: "module = 'diary' AND item_id = ?", whereArgs: [id]);
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  /// 冷启动到期清理（回收站档位同源）。返回清除篇数。
  Future<int> purgeExpired(int keepDays) async {
    final cutoff =
        DateTime.now().subtract(Duration(days: keepDays)).millisecondsSinceEpoch;
    final rows = await db.query(table,
        columns: ['id'],
        where: 'deleted_at IS NOT NULL AND deleted_at <= ?',
        whereArgs: [cutoff]);
    for (final r in rows) {
      await _hardRemove(r['id'] as int);
    }
    return rows.length;
  }

  Future<void> setFlags(int id, {bool? starred, bool? liked}) => updateById(id, {
        if (starred != null) 'starred': starred ? 1 : 0,
        if (liked != null) 'liked': liked ? 1 : 0,
      });

  Future<void> incView(int id) => db.rawUpdate(
        'UPDATE $table SET view_count = view_count + 1 WHERE id = ?',
        [id],
      );

  /// 有内容的自然日毫秒列表（连续天数计算，倒序）。
  Future<List<int>> activeDays() async =>
      (await db.rawQuery(
              "SELECT entry_date d FROM $table WHERE deleted_at IS NULL AND (content != '' OR mood IS NOT NULL) ORDER BY d DESC"))
          .map((r) => r['d'] as int)
          .toList();
}
