import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../logging/app_log.dart';

/// AI token 用量台账（真机反馈 2026-09-26：想看 token 使用情况）。
///
/// 口径：
/// - 只记**真的发出去并拿到应答**的调用（三重门控拒绝、参数校验即退的零请求不入账）；
/// - 失败也计一次调用（`f`），但 tokens 只在端点回了 usage 时才有值——不编造；
/// - 按「日期 × 能力点」聚合存 SharedPreferences 单键 JSON，保留最近 [keepDays] 天，
///   整包备份随 prefs 一起走（换机即带走，不额外建表）。
class AiTokenStats {
  AiTokenStats._();

  static const String prefsKey = 'ai.tokenStats';

  /// 明细保留天数（超出按日期最旧整日丢弃，控制 prefs 体积）。
  static const int keepDays = 92;

  /// 单日单能力点的累计量。
  static const String fIn = 'in', fOut = 'out', fCalls = 'n', fFails = 'f', fMs = 'ms';

  /// 读全表：`{ '2026-09-26': { 'read.toc': {in,out,n,f,ms} } }`；脏数据整键弃用。
  static Map<String, Map<String, Map<String, int>>> load(SharedPreferences prefs) {
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, Map<String, Map<String, int>>>{};
      decoded.forEach((day, tasks) {
        if (tasks is! Map) return;
        final perTask = <String, Map<String, int>>{};
        tasks.forEach((task, v) {
          if (v is! Map) return;
          perTask['$task'] = {
            for (final k in [fIn, fOut, fCalls, fFails, fMs])
              k: (v[k] as num?)?.toInt() ?? 0,
          };
        });
        if (perTask.isNotEmpty) out['$day'] = perTask;
      });
      return out;
    } catch (e) {
      AppLog.add('AI 用量台账解码失败，本轮按空台账起算：$e',
          level: LhLevel.warn);
      return {};
    }
  }

  static String dayKey(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}'
      '-${t.day.toString().padLeft(2, '0')}';

  /// 记一次调用（成功或失败）。
  static Future<void> record(
    SharedPreferences prefs,
    String taskId, {
    int inTok = 0,
    int outTok = 0,
    int latencyMs = 0,
    bool failed = false,
    DateTime? at,
  }) async {
    final table = load(prefs);
    final day = table.putIfAbsent(dayKey(at ?? DateTime.now()), () => {});
    final cell = day.putIfAbsent(taskId, () => {
          fIn: 0,
          fOut: 0,
          fCalls: 0,
          fFails: 0,
          fMs: 0,
        });
    cell[fIn] = cell[fIn]! + inTok;
    cell[fOut] = cell[fOut]! + outTok;
    cell[fCalls] = cell[fCalls]! + 1;
    if (failed) cell[fFails] = cell[fFails]! + 1;
    cell[fMs] = cell[fMs]! + latencyMs;
    // 只留最近 keepDays 天（按日期串序即时间序）。
    if (table.length > keepDays) {
      final keys = table.keys.toList()..sort();
      for (final k in keys.take(keys.length - keepDays)) {
        table.remove(k);
      }
    }
    await prefs.setString(prefsKey, jsonEncode(table));
  }

  /// 抹掉全部用量明细（与「日志清理」分开的独立动作，二次确认由 UI 侧负责）。
  static Future<void> clear(SharedPreferences prefs) async {
    await prefs.remove(prefsKey);
  }

  /// 汇总若干天 → 按能力点合计（`{'read.toc': {in,out,n,f,ms}}`）。
  static Map<String, Map<String, int>> aggregate(
    Iterable<Map<String, Map<String, int>>> days,
  ) {
    final out = <String, Map<String, int>>{};
    for (final day in days) {
      day.forEach((task, cell) {
        final acc = out.putIfAbsent(
            task, () => {fIn: 0, fOut: 0, fCalls: 0, fFails: 0, fMs: 0});
        for (final k in [fIn, fOut, fCalls, fFails, fMs]) {
          acc[k] = acc[k]! + (cell[k] ?? 0);
        }
      });
    }
    return out;
  }

  /// 合计行的总量（入/出/次数/失败/平均耗时 ms）。
  static ({int inTok, int outTok, int calls, int fails, int avgMs}) total(
      Map<String, Map<String, int>> perTask) {
    var i = 0, o = 0, n = 0, f = 0, ms = 0;
    perTask.forEach((_, c) {
      i += c[fIn] ?? 0;
      o += c[fOut] ?? 0;
      n += c[fCalls] ?? 0;
      f += c[fFails] ?? 0;
      ms += c[fMs] ?? 0;
    });
    return (
      inTok: i,
      outTok: o,
      calls: n,
      fails: f,
      avgMs: n == 0 ? 0 : (ms / n).round(),
    );
  }
}
