/// V1.64 批3 · N-2「导出为本地目录」（工单 交棒话术-20261004 §15 · 需求清单 V1.64 N-2 ·
/// 原型 `index-bookshelf.html` 的 `sheetNoteExport`/`nxScChg`/`nxDo`）。
///
/// 口径（按三源优先序「需求修订史 > 原型 > 计划文档」定，面板 §15.1）：
///  · 范围两档＝「当前目录」（＝原型 `nxDo` 的 `x.folder===ntSel`，**只所选夹本身，不含子夹**）
///    /「全部笔记」；软删行一律不参与（E 批红线，`NoteDao.list` 已过滤 `deleted_at`）；
///  · 落盘＝所选目标目录下建（或复用）**一枚**根节点「笔记导出」，每条写 `<标题>.md`，
///    **文件平铺**——子层级只在导入侧还原（批2 §11 定的那条，导出不反向建树）；
///  · 正文＝Markdown 无损：`plain`/`md` 原样，`rich` 的 Quill Delta 走本件的 [_deltaToMd]
///    （既有 `Note.richToPlain` 会把图片退化成「图片」二字＝导出丢图，不能复用）；
///  · 图片附件拷到同级 `_assets/`，md 内引用**相对路径**（内容寻址名 `<hash>.<ext>` 已保证唯一）；
///  · 导出目录进文件树带「导出」标＝`source:'export'` 的挂载节点；**只读挂载、不回写**
///    （`noteWritesBackToMount` 现口径已排除 `export`，本批不许放宽）；
///  · 全程可见进度＋一句汇总；`no_perm`/写不进必须出声（「点了必须有看得见的变化」）。
///
/// 真 IO 全走注入缝（[ensureDir]/[create]/[pickTree]），用例里不碰平台通道（同批2 定式）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/platform/saf_tree.dart';
import '../../../shared/widgets/ui_kit.dart' show AppToast, SegRow;
import '../data/note_dao.dart';
import '../data/note_folder_dao.dart';
import '../domain/note.dart';
import 'note_local_import.dart' show ensureMountFolder;

/// 导出包根目录名（原型 `nxDo` 里就是这一个节点名）。
const String kNoteExportRoot = '笔记导出';

/// 附件目录名（同级 `_assets/`，md 内相对引用）。
const String kNoteExportAssetsDir = '_assets';

/// md 本地图片语法（附件识别与相对化共用）。
final RegExp _mdImgRe = RegExp(r'!\[([^\]]*)\]\(([^)]+)\)');

/// 是不是「本机图片路径」（http(s) 外链与相对路径一律不动，导出只管库内落的附件）。
bool _isLocalAsset(String s) =>
    s.isNotEmpty && !s.startsWith('http://') && !s.startsWith('https://');

/// 一篇笔记正文里引用到的本地附件（按出现顺序去重）。
List<String> noteAssetPaths(Note n) {
  final out = <String>[];
  if (n.kind == 'rich') {
    Object? decoded;
    try {
      decoded = jsonDecode(n.content);
    } catch (_) {
      decoded = null; // 非 JSON 的历史稿：下面按纯文本扫
    }
    if (decoded is List) {
      for (final op in decoded) {
        if (op is! Map) continue;
        final ins = op['insert'];
        if (ins is Map) {
          final img = ins['image'];
          if (img is String && _isLocalAsset(img) && !out.contains(img)) out.add(img);
        }
      }
      return out;
    }
  }
  for (final m in _mdImgRe.allMatches(n.content)) {
    final path = m.group(2) ?? '';
    if (_isLocalAsset(path) && !out.contains(path)) out.add(path);
  }
  return out;
}

