import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../domain/note_folder.dart';

/// note_folders 表数据访问（V1.29 批A1）：多层嵌套文件夹树管理。
class NoteFolderDao {
  NoteFolderDao(this.db);

  final Database db;

  String get table => DbSchema.tNoteFolders;

  Future<List<NoteFolder>> list() async => (await db
          .query(table, orderBy: 'sort, id'))
      .map(NoteFolder.fromRow)
      .toList();

  /// 在 [parentId]（null=顶层）下新建；同级 sort 顺延。
  Future<NoteFolder> create(String name, {int? parentId}) async {
    final maxSort = await db.rawQuery(
        'SELECT COALESCE(MAX(sort), 0) m FROM $table WHERE '
        '${parentId == null ? 'parent_id IS NULL' : 'parent_id = ?'}',
        parentId == null ? null : [parentId]);
    final f = NoteFolder(
        name: name.trim(), parentId: parentId, sort: (maxSort.first['m'] as int) + 1);
    final id = await db.insert(table, f.toRow());
    return f.copyWithId(id);
  }

  Future<void> rename(int id, String name) => db.update(table,
      {'name': name.trim()},
      where: 'id = ?', whereArgs: [id]);

  /// 移动到另一父级（null=顶层；防环由调用层保证：target 不是自身/后代）。
  Future<void> move(int id, int? parentId) => db.update(
      table, {'parent_id': parentId}, where: 'id = ?', whereArgs: [id]);

  /// 删除文件夹：子夹整体上移到其父级，夹内笔记 folder 置空（无分类），不删笔记。
  /// V1.64 批1（拍板 F）：固定「系统打开」夹不可删——它是 N-4 历史列表的载体，
  /// 删除请求按无操作吞掉（入口侧本不该给这枚节点删钮，此处为 DAO 层兜底守卫）。
  Future<void> deleteTree(int id) async {
    final row = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (row.isEmpty) return;
    if ((row.first['name'] as String?) == kSystemOpenFolder) return;
    final parentId = row.first['parent_id'] as int?;
    await db.update(table, {'parent_id': parentId},
        where: 'parent_id = ?', whereArgs: [id]);
    final names = (await db.query(table, columns: ['name'], where: 'id = ?', whereArgs: [id]))
        .map((r) => r['name'] as String)
        .toList();
    if (names.isNotEmpty) {
      await db.update(DbSchema.tNotes, {'folder': null},
          where: 'folder = ?', whereArgs: [names.first]);
    }
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  /// 某文件夹（含全部后代）的名字集合；用于「选中目录=看该目录及子目录」过滤。
  Future<Set<String>> subtreeNames(int id) async {
    final all = await list();
    final byParent = <int?, List<NoteFolder>>{};
    for (final f in all) {
      byParent.putIfAbsent(f.parentId, () => []).add(f);
    }
    final root = all.where((f) => f.id == id).firstOrNull;
    if (root == null) return {};
    final out = <String>{root.name};
    final queue = [root];
    while (queue.isNotEmpty) {
      final cur = queue.removeLast();
      for (final k in byParent[cur.id] ?? const <NoteFolder>[]) {
        out.add(k.name);
        queue.add(k);
      }
    }
    return out;
  }

  /// 组装渲染树（纯函数：仅从顶层向下遍历，孤儿节点自然被忽略）。
  static List<FolderNode> buildTree(List<NoteFolder> all,
      {Map<String, int> noteCounts = const {}}) {
    final byParent = <int?, List<NoteFolder>>{};
    for (final f in all) {
      byParent.putIfAbsent(f.parentId, () => []).add(f);
    }
    List<FolderNode> build(int? pid) => (byParent[pid] ?? const <NoteFolder>[])
        .map((f) => FolderNode(
            folder: f,
            children: build(f.id),
            noteCount: noteCounts[f.name] ?? 0))
        .toList();
    return build(null);
  }
}

extension on NoteFolder {
  NoteFolder copyWithId(int id) =>
      NoteFolder(id: id, name: name, parentId: parentId, sort: sort);
}
