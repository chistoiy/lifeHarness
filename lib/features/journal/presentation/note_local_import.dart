/// V1.64 批2（工单 交棒话术-20261004 §2 N-1 · §1.2 N-1c · 拍板 E/H）：
/// 笔记「导入本地」与「移除挂载」——导入域服务（可脱离 context 测）＋两枚弹层。
///
/// 口径落点：
///  · 目录档＝**还原磁盘子层级**（2026-10-11 产品定，翻案样张单节点）：每个子夹
///    各成一个挂载节点（`note_folders.source='local_dir'`），笔记按所属子夹归位；
///    同名夹复用不重复建（既有模型 notes.folder 按名匹配）。
///  · 判重＝**内容哈希**（sha256 前 16 位）只约束在册行，回收站行不参与（E 批红线）；
///    重复跳过并汇总「跳过 N 条重复」，不堆副本。
///  · 文件档＝落当前目录并给该夹挂 `local_file` 标（无独立节点）；未选目录＝未归类。
///  · 移除（N-1c·拍板 H）＝必经确认层，只摘挂载行连子夹，磁盘原件与库内笔记都不动。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../../../core/platform/saf_tree.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/note_dao.dart';
import '../data/note_folder_dao.dart';
import '../domain/note.dart';
import '../domain/note_folder.dart';

/// 目录档收哪些扩展名（工单 §2 N-1＝`.md`；markdown 视为同族，txt 只走打开方式）。
const kLocalImportExts = ['.md', '.markdown'];

/// 内容哈希（判重锚点；落 notes.src_hash）。
String noteSrcHash(String content) =>
    sha256.convert(utf8.encode(content)).toString().substring(0, 16);

bool _isImportableName(String name) {
  if (name.startsWith('.')) return false; // 隐藏项（.DS_Store/.obsidian…）一律不收
  final lower = name.toLowerCase();
  return kLocalImportExts.any((e) => lower.endsWith(e));
}

String _titleOf(String fileName) =>
    fileName.replaceAll(RegExp(r'\.(md|markdown)$', caseSensitive: false), '');

class LocalImportReport {
  const LocalImportReport(
      {this.added = 0, this.skipped = 0, this.unread = 0, this.folders = 0});

  final int added;

  /// 命中同哈希的在册行＝跳过（不新建）。
  final int skipped;

  /// 读不出正文（授权失效/provider 拒绝）＝可见计数，不静默吞。
  final int unread;
  final int folders;

  bool get didWork => added > 0 || skipped > 0 || unread > 0;

  /// 汇总成人话一行（样张同款：「已导入 N 条 · 跳过重复 M 条」）。
  String get line => '已导入 $added 条 · 跳过重复 $skipped 条'
      '${unread > 0 ? ' · 读取失败 $unread 条' : ''}';
}

class _Counts {
  int added = 0, skipped = 0, unread = 0, folders = 0;
  LocalImportReport get report => LocalImportReport(
      added: added, skipped: skipped, unread: unread, folders: folders);
}

/// 找回或新建挂载夹（同名复用；手建夹被本地导入命中时升挂为挂载）。
Future<NoteFolder> ensureMountFolder(NoteFolderDao folders, String name,
    {int? parentId,
    String source = 'local_dir',
    String originUri = '',
    String originPath = ''}) async {
  final hit = await folders.byName(name);
  if (hit != null) {
    if (hit.source.isEmpty && source.isNotEmpty) {
      await folders.setMount(hit.id!,
          source: source, originUri: originUri, originPath: originPath);
    } else if (hit.isMount && originUri.isNotEmpty) {
      // 真机反馈批③（工单 §4）：**重新导入同一个目录＝刷新挂载锚点**——老挂载点当初只拿了
      // 读授权，重选一次才带得上写权限；URI 不更新则写回永远 no_perm。
      await folders.setMount(hit.id!,
          source: hit.source, originUri: originUri, originPath: originPath);
    }
    return hit;
  }
  return folders.create(name,
      parentId: parentId,
      source: source,
      originUri: originUri,
      originPath: originPath);
}

