/// 呵护聚合纯函数（hero 三数据位 / 日汇总行 / 周柱共用口径）。
library;

import 'care_models.dart';

/// 喂养类事件（原型 HG 喂养组：亲喂/瓶喂/配方/辅食/吸奶/喝水）。
const Set<String> kFeedKinds = {
  'nurse', 'bmilk', 'formula', 'solids', 'pump', 'water'
};

/// hero 数据位 → 全天记录筛选组（heroStat(k) 同构）。
Set<String> careHeroSlotKinds(String group) => switch (group) {
      'feed' => kFeedKinds,
      'diaper' => const {'diaper'},
      'sleep' => const {'sleep'},
      _ => const {},
    };

/// 近 7 天窗口聚合（含今天）。
class CareWeekStats {
  const CareWeekStats({required this.feedN, required this.diaperN, required this.sleepAvgH});
  final int feedN;
  final int diaperN;
  final double sleepAvgH;
}

bool _in7(String day, DateTime today) {
  final d = DateTime.parse(day);
  return !d.isBefore(today.subtract(const Duration(days: 6))) && !d.isAfter(today);
}

CareWeekStats careWeekStats(List<CareRecord> logs, DateTime today) {
  var feed = 0, diaper = 0, sleepMin = 0;
  final daysWithSleep = <String>{};
  for (final r in logs) {
    if (!_in7(r.day, today)) continue;
    if (kFeedKinds.contains(r.k)) feed++;
    if (r.k == 'diaper') diaper++;
    if (r.k == 'sleep') {
      sleepMin += r.durOr0;
      daysWithSleep.add(r.day);
    }
  }
  return CareWeekStats(
    feedN: feed,
    diaperN: diaper,
    sleepAvgH: daysWithSleep.isEmpty ? 0 : sleepMin / 60 / 7,
  );
}

/// 全天记录某日的日汇总行文案（原型 sum 顺序：配方奶/瓶喂/母乳/辅食/吸奶/尿布/睡眠）。
List<String> careDaySummary(List<CareRecord> dayLogs) {
  Iterable<CareRecord> g(String k) => dayLogs.where((r) => r.k == k);
  double sumMl(Iterable<CareRecord> rs) => rs.fold(0, (a, r) => a + (r.ml ?? 0));
  int sumDur(Iterable<CareRecord> rs) => rs.fold(0, (a, r) => a + r.durOr0);
  double sumAmt(Iterable<CareRecord> rs) =>
      rs.fold(0, (a, r) => a + (double.tryParse(r.amt ?? '') ?? 0));
  final out = <String>[];
  final fm = g('formula'), bm = g('bmilk'), nu = g('nurse'), so = g('solids'),
      pu = g('pump'), dp = g('diaper'), sl = g('sleep');
  if (fm.isNotEmpty) out.add('配方奶 ${fm.length}次 ${_n(sumMl(fm))}ml');
  if (bm.isNotEmpty) out.add('瓶喂母乳 ${bm.length}次 ${_n(sumMl(bm))}ml');
  if (nu.isNotEmpty) out.add('母乳 ${nu.length}次 ${sumDur(nu)}min');
  if (so.isNotEmpty) out.add('辅食 ${so.length}次 ${_n(sumAmt(so))}g');
  if (pu.isNotEmpty) out.add('吸奶 ${pu.length}次 ${_n(sumMl(pu))}ml');
  if (dp.isNotEmpty) out.add('换尿布 ${dp.length}次');
  if (sl.isNotEmpty) out.add('睡眠 ${sl.length}段');
  return out;
}

String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

/// 原型 hms()：≥60 分钟折算 "1h30′/2h"，否则 "45min"。
String careHmsStr(int v) =>
    v >= 60 ? '${v ~/ 60}h${v % 60 > 0 ? '${v % 60}′' : ''}' : '${v}min';

/// 全天时间线行右侧内容串（原型 bdRow content 分支同构 · 红线 6 由数据生成）。
String careLogContent(CareRecord r) {
  if (r.k == 'diaper') {
    final t = r.dia == 'pee' ? '嘘嘘' : r.dia == 'mix' ? '臭臭+嘘嘘' : '臭臭';
    return r.dia != 'pee' ? '$t ${r.color ?? ''}、${r.tex ?? ''}' : t;
  }
  if (r.k == 'solids') {
    final nm = (r.name?.isNotEmpty ?? false) ? r.name! : '辅食';
    return (r.amt?.isNotEmpty ?? false) ? '$nm ${r.amt}g' : nm;
  }
  if ((r.ml ?? 0) > 0) return '${_n(r.ml!)}ml';
  if (r.k == 'supp') return r.name ?? '—';
  if (r.amt?.isNotEmpty ?? false) return '${r.amt}${r.unit ?? ''}';
  if (r.k == 'play' && (r.name?.isNotEmpty ?? false)) {
    return '${r.name} ${careHmsStr(r.durOr0)}';
  }
  if ((r.dur ?? 0) > 0) return careHmsStr(r.dur!);
  return '—';
}

/// bdRow 圆点色（喂养组粉 / 尿布橙 / 睡眠紫 / 其余灰）。
String careDotColor(String k) => kFeedKinds.contains(k)
    ? '#ec4899'
    : k == 'diaper'
        ? '#f59e0b'
        : k == 'sleep'
            ? '#8b5cf6'
            : '#94a3b8';

/// 展示起止区间的事件组（原型 showRange；时长>0 且有结束且不等起始才显示）。
const Set<String> kRangeShowKinds = {
  'nurse', 'bmilk', 'formula', 'bath', 'play', 'swim', 'sleep', 'pump'
};

bool careShowRange(CareRecord r) =>
    kRangeShowKinds.contains(r.k) && (r.dur ?? 0) > 0 && r.e != null && r.e != r.s;

/// 日分组标题（今天/昨天/前天，其余 MM-DD）。
String careDayLabel(String day, DateTime today) {
  final d = DateTime.parse(day);
  final diff = today.difference(DateTime(d.year, d.month, d.day)).inDays;
  return switch (diff) {
    0 => '今天',
    1 => '昨天',
    2 => '前天',
    _ => day.substring(5),
  };
}
