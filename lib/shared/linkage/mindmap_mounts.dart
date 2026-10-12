import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/database/app_database.dart';
import '../../core/database/schema.dart';

/// 思维导图 ⇄ 笔记/收集箱 挂载出口（连接点①③④ · 批1 · 仿 search_mounts 惯例）。
///
/// mindmap feature **不直接 import** journal/inbox 域（架构守护 R1：
/// `features/mindmap/**` → `features/journal/**` 直连＝红），
/// 跨模块数据读写统一经本文件的函数出口。变异刀 2 钉此口径：
/// 摘掉本出口、把挂载改成 mindmap 直连笔记域，`architecture_test` R1 必红。
///
/// 口径（H3/C4 裁定）：节点只存笔记引用（`note_id`），显示标题**实时取笔记标题**
/// ——笔记改名节点跟着变；笔记删除（含回收站/彻底删）→ [mmNoteTitleOf] 返回 null，
/// 节点保留并显示「（已删除的笔记）」占位、不崩（B6），双击置灰无响应。

/// 可挂载笔记引用（id + 当前标题）。
class MmNoteRef {
  const MmNoteRef({required this.id, required this.title});
  final int id;
  final String title;
}

/// 在册笔记（未删未归档），按更新时间倒序——挂载弹层与 md 起点共用一份读法。
Future<List<MmNoteRef>> mmMountableNotes([Database? db]) async {
  final d = db ?? AppDatabase.instance.db;
  final rows = await d.query(DbSchema.tNotes,
      columns: ['id', 'title'],
      where: 'archived = 0 AND deleted_at IS NULL',
      orderBy: 'updated_at DESC');
  return [
    for (final r in rows)
      MmNoteRef(id: r['id'] as int, title: (r['title'] as String? ?? '').trim().isEmpty
          ? '未命名笔记'
          : r['title'] as String? ?? ''),
  ];
}

/// 挂载笔记的当前标题；null＝笔记已不在册（回收站/彻底删除）＝占位态。
Future<String?> mmNoteTitleOf(int noteId, [Database? db]) async {
  final d = db ?? AppDatabase.instance.db;
  final rows = await d.query(DbSchema.tNotes,
      columns: ['title'],
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [noteId]);
  if (rows.isEmpty) return null;
  final t = (rows.first['title'] as String? ?? '').trim();
  return t.isEmpty ? '未命名笔记' : t;
}

/// 笔记正文（连接点④ md 解析的读源；null＝笔记已不在册）。
Future<String?> mmNoteContentOf(int noteId, [Database? db]) async {
  final d = db ?? AppDatabase.instance.db;
  final rows = await d.query(DbSchema.tNotes,
      columns: ['content'],
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [noteId]);
  return rows.isEmpty ? null : rows.first['content'] as String?;
}

/// 双击进笔记（H4/C5 裁定）：复用既有笔记编辑路由（不新开编辑器）。
/// 测试注入 [mmOpenNoteOverride] 断言「跳转出口被调用」。
Future<void> Function(BuildContext, int)? mmOpenNoteOverride;

Future<void> mmOpenNote(BuildContext context, int noteId) async {
  final override = mmOpenNoteOverride;
  if (override != null) return override(context, noteId);
  await context.push('/note/edit', extra: noteId);
}

/// 待整理收集箱条目（routed_to IS NULL），按创建倒序——「从收集箱」起点用。
Future<List<(int, String)>> mmPendingInbox([Database? db]) async {
  final d = db ?? AppDatabase.instance.db;
  final rows = await d.query(DbSchema.tInbox,
      columns: ['id', 'raw_text'],
      where: 'routed_to IS NULL',
      orderBy: 'created_at DESC');
  return [
    for (final r in rows) (r['id'] as int, r['raw_text'] as String? ?? ''),
  ];
}