Future<void> _importOneDoc(
    {required NoteDao notes,
    required SafDoc doc,
    required String? folder,
    required String source,
    required String originPath,
    required Future<String?> Function(String uri) readText,
    required _Counts c}) async {
  String? text;
  try {
    text = await readText(doc.uri);
  } catch (_) {
    // catch-ok: 单篇读不到＝计入「读取失败」可见汇总，不中断整批。
    c.unread++;
    return;
  }
  if (text == null) {
    c.unread++;
    return;
  }
  final hash = noteSrcHash(text);
  if (await notes.bySrcHash(hash) != null) {
    c.skipped++; // 判重：同内容在册＝跳过不堆副本
    return;
  }
  final now = DateTime.now();
  await notes.save(Note(
      title: _titleOf(doc.name),
      content: text,
      kind: 'md',
      folder: (folder == null || folder.isEmpty) ? null : folder,
      source: source,
      originPath: originPath,
      originUri: doc.uri,
      srcHash: hash,
      createdAt: now,
      updatedAt: now));
  c.added++;
}

Future<void> _walkDir(
    {required NoteDao notes,
    required NoteFolderDao folders,
    required SafDoc dir,
    required NoteFolder parent,
    required String relPrefix,
    required Future<String?> Function(String uri) readText,
    required _Counts c}) async {
  for (final ch in dir.children) {
    if (ch.name.startsWith('.')) continue;
    if (ch.isDir) {
      final sub = await ensureMountFolder(folders, ch.name,
          parentId: parent.id, originPath: '$relPrefix${ch.name}', originUri: ch.uri);
      c.folders++;
      await _walkDir(
          notes: notes,
          folders: folders,
          dir: ch,
          parent: sub,
          relPrefix: '$relPrefix${ch.name}/',
          readText: readText,
          c: c);
    } else if (_isImportableName(ch.name)) {
      await _importOneDoc(
          notes: notes,
          doc: ch,
          folder: parent.name,
          source: 'local_dir',
          originPath: '$relPrefix${ch.name}',
          readText: readText,
          c: c);
    }
  }
}

/// 目录档：把一棵 SAF 目录树挂进文件树（层级还原）并逐篇导入 .md。
Future<LocalImportReport> importLocalTree(
    {required NoteDao notes,
    required NoteFolderDao folders,
    required SafDoc root,
    required Future<String?> Function(String uri) readText}) async {
  final c = _Counts();
  final top = await ensureMountFolder(folders, root.name,
      originUri: root.uri, originPath: root.path);
  c.folders++;
  await _walkDir(
      notes: notes,
      folders: folders,
      dir: root,
      parent: top,
      relPrefix: '',
      readText: readText,
      c: c);
  return c.report;
}

/// 文件档：单/多文件落当前目录（未选＝未归类），并给该夹挂 `local_file` 标。
Future<LocalImportReport> importLocalFiles(
    {required NoteDao notes,
    required NoteFolderDao folders,
    required List<SafDoc> docs,
    String currentFolder = '',
    Future<String?> Function(String uri)? readText}) async {
  final c = _Counts();
  if (currentFolder.isNotEmpty) {
    final hit = await folders.byName(currentFolder);
    if (hit != null && hit.source.isEmpty) {
      await folders.setMount(hit.id!, source: 'local_file');
    }
  }
  final read = readText ?? ((uri) async => safReadText(uri));
  for (final d in docs) {
    await _importOneDoc(
        notes: notes,
        doc: d,
        folder: currentFolder,
        source: 'local_file',
        originPath: d.name,
        readText: read,
        c: c);
  }
  return c.report;
}

/// 确认层用：该挂载子树内「保留在库」的笔记数（现算，不写死）。
Future<int> mountNoteCount(
    NoteFolderDao folders, NoteDao notes, int rootId) async {
  final names = await folders.subtreeNames(rootId);
  final counts = await notes.folderCounts();
  return names.fold<int>(0, (t, n) => t + (counts[n] ?? 0));
}

/// 移除挂载（N-1c·拍板 H）：返回摘掉的节点数（0＝被守卫拒绝）。
Future<int> unmountFolder({
  required NoteFolderDao folders,
  required NoteDao notes,
  required NoteFolder folder,
}) async {
  final ids = await folders.subtreeIds(folder.id!);
  final ok = await folders.unmount(folder.id!);
  return ok ? ids.length : 0;
}

// ---------------------------------------------------------------------------
// 弹层（UI 只做展示与分派，动作经回调注入＝可单测不碰平台通道）
// ---------------------------------------------------------------------------

