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
  /// V1.57 E 批红线：垃圾箱条目（deleted_at 非空）不得出现在任何在册查询里。
  Future<List<Todo>> list() async {
    final manual = await _maxSort();
    final rows = await db.query(
      table,
      where: 'deleted_at IS NULL',
      // 次级键 id 兜底：同毫秒 updated_at 并列时保持新在前（确定性，防抖动）。
      orderBy: manual > 0
          ? 'done ASC, sort_order ASC, id ASC'
          : 'done ASC, due_at IS NULL, due_at ASC, updated_at DESC, id DESC',
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

  // ---- V1.57 E 批 · 待办垃圾箱（软删/恢复/彻底删除/到期自动清理） ----

  /// 软删：置 deleted_at=now（进垃圾箱）；不动 done/quadrant/due 等既有行数据。
  Future<void> softRemove(int id) => db.update(
        table,
        {
          'deleted_at': DateTime.now().millisecondsSinceEpoch,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

  /// 垃圾箱清单（删得晚的在前）。
  Future<List<Todo>> trashed() async {
    final rows = await db.query(table,
        where: 'deleted_at IS NOT NULL', orderBy: 'deleted_at DESC, id DESC');
    return rows.map(fromRow).toList();
  }

  /// 恢复＝置 deleted_at=NULL，**回原象限原截止**（不新建条目、不改其它列）。
  Future<void> restore(int id) => db.update(
        table,
        {
          'deleted_at': null,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

  /// 彻底删除（真 DELETE·不可恢复）；返回删除条数。
  Future<int> purge(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final marks = List.filled(ids.length, '?').join(',');
    return db.delete(table, where: 'id IN ($marks)', whereArgs: ids);
  }

  /// 到期自动清理：删早于保留期的垃圾箱条目；[keepDays]<=0＝不清理。返回删除数。
  Future<int> purgeExpired(int keepDays) {
    if (keepDays <= 0) return Future.value(0);
    final cutoff =
        DateTime.now().subtract(Duration(days: keepDays)).millisecondsSinceEpoch;
    return db.delete(table,
        where: 'deleted_at IS NOT NULL AND deleted_at < ?', whereArgs: [cutoff]);
  }

  /// 逾期计数（与 [Todo.overdue] 同口径：按自然日，截止日当天不算逾期）。
  Future<int> countOverdue() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final rows = await db.rawQuery(
        'SELECT COUNT(*) c FROM $table WHERE done = 0 AND due_at IS NOT NULL AND due_at < ? AND deleted_at IS NULL',
        [todayStart]);
    return (rows.first['c'] as int?) ?? 0;
  }
}
