import 'dart:convert';

/// 模块3 笔记条目（notes 表；M0 仅收集箱分流写入，M1 批1 开放编辑与管理）。
class Note {
  const Note({
    this.id,
    required this.title,
    required this.content,
    this.kind = 'plain',
    this.folder,
    this.pinned = false,
    this.archived = false,
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String title;
  final String content;
  final String kind;
  final String? folder;
  final bool pinned;
  final bool archived;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 富文本(kind=rich)正文=Quill Delta JSON；其余类型原样返回。
  /// 非 JSON（批B 前的占位/手输数据）容错回退原文；嵌入对象（图片）以 🖼 占位。
  static String richToPlain(String content) {
    try {
      final ops = jsonDecode(content);
      if (ops is! List) return content;
      final sb = StringBuffer();
      for (final op in ops) {
        if (op is! Map) continue;
        final insert = op['insert'];
        if (insert is String) {
          sb.write(insert);
        } else if (insert is Map) {
          sb.write(insert.containsKey('image') ? '🖼' : '▪');
        }
      }
      return sb.toString();
    } catch (_) {
      return content;
    }
  }

  /// 面向展示/计数/导出的正文（rich 去 Delta JSON 痕迹）。
  String get plainBody => kind == 'rich' ? richToPlain(content) : content;

  /// 列表预览：去标题行与换行，截 40 字。
  String get preview {
    final body = plainBody.replaceAll('\r', '').trim();
    if (body.isEmpty) return '（空白笔记）';
    return body.length <= 40 ? body : '${body.substring(0, 40)}…';
  }

  int get wordCount => plainBody.replaceAll(RegExp(r'\s'), '').length;

  static Note fromRow(Map<String, Object?> row) => Note(
        id: row['id'] as int?,
        title: (row['title'] as String?) ?? '',
        content: (row['content'] as String?) ?? '',
        kind: (row['kind'] as String?) ?? 'plain',
        folder: row['folder'] as String?,
        pinned: (row['pinned'] as int? ?? 0) == 1,
        archived: (row['archived'] as int? ?? 0) == 1,
        deletedAt: row['deleted_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row['deleted_at'] as int),
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
        'archived': archived ? 1 : 0,
        'deleted_at': deletedAt?.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  Note copyWith({
    int? id,
    String? title,
    String? content,
    String? kind,
    String? folder,
    bool? pinned,
    bool? archived,
    DateTime? deletedAt,
    DateTime? updatedAt,
  }) =>
      Note(
        id: id ?? this.id,
        title: title ?? this.title,
        content: content ?? this.content,
        kind: kind ?? this.kind,
        folder: folder ?? this.folder,
        pinned: pinned ?? this.pinned,
        archived: archived ?? this.archived,
        deletedAt: deletedAt ?? this.deletedAt,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
