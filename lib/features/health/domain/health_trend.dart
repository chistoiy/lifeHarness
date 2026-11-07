/// 健康趋势与周报规格单源（批6a · 原型 `prototype/index-health.html` 的 `p-trends`＋`sheetHealthReport`，
/// JS 段 `HT_METRICS`／`hTrends`／`hMonthAvg`／`hTrendDay`／`hReport` 逐句对照）。
///
/// 四条口径写在最近处，页面与仓储都别再各定一套：
/// · **目标线只吃设置与目标读数**（计划 §五.1）：喝水＝`waterGoal()`、睡眠＝`sleepGoalHours()`、
///   运动＝「每周次数 × 单次门槛 ÷ 7」折算、体重＝`health_goal.weight_goal`。
///   原型 JS 里 `htGoal('ex')=30` 是演示硬编码，不照抄；
///   `all:80`／`drug:100` 两条是「达标天」的**判据**（不是用户能改的目标），所以作常量并在此说明；
/// · **缺记录日不画假点**（§五.11／§九.2）：原型 `htWater`／`htSleepH`／`htKg` 拿哈希生成数补空槽，
///   实现一律出 null——热力格是空格、曲线跳过该点、均值只按有记录日取（分母见 `trAvg`）；
/// · **占比的分母是天数、日均的分母是有记录日**：「全达标天 43%」一周就是 7 天（没记录那天不可能达标），
///   而「日均睡眠」若除以 7 会把三个没记录的夜当 0 小时，失真——两处口径不同是有意为之；
/// · **年视图＝近 12 个月按月聚合**（旧→新），不是「今年 1~12 月」（原型 `hMonthAvg(m)` 只按月-日拼演示日期）。
library;

import 'health_calc.dart';

// ==================== 六指标 ====================

enum TrShape { percent, quantity, body }

enum TrMetric { all, water, sleep, ex, body, drug }

const trMetricOrder = <TrMetric>[
  TrMetric.all,
  TrMetric.water,
  TrMetric.sleep,
  TrMetric.ex,
  TrMetric.body,
  TrMetric.drug,
];

extension TrMetricX on TrMetric {
  /// 原型 `HT_METRICS[k].n`
  String get label => switch (this) {
        TrMetric.all => '综合达标',
        TrMetric.water => '喝水',
        TrMetric.sleep => '睡眠',
        TrMetric.ex => '运动',
        TrMetric.body => '体重',
        TrMetric.drug => '用药',
      };

  /// 原型 `HT_METRICS[k].u`
  String get unit => switch (this) {
        TrMetric.all => '%',
        TrMetric.water => '杯',
        TrMetric.sleep => 'h',
        TrMetric.ex => '分钟',
        TrMetric.body => 'kg',
        TrMetric.drug => '%',
      };

  TrShape get shape => switch (this) {
        TrMetric.all || TrMetric.drug => TrShape.percent,
        TrMetric.body => TrShape.body,
        _ => TrShape.quantity,
      };

  /// 读数小数位：体重/睡眠一位，百分比与整数量（杯/分钟）取整。
  int get decimals => switch (this) {
        TrMetric.body || TrMetric.sleep => 1,
        _ => 0,
      };
}

// ==================== 目标线 ====================

class TrGoals {
  const TrGoals({
    required this.waterCups,
    required this.sleepHours,
    required this.weekExGoal,
    this.bodyKg,
  });

  final double waterCups;
  final double sleepHours;

  /// 每周运动次数目标（次/周，`HealthSettings.weekExGoal()`）。
  final int weekExGoal;

  /// 目标体重（`health_goal.weight_goal`）；未设＝null，曲线不画虚线。
  final double? bodyKg;

  /// 「达标天」判据：综合 80 分线（§五.1 权重 40/35/25 下的达标定义），非用户可改目标。
  static const double scoreGoalPct = 80;

  /// 用药依从的达标定义＝当日计划时刻全部已服。
  static const double drugGoalPct = 100;

  /// 原型 `vs.filter(v=>v<40)` 的「待改善天」判据。
  static const double lowDayPct = 40;

  /// §五.9：单次 ≥10 分钟才计 1 次——周目标折算到日参考线用的就是这枚门槛。
  static const int exSessionMin = 10;

