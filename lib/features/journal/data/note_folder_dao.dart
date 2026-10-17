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
  /// V1.64 批2：[source]/[originPath]/[originUri] 建挂载夹时落值（手建夹一律默认空）。
  Future<NoteFolder> create(String name,
      {int? parentId,
      String source = '',
      String originPath = '',
      String originUri = ''}) async {
    final maxSort = await db.rawQuery(
        'SELECT COALESCE(MAX(sort), 0) m FROM $table WHERE '
        '${parentId == null ? 'parent_id IS NULL' : 'parent_id = ?'}',
        parentId == null ? null : [parentId]);
    final f = NoteFolder(
        name: name.trim(),
        parentId: parentId,
        sort: (maxSort.first['m'] as int) + 1,
        source: source,
        originPath: originPath,
        originUri: originUri);
    final id = await db.insert(table, f.toRow());
    return f.copyWithId(id);
  }

  Future<void> rename(int id, String name) => db.update(table,
      {'name': name.trim()},
      where: 'id = ?', whereArgs: [id]);

  /// V1.64 批2：把既有夹标成挂载夹（本地导入命中同名手建夹时用）；只动来源三列。
  Future<void> setMount(int id,
          {required String source,
          String originUri = '',
          String originPath = ''}) =>
      db.update(table, {
        'source': source,
        if (originUri.isNotEmpty) 'origin_uri': originUri,
        if (originPath.isNotEmpty) 'origin_path': originPath,
      }, where: 'id = ?', whereArgs: [id]);

  /// 移动到另一父级（null=顶层；防环由调用层保证：target 不是自身/后代）。
  Future<void> move(int id, int? parentId) => db.update(
      table, {'parent_id': parentId}, where: 'id = ?', whereArgs: [id]);

  /// 删除文件夹：子夹整体上移到其父级，夹内笔记 folder 置空（无分类），不删笔记。
  /// V1.64 批1（拍板 F）：固定「系统打开」夹不可删——它是 N-4 历史列表的载体。
  /// 批2 改返回布尔（原为静默吞掉＝「点了没反应」）：入口侧据此出一行人话提示。
  Future<bool> deleteTree(int id) async {
    final row = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (row.isEmpty) return false;
    if ((row.first['name'] as String?) == kSystemOpenFolder) return false;
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
    return true;
  }

  /// 按名找回在册夹（notes.folder 按名匹配＝本表既有模型；导入侧同名一律复用）。
  Future<NoteFolder?> byName(String name) async {
    final rows = await db
        .query(table, where: 'name = ?', whereArgs: [name.trim()], limit: 1);
    return rows.isEmpty ? null : NoteFolder.fromRow(rows.first);
  }

  /// V1.67 默认归属：「默认」夹不存在则建（顶层·sort 顺延）。返回是否新建。
  /// 用户自建同名夹直接复用（byName 命中即不建）；幂等可随保存路径高频调。
  Future<bool> ensureDefaultFolder() async {
    if (await byName(kDefaultNoteFolder) != null) return false;
    await create(kDefaultNoteFolder);
    return true;
  }

  /// V1.67 默认归属兜底（树加载前调·幂等）：把散笔记（folder NULL/''·未删）归入
  /// 「默认」夹——产品令「所有笔记必须有目录归属」；删夹后重读树即重建归位。
  /// 零散笔记时零写入；返回是否有变更（建夹或归位）。
  Future<bool> ensureDefaultOwnership() async {
    final created = await ensureDefaultFolder();
    const cond = "(folder IS NULL OR folder = '') AND deleted_at IS NULL";
    // 谓词内联进语句文本（trash_guard 按语句文本判定，变量引用看不见谓词）。
    final rows = await db.rawQuery(
        "SELECT COUNT(*) c FROM ${DbSchema.tNotes} "
        "WHERE (folder IS NULL OR folder = '') AND deleted_at IS NULL");
    if ((rows.first['c'] as int) == 0) return created;
    await db.update(DbSchema.tNotes, {'folder': kDefaultNoteFolder},
        where: cond);
    return true;
  }

  /// V1.64 批2 N-1c（工单 §1.2 · 拍板 H＝保留在库）：**摘挂载**＝删本表这些行
  /// （连子夹一起摘），notes 一行不动、磁盘原件一行不动。与 [deleteTree] 的区别＝
  /// 后者是「删文件夹」语义（子夹上移＋夹内笔记归未归类），本口只服务挂载节点。
  /// 守卫：固定「系统打开」夹与非挂载夹一律拒绝（返回 false，不吞成假成功）。
  Future<bool> unmount(int id) async {
    final row = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (row.isEmpty) return false;
    final f = NoteFolder.fromRow(row.first);
    if (f.name == kSystemOpenFolder || !f.isMount) return false;
    final ids = await subtreeIds(id);
    final ph = ids.map((_) => '?').join(',');
    await db.delete(table, where: 'id IN ($ph)', whereArgs: ids);
    return true;
  }

  /// 自身＋全部后代 id（挂载移除的作用面；环防护＝已收集的不再下钻）。
  Future<List<int>> subtreeIds(int id) async {
    final all = await list();
    final byParent = <int?, List<NoteFolder>>{};
    for (final f in all) {
      byParent.putIfAbsent(f.parentId, () => []).add(f);
    }
    final out = <int>[id];
    final seen = <int>{id};
    final queue = [id];
    while (queue.isNotEmpty) {
      final cur = queue.removeLast();
      for (final k in byParent[cur] ?? const <NoteFolder>[]) {
        if (k.id == null || !seen.add(k.id!)) continue;
        out.add(k.id!);
        queue.add(k.id!);
      }
    }
    return out;
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
  /// 批2 起必须带上来源三列——首版只拷四字段，导致 create() 回对象丢挂载态
  /// （库里对、内存里错＝树上角标与长按分派拿到空 source）。
  NoteFolder copyWithId(int id) => NoteFolder(
      id: id,
      name: name,
      parentId: parentId,
      sort: sort,
      source: source,
      originPath: originPath,
      originUri: originUri);
}
