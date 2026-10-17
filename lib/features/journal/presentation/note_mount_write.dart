/// V1.64 真机反馈批③（工单 交棒话术-20261011 §4 · 拍板「挂载即双向」）：
/// 挂在「本地导入的目录夹」下的笔记，保存时同步落盘成 .md。
///
/// 口径：
///  · 已有 `origin_uri`（导入进来的那篇，或本函数首次落盘回填过的）＝**覆写原文件**，
///    文件名不随应用内改名而变（改名同步改文件名另批议，避免断链）；
///  · 没有＝在该目录里新建 `<标题>.md`，同名由原生追加 `(2)(3)…`，成功后把文件 URI
///    回填进这条笔记（下次编辑就走覆写）；
///  · 删除/进回收站**不动磁盘文件**；移动到别的夹＝文件留在原目录（只改库内归属）；
///  · 写盘失败（只读挂载/原文件没了/provider 抽风）一律按码回给 UI 出一行人话，
///    **应用内的保存照完成**——绝不因为写不出去而丢用户的稿子。
///
/// 真 IO 全走注入缝（`create`/`overwrite`），用例里不碰平台通道。
library;

import '../../../core/platform/open_intent.dart' show noteWriteBack;
import '../../../core/platform/saf_tree.dart';
import '../data/note_dao.dart';
import '../data/note_folder_dao.dart';
import '../domain/note.dart';
import 'note_local_import.dart' show noteSrcHash;

enum MountSync {
  none,

  /// 覆写原文件成功
  written,

  /// 首次落盘成功（已回填 URI）
  created,

  /// 该目录只有读权限（老挂载点当初没拿写授权）
  noPerm,

  /// 写失败（原文件不在/provider 拒绝）
  failed,
}

class MountSyncResult {
  const MountSyncResult(this.outcome, {this.path = '', this.note});

  final MountSync outcome;

  /// 人话位置（提示与日志用）。
  final String path;

  /// 回填后的条目（仅 created 会变；调用方要拿它覆盖自己的当前稿）。
  final Note? note;

  /// 只有失败才出声：自动保存是高频动作，成功再弹一条就成了刷屏。
  String get toastLine => switch (outcome) {
        MountSync.noPerm => '该目录只有读取权限 · 用「导入本地」再选它一次即可恢复写回',
        MountSync.failed => '写回本地目录失败 · 改动仅存应用内',
        _ => '',
      };
}

/// 该不该写、写到哪（无副作用的判定，测试与 UI 都读它）。
Future<bool> noteWritesBackToMount(
    {required Note saved, required NoteFolderDao folders}) async {
  final name = saved.folder;
  if (name == null || name.isEmpty) return false;
  final folder = await folders.byName(name);
  return folder != null &&
      folder.source == 'local_dir' &&
      folder.originUri.isNotEmpty;
}

/// 保存后把这条笔记同步到它所在的挂载目录。
Future<MountSyncResult> syncNoteToMount({
  required Note saved,
  required NoteDao notes,
  required NoteFolderDao folders,
  Future<MountWriteResult> Function(
      {required String tree,
      required String relPath,
      required String name,
      required String text})? create,
  Future<String> Function(String uri, String content)? overwrite,
}) async {
  final folderName = saved.folder;
  if (folderName == null || folderName.isEmpty) {
    return const MountSyncResult(MountSync.none);
  }
  // open_with 来源＝批1 的回写口（`noteWriteBackGuard`）已经按原始 URI 写过一次，
  // 这里再走挂载口＝同一次保存写两遍，且第二遍可能写到别的文件上。
  if (saved.source == 'open_with') return const MountSyncResult(MountSync.none);
  final folder = await folders.byName(folderName);
  // 只认「本地导入的目录夹」：手建夹、单文件挂标夹、导出挂载（只读）都不写回。
  if (folder == null ||
      folder.source != 'local_dir' ||
      folder.originUri.isEmpty) {
    return const MountSyncResult(MountSync.none);
  }
  if (saved.originUri.isNotEmpty) {
    final code = await (overwrite ?? noteWriteBack)(saved.originUri, saved.content);
    return code == 'ok'
        ? MountSyncResult(MountSync.written,
            path: saved.originPath, note: saved)
        : MountSyncResult(
            code == 'no_perm' ? MountSync.noPerm : MountSync.failed);
  }
  final base = saved.title.trim().isEmpty ? '未命名笔记' : saved.title.trim();
  // 挂载根＝顶层夹（relPath 空）；子夹的 origin_path 本身就是相对挂载根的路径。
  final rel = folder.parentId == null ? '' : folder.originPath;
  final r = await (create ?? safCreateInTree)(
      tree: folder.originUri, relPath: rel, name: '$base.md', text: saved.content);
  if (!r.ok) {
    return MountSyncResult(
        r.code == 'no_perm' ? MountSync.noPerm : MountSync.failed);
  }
  final back = await notes.save(saved.copyWith(
      originUri: r.uri,
      originPath: r.name,
      srcHash: noteSrcHash(saved.content)));
  return MountSyncResult(MountSync.created, path: r.localPath, note: back);
}