/// 附件在导出包里的文件名：取原名（内容寻址＝天然唯一）；
/// 真撞上同名不同物（手输的路径可能）才追加序号——宁可改名不可覆盖。
Map<String, String> planAssetNames(Iterable<String> paths) {
  final map = <String, String>{};
  final used = <String, String>{}; // 包内名 → 原路径（同一个名字被两张不同的图占过就要让位）
  for (final path in paths) {
    var name = p.basename(path.replaceAll('\\', '/'));
    if (name.isEmpty) name = 'image';
    var cand = name;
    var n = 1;
    while (used.containsKey(cand) && used[cand] != path) {
      n++;
      final dot = name.lastIndexOf('.');
      cand = dot > 0
          ? '${name.substring(0, dot)}($n)${name.substring(dot)}'
          : '$name($n)';
    }
    used[cand] = path;
    map[path] = cand;
  }
  return map;
}

/// md/纯文本正文：把 `![alt](本地绝对路径)` 的引用改成相对 `_assets/<名>`。
String _relativizeMd(String body, Map<String, String> assetOf) =>
    body.replaceAllMapped(_mdImgRe, (m) {
      final path = m.group(2) ?? '';
      final name = assetOf[path];
      if (name == null) return m.group(0)!; // 非本地/未入包：原样留着，不编造
      final alt = (m.group(1) ?? '').isEmpty ? '图片' : m.group(1)!;
      return '![$alt]($kNoteExportAssetsDir/$name)';
    });

String _inlineRun(String text, Map attrs) {
  if (text.isEmpty) return text;
  var s = text;
  if (attrs['code'] == true) s = '`$s`';
  if (attrs['bold'] == true) s = '**$s**';
  if (attrs['italic'] == true) s = '*$s*';
  if (attrs['strike'] == true) s = '~~$s~~';
  final link = attrs['link'];
  if (link is String && link.isNotEmpty) s = '[$s]($link)';
  return s;
}

/// Quill Delta → Markdown（批3 导出专用；`richToPlain` 丢图，不能拿来导）。
/// 行级属性取「该段结尾那个 `\n`」的 attrs（Quill 模型：块格式挂在行末换行符上）。
String _deltaToMd(String content, Map<String, String> assetOf) {
  Object? decoded;
  try {
    decoded = jsonDecode(content);
  } catch (_) {
    return _relativizeMd(Note.richToPlain(content), assetOf);
  }
  if (decoded is! List) return _relativizeMd(Note.richToPlain(content), assetOf);
  final sb = StringBuffer();
  var line = StringBuffer();
  var inFence = false;

  void flushFence() {
    if (inFence) {
      sb.write('```\n');
      inFence = false;
    }
  }

  void closeLine(Map attrs) {
    final text = line.toString();
    line = StringBuffer();
    final h = attrs['heading'];
    final list = attrs['list'];
    final codeBlock = attrs['code-block'] == true;
    if (!codeBlock) flushFence();
    if (codeBlock && !inFence) {
      sb.write('```\n');
      inFence = true;
    }
    if (codeBlock) {
      sb.write('$text\n');
      return;
    }
    final prefix = h is int && h > 0
        ? '${'#' * (h.clamp(1, 6))} '
        : list == 'ordered'
            ? '1. '
            : list == 'bullet'
                ? '- '
                : list == 'checked'
                    ? '- [x] '
                    : list == 'unchecked'
                        ? '- [ ] '
                        : attrs['blockquote'] == true
                            ? '> '
                            : '';
    sb.write('$prefix$text\n');
  }

  for (final op in decoded) {
    if (op is! Map) continue;
    final attrs = (op['attributes'] is Map) ? op['attributes'] as Map : const {};
    final ins = op['insert'];
    if (ins is String) {
      final pieces = ins.split('\n');
      for (var i = 0; i < pieces.length; i++) {
        if (i > 0) closeLine(attrs);
        line.write(_inlineRun(pieces[i], attrs));
      }
    } else if (ins is Map) {
      final img = ins['image'];
      if (img is String) {
        final name = assetOf[img];
        line.write(name == null
            ? '![图片]($kNoteExportAssetsDir)' // 没进包（非本地路径）：不留假链接
            : '![图片]($kNoteExportAssetsDir/$name)');
      } else {
        line.write('▪'); // 其它嵌入物（视频等）沿用既有占位口径
      }
    }
  }
  if (line.isNotEmpty) closeLine(const {});
  flushFence();
  return sb.toString();
}

