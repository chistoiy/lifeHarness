import 'dart:math' as math;

import 'ledger_txn.dart';

/// 记账口径纯函数层（计划 §3/§4 + 九·补 指标口径；全部可单测，不触库）。

// ---- 日期 ----

String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}'
    '-${d.day.toString().padLeft(2, '0')}';

String monthKey(DateTime d) => dayKey(d).substring(0, 7);

DateTime parseDay(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// 'YYYY-MM-DD' → 当月内日号。
int dayNum(String date) => int.parse(date.substring(8));

/// 该月天数（含闰年）。命名避开 FinMetricCtx.daysInMonth 字段遮蔽。
int monthDayCount(String month) {
  final y = int.parse(month.substring(0, 4));
  final m = int.parse(month.substring(5, 7));
  return DateTime(y, m + 1, 0).day;
}

const wdBrief = ['日', '一', '二', '三', '四', '五', '六'];

String wdOf(String date) => wdBrief[parseDay(date).weekday % 7];

/// 月份步进：'2026-01' + (-1) → '2025-12'（跨年安全）。
String monthStep(String month, int d) {
  final y = int.parse(month.substring(0, 4));
  final m0 = int.parse(month.substring(5, 7)) - 1; // 0 基
  final t = y * 12 + m0 + d;
  final nm = t % 12 + 1; // Dart % 恒非负（除数 12>0）
  final ny = (t - (nm - 1)) ~/ 12;
  return '$ny-${nm.toString().padLeft(2, '0')}';
}

String finLbl(String month) =>
    '${month.substring(0, 4)}年${int.parse(month.substring(5, 7))}月';

// ---- 金额 ----

/// 原型 money()：¥ + zh-CN 千分位两位小数（绝对值）。
String money(double v) {
  final abs = v.abs();
  final parts = abs.toStringAsFixed(2).split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    buf.write(intPart[i]);
    final remain = intPart.length - i - 1;
    if (remain > 0 && remain % 3 == 0) buf.write(',');
  }
  return '¥$buf.${parts[1]}';
}

/// 原型 AMT()：全局金额隐藏开关统一打点。
String amtText(double v, {bool hide = false}) => hide ? '¥•••••' : money(v);

/// 带符号金额（负值前缀 '-'，绝对值千分位）。
String signedAmt(double v, {bool hide = false}) =>
    '${v < 0 ? '-' : ''}${amtText(v.abs(), hide: hide)}';

// ---- 四则键盘求值（§4：先乘除后加减；12+3×4=24；除零/非法回退左值） ----

/// [exprVal] 输入为键盘拼出的表达式串，运算符为 '+','−','×','÷'。
double exprVal(String e) {
  if (e.isEmpty) return 0;
  final toks = RegExp(r'\d+\.?\d*|[+−×÷]').allMatches(e).map((m) => m.group(0)!).toList();
  if (toks.isEmpty) return 0;
  // pass1：先算 × ÷（除零回退左值，同原型 JS 语义）
  final pass1 = <String>[];
  for (var i = 0; i < toks.length; i++) {
    final tk = toks[i];
    if (tk == '×' || tk == '÷') {
      final a = pass1.isEmpty ? 0.0 : (double.tryParse(pass1.removeLast()) ?? 0);
      final b = i + 1 < toks.length ? (double.tryParse(toks[++i]) ?? 0) : 0.0;
      pass1.add((tk == '×' ? a * b : (b != 0 ? a / b : a)).toString());
    } else {
      pass1.add(tk);
    }
  }
  // pass2：+ −
  var res = double.tryParse(pass1.isEmpty ? '0' : pass1[0]) ?? 0;
  for (var i = 1; i + 1 < pass1.length; i += 2) {
    final op = pass1[i];
    final v = double.tryParse(pass1[i + 1]);
    if (v == null) break;
    if (op == '+') {
      res += v;
    } else if (op == '−') {
      res -= v;
    }
  }
  return math.max(0, double.parse(res.toStringAsFixed(2)));
}

