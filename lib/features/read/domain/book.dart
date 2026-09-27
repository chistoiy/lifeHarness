import 'dart:convert';

/// 一本书（books 表 · M1批3 计划 §2.1）。
///
/// 口径：
/// - [state] ∈ 在读|想读|已读|弃读（书架四分区）；
/// - [format] ∈ 纸质|电子书|有声（决定默认进度方式）；
/// - [progressWay] ∈ page|pos|chap|pct|min；
/// - [tags] 逗号分隔（书架标签维度 / 批量加标签）；
/// - [lastReadAt] 聚合索引列＝max(开始/读完/摘录/会话 ended_at)，「最近阅读」倒序口径（§3.2）；
/// - [sumQuote]/[sumView]/[sumGain] 一页式总结人工覆写，全空即走自动生成（§3.3）。
class Book {
  const Book({
    this.id = '',
    required this.title,
    this.author = '佚名',
    this.translator,
    this.publisher,
    this.pubDate,
    this.series,
    this.isbn,
    this.coverPath,
    this.colorIdx = 0,
    this.state = kStateWant,
    this.format = kFormatPaper,
    this.progressWay = kWayPage,
    this.pages = 0,
    this.readPages = 0,
    this.totalLoc,
    this.readLoc,
    this.chapter,
    this.rating = 0,
    this.fee = 0,
    this.feeTxnId,
    this.source,
    this.grp,
    this.tags = const [],
    this.startedAt,
    this.endedAt,
    this.lastReadAt,
    this.intro,
    this.authorNote,
    this.note,
    this.finalNote,
    this.sumQuote,
    this.sumView,
    this.sumGain,
    this.wordCount = 0,
    this.binding,
    this.feeDate,
    this.local = false,
    this.epub,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  // ---- 取值域常量（与计划 §2.1 / 原型 BS_STS / fmt 对齐）----
  static const kStateReading = '在读';
  static const kStateWant = '想读';
  static const kStateDone = '已读';
  static const kStateDropped = '弃读';
  static const states = [kStateReading, kStateWant, kStateDone, kStateDropped];

  static const kFormatPaper = '纸质';
  static const kFormatEbook = '电子书';
  static const kFormatAudio = '有声';
  static const formats = [kFormatPaper, kFormatEbook, kFormatAudio];

  static const kWayPage = 'page';
  static const kWayPos = 'pos';
  static const kWayChap = 'chap';
  static const kWayPct = 'pct';
  static const kWayMin = 'min';

  /// format → 默认进度方式（编辑页换类型未手动改过进度方式时带出）。
  static String defaultWayFor(String format) => switch (format) {
    kFormatEbook => kWayPos,
    kFormatAudio => kWayMin,
    _ => kWayPage,
  };

  final String id;
  final String title;
  final String author;
  final String? translator;
  final String? publisher;
  final String? pubDate;
  final String? series;
  final String? isbn;
  final String? coverPath;
  final int colorIdx;
  final String state;
  final String format;
  final String progressWay;
  final int pages;
  final int readPages;
  final double? totalLoc;
  final double? readLoc;
  final String? chapter;
  final double rating;
  final double fee;
  final int? feeTxnId;
  final String? source;
  final String? grp;
  final List<String> tags;
  final int? startedAt;
  final int? endedAt;
  final int? lastReadAt;
  final String? intro;
  final String? authorNote;
  final String? note;
  final String? finalNote;
  final String? sumQuote;
  final String? sumView;
  final String? sumGain;
  // V1.44 先搜后加：字数/装帧/购入日期（DB v24 三列；豆瓣评分存 douban_meta 不加列）。
  final int wordCount;
  final String? binding;
  final String? feeDate;
  // V1.50 本地阅读器：local＝EPUB 导入书（点封面直达阅读器 + 角标），
  // epub＝源文件描述符（DB v25 两列；无新表，位置/外观走 settings KV）。
  final bool local;
  final EpubRef? epub;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;

  /// 进度百分比 0~100（整数口径与原型 `p` 一致）。
  /// 派生优先：pages>0 用页比；否则有位置用位置比；pct 覆写场景批2 随记进度落页数字段。
  int get percent {
    if (progressWay == kWayPos && (totalLoc ?? 0) > 0 && readLoc != null) {
      return (readLoc! / totalLoc! * 100).clamp(0, 100).round();
    }
    if (pages > 0) return (readPages / pages * 100).clamp(0, 100).round();
    if ((totalLoc ?? 0) > 0 && readLoc != null) {
      return (readLoc! / totalLoc! * 100).clamp(0, 100).round();
    }
    return 0;
  }

  bool get isReading => state == kStateReading;
  bool get isDeleted => deletedAt != null;

  /// 色板封面下标（原型 BS_COV 8 色，越界回绕）。
  int get paletteIdx => colorIdx % 8;

  static Book fromRow(Map<String, Object?> r) => Book(
    id: r['id'] as String,
    title: r['title'] as String,
    author: (r['author'] as String?) ?? '佚名',
    translator: r['translator'] as String?,
    publisher: r['publisher'] as String?,
    pubDate: r['pub_date'] as String?,
    series: r['series'] as String?,
    isbn: r['isbn'] as String?,
    coverPath: r['cover_path'] as String?,
    colorIdx: (r['color_idx'] as int?) ?? 0,
    state: (r['state'] as String?) ?? kStateWant,
    format: (r['format'] as String?) ?? kFormatPaper,
    progressWay: (r['progress_way'] as String?) ?? kWayPage,
    pages: (r['pages'] as int?) ?? 0,
    readPages: (r['read_pages'] as int?) ?? 0,
    totalLoc: (r['total_loc'] as num?)?.toDouble(),
    readLoc: (r['read_loc'] as num?)?.toDouble(),
    chapter: r['chapter'] as String?,
    rating: (r['rating'] as num?)?.toDouble() ?? 0,
    fee: (r['fee'] as num?)?.toDouble() ?? 0,
    feeTxnId: r['fee_txn_id'] as int?,
    source: r['source'] as String?,
    grp: r['grp'] as String?,
    tags: splitTags(r['tags'] as String?),
    startedAt: r['started_at'] as int?,
    endedAt: r['ended_at'] as int?,
    lastReadAt: r['last_read_at'] as int?,
    intro: r['intro'] as String?,
    authorNote: r['author_note'] as String?,
    note: r['note'] as String?,
    finalNote: r['final_note'] as String?,
    sumQuote: r['sum_quote'] as String?,
    sumView: r['sum_view'] as String?,
    sumGain: r['sum_gain'] as String?,
    wordCount: (r['word_count'] as int?) ?? 0,
    binding: r['binding'] as String?,
    feeDate: r['fee_date'] as String?,
    local: ((r['local'] as int?) ?? 0) == 1,
    epub: EpubRef.decode(r['epub'] as String?),
    createdAt: r['created_at'] as int,
    updatedAt: r['updated_at'] as int,
    deletedAt: r['deleted_at'] as int?,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'title': title,
    'author': author,
    'translator': translator,
    'publisher': publisher,
    'pub_date': pubDate,
    'series': series,
    'isbn': (isbn == null || isbn!.isEmpty) ? null : isbn,
    'cover_path': coverPath,
    'color_idx': colorIdx,
    'state': state,
    'format': format,
    'progress_way': progressWay,
    'pages': pages,
    'read_pages': readPages,
    'total_loc': totalLoc,
    'read_loc': readLoc,
    'chapter': chapter,
    'rating': rating,
    'fee': fee,
    'fee_txn_id': feeTxnId,
    'source': source,
    'grp': grp,
    'tags': tags.join(','),
    'started_at': startedAt,
    'ended_at': endedAt,
    'last_read_at': lastReadAt,
    'intro': intro,
    'author_note': authorNote,
    'note': note,
    'final_note': finalNote,
    'sum_quote': sumQuote,
    'sum_view': sumView,
    'sum_gain': sumGain,
    'word_count': wordCount,
    'binding': binding,
    'fee_date': feeDate,
    'local': local ? 1 : 0,
    'epub': epub?.encode(),
    'created_at': createdAt,
    'updated_at': updatedAt,
    'deleted_at': deletedAt,
  };

  Book copyWith({
    String? title,
    String? author,
    String? translator,
    String? publisher,
    String? pubDate,
    String? series,
    String? isbn,
    String? coverPath,
    int? colorIdx,
    String? state,
    String? format,
    String? progressWay,
    int? pages,
    int? readPages,
    double? totalLoc,
    double? readLoc,
    String? chapter,
    double? rating,
    double? fee,
    int? feeTxnId,
    String? source,
    String? grp,
    List<String>? tags,
    int? startedAt,
    int? endedAt,
    int? lastReadAt,
    String? intro,
    String? authorNote,
    String? note,
    String? finalNote,
    String? sumQuote,
    String? sumView,
    String? sumGain,
    int? wordCount,
    String? binding,
    String? feeDate,
    bool? local,
    EpubRef? epub,
    int? updatedAt,
    int? deletedAt,
  }) => Book(
    id: id,
    title: title ?? this.title,
    author: author ?? this.author,
    translator: translator ?? this.translator,
    publisher: publisher ?? this.publisher,
    pubDate: pubDate ?? this.pubDate,
    series: series ?? this.series,
    isbn: isbn ?? this.isbn,
    coverPath: coverPath ?? this.coverPath,
    colorIdx: colorIdx ?? this.colorIdx,
    state: state ?? this.state,
    format: format ?? this.format,
    progressWay: progressWay ?? this.progressWay,
    pages: pages ?? this.pages,
    readPages: readPages ?? this.readPages,
    totalLoc: totalLoc ?? this.totalLoc,
    readLoc: readLoc ?? this.readLoc,
    chapter: chapter ?? this.chapter,
    rating: rating ?? this.rating,
    fee: fee ?? this.fee,
    feeTxnId: feeTxnId ?? this.feeTxnId,
    source: source ?? this.source,
    grp: grp ?? this.grp,
    tags: tags ?? this.tags,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt ?? this.endedAt,
    lastReadAt: lastReadAt ?? this.lastReadAt,
    intro: intro ?? this.intro,
    authorNote: authorNote ?? this.authorNote,
    note: note ?? this.note,
    finalNote: finalNote ?? this.finalNote,
    sumQuote: sumQuote ?? this.sumQuote,
    sumView: sumView ?? this.sumView,
    sumGain: sumGain ?? this.sumGain,
    wordCount: wordCount ?? this.wordCount,
    binding: binding ?? this.binding,
    feeDate: feeDate ?? this.feeDate,
    local: local ?? this.local,
    epub: epub ?? this.epub,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );
}

/// 本地 EPUB 源文件描述符（books.epub 列 JSON 值 · V1.50 数据口径③）。
///
/// [fmt] EPUB2|EPUB3（解析时识别）；[size] 源文件字节数；
/// [path] 应用私有目录内的副本路径（原文件保留原位，删书可选连副本移除）。
class EpubRef {
  const EpubRef({
    required this.fmt,
    required this.size,
    required this.path,
    this.st,
    this.pr = 0,
    this.srcPath,
    this.srcName,
  });

  final String fmt;
  final int size;

  /// 应用私有副本路径（阅读只读它；源文件永远保留原位）。
  final String path;

  /// 预载状态（批3.5）：'pre' 整本预载中（不可进阅读）· null/'rdy' 就绪 ·
  /// 'cl' 已清缓存（本地副本/分页表已回收，记录与书摘全保留）。
  final String? st;

  /// 预载进度 0~100（仅 st=='pre' 期间有意义）。
  final int pr;

  /// 源文件原始位置（重载入探测用；丢失则引导重选挂回）。
  final String? srcPath;

  /// 源文件名（重选时按名匹配挂回原记录）。
  final String? srcName;

  /// 归一状态：旧数据无 st 字段＝就绪。
  String get state => st == null || st!.isEmpty ? 'rdy' : st!;
  bool get preloadable => state == 'pre';
  bool get cleared => state == 'cl';

  static const stPreload = 'pre';
  static const stReady = 'rdy';
  static const stCleared = 'cl';

  EpubRef copyWith({
    String? fmt,
    int? size,
    String? path,
    String? st,
    int? pr,
    String? srcPath,
    String? srcName,
  }) => EpubRef(
    fmt: fmt ?? this.fmt,
    size: size ?? this.size,
    path: path ?? this.path,
    st: st ?? this.st,
    pr: pr ?? this.pr,
    srcPath: srcPath ?? this.srcPath,
    srcName: srcName ?? this.srcName,
  );

  static EpubRef? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final v = jsonDecode(raw);
      if (v is! Map) return null;
      final fmt = v['fmt']?.toString();
      final path = v['path']?.toString();
      if (fmt == null || path == null || path.isEmpty) return null;
      return EpubRef(
        fmt: fmt,
        size: (v['size'] as num?)?.toInt() ?? 0,
        path: path,
        st: v['st']?.toString(),
        pr: (v['pr'] as num?)?.toInt() ?? 0,
        srcPath: v['srcPath']?.toString(),
        srcName: v['srcName']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode({
    'fmt': fmt,
    'size': size,
    'path': path,
    if (st != null) 'st': st,
    if (pr != 0) 'pr': pr,
    if (srcPath != null) 'srcPath': srcPath,
    if (srcName != null) 'srcName': srcName,
  });
}

/// 逗号分隔标签列的进出工具（books.tags / book_quotes.tags 共用）。
List<String> splitTags(String? raw) => raw == null || raw.isEmpty
    ? const []
    : raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

/// JSON 数组列（image_paths）解析，坏值回空。
List<String> decodeStringList(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final v = jsonDecode(raw);
    return v is List ? v.map((e) => e.toString()).toList() : const [];
  } catch (_) {
    return const [];
  }
}
