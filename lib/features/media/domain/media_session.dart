import 'media_item.dart';

/// 影音游计时会话（`media_sessions` 表 · 与 `book_sessions` 同构，计划 §八 定案）。
///
/// 三条口径在模型层钉死：
/// - [minutes] 落**真实耗时**（墙钟），[speed] 另存列，折算值只在读取侧算
///   （批2 工单 §2 判断1：账本对的是生活时间）；
/// - 音乐「循环次数」＝该条目的**会话条数**（含手动补记的记一次），表里没有 loops 列；
/// - [txnId] 指向时间账本 `time_blocks` 行（分类=娱乐），明细改动差量回写同一条。
class MediaSession {
  const MediaSession({
    this.id,
    required this.itemId,
    required this.kind,
    required this.startedAt,
    this.endedAt,
    this.minutes = 0,
    this.speed,
    this.fromMin,
    this.toMin,
    this.fromPct,
    this.toPct,
    this.fromUnit,
    this.toUnit,
    this.fromText,
    this.toText,
    this.source = kSrcTimer,
    this.txnId,
  });

  static const kSrcTimer = 'timer';
  static const kSrcManual = 'manual';

  final int? id;
  final String itemId;
  final String kind;

  /// 起点毫秒；[endedAt] 为空＝进行中（全库单活，与阅读侧同语义）。
  final int startedAt;
  final int? endedAt;

  /// 真实耗时分钟（结束结算/手动补记写入；进行中读数用 [liveMinutes]）。
  final int minutes;

  /// 倍速（本批只留列与折算口径，录入位在计时明细批）。
  final double? speed;

  // 进度区间快照：按 kind 解释（min/pct/unit=集|曲|周目），文本档留原样。
  final int? fromMin;
  final int? toMin;
  final int? fromPct;
  final int? toPct;
  final int? fromUnit;
  final int? toUnit;
  final String? fromText;
  final String? toText;

  final String source;

  /// L4 时间账本块 id（`time_blocks.id`）；null＝尚未入账。
  final int? txnId;

  bool get running => endedAt == null;

  /// 入账分钟：倍速折算只在 speedFold 开启且带倍速时生效（读取侧口径）。
  int billedMinutes({bool speedFold = true}) {
    final base = endedAt != null ? minutes : liveMinutes;
    if (speedFold && speed != null && speed! > 0) {
      return (base * speed!).round();
    }
    return base;
  }

  /// 进行中会话的实时墙钟分钟。
  int get liveMinutes =>
      ((DateTime.now().millisecondsSinceEpoch - startedAt) / 60000).floor();

  static MediaSession fromRow(Map<String, Object?> m) => MediaSession(
    id: (m['id'] as num?)?.toInt(),
    itemId: '${m['item_id']}',
    kind: '${m['kind']}',
    startedAt: (m['started_at'] as num?)?.toInt() ?? 0,
    endedAt: (m['ended_at'] as num?)?.toInt(),
    minutes: (m['minutes'] as num?)?.toInt() ?? 0,
    speed: (m['speed'] as num?)?.toDouble(),
    fromMin: (m['from_min'] as num?)?.toInt(),
    toMin: (m['to_min'] as num?)?.toInt(),
    fromPct: (m['from_pct'] as num?)?.toInt(),
    toPct: (m['to_pct'] as num?)?.toInt(),
    fromUnit: (m['from_unit'] as num?)?.toInt(),
    toUnit: (m['to_unit'] as num?)?.toInt(),
    fromText: m['from_text'] as String?,
    toText: m['to_text'] as String?,
    source: '${m['source'] ?? kSrcTimer}',
    txnId: (m['txn_id'] as num?)?.toInt(),
  );

  Map<String, Object?> toRow({bool includeId = false}) => {
    if (includeId && id != null) 'id': id,
    'item_id': itemId,
    'kind': kind,
    'started_at': startedAt,
    'ended_at': endedAt,
    'minutes': minutes,
    'speed': speed,
    'from_min': fromMin,
    'to_min': toMin,
    'from_pct': fromPct,
    'to_pct': toPct,
    'from_unit': fromUnit,
    'to_unit': toUnit,
    'from_text': fromText,
    'to_text': toText,
    'source': source,
    'txn_id': txnId,
  };

  MediaSession copyWith({
    int? id,
    int? endedAt,
    int? minutes,
    int? toMin,
    int? toPct,
    int? toUnit,
    String? toText,
    int? txnId,
  }) => MediaSession(
    id: id ?? this.id,
    itemId: itemId,
    kind: kind,
    startedAt: startedAt,
    endedAt: endedAt ?? this.endedAt,
    minutes: minutes ?? this.minutes,
    speed: speed,
    fromMin: fromMin,
    toMin: toMin ?? this.toMin,
    fromPct: fromPct,
    toPct: toPct ?? this.toPct,
    fromUnit: fromUnit,
    toUnit: toUnit ?? this.toUnit,
    fromText: fromText,
    toText: toText ?? this.toText,
    source: source,
    txnId: txnId ?? this.txnId,
  );
}

/// 均速 / 预计剩余 / 预计完成日（计划 §五 批2 验收「重算预计完成日」的算法面）。
///
/// 三条诚实口径：**没有总时长或没有 pace 就不出数**（返回 null／隐藏该行），
/// 绝不按观感编数。pace＝近 90 天日均入账分钟（跨天平均）。
class MediaEta {
  const MediaEta({
    required this.avgMinPerDay,
    required this.remainMin,
    required this.remainDays,
    required this.etaDate,
  });

  /// 日均入账分钟（真实耗时口径）。
  final int avgMinPerDay;