/// 键入约束（§4 记一笔键盘）：小数点每段唯一、单段最长 9 字符。
bool exprDigitAllowed(String expr, String key) {
  final tail = expr.split(RegExp(r'[+−×÷]')).last;
  if (key == '.' && tail.contains('.')) return false;
  return tail.length < 9;
}

// ---- 聚合口径（mStat / catStat / dayMap；nb 剔除、refund 冲抵） ----

class MStat {
  const MStat({required this.exp, required this.inc});
  final double exp;
  final double inc;
  double get net => inc - exp;
}

/// 月合计：按 `bk` 过滤后的流水集合聚合（unpaid 仍计收支；nb 剔除）。
MStat mStat(Iterable<LedgerTxn> txns) {
  var e = 0.0, i = 0.0;
  for (final t in txns) {
    if (t.nb) continue;
    if (t.kind == LedgerTxn.kExpense) {
      e += t.amt;
    } else if (t.kind == LedgerTxn.kRefund) {
      e -= t.amt;
    } else if (t.kind == LedgerTxn.kIncome) {
      i += t.amt;
    }
  }
  return MStat(exp: e, inc: i);
}

/// 分类支出聚合（>0 过滤、降序）。withNb=true 时不剔除不计入行（分类预算进度用）。
List<(int catId, double v)> catStat(Iterable<LedgerTxn> txns, {bool withNb = false}) {
  final o = <int, double>{};
  for (final t in txns) {
    if (t.nb && !withNb) continue;
    final cid = t.catId;
    if (cid == null) continue;
    if (t.kind == LedgerTxn.kExpense) {
      o[cid] = (o[cid] ?? 0) + t.amt;
    } else if (t.kind == LedgerTxn.kRefund) {
      o[cid] = (o[cid] ?? 0) - t.amt;
    }
  }
  final list = o.entries.where((e) => e.value > 0).map((e) => (e.key, e.value)).toList();
  list.sort((a, b) => b.$2.compareTo(a.$2));
  return list;
}

class DayAgg {
  double exp = 0;
  double inc = 0;
  final Set<int> cats = {};
}

Map<int, DayAgg> dayMap(Iterable<LedgerTxn> txns) {
  final o = <int, DayAgg>{};
  for (final t in txns) {
    final k = dayNum(t.date);
    final v = o.putIfAbsent(k, DayAgg.new);
    if (t.kind == LedgerTxn.kExpense) {
      v.exp += t.amt;
      v.cats.add(t.catId ?? 0);
    } else if (t.kind == LedgerTxn.kRefund) {
      v.exp -= t.amt;
      v.cats.add(t.catId ?? 0);
    } else if (t.kind == LedgerTxn.kIncome) {
      v.inc += t.amt;
    }
  }
  return o;
}

/// 按日分组的日合计行（L1 列表：日支/日收；refund/adjust 记负支出）。
({double exp, double inc}) dayTotals(Iterable<LedgerTxn> txns) {
  var e = 0.0, i = 0.0;
  for (final t in txns) {
    if (t.kind == LedgerTxn.kExpense) {
      e += t.amt;
    } else if (t.kind == LedgerTxn.kRefund || t.kind == LedgerTxn.kAdjust) {
      e -= t.amt;
    } else if (t.kind == LedgerTxn.kIncome) {
      i += t.amt;
    }
  }
  return (exp: e, inc: i);
}

// ---- 记一笔快捷 chips（§4 + 九·补1/2） ----

