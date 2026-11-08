/// C06 自动时间采集 · 分段模型与聚合纯函数（单测友好 · 零 IO · 零 UI）。
///
/// 链路：原生 `UsageStatsManager` 原始分段 → [normalizeUsageSegments]（排序/合并/滤短）
/// → [splitUsageByDay]（跨天按日切分）→ [buildUsageSuggestions]（建议时间块）。
/// 建议块只进习惯模块的待确认队列，**不直接写库**（见 `usage_pending_plan.dart`）。
library;

/// 原始前台分段：`[start, end)`，由原生通道 `lh/usagestats` 回报。
class UsageSegment {
  const UsageSegment({
    required this.packageName,
    required this.label,
    required this.start,
    required this.end,
  });

  final String packageName;

  /// 应用显示名；原生取不到时回落为包名。
  final String label;

  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);

  int get minutes => duration.inMinutes;

  /// 有效＝包名非空且结束晚于开始（原生异常切片一律丢弃）。
  bool get isValid => packageName.isNotEmpty && end.isAfter(start);

  UsageSegment copyWith({DateTime? start, DateTime? end}) => UsageSegment(
    packageName: packageName,
    label: label,
    start: start ?? this.start,
    end: end ?? this.end,
  );

  @override
  String toString() =>
      'UsageSegment($packageName, ${start.toIso8601String()}, '
      '${end.toIso8601String()})';
}

/// 一次查询结果（含拒权/不支持的降级文案，调用方据此展示「去授予」）。
class UsageQueryResult {
  const UsageQueryResult({
    required this.granted,
    required this.message,
    this.segments = const <UsageSegment>[],
  });

  final bool granted;

  /// 空串＝正常；否则为可直接展示的人话（去授予/不支持/查询失败）。
  final String message;

  final List<UsageSegment> segments;

  bool get hasSegments => segments.isNotEmpty;

  /// 拒权降级文案（原生未授予「使用情况访问」时同文）。
  static const String deniedMessage =
      '未授予「使用情况访问」权限：请到 系统设置 › 特殊应用权限 › 使用情况访问 '
      '打开本应用，再回来重试';

  /// 平台无此能力（旧包/非 Android）：静默跳过，不引导授权。
  static const String unsupportedMessage = '当前设备不支持使用情况访问，已跳过自动采集';

  factory UsageQueryResult.denied([String message = deniedMessage]) =>
      UsageQueryResult(granted: false, message: message);

  factory UsageQueryResult.unsupported() =>
      const UsageQueryResult(granted: false, message: unsupportedMessage);

  /// 原生 Map → 结果。**任何脏数据都不抛**：缺字段/类型不符的切片直接跳过；
  /// `granted != true` 时清空分段（拒权残留不参与建议）。
  factory UsageQueryResult.fromNative(Object? raw) {
    if (raw is! Map) return UsageQueryResult.denied();
    final granted = raw['granted'] == true;
    final rawMessage = raw['message'];
    final message = rawMessage is String ? rawMessage : '';
    if (!granted) {
      return UsageQueryResult.denied(
        message.isEmpty ? deniedMessage : message,
      );
    }
    final out = <UsageSegment>[];
    final rawSegments = raw['segments'];
    if (rawSegments is List) {
      for (final item in rawSegments) {
        if (item is! Map) continue;
        final pkg = item['package'];
        final startMs = item['startMs'];
        final endMs = item['endMs'];
        if (pkg is! String || pkg.isEmpty) continue;
        if (startMs is! num || endMs is! num) continue;
        final start = DateTime.fromMillisecondsSinceEpoch(startMs.toInt());
        final end = DateTime.fromMillisecondsSinceEpoch(endMs.toInt());
        if (!end.isAfter(start)) continue;
        final rawLabel = item['label'];
        final label = rawLabel is String && rawLabel.isNotEmpty
            ? rawLabel
            : pkg;
        out.add(
          UsageSegment(
            packageName: pkg,
            label: label,
            start: start,
            end: end,
          ),
        );
      }
    }
    return UsageQueryResult(granted: true, message: message, segments: out);
  }
}

