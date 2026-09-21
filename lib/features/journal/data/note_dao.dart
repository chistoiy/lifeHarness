import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../domain/note.dart';

/// 排序（原型 ↕：更新时间↓ / 创建时间 / 字数）。
enum NoteSort { updated, created, words }

/// notes 表数据访问（M1 批1：列表/搜索/管理 + 版本快照）。
class NoteDao {
  NoteDao(this.db);

  final Database db;

  String get table => DbSchema.tNotes;

  /// 活跃列表（排除归档与回收站）：置顶优先，按排序模式。
  Future<List<Note>> list({
    String? folder,
    String? query,
    NoteSort sort = NoteSort.updated,
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
    final order = switch (sort) {
      NoteSort.updated => 'pinned DESC, updated_at DESC',
      NoteSort.created => 'pinned DESC, created_at DESC',
      // 字数排序在应用层算（content 长度近似=字符数）
      NoteSort.words => 'pinned DESC, LENGTH(REPLACE(content, \' \', \'\')) DESC',
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
