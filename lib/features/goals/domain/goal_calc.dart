/// 目标周期体系与汇聚口径（V1.42 模块7：Q1~Q4 切换/归档只读/预建/复制清零）。
library;

import 'goal_models.dart';

/// 周期串工具。
class GoalPeriod {
  const GoalPeriod._();

  /// 年度目标桶（跨四季，展示归一年视角）。
  static const yearBucket = '年度目标';

  static String quarter(int year, int q) => '$year Q$q';

  static bool isQuarter(String p) => RegExp(r'^\d{4} Q[1-4]$').hasMatch(p);

  static int yearOf(String p) => int.parse(p.substring(0, 4));

  static int quarterOf(String p) => int.parse(p.substring(6));

  /// 当前周期（如 '2026 Q3'）。
  static String current(DateTime now) => quarter(now.year, (now.month - 1) ~/ 3 + 1);

  /// 当年四季列表（‹› 逐周期切换域）。
  static List<String> quartersOfYear(int year) =>
      [for (var q = 1; q <= 4; q++) quarter(year, q)];

  /// 周期起止（含首末日的 epoch ms 天边界）。
  static (DateTime, DateTime) range(String period, DateTime now) {
    if (isQuarter(period)) {
      final y = yearOf(period), q = quarterOf(period);
      final start = DateTime(y, (q - 1) * 3 + 1);
      final end = DateTime(y, q * 3 + 1); // 次季首日（排他）
      return (start, end);
    }
    // 年度目标桶：按当前年（展示口径跨周期总览，实算窗取整年）
    final y = period == yearBucket ? now.year : yearOf(period);
    return (DateTime(y), DateTime(y + 1));
  }

  /// 下一季（Try→下季草稿 / 复制清零目标周期）。
  static String nextQuarter(String period, DateTime now) {
    if (!isQuarter(period)) return current(now);
    final y = yearOf(period), q = quarterOf(period);
    return q == 4 ? quarter(y + 1, 1) : quarter(y, q + 1);
  }

  /// 上一季（复制上期目标回退找有内容的周期用）。
  static String prevQuarter(String period) {
    if (!isQuarter(period)) return period;
    final y = yearOf(period), q = quarterOf(period);
    return q == 1 ? quarter(y - 1, 4) : quarter(y, q - 1);
  }

  /// 周期状态标签（原型 perState：已归档只读 / 进行中 / 未开始·可预建 / 已结束）。
  static String stateLabel(String period, Set<String> archived, DateTime now) {
    if (archived.contains(period)) return '已归档 · 只读';
    if (!isQuarter(period)) return '年度 · 可编辑';
    final cur = current(now);
    if (period == cur) return '进行中';
    return period.compareTo(cur) > 0 ? '未开始 · 可预建' : '已结束 · 请归档';
  }
}

/// 归档周期保留的最终达成口径：以归档时点 KR cur 冻结展示（载入不再自动重算）。
bool shouldAggregate(KrSource src, bool periodArchived) =>
    src != KrSource.manual && !periodArchived;
