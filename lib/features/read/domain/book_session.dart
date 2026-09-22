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
  final String source;
  final int? txnId;

  bool get running => endedAt == null;

  /// 折算入账分钟数：倍速设置生效时 = 墙钟分钟 × speed（有声）。
  int get billedMinutes =>
      speed != null && speed! > 0 ? (minutes * speed!).round() : minutes;

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
    source: source ?? this.source,
    txnId: txnId ?? this.txnId,
  );
}
