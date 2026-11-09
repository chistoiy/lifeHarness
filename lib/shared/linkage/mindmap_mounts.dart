import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/database/app_database.dart';
import '../../core/database/schema.dart';
import '../../core/providers.dart' show eventBusProvider;
import '../../features/mindmap/domain/mindmap_node_meta.dart';
import 'linkage_events.dart';

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

/// 导图**根节点总数**（卡片副文案「N 个根节点」用）。
/// 与 [mmCardPreview] 分开出口的原因：预览按 §4.9 只取前 5 根，
/// 拿 `roots.length` 当根数会在根超 5 时谎报（显示 5 实为 8）。
Future<int> mmRootCountOf(int mapId, [Database? db]) async {
  final d = db ?? AppDatabase.instance.db;
  final rows = await d.rawQuery(
    'SELECT COUNT(*) AS c FROM ${DbSchema.tMindmapNodes} '
    'WHERE map_id = ? AND parent_id IS NULL',
    [mapId],
  );
  return rows.isEmpty ? 0 : (rows.first['c'] as int?) ?? 0;
}

/// 卡片点击 → 进画布（§4.9：点击卡片 push mm-canvas?id=；测试注入缝同款）。
Future<void> Function(BuildContext, int mapId)? mmOpenCanvasOverride;

Future<void> mmOpenCanvas(BuildContext context, int mapId) async {
  final override = mmOpenCanvasOverride;
  if (override != null) return override(context, mapId);
  await context.push('/mindmap/canvas?id=$mapId');
}

/// 可插卡片的在册导图清单（连接点② 挑图弹层读源）：只出在册图，
/// 回收站里的图不进挑图（插了必然是占位）。按最近更新倒序。
class MmMapBrief {
  const MmMapBrief({required this.id, required this.title, this.nodeCount = 0});

  final int id;
  final String title;

  /// 节点总数（副文案「N 个根节点」用根数，这里给全量计数备用）。
  final int nodeCount;
}

Future<List<MmMapBrief>> mmSelectableMaps([Database? db]) async {
  final d = db ?? AppDatabase.instance.db;
  final rows = await d.rawQuery('''
    SELECT m.id AS mid, m.title AS mtitle, COUNT(n.id) AS ncount
    FROM ${DbSchema.tMindmaps} m
    LEFT JOIN ${DbSchema.tMindmapNodes} n ON n.map_id = m.id
    WHERE m.deleted_at IS NULL
    GROUP BY m.id
    ORDER BY m.updated_at DESC, m.id DESC
  ''');
  return [
    for (final r in rows)
      MmMapBrief(
        id: r['mid'] as int,
        title: (r['mtitle'] as String? ?? '').trim().isEmpty
            ? '未命名导图'
            : r['mtitle'] as String? ?? '',
        nodeCount: (r['ncount'] as int?) ?? 0,
      ),
  ];
}

// ==================== 批5 F4-9 · 任务属性联动出口 ====================

/// 导图节点勾选任务完成 → **经本出口**发事件（工单 §4f.2 ④，变异刀1 钉点）。
///
/// 为什么不直接发 [TaskCompletedEvent]：`todoId` 是待办行 id，塞节点 id 会让
/// `habit_mounts` 等既有订阅方按 id 反查待办落空（虽不误伤，但载荷语义被污染）。
/// 故独立 [MmNodeTaskEvent]（带 `source='mindmap'`），由本出口转发到事件总线。
///
/// 测试注入 [mmPublishOverride] 断言「事件真的被发布」——不注入时走宿主总线。
void Function(MmNodeTaskEvent)? mmPublishOverride;

/// 发事件的实际通道（生产＝宿主总线；测试注入 fake）。
void _publish(WidgetRef ref, MmNodeTaskEvent e) {
  final override = mmPublishOverride;
  if (override != null) return override(e);
  ref.read(eventBusProvider).publish(e);
}

/// 节点勾选完成/取消完成。`done=true` 即完成。
///
/// 事件只读侧有影响（订阅方刷新统计等），**不写任何待办表**——导图节点与待办
/// 是两个域的平行数据，「联动」= 通知，不是一边落库另一边跟着改
/// （否则勾一下节点就凭空多出一条待办＝用户看到重复条目）。
void mmCompleteNodeTask(
  WidgetRef ref, {
  required int mapId,
  required int nodeId,
  required String nodeTitle,
  required bool done,
}) {
  if (!done) return; // 取消完成不发事件（统计只关心达成）
  _publish(
    ref,
    MmNodeTaskEvent(
      mapId: mapId,
      nodeId: nodeId,
      nodeTitle: nodeTitle,
      atMs: DateTime.now().millisecondsSinceEpoch,
    ),
  );
}
