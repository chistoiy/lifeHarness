import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../domain/todo.dart';

/// todos 表数据访问对象。
class TodoDao {
  TodoDao(this.db);

  final Database db;

  String get table => DbSchema.tTodos;

  Todo fromRow(Map<String, Object?> row) => Todo.fromRow(row);

  /// 未完成在前（按到期升序），已完成沉底（按完成更新倒序）。
  Future<List<Todo>> list() async {
    final rows = await db.query(
      table,
      orderBy: 'done ASC, due_at IS NULL, due_at ASC, updated_at DESC',
    );
    return rows.map(fromRow).toList();
  }

  Future<Todo> insert(Todo t) async {
    final id = await db.insert(table, t.toRow());
    return t.copyWith(id: id);
  }

  Future<void> update(Todo t) => db.update(
        table,
        t.toRow()..remove('id'),
        where: 'id = ?',
        whereArgs: [t.id],
      );

  Future<void> setQuadrant(int id, Quadrant q) => db.update(
        table,
        {'quadrant': q.value, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<void> setDone(int id, bool done) => db.update(
        table,
        {'done': done ? 1 : 0, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<void> remove(int id) => db.delete(table, where: 'id = ?', whereArgs: [id]);

  /// 逾期计数（与 [Todo.overdue] 同口径：按自然日，截止日当天不算逾期）。
  Future<int> countOverdue() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final rows = await db
        .rawQuery('SELECT COUNT(*) c FROM $table WHERE done = 0 AND due_at IS NOT NULL AND due_at < ?', [todayStart]);
    return (rows.first['c'] as int?) ?? 0;
  }
}
