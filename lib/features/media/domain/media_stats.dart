import 'media_item.dart';
import 'media_session.dart';

/// 影音游统计与轨迹的**算面**（批7 · 词典 LH-C21／LH-S37）。
///
/// 四条诚实口径在本件钉死，UI 侧不许另算一套：
/// - **真实／折算**只由 [MdsStatFilter.fold] 决定（＝设置项 `media.speedFold` 的可见表达），
///   折算走 [MediaSession.billedMinutes]，账本金额恒吃真实耗时（批4 §0.3 定案）；
/// - **近 30 天热力恒 30 天窗口**，只吃口径／度量／构成，不吃年月钻取；
/// - **平均评分档**＝该窗口内「有记录条目」的 `my_rating` 均值（会话表没有逐次评分列，
///   只能按条目取均值，绝不编逐次分数）；
/// - 算不出＝返回 0／空列表，由调用侧出虚线或整行不出现，**不拿 0 冒充真实读数**。
///
/// 件内不读时钟：`now` 一律由调用侧注入（日期类用例禁时间炸弹，计划书 §7.5）。

/// 统计屏四行筛选条＋口径的唯一状态（record 整体换，理由同 `MediaNoteFilter`）。
class MdsStatFilter {
  const MdsStatFilter({
    this.year,
    this.month,
    this.metric = kMdsMetricMin,
    this.kind = 'all',
    this.fold = false,
  });

  /// null＝全部年份；非空＝趋势按月出 12 根柱。
  final int? year;

  /// null／0＝全年。
  final int? month;
  final String metric;

  /// all | movie | series | music | game。
  final String kind;

  /// true＝折算时长（倍速折进读数）；false＝真实耗时（默认）。
  final bool fold;

  MdsStatFilter copyWith({
    int? year,
    bool clearYear = false,
    int? month,
    bool clearMonth = false,
    String? metric,
    String? kind,
    bool? fold,
  }) => MdsStatFilter(
    year: clearYear ? null : (year ?? this.year),
    month: clearMonth ? null : (month ?? this.month),
    metric: metric ?? this.metric,
    kind: kind ?? this.kind,
    fold: fold ?? this.fold,
  );

  /// 窗口标题（趋势卡与热力卡各自措辞用）。
  String get windowLabel => year == null
      ? '按年'
      : (month == null || month == 0
          ? '$year 年'
          : '$year 年 $month 月');

  String get metricWord =>
      kMdsMetrics.firstWhere((m) => m.$1 == metric, orElse: () => kMdsMetrics.first).$2;

  String get foldWord => fold ? '折算' : '真实';
}

const String kMdsMetricMin = 'min';
const String kMdsMetricCnt = 'cnt';
const String kMdsMetricRate = 'rate';

/// 度量三档（词典 LH-C21 铁口径③：各档换纵轴语义，不是同一根轴换个标签）。
const List<(String, String)> kMdsMetrics = [
  (kMdsMetricMin, '时长'),
  (kMdsMetricCnt, '次数'),
  (kMdsMetricRate, '平均评分'),
];

/// 时段五档（会话**起始时刻**落档；取不到时刻归深夜，与明细屏「起讫时刻」同料）。
const List<(String, String, int, int)> kMdsHours = [
  ('dawn', '凌晨', 0, 5),
  ('am', '上午', 6, 11),
  ('pm', '午后', 12, 16),
  ('eve', '傍晚', 17, 20),
  ('night', '深夜', 21, 23),
];

const int kMdsHeatDays = 30;

/// 人话词（观影／追剧／听歌／游玩）——统计与轨迹两面共用一份，别在各屏里各写一遍。
String mdsKindWord(String k) => switch (k) {
      MediaItem.kMovie => '观影',
      MediaItem.kSeries => '追剧',
      MediaItem.kMusic => '听歌',
      MediaItem.kGame => '游玩',
      _ => '计时',
    };