/// 导出正文（不含标题行——文件名就是标题，正文按需求「Markdown 无损」）。
String noteToMarkdown(Note n, Map<String, String> assetOf) => n.kind == 'rich'
    ? _deltaToMd(n.content, assetOf)
    : _relativizeMd(n.content, assetOf);

/// 文件名：标题（空＝未命名笔记）里的路径非法字符换 `-`；同名由原生追加 (2)。
String noteExportFileName(Note n) {
  final title = (n.title.trim().isEmpty ? '未命名笔记' : n.title.trim())
      .replaceAll(RegExp(r'[/\\:*?"<>|\r\n\t]'), '-')
      .trim();
  return '$title.md';
}

/// 导出结果（汇总 toast 的唯一文案源；失败一律进句子，不许静默）。
class NoteExportReport {
  const NoteExportReport({
    this.exported = 0,
    this.assets = 0,
    this.failedNotes = 0,
    this.failedAssets = 0,
    this.errorCode = '',
  });

  final int exported;
  final int assets;
  final int failedNotes;
  final int failedAssets;

  /// ''＝有落盘动作；no_perm＝那个目录只给了读授权；error＝根目录就没建出来。
  final String errorCode;

  /// 汇总句**恒出声**（含 0 篇）：整批没落成（errorCode）更要出声——「点了没反应」是本系列红线，
  /// 导入侧那种「没动就没提示」在这里不成立（导出至少该给出「为什么没导」）。
  String get line => switch (errorCode) {
        'no_perm' => '这个目录只有读取权限 · 没能导出',
        'error' => '导出目录建不出来 · 没能导出',
        _ => '已导出 $exported 篇 · 附件 $assets 张'
            '${failedNotes > 0 ? ' · $failedNotes 篇没写成' : ''}'
            '${failedAssets > 0 ? ' · $failedAssets 张附件没拷成' : ''}',
      };
}

/// 把 [scope] 范围的笔记导出进已授权目录树 [treeUri]（`''`＝全部笔记）。
Future<NoteExportReport> exportNotesToTree({
  required NoteDao notes,
  required NoteFolderDao folders,
  required String treeUri,
  required String treePath,
  required String scope,
  Future<MountWriteResult> Function(
          {required String tree,
          required String relPath,
          required String name})? ensureDir,
  Future<MountWriteResult> Function(
          {required String tree,
          required String relPath,
          required String name,
          required String text,
          String mime,
          String srcPath})? create,
}) async {
  final dir = ensureDir ?? safEnsureDirInTree;
  final put = create ?? safCreateInTree;

  // 1) 根目录（复用已有＝同名不再造一枚「笔记导出 (2)」）。
  final root = await dir(tree: treeUri, relPath: '', name: kNoteExportRoot);
  if (!root.ok) {
    return NoteExportReport(errorCode: root.code == 'no_perm' ? 'no_perm' : 'error');
  }
  final rootRel = root.name;

  // 2) 取范围（软删/归档行由 DAO 过滤；「当前目录」只本夹一层，＝原型 nxDo 口径）。
  final list = await notes.list(folder: scope.isEmpty ? null : scope);

  // 3) 先全量规划附件名（跨篇共用一张表＝同一张图只拷一次、两处引用同一个名）。
  final assetOf = planAssetNames([for (final n in list) ...noteAssetPaths(n)]);
  var copied = 0, failedAssets = 0;
  if (assetOf.isNotEmpty) {
    final assetsDir =
        await dir(tree: treeUri, relPath: rootRel, name: kNoteExportAssetsDir);
    if (assetsDir.ok) {
      for (final e in assetOf.entries) {
        final r = await put(
            tree: treeUri,
            relPath: '$rootRel/$kNoteExportAssetsDir',
            name: e.value,
            text: '',
            srcPath: e.key,
            mime: _mimeOfPath(e.key));
        if (r.ok) {
          copied++;
        } else {
          failedAssets++;
        }
      }
    } else {
      failedAssets = assetOf.length;
    }
  }

  // 4) 逐篇写 md（同名由原生追加序号；失败计数出声，不中断整批）。
  var exported = 0, failedNotes = 0;
  for (final n in list) {
    final r = await put(
        tree: treeUri,
        relPath: rootRel,
        name: noteExportFileName(n),
        text: noteToMarkdown(n, assetOf));
    r.ok ? exported++ : failedNotes++;
  }

  // 5) 挂载节点（「笔记导出」带「导出」标·重导＝刷新锚点；只读挂载，不回写）。
  await ensureMountFolder(folders, kNoteExportRoot,
      source: 'export',
      originUri: treeUri,
      originPath: treePath.isEmpty
          ? kNoteExportRoot
          : '${treePath.replaceAll(RegExp(r'[/\\]+$'), '')}/$kNoteExportRoot');

  return NoteExportReport(
      exported: exported,
      assets: copied,
      failedNotes: failedNotes,
      failedAssets: failedAssets);
}

