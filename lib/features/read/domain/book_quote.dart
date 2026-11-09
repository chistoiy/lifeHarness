import 'dart:convert';

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
    this.cf,
    this.rid,
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
  // V1.50 阅读器同库口径（DB v25 两列）：[cf]＝划线出处的章+段落区间，
  // [rid]＝阅读器高亮稳定标识（编辑摘录时二者必须保留 · qeSave 守卫同语义）。
  final QuoteCf? cf;
  final String? rid;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;

  int get colorInt =>
      int.tryParse(colorHex[tag] ?? colorHex[kTagReso]!, radix: 16) ?? 0;

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
    cf: QuoteCf.decode(r['cf'] as String?),
    rid: r['rid'] as String?,
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
    'image_paths': imagePaths.isEmpty
        ? null
        : '[${imagePaths.map((e) => '"$e"').join(',')}]',
    'starred': starred ? 1 : 0,
    'origin': origin,
    'dedup_hash': dedupHash,
    'cf': cf?.encode(),
    'rid': rid,
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
    QuoteCf? cf,
    String? rid,
    int? createdAt,
    int? updatedAt,
    int? deletedAt,
  }) => BookQuote(
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
    cf: cf ?? this.cf,
    rid: rid ?? this.rid,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );
}

/// 划线出处 CFI 区间（book_quotes.cf 列 JSON 值 · V1.50 数据口径①）。
///
/// [c]＝章序（0 基，对应阅读器 spine 叶子章），[p0]~[p1]＝段落下标闭区间。
/// 原型形态 `cf:{c,p0,p1}`；阅读器高亮渲染与「跳原文」都以此为唯一锚点。
/// V1.59 轮4① 扩字符级：[o0]＝`p0` 段内起始偏移、[o1]＝`p1` 段内结束偏移
/// （原文坐标系，不含缩进前缀；简繁转换逐字等长不破坏对齐）。
/// **旧行无偏移 decode 回 null＝维持整段旧行为**（向后兼容，JSON 列内零迁移）。
class QuoteCf {
  const QuoteCf({
    required this.c,
    required this.p0,
    required this.p1,
    this.o0,
    this.o1,
  });

  final int c;
  final int p0;
  final int p1;
  final int? o0;
  final int? o1;

  static QuoteCf? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final v = jsonDecode(raw);
      if (v is! Map) return null;
      final c = (v['c'] as num?)?.toInt();
      final p0 = (v['p0'] as num?)?.toInt();
      final p1 = (v['p1'] as num?)?.toInt();
      if (c == null || p0 == null || p1 == null) return null;
      return QuoteCf(
        c: c,
        p0: p0,
        p1: p1,
        o0: (v['o0'] as num?)?.toInt(),
        o1: (v['o1'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode({
    'c': c,
    'p0': p0,
    'p1': p1,
    if (o0 != null) 'o0': o0,
    if (o1 != null) 'o1': o1,
  });

  /// 命中判定：章相同且段落落在闭区间内（阅读器逐段上色用）。
  bool covers(int chapter, int para) =>
      chapter == c && para >= p0 && para <= p1;

  /// 任一端带偏移＝可按字符区间精确铺底（旧整段行两皆 null → false）。
  bool get isPrecise => o0 != null || o1 != null;

  /// 段 [pi]（原文长 [len]）内的上色闭区间；未命中＝null。
  /// 首尾段各切一头，中间段整段；缺省端按段边补齐。
  ({int a, int b})? rangeAt(int pi, int len) {
    if (pi < p0 || pi > p1) return null;
    final a = pi == p0 ? (o0 ?? 0) : 0;
    final b = pi == p1 ? (o1 ?? len) : len;
    return (a: a.clamp(0, len), b: b.clamp(a.clamp(0, len), len));
  }
}
