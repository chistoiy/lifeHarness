import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../domain/todo.dart';

/// todos 表数据访问对象。
class TodoDao {
  TodoDao(this.db);

  final Database db;

  String get table => DbSchema.tTodos;

  Todo fromRow(Map<String, Object?> row) => Todo.fromRow(row);

  /// 未完成在前；未手动排序=智能序（逾期/近到期优先，已完成按更新倒序沉底）；
  /// 一旦存在手动排序（V1.27 T6 长按拖拽写入 sort_order>0）→ 组内按用户序。
  Future<List<Todo>> list() async {
    final manual = await _maxSort() > 0;
    final rows = await db.query(
      table,
      orderBy: manual
          ? 'done ASC, sort_order ASC'
          : 'done ASC, due_at IS NULL, due_at ASC, updated_at DESC',
    );
    return rows.map(fromRow).toList();
  }

  Future<int> _maxSort() async {
    final r = await db
        .rawQuery('SELECT COALESCE(MAX(sort_order),0) m FROM $table');
    return (r.first['m'] as int?) ?? 0;
  }

  Future<Todo> insert(Todo t) async {
    var row = t.toRow();
    if (t.sortOrder == 0) {
      final max = await _maxSort();
      if (max > 0) row['sort_order'] = max + 1; // 手动序存在时新任务追加尾位
    }
    final id = await db.insert(table, row);
    return t.copyWith(id: id, sortOrder: row['sort_order'] as int?);
  }

  /// 长按拖拽排序落库：按当前展示序写 1..n（全表统一手动序）。
  Future<void> reorder(List<int> ids) async {
    await db.transaction((txn) async {
      for (var i = 0; i < ids.length; i++) {
        await txn.update(table, {'sort_order': i + 1},
            where: 'id = ?', whereArgs: [ids[i]]);
      }
    });
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
