import 'book.dart' show splitTags, decodeStringList;

/// 一条书摘（book_quotes 表 · 计划 §2.1 / §3.3）。
///
/// 硬约束（需求 模块4）：原文 [body] 与感想 [thought] 存同一行的两个字段，
/// 而非两条记录；一条摘录只属于一本书（[bookId] NOT NULL，不跨书合并 · §9 已拍板②）。
/// - [tag] ＝划线颜色分类单选（重点|共鸣|待查证|行动|疑问，颜色同源 BS_QTAGS）；
/// - [tags] ＝多选标签（逗号分隔，笔记库按标签筛选与卡片展示）；
/// - [createdAt] 允许补记改写（手动/OCR/导入渠道走 [origin] 溯源）。
class BookQuote {
  const BookQuote({
    this.id,
    required this.bookId,
    required this.kind,
    this.tag = kTagReso,
    this.tags = const [],
    this.body = '',
    this.thought,
    this.chapter,
    this.page,
    this.loc,
    this.imagePaths = const [],
    this.starred = false,
    this.origin,
    this.dedupHash,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  static const kKindMark = '划线';
  static const kKindThought = '感想';
  static const kinds = [kKindMark, kKindThought];

  /// 划线颜色分类（与原型 BS_QTAGS c1~c5 顺序一致）。
  static const kTagKey = '重点';
  static const kTagReso = '共鸣';
  static const kTagCheck = '待查证';
  static const kTagAct = '行动';
  static const kTagQues = '疑问';
  static const colorTags = [kTagKey, kTagReso, kTagCheck, kTagAct, kTagQues];

  /// 分类 → 色值（书摘卡左边条与笔记库标签同源）。
  static const colorHex = {
    kTagKey: '6366F1',
    kTagReso: '2DD4BF',
    kTagCheck: 'FB7185',
    kTagAct: 'F59E0B',
    kTagQues: '8B5CF6',
  };

  static int? hexToInt(String? h) =>
      h == null ? null : int.tryParse(h, radix: 16);

  final int? id;
  final String bookId;
  final String kind;
  final String tag;
  final List<String> tags;
  final String body;
  final String? thought;
  final String? chapter;
  final int? page;
  final double? loc;
  final List<String> imagePaths;
  final bool starred;
  final String? origin;
  final String? dedupHash;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;

  int get colorInt => int.tryParse(colorHex[tag] ?? colorHex[kTagReso]!, radix: 16) ?? 0;

  static BookQuote fromRow(Map<String, Object?> r) => BookQuote(
        id: r['id'] as int?,
        bookId: r['book_id'] as String,
        kind: r['kind'] as String,
        tag: (r['tag'] as String?) ?? kTagReso,
        tags: splitTags(r['tags'] as String?),
        body: (r['body'] as String?) ?? '',
        thought: r['thought'] as String?,
        chapter: r['chapter'] as String?,
        page: r['page'] as int?,
        loc: (r['loc'] as num?)?.toDouble(),
        imagePaths: decodeStringList(r['image_paths'] as String?),
        starred: ((r['starred'] as int?) ?? 0) == 1,
        origin: r['origin'] as String?,
        dedupHash: r['dedup_hash'] as String?,
        createdAt: r['created_at'] as int,
        updatedAt: r['updated_at'] as int,
        deletedAt: r['deleted_at'] as int?,
      );

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'book_id': bookId,
        'kind': kind,
        'tag': tag,
        'tags': tags.join(','),
        'body': body,
        'thought': thought,
        'chapter': chapter,
        'page': page,
        'loc': loc,
        'image_paths':
            imagePaths.isEmpty ? null : '[${imagePaths.map((e) => '"$e"').join(',')}]',
        'starred': starred ? 1 : 0,
        'origin': origin,
        'dedup_hash': dedupHash,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
      };

  BookQuote copyWith({
    String? kind,
    String? tag,
    List<String>? tags,
    String? body,
    String? thought,
    String? chapter,
    int? page,
    double? loc,
    List<String>? imagePaths,
    bool? starred,
    String? origin,
    String? dedupHash,
    int? createdAt,
    int? updatedAt,
    int? deletedAt,
  }) =>
      BookQuote(
        id: id,
        bookId: bookId,
        kind: kind ?? this.kind,
        tag: tag ?? this.tag,
        tags: tags ?? this.tags,
        body: body ?? this.body,
        thought: thought ?? this.thought,
        chapter: chapter ?? this.chapter,
        page: page ?? this.page,
        loc: loc ?? this.loc,
        imagePaths: imagePaths ?? this.imagePaths,
        starred: starred ?? this.starred,
        origin: origin ?? this.origin,
        dedupHash: dedupHash ?? this.dedupHash,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt ?? this.deletedAt,
      );
}
