import 'todo.dart';

/// M0末B · 待办智能建议包（纯函数，可单测直接喂列表+固定时钟）。
///
/// 三条规则对齐高保真原型：
/// ① 失衡提醒（四象限视图底部 amber 卡：「重要不紧急」连续空置 ≥3 天）；
/// ② 临期升紧急建议（清单视图逾期卡下：q2 任务已逾期或 24h 内截止 → 一键升 q1）；
/// ③ 精力占比分级文案（仪表盘问候卡胶囊）。

/// 失衡提醒触发阈值（原型「已 3 天空置」）。
const kImbalanceThresholdDays = 3;

/// 「重要不紧急」(Q2) 连续空置天数；不适用时返回 null（不提醒）：
/// • Q2 仍有未完成且未放弃的任务；
/// • 待办列表整体为空（无数据不判断）。
///
/// 天数口径：以 Q2 最近一次完成（updated_at 由 setDone 刷新）为起点按自然日计；
/// 从未在 Q2 完成过任务时，退化为「自最早一条待办创建以来」（即整个使用周期空置）。
int? q2EmptyDays(List<Todo> todos, [DateTime? now]) {
  if (todos.isEmpty) return null;
  final t = now ?? DateTime.now();
  final active = todos
      .where((e) => e.quadrant == Quadrant.q2 && !e.done && !e.dropped)
      .isNotEmpty;
  if (active) return null;

  DateTime? base;
  for (final e in todos) {
    if (e.quadrant == Quadrant.q2 && e.done) {
      final at = e.updatedAt ?? e.createdAt;
      if (at != null && (base == null || at.isAfter(base))) base = at;
    }
  }
  if (base == null) {
    // 从未完成过 Q2：以最早创建时间为起点
    for (final e in todos) {
      final at = e.createdAt;
      if (at != null && (base == null || at.isBefore(base))) base = at;
    }
  }
  if (base == null) return null;
  final days = DateTime(t.year, t.month, t.day)
      .difference(DateTime(base.year, base.month, base.day))
      .inDays;
  return days < 0 ? 0 : days;
}

/// 临期升紧急候选：「重要不紧急」(Q2) 中未完成/未放弃，且已逾期或 24h 内到期。
/// 只有标记为「重要」的任务才值得升级；Q4 临期任务归入淘汰考量，不推荐。
List<Todo> escalateSuggestions(List<Todo> todos, [DateTime? now]) {
  final t = now ?? DateTime.now();
  final horizon = t.add(const Duration(hours: 24));
  return todos.where((e) {
    if (e.done || e.dropped || e.quadrant != Quadrant.q2) return false;
    final due = e.dueAt;
    return due != null && !due.isAfter(horizon);
  }).toList();
}

/// 仪表盘精力胶囊分级文案——**逐字对齐原型** `dashInsight` 三档
/// （index.html：≥60 状态不错 / ≥40 还能更聚焦 / 其余 紧急事偏多）。
/// 6110 实锤：曾扩写为长句（「试试把重心挪回重要的事」等）⇒ 胶囊行溢出 13px。
String energyCaption(int pct) {
  if (pct >= 60) return '，状态不错';
  if (pct >= 40) return '，还能更聚焦';
  return '，紧急事偏多';
}