  /// 运动日参考线＝`周次数目标 × 单次门槛 ÷ 7`（3 次/周 → 4.3 分钟/日）。
  /// 折算而非写死，改「每周运动次数」后目标线当场跟（工单 §2 红线、变异刀3 钉这行）。
  double get exDailyMinGoal =>
      double.parse((weekExGoal * exSessionMin / 7).toStringAsFixed(1));

  double? of(TrMetric m) => switch (m) {
        TrMetric.all => scoreGoalPct,
        TrMetric.water => waterCups,
        TrMetric.sleep => sleepHours,
        TrMetric.ex => exDailyMinGoal,
        TrMetric.body => bodyKg,
        TrMetric.drug => drugGoalPct,
      };

  /// 目标线右上角读数（原型曲线卡只有「虚线 = 目标值」一句，这里带上数值更有用；未设＝不出该串）。
  String? goalTx(TrMetric m) {
    final g = of(m);
    if (g == null) return null;
    return '目标 ${g.toStringAsFixed(m.decimals)} ${m.unit}';
  }
}

// ==================== 单日读数 ====================

class TrDay {
  const TrDay({
    required this.date,
    this.cups,
    this.sleepMin,
    this.exMin,
    this.kg,
    this.medPlanned,
    this.medTaken,
    this.paces = const <int>[],
  });

  /// `yyyy-MM-dd`（自然日 00:00 切分，需求 174 行）
  final String date;
  final int? cups;
  final int? sleepMin;
  final int? exMin;
  final double? kg;

  /// 当日计划时刻数／已服数（含已归档档案的历史流水，读侧不过滤＝批5 工单 §2 前置兑现）
  final int? medPlanned;
  final int? medTaken;

  /// 当日距离类运动的配速（秒/公里），周报「平均配速」取均值用。
  final List<int> paces;

  /// 任何一格都没记录＝整日缺席（热力出空格、曲线不画点、不进均值分母）。
  bool get recorded =>
      cups != null || sleepMin != null || exMin != null || kg != null || medTaken != null;

  double? get medRate {
    final p = medPlanned ?? 0, o = medTaken ?? 0;
    return p <= 0 ? null : double.parse((o / p * 100).toStringAsFixed(0));
  }

  /// 综合达标（§五.1）：分量缺记录按 0 吃（那天确实没记），整日无记录才出 null。
  double? score(TrGoals g) => recorded
      ? dailyScore(
          cups: cups ?? 0,
          waterGoalCups: g.waterCups,
          sleepMin: sleepMin ?? 0,
          sleepGoalMin: g.sleepHours * 60,
          exerciseMin: exMin ?? 0,
        )
      : null;

  double? valueOf(TrMetric m, TrGoals g) => switch (m) {
        TrMetric.all => score(g),
        TrMetric.water => cups?.toDouble(),
        TrMetric.sleep => sleepMin == null ? null : sleepMin! / 60,
        TrMetric.ex => exMin?.toDouble(),
        TrMetric.body => kg,
        TrMetric.drug => medRate,
      };

  /// 点热力格出来的当日明细行（原型 `hTrendDay` 的日视图分支）。
  String detailTx(TrGoals g) {
    String n(double? v, int d) => v == null ? '—' : v.toStringAsFixed(d);
    return '${date.substring(5)} ${dayWd(date)} · '
        '喝水 ${cups ?? '—'}/${g.waterCups.toStringAsFixed(0)} 杯 · '
        '睡眠 ${n(sleepMin == null ? null : sleepMin! / 60, 1)}h · '
        '运动 ${n(exMin?.toDouble(), 0)} 分钟 · '
        '体重 ${n(kg, 1)}kg · '
        '用药 ${medRate == null ? '—' : '${medRate!.toStringAsFixed(0)}%'} · '
        '综合 ${n(score(g), 0)}%';
  }
}

// ==================== 取样：三档跨度 ====================

/// 三档跨度的取值（周 7 天／月 30 天／年 12 个月）；`12` 是**月**数不是天数，别拿去喂日取样。
const trRanges = <int>[7, 30, 12];

