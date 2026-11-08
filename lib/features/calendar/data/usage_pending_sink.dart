/// C06：采集 → 建议块 → 习惯「自动达成源待确认队列」的落点。
///
/// **只向既有 `habit_pend` 插待确认行，绝不写 `habit_entries`**：确认由习惯页
/// 既有「待确认打卡」弹层完成（`confirmPend` 才落流水），丢弃走 `ignorePend`。
/// 不改 schema、不做 DB 迁移、不碰习惯模块源码（架构守护 R1：features 间禁 import，
/// 故这里只依赖 `core/database` 的既有表与列，口径与 `HabitRepository` 同源）。
///
/// 与 `habit.autoMode` 无关：使用时长是**推断**出来的，C06 一律先入待确认队列，
/// 即使用户把其它自动源设为「直接打卡」也不直接落流水。
library;

import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/schema.dart';
import '../domain/usage_pending_plan.dart';
import '../domain/usage_segment.dart';
import 'usage_stats_source.dart';

/// 一次采集/入队的结果（`granted=false` 时 [message] 即「去授予」文案）。
class UsageIngestReport {
  const UsageIngestReport({
    required this.granted,
    required this.added,
    required this.suggestions,
    required this.message,
  });

  final bool granted;

  /// 本次实际新增的待确认行数（去重后）。
  final int added;

  /// 本次生成的建议块数（未去重前）。
  final int suggestions;

  final String message;

  bool get hasNew => added > 0;
}

/// 自动打卡总闸 KV 键（与 `HabitRepository.kvBool('habit.autoChk')` 同源）。
const String _kAutoCheckKey = 'habit.autoChk';

/// 读「可承接使用时长建议」的习惯：未删除 · 未归档 · 正向 · source_kinds 含来源。
///
/// 筛选谓词全在纯函数 [usagePendTargetOf]（可单测）；这里只负责取列。
Future<List<UsagePendTarget>> loadUsagePendTargets(
  Database db, {
  String src = kUsagePendSrc,
}) async {
  final rows = await db.query(
    DbSchema.tHabits,
    columns: <String>[
      'id',
      'name',
      'type',
      'source_kinds',
      'archived_at',
      'deleted_at',
    ],
  );
  final out = <UsagePendTarget>[];
  for (final r in rows) {
    final t = usagePendTargetOf(r, src: src);
    if (t != null) out.add(t);
  }
  return out;
}

/// 自动打卡总闸（settings KV；缺省开，与习惯仓库 `kvBool(..., true)` 同口径）。
Future<bool> loadAutoCheckEnabled(Database db) async {
  final rows = await db.query(
    DbSchema.tSettings,
    columns: <String>['value'],
    where: 'key = ?',
    whereArgs: <Object?>[_kAutoCheckKey],
    limit: 1,
  );
  if (rows.isEmpty) return true;
  final value = rows.first['value'];
  return value is String ? value == 'true' : true;
}

/// 已处理过的去重键（**三态全收**：pending/confirmed/ignored）。
///
/// 丢弃是持久语义：用户忽略过的建议同日不再复活。
Future<Set<String>> loadHandledPendKeys(Database db) async {
  final rows = await db.query(
    DbSchema.tHabitPend,
    columns: <String>['habit_id', 'day', 'src'],
  );
  final keys = <String>{};
  for (final r in rows) {
    final habitId = r['habit_id'];
    final day = r['day'];
    final src = r['src'];
    if (habitId is String && day is String && src is String) {
      keys.add('$habitId|$day|$src');
    }
  }
  return keys;
}

/// 建议块 → `habit_pend`（`src=日程事件`）。
///
/// 自动打卡关闭/无目标习惯/全部已处理时 `added=0`，[UsageIngestReport.message]
/// 给出可展示的原因；本函数不写 `habit_entries`（确认才落流水）。
Future<UsageIngestReport> enqueueUsagePends(
  Database db,
  List<UsageSuggestion> suggestions, {
  String src = kUsagePendSrc,
  bool? autoCheckEnabled,
}) async {
  final enabled = autoCheckEnabled ?? await loadAutoCheckEnabled(db);
  if (!enabled) {
    return UsageIngestReport(
      granted: true,
      added: 0,
      suggestions: suggestions.length,
      message: '自动打卡已关闭，建议未入队',
    );
  }

  final targets = await loadUsagePendTargets(db, src: src);
  if (targets.isEmpty) {
    return UsageIngestReport(
      granted: true,
      added: 0,
      suggestions: suggestions.length,
      message: '没有绑定「$src」自动达成源的习惯，建议未入队',
    );
  }
  final handled = await loadHandledPendKeys(db);
  final drafts = planUsagePends(
    targets,
    suggestions,
    src: src,
    existingKeys: handled,
  );
  final now = DateTime.now().millisecondsSinceEpoch;
  for (final d in drafts) {
    await db.insert(DbSchema.tHabitPend, <String, Object?>{
      'habit_id': d.habitId,
      'day': d.day,
      'src': d.src,
      'value': d.minutes,
      'created_at': now,
      'state': 'pending',
    });
  }
  return UsageIngestReport(
    granted: true,
    added: drafts.length,
    suggestions: suggestions.length,
    message: drafts.isEmpty
        ? '没有新的待确认建议（已入队或已处理过）'
        : '已加入待确认队列 ${drafts.length} 条',
  );
}

/// 采集入口：查权限 → 拉分段 → 清洗/跨天切分 → 建议块 → 入待确认队列。
///
/// 拒权时**只回文案**（[UsageIngestReport.granted] 为 false），不抛异常、
/// 不自动跳设置页、不重试；是否引导授权由调用方显式调 `openSettings`。
/// 数据库未就绪时同样只回文案（不崩）。
Future<UsageIngestReport> collectUsageIntoPending({
  required UsageStatsSource source,
  Database? db,
  DateTime? now,
  int daysBack = 1,
  Duration minDuration = kUsageMinDuration,
}) async {
  final at = now ?? DateTime.now();
  final today = DateTime(at.year, at.month, at.day);
  final span = daysBack.clamp(1, kUsageMaxQueryWindow.inDays).toInt();
  final from = today.subtract(Duration(days: span - 1));

  final result = await source.query(from: from, to: at);
  if (!result.granted) {
    return UsageIngestReport(
      granted: false,
      added: 0,
      suggestions: 0,
      message: result.message,
    );
  }

  final database = db ?? _defaultDatabase();
  if (database == null) {
    return const UsageIngestReport(
      granted: true,
      added: 0,
      suggestions: 0,
      message: '数据库尚未就绪，建议未入队',
    );
  }

  final cleaned = normalizeUsageSegments(
    result.segments,
    minDuration: minDuration,
  );
  final suggestions = buildUsageSuggestions(splitUsageByDay(cleaned));
  return enqueueUsagePends(database, suggestions);
}

Database? _defaultDatabase() =>
    AppDatabase.instance.isInitialized ? AppDatabase.instance.db : null;