/// 附件的文档类型（SAF 建档要 mime；认不出的按二进制/octet-stream 落，别硬编成 md）。
String _mimeOfPath(String path) {
  final ext = p.extension(path.replaceAll('\\', '/')).toLowerCase();
  return switch (ext) {
    '.png' => 'image/png',
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.gif' => 'image/gif',
    '.webp' => 'image/webp',
    '.bmp' => 'image/bmp',
    '.heic' => 'image/heic',
    _ => 'application/octet-stream',
  };
}

/// 「导出为本地目录」半屏（原型 `sheetNoteExport`）：两档范围＋进度行＋主钮。
/// 未点选文件夹时「当前目录」档**点了拒切换并出一句实话**（原型 `nxScChg` 同口径）。
/// [onRun] 收所选范围（''＝全部笔记），返回 null＝用户在系统选择器里取消（不出提示）。
Future<void> showNoteExportSheet(BuildContext context,
    {required bool hasCurrentFolder,
    required String folderLabel,
    required Future<NoteExportReport?> Function(String scope) onRun}) async {
  var pick = 'all'; // 原型 `let nxSc='all'`＝默认「全部笔记」
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
                child: Text('导出为本地目录',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              )),
              SegRow<String>(
                keyPrefix: 'nx-sc',
                items: [
                  (id: 'cur', label: '当前目录${hasCurrentFolder ? ' · $folderLabel' : ''}'),
                  (id: 'all', label: '全部笔记'),
                ],
                value: pick,
                onChanged: busy
                    ? null
                    : (v) => setSheet(() {
                          // 没点选文件夹就别切过去（切了导空包更迷惑），给一句为什么。
                          if (v == 'cur' && !hasCurrentFolder) {
                            AppToast.show(bc, '先在树中点选文件夹，或改选「全部笔记」');
                            return;
                          }
                          pick = v;
                        }),
              ),
              const SizedBox(height: 8),
              Text(
                  pick == 'cur'
                      ? '只导「$folderLabel」里的笔记 · 每条一个 .md · 附件随导出为 _assets/ 目录包'
                      : '导出全部笔记 · 每条一个 .md · 附件随导出为 _assets/ 目录包',
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(bc).colorScheme.onSurfaceVariant)),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text('写入 .md 与 _assets/ 附件中…',
                      key: ValueKey('nx-progress'),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
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
                          key: const ValueKey('nx-go'),
                          onPressed: busy
                              ? null
                              : () async {
                                  setSheet(() => busy = true);
                                  final r = await onRun(pick == 'cur' ? folderLabel : '');
                                  if (!bc2.mounted) return;
                                  Navigator.pop(bc);
                                  if (r != null && context.mounted) {
                                    AppToast.show(context, r.line);
                                  }
                                },
                          child: const Text('选择目录并导出'))),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
