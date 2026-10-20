import 'package:sqflite/sqflite.dart';

import '../../../core/logging/app_log.dart';

import '../../../core/database/schema/core.dart' as core;
import '../../../core/database/schema/media.dart';
import '../domain/media_goal.dart';

import 'media_repository.dart';

/// 影音游目标与设置生效面的取数口（批8a · 工单 §⚙）。
extension MediaGoalRepo on MediaRepository {
  /// settings 表 `media.*` 整读（设置屏一次取回；表缺席等异常回落空份＝读侧默认兜底）。
  Future<Map<String, String>> kvAllMedia() async {
    try {
      final rows =
          await db.query(core.tSettings, where: "key LIKE 'media.%'");
      return {for (final r in rows) '${r['key']}': '${r['value']}'};
    } catch (e) {
      AppLog.add('影音设置 KV 整读失败（回落默认面）：$e', src: '数据库');
      return const {};
    }
  }

  /// `media_goals` 全行（一指标一行；未设＝无行）。
  Future<List<MediaGoal>> goalRows() async {
    final rows = await db.query(tMediaGoals, orderBy: 'id ASC');
    return rows.map(MediaGoal.fromRow).toList(growable: false);
  }

  /// 落目标（同指标覆盖写）。unit/updated_at 随行存真，读数与统计块同吃这一份。
  Future<void> setGoal(String metric, String unit, int target) => db.insert(
        tMediaGoals,
        {
          'metric': metric,
          'unit': unit,
          'target': target,
          'active': 1,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  /// 清档＝删行（屏上回虚线「设目标」，统计块同帧回「未设目标」）。
  Future<int> clearGoal(String metric) =>
      db.delete(tMediaGoals, where: 'metric = ?', whereArgs: [metric]);

  /// 本月名场面条数（scene 类在册笔记；软删不入＝LH-C22 铁口径⑥）。
  Future<int> sceneNotesBetween(DateTime from, DateTime to) async {
    final r = await db.rawQuery(
      'SELECT COUNT(*) c FROM $tMediaNotes '
      "WHERE note_type = 'scene' AND deleted_at IS NULL "
      'AND created_at >= ? AND created_at < ?',
      [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
    );
    return (r.first['c'] as num?)?.toInt() ?? 0;
  }

  /// 某日是否有已结算会话（dailyQ 晚间补记提示行的判定：今天没计过时才出）。
  Future<bool> hasSessionOnDay(DateTime day) async {
    final r = await db.rawQuery(
      'SELECT 1 FROM $tMediaSessions '
      'WHERE ended_at IS NOT NULL AND started_at >= ? AND started_at < ? LIMIT 1',
      [
        day.millisecondsSinceEpoch,
        day.add(const Duration(days: 1)).millisecondsSinceEpoch,
      ],
    );
    return r.isNotEmpty;
  }

  /// 条目最近一条已结算会话的终点分钟（autoPos 时间点预填＝原型 `ls[ls.length-1].p1`）。
  Future<int?> lastSessionToMin(String itemId) async {
    final rows = await db.query(
      tMediaSessions,
      where: 'item_id = ? AND ended_at IS NOT NULL',
      whereArgs: [itemId],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['to_min'] as num?)?.toInt();
  }

  /// 在册条目最早的 created_at（newPos=tail 落位基准＝最小值-1，原型「追加到末尾」同语义）。
  Future<int?> minLiveCreatedAt() async {
    final r = await db.rawQuery(
      'SELECT MIN(created_at) m FROM $tMediaItems WHERE deleted_at IS NULL',
    );
    final m = r.first['m'];
    return m == null ? null : (m as num).toInt();
  }
}