/// 紧凑时长读数（原型 `mHMtxt` 同口径：45m / 1h / 1h 20m）。
String mdsHm(int m) {
  final v = m < 0 ? 0 : m;
  final h = v ~/ 60, mm = v % 60;
  if (h == 0) return '${mm}m';
  return mm == 0 ? '${h}h' : '${h}h ${mm}m';
}

/// 度量读数（0＝没有读数，出「—」；时长档由调用侧先判 0）。
String mdsMetricText(String metric, double v) {
  if (metric == kMdsMetricCnt) return '${v.round()} 次';
  if (metric == kMdsMetricRate) return v > 0 ? v.toStringAsFixed(1) : '—';
  return v > 0 ? mdsHm(v.round()) : '—';
}

/// 热力一格（近 30 天逐日）。[level]0＝没记录（虚线空格），1~3＝强度档。
class MdsHeatCell {
  const MdsHeatCell({
    required this.day,
    required this.value,
    required this.count,
    required this.level,
    this.topKind,
    this.kinds = const [],
    this.kindValues = const {},
  });

  final DateTime day;
  final double value;
  final int count;
  final int level;

  /// 当日主导 kind（按时长取大者）；没记录＝null。
  final String? topKind;

  /// 当日出现过的 kind（读数行按类各报一次）。
  final List<String> kinds;

  /// 当日各 kind 的读数（已按口径与度量算好；读数行直接取，不在 UI 侧再算一遍）。
  final Map<String, double> kindValues;

  /// 强度分档要等 30 天全算完才知道分位数，故先建格再补档（不可变件的小复制口）。
  MdsHeatCell withLevel(int lv) => MdsHeatCell(
        day: day,
        value: value,
        count: count,
        level: lv,
        topKind: topKind,
        kinds: kinds,
        kindValues: kindValues,
      );
}

/// 趋势一根柱（选年＝12 个月；全部＝按年）。[hasData]false＝虚线底不出数值。
class MdsTrendBar {
  const MdsTrendBar({required this.key, required this.label, required this.value, required this.hasData});

  final String key;
  final String label;
  final double value;
  final bool hasData;
}

/// 构成一行（含百分比，四舍五入后合计可差 ±1%）。
class MdsKindSlice {
  const MdsKindSlice({required this.kind, required this.value, required this.pct});

  final String kind;
  final double value;
  final int pct;
}

/// 时段一档。
class MdsHourSlice {
  const MdsHourSlice({required this.key, required this.label, required this.value});

  final String key;
  final String label;
  final double value;
}

/// 统计屏一次算齐的读数集（八块各取所需，全部同源）。
class MdsStatRead {
  const MdsStatRead({
    required this.heat,
    required this.trend,
    required this.kinds,
    required this.hours,
    required this.kindMinutes,
    required this.totalMinutes,
    required this.ratingAvg,
    required this.ratingCount,
    required this.ratingByKind,
    required this.years,
  });

  final List<MdsHeatCell> heat;
  final List<MdsTrendBar> trend;
  final List<MdsKindSlice> kinds;
  final List<MdsHourSlice> hours;

  /// 跨 kind 总时长卡：**恒为时长**（吃口径与年月，不吃度量）。
  final Map<String, int> kindMinutes;
  final int totalMinutes;

  /// 窗口内有记录条目的我的评分均值；null＝没评分记录。
  final double? ratingAvg;
  final int ratingCount;
  final Map<String, double> ratingByKind;

  /// 有会话数据的年份（倒序，供「年」那一行 chips）。
  final List<int> years;
}

