/// C6（时间模块批1 · 冻结口径）：周视图与时间账本「自然周」同源——周起点=周日。
/// 与月历表头「日一二三四五六」同口径（`weekday % 7`：周日=0）。
/// 周视图禁用「选中日 ±3 滚动窗」（原实现口径作废）；账本『w』档与周视图共用本文件。
library;

/// 含 [d] 的自然周的起点（周日 00:00）。
DateTime weekStartOf(DateTime d) {
  final d0 = DateTime(d.year, d.month, d.day);
  return d0.subtract(Duration(days: d0.weekday % 7));
}

/// 含 [d] 的自然周 7 天（周日 → 周六）。
List<DateTime> naturalWeek(DateTime d) =>
    List.generate(7, (i) => weekStartOf(d).add(Duration(days: i)));
