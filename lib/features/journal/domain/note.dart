/// 模块3 笔记条目（notes 表；M0 仅收集箱分流写入，编辑能力 M1 开放）。
class Note {
  const Note({
    this.id,
    required this.title,
    required this.content,
    this.kind = 'plain',
    this.folder,
    this.pinned = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String title;
  final String content;
  final String kind;
  final String? folder;
  final bool pinned;
  final DateTime createdAt;
  final DateTime updatedAt;

  static Note fromRow(Map<String, Object?> row) => Note(
        id: row['id'] as int?,
        title: (row['title'] as String?) ?? '',
        content: (row['content'] as String?) ?? '',
        kind: (row['kind'] as String?) ?? 'plain',
        folder: row['folder'] as String?,
        pinned: (row['pinned'] as int? ?? 0) == 1,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      );

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'title': title,
        'content': content,
        'kind': kind,
        'folder': folder,
        'pinned': pinned ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };
}