/// 收集箱条目 → 导图节点 分流标记（L6 第五向的导图侧拉取；收集箱页侧第五向
/// 入口涉 inbox 页面文件，属另一线写区，批 1 不落——工单 §4b 互斥面）。
Future<void> mmRouteInboxToMindmap(List<int> ids, int mapId,
    [Database? db]) async {
  if (ids.isEmpty) return;
  final d = db ?? AppDatabase.instance.db;
  await d.update(
    DbSchema.tInbox,
    {'routed_to': 'mindmap', 'routed_ref': mapId},
    where: 'id IN (${List.filled(ids.length, '?').join(',')})',
    whereArgs: ids,
  );
}

// ==================== 批2 出口（F4-3 搜索 / 连接点② 卡片） ====================

/// 全局搜索第三源（F4-3）：跨图搜**已挂载节点**——
/// 命中＝节点标题或其挂载笔记标题含关键字；返回可跳画布定位的命中行。
/// 只搜在册图（`deleted_at IS NULL`）；回收站里的图不进搜索。
class MmSearchHit {
  const MmSearchHit({
    required this.nodeId,
    required this.mapId,
    required this.mapTitle,
    required this.nodeTitle,
    this.noteTitle,
  });

  final int nodeId;
  final int mapId;
  final String mapTitle;
  final String nodeTitle;

  /// 命中来自挂载笔记标题时给来源标题（null＝命中的是节点自身标题）。
  final String? noteTitle;
}

Future<List<MmSearchHit>> mmSearchMountedNodes(String query,
    [Database? db]) async {
  final q = query.trim();
  if (q.isEmpty) return const [];
  final d = db ?? AppDatabase.instance.db;
  // 两路合并：节点自身标题命中 ＋ 挂载笔记标题命中（笔记标题实时 join，
  // 与画布显示口径同源——笔记删了 join 不出行，该节点不因失效标题而谎报）。
  final like = '%$q%';
  final rows = await d.rawQuery('''
    SELECT n.id AS nid, n.title AS ntitle, m.id AS mid, m.title AS mtitle,
           nb.title AS btitle
    FROM ${DbSchema.tMindmapNodes} n
    JOIN ${DbSchema.tMindmaps} m ON m.id = n.map_id AND m.deleted_at IS NULL
    LEFT JOIN ${DbSchema.tNotes} nb ON nb.id = n.note_id AND nb.deleted_at IS NULL
    WHERE (n.title LIKE ? OR nb.title LIKE ?)
    ORDER BY m.updated_at DESC, n.sort ASC
    LIMIT 50
  ''', [like, like]);
  return [
    for (final r in rows)
      MmSearchHit(
        nodeId: r['nid'] as int,
        mapId: r['mid'] as int,
        mapTitle: r['mtitle'] as String? ?? '',
        nodeTitle: r['ntitle'] as String? ?? '',
        noteTitle: r['btitle'] as String?,
      ),
  ];
}

/// 连接点② 卡片预览数据（批2）：图在册＝(图名, 根节点标题集 ≤5 行)；null＝图已删。
/// 卡片只存 `map_id` 引用不存快照（§4.9）——预览每次现取，图更新卡片跟着更新。
Future<(String, List<String>)?> mmCardPreview(int mapId, [Database? db]) async {
  final d = db ?? AppDatabase.instance.db;
  final m = await d.query(DbSchema.tMindmaps,
      columns: ['title'],
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [mapId]);
  if (m.isEmpty) return null;
  final roots = await d.query(DbSchema.tMindmapNodes,
      columns: ['title'],
      where: 'map_id = ? AND parent_id IS NULL',
      whereArgs: [mapId],
      orderBy: 'sort ASC, id ASC',
      limit: 5);
  return (
    m.first['title'] as String? ?? '',
    [for (final r in roots) r['title'] as String? ?? ''],
  );
}

/// 卡片点击 → 进画布（§4.9：点击卡片 push mm-canvas?id=；测试注入缝同款）。
Future<void> Function(BuildContext, int mapId)? mmOpenCanvasOverride;

Future<void> mmOpenCanvas(BuildContext context, int mapId) async {
  final override = mmOpenCanvasOverride;
  if (override != null) return override(context, mapId);
  await context.push('/mindmap/canvas?id=$mapId');
}
