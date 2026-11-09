import 'dart:convert';

import '../../../core/logging/app_log.dart';

/// 影音笔记（`media_notes` 表 · 影音游批5 · 计划 §五批3「影音笔记＋名场面复习」）。
///
/// 四条口径在模型层钉死：
/// - 五类子类型＝`scene|line|lyric|shot|long`（名场面/台词/歌词/截图/长评），
///   色标属 UI 侧（词典 LH-C18 按原型 `MTYPE_COLOR` 照抄），本类只给取值域与顺序；
/// - **复习档位落本行三列**（工单 §1.2 定案＝`review_stage`/`reviewed_at`/`next_review_at`，
///   零搬数据加列）：档位 0＝未排期，1/3/7 天三档走完＝[masteredStage]（不再排期）；
/// - [dedupHash] 判重键＝条目＋子项＋时间点＋归一化正文（与阅读侧摘录同式，
///   跨模块不 import＝architecture R1）；正文空＝无键（不参与判重，也存不进）；
/// - `image_paths`／`tags` 是 JSON 文本列，脏值（裸文本/坏 JSON/非列表）读成空列表
///   并走 AppLog 留痕，**不抛**——一条脏行不许炸掉整屏笔记库（守 catch_log_guard）。
class MediaNote {
  const MediaNote({
    this.id,
    required this.itemId,
    required this.kind,
    required this.noteType,
    required this.body,
    this.tag,
    this.thought,
    this.unitRef,
    this.atMin,
    this.imagePaths = const <String>[],
    this.tags = const <String>[],
    this.starred = false,
    this.createdAt = 0,
    this.updatedAt = 0,
    this.deletedAt,
    this.origin,
    this.dedupHash,
    this.reviewStage = 0,
    this.reviewedAt,
    this.nextReviewAt,
  });

  // ---- 取值域（顺序即筛选行顺序，原型 mNotes 同口径）----
  static const String kScene = 'scene';
  static const String kLine = 'line';
  static const String kLyric = 'lyric';
  static const String kShot = 'shot';
  static const String kLong = 'long';
  static const List<String> noteTypes = <String>[kScene, kLine, kLyric, kShot, kLong];

  /// 五类人话名（词典 LH-C18／筛选 chip 文案；色标在 UI 侧）。
  static const Map<String, String> typeLabels = <String, String>{
    kScene: '名场面',
    kLine: '台词',
    kLyric: '歌词',
    kShot: '截图',
    kLong: '长评',
  };

  /// 录入来源（`origin` 列）：手动／计时明细「记一次」／导入。
  static const String kOriginManual = 'manual';
  static const String kOriginSession = 'session';
  static const String kOriginImport = 'import';

  /// 艾宾浩斯三档（天）＝计划 L208 与原型 `m-review` 底栏三 chip 同一口径。
  /// 档位号 [stage] 直接当索引：0→次日 1 天，1→3 天，2→7 天，3＝走完不再排期。
  static const List<int> reviewGapsDays = <int>[1, 3, 7];
  static const int masteredStage = 3;

  static const int _dayMs = 24 * 60 * 60 * 1000;

  final int? id;
  final String itemId;

  /// 条目类别（`movie|series|music|game`，与 [MediaItemKind] 同源文本；
  /// 笔记自带一份＝笔记库跨条目筛 kind 时不必回查条目行）。
  final String kind;
  final String noteType;
  final String body;

  /// 单标签（原型 `MNOTES.tag`，筛选行⑤走这一列；[tags] 是多标签扩展位，本期录入只写一个）
  final String? tag;
  final String? thought;

  /// 子项外键（`media_units.id`：第几集／曲目／章节），无子项＝null。
  final int? unitRef;

  /// 时间点（分钟，自条目起点）；音乐/游戏可空。
  final int? atMin;
  final List<String> imagePaths;
  final List<String> tags;
  final bool starred;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final String? origin;
  final String? dedupHash;

  /// 0＝未开始复习；1/2/3＝已过 1/3/7 天档（3＝走完，[nextReviewAt] 落 null）。
  final int reviewStage;
  final int? reviewedAt;
  final int? nextReviewAt;

  bool get isDeleted => deletedAt != null;
  bool get isMastered => reviewStage >= masteredStage;

  /// 该档位的下次间隔天数（null＝不再排期）。
  static int? gapDaysForStage(int stage) =>
      stage >= masteredStage ? null : reviewGapsDays[stage];

  /// 「记住了」后的新行：推一档、记打卡时刻、按**新档**取下次到期（走完＝清排期）。
  /// [now] 由调用侧传入（测试可注入固定时刻，禁在模型里读时钟）。
  MediaNote remembered(int now) {
    final stage = (reviewStage + 1).clamp(0, masteredStage);
    final gap = gapDaysForStage(stage);
    return copyWith(
      reviewStage: stage,
      reviewedAt: now,
      nextReviewAt: gap == null ? null : now + gap * _dayMs,
      // copyWith 的 null＝「不改」（与 book.dart 的 clearEpub 同一条坑）：
      // 走完三档要把 next_review_at 清成 NULL，必须走显式哨兵，否则旧到期时刻留着＝永远排队。
      clearNextReview: gap == null,
    );
  }