/// 近 30 天高频 (catId,sub) ∪ 收藏（去重截 12），按当前收支树过滤。
List<(int, String)> recentFavChips({
  required Iterable<LedgerTxn> last30,
  required List<(int, String)> favs,
  required Set<int> treeCatIds,
}) {
  final cnt = <(int, String), int>{};
  for (final t in last30) {
    final cid = t.catId;
    if (cid == null || t.kind == LedgerTxn.kTransfer || t.kind == LedgerTxn.kAdjust) {
      continue;
    }
    if (!treeCatIds.contains(cid)) continue;
    cnt[(cid, t.sub)] = (cnt[(cid, t.sub)] ?? 0) + 1;
  }
  final out = <(int, String)>[
    for (final f in favs)
      if (treeCatIds.contains(f.$1)) f
  ];
  final recent = cnt.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in recent) {
    if (out.length >= 12) break;
    if (!out.contains(e.key)) out.add(e.key);
  }
  return out.take(12).toList();
}

// ---- 顶部卡 24 项指标（九·补5 指标口径；输入=当前账本聚合值，全部排除 nb） ----

/// 指标计算上下文：一次性备好各窗口聚合，避免每键全表扫。
class FinMetricCtx {
  const FinMetricCtx({
    required this.today,
    required this.month,
    required this.todayStat,
    required this.weekStat,
    required this.monthStat,
    required this.yearStat,
    required this.allStat,
    required this.budgetTotal,
    required this.daysInMonth,
    required this.elapsedDays,
    required this.leftDays,
    required this.balances,
  });

  /// 窗口聚合均已排除 nb；周界=周一起始；年=finMonth 年份。
  final String today;
  final String month;
  final MStat todayStat;
  final MStat weekStat;
  final MStat monthStat;
  final MStat yearStat;
  final MStat allStat;

  final double budgetTotal;
  final int daysInMonth;

  /// 当月已过天数（当前月=今天日号；历史月=全月）。
  final int elapsedDays;

  /// 剩余天数（至少 1）。
  final int leftDays;

  /// 全部非归档账户余额（跨账本合并 accBal 口径）。
  final List<double> balances;

  /// [bookTxns]=当前账本全部流水；账户余额另传（跨账本合并口径）。
  factory FinMetricCtx.build({
    required List<LedgerTxn> bookTxns,
    required String today,
    required String month,
    required double budgetTotal,
    required List<double> balances,
  }) {
    Iterable<LedgerTxn> win(String s, String e) => bookTxns.where(
        (t) => !t.nb && t.date.compareTo(s) >= 0 && t.date.compareTo(e) <= 0);
    final y = month.substring(0, 4);
    final td = parseDay(today);
    final weekStart = dayKey(td.subtract(Duration(days: td.weekday - 1)));
    final weekEnd =
        dayKey(parseDay(weekStart).add(const Duration(days: 6)));
    final dim = monthDayCount(month);
    final isCur = month == today.substring(0, 7);
    final elaps = isCur ? dayNum(today) : dim;
    return FinMetricCtx(
      today: today,
      month: month,
      todayStat: mStat(win(today, today)),
      weekStat: mStat(win(weekStart, weekEnd)),
      monthStat:
          mStat(win('$month-01', '$month-${dim.toString().padLeft(2, '0')}')),
      yearStat: mStat(win('$y-01-01', '$y-12-31')),
      allStat: mStat(win('0000-01-01', '9999-12-31')),
      budgetTotal: budgetTotal,
      daysInMonth: dim,
      elapsedDays: elaps,
      leftDays: math.max(1, dim - elaps + 1),
      balances: balances,
    );
  }
}

/// 24 指标目录（键/名；分节顺序与原型 FIN_METRICS 一致）。
const finMetrics = <(String, String)>[
  ('teToday', '今日支出'), ('tiToday', '今日收入'), ('balToday', '今日结余'),
  ('teWeek', '本周支出'), ('tiWeek', '本周收入'), ('balWeek', '本周结余'),
  ('teMonth', '本月支出'), ('tiMonth', '本月收入'), ('balMonth', '本月结余'),
  ('teYear', '本年支出'), ('tiYear', '本年收入'), ('balYear', '本年结余'),
  ('budToday', '今日预算'), ('budLeft', '剩余预算'), ('budDayLeft', '剩余日预算'),
  ('avgTe', '日均支出'), ('avgTi', '日均收入'), ('avgBal', '日均结余'),
  ('netWorth', '净资产'), ('assets', '总资产'), ('liab', '总负债'),
  ('teAll', '总支出'), ('tiAll', '总收入'), ('balAll', '总结余'),
];

