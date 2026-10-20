// 模块3 笔记文件夹（note_folders 表 · V1.29 多层嵌套树）。
// notes.folder 仍存文件夹名（筛选按名精确匹配），本表只承载层级与重命名/删除语义。

/// V1.64 批1（工单 §4 拍板 D/F）：系统「打开方式」进来的 md 归集的固定临时夹。
/// N-4 历史列表即该夹内容；删除守卫见 NoteFolderDao.deleteTree。
const kSystemOpenFolder = '系统打开';

/// V1.67（产品令「所有笔记必须有目录归属」）：未选夹的新笔记自动归入的兜底夹。
/// 夹不存在则建（顶层·sort 顺延）；用户自建同名夹直接复用。删除守卫见 NoteFolderDao。
const kDefaultNoteFolder = '默认';

class NoteFolder {
  const NoteFolder({
    this.id,
    required this.name,
    this.parentId,
    this.sort = 0,
    this.source = '',
    this.originPath = '',
    this.originUri = '',
  });

  final int? id;
  final String name;
  final int? parentId;
  final int sort;

  /// V1.64 批2（工单 §1.2 N-1c · 拍板 H）：该夹是否＝「手机里某目录的挂载」。
  /// ''=应用内手建 | local_dir(本地导入的目录) | export(导出目录·只读挂载)。
  /// 挂载夹在树内长按给「移除」＝只摘本表这些行，磁盘原件与库内笔记都不动。
  final String source;

  /// 挂载来源展示路径（目录名/相对路径；仅挂载夹有值，确认层与列表用）。
  final String originPath;

  /// 挂载的 SAF tree URI（权限持久化锚点；手建夹为空）。
  final String originUri;

  /// 树上可给「移除挂载」入口的两类（手建夹与固定「系统打开」夹都不在内）。
  bool get isMount => source == 'local_dir' || source == 'export';

  static NoteFolder fromRow(Map<String, Object?> row) => NoteFolder(
        id: row['id'] as int?,
        name: row['name'] as String,
        parentId: row['parent_id'] as int?,
        sort: (row['sort'] as int?) ?? 0,
        source: (row['source'] as String?) ?? '',
        originPath: (row['origin_path'] as String?) ?? '',
        originUri: (row['origin_uri'] as String?) ?? '',
      );

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'name': name,
        'parent_id': parentId,
        'sort': sort,
        'source': source,
        'origin_path': originPath,
        'origin_uri': originUri,
      };
}

/// 树节点（渲染用：folder + 子节点 + 直属笔记数）。
class FolderNode {
  const FolderNode({required this.folder, required this.children, this.noteCount = 0});

  final NoteFolder folder;
  final List<FolderNode> children;
  final int noteCount;

  int get id => folder.id!;
  String get name => folder.name;
}
