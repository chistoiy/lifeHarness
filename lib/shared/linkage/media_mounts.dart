import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/media/presentation/media_add_sheet.dart';
import '../../features/media/presentation/media_workbench.dart';
import 'stats_providers.dart';

/// 记录页·影音游 tab 挂载点（shared/linkage 聚合装配 feature，R1 与 read_mounts 同法）。
/// 记录页（journal feature）不直接 import 影音游模块。

/// 影音游工作台（影音架入口＋四类在册计数＋最近四条俯瞰）。
Widget mediaWorkbench() => const MediaWorkbench();

/// 影音游 tab FAB ＝ 新条目录入（原型 S-09：FAB 随记录页 tab 语境变，四类分派四套字段）。
void mediaTabFabTap(BuildContext context, WidgetRef ref) =>
    showMediaAddSheet(context, ref);

// ==================== L5 联动出口（影音笔记 → 日记草稿 / 待办） ====================
//
// 计划 §六 L5（L306）：影音笔记的「→日记」把这一条插进**今日日记草稿**，「→待办」生成一条
// **无截止日**的任务。media feature 不得 import journal/todo（架构守护 R1），
// 两个写入都从这枚 shared 出口走，journalRepositoryProvider / todoRepositoryProvider
// 由本文件下方 stats_providers 的 re-export 拿到。

/// 一句人话的来源串（写进日记行首与待办备注，用户在他页能认出这条从哪来）。
String mediaNoteSourceLabel(String itemTitle) => '影音笔记 · 《$itemTitle》';

/// 笔记 → 今日日记草稿（同日已有正文就换行追加，没有就新建当天一篇）。
/// 返回当天日记 id，供 UI 侧 toast 与 tick。
Future<int?> mediaNoteAppendJournal(WidgetRef ref,
    {required String body, required String itemTitle}) async {
  final repo = ref.read(journalRepositoryProvider);
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  final line = '${mediaNoteSourceLabel(itemTitle)}\n$body';
  final cur = await repo.byDay(day);
  // 目标页当场可见（「设置必须当场生效」同一条口径）：写完 invalidate 日记侧列表。
  ref.invalidate(journalsProvider);
  final saved = await repo.save(
    cur == null
        ? JournalEntry(
            day: day, content: line, createdAt: now, updatedAt: now)
        : cur.copyWith(content: cur.content.trim().isEmpty ? line : '${cur.content}\n\n$line'),
  );
  return saved.id;
}

/// 笔记 → 待办（**无截止日**＝L5 原口径；标题取正文首行，备注带来源）。
Future<int?> mediaNoteCreateTodo(WidgetRef ref,
    {required String body, required String itemTitle}) async {
  final firstLine = body.trim().split('\n').first;
  final title = firstLine.length > 30 ? '${firstLine.substring(0, 30)}…' : firstLine;
  final t = await ref.read(todoRepositoryProvider).add(Todo(
        title: title.isEmpty ? '整理影音笔记' : title,
        tag: '影音游',
        note: mediaNoteSourceLabel(itemTitle),
      ));
  ref.invalidate(todosProvider);
  return t.id;
}
