/// C06：建议时间块 → 习惯模块「自动达成源待确认队列」的**纯规划**（零 IO）。
///
/// 铁律：本文件只产出待写入草稿，**不写库**。落库只经 `usage_pending_sink.dart`
/// 向既有 `habit_pend` 表插入待确认行；用户在习惯页既有「待确认打卡」弹层
/// 逐条确认后才由习惯仓库 `confirmPend` 落流水，丢弃走 `ignorePend`。
///
/// 为什么不用 `Habit` 模型：架构守护 R1 禁止 `features/calendar` import
/// `features/habit`（跨模块只经 shared/linkage，而本轮写区不含 linkage）。
/// 这里只保留规划所需的最小字段，来源字面量与习惯模块同源。
library;

import 'dart:convert';

import 'usage_segment.dart';

/// 自动达成源名称：沿用习惯模块既有枚举（`autoIngest`/`originForSrc` 同字面量），
/// 确认时自动映射为 `origin=auto-schedule`（不新增来源，不做 DB 迁移）。
const String kUsagePendSrc = '日程事件';

/// 习惯正向类型字面量（与 `Habit.kPos` 同源）。
const String _kPositiveType = 'pos';

/// 空 `source_kinds` 的默认来源（与 `Habit.fromRow` 同源）。
const String _kDefaultSource = '手动打卡';

/// 规划所需的最小习惯视图（id＋名）。
class UsagePendTarget {
  const UsagePendTarget({required this.id, required this.name});

  final String id;
  final String name;
}

/// `habits` 行 → 可承接使用时长建议的目标；不合格返回 null。
///
/// 与习惯仓库 `allHabits()`＋`habitSyncFromTitle` 的筛选口径一致：
/// 未删除 · 未归档 · 正向 · `source_kinds` 含 [src]。
/// 负向习惯不吃使用时长（使用某应用≠规避触发），组习惯不自动达成。
UsagePendTarget? usagePendTargetOf(
  Map<String, Object?> row, {
  String src = kUsagePendSrc,
}) {
  if (row['deleted_at'] != null || row['archived_at'] != null) return null;
  if (row['type'] != _kPositiveType) return null;
  final id = row['id'];
  final name = row['name'];
  if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
    return null;
  }
  if (!usageSourceKindsOf(row['source_kinds']).contains(src)) return null;
  return UsagePendTarget(id: id, name: name);
}

/// `source_kinds` JSON 列 → 来源名列表。
///
/// 空列回落默认「手动打卡」（与 `Habit.fromRow` 一致）；脏 JSON 视为未绑定，
/// 不让一条坏数据中断整批采集。
List<String> usageSourceKindsOf(Object? raw) {
  if (raw is! String || raw.isEmpty) return const <String>[_kDefaultSource];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return <String>[
        for (final x in decoded)
          if (x is String) x,
      ];
    }
  } catch (_) {
    // 脏 JSON：按未绑定处理。
  }
  return const <String>[];
}

/// 一条待确认草稿（同习惯+同日+同来源合并为一条，分钟数累加）。
class UsagePendDraft {
  const UsagePendDraft({
    required this.habitId,
    required this.habitName,
    required this.day,
    required this.src,
    required this.minutes,
  });

  final String habitId;
  final String habitName;

  /// 'YYYY-MM-DD'。
  final String day;
  final String src;
  final double minutes;

  String get dedupKey => '$habitId|$day|$src';
}

/// 生成待确认草稿。
///
/// - [existingKeys] 为**所有状态**（pending/confirmed/ignored）的 `habit|day|src`：
///   用户丢弃过的建议同日不再复活（逐条丢弃是持久语义）。
/// - 同批多条建议命中同一习惯同一天 → 合并一条并累加分钟（避免同日刷屏）。
List<UsagePendDraft> planUsagePends(
  List<UsagePendTarget> targets,
  List<UsageSuggestion> suggestions, {
  String src = kUsagePendSrc,
  Set<String> existingKeys = const <String>{},
}) {
  if (targets.isEmpty || suggestions.isEmpty) return const <UsagePendDraft>[];

  final acc = <String, UsagePendDraft>{};
  for (final s in suggestions) {
    if (!s.isValid) continue;
    final day = _dayKey(s.day);
    for (final t in targets) {
      final key = '${t.id}|$day|$src';
      if (existingKeys.contains(key)) continue;
      final prev = acc[key];
      acc[key] = UsagePendDraft(
        habitId: t.id,
        habitName: t.name,
        day: day,
        src: src,
        minutes: (prev?.minutes ?? 0) + s.minutes.toDouble(),
      );
    }
  }
  return acc.values.toList(growable: false);
}

/// 'YYYY-MM-DD'（与习惯模块 `dayKey` 同口径 · D13 自然日）。
String _dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