/// 全库统计的唯一算面。[sessions] 必须是**已结算**会话（进行中不入账＝不进统计），
/// [items] 是在册条目（软删行由仓储侧挡掉，本件不再判）。
MdsStatRead mdsComputeStat({
  required List<MediaSession> sessions,
  required List<MediaItem> items,
  required MdsStatFilter filter,
  required DateTime now,
}) {
  final byId = {for (final x in items) x.id: x};
  final years = mdsYearsOf(sessions);
  bool inWindow(MediaSession s) {
    final d = DateTime.fromMillisecondsSinceEpoch(s.startedAt);
    if (filter.year != null && d.year != filter.year) return false;
    if (filter.month != null && filter.month != 0 && d.month != filter.month) return false;
    return true;
  }

  bool kindPass(MediaSession s) => filter.kind == 'all' || s.kind == filter.kind;
  final win = sessions.where((s) => inWindow(s) && kindPass(s)).toList();
  final winYm = sessions.where(inWindow).toList();

  double value(List<MediaSession> rows) {
    if (rows.isEmpty) return 0;
    switch (filter.metric) {
      case kMdsMetricCnt:
        return rows.length.toDouble();
      case kMdsMetricRate:
        final vals = rows.map((s) => s.itemId).toSet().map((i) => byId[i]?.myRating ?? 0)
            .where((v) => v > 0)
            .toList();
        if (vals.isEmpty) return 0;
        return vals.reduce((a, b) => a + b) / vals.length;
      default:
        return rows.fold<double>(0, (t, s) => t + (filter.fold ? s.billedMinutes() : s.minutes));
    }
  }

  // ---- 近 30 天热力（恒 30 天窗口，只吃口径／度量／构成）----
  final today = DateTime(now.year, now.month, now.day);
  final byDay = <String, List<MediaSession>>{};
  for (final s in sessions.where(kindPass)) {
    final d = DateTime.fromMillisecondsSinceEpoch(s.startedAt);
    byDay.putIfAbsent(_dayKey(d), () => []).add(s);
  }
  final heatRows = <List<MediaSession>>[];
  final cells = <MdsHeatCell>[];
  for (var i = kMdsHeatDays - 1; i >= 0; i--) {
    final d = today.subtract(Duration(days: i));
    final rows = byDay[_dayKey(d)] ?? const <MediaSession>[];
    heatRows.add(rows);
    final ks = rows.map((s) => s.kind).where(MediaItem.kinds.contains).toSet().toList()..sort();
    final kindValues = {for (final k in ks) k: value(rows.where((s) => s.kind == k).toList())};
    // 主导 kind 恒按**时长**取大者（度量切到次数/评分时格色不跟着跳，读的是「这天在看什么」）。
    final mins = <String, double>{};
    for (final s in rows) {
      mins[s.kind] = (mins[s.kind] ?? 0) + (filter.fold ? s.billedMinutes() : s.minutes);
    }
    String? top;
    var best = 0.0;
    mins.forEach((k, m) {
      if (m > best) {
        best = m;
        top = k;
      }
    });
    cells.add(MdsHeatCell(
      day: d,
      value: value(rows),
      count: rows.length,
      level: 0,
      topKind: top,
      kinds: ks,
      kindValues: kindValues,
    ));
  }
  final pos = heatRows.map(value).where((v) => v > 0).toList()..sort();
  final heat = [for (final c in cells) c.withLevel(_level(c.value, pos))];

  // ---- 趋势（选年＝12 根月柱；全部＝按年）----
  final trend = <MdsTrendBar>[];
  if (filter.year == null) {
    for (final y in years) {
      final rows = win.where((s) => DateTime.fromMillisecondsSinceEpoch(s.startedAt).year == y).toList();
      final v = value(rows);
      trend.add(MdsTrendBar(key: '$y', label: '$y', value: v, hasData: v > 0));
    }
  } else {
    for (var m = 1; m <= 12; m++) {
      final rows = win.where((s) {
        final d = DateTime.fromMillisecondsSinceEpoch(s.startedAt);
        return d.year == filter.year && d.month == m;
      }).toList();
      final v = value(rows);
      trend.add(MdsTrendBar(key: '$m', label: '$m月', value: v, hasData: v > 0));
    }
  }

  // ---- 类型构成（百分比按当前度量归一）----
  final kindVals = <String, double>{};
  for (final k in MediaItem.kinds) {
    final v = value(win.where((s) => s.kind == k).toList());
    if (v > 0) kindVals[k] = v;
  }
  final kindSum = kindVals.values.fold<double>(0, (a, b) => a + b);
  final slices = [
    for (final e in kindVals.entries)
      MdsKindSlice(kind: e.key, value: e.value, pct: kindSum <= 0 ? 0 : (e.value / kindSum * 100).round()),
  ];

  // ---- 时段五档 ----
  final hours = <MdsHourSlice>[];
  for (final (key, label, lo, hi) in kMdsHours) {
    final rows = win.where((s) {
      final h = DateTime.fromMillisecondsSinceEpoch(s.startedAt).hour;
      return h >= lo && h <= hi;
    }).toList();
    hours.add(MdsHourSlice(key: key, label: label, value: value(rows)));
  }

  // ---- 跨 kind 总时长（恒时长口径，吃年月与口径，不吃度量）----
  final kindMinutes = <String, int>{};
  for (final k in MediaItem.kinds) {
    if (filter.kind != 'all' && filter.kind != k) continue;
    kindMinutes[k] = winYm
        .where((s) => s.kind == k)
        .fold<int>(0, (t, s) => t + (filter.fold ? s.billedMinutes() : s.minutes));
  }
  final totalMinutes = kindMinutes.values.fold<int>(0, (a, b) => a + b);

  // ---- 平均评分（窗口内有记录条目的 my_rating 均值）----
  final ratedIds = win.map((s) => s.itemId).toSet().map((i) => byId[i]).whereType<MediaItem>()
      .where((x) => x.myRating > 0)
      .toList();
  double? avg;
  if (ratedIds.isNotEmpty) {
    avg = ratedIds.fold<double>(0, (t, x) => t + x.myRating) / ratedIds.length;
  }
  final byKind = <String, double>{};
  for (final k in MediaItem.kinds) {
    final g = ratedIds.where((x) => x.kind == k).toList();
    if (g.isEmpty) continue;
    byKind[k] = g.fold<double>(0, (t, x) => t + x.myRating) / g.length;
  }

  return MdsStatRead(
    heat: heat,
    trend: trend,
    kinds: slices,
    hours: hours,
    kindMinutes: kindMinutes,
    totalMinutes: totalMinutes,
    ratingAvg: avg,
    ratingCount: ratedIds.length,
    ratingByKind: byKind,
    years: years,
  );
}