String trRangeTx(int r) => r == 12 ? '近 12 个月' : '近 $r 天';
String trRangeShortTx(int r) => r == 12 ? '年' : (r == 7 ? '周' : '月');

/// 旧→新的日序列（含今天）。日期一律 `healthClockProvider` 实算，禁写死。
List<String> trDaysBack(DateTime now, int n) =>
    [for (var i = n - 1; i >= 0; i--) dayKey(now.subtract(Duration(days: i)))];

/// 旧→新的月序列（`yyyy-MM`），含当月。
List<String> trMonthsBack(DateTime now, int n) => [
      for (var i = n - 1; i >= 0; i--)
        dayKey(DateTime(now.year, now.month - i, 1)).substring(0, 7)
    ];

/// 该档跨度要取多少天：**两倍**（当前期＋环比上期），年视图按月所以要 730 天量级。
int trFetchDays(int range) => range == 12 ? 731 : range * 2;

/// 当前期 / 上一期的日切片（都旧→新）。新用户上期不满一段时 `prev` 会变短甚至为空，
/// `trCompareTx` 据此出「上期无记录」，不做除零、也不拿短段外推。
({List<TrDay> cur, List<TrDay> prev}) trSplitDays(List<TrDay> days, int span) {
  final n = days.length;
  if (n <= span) return (cur: days, prev: const <TrDay>[]);
  return (
    cur: days.sublist(n - span),
    prev: days.sublist((n - 2 * span).clamp(0, n - span), n - span),
  );
}

/// 年视图的月分段：`months` 是 24 个月键（旧→新），后 12 为当前期、前 12 为上期。
({List<String> cur, List<String> prev}) trSplitMonths(List<String> months) {
  final n = months.length;
  if (n <= 12) return (cur: months, prev: const <String>[]);
  return (cur: months.sublist(n - 12), prev: months.sublist(n - 24, n - 12));
}

class TrCell {
  const TrCell({required this.key, required this.label, this.v});
  final String key; // 日视图＝yyyy-MM-dd；年视图＝yyyy-MM
  final String label; // 格内短标（`03-19`／`11月`）
  final double? v;
  bool get hasData => v != null;
}

/// 日视图格：旧→新，缺记录日 `v=null`（不补数）。
List<TrCell> trDayCells({required List<TrDay> days, required TrMetric m, required TrGoals g}) => [
      for (final d in days)
        TrCell(key: d.date, label: d.date.substring(5), v: d.valueOf(m, g)),
    ];

/// 年视图格：按月聚合，月均只吃该月有记录日（原型除以整月天数，会把空日当 0 拉低月均＝登记偏离）。
List<TrCell> trMonthCells({
  required List<TrDay> days,
  required List<String> months,
  required TrMetric m,
  required TrGoals g,
}) {
  return [
    for (final mk in months)
      TrCell(
        key: mk,
        label: '${int.parse(mk.substring(5))}月',
        v: trAvg([for (final d in days) if (d.date.startsWith(mk)) d.valueOf(m, g)]),
      ),
  ];
}

/// 均值＝只按有记录日取；全空返回 null（UI 出「—」，不出现 NaN）。
double? trAvg(Iterable<double?> xs) {
  final v = <double>[for (final x in xs) ?x];
  if (v.isEmpty) return null;
  return v.reduce((a, b) => a + b) / v.length;
}

double trSum(Iterable<double?> xs) => <double>[for (final x in xs) ?x].fold(0, (a, b) => a + b);

int trCountAtGoal(Iterable<double?> xs, double? goal) =>
    goal == null ? 0 : <double>[for (final x in xs) if (x != null && x >= goal) x].length;

// ==================== 热力色阶 ====================

({double mn, double mx}) trScale(List<TrCell> cells, double? goal) {
  final vs = <double>[for (final c in cells) ?c.v];
  final mx = <double>[...vs, ?goal, 1].reduce((a, b) => a > b ? a : b);
  final mn = <double>[...vs, 0].reduce((a, b) => a < b ? a : b);
  return (mn: mn, mx: mx);
}

