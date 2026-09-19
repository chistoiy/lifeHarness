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

  Future<void> remove(int id) => db.delete(table, where: 'id = ?', whereArgs: [id]);

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
}