String finMetricName(String k) =>
    finMetrics.firstWhere((e) => e.$1 == k, orElse: () => (k, k)).$2;

/// 24 指标统一取值（顶部卡四数据位 / 配置弹层预览共用同口径）。
double finMetricVal(String k, FinMetricCtx c) {
  switch (k) {
    case 'teToday':
      return c.todayStat.exp;
    case 'tiToday':
      return c.todayStat.inc;
    case 'balToday':
      return c.todayStat.net;
    case 'teWeek':
      return c.weekStat.exp;
    case 'tiWeek':
      return c.weekStat.inc;
    case 'balWeek':
      return c.weekStat.net;
    case 'teMonth':
      return c.monthStat.exp;
    case 'tiMonth':
      return c.monthStat.inc;
    case 'balMonth':
      return c.monthStat.net;
    case 'teYear':
      return c.yearStat.exp;
    case 'tiYear':
      return c.yearStat.inc;
    case 'balYear':
      return c.yearStat.net;
    case 'budToday':
      return c.budgetTotal / c.daysInMonth;
    case 'budLeft':
      return c.budgetTotal - c.monthStat.exp;
    case 'budDayLeft':
      return math.max(0, (c.budgetTotal - c.monthStat.exp) / c.leftDays);
    case 'avgTe':
      return c.monthStat.exp / c.elapsedDays;
    case 'avgTi':
      return c.monthStat.inc / c.elapsedDays;
    case 'avgBal':
      return c.monthStat.net / c.elapsedDays;
    case 'netWorth':
      return c.balances.fold<double>(0, (x, v) => x + v);
    case 'assets':
      return c.balances.where((v) => v > 0).fold<double>(0, (x, v) => x + v);
    case 'liab':
      return -c.balances.where((v) => v < 0).fold<double>(0, (x, v) => x + v);
    case 'teAll':
      return c.allStat.exp;
    case 'tiAll':
      return c.allStat.inc;
    case 'balAll':
      return c.allStat.net;
    default:
      return 0;
  }
}

String finMetricTxt(String k, FinMetricCtx c, {bool hide = false}) =>
    signedAmt(finMetricVal(k, c), hide: hide);

// ---- 消费洞察（九·补3 · 纯前端规则引擎四条，标签仅 合理/优秀/注意；不落库） ----

/// 返回 (标签, 图标键, 标题, 副标题) 列表；输入=当前区间聚合值（报表批2 接线）。
List<(String, String, String, String)> spendingInsights({
  required MStat cur,
  required double prevExp,
  required (String, double)? topRank,
  required double totalExp,
  required double budgetTotal,
  required (String, double)? biggest,
}) {
  final ins = <(String, String, String, String)>[];
  if (topRank != null && totalExp > 0) {
    final pc = topRank.$2 / totalExp * 100;
    ins.add((
      pc >= 40 ? '注意' : '合理',
      'pie',
      '${topRank.$1}是主要支出',
      '占比 ${pc.toStringAsFixed(0)}% · 共 ${money(topRank.$2)}'
    ));
  }
  if (prevExp > 0) {
    final cmp = (cur.exp - prevExp) / prevExp * 100;
    if (cmp <= -5) {
      ins.add((
        '优秀',
        'down',
        '支出较上期减少 ${cmp.abs().toStringAsFixed(0)}%',
        '继续保持消费节奏'
      ));
    } else if (cmp >= 5) {
      ins.add((
        '注意',
        'bars',
        '支出较上期增加 ${cmp.toStringAsFixed(0)}%',
        '关注高频分类的变化'
      ));
    } else {
      ins.add((
        '合理',
        'scale',
        '支出与上期基本持平',
        '环比 ${cmp >= 0 ? '+' : ''}${cmp.toStringAsFixed(0)}%'
      ));
    }
  }
  if (budgetTotal > 0) {
    final bpct = cur.exp / budgetTotal * 100;
    if (cur.exp > budgetTotal) {
      ins.add((
        '注意',
        'target',
        '本期预算已超支 ${money(cur.exp - budgetTotal)}',
        '可到预算页调整额度'
      ));
    } else if (bpct >= 90) {
      ins.add((
        '注意',
        'target',
        '预算已用 ${bpct.toStringAsFixed(0)}%',
        '剩余 ${money(budgetTotal - cur.exp)}'
      ));
    } else {
      ins.add((
        '合理',
        'target',
        '预算余量充足',
        '已用 ${bpct.toStringAsFixed(0)}% · 剩 ${money(budgetTotal - cur.exp)}'
      ));
    }
  }
  if (biggest != null) {
    ins.add(('合理', 'receipt', '最大单笔 ${biggest.$1}', money(biggest.$2)));
  }
  return ins;
}