/// 有会话数据的年份（倒序）。
List<int> mdsYearsOf(List<MediaSession> sessions) {
  final ys = sessions.map((s) => DateTime.fromMillisecondsSinceEpoch(s.startedAt).year).toSet().toList()
    ..sort((a, b) => b.compareTo(a));
  return ys;
}

double _q(List<double> sorted, double f) =>
    sorted[((sorted.length - 1) * f).floor()];

/// 强度分档：正数按四分位切三档（词典 LH-C21 铁口径②），0＝虚线空格。
int _level(double v, List<double> posSorted) {
  if (v <= 0 || posSorted.isEmpty) return 0;
  if (v >= _q(posSorted, .75)) return 3;
  if (v >= _q(posSorted, .5)) return 2;
  return 1;
}

String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

// ==================== 单条目轨迹（词典 LH-S37） ====================

/// 里程碑一条（达成日必取真料：会话日或 `ended_at`，取不到＝整行不出现）。
class MdsMilestone {
  const MdsMilestone(this.label, this.date);

  final String label;
  final DateTime date;
}

/// 轨迹弹层的逐次柱（最多最近 [kMdsTrackCols] 根，日期升序）。
const int kMdsTrackCols = 14;

/// 四类各一套里程碑（工单 §1 口径）：
/// 电影＝开始观影／看过一半（累计分钟过半，需填片长）／看完 ·
/// 剧集＝开始追剧／看到一半（会话进度快照按 `S02E05` 解析）／追完 ·
/// 音乐＝开始听歌／循环 100 次（循环次数＝会话条数）·
/// 游戏＝开始游玩／主线半程（快照 `to_pct>=50`）／通关。
/// **算不出的整行不出现**，不铺「未达成」占位，也不编日期。
List<MdsMilestone> mdsMilestonesOf(MediaItem x, List<MediaSession> closed) {
  final rows = [
    ...closed.where((s) => s.endedAt != null),
  ]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  if (rows.isEmpty) return const [];
  int mins(MediaSession s) => s.minutes;
  final out = <MdsMilestone>[
    MdsMilestone('开始${mdsKindWord(x.kind)}', _dayOf(rows.first.startedAt)),
  ];

  MdsMilestone? half;
  if (x.kind == MediaItem.kMovie) {
    final need = x.durationMin / 2;
    if (need > 0) {
      var acc = 0;
      for (final s in rows) {
        acc += mins(s);
        if (acc >= need) {
          half = MdsMilestone('看过一半', _dayOf(s.startedAt));
          break;
        }
      }
    }
  } else if (x.kind == MediaItem.kSeries) {
    final need = x.episodesTotal / 2;
    if (need > 0) {
      for (final s in rows) {
        final ep = _epSeen(x, s);
        if (ep != null && ep >= need) {
          half = MdsMilestone('看到一半', _dayOf(s.startedAt));
          break;
        }
      }
    }
  } else if (x.kind == MediaItem.kGame) {
    for (final s in rows) {
      if ((s.toPct ?? 0) >= 50) {
        half = MdsMilestone('主线半程', _dayOf(s.startedAt));
        break;
      }
    }
  } else if (x.kind == MediaItem.kMusic && rows.length >= 100) {
    half = MdsMilestone('循环 100 次', _dayOf(rows[99].startedAt));
  }
  if (half != null) out.add(half);

  final doneLabel = switch (x.kind) {
    MediaItem.kMovie => '看完',
    MediaItem.kSeries => '追完',
    MediaItem.kGame => '通关',
    _ => null,
  };
  if (doneLabel != null && x.completed) {
    final ms = x.endedAt ?? rows.last.endedAt;
    if (ms != null) out.add(MdsMilestone(doneLabel, _dayOf(ms)));
  }
  return out;
}

