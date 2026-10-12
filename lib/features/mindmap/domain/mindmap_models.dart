/// 思维导图域模型（批1 · 需求模块 18）。
///
/// 节点坐标口径（冻结方案 2d/B4）：模型里**只有偏移** `dx/dy`（相对自动布局基线），
/// 绝对位置＝布局引擎输出＋偏移，不落库。折叠态 `folded` 持久化（C10）；
/// 视图态（scale/tx/ty）不持久化（C11，进图 fit 到内容＝有意取舍）。
library;

/// 一张导图（`mindmaps` 行）。
class Mindmap {
  const Mindmap({
    this.id,
    required this.title,
    this.folderId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final int? id;
  final String title;

  /// 归入的文件夹（批2 F4-4；null＝未归入；删文件夹只置空引用不删图）。
  final int? folderId;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;

  bool get isDeleted => deletedAt != null;

  factory Mindmap.fromRow(Map<String, Object?> row) => Mindmap(
        id: row['id'] as int?,
        title: row['title'] as String? ?? '',
        folderId: row['folder_id'] as int?,
        createdAt: row['created_at'] as int? ?? 0,
        updatedAt: row['updated_at'] as int? ?? 0,
        deletedAt: row['deleted_at'] as int?,
      );

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'title': title,
        'folder_id': folderId,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
      };

  Mindmap copyWith({
    int? id,
    String? title,
    int? folderId,
    bool clearFolder = false,
    int? updatedAt,
  }) =>
      Mindmap(
        id: id ?? this.id,
        title: title ?? this.title,
        folderId: clearFolder ? null : (folderId ?? this.folderId),
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt,
      );
}

/// 一个文件夹（`mindmap_folders` 行，批2 F4-4）。单层用法 `parentId` 恒 null
///（列留多层树口，将来扩多级零再迁移）。
class MindmapFolder {
  const MindmapFolder({
    this.id,
    required this.title,
    this.parentId,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String title;
  final int? parentId;
  final int createdAt;
  final int updatedAt;

  factory MindmapFolder.fromRow(Map<String, Object?> row) => MindmapFolder(
        id: row['id'] as int?,
        title: row['title'] as String? ?? '',
        parentId: row['parent_id'] as int?,
        createdAt: row['created_at'] as int? ?? 0,
        updatedAt: row['updated_at'] as int? ?? 0,
      );
}

/// 一个节点（`mindmap_nodes` 行）。树关系只靠 `parentId`（null＝根）。
class MindmapNode {
  const MindmapNode({
    this.id,
    required this.mapId,
    this.parentId,
    this.noteId,
    required this.title,
    this.note = '',
    this.side,
    this.sort = 0,
    this.dx = 0,
    this.dy = 0,
    this.folded = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final int mapId;

  /// 父节点 id；null＝根节点（一图多根，C6）。
  final int? parentId;

  /// 挂载笔记引用（连接点①；null＝未挂）。只存引用不存快照——
  /// 显示标题实时取笔记标题（C4/H3 裁定），笔记删除回落占位（B6）。
  final int? noteId;

  final String title;

  /// 节点备注（画布不显示，编辑弹层读回改写——H2 口径：写得进也读得回）。
  final String note;

  /// 左右归属标记（6b：`'l'/'r'` 可空，空＝布局引擎自动分配；批1 tree 引擎统一右置）。
  final String? side;

  /// 兄弟序（整数显式序，不靠 rowid）。
  final int sort;

  /// 相对自动布局基线的偏移（拖拽定位；不存绝对坐标）。
  final double dx;
  final double dy;

  /// 折叠子级（持久化，C10）。true＝子级不参与布局与绘制。
  final bool folded;

  final int createdAt;
  final int updatedAt;

  /// 拖拽是否有过非零偏移（「归位」按钮只在有偏移时显示的依据）。
  bool get hasOffset => dx != 0 || dy != 0;

  factory MindmapNode.fromRow(Map<String, Object?> row) => MindmapNode(
        id: row['id'] as int?,
        mapId: row['map_id'] as int,
        parentId: row['parent_id'] as int?,
        noteId: row['note_id'] as int?,
        title: row['title'] as String? ?? '',
        note: row['note'] as String? ?? '',
        side: row['side'] as String?,
        sort: row['sort'] as int? ?? 0,
        dx: (row['dx'] as num?)?.toDouble() ?? 0,
        dy: (row['dy'] as num?)?.toDouble() ?? 0,
        folded: (row['folded'] as int? ?? 0) != 0,
        createdAt: row['created_at'] as int? ?? 0,
        updatedAt: row['updated_at'] as int? ?? 0,
      );

  MindmapNode copyWith({
    int? id,
    int? parentId,
    int? noteId,
    String? title,
    String? note,
    String? side,
    int? sort,
    double? dx,
    double? dy,
    bool? folded,
    bool clearParent = false,
    bool clearNote = false,
    int? updatedAt,
  }) =>
      MindmapNode(
        id: id ?? this.id,
        mapId: mapId,
        parentId: clearParent ? null : (parentId ?? this.parentId),
        noteId: clearNote ? null : (noteId ?? this.noteId),
        title: title ?? this.title,
        note: note ?? this.note,
        side: side ?? this.side,
        sort: sort ?? this.sort,
        dx: dx ?? this.dx,
        dy: dy ?? this.dy,
        folded: folded ?? this.folded,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
