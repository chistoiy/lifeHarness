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
  Future<List<JournalEntry>> list() async => (await db
          .query(table, orderBy: 'entry_date DESC, created_at DESC, id DESC'))
      .map(fromRow)
      .toList();

  /// 当日全部篇（新→旧）。
  Future<List<JournalEntry>> listByDay(DateTime day) async => (await db.query(
        table,
        where: 'entry_date = ?',
        whereArgs: [JournalEntry.dayStart(day).millisecondsSinceEpoch],
        orderBy: 'created_at DESC, id DESC',
      ))
          .map(fromRow)
          .toList();

  Future<JournalEntry?> byDay(DateTime day) async {
    final rows = await db.query(table,
        where: 'entry_date = ?',
        whereArgs: [JournalEntry.dayStart(day).millisecondsSinceEpoch],
        orderBy: 'created_at DESC, id DESC',
        limit: 1);
    return rows.isEmpty ? null : fromRow(rows.first);
  }

  Future<JournalEntry?> byId(int id) async {
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : fromRow(rows.first);
  }

  /// 区间 [from, to)（月历色条用）。
  Future<List<JournalEntry>> range(DateTime from, DateTime to) async => (await db.query(
        table,
        where: 'entry_date >= ? AND entry_date < ?',
        whereArgs: [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
        orderBy: 'entry_date ASC',
      ))
      .map(fromRow)
      .toList();

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
              "SELECT entry_date d FROM $table WHERE content != '' OR mood IS NOT NULL ORDER BY d DESC"))
          .map((r) => r['d'] as int)
          .toList();
}
