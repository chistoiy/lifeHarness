import 'dart:convert';

import '../../../core/logging/app_log.dart';

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
    this.paper = '',
    this.source = '',
    this.originPath = '',
    this.originUri = '',
    this.openedAt,
    this.srcHash = '',
    this.wbAt,
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

  /// V1.29轮9n：按篇纸色 hex（0xFFRRGGBB）；''=默认米纸。仅卡片视图条目底色跟随。
  final String paper;

  /// V1.64 批1（工单 §4 拍板 B/E）：来源标记＝''(应用内自建) | open_with(系统打开)
  /// | local_dir / local_file(本地导入)。编辑不抹标；判重/回写按此分派。
  final String source;

  /// 来源展示名（文件名/目录内相对路径；仅本地来源与打开方式有值）。
  final String originPath;

  /// 原始 content URI 字符串（open_with 回写锚点；local_* 为空）。
  final String originUri;

  /// 经系统打开的最近一次导入时间（N-4 历史行读数；其余为 null）。
  final DateTime? openedAt;

  /// V1.64 批4（DB v43·工单 §18.1）：**最后一次成功回写原始文件**的时间。
  /// null＝从没回写成功过（含从没保存过）。三态里「已回写原文件」与「仅应用内」的唯一依据＝
  /// 本列与 `updatedAt` 的先后（`wbAt != null && wbAt >= updatedAt`＝回写后没再改过）。
  final DateTime? wbAt;

  /// V1.64 批2（N-1）：内容哈希（sha256 前 16 位十六进制）。仅本地导入/打开方式
  /// 写入时算好落库；导入侧按「同哈希＋在册行」判重跳过（回收站行不参与）。
  /// ''＝应用内自建或批2 前的存量行（不参与判重，避免把老数据误判成重复）。
  final String srcHash;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 富文本(kind=rich)正文=Quill Delta JSON；其余类型原样返回。
  /// 非 JSON（批B 前的占位/手输数据）容错回退原文；嵌入对象以「图片」文字占位（轮10 去 emoji）。
  /// 批2b：带 list=todo/unchecked/checked 属性的行渲染为 ☐/☑ 前缀——
  /// 日记/笔记 L3 待办同步（todoLines 解析 ☐）在富文本下继续成立。
  static String richToPlain(String content) {
    try {
      final ops = jsonDecode(content);
      if (ops is! List) return content;
      final sb = StringBuffer();
      for (final op in ops) {
        if (op is! Map) continue;
        final insert = op['insert'];
        if (insert is String) {
          final attrs = op['attributes'];
          final list = attrs is Map ? attrs['list'] : null;
          final isTodo = list == 'todo' || list == 'unchecked' || list == 'checked';
          if (isTodo && insert.endsWith('\n')) {
            sb.write(list == 'checked' ? '☑ ' : '☐ ');
          }
          sb.write(insert);
        } else if (insert is Map) {
          sb.write(insert.containsKey('image') ? '图片' : '▪');
        }
      }
      return sb.toString();
    } catch (err) {
      AppLog.add('笔记正文非 quill JSON，摘要回退原文：$err', level: LhLevel.warn);
      return content;
    }
  }

  /// 面向展示/计数/导出的正文（rich 去 Delta JSON 痕迹）。
  String get plainBody => kind == 'rich' ? richToPlain(content) : content;

  /// 展示/计数用正文：rich 去 JSON，非 rich 去 Markdown 图片本地语法（→alt/图片）。
  String get displayBody =>
      kind == 'rich' ? richToPlain(content) : stripMdImages(content);

  /// 图片本地语法 ![alt](path) → alt（无 alt 则「图片」），避免长路径进预览/字数。
  static String stripMdImages(String s) => s
      .replaceAllMapped(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), (m) {
        final alt = m.group(1) ?? '';
        return alt.isEmpty ? '图片' : alt;
      });

  /// 列表预览：去标题行与换行，截 40 字。
  String get preview {
    final body = displayBody.replaceAll('\r', '').trim();
    if (body.isEmpty) return '（空白笔记）';
    return body.length <= 40 ? body : '${body.substring(0, 40)}…';
  }

  int get wordCount => displayBody.replaceAll(RegExp(r'\s'), '').length;

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
        paper: (row['paper'] as String?) ?? '',
        source: (row['source'] as String?) ?? '',
        originPath: (row['origin_path'] as String?) ?? '',
        originUri: (row['origin_uri'] as String?) ?? '',
        openedAt: row['opened_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row['opened_at'] as int),
        srcHash: (row['src_hash'] as String?) ?? '',
        wbAt: row['wb_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row['wb_at'] as int),
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
        'paper': paper,
        'source': source,
        'origin_path': originPath,
        'origin_uri': originUri,
        'opened_at': openedAt?.millisecondsSinceEpoch,
        'src_hash': srcHash,
        'wb_at': wbAt?.millisecondsSinceEpoch,
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
    String? paper,
    String? source,
    String? originPath,
    String? originUri,
    DateTime? openedAt,
    String? srcHash,
    DateTime? wbAt,
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
        paper: paper ?? this.paper,
        source: source ?? this.source,
        originPath: originPath ?? this.originPath,
        originUri: originUri ?? this.originUri,
        openedAt: openedAt ?? this.openedAt,
        srcHash: srcHash ?? this.srcHash,
        wbAt: wbAt ?? this.wbAt,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
