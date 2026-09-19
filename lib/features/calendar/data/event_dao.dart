import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../domain/cal_event.dart';

/// events 表数据访问。
class EventDao {
  EventDao(this.db);

  final Database db;

  String get table => DbSchema.tEvents;

  Future<List<CalEvent>> listAll() async {
    final rows = await db.query(table, orderBy: 'start_at ASC');
    return rows.map(CalEvent.fromRow).toList();
  }

  Future<CalEvent?> activeOne() async {
    final rows = await db.query(table,
        where: 'status = ?', whereArgs: [EventStatus.active.index], limit: 1);
    return rows.isEmpty ? null : CalEvent.fromRow(rows.first);
  }

  Future<CalEvent> insert(CalEvent e) async {
    final id = await db.insert(table, e.toRow());
    return e.copyWith(id: id);
  }

  Future<void> update(CalEvent e) => db.update(
        table,
        e.toRow()..remove('id'),
        where: 'id = ?',
        whereArgs: [e.id],
      );

  Future<void> setStatus(int id, EventStatus s, {int? durationMin, DateTime? endAt}) =>
      db.update(
        table,
        {
          'status': s.index,
          'duration_min': ?durationMin,
          'end_at': endAt?.millisecondsSinceEpoch,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<void> remove(int id) => db.delete(table, where: 'id = ?', whereArgs: [id]);
}
