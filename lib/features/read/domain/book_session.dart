/// 阅读位置快照（原型 brLocSnap · 轮5.2②）：会话起止各记一份，
/// 由阅读器在进出时自动采集，用户不再手填页码/位置。
class BrLoc {
  const BrLoc({this.page, this.pct, this.chapter});

  /// 全书估算页（1 起 · foliate 口径约 1500 字/页）。
  final int? page;

  /// 全书百分比（0~100，按章字符权重）。
  final double? pct;

  /// 章节名（快照标题回落链的结果，与书摘同源）。
  final String? chapter;
}

/// 一次阅读计时会话（book_sessions 表 · 计划 §2.1）。
///
/// 口径（§3.3 / §7）：
/// - 计时中的「当前会话」＝ `endedAt == null` 的那行（started_at 落库，杀 App 重启可续计）；
/// - 明细可改：改 minutes/started_at/页码 后由仓储按差量回写 books 聚合列与 L4 流水
///   （[txnId] 复用不新建）；补记走 `source='manual'`；
/// - 时钟回拨防护：`endedAt < startedAt` 的行入账时直接丢弃并记日志。
class BookSession {
  const BookSession({
    this.id,
    required this.bookId,
    required this.startedAt,
    this.endedAt,
    this.minutes = 0,
    this.speed,
    this.fromPage,
    this.toPage,
    this.fromLoc,
    this.toLoc,
    this.fromChapter,
    this.toChapter,
    this.fromPct,
    this.toPct,
    this.source = kSrcTimer,
    this.txnId,
  });

  static const kSrcTimer = 'timer';
  static const kSrcManual = 'manual';
  static const kSrcImport = 'import';

  final int? id;
  final String bookId;
  final int startedAt;
  final int? endedAt;
  final int minutes;

  /// 倍速（有声；speedFold 设置开启时按倍速折算时长）。
  final double? speed;
  final int? fromPage;
  final int? toPage;
  final double? fromLoc;
  final double? toLoc;

  /// 轮5.2②：起止章节名与全书百分比（阅读器退出时自动写入，无需手填）。
  final String? fromChapter, toChapter;
  final double? fromPct, toPct;
  final String source;
  final int? txnId;

  bool get running => endedAt == null;

  /// read.speedFold（计划 §6 阅读计时·默认开）：关闭后有声按墙钟时长入账。
  /// 纯 getter 拿不到库内 KV，由 speedFoldProvider 在读取链路上同步此开关。
  static bool speedFold = true;

  /// 折算入账分钟数：倍速设置生效时 = 墙钟分钟 × speed（有声）。
  int get billedMinutes =>
      speedFold && speed != null && speed! > 0
      ? (minutes * speed!).round()
      : minutes;

  static BookSession fromRow(Map<String, Object?> r) => BookSession(
    id: r['id'] as int?,
    bookId: r['book_id'] as String,
    startedAt: r['started_at'] as int,
    endedAt: r['ended_at'] as int?,
    minutes: (r['minutes'] as int?) ?? 0,
    speed: (r['speed'] as num?)?.toDouble(),
    fromPage: r['from_page'] as int?,
    toPage: r['to_page'] as int?,
    fromLoc: (r['from_loc'] as num?)?.toDouble(),
    toLoc: (r['to_loc'] as num?)?.toDouble(),
    fromChapter: r['from_chapter'] as String?,
    toChapter: r['to_chapter'] as String?,
    fromPct: (r['from_pct'] as num?)?.toDouble(),
    toPct: (r['to_pct'] as num?)?.toDouble(),
    source: (r['source'] as String?) ?? kSrcTimer,
    txnId: r['txn_id'] as int?,
  );

  Map<String, Object?> toRow() => {
    if (id != null) 'id': id,
    'book_id': bookId,
    'started_at': startedAt,
    'ended_at': endedAt,
    'minutes': minutes,
    'speed': speed,
    'from_page': fromPage,
    'to_page': toPage,
    'from_loc': fromLoc,
    'to_loc': toLoc,
    'from_chapter': fromChapter,
    'to_chapter': toChapter,
    'from_pct': fromPct,
    'to_pct': toPct,
    'source': source,
    'txn_id': txnId,
  };

  BookSession copyWith({
    int? endedAt,
    int? minutes,
    double? speed,
    int? fromPage,
    int? toPage,
    double? fromLoc,
    double? toLoc,
    String? fromChapter,
    String? toChapter,
    double? fromPct,
    double? toPct,
    String? source,
    int? txnId,
  }) => BookSession(
    id: id,
    bookId: bookId,
    startedAt: startedAt,
    endedAt: endedAt ?? this.endedAt,
    minutes: minutes ?? this.minutes,
    speed: speed ?? this.speed,
    fromPage: fromPage ?? this.fromPage,
    toPage: toPage ?? this.toPage,
    fromLoc: fromLoc ?? this.fromLoc,
    toLoc: toLoc ?? this.toLoc,
    fromChapter: fromChapter ?? this.fromChapter,
    toChapter: toChapter ?? this.toChapter,
    fromPct: fromPct ?? this.fromPct,
    toPct: toPct ?? this.toPct,
    source: source ?? this.source,
    txnId: txnId ?? this.txnId,
  );
}