// ---- L4 统计报表（批2a · 原型 repRange/renderReport 口径；聚合统一剔 nb） ----

/// 'YYYY-MM-DD' ± n 天（原型 shiftDays）。
String shiftDays(String s, int n) => dayKey(parseDay(s).add(Duration(days: n)));

/// 报表趋势桶（周7日 / 月各日 / 年12月 / 自定义按天）。
class RepBucket {
  const RepBucket(this.s, this.e, this.label);
  final String s;
  final String e;
  final String label;
}

/// 报表周期区间（原型 repRange 返回体）。
class RepRange {
  const RepRange({
    required this.s,
    required this.e,
    required this.label,
    required this.buckets,
    required this.monthlyAvg,
  });

  final String s;
  final String e;
  final String label;
  final List<RepBucket> buckets;

  /// 年视图=月均，其余=日均（九·补3 均值线口径）。
  final bool monthlyAvg;

  /// 区间天数（原型 days = (e-s)/864e5 + 1）。
  int get days => parseDay(e).difference(parseDay(s)).inDays + 1;
}

/// L4 周期区间（原型 repRange 逐项对照）：
/// week=近 7 天（weekOffset 供前后翻期，按 7 天平移）· month=finMonth 各日 ·
/// year=finMonth 年份 12 月 · custom=起讫按天分桶（上限 62 桶，同原型截断）。
RepRange repRange({
  required String period,
  required String today,
  required String month,
  String? from,
  String? to,
  int weekOffset = 0,
}) {
  switch (period) {
    case 'week':
      final end = shiftDays(today, weekOffset * 7);
      final b = [
        for (var i = 0; i < 7; i++) (() {
          final ds = shiftDays(end, -(6 - i));
          return RepBucket(ds, ds, ds.substring(8));
        })(),
      ];
      final s = b.first.s, e = b.last.e;
      return RepRange(
        s: s,
        e: e,
        label: weekOffset == 0 ? '近 7 天' : '${s.substring(5)} ~ ${e.substring(5)}',
        buckets: b,
        monthlyAvg: false,
      );
    case 'year':
      final y = int.parse(month.substring(0, 4));
      return RepRange(
        s: '$y-01-01',
        e: '$y-12-31',
        label: '$y年',
        buckets: [
          for (var m = 1; m <= 12; m++)
            RepBucket(
              dayKey(DateTime(y, m, 1)),
              dayKey(DateTime(y, m + 1, 0)),
              '$m月',
            ),
        ],
        monthlyAvg: true,
      );
    case 'custom':
      final s = from ?? '$month-01';
      final e = to ?? today;
      final b = <RepBucket>[];
      var cur = s;
      while (cur.compareTo(e) <= 0 && b.length < 62) {
        b.add(RepBucket(cur, cur, cur.substring(8)));
        cur = shiftDays(cur, 1);
      }
      return RepRange(
        s: s,
        e: e,
        label: '${s.substring(5)} ~ ${e.substring(5)}',
        buckets: b,
        monthlyAvg: false,
      );
    default: // month
      final dim = monthDayCount(month);
      return RepRange(
        s: '$month-01',
        e: '$month-${dim.toString().padLeft(2, '0')}',
        label: finLbl(month),
        buckets: [
          for (var dd = 1; dd <= dim; dd++)
            RepBucket(
              '$month-${dd.toString().padLeft(2, '0')}',
              '$month-${dd.toString().padLeft(2, '0')}',
              '$dd',
            ),
        ],
        monthlyAvg: false,
      );
  }
}