  /// 到期判定：未走完档 且 排期时刻已到（[now] 注入，同上）。
  bool dueAt(int now) => nextReviewAt != null && nextReviewAt! <= now;

  /// 判重键＝条目＋子项＋时间点＋归一化正文（去空白＋小写）。正文空＝无键。
  static String dedupKey({
    required String itemId,
    int? unitRef,
    int? atMin,
    required String body,
  }) {
    final t = body.trim();
    if (t.isEmpty) return '';
    final norm = t.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    return '$itemId|${unitRef ?? ''}|${atMin ?? ''}|$norm';
  }

  /// 行 → 模型（JSON 列容错读空，档位缺列按 0／null 读＝旧行未排期）。
  factory MediaNote.fromMap(Map<String, Object?> m) => MediaNote(
    id: m['id'] as int?,
    itemId: (m['item_id'] as String?) ?? '',
    kind: (m['kind'] as String?) ?? '',
    noteType: (m['note_type'] as String?) ?? kScene,
    body: (m['body'] as String?) ?? '',
    tag: m['tag'] as String?,
    thought: m['thought'] as String?,
    unitRef: m['unit_ref'] as int?,
    atMin: m['at_min'] as int?,
    imagePaths: _jsonList(m['image_paths'], 'image_paths'),
    tags: _jsonList(m['tags'], 'tags'),
    starred: (m['starred'] as int? ?? 0) != 0,
    createdAt: m['created_at'] as int? ?? 0,
    updatedAt: m['updated_at'] as int? ?? 0,
    deletedAt: m['deleted_at'] as int?,
    origin: m['origin'] as String?,
    dedupHash: m['dedup_hash'] as String?,
    reviewStage: m['review_stage'] as int? ?? 0,
    reviewedAt: m['reviewed_at'] as int?,
    nextReviewAt: m['next_review_at'] as int?,
  );

  /// 模型 → 行（不含 id／created_at／updated_at，由仓储侧统一落，避免各处造时间）。
  Map<String, Object?> toRow() => <String, Object?>{
    'item_id': itemId,
    'kind': kind,
    'note_type': noteType,
    'tag': tag,
    'body': body,
    'thought': thought,
    'unit_ref': unitRef,
    'at_min': atMin,
    'image_paths': imagePaths.isEmpty ? null : jsonEncode(imagePaths),
    'starred': starred ? 1 : 0,
    'deleted_at': deletedAt,
    'origin': origin,
    'dedup_hash': dedupHash,
    'tags': tags.isEmpty ? null : jsonEncode(tags),
    'review_stage': reviewStage,
    'reviewed_at': reviewedAt,
    'next_review_at': nextReviewAt,
  };

  /// 全字段透传（批3 教训：漏字段＝把未露字段洗成空）。
  MediaNote copyWith({
    int? id,
    String? itemId,
    String? kind,
    String? noteType,
    String? body,
    String? tag,
    String? thought,
    int? unitRef,
    int? atMin,
    List<String>? imagePaths,
    List<String>? tags,
    bool? starred,
    int? createdAt,
    int? updatedAt,
    int? deletedAt,
    String? origin,
    String? dedupHash,
    int? reviewStage,
    int? reviewedAt,
    int? nextReviewAt,
    /// 显式把 `next_review_at` 清成 null 的哨兵（走完档＝不再排期）。
    bool clearNextReview = false,
  }) => MediaNote(
    id: id ?? this.id,
    itemId: itemId ?? this.itemId,
    kind: kind ?? this.kind,
    noteType: noteType ?? this.noteType,
    body: body ?? this.body,
    tag: tag ?? this.tag,
    thought: thought ?? this.thought,
    unitRef: unitRef ?? this.unitRef,
    atMin: atMin ?? this.atMin,
    imagePaths: imagePaths ?? this.imagePaths,
    tags: tags ?? this.tags,
    starred: starred ?? this.starred,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
    origin: origin ?? this.origin,
    dedupHash: dedupHash ?? this.dedupHash,
    reviewStage: reviewStage ?? this.reviewStage,
    reviewedAt: reviewedAt ?? this.reviewedAt,
    nextReviewAt: clearNextReview
        ? null
        : (nextReviewAt ?? this.nextReviewAt),
  );

  static List<String> _jsonList(Object? raw, String col) {
    if (raw == null) return const <String>[];
    if (raw is String && raw.trim().isEmpty) return const <String>[];
    try {
      final d = raw is String ? jsonDecode(raw) : raw;
      if (d is List) return d.map((Object? e) => '$e').toList();
      AppLog.add('media note decode：$col 非列表，按空处理', level: LhLevel.warn);
    } catch (e) {
      AppLog.add('media note decode：$col 非 JSON，按空处理: $e', level: LhLevel.warn);
    }
    return const <String>[];
  }
}