/// 四档：`>=0.72 → 3`、`>=0.45 → 2`、`>=0.18 → 1`、其余 0；无数据出 -1（空格，不吃 0 档色）。
/// 阈值取自原型 `hTrends` 的 `r>=.72/.45/.18`（变异刀1 钉这三档）。
int trHeatLevel(double? v, {required double mn, required double mx}) {
  if (v == null) return -1;
  final r = (v - mn) / (mx - mn).abs().clamp(0.0001, double.infinity);
  return r >= 0.72 ? 3 : (r >= 0.45 ? 2 : (r >= 0.18 ? 1 : 0));
}

/// 色阶端点（原型 `trLegend`）：`色阶 0 ~ 8.0杯`，年视图前面再挂「按月 · 」。
String trLegendTx({required double mn, required double mx, required String unit, required bool year}) =>
    '${year ? '按月 · ' : ''}色阶 ${mn.toStringAsFixed(0)} ~ ${mx.toStringAsFixed(1)}$unit';

String trHeatTx(TrMetric m, int range) => '达标热力 · ${m.label} · ${trRangeTx(range)}';

/// 点年视图的格：月均＋月合计（百分比指标改口「约 N 天/月达标」），并明说日明细要切「月」。
String trMonthDetailTx(String monthKey, double? v, TrMetric m) {
  if (v == null) return '$monthKey 无记录 · 日明细请切「月」';
  final tx = v.toStringAsFixed(m.decimals);
  final tail = m.shape == TrShape.percent
      ? '约 ${(v * 30 / 100).round()} 天/月达标'
      : '月合计约 ${(v * 30).toStringAsFixed(0)} ${m.unit}';
  final ym = '${monthKey.substring(0, 4)}-${monthKey.substring(5)}';
  return '$ym 月均 $tx ${m.unit} · $tail · 年视图按月聚合，日明细请切「月」';
}

// ==================== 四数据位（三形态） ====================

class TrSlot {
  const TrSlot(this.value, this.label);
  final String value;
  final String label;
}

/// 原型 `hTrends` 的 `tv1..tv4` 三形态：
/// · 体重＝期末 / 区间均值 / 区间变化 / 距目标；
/// · 百分比类（综合·用药）＝平均达标 / 达标天 / 峰值 / 待改善天；
/// · 量类＝合计 / 日均 / 达标天 / 单日峰值。
List<TrSlot> trSlots({required TrMetric m, required List<double?> vals, required TrGoals g}) {
  final vs = <double>[for (final v in vals) ?v];
  if (vs.isEmpty) return [for (final l in _slotLabels(m)) TrSlot('—', l)];
  final goal = g.of(m);
  final dec = m.decimals;
  final delta = vs.last - vs.first;
  String f(double v) => v.toStringAsFixed(dec);
  return switch (m.shape) {
    TrShape.body => [
        TrSlot(f(vs.last), '期末 kg'),
        TrSlot(f(trAvg(vals)!), '区间均值'),
        TrSlot('${delta >= 0 ? '+' : ''}${f(delta)}', '区间变化'),
        TrSlot(goal == null
            ? '未设目标'
            : '${vs.last - goal >= 0 ? '+' : ''}${f(vs.last - goal)}', '距目标'),
      ],
    TrShape.percent => [
        TrSlot('${trAvg(vals)!.toStringAsFixed(0)}%', '平均达标'),
        TrSlot('${trCountAtGoal(vals, goal)}', '达标天'),
        TrSlot('${vs.reduce((a, b) => a > b ? a : b).toStringAsFixed(0)}%', '峰值'),
        TrSlot(vals.where((v) => v != null && v < TrGoals.lowDayPct).length.toString(), '待改善天'),
      ],
    TrShape.quantity => [
        TrSlot(trSum(vals).toStringAsFixed(0), '合计 ${m.unit}'),
        TrSlot((trAvg(vals) ?? 0).toStringAsFixed(dec), '日均 ${m.unit}'),
        TrSlot(trCountAtGoal(vals, goal).toString(), '达标天'),
        TrSlot(vs.reduce((a, b) => a > b ? a : b).toStringAsFixed(dec), '单日峰值'),
      ],
  };
}

List<String> _slotLabels(TrMetric m) => switch (m.shape) {
      TrShape.body => const ['期末 kg', '区间均值', '区间变化', '距目标'],
      TrShape.percent => const ['平均达标', '达标天', '峰值', '待改善天'],
      TrShape.quantity => const ['合计', '日均', '达标天', '单日峰值'],
    };