/// 区间流水（当前账本集合内 s≤date≤e；bk 过滤在数据源侧已完成）。
List<LedgerTxn> txnsBetween(Iterable<LedgerTxn> all, String s, String e) =>
    all.where((t) => t.date.compareTo(s) >= 0 && t.date.compareTo(e) <= 0)
        .toList();

/// 趋势分桶聚合（柱与曲线共用同一 buckets，九·补3）：每桶 exp/inc（剔 nb、refund 冲抵）。
List<({String label, double exp, double inc})> repTrend(
  Iterable<LedgerTxn> all,
  RepRange r,
) =>
    [
      for (final b in r.buckets)
        (() {
          final s = mStat(txnsBetween(all, b.s, b.e));
          return (label: b.label, exp: s.exp, inc: s.inc);
        })(),
    ];

/// 环比上期窗口（原型 ps=s−days / pe=s−1）。
(String, String) repPrevWindow(RepRange r) =>
    (shiftDays(r.s, -r.days), shiftDays(r.s, -1));

/// 环比百分比（上期无数据回 0，同原型 cmp 口径）。
double momPct(double cur, double prevExp) =>
    prevExp != 0 ? (cur - prevExp) / prevExp * 100 : 0;

/// 排行键（九·补2④）：大类=按 cat、小类=按 cat|sub（sub 空串归「未细分」）。
String rankKey(LedgerTxn t, {required bool bySub}) =>
    bySub ? '${t.catId}|${t.sub}' : '${t.catId}';

/// L4 分类排行双维度（九·补2④）：expense 累加、refund 冲抵；剔 nb 与无分类行；
/// v>0 保留、降序；小类维度截 Top15（大类不截，同原型 slice(99)）。
List<(String, double)> rankAgg(Iterable<LedgerTxn> all, {required bool bySub}) {
  final m = <String, double>{};
  for (final t in all) {
    if (t.nb || t.catId == null) continue;
    if (t.kind != LedgerTxn.kExpense && t.kind != LedgerTxn.kRefund) continue;
    final k = rankKey(t, bySub: bySub);
    m[k] = (m[k] ?? 0) + (t.kind == LedgerTxn.kExpense ? t.amt : -t.amt);
  }
  final list =
      m.entries.where((e) => e.value > 0).map((e) => (e.key, e.value)).toList();
  list.sort((a, b) => b.$2.compareTo(a.$2));
  return bySub ? list.take(15).toList() : list;
}

/// L4 钻取（repDrill）：区间内该排行键的 expense/refund 流水，日期降序。
List<LedgerTxn> drillTxns(
  Iterable<LedgerTxn> rangeTxns, {
  required String key,
  required bool bySub,
}) {
  final out = rangeTxns
      .where((t) =>
          !t.nb &&
          (t.kind == LedgerTxn.kExpense || t.kind == LedgerTxn.kRefund) &&
          rankKey(t, bySub: bySub) == key)
      .toList();
  out.sort((a, b) => b.date.compareTo(a.date));
  return out;
}

/// L4 Top 支出项目：expense 按备注聚合（空备注回落 [nameOf] 类目名），降序截 [cap]。
List<(String, double)> topNotes(
  Iterable<LedgerTxn> all, {
  required String Function(LedgerTxn) nameOf,
  int cap = 5,
}) {
  final m = <String, double>{};
  for (final t in all) {
    if (t.nb || t.kind != LedgerTxn.kExpense) continue;
    final k = t.note.isNotEmpty ? t.note : nameOf(t);
    m[k] = (m[k] ?? 0) + t.amt;
  }
  final list =
      m.entries.map((e) => (e.key, e.value)).toList()
        ..sort((a, b) => b.$2.compareTo(a.$2));
  return list.take(cap).toList();
}

