// 模块3 笔记文件夹（note_folders 表 · V1.29 多层嵌套树）。
// notes.folder 仍存文件夹名（筛选按名精确匹配），本表只承载层级与重命名/删除语义。

/// V1.64 批1（工单 §4 拍板 D/F）：系统「打开方式」进来的 md 归集的固定临时夹。
/// N-4 历史列表即该夹内容；删除守卫见 NoteFolderDao.deleteTree。
const kSystemOpenFolder = '系统打开';

class NoteFolder {
  const NoteFolder({
    this.id,
    required this.name,
    this.parentId,
    this.sort = 0,
  });

  final int? id;
  final String name;
  final int? parentId;
  final int sort;

  static NoteFolder fromRow(Map<String, Object?> row) => NoteFolder(
        id: row['id'] as int?,
        name: row['name'] as String,
        parentId: row['parent_id'] as int?,
        sort: (row['sort'] as int?) ?? 0,
      );

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'name': name,
        'parent_id': parentId,
        'sort': sort,
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