/// 「导入本地」面板（原型 sheetNoteImport）：目录/文件就地两取法＋进度行＋汇总。
/// [onRun] 收 'dir'|'file'，返回 null＝用户在系统选择器里取消（不出提示）。
Future<void> showNoteLocalImportSheet(BuildContext context,
    {required Future<LocalImportReport?> Function(String kind) onRun}) async {
  var kind = 'dir';
  var busy = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (bc) => StatefulBuilder(
      builder: (bc2, setSheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                  child: Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('导入本地',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              )),
              SegRow<String>(
                keyPrefix: 'ni-kind',
                items: const [
                  (id: 'dir', label: '目录'),
                  (id: 'file', label: '文件'),
                ],
                value: kind,
                onChanged:
                    busy ? null : (v) => setSheet(() => kind = v),
              ),
              const SizedBox(height: 8),
              Text(
                  kind == 'dir'
                      ? '递归收目录内 .md · 按内容哈希判重 · 子文件夹各成带「本地」角标节点'
                      : '多选 .md 文件 · 建于当前目录 · 该目录带「本地」角标',
                  style: TextStyle(
                      fontSize: 11, color: Theme.of(bc).colorScheme.onSurfaceVariant)),
              if (busy)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                      kind == 'dir' ? '扫描目录 · 抽取 .md 中…' : '读取所选文件…',
                      key: const ValueKey('ni-progress'),
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: OutlinedButton(
                          onPressed: busy ? null : () => Navigator.pop(bc),
                          child: const Text('取消'))),
                  const SizedBox(width: 10),
                  Expanded(
                      flex: 2,
                      child: FilledButton(
                          key: const ValueKey('ni-go'),
                          onPressed: busy
                              ? null
                              : () async {
                                  setSheet(() => busy = true);
                                  final r = await onRun(kind);
                                  if (!bc2.mounted) return;
                                  Navigator.pop(bc);
                                  if (r != null && context.mounted) {
                                    AppToast.show(context, r.line);
                                  }
                                },
                          child: Text(kind == 'dir' ? '选择目录并导入' : '选择文件并导入'))),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 来源角标（纯文字线性胶囊·零 emoji）：本地导入＝「本地」·导出目录＝「导出」。
/// 单文件导入的挂标（local_file）显隐由树侧按「该夹还有无 local_* 来源笔记」决定
/// （工单 §1.2 自动回落口径），本件只负责画法。
class MountBadge extends StatelessWidget {
  const MountBadge({super.key, required this.source});

  final String source;

  static const _label = {
    'local_dir': '本地',
    'local_file': '本地',
    'export': '导出'
  };
  static const _color = {
    'local_dir': Color(0xFF0D9488),
    'local_file': Color(0xFF0D9488),
    'export': Color(0xFFD97706),
  };

  @override
  Widget build(BuildContext context) {
    final label = _label[source];
    if (label == null) return const SizedBox.shrink();
    final color = _color[source]!;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .7)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1.2)),
    );
  }
}

/// 「移除挂载」确认层（原型 sheetNoteUnmount · 工单 §11 过门点②）：后果三行现算。
Future<void> showNoteUnmountSheet(BuildContext context,
    {required NoteFolder folder,
    required int childCount,
    required int keepCount,
    required Future<void> Function() onConfirm}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (bc) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text('移除挂载 · ${folder.name}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 15))),
                MountBadge(source: folder.source),
              ],
            ),
            const SizedBox(height: 4),
            Text(
                '${folder.originPath.isEmpty ? '本机的挂载目录' : folder.originPath}'
                ' · 子夹 $childCount 个',
                key: const ValueKey('nu-subline'),
                style: TextStyle(
                    fontSize: 10, color: Theme.of(bc).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            for (final line in [
              '只从文件树摘掉该挂载${childCount > 0 ? '及其 $childCount 个子夹' : ''}',
              '手机里的目录与文件不删除',
              '已导入的 $keepCount 条笔记保留在库 · 来源标仍可筛',
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                        padding: const EdgeInsets.only(top: 6, right: 8),
                        child: Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                                color: Theme.of(bc).colorScheme.outlineVariant,
                                shape: BoxShape.circle))),
                    Expanded(
                        child: Text(line,
                            style: const TextStyle(fontSize: 12, height: 1.35))),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: OutlinedButton(
                        onPressed: () => Navigator.pop(bc), child: const Text('取消'))),
                const SizedBox(width: 10),
                Expanded(
                    flex: 2,
                    child: FilledButton(
                        key: const ValueKey('nu-confirm'),
                        style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFF43F5E)),
                        onPressed: () async {
                          Navigator.pop(bc);
                          await onConfirm();
                        },
                        child: const Text('确认移除'))),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
