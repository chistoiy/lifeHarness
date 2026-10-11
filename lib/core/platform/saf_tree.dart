/// V1.64 批2（工单 交棒话术-20261004 §12 面板 · N-1 本地导入）：SAF 目录/多文件通道。
///
/// 为什么自研而不吃 file_picker：目录档要 `OPEN_DOCUMENT_TREE`＋**可持久化读授权**
/// （工单 §3 红线：一律 SAF，禁 `MANAGE_EXTERNAL_STORAGE`），并且要能递归列目录树、
/// 按 URI 读正文——file_picker 的 `getDirectoryPath()` 只给一条路径字符串，
/// 分区存储下既读不到子项也留不住授权。原生实现落 `MainActivity.kt` 的 `lh/saf`。
///
/// 返回语义：选择器取消＝null／空列表；列树/读文档失败抛 [PlatformException]
/// （调用侧兜底成人话提示，不静默）。真 IO 一律走可替换缝（widget 测试 FakeAsync
/// 禁真通道，同 `open_intent.dart` 的 `noteWriteBack` 定式）。
library;

import 'package:flutter/services.dart';

const MethodChannel _safChannel = MethodChannel('lh/saf');

/// 目录树节点（原生 `listTree`/`pickFiles` 的解析结果；uri＝content 文档 URI）。
class SafDoc {
  const SafDoc(
      {required this.name,
      required this.uri,
      required this.isDir,
      this.path = '',
      this.children = const []});

  final String name;
  final String uri;
  final bool isDir;

  /// 人话路径（原生给的 document 尾段，形如 `Download/外来笔记夹`；可空）。
  final String path;
  final List<SafDoc> children;
}

/// 原生 map → [SafDoc]（纯函数，测试直接喂假 map）。
SafDoc parseSafDoc(Map<Object?, Object?> raw) => SafDoc(
      name: (raw['name'] as String?) ?? '',
      uri: (raw['uri'] as String?) ?? '',
      isDir: (raw['dir'] as bool?) ?? false,
      path: (raw['path'] as String?) ?? '',
      children: [
        for (final e in (raw['children'] as List<Object?>? ?? const []))
          if (e is Map) parseSafDoc(e),
      ],
    );

List<SafDoc> parseSafDocs(List<Object?>? raw) => [
      for (final e in raw ?? const [])
        if (e is Map) parseSafDoc(e),
    ];

/// 系统目录选择器：返回拿到持久化读授权的 tree URI（取消＝null）。
Future<String?> Function() safPickTree = () async {
  final uri = await _safChannel.invokeMethod<String?>('pickTree');
  return (uri == null || uri.isEmpty) ? null : uri;
};

/// 列目录树：原生回**所选目录这一个根节点**（children 递归·只收目录与 .md/.markdown）。
Future<SafDoc> Function(String treeUri) safListTree = (treeUri) async {
  final raw = await _safChannel
      .invokeMethod<Map<Object?, Object?>>('listTree', {'uri': treeUri});
  if (raw == null) {
    throw PlatformException(code: 'empty', message: '目录读不到');
  }
  return parseSafDoc(raw);
};

/// 系统多选文件选择器（笔记扩展名档）：取消＝空表。
Future<List<SafDoc>> Function() safPickFiles = () async => parseSafDocs(
    await _safChannel.invokeMethod<List<Object?>>('pickFiles',
        {'notesOnly': true}));

/// 按 URI 读文本正文（UTF-8；读不到抛）。
Future<String?> Function(String uri) safReadText = (uri) async =>
    await _safChannel.invokeMethod<String>('readDoc', {'uri': uri});

/// 目录树里落盘的返回（code＝ok|no_perm|error；name＝实际文件名）。
class MountWriteResult {
  const MountWriteResult(
      {required this.code, this.uri = '', this.name = '', this.localPath = ''});

  final String code;
  final String uri;
  final String name;

  /// 人话位置（原生给的 document 尾段，提示里要说「写到哪」）。
  final String localPath;

  bool get ok => code == 'ok';
}

/// 在已授权目录树里新建（或覆写）一个文件并落内容（真机反馈批③·挂载即双向；批3 导出附件）。
/// 同名由原生自动追加 (2)(3)…；失败按码返回不抛（写盘失败绝不吞掉应用内的保存）。
///
/// 批3 新增两个**可选**形参（不传＝批2 行为逐字节不变）：
///  · [mime]＝文档类型（缺省 md；附件传 image/* 等，原生按此建档）；
///  · [srcPath]＝给定时**按字节流拷这个本地文件**（图片是二进制，走 text 必坏），此时 [text] 忽略。
/// [relPath] 只**查找**、不建目录——要目录先走 [safEnsureDirInTree]（批2 写回「老挂载目录
/// 被删了就落浅层」的语义因此不动，导出包的 `_assets/` 也不靠这条暗道）。
Future<MountWriteResult> Function(
        {required String tree,
        required String relPath,
        required String name,
        required String text,
        String mime,
        String srcPath})
    safCreateInTree = ({
  required String tree,
  required String relPath,
  required String name,
  required String text,
  String mime = 'text/markdown',
  String srcPath = '',
}) async {
  final raw = await _safChannel.invokeMethod<Map<Object?, Object?>>(
      'createInTree', {
    'tree': tree,
    'relPath': relPath,
    'name': name,
    'text': text,
    'mime': mime,
    if (srcPath.isNotEmpty) 'srcPath': srcPath,
  });
  if (raw == null) return const MountWriteResult(code: 'error');
  return MountWriteResult(
    code: (raw['code'] as String?) ?? 'error',
    uri: (raw['uri'] as String?) ?? '',
    name: (raw['name'] as String?) ?? '',
    localPath: (raw['localPath'] as String?) ?? '',
  );
};

/// 在授权树里按 [relPath] 逐级建目录后再建（**或复用**）一层 [name] 目录（批3 导出）。
/// 复用是硬要求：`createDocument(MIME_TYPE_DIR)` 撞同名会自己追加「 (2)」，
/// 导两次就得到两个 `_assets (2)`＝脏盘。失败按码返回不抛。
Future<MountWriteResult> Function(
        {required String tree, required String relPath, required String name})
    safEnsureDirInTree = ({
  required String tree,
  required String relPath,
  required String name,
}) async {
  final raw = await _safChannel.invokeMethod<Map<Object?, Object?>>(
      'ensureDirInTree',
      {'tree': tree, 'relPath': relPath, 'name': name});
  if (raw == null) return const MountWriteResult(code: 'error');
  return MountWriteResult(
    code: (raw['code'] as String?) ?? 'error',
    uri: (raw['uri'] as String?) ?? '',
    name: (raw['name'] as String?) ?? '',
    localPath: (raw['localPath'] as String?) ?? '',
  );
};
