/// V1.64 批1 N-3/N-4（工单 交棒话术-20261004 §2 · 拍板 C/D/F/G）：
/// 系统「打开方式」收到 .md/.markdown/.txt → 归集固定「系统打开」临时文件夹 →
/// 直达编辑页；同名（原始 URI 命中）＝覆盖更新不堆副本；回收站行不参与判重。
/// UI 侧只做「导入＋提示＋跳编辑」，导入本体是可脱离 context 的服务函数（可测）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/open_intent.dart' show OpenIntentFile;
import '../../../shared/widgets/ui_kit.dart' show AppToast;
import '../data/note_dao.dart';
import '../data/note_folder_dao.dart';
import '../domain/note.dart';
import '../domain/note_folder.dart';
import 'journal_providers.dart';

/// 读正文缝：测试替换避免 FakeAsync 真磁盘 IO（既有踩坑＝真异步 I/O 挂死）。
Future<String> Function(String path) noteOpenReadContent =
    (path) => File(path).readAsString();

enum NoteOpenOutcome { created, updated, failed }

class NoteOpenResult {
  const NoteOpenResult(this.note, this.outcome);
  final Note? note;
  final NoteOpenOutcome outcome;
}

/// 确保固定「系统打开」夹在场（幂等；拍板 F：N-4 历史列表即该夹内容）。
Future<void> ensureSystemOpenFolder(NoteFolderDao folders) async {
  final all = await folders.list();
  if (all.any((f) => f.name == kSystemOpenFolder)) return;
  await folders.create(kSystemOpenFolder);
}

/// 导入一篇经打开方式进来的文本笔记（无 context 依赖，直接可测）。
Future<NoteOpenResult> importOpenedNote({
  required NoteDao notes,
  required NoteFolderDao folders,
  required String path,
  required String fileName,
  required String uri,
}) async {
  String text;
  try {
    text = await noteOpenReadContent(path);
  } catch (_) {
    // catch-ok: 读失败＝用户可见错误由调用侧 toast，此处仅回决策值。
    return const NoteOpenResult(null, NoteOpenOutcome.failed);
  }
  final title = fileName.replaceAll(RegExp(r'\.(md|markdown|txt)$', caseSensitive: false), '');
  final now = DateTime.now();
  final existing = await notes.byOriginUri(uri);
  if (existing != null) {
    // 拍板 C：同名二次打开＝覆盖更新该条（正文取最新、打开时间刷新），不新建。
    final saved = await notes.save(existing.copyWith(
        title: title, content: text, updatedAt: now, openedAt: now));
    return NoteOpenResult(saved, NoteOpenOutcome.updated);
  }
  await ensureSystemOpenFolder(folders);
  final saved = await notes.save(Note(
      title: title.isEmpty ? fileName : title,
      content: text,
      kind: 'md',
      folder: kSystemOpenFolder,
      source: 'open_with',
      originPath: fileName,
      originUri: uri,
      openedAt: now,
      createdAt: now,
      updatedAt: now));
  return NoteOpenResult(saved, NoteOpenOutcome.created);
}

/// 打开方式 note 支路的 UI 出口（app.dart 分派后调用）。
Future<void> noteOpenConsume(BuildContext context, WidgetRef ref, OpenIntentFile f) async {
  final r = await importOpenedNote(
    notes: ref.read(noteDaoProvider),
    folders: ref.read(noteFolderDaoProvider),
    path: f.path,
    fileName: f.name,
    uri: f.uri,
  );
  if (!context.mounted) return;
  final n = r.note;
  switch (r.outcome) {
    case NoteOpenOutcome.failed:
      AppToast.show(context, '文件无法读取');
      return;
    case NoteOpenOutcome.updated:
      AppToast.show(context, '「${n!.title}」已按最新内容更新 · 保存将回写原文件');
    case NoteOpenOutcome.created:
      AppToast.show(context, '已导入到「$kSystemOpenFolder」 · 保存将回写原文件');
  }
  ref.invalidate(notesProvider);
  ref.invalidate(noteFoldersProvider);
  // R6 栈路由：编辑器 push 保栈（go 清栈会致返回键直接退 app）。
  context.push('/note/edit', extra: n!.id);
}