  /// 剩余内容分钟（总时长−已完成；百分比/按集口径折算成分钟）。
  final int remainMin;

  /// 按当前 pace 还需的自然日数（向上取整）。
  final int remainDays;

  final DateTime etaDate;

  /// 百分比档（电影 pct / 游戏 mainpct/achv）：[pct]0–100、[totalMin] 总时长。
  static MediaEta? forPct({
    required int pct,
    required int totalMin,
    required List<MediaSession> closed,
    DateTime? now,
  }) {
    if (totalMin <= 0 || pct >= 100) return null;
    return _build(
      remain: totalMin * (100 - pct) ~/ 100,
      closed: closed,
      now: now,
    );
  }

  /// 时间点档（movie=way min）：已看到第几分钟。
  static MediaEta? forMin({
    required int atMin,
    required int totalMin,
    required List<MediaSession> closed,
    DateTime? now,
  }) {
    if (totalMin <= 0 || atMin >= totalMin) return null;
    return _build(remain: totalMin - atMin, closed: closed, now: now);
  }

  /// 按集档：[curEp]/[epsTotal]，[epMin]＝单集时长。
  static MediaEta? forEp({
    required int curEp,
    required int epsTotal,
    required int epMin,
    required List<MediaSession> closed,
    DateTime? now,
  }) {
    if (epsTotal <= 0 || epMin <= 0 || curEp >= epsTotal) return null;
    return _build(
      remain: (epsTotal - curEp) * epMin,
      closed: closed,
      now: now,
    );
  }

  /// 循环档（音乐）：目标 [targetLoops] 未设＝不预测（不编目标）。
  static MediaEta? forLoops({
    required int doneLoops,
    int? targetLoops,
    required List<MediaSession> closed,
    DateTime? now,
  }) {
    if (targetLoops == null || targetLoops <= doneLoops) return null;
    return _build(
      remain: (targetLoops - doneLoops) * 0,
      closed: closed,
      now: now,
      extraDays: (targetLoops - doneLoops),
      unitPerDay: true,
    );
  }

  static MediaEta? _build({
    required int remain,
    required List<MediaSession> closed,
    DateTime? now,
    int? extraDays,
    bool unitPerDay = false,
  }) {
    final t0 = now ?? DateTime.now();
    if (closed.isEmpty) return null;
    // pace＝入账总分钟 ÷ 覆盖自然日数（至少 1 天）
    final days = <DateTime>{};
    var mins = 0;
    for (final s in closed) {
      if (s.endedAt == null) continue;
      final d = DateTime.fromMillisecondsSinceEpoch(s.endedAt!);
      days.add(DateTime(d.year, d.month, d.day));
      mins += s.minutes;
    }
    if (mins <= 0 || days.isEmpty) return null;
    final avgPerDay = (mins / days.length).round();
    if (avgPerDay <= 0) return null;
    final remainDays = unitPerDay
        ? (extraDays ?? 0)
        : (remain / avgPerDay).ceil();
    if (remainDays <= 0) return null;
    final eta = DateTime(t0.year, t0.month, t0.day).add(
      Duration(days: remainDays),
    );
    return MediaEta(
      avgMinPerDay: avgPerDay,
      remainMin: unitPerDay ? 0 : remain,
      remainDays: remainDays,
      etaDate: eta,
    );
  }

  /// 一行读数（无剩余分钟＝循环档只报天数；两样都没有＝调用侧不渲染）。
  String get label {
    final parts = <String>[
      '日均 $avgMinPerDay 分钟',
      if (remainMin > 0) '剩约 $remainMin 分钟',
      '预计 $remainDays 天后完成',
    ];
    return parts.join(' · ');
  }

  String get etaLabel {
    const m = [
      '1月', '2月', '3月', '4月', '5月', '6月',
      '7月', '8月', '9月', '10月', '11月', '12月',
    ];
    return '${etaDate.year} 年 ${m[etaDate.month - 1]}${etaDate.day} 日';
  }
}

/// 详情统计行／进度弹层的「均速 · 预计剩余 · 预计完成日」统一取数口。
///
/// 诚实口径：总时长未知（电影未填时长、剧集无单集时长、游戏无总时长）＝返回 null，
/// 调用侧**隐藏该行**，不按观感编数。
MediaEta? mediaEtaOf(
  MediaItem item,
  List<MediaSession> closed, {
  DateTime? now,
}) {
  switch (item.kind) {
    case MediaItem.kMovie:
      if (item.progressWay == MediaItem.kWayMin) {
        return MediaEta.forMin(
          atMin: int.tryParse(item.progressTo ?? '') ?? 0,
          totalMin: item.durationMin,
          closed: closed,
          now: now,
        );
      }
      return MediaEta.forPct(
        pct: int.tryParse(item.progressTo ?? '') ?? item.mainPct,
        totalMin: item.durationMin,
        closed: closed,
        now: now,
      );
    case MediaItem.kSeries:
      // duration_min＝单集时长（§2.1 列口径），没填＝不预测。
      return MediaEta.forEp(
        curEp: int.tryParse(item.progressTo ?? '') ?? 0,
        epsTotal: item.episodesTotal,
        epMin: item.durationMin,
        closed: closed,
        now: now,
      );
    case MediaItem.kMusic:
      // 循环目标不入库（不设就不预测）；本批没有目标列＝恒 null。
      return null;
    case MediaItem.kGame:
      return MediaEta.forPct(
        pct: switch (item.progressWay) {
          MediaItem.kWayAchv => item.achPct,
          MediaItem.kWayPlaythrough => 0,
          _ => item.mainPct,
        },
        totalMin: item.durationMin,
        closed: closed,
        now: now,
      );
    default:
      return null;
  }
}