/// 单段最短时长：短于此的切屏（通知栏/来电/误触）不算建议块。
const Duration kUsageMinDuration = Duration(minutes: 2);

/// 同包相邻段合并容差：间隔不超过它视为同一次使用。
const Duration kUsageMergeGap = Duration(minutes: 1);

/// 排序 → 丢弃无效/排除包 → 同包相邻合并 → 滤掉过短段。
///
/// 只做单日无关的清洗；跨天切分交给 [splitUsageByDay]（顺序不可颠倒：
/// 先合并会把 23:50–00:10 的跨天段当成一段，再切分才不丢时间）。
List<UsageSegment> normalizeUsageSegments(
  List<UsageSegment> raw, {
  Duration minDuration = kUsageMinDuration,
  Duration mergeGap = kUsageMergeGap,
  Set<String> excludePackages = const <String>{},
}) {
  final sorted = <UsageSegment>[
    for (final s in raw)
      if (s.isValid && !excludePackages.contains(s.packageName)) s,
  ]..sort((a, b) => a.start.compareTo(b.start));

  final merged = <UsageSegment>[];
  for (final s in sorted) {
    if (merged.isEmpty) {
      merged.add(s);
      continue;
    }
    final last = merged.last;
    final gap = s.start.difference(last.end);
    if (last.packageName == s.packageName &&
        !gap.isNegative &&
        gap <= mergeGap) {
      merged[merged.length - 1] = last.copyWith(
        end: s.end.isAfter(last.end) ? s.end : last.end,
      );
    } else {
      merged.add(s);
    }
  }
  return <UsageSegment>[
    for (final s in merged)
      if (s.duration >= minDuration) s,
  ];
}

/// 跨天按**本地自然日**切分（D13 日界线 00:00）。
///
/// 例：23:30–次日 01:10 → 两段（23:30–00:00 / 00:00–01:10）。
/// 恰好止于 00:00 的段不产出零长度尾段（负档）。
List<UsageSegment> splitUsageByDay(List<UsageSegment> segments) {
  final out = <UsageSegment>[];
  for (final s in segments) {
    if (!s.isValid) continue;
    var start = s.start;
    while (start.isBefore(s.end)) {
      final nextDay = DateTime(start.year, start.month, start.day + 1);
      if (!s.end.isAfter(nextDay)) {
        out.add(s.copyWith(start: start, end: s.end));
        break;
      }
      out.add(s.copyWith(start: start, end: nextDay));
      start = nextDay;
    }
  }
  return out;
}

/// 建议时间块（一日内、分钟口径 0–1440；1440＝当日 24:00）。
class UsageSuggestion {
  const UsageSuggestion({
    required this.day,
    required this.packageName,
    required this.label,
    required this.startMin,
    required this.endMin,
  });

  /// 当日 00:00。
  final DateTime day;
  final String packageName;
  final String label;
  final int startMin;
  final int endMin;

  int get minutes => endMin - startMin;

  bool get isValid => minutes > 0 && startMin >= 0 && endMin <= 1440;
}

/// 已按日切分的分段 → 建议块（分钟数按当日零点起算，24:00 记 1440）。
List<UsageSuggestion> buildUsageSuggestions(
  List<UsageSegment> daySegments,
) {
  final out = <UsageSuggestion>[];
  for (final s in daySegments) {
    if (!s.isValid) continue;
    final day = DateTime(s.start.year, s.start.month, s.start.day);
    final startMin = s.start.difference(day).inMinutes.clamp(0, 1440).toInt();
    final endMin = s.end.difference(day).inMinutes.clamp(0, 1440).toInt();
    if (endMin <= startMin) continue;
    out.add(
      UsageSuggestion(
        day: day,
        packageName: s.packageName,
        label: s.label,
        startMin: startMin,
        endMin: endMin,
      ),
    );
  }
  return out;
}