// ---- L5 预算中心（批2b · 原型 renderBudget / L17 结转口径） ----

/// L17 结转额（原型 carryAmt）：上月总预算>0 时为 max(0, 上月总预算−上月支出)，
/// 上月未设总额恒 0；支出口径同 mStat（剔 nb、refund 冲抵）。
double carryOf({required double prevTotal, required double prevExp}) =>
    prevTotal > 0 ? math.max(0.0, prevTotal - prevExp) : 0;

/// 「日均可用」剩余天数（§7 monthStart 仅作用于该口径，不改流水归属）：
/// 原型 renderBudget：非当前查看月恒 1（历史/未来月按月末）；当前月且
/// monthStart=1 → 自然月剩余（含今日，至少 1）；monthStart>1 → 预算周期
/// （本月 monthStart 日 ~ 次月 monthStart−1 日，末日截断到次月天数）剩余。
int budLeftDays({
  required String month,
  required String today,
  int monthStart = 1,
}) {
  final dim = monthDayCount(month);
  if (month != today.substring(0, 7)) return 1;
  final tDay = dayNum(today);
  final ms = math.max(1, math.min(monthStart, dim));
  if (ms <= 1) return math.max(1, dim - tDay + 1);
  final nextDim = monthDayCount(monthStep(month, 1));
  // 显式 int 局部：避免 `int + math.min(…)` 位置把 T 向下推断为 num。
  final int tail = math.min(ms - 1, nextDim);
  final int cycleTotal = (dim - ms + 1) + tail;
  if (tDay < ms) return cycleTotal; // 本预算周期尚未开始：整周期剩余
  return math.max(1, cycleTotal - (tDay - ms + 1) + 1);
}

String _p2(int v) => v.toString().padLeft(2, '0');

// ---- L6 资产总览 / L7 账户详情（批2c · 原型 renderAssets / renderAcctDetail 口径） ----

/// 净资产三值（原型 renderAssets：资产=Σ正余额、负债=Σ|负余额|、净=资产−负债；
/// 仅非归档账户，余额取 balance_cache 跨账本合并 accBal 口径）。
({double assets, double liab, double net}) netWorthOf(Iterable<double> balances) {
  final assets = balances.where((v) => v > 0).fold<double>(0, (x, v) => x + v);
  final liab = balances.where((v) => v < 0).fold<double>(0, (x, v) => x - v);
  return (assets: assets, liab: liab, net: assets - liab);
}

/// 信用卡账期两值（原型 renderAcctDetail：以查看月出账日前一天为界，
/// 已出=上月出账日~本月前一天区间支出、未出=本月前一天~月末区间支出）。
/// [expenses] 为该账户 kind=expense 且 account_id=本账户 的流水（跨账本合并）。
({double billed, double unbilled}) creditBills({
  required List<LedgerTxn> expenses,
  required String finMonth,
  required int billDay,
}) {
  final prev = '$finMonth-${_p2(math.max(1, billDay - 1))}'; // 本期结束=出账日前一天
  final start = '${monthStep(finMonth, -1)}-${_p2(billDay)}'; // 上期出账日
  final end = '$finMonth-${_p2(monthDayCount(finMonth))}'; // 查看月末
  double sum(Iterable<LedgerTxn> ts) =>
      ts.fold<double>(0, (s, t) => s + t.amt);
  return (
    billed: sum(expenses.where(
        (t) => t.date.compareTo(start) >= 0 && t.date.compareTo(prev) <= 0)),
    unbilled: sum(expenses.where(
        (t) => t.date.compareTo(prev) > 0 && t.date.compareTo(end) <= 0)),
  );
}

// ---- L16 年度总结（批2a · 原型 renderYearly 口径） ----