/// 曲线卡脚注（原型 `trCompare`）：环比上期＋日均；上期无记录出实话，不做除零。
String trCompareTx({
  required List<double?> cur,
  required List<double?> prev,
  required TrMetric m,
}) {
  final a = trAvg(cur), p = trAvg(prev);
  final cmp = a == null || p == null || p == 0
      ? '环比上期 —（上期无记录）'
      : (() {
          final c = (a - p) / p * 100;
          return '环比上期 ${c >= 0 ? '+' : ''}${c.toStringAsFixed(1)}%';
        })();
  return '$cmp · 日均 ${(a ?? 0).toStringAsFixed(m.decimals)}${m.unit}';
}

// ==================== 健康周报 ====================

class TrTile {
  const TrTile(this.value, this.name);
  final String value;
  final String name;
}

class TrDiff {
  const TrDiff(this.name, this.delta, this.tag);
  final String name;
  final String delta;

  /// 三档判词：好 / 持平 / 注意（原型另有「优」，与「好」同义，合并）
  final String tag;
}

class TrBar {
  const TrBar(this.label, this.score);
  final String label; // `03-19 周五`
  final double score;
}

class TrWeekReport {
  const TrWeekReport({
    required this.rangeTx,
    required this.weekTx,
    required this.tiles,
    required this.diffs,
    required this.bars,
    required this.verdictTx,
  });

  final String rangeTx;
  final String weekTx;
  final List<TrTile> tiles;
  final List<TrDiff> diffs;
  final List<TrBar> bars;
  final String verdictTx;

  /// 「复制文本」按钮的真内容（原型是 `toast(…模拟)`；长图按钮本期不铺）。
  String get copyText => [
        'LifeHarness 健康周报 · $weekTx（$rangeTx）',
        '结论：$verdictTx',
        for (final t in tiles) '${t.name}：${t.value}',
        '同比上周：',
        for (final d in diffs) '${d.name} ${d.delta}（${d.tag}）',
        '每日达标：',
        for (final b in bars) '${b.label} ${b.score.toStringAsFixed(0)}%',
        '全部本机计算 · 无网络上传',
      ].join('\n');
}

/// ISO 周号（原型写死「第 38 周」，实态按今天所在周算）。
int trWeekNo(DateTime d) {
  final t = DateTime(d.year, d.month, d.day);
  final wd = t.weekday; // 1=周一
  final thu = t.add(Duration(days: 4 - wd));
  final y0 = DateTime(thu.year, 1, 1);
  return 1 + thu.difference(y0).inDays ~/ 7;
}

String trWeekTx(DateTime now) => '第 ${trWeekNo(now)} 周';

