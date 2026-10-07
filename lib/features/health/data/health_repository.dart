import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema/health.dart' as h;
import '../../../core/logging/app_log.dart';
import '../domain/health_calc.dart';
import '../domain/health_models.dart';
import '../domain/health_vital.dart';

/// 健康模块数据层（仿 items/care 范式：一个仓储吃全部表，写库后由 providers 的 tick 触发重取）。
///
/// 三条硬口径在代码里钉住，别在调用侧补：
/// · **跨档案不聚合**——每个读口第一参数都是 profileId，SQL 必带 `profile_id=?`（V1.48.1 §11.1）；
/// · **派生不落库**——达标度/配速/依从率等一律读取侧算，本类只存原值（§2.2）；
/// · **删除档案＝连同该档案全部健康数据移除**（§11.3.8），「本人」不可删。
class HealthRepository {
  HealthRepository(this.db);

  final Database db;

  // ==================== 档案 ====================

  Future<List<HealthProfile>> profiles({bool includeArchived = false}) async {
    final rows = await db.query(h.tHealthProfile,
        where: includeArchived ? null : 'archived=0', orderBy: 'id ASC');
    return rows.map(HealthProfile.fromRow).toList();
  }

  /// 新增（id==0）或改名/改字段；「本人」那行只许改身高体重基线等字段，不许换人。
  Future<int> saveProfile(HealthProfile p) async {
    if (p.id == 0) {
      return db.insert(h.tHealthProfile, {
        ...p.toRow(),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
    await db.update(h.tHealthProfile, p.toRow(), where: 'id=?', whereArgs: [p.id]);
    return p.id;
  }

  /// 档案删除＝级联清掉该档案在 14 张表里的全部行（含打卡流水与报告子表）。
  /// 与「删除但保留记录」的回收站口径**不同**：健康档案是数据主体，删了就没了——
  /// 所以调用侧必须走二次确认，这里再落一条日志备查。
  Future<void> deleteProfile(int profileId) async {
    if (profileId == h.selfProfileId) {
      throw StateError('「本人」档案不可删');
    }
    await db.transaction((txn) async {
      // 先清「靠父表反查」的两张子表——父行一旦删掉，子行就成了查不到的孤儿（顺序即正确性）。
      await txn.rawDelete(
          'DELETE FROM ${h.tHealthDrugLog} WHERE drug_id IN (SELECT id FROM ${h.tHealthDrug} WHERE profile_id=?)',
          [profileId]);
      await txn.rawDelete(
          'DELETE FROM ${h.tHealthReportMetric} WHERE report_id IN (SELECT id FROM ${h.tHealthReport} WHERE profile_id=?)',
          [profileId]);
      for (final t in h.healthTables) {
        if (t == h.tHealthProfile || t == h.tHealthDrugLog || t == h.tHealthReportMetric) continue;
        await txn.delete(t, where: 'profile_id=?', whereArgs: [profileId]);
      }
      await txn.delete(h.tHealthProfile, where: 'id=?', whereArgs: [profileId]);
    });
    AppLog.addKey('健康档案删除：#$profileId 连同其全部健康数据已移除');
  }

  Future<List<ProfileTag>> tags(int profileId, String kind) async {
    final rows = await db.query(h.tHealthProfileTag,
        where: 'profile_id=? AND kind=?', whereArgs: [profileId, kind], orderBy: 'sort ASC, id ASC');
    return rows.map(ProfileTag.fromRow).toList();
  }

  Future<void> addTag(ProfileTag t) => db.insert(h.tHealthProfileTag, t.toRow());
  Future<void> deleteTag(int id) =>
      db.delete(h.tHealthProfileTag, where: 'id=?', whereArgs: [id]);

  // ==================== 喝水 ====================

  Future<int> cupsOf(int profileId, String date) async {
    final rows = await db.query(h.tHealthWater,
        where: 'profile_id=? AND date=?', whereArgs: [profileId, date], limit: 1);
    return rows.isEmpty ? 0 : (rows.first['cups'] as int? ?? 0);
  }

  /// 就地累加/回退（工作台「+1 杯 / 撤销」）：下限 0，不做二次确认。
  Future<int> bumpCups(int profileId, String date, int delta) async {
    final now = (await cupsOf(profileId, date)) + delta;
    final v = now < 0 ? 0 : now;
    await db.insert(h.tHealthWater,
        {'profile_id': profileId, 'date': date, 'cups': v, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        conflictAlgorithm: ConflictAlgorithm.replace);
    return v;
  }

  Future<List<WaterDay>> waterRange(int profileId, String from, String to) async {
    final rows = await db.query(h.tHealthWater,
        where: 'profile_id=? AND date>=? AND date<=?',
        whereArgs: [profileId, from, to],
        orderBy: 'date ASC');
    return rows.map(WaterDay.fromRow).toList();
  }

  // ==================== 睡眠 ====================

  /// 保存睡眠：`date`＝醒来日；时长在写入侧算一次（跨天 +1440 规则只在这里跑）。
  Future<int> saveSleep(SleepRecord s) {
    final row = s.toRow()
      ..['duration_min'] = sleepDurationMin(s.bedTime, s.wakeTime);
    if (s.id == null) {
      return db.insert(h.tHealthSleep,
          {...row, 'created_at': DateTime.now().millisecondsSinceEpoch});
    }
    return db
        .update(h.tHealthSleep, row, where: 'id=?', whereArgs: [s.id])
        .then((_) => s.id!);
  }

  Future<List<SleepRecord>> sleepRange(int profileId, String from, String to) async {
    final rows = await db.query(h.tHealthSleep,
        where: 'profile_id=? AND date>=? AND date<=?',
        whereArgs: [profileId, from, to],
        orderBy: 'date ASC');
    return rows.map(SleepRecord.fromRow).toList();
  }

  /// 「昨晚」＝归属日为今天的那条（醒来日口径）。
  Future<SleepRecord?> lastNight(int profileId, String today) async {
    final rows = await db.query(h.tHealthSleep,
        where: 'profile_id=? AND date<=?',
        whereArgs: [profileId, today],
        orderBy: 'date DESC',
        limit: 1);
    return rows.isEmpty ? null : SleepRecord.fromRow(rows.first);
  }

  Future<void> deleteSleep(int id) =>
      db.delete(h.tHealthSleep, where: 'id=?', whereArgs: [id]);

  // ==================== 运动 ====================

  /// 新增运动：kcal 留空按 MET 估；配速可由距离+时长算（用户填了以用户为准）。
  Future<int> addExercise(ExerciseRecord e) {
    final pace = e.paceSec ?? paceSecOf(distanceKm: e.distanceKm, durationMin: e.durationMin);
    final kcal = e.kcal ?? estKcal(e.type, e.durationMin);
    return db.insert(h.tHealthExercise, {
      'profile_id': e.profileId,
      'date': e.date,
      'type': e.type,
      'distance_km': e.distanceKm,
      'duration_min': e.durationMin,
      'pace_sec': pace,
      'kcal': kcal,
      'note': e.note,
      'source': e.source,
      'started_at': e.startedAt,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<ExerciseRecord>> exerciseRange(int profileId, String from, String to) async {
    final rows = await db.query(h.tHealthExercise,
        where: 'profile_id=? AND date>=? AND date<=?',
        whereArgs: [profileId, from, to],
        orderBy: 'date ASC, id ASC');
    return rows.map(ExerciseRecord.fromRow).toList();
  }

  Future<void> deleteExercise(int id) =>
      db.delete(h.tHealthExercise, where: 'id=?', whereArgs: [id]);

  // ==================== 身体数据 ====================

  /// 同日重记＝覆盖（(profile_id,date) 唯一索引 + replace）。
  Future<void> saveBody(BodyRecord b) => db.insert(
      h.tHealthBody,
      {...b.toRow(), 'created_at': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<BodyRecord>> bodyRange(int profileId, String from, String to) async {
    final rows = await db.query(h.tHealthBody,
        where: 'profile_id=? AND date>=? AND date<=?',
        whereArgs: [profileId, from, to],
        orderBy: 'date ASC');
    return rows.map(BodyRecord.fromRow).toList();
  }

  Future<BodyRecord?> latestBody(int profileId, String upto) async {
    final rows = await db.query(h.tHealthBody,
        where: 'profile_id=? AND date<=?', whereArgs: [profileId, upto],
        orderBy: 'date DESC', limit: 1);
    return rows.isEmpty ? null : BodyRecord.fromRow(rows.first);
  }

  /// 删除一条测量：**带 profile 归属**（跨档案删不到别人的行，与体征同一道闸）。
  Future<void> deleteBody(int profileId, int id) =>
      db.delete(h.tHealthBody, where: 'id=? AND profile_id=?', whereArgs: [id, profileId]);

  // ==================== 体征（批2.5） ====================

  /// 保存一次测量：`id==null` 新增，否则按 id 覆盖原行（流水点行就地改）。
  Future<int> saveVital(HealthVital v) {
    final row = v.toRow();
    if (v.id == null) {
      return db.insert(h.tHealthVital,
          {...row, 'created_at': DateTime.now().millisecondsSinceEpoch});
    }
    return db
        .update(h.tHealthVital, row, where: 'id=?', whereArgs: [v.id])
        .then((_) => v.id!);
  }

  /// 窗口内读数（升序＝日期+时刻；`kind` 为空＝五类一起取，页面四处共用同一份）。
  /// `profile_id=?` 是本模块每个读口的第一道 where（§11.1 跨档案不聚合），别在这里"顺手"放宽。
  Future<List<HealthVital>> vitals(int profileId, String from, String to, {String? kind}) async {
    final rows = await db.query(
      h.tHealthVital,
      where: kind == null
          ? 'profile_id=? AND date>=? AND date<=?'
          : 'profile_id=? AND kind=? AND date>=? AND date<=?',
      whereArgs: kind == null ? [profileId, from, to] : [profileId, kind, from, to],
      orderBy: 'date ASC, time ASC, id ASC',
    );
    return rows.map(HealthVital.fromRow).toList();
  }

  /// 工作台体征条：五类各取「最近一条」。**一次查询按序覆盖**，不留五路读数各自取数的错位。
  Future<Map<String, HealthVital?>> latestVitals(int profileId, String upto) async {
    final rows = await db.query(h.tHealthVital,
        where: 'profile_id=? AND date<=?',
        whereArgs: [profileId, upto],
        orderBy: 'date ASC, time ASC, id ASC');
    final last = <String, HealthVital>{};
    for (final r in rows) {
      final v = HealthVital.fromRow(r);
      last[v.kind] = v; // 升序遍历，后写的盖住前一条——留下的即该类最近一次测量
    }
    return {for (final k in vitalOrder) k: last[k]};
  }

  Future<void> deleteVital(int id) =>
      db.delete(h.tHealthVital, where: 'id=?', whereArgs: [id]);

  // ==================== 用药 ====================

  Future<List<DrugPlan>> drugs(int profileId, {bool includeArchived = false}) async {
    final rows = await db.query(h.tHealthDrug,
        where: includeArchived ? 'profile_id=?' : 'profile_id=? AND archived=0',
        whereArgs: [profileId],
        orderBy: 'id ASC');
    return rows.map(DrugPlan.fromRow).toList();
  }

  Future<int> saveDrug(DrugPlan d) {
    if (d.id == null) {
      return db.insert(h.tHealthDrug,
          {...d.toRow(), 'created_at': DateTime.now().millisecondsSinceEpoch});
    }
    return db.update(h.tHealthDrug, d.toRow(), where: 'id=?', whereArgs: [d.id]).then((_) => d.id!);
  }

  /// 删除档案＝置 archived，**打卡流水保留**（历史依从率不因此失真）。
  Future<void> archiveDrug(int id) async {
    await db.update(h.tHealthDrug, {'archived': 1}, where: 'id=?', whereArgs: [id]);
    AppLog.addKey('用药档案归档：#$id 已停用 · 打卡流水保留');
  }

  /// 打卡：一个 (drug,date,time) 一行，重复打卡＝覆盖该时刻状态（点一下已服↔待服互切在调用侧算）。
  Future<void> logDrug(DrugLog l) => db.insert(h.tHealthDrugLog, {
        'profile_id': l.profileId,
        'drug_id': l.drugId,
        'date': l.date,
        'time': l.time,
        'state': l.state,
        'note': l.note,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> undoDrugLog(int drugId, String date, String time) => db.delete(
      h.tHealthDrugLog,
      where: 'drug_id=? AND date=? AND time=?',
      whereArgs: [drugId, date, time]);

  /// 当日全部打卡（按 drug_id 分组给 UI 判「已服/跳过」）。
  Future<Map<int, Map<String, String>>> drugLogs(int profileId, String date) async {
    final rows = await db.query(h.tHealthDrugLog,
        where: 'profile_id=? AND date=?', whereArgs: [profileId, date]);
    final out = <int, Map<String, String>>{};
    for (final r in rows) {
      out.putIfAbsent(r['drug_id'] as int, () => {})[r['time'] as String] = r['state'] as String;
    }
    return out;
  }

  // ==================== 目标 ====================

  Future<Map<String, double>> goals(int profileId) async {
    final rows = await db.query(h.tHealthGoal, where: 'profile_id=?', whereArgs: [profileId]);
    return {for (final r in rows) r['key'] as String: (r['value'] as num).toDouble()};
  }

  Future<void> setGoal(int profileId, String key, double value) => db.insert(h.tHealthGoal, {
        'profile_id': profileId,
        'key': key,
        'value': value,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  // ==================== 工作台快照 ====================

  /// 今日快照：喝水杯数 + 昨晚睡眠 + 今日运动 + 当前体重 + 今日用药计划与打卡。
  Future<HealthToday> today(int profileId, String date) async {
    final ex = await exerciseRange(profileId, date, date);
    final logs = await drugLogs(profileId, date);
    return HealthToday(
      profileId: profileId,
      date: date,
      cups: await cupsOf(profileId, date),
      lastNight: await lastNight(profileId, date),
      exercises: ex,
      latestBody: await latestBody(profileId, date),
      drugs: await drugs(profileId),
      drugLogs: logs,
    );
  }
}

/// 工作台一次取数快照（避免五张卡各读各的，出现「杯数新、运动旧」的错位）。
class HealthToday {
  const HealthToday({
    required this.profileId,
    required this.date,
    required this.cups,
    required this.lastNight,
    required this.exercises,
    required this.latestBody,
    required this.drugs,
    required this.drugLogs,
  });

  final int profileId;
  final String date;
  final int cups;
  final SleepRecord? lastNight;
  final List<ExerciseRecord> exercises;
  final BodyRecord? latestBody;
  final List<DrugPlan> drugs;

  /// drug_id → (HH:mm → taken/skipped)
  final Map<int, Map<String, String>> drugLogs;

  int get exerciseMin => exercises.fold(0, (a, e) => a + e.durationMin);
  int get exerciseCount => sessionCount(exercises.map((e) => e.durationMin).toList());
  double? get kg => latestBody?.kg;
  int get sleepMin => lastNight?.durationMin ?? 0;

  /// 达标度（§五.1）：分母取当日目标，目标由调用侧传（本快照不读设置，保持纯数据）。
  double score({required double waterGoalCups, required double sleepGoalHours}) => dailyScore(
        cups: cups,
        waterGoalCups: waterGoalCups,
        sleepMin: sleepMin,
        sleepGoalMin: sleepGoalHours * 60,
        exerciseMin: exerciseMin,
      );

  /// 今日计划时刻总数（各档案 times 之和）。
  int get plannedSlots => drugs.fold(0, (a, d) => a + d.times.length);
  int get takenSlots => drugs.fold(
      0, (a, d) => a + d.times.where((t) => slotTaken(drugLogs[d.id] ?? const {}, t)).length);
}
