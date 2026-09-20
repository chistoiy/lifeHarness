import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../domain/time_block.dart';

/// time_blocks 表数据访问。
class TimeBlockDao {
  TimeBlockDao(this.db);

  final Database db;

  String get table => DbSchema.tTimeBlocks;

  Future<List<TimeBlock>> listByDay(DateTime day) async {
    final rows = await db.query(table,
        where: 'day = ?',
        whereArgs: [DateTime(day.year, day.month, day.day).millisecondsSinceEpoch],
        orderBy: 'start_min ASC');
    return rows.map(TimeBlock.fromRow).toList();
  }

  Future<TimeBlock> insert(TimeBlock b) async {
    final id = await db.insert(table, b.toRow());
    return TimeBlock.fromRow({...b.toRow(), 'id': id});
  }

  /// V1.27 C3：某月内有块的「日」集合（月历点=事件/块任一存在，四视图同一数据源）。
  Future<Set<int>> daysWithBlocks(int y, int m) async {
    final start = DateTime(y, m, 1).millisecondsSinceEpoch;
    final end = DateTime(y, m + 1, 1).millisecondsSinceEpoch;
    final rows = await db.rawQuery(
        'SELECT DISTINCT day FROM $table WHERE day >= ? AND day < ?',
        [start, end]);
    return rows
        .map((r) => DateTime.fromMillisecondsSinceEpoch(r['day'] as int).day)
        .toSet();
  }

  Future<void> remove(int id) => db.delete(table, where: 'id = ?', whereArgs: [id]);

  /// 速记接龙：上一段"记到此刻"块截止到新时刻。
  Future<void> updateEnd(int id, int endMin) => db.update(
      table, {'end_min': endMin, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?', whereArgs: [id]);

  /// 与日程事件区间重叠的标记块（事件回填时避免重复着色）。
  Future<void> removeOverlapping(DateTime day, int startMin, int endMin) =>
      db.delete(
        table,
        where:
            'day = ? AND source = ? AND start_min < ? AND end_min > ?',
        whereArgs: [
          DateTime(day.year, day.month, day.day).millisecondsSinceEpoch,
          'mark',
          endMin,
          startMin,
        ],
      );

  /// 选块即标记（V1.21）：交叠部分被新分类替换，原块非交叠段自动保留（拆分），
  /// 相邻同分类同备注块合并；仅作用于 source=mark，事件回填块不动。
  Future<void> markRange(DateTime day, int startMin, int endMin,
      {int? catId, String catName = '其他', String? note}) async {
    final dayMs = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final rows = await txn.query(table,
          where: 'day = ? AND source = ?',
          whereArgs: [dayMs, 'mark'],
          orderBy: 'start_min ASC');
      final keep = <TimeBlock>[];
      for (final b in rows.map(TimeBlock.fromRow)) {
        if (b.endMin <= startMin || b.startMin >= endMin) {
          keep.add(b.copyWith(id: b.id));
          continue;
        }
        if (b.startMin < startMin) {
          keep.add(TimeBlock(day: day, startMin: b.startMin, endMin: startMin,
              catId: b.catId, catName: b.catName, note: b.note, source: b.source, eventId: b.eventId));
        }
        if (b.endMin > endMin) {
          keep.add(TimeBlock(day: day, startMin: endMin, endMin: b.endMin,
              catId: b.catId, catName: b.catName, note: b.note, source: b.source, eventId: b.eventId));
        }
      }
      keep.add(TimeBlock(
          day: day, startMin: startMin, endMin: endMin, catId: catId, catName: catName, note: note));
      keep.sort((a, b) => a.startMin.compareTo(b.startMin));
      final merged = <TimeBlock>[];
      for (final b in keep) {
        if (merged.isNotEmpty) {
          final l = merged.last;
          if (l.catName == b.catName && l.note == b.note && l.endMin == b.startMin) {
            merged[merged.length - 1] = l.copyWith(endMin: b.endMin);
            continue;
          }
        }
        merged.add(b);
      }
      final batch = txn.batch()
        ..delete(table, where: 'day = ? AND source = ?', whereArgs: [dayMs, 'mark']);
      for (final b in merged) {
        batch.insert(table, b.toRow());
      }
      await batch.commit(noResult: true);
    });
  }
}
