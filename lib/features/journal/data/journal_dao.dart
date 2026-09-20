import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../domain/journal_entry.dart';

/// journal_entries 表数据访问对象（一天一篇，按日 upsert）。
class JournalDao {
  JournalDao(this.db);

  final Database db;

  String get table => DbSchema.tJournal;

  JournalEntry fromRow(Map<String, Object?> row) => JournalEntry.fromRow(row);

  /// 全部条目（新→旧）。
  Future<List<JournalEntry>> list() async =>
      (await db.query(table, orderBy: 'entry_date DESC')).map(fromRow).toList();

  Future<JournalEntry?> byDay(DateTime day) async {
    final rows = await db.query(table,
        where: 'entry_date = ?', whereArgs: [JournalEntry.dayStart(day).millisecondsSinceEpoch], limit: 1);
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
