import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../domain/mindmap_models.dart';

/// 思维导图 DAO（批1）。扁平表口径：整图一次 `WHERE map_id=?` 拉平，
/// 树关系在内存里由 `parentId` 组装（数据层三条：不 JOIN、sort 显式序、复合索引）。
///
/// 回收站口径（第九类）：删图＝图行软删（`deleted_at`），节点行不动——
/// 恢复只清图行标记即「带全节点回原位」（B7）；**彻底删除**才级联
/// `DELETE FROM mindmap_nodes WHERE map_id=?`（登记式接口无自动级联，
/// 与 book→quote、journal→分节同类，守护＝trash_guard_test 第九类点名）。
class MindmapDao {
  MindmapDao(this.db);

  final Database db;

  static const String _maps = DbSchema.tMindmaps;
  static const String _nodes = DbSchema.tMindmapNodes;

  // ==================== 图 ====================

  /// 在册图列表（含节点数副信息），按更新时间倒序。
  Future<List<(Mindmap, int)>> listLive() async {
    final rows = await db.query(_maps,
        where: 'deleted_at IS NULL', orderBy: 'updated_at DESC');
    final out = <(Mindmap, int)>[];
    for (final row in rows) {
      final m = Mindmap.fromRow(row);
      final cnt = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $_nodes WHERE map_id = ?',
                [m.id]),
          ) ??
          0;
      out.add((m, cnt));
    }
    return out;
  }

  Future<Mindmap?> mapById(int id) async {
    final rows = await db.query(_maps, where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Mindmap.fromRow(rows.first);
  }

  /// 新建图（三起点：空白/md 解析/收集箱导入都经这里；节点随后逐条插入）。
  Future<int> createMap(String title, {int? now}) async {
    final t = now ?? DateTime.now().millisecondsSinceEpoch;
    return db.insert(_maps, {
      'title': title,
      'created_at': t,
      'updated_at': t,
    });
  }

  Future<void> renameMap(int id, String title) => _touchMap(id, {'title': title});

  /// 删图进回收站（软删图行；节点不动）。
  Future<void> trashMap(int id) => _touchMap(id, {'deleted_at': _now()});

  /// 恢复（回原位；节点行从未动过＝级联语义的恢复侧）。
  Future<void> restoreMap(int id) async {
    await db.update(_maps, {'deleted_at': null}, where: 'id = ?', whereArgs: [id]);
    await _touchMap(id, null);
  }

  /// 彻底删除：图行＋**全部节点行**级联真 DELETE。返回级联节点数。
  Future<int> purgeMap(int id) async {
    final n = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM $_nodes WHERE map_id = ?', [id])) ??
        0;
    await db.delete(_nodes, where: 'map_id = ?', whereArgs: [id]);
    await db.delete(_maps, where: 'id = ?', whereArgs: [id]);
    return n;
  }

  /// 到期清理（回收站自动清理档位），返回清除图数（连带节点级联）。
  Future<int> purgeExpired(int keepDays) async {
    if (keepDays <= 0) return 0;
    final horizon = _now() - keepDays * 86400000;
    final rows = await db.query(_maps,
        columns: ['id'],
        where: 'deleted_at IS NOT NULL AND deleted_at <= ?',
        whereArgs: [horizon]);
    for (final r in rows) {
      await purgeMap(r['id'] as int);
    }
    return rows.length;
  }

  Future<List<Mindmap>> trashed() async {
    final rows = await db.query(_maps,
        where: 'deleted_at IS NOT NULL', orderBy: 'deleted_at DESC');
    return rows.map(Mindmap.fromRow).toList();
  }

  /// 复制图：连同全部节点与挂载引用复制，标题「原名 副本」（F2-3）。
  Future<int> copyMap(int id) async {
    final src = await mapById(id);
    if (src == null) throw StateError('导图不存在：$id');
    final newId = await createMap('${src.title} 副本');
    final nodes = await nodesOf(id);
    // 旧 id → 新 id 映射：先插全部行拿新键，再按映射补 parent_id（两趟，防父子错挂）。
    final idMap = <int, int>{};
    final t = _now();
    for (final n in nodes) {
      final nid = await db.insert(_nodes, {
        'map_id': newId,
        'parent_id': null, // 第二趟补
        'note_id': n.noteId,
        'title': n.title,
        'note': n.note,
        'side': n.side,
        'sort': n.sort,
        'dx': n.dx,
        'dy': n.dy,
        'folded': n.folded ? 1 : 0,
        'created_at': t,
        'updated_at': t,
      });
      if (n.id != null) idMap[n.id!] = nid;
    }
    for (final n in nodes) {
      if (n.parentId != null) {
        final newParent = idMap[n.parentId!];
        if (newParent != null) {
          await db.update(_nodes, {'parent_id': newParent},
              where: 'id = ?', whereArgs: [idMap[n.id!]]);
        }
      }
    }
    await _touchMap(newId, null);
    return newId;
  }

  // ==================== 节点 ====================

  /// 整图节点（拉平，树组装在调用侧）。
  Future<List<MindmapNode>> nodesOf(int mapId) async {
    final rows = await db.query(_nodes,
        where: 'map_id = ?', whereArgs: [mapId], orderBy: 'sort ASC, id ASC');
    return rows.map(MindmapNode.fromRow).toList();
  }

  Future<MindmapNode?> nodeById(int id) async {
    final rows = await db.query(_nodes, where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : MindmapNode.fromRow(rows.first);
  }

  /// 加节点（加子/加同级/加根共用；根＝parentId null）。返回新节点。
  /// `sort` 取兄弟末尾递增（F1-5）。
  Future<MindmapNode> addNode({
    required int mapId,
    int? parentId,
    int? noteId,
    required String title,
    String note = '',
    String? side,
  }) async {
    final sort = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT MAX(sort) FROM $_nodes WHERE map_id = ? AND parent_id IS ?',
            [mapId, parentId])) ??
        -1;
    final t = _now();
    final id = await db.insert(_nodes, {
      'map_id': mapId,
      'parent_id': parentId,
      'note_id': noteId,
      'title': title,
      'note': note,
      'side': side,
      'sort': sort + 1,
      'dx': 0,
      'dy': 0,
      'folded': 0,
      'created_at': t,
      'updated_at': t,
    });
    await _touchMap(mapId, null);
    return (await nodeById(id))!;
  }

  /// 通用节点更新（编辑标题备注/折叠/偏移/挂载/换序全走这里）。
  Future<void> updateNode(MindmapNode n, {int? mapIdForTouch}) =>
      db.update(
        _nodes,
        {
          'parent_id': n.parentId,
          'note_id': n.noteId,
          'title': n.title,
          'note': n.note,
          'side': n.side,
          'sort': n.sort,
          'dx': n.dx,
          'dy': n.dy,
          'folded': n.folded ? 1 : 0,
          'updated_at': _now(),
        },
        where: 'id = ?',
        whereArgs: [n.id],
      ).then((_) => _touchMap(mapIdForTouch ?? n.mapId, null));

  /// 节点及其全部后代 id 集（删除确认读数与级联删除共用一份算法）。
  Future<Set<int>> descendantIdsOf(int id) async {
    final all = await db.query(_nodes, columns: ['id', 'parent_id']);
    final children = <int, List<int>>{};
    for (final r in all) {
      final p = r['parent_id'] as int?;
      if (p != null) children.putIfAbsent(p, () => []).add(r['id'] as int);
    }
    final out = <int>{id};
    final stack = <int>[id];
    while (stack.isNotEmpty) {
      for (final c in children[stack.removeLast()] ?? const <int>[]) {
        if (out.add(c)) stack.add(c);
      }
    }
    return out;
  }

  /// 删节点（含全部后代；画布侧二次确认后调用）。返回连带子级数。
  Future<int> deleteNodeCascade(int id) async {
    final ids = await descendantIdsOf(id);
    final childCount = ids.length - 1;
    await db.delete(_nodes, where: 'id IN (${List.filled(ids.length, '?').join(',')})',
        whereArgs: ids.toList());
    return childCount;
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;

  Future<void> _touchMap(int id, Map<String, Object?>? extra) =>
      db.update(_maps, {...?extra, 'updated_at': _now()},
          where: 'id = ?', whereArgs: [id]);
}