/// 周报六枚 tile＋同比上周五行＋七日条＋结论句，一次算全（弹层只管画）。
/// `thisWeek`/`lastWeek` 各七天、旧→新，缺记录日 `recorded=false`。
TrWeekReport trWeekReport({
  required List<TrDay> thisWeek,
  required List<TrDay> lastWeek,
  required TrGoals goals,
  required DateTime now,
}) {
  double? avg(List<TrDay> ws, double? Function(TrDay) f) => trAvg([for (final d in ws) f(d)]);
  double? sleepH(TrDay d) => d.sleepMin == null ? null : d.sleepMin! / 60;
  double? lastKg(List<TrDay> ws) {
    for (final d in ws.reversed) {
      if (d.kg != null) return d.kg;
    }
    return null;
  }

  double? paceAvg(List<TrDay> ws) {
    final all = [for (final d in ws) ...d.paces];
    if (all.isEmpty) return null;
    return all.fold<int>(0, (a, b) => a + b) / all.length;
  }

  final water = avg(thisWeek, (d) => d.cups?.toDouble());
  final sleep = avg(thisWeek, sleepH);
  final lastWater = avg(lastWeek, (d) => d.cups?.toDouble());
  final lastSleep = avg(lastWeek, sleepH);
  final exDays = thisWeek.where((d) => (d.exMin ?? 0) >= TrGoals.exSessionMin).length;
  final lastExDays = lastWeek.where((d) => (d.exMin ?? 0) >= TrGoals.exSessionMin).length;
  final kg = lastKg(thisWeek), lastKgV = lastKg(lastWeek);
  final pace = paceAvg(thisWeek), lastPace = paceAvg(lastWeek);
  final planned = thisWeek.fold<int>(0, (a, d) => a + (d.medPlanned ?? 0));
  final taken = thisWeek.fold<int>(0, (a, d) => a + (d.medTaken ?? 0));
  final compliance = planned <= 0 ? null : (taken / planned * 100).roundToDouble();
  final fullDays = thisWeek.where((d) => (d.score(goals) ?? 0) >= TrGoals.scoreGoalPct).length;

  final tiles = <TrTile>[
    TrTile('${(water ?? 0).toStringAsFixed(1)} 杯', '日均喝水'),
    TrTile('${(sleep ?? 0).toStringAsFixed(1)} h', '日均睡眠'),
    TrTile('$exDays 次', '运动次数'),
    TrTile('${(fullDays / 7 * 100).round()}%', '全达标天'),
    TrTile(kg == null ? '—' : '${kg.toStringAsFixed(1)} kg', '期末体重'),
    TrTile(compliance == null ? '—' : '${compliance.toStringAsFixed(0)}%', '用药依从'),
  ];

  String tag(String v) => v.startsWith('-') ? '注意' : (v == '±0' ? '持平' : '好');
  String dlt(double? a, double? p, int dec, String unit) {
    if (a == null || p == null) return '—';
    final v = a - p;
    if (v.abs() < (dec == 0 ? 0.5 : 0.05)) return '±0';
    return '${v > 0 ? '+' : ''}${v.toStringAsFixed(dec)} $unit';
  }

  TrDiff diff(String name, double? a, double? p, int dec, String unit) {
    final tx = dlt(a, p, dec, unit);
    return TrDiff(name, tx, tag(tx));
  }

  final diffs = <TrDiff>[
    diff('日均睡眠', sleep, lastSleep, 1, 'h'),
    diff('日均喝水', water, lastWater, 1, '杯'),
    diff('运动次数', exDays.toDouble(), lastExDays.toDouble(), 0, '次'),
    TrDiff('平均配速', _paceDlt(pace, lastPace), _paceTag(pace, lastPace)),
    diff('体重', kg, lastKgV, 1, 'kg'),
  ];

  final bars = [
    for (final d in thisWeek)
      TrBar('${d.date.substring(5)} ${dayWd(d.date)}', d.score(goals) ?? 0),
  ];

  final sleepWord = sleep == null || lastSleep == null
      ? '睡眠上周无记录'
      : (sleep - lastSleep > 0.05
          ? '睡眠比上周改善'
          : (sleep - lastSleep < -0.05 ? '睡眠比上周回落' : '睡眠与上周持平'));
  final lowWater = thisWeek.where((d) => (d.cups ?? 0) < goals.waterCups).length;

  final verdict = '本周 ${(fullDays / 7 * 100).round()}% 的天数完成全部目标 · '
      '$sleepWord · 喝水有 $lowWater 天不足 ${goals.waterCups.toStringAsFixed(0)} 杯';

  final first = thisWeek.isEmpty ? '' : thisWeek.first.date;
  final lastD = thisWeek.isEmpty ? dayKey(now) : thisWeek.last.date;
  return TrWeekReport(
    rangeTx: first.isEmpty ? '—' : '${first.substring(5)} ~ ${lastD.substring(5)}',
    weekTx: trWeekTx(now),
    tiles: tiles,
    diffs: diffs,
    bars: bars,
    verdictTx: verdict,
  );
}

/// 配速差：秒/公里换算成「分′秒″」的带符号差（越小越快＝好）。
String _paceDlt(double? cur, double? prev) {
  if (cur == null || prev == null) return '—';
  final d = (cur - prev).round();
  if (d == 0) return '±0';
  return '${d > 0 ? '+' : ''}$d″ /km';
}

String _paceTag(double? cur, double? prev) {
  if (cur == null || prev == null) return '持平';
  if (cur < prev) return '好';
  if (cur > prev) return '注意';
  return '持平';
}
