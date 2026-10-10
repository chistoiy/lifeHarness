import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../domain/note.dart';

/// 排序（V1.29轮6 原型三方式：最后修改↓ / 创建时间↓ / 标题 A→Z）。
enum NoteSort { updated, created, title }

/// notes 表数据访问（M1 批1：列表/搜索/管理 + 版本快照）。
class NoteDao {
  NoteDao(this.db);

  final Database db;

  String get table => DbSchema.tNotes;

  /// 活跃列表（排除归档与回收站）：置顶优先，按排序模式。
  /// asc=轮8④ 方向翻转（默认降序；title 默认 A→Z）。
  Future<List<Note>> list({
    String? folder,
    String? query,
    NoteSort sort = NoteSort.updated,
    bool asc = false,
  }) async {
    final where = <String>['archived = 0', 'deleted_at IS NULL'];
    final args = <Object?>[];
    if (folder != null && folder.isNotEmpty) {
      where.add('folder = ?');
      args.add(folder);
    }
    if (query != null && query.isNotEmpty) {
      where.add('(title LIKE ? OR content LIKE ?)');
      args.addAll(['%$query%', '%$query%']);
    }
    final dir = asc ? 'ASC' : 'DESC';
    final order = switch (sort) {
      NoteSort.updated => 'pinned DESC, updated_at $dir',
      NoteSort.created => 'pinned DESC, created_at $dir',
      // V1.29轮6：标题 A→Z（英文不区分大小写；中文按码位近似笔画序）
      // 轮8④：翻转=A→Z⇄Z→A（asc 时 DESC）
      NoteSort.title =>
        'pinned DESC, title COLLATE NOCASE ${asc ? 'DESC' : 'ASC'}',
    };
    return (await db.query(table,
            where: where.join(' AND '), whereArgs: args, orderBy: order))
        .map(Note.fromRow)
        .toList();
  }

  /// 回收站（进回收站时间倒序）。
  Future<List<Note>> trash() async => (await db.query(table,
          where: 'deleted_at IS NOT NULL', orderBy: 'deleted_at DESC'))
      .map(Note.fromRow)
      .toList();

  /// 归档列表。
  Future<List<Note>> archived() async => (await db.query(table,
          where: 'archived = 1 AND deleted_at IS NULL',
          orderBy: 'updated_at DESC'))
      .map(Note.fromRow)
      .toList();

  /// 已用文件夹名（chips 行）。
  Future<List<String>> folders() async {
    final rows = await db.rawQuery(
        'SELECT DISTINCT folder FROM $table WHERE folder IS NOT NULL AND folder != \'\' AND archived = 0 AND deleted_at IS NULL ORDER BY folder');
    return rows.map((r) => r['folder'] as String).toList();
  }

  /// 各文件夹活跃笔记数（树抽屉节点计数）。
  Future<Map<String, int>> folderCounts() async {
    final rows = await db.rawQuery(
        'SELECT folder, COUNT(*) c FROM $table WHERE folder IS NOT NULL AND folder != \'\' '
        'AND archived = 0 AND deleted_at IS NULL GROUP BY folder');
    return {for (final r in rows) r['folder'] as String: r['c'] as int};
  }

  Future<Note?> byId(int id) async {
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Note.fromRow(rows.first);
  }

  /// V1.64 批1 N-3（拍板 C）：同名文件二次打开＝按原始 URI 找回在册条目覆盖更新。
  /// E 批红线＝回收站行不参与判重（deleted_at IS NULL）。
  Future<Note?> byOriginUri(String uri) async {
    if (uri.isEmpty) return null;
    final rows = await db.query(table,
        where: 'origin_uri = ? AND deleted_at IS NULL',
        whereArgs: [uri],
        limit: 1);
    return rows.isEmpty ? null : Note.fromRow(rows.first);
  }

  Future<int> insert(Note n) => db.insert(table, n.toRow());