/// 年度聚合值（渲染层只做排版，全部数值在此算好）。
class YearStat {
  const YearStat({
    required this.exp,
    required this.inc,
    required this.cnt,
    required this.actDays,
    this.big,
    required this.rank,
    required this.months,
  });

  final double exp;
  final double inc;

  /// expense/income 笔数（剔 nb）。
  final int cnt;

  /// 有支出流水的自然日数（记账 N 天）。
  final int actDays;

  /// 年度最大单笔（仅 expense）。
  final LedgerTxn? big;

  /// 大类支出排行（catStat 同口径）。
  final List<(int, double)> rank;

  /// 12 个月 exp/inc。
  final List<({int m, double exp, double inc})> months;

  double get avgDaily => exp / 365;
}

/// L16 年度聚合：按年份过滤当前账本流水后 mStat/catStat 同口径聚合。
YearStat yearStat(Iterable<LedgerTxn> all, String year) {
  final ys = all.where((t) => t.date.startsWith('$year-')).toList();
  final st = mStat(ys);
  final actDates = <String>{};
  LedgerTxn? big;
  for (final t in ys) {
    if (t.nb || t.kind != LedgerTxn.kExpense) continue;
    actDates.add(t.date);
    if (big == null || t.amt > big.amt) big = t;
  }
  final cnt = ys
      .where((t) =>
          !t.nb &&
          (t.kind == LedgerTxn.kExpense || t.kind == LedgerTxn.kIncome))
      .length;
  return YearStat(
    exp: st.exp,
    inc: st.inc,
    cnt: cnt,
    actDays: actDates.length,
    big: big,
    rank: catStat(ys),
    months: [
      for (var m = 1; m <= 12; m++)
        (() {
          final s = mStat(
              ys.where((t) => int.parse(t.date.substring(5, 7)) == m));
          return (m: m, exp: s.exp, inc: s.inc);
        })(),
    ],
  );
}

// ---- L9 周期账单（批2d · 原型 FREQS/freqNext/renderRecur 口径） ----

/// 周期频率目录（原型 FREQS 同序）：键/名。
const recurFreqs = <(String, String)>[
  ('day', '每天'),
  ('week', '每周'),
  ('month', '每月'),
  ('year', '每年'),
];

/// 频率名（原型 `FREQS.find(...)||['','每周']` 回落：未知键回「每周」）。
String recurFreqName(String f) =>
    recurFreqs.firstWhere((e) => e.$1 == f, orElse: () => ('week', '每周')).$2;

/// 周期 next 推进（原型 freqNext + 计划书 §4「生成即 next=freq+1周期，
/// 月频按同日号、月末截断」）：
/// - day +1 天 / week +7 天；
/// - month：次月同日号，次月天数不足截到月末（1/31 → 2/28，闰年 → 2/29）；
/// - year：次年同月同日，闰日 2/29 截到次年 2/28（日历语义；原型 JS 以
///   +365 天近似、跨闰漂移，按计划书「同日号截断」口径取日历正确实现）。
String recurNext(String date, String freq) {
  final d = parseDay(date);
  switch (freq) {
    case 'day':
      return dayKey(d.add(const Duration(days: 1)));
    case 'year':
      final ny = d.year + 1;
      final dim = DateTime(ny, d.month + 1, 0).day;
      return dayKey(DateTime(ny, d.month, d.day > dim ? dim : d.day));
    case 'month':
      final mth = monthStep(dayKey(d).substring(0, 7), 1);
      final dim = monthDayCount(mth);
      return '$mth-${(d.day > dim ? dim : d.day).toString().padLeft(2, '0')}';
    case 'week':
    default:
      return dayKey(d.add(const Duration(days: 7)));
  }
}

/// 距下次扣款天数（原型 `Math.round((next-TODAY)/864e5)`；≤0=已到期）。
int recurDaysLeft(String today, String next) =>
    parseDay(next).difference(parseDay(today)).inDays;