/// 会话快照里的集序号（`S02E05` 文本档或纯数字档都吃；解析不出＝null，不猜）。
double? _epSeen(MediaItem x, MediaSession s) {
  final t = s.toText;
  if (t != null) {
    final m = RegExp(r'^S(\d+)E(\d+)$', caseSensitive: false).firstMatch(t.trim());
    if (m != null) {
      final per = x.seasonsCount > 0 ? (x.episodesTotal / x.seasonsCount).ceil() : 0;
      return ((int.parse(m.group(1)!) - 1) * per + int.parse(m.group(2)!)).toDouble();
    }
    final n = double.tryParse(t.trim());
    if (n != null) return n;
  }
  if (s.toUnit != null) return s.toUnit!.toDouble();
  return null;
}

/// 时段五档（轨迹弹层用真实耗时，倍速只在柱顶出角标＝明细屏同一口径）。
List<MdsHourSlice> mdsTrackHours(List<MediaSession> closed) {
  final rows = closed.where((s) => s.endedAt != null).toList();
  return [
    for (final (key, label, lo, hi) in kMdsHours)
      MdsHourSlice(
        key: key,
        label: label,
        value: rows
            .where((s) {
              final h = DateTime.fromMillisecondsSinceEpoch(s.startedAt).hour;
              return h >= lo && h <= hi;
            })
            .fold<double>(0, (t, s) => t + s.minutes),
      ),
  ];
}

DateTime _dayOf(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return DateTime(d.year, d.month, d.day);
}