  Future<Note> save(Note n) async {
    if (n.id == null) {
      final id = await insert(n);
      return n.copyWith(id: id);
    }
    await db.update(table, n.toRow()..remove('id'),
        where: 'id = ?', whereArgs: [n.id]);
    return n;
  }

  Future<void> setPinned(int id, bool pinned) => db.update(
      table, {'pinned': pinned ? 1 : 0, 'updated_at': _now()},
      where: 'id = ?', whereArgs: [id]);

  Future<void> setArchived(int id, bool archived) => db.update(table,
      {'archived': archived ? 1 : 0, 'updated_at': _now()},
      where: 'id = ?', whereArgs: [id]);

  // ---- V1.29批A3：批量选择操作（置顶 / 移动到 / 删除） ----

  String _ph(List<int> ids) => ids.map((_) => '?').join(',');

  Future<void> setPinnedMany(List<int> ids, bool pinned) => db.transaction((txn) async {
        for (final id in ids) {
          await txn.update(table, {'pinned': pinned ? 1 : 0, 'updated_at': _now()},
              where: 'id = ?', whereArgs: [id]);
        }
      });

  Future<void> setFolderMany(List<int> ids, String? folder) => db.update(table,
      {'folder': folder?.isEmpty == true ? null : folder, 'updated_at': _now()},
      where: 'id IN (${_ph(ids)})', whereArgs: ids);

  Future<void> softDeleteMany(List<int> ids) => db.update(table,
      {'deleted_at': _now(), 'updated_at': _now()},
      where: 'id IN (${_ph(ids)})', whereArgs: ids);

  /// 进回收站（软删）。
  Future<void> softDelete(int id) => db.update(table,
      {'deleted_at': _now(), 'updated_at': _now()},
      where: 'id = ?', whereArgs: [id]);

  Future<void> restore(int id) =>
      db.update(table, {'deleted_at': null}, where: 'id = ?', whereArgs: [id]);

  /// 回收站内彻底删除（连带快照）。
  Future<void> purge(int id) async {
    await db.delete(DbSchema.tNoteSnapshots,
        where: 'note_id = ?', whereArgs: [id]);
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> emptyTrash() async {
    final ids = (await db.query(table,
            columns: ['id'], where: 'deleted_at IS NOT NULL'))
        .map((r) => r['id'] as int)
        .toList();
    if (ids.isEmpty) return;
    final ph = ids.map((_) => '?').join(',');
    await db.delete(DbSchema.tNoteSnapshots,
        where: 'note_id IN ($ph)', whereArgs: ids);
    await db.delete(table, where: 'id IN ($ph)', whereArgs: ids);
  }

  /// V1.60 到期自动清理：真删早于保留期的回收站笔记（连带快照）。
  /// [keepDays]<=0＝不清理。返回删除条数。
  Future<int> purgeExpired(int keepDays) async {
    if (keepDays <= 0) return 0;
    final cutoff =
        DateTime.now().subtract(Duration(days: keepDays)).millisecondsSinceEpoch;
    final ids = (await db.query(table,
            columns: ['id'],
            where: 'deleted_at IS NOT NULL AND deleted_at < ?',
            whereArgs: [cutoff]))
        .map((r) => r['id'] as int)
        .toList();
    if (ids.isEmpty) return 0;
    final ph = ids.map((_) => '?').join(',');
    await db.delete(DbSchema.tNoteSnapshots,
        where: 'note_id IN ($ph)', whereArgs: ids);
    await db.delete(table, where: 'id IN ($ph)', whereArgs: ids);
    return ids.length;
  }

  // ---- 版本快照（1d 使用；表与写入通道先建好） ----

  Future<void> snapshot(int noteId, String content) =>
      db.insert(DbSchema.tNoteSnapshots, {
        'note_id': noteId,
        'content': content,
        'created_at': _now(),
      });

  Future<List<Map<String, Object?>>> snapshotsOf(int noteId) => db.query(
      DbSchema.tNoteSnapshots,
      where: 'note_id = ?', whereArgs: [noteId], orderBy: 'created_at DESC');

  static int _now() => DateTime.now().millisecondsSinceEpoch;
}
