/// 周期推导纯函数（原型 cycleCells/saveCycleDay 预测口径的程序化落法）。
///
/// 规则（p-cycleCal 图例卡逐字对应）：
/// - 排卵日 = 预测下次月经前 14 天；易孕窗口 = 排卵前 5 天 ~ 排卵后 1 天；
/// - 实色 = 已记录；预测带（下次月经/排卵/易孕）由平均周期长度推导；
/// - 每次修改经期起始重新预测（旧预测存档由仓储落 care_cycle_pred 处理）。
library;

import 'care_models.dart';

/// 一次经期区间 [start, len]（len 含起始日；至少 1 天）。
typedef PeriodRun = ({DateTime start, int len});

/// 周期日状态 → 经期区间列表：p1 开新段；紧随其后的 p/s 段并入当前段。
/// （p 与 p1 之间断档 ≤1 天视为连续，超出即闭合当前段。）
List<PeriodRun> periodRuns(Map<String, CycleDay> days) {
  final keys = days.keys.where((d) {
    final s = days[d]!.state;
    return s == 'p1' || s == 'p';
  }).toList()
    ..sort();
  final out = <PeriodRun>[];
  DateTime? curStart;
  DateTime? curEnd;
  for (final k in keys) {
    final d = DateTime.parse(k);
    final s = curStart, e = curEnd;
    if (s == null || d.difference(e!).inDays > 1) {
      if (s != null) {
        out.add((start: s, len: e!.difference(s).inDays + 1));
      }
      curStart = d;
      curEnd = d;
    } else if (d.isAfter(e)) {
      curEnd = d;
    }
  }
  if (curStart != null) {
    out.add((start: curStart, len: (curEnd!.difference(curStart).inDays + 1)));
  }
  return out;
}

/// 相邻经期起始的周期长度序列（天）。
List<int> cycleLengths(List<PeriodRun> runs) {
  final starts = runs.map((r) => r.start).toList()..sort();
  return [
    for (var i = 1; i < starts.length; i++)
      starts[i].difference(starts[i - 1]).inDays,
  ];
}

double? avgCycleLen(List<PeriodRun> runs) {
  final ls = cycleLengths(runs);
  if (ls.isEmpty) return null;
  return ls.reduce((a, b) => a + b) / ls.length;
}

double? avgPeriodLen(List<PeriodRun> runs) {
  if (runs.isEmpty) return null;
  return runs.map((r) => r.len).reduce((a, b) => a + b) / runs.length;
}

/// 规律度：周期长度标准差 ≤2=优，≤4=良，其余=波动（±N 天为展示副值）。
({String label, double std}) regularity(List<PeriodRun> runs) {
  final ls = cycleLengths(runs);
  if (ls.length < 2) return (label: '数据积累中', std: 0);
  final avg = ls.reduce((a, b) => a + b) / ls.length;
  final std =
      (ls.map((v) => (v - avg) * (v - avg)).reduce((a, b) => a + b) / ls.length);
  final s = _sqrt(std);
  return (label: s <= 2 ? '优' : s <= 4 ? '良' : '波动', std: s);
}

double _sqrt(double v) {
  if (v <= 0) return 0;
  var x = v;
  for (var i = 0; i < 24; i++) {
    x = (x + v / x) / 2;
  }
  return x;
}

/// 当前周期状态（p-care hero）。
class CycleNow {
  const CycleNow({
    required this.cycleDay,
    required this.cycleLen,
    required this.nextStart,
    required this.ovDay,
    required this.fertileStart,
    required this.fertileEnd,
    required this.phase,
  });

  final int cycleDay; // 本周期第 N 天
  final int cycleLen; // 采用长度（平均或 28 兜底）
  final DateTime nextStart;
  final DateTime? ovDay;
  final DateTime? fertileStart;
  final DateTime? fertileEnd;
  final String phase; // 月经期|易孕期|排卵期|黄体期|卵泡期

  int daysToNext(DateTime today) => nextStart.difference(today.withoutTimeCare()).inDays;
  int daysToOv(DateTime today) =>
      ovDay == null ? 0 : ovDay!.difference(today.withoutTimeCare()).inDays;
}

CycleNow? cycleNow(Map<String, CycleDay> days, DateTime today) {
  final runs = periodRuns(days);
  if (runs.isEmpty) return null;
  final last = runs.last;
  final len = (avgCycleLen(runs) ?? 28).round();
  final t = today.withoutTimeCare();
  final cd = t.difference(last.start).inDays + 1;
  if (cd <= 0) return null; // 起始在未来：不展示进行中
  final next = last.start.add(Duration(days: len));
  final ov = next.subtract(const Duration(days: 14));
  final fs = ov.subtract(const Duration(days: 5));
  final fe = ov.add(const Duration(days: 1));
  String phase;
  final st = days[careDayKey(t)]?.state;
  if (st == 'p1' || st == 'p') {
    phase = '月经期';
  } else if (!t.isBefore(fs) && !t.isAfter(fe)) {
    phase = t == ov ? '排卵期' : '易孕期';
  } else if (t.isAfter(fe)) {
    phase = '黄体期';
  } else {
    phase = '卵泡期';
  }
  return CycleNow(
    cycleDay: cd,
    cycleLen: len,
    nextStart: next,
    ovDay: ov,
    fertileStart: fs,
    fertileEnd: fe,
    phase: phase,
  );
}

/// 某天着色类别（日历渲染）：p=经期 o=排卵 f=易孕 s=点滴 null=普通。
/// 实色（已记录）优先于预测。
String? dayMarkKind(Map<String, CycleDay> days, CycleNow? now, DateTime d) {
  final st = days[careDayKey(d)]?.state;
  if (st == 'p1' || st == 'p') return 'p';
  if (st == 's') return 's';
  if (now == null) return null;
  if (now.ovDay != null && careDayKey(now.ovDay!) == careDayKey(d)) return 'o';
  if (now.fertileStart != null &&
      now.fertileEnd != null &&
      !d.isBefore(now.fertileStart!) &&
      !d.isAfter(now.fertileEnd!) &&
      careDayKey(d) != careDayKey(now.nextStart)) {
    return 'f';
  }
  if (careDayKey(d) == careDayKey(now.nextStart)) return 'p';
  return null;
}

/// 超 ±7 天异常波动检测（周期统计卡提示行）。
/// 基线用中位数，避免单次异常值自我掩盖（均值会被 37 天长周期拉偏）。
List<({int index, int len})> abnormalCycles(List<PeriodRun> runs) {
  final ls = cycleLengths(runs);
  if (ls.length < 3) return const [];
  final sorted = [...ls]..sort();
  final base = sorted.length.isOdd
      ? sorted[sorted.length ~/ 2].toDouble()
      : (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2;
  return [
    for (var i = 0; i < ls.length; i++)
      if ((ls[i] - base).abs() > 7) (index: i + 1, len: ls[i]),
  ];
}
