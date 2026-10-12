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
