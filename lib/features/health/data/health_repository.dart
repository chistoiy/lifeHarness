import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema/health.dart' as h;
import '../../../core/logging/app_log.dart';
import '../domain/health_calc.dart';
import '../domain/health_export.dart';
import '../domain/health_models.dart';
import '../domain/health_report.dart';
import '../domain/health_trend.dart';
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

  /// 就地改一条运动流水：**按 id＋档案归属**双闸（同日可多条，故不是 UPSERT 而是 update）。
  /// 空列回落与 `addExercise` 同式——距离/配速算不出就写 null，kcal 用户没填按 MET 估。
  Future<int> updateExercise(ExerciseRecord e) async {
    final pace = e.paceSec ?? paceSecOf(distanceKm: e.distanceKm, durationMin: e.durationMin);
    final kcal = e.kcal ?? estKcal(e.type, e.durationMin);
    return db.update(
      h.tHealthExercise,
      {
        'date': e.date,
        'type': e.type,
        'distance_km': e.distanceKm,
        'duration_min': e.durationMin,
        'pace_sec': pace,
        'kcal': kcal,
        'note': e.note,
        'source': e.source,
        'started_at': e.startedAt,
      },
      where: 'id=? AND profile_id=?',
      whereArgs: [e.id, e.profileId],
    );
  }

  /// 删除一条运动：**带 profile 归属**（与体征/身体数据同一道闸，跨档案删不到别人的行）。
  Future<int> deleteExercise(int profileId, int id) =>
      db.delete(h.tHealthExercise, where: 'id=? AND profile_id=?', whereArgs: [id, profileId]);

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

  // ==================== 症状（批3.5a） ====================

  /// 记一条症状：**同日可多条**（表无唯一索引），所以只有 INSERT 与「按 id 的 UPDATE」两种写法，
  /// 不存在体征/身体数据那种同日覆盖——覆盖会把用户下午与夜里两次发作并成一条。
  Future<int> addSymptom(SymptomRecord s) => db.insert(h.tHealthSymptom, s.toRow());

  /// 某档案的全部症状（日期升序；页面自己按 `symListDesc` 倒排，仓储不替 UI 决定顺序）。
  Future<List<SymptomRecord>> symptoms(int profileId) async {
    final rows = await db.query(h.tHealthSymptom,
        where: 'profile_id=?', whereArgs: [profileId], orderBy: 'date ASC, id ASC');
    return rows.map(SymptomRecord.fromRow).toList();
  }

  /// 就地改一条症状：**按 id＋档案归属**双闸；`created_at` 用模型里的原值写回，
  /// 免得一次编辑把建档时间冲成现在（备份与「最近新增」都读这列）。
  Future<int> updateSymptom(SymptomRecord s) => db.update(
        h.tHealthSymptom,
        s.toRow(),
        where: 'id=? AND profile_id=?',
        whereArgs: [s.id, s.profileId],
      );

  /// 标记结束＝「ongoing 落下 且 持续 +15 分钟」两件事一次写完（原型 `syEnd` 是一处赋值，
  /// 拆成两次调用会让中途失败留下「已结束但时长没加」的半态）。
  Future<int> endSymptom(SymptomRecord s) => updateSymptom(s.ended());

  /// 删除一条症状：带 profile 归属（跨档案删不到别人的行），照片文件不在此处清——
  /// 附件回收属既有备份/清理服务的职责（批3.5 工单 §2「删除报告只清 DB 行」同一条口径）。
  Future<int> deleteSymptom(int profileId, int id) =>
      db.delete(h.tHealthSymptom, where: 'id=? AND profile_id=?', whereArgs: [id, profileId]);

  // ==================== 检查报告（批3.5b） ====================

  /// 建档一张报告（原型 `rpaSave`：一次只写元信息＋附件，检验项之后逐条 `addMetric`）。
  ///
  /// **没有改档出口**：原型里 `rpaOpen(idx)` 只有定义、没有调用点（`v2_js.js:387`），
  /// 也即报告建档后只能删除重传——按「不铺假入口」不替它补一个原型没有的编辑弹层（偏离登记工单 §3）。
  Future<int> addReport(HealthReport r) => db.insert(h.tHealthReport, r.toRow());

  /// 某档案的报告（日期升序；页面按 `rpDesc` 倒排，仓储不替 UI 决定顺序）。
  Future<List<HealthReport>> reports(int profileId) async {
    final rows = await db.query(h.tHealthReport,
        where: 'profile_id=?', whereArgs: [profileId], orderBy: 'date ASC, id ASC');
    return rows.map(HealthReport.fromRow).toList();
  }

  /// 报告＋它的检验项一次拼好（原型 `HP.reports[i].ms` 天生是一个对象里的数组，
  /// 页面若分两路取数，切档案时会出现「报告已换、检验项还是上一档案的」的错位帧）。
  Future<List<ReportBundle>> reportBundles(int profileId) async {
    final rs = await reports(profileId);
    if (rs.isEmpty) return const [];
    final rows = await db.query(
      h.tHealthReportMetric,
      where: 'report_id IN (${List.filled(rs.length, '?').join(',')})',
      whereArgs: [for (final r in rs) r.id],
      orderBy: 'report_id ASC, sort ASC, id ASC',
    );
    final by = <int, List<ReportMetric>>{};
    for (final row in rows) {
      final m = ReportMetric.fromRow(row);
      (by[m.reportId!] ??= []).add(m);
    }
    return [
      for (final r in rs)
        ReportBundle(report: r, metrics: by[r.id] ?? const <ReportMetric>[]),
    ];
  }

  /// 删除报告＝先按档案归属删父行，删到了才连带清它的检验项（一个事务，
  /// 不留「报告没了、检验项还在表里」的孤儿行）。附件文件不在此处删——
  /// 回收归既有附件清理服务（批3.5 工单 §2）。
  Future<int> deleteReport(int profileId, int id) => db.transaction((txn) async {
        final n = await txn.delete(h.tHealthReport,
            where: 'id=? AND profile_id=?', whereArgs: [id, profileId]);
        if (n > 0) await txn.delete(h.tHealthReportMetric, where: 'report_id=?', whereArgs: [id]);
        return n;
      });

  // ==================== 检验项 ====================

  /// 加一项（原型 `hmkAdd` 的 `push`＝追加在尾）：`sort` 取该报告现有最大位次 +1，
  /// 回读按 `sort ASC` 才不会把新项插到中间去。
  Future<int> addMetric(ReportMetric m) async {
    final rows = await db.query(h.tHealthReportMetric,
        columns: ['MAX(sort) AS s'],
        where: 'report_id=?',
        whereArgs: [m.reportId],
        limit: 1);
    final next = ((rows.first['s'] as int? ?? -1) + 1);
    return db.insert(h.tHealthReportMetric, m.copyWith(sort: next).toRow());
  }

  Future<List<ReportMetric>> metrics(int reportId) async {
    final rows = await db.query(h.tHealthReportMetric,
        where: 'report_id=?', whereArgs: [reportId], orderBy: 'sort ASC, id ASC');
    return rows.map(ReportMetric.fromRow).toList();
  }

  /// 删一项（原型 `hmkList` 行末「删」钮）：按 id＋归属报告双闸，
  /// 别人的报告里的行改不到（reportId 由调用侧从当前档案的bundle 拿）。
  Future<int> deleteMetric(int reportId, int id) => db.delete(h.tHealthReportMetric,
      where: 'id=? AND report_id=?', whereArgs: [id, reportId]);

  // ==================== 用药（批5） ====================

  Future<List<DrugPlan>> drugs(int profileId, {bool includeArchived = false}) async {
    final rows = await db.query(h.tHealthDrug,
        where: includeArchived ? 'profile_id=?' : 'profile_id=? AND archived=0',
        whereArgs: [profileId],
        orderBy: 'id ASC');
    return rows.map(DrugPlan.fromRow).toList();
  }

  /// 建档（`times` 由域层 `mdCleanTimes` 去过重排过序，这里只管落库）。
  Future<int> addDrug(DrugPlan d) => db.insert(h.tHealthDrug, {
        ...d.toRow(),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

  /// 改档：**按 id＋档案归属**双闸（跨档案改不到别人的药，同症状/体征一道闸）。
  Future<int> updateDrug(DrugPlan d) => db.update(
        h.tHealthDrug,
        d.toRow(),
        where: 'id=? AND profile_id=?',
        whereArgs: [d.id, d.profileId],
      );

  /// 删除档案＝置 archived，**打卡流水保留**（历史依从率不因此失真）。
  ///
  /// 只动父行的这一个标记位：不软删子树、不碰 `health_drug_log`——
  /// 「归档把历史一起藏了」是需求明令禁止的形态（工单 §2 偏离②，批6 趋势读侧带 `includeArchived`）。
  Future<int> archiveDrug(int profileId, int id) async {
    final n = await db.update(h.tHealthDrug, {'archived': 1},
        where: 'id=? AND profile_id=?', whereArgs: [id, profileId]);
    if (n > 0) AppLog.addKey('用药档案归档：#$id 已停用 · 打卡流水保留');
    return n;
  }

  /// 单药提醒开关（原型 `hDrugRem`）：带归属，跨档案改不到。
  Future<int> setDrugRemind(int profileId, int id, bool on) => db.update(
      h.tHealthDrug, {'remind': on ? 1 : 0},
      where: 'id=? AND profile_id=?', whereArgs: [id, profileId]);

  /// 「全部提醒」总开关（原型 `tgMedAll`）：**全量覆写**非归档行的 remind，
  /// 关掉再打开不记得单药原状态（工单 §2 偏离⑤）；归档档案不参与（它已经不在卡列表里）。
  Future<int> setAllDrugRemind(int profileId, bool on) => db.update(h.tHealthDrug,
      {'remind': on ? 1 : 0}, where: 'profile_id=? AND archived=0', whereArgs: [profileId]);

  /// 打卡：一个 (drug,date,time) 一行，重复打卡＝覆盖该时刻状态（唯一索引 `idx_hdruglog_slot`）。
  Future<void> logDrug(DrugLog l) => db.insert(h.tHealthDrugLog, {
        'profile_id': l.profileId,
        'drug_id': l.drugId,
        'date': l.date,
        'time': l.time,
        'state': l.state,
        'note': l.note,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  /// 撤销打卡＝删行（回到「待服」；留痕在 `created_at` 之外不补软删列，流水语义就是「现在算不算服过」）。
  Future<int> undoDrugLog(int profileId, int drugId, String date, String time) => db.delete(
      h.tHealthDrugLog,
      where: 'drug_id=? AND date=? AND time=? AND profile_id=?',
      whereArgs: [drugId, date, time, profileId]);

  /// 当日全部打卡（按 drug_id 分组给 UI 判「已服/跳过」）。
  Future<Map<int, Map<String, String>>> drugLogs(int profileId, String date) async {
    final rows = await db.query(h.tHealthDrugLog,
        where: 'profile_id=? AND date=?', whereArgs: [profileId, date]);
    return _groupByDrug(rows);
  }

  /// 日期区间的全部打卡（批5 近 7 天热力**一次取数**，不按天开七路查询——
  /// 七路查询会让七格来自七份快照，翻页时会出现「昨天那格和今天不一致」）。
  /// 返回 日期 →（drug_id →（时刻 → 状态）），归档档案的历史照样在里面（读侧不过滤，见 §2）。
  Future<Map<String, Map<int, Map<String, String>>>> drugLogRange(
      int profileId, String from, String to) async {
    final rows = await db.query(h.tHealthDrugLog,
        where: 'profile_id=? AND date>=? AND date<=?', whereArgs: [profileId, from, to]);
    final out = <String, Map<int, Map<String, String>>>{};
    for (final r in rows) {
      final byDrug = out.putIfAbsent(r['date'] as String, () => <int, Map<String, String>>{});
      byDrug
          .putIfAbsent(r['drug_id'] as int, () => <String, String>{})[r['time'] as String] =
          r['state'] as String;
    }
    return out;
  }

  static Map<int, Map<String, String>> _groupByDrug(List<Map<String, Object?>> rows) {
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

  // ==================== 趋势（批6a） ====================

  /// 趋势与周报的一次取数出口：`from..to` 之间**每个自然日都出一格**（没记录的日子整格 null，
  /// 热力画空格、曲线跳过该点——原型拿哈希补空槽的写法不照抄，§五.11「不造假数据」）。
  ///
  /// 六枚指标共用这一条流水：为每枚 chip 各开一路查询会让切 chip 时读数来自不同快照，
  /// 热力格与曲线就会出现「同一天两个值」。
  /// 用药侧的**计划分母含已归档档案**（`includeArchived: true`＝批5 工单 §2 偏离②的前置兑现），
  /// 但归档药只在自己当天有打卡流水时才计进分母，否则多年前的停用药会把历史依从率一直拖着。
  Future<List<TrDay>> trendDays(int profileId, String from, String to) async {
    final water = await waterRange(profileId, from, to);
    final sleep = await sleepRange(profileId, from, to);
    final ex = await exerciseRange(profileId, from, to);
    final body = await bodyRange(profileId, from, to);
    final drugs = await this.drugs(profileId, includeArchived: true);
    final logs = await drugLogRange(profileId, from, to);

    final cups = {for (final w in water) w.date: w.cups};
    // 同日多条睡眠：按 date ASC 取最后写入的那条（与原型 `find(x=>x.d===d)` 的「一条为准」同形）。
    final sleepMin = <String, int>{};
    for (final s in sleep) {
      sleepMin[s.date] = s.durationMin;
    }
    final exMin = <String, int>{};
    final paces = <String, List<int>>{};
    for (final e in ex) {
      exMin[e.date] = (exMin[e.date] ?? 0) + e.durationMin;
      if (e.paceSec != null) (paces[e.date] ??= []).add(e.paceSec!);
    }
    final kg = {for (final b in body) if (b.kg != null) b.date: b.kg!};

    final planned = <String, int>{}, taken = <String, int>{};
    for (final d in drugs) {
      final n = d.times.length;
      if (n == 0) continue;
      logs.forEach((date, byDrug) {
        final st = byDrug[d.id!];
        if (st == null) return; // 该日无此药流水
        planned[date] = (planned[date] ?? 0) + n;
        for (final t in d.times) {
          if (st[t] == 'taken') taken[date] = (taken[date] ?? 0) + 1;
        }
      });
    }

    final out = <TrDay>[];
    var cursor = DateTime.parse(from);
    final end = DateTime.parse(to);
    while (!cursor.isAfter(end)) {
      final k = dayKey(cursor);
      final p = planned[k];
      out.add(TrDay(
        date: k,
        cups: cups[k],
        sleepMin: sleepMin[k],
        exMin: exMin[k],
        kg: kg[k],
        medPlanned: p,
        medTaken: p == null ? null : taken[k] ?? 0,
        paces: paces[k] ?? const <int>[],
      ));
      cursor = cursor.add(const Duration(days: 1));
    }
    return out;
  }

  // ==================== 导出（批6b） ====================

  /// 健康流水导出取数：五类**一次取齐**后按日期升序合并（类型内序固定喝水·睡眠·运动·身体·用药，
  /// 同一天多类不至于每次导出换序——文件是要被人拿去对账的）。
  ///
  /// · 用药侧 `includeArchived: true` 且流水读侧不过滤＝归档档案的历史打卡照样进流水（批5 §2 偏离②）；
  /// · **写公制原值**：kg/km/分钟，屏上单位切换不参与导出（§五.10，同一列出现两种单位就没法再读）；
  /// · 只出「有行的日子」——导出不是热力格，缺记录日不占位、也不补 0。
  Future<List<HealthExportRow>> exportRows(int profileId, String from, String to) async {
    final water = await waterRange(profileId, from, to);
    final sleep = await sleepRange(profileId, from, to);
    final ex = await exerciseRange(profileId, from, to);
    final body = await bodyRange(profileId, from, to);
    final drugs = await this.drugs(profileId, includeArchived: true);
    final nameOf = {for (final d in drugs) d.id: d.name};
    final logRows = await db.query(h.tHealthDrugLog,
        where: 'profile_id=? AND date>=? AND date<=?',
        whereArgs: [profileId, from, to],
        orderBy: 'date ASC, time ASC');

    final out = <HealthExportRow>[
      for (final w in water)
        (date: w.date, kind: '喝水', value: '${w.cups} 杯', detail: '', note: ''),
      for (final s in sleep)
        (
          date: s.date,
          kind: '睡眠',
          value: '${s.durationMin} 分钟',
          detail: [
            '入睡 ${s.bedTime}',
            '醒 ${s.wakeTime}',
            if (s.deepMin != null || s.lightMin != null || s.remMin != null || s.awakeMin != null)
              '深${s.deepMin ?? 0} 浅${s.lightMin ?? 0} REM${s.remMin ?? 0} 醒${s.awakeMin ?? 0}',
          ].join(' · '),
          note: s.quality ?? '',
        ),
      for (final e in ex)
        (
          date: e.date,
          kind: '运动',
          value: '${e.durationMin} 分钟',
          detail: [
            e.type,
            if (e.distanceKm != null) '${e.distanceKm} km',
            if (e.paceSec != null) paceLabel(e.paceSec),
            if (e.kcal != null) '${e.kcal} kcal',
          ].join(' · '),
          note: e.note ?? '',
        ),
      for (final b in body)
        (
          date: b.date,
          kind: '身体',
          value: b.kg == null ? '—' : '${b.kg} kg',
          detail: [
            if (b.heightCm != null) '身高 ${b.heightCm} cm',
            if (b.fatPct != null) '体脂 ${b.fatPct} %',
            if (b.waistCm != null) '腰 ${b.waistCm}',
            if (b.hipCm != null) '臀 ${b.hipCm}',
            if (b.neckCm != null) '颈 ${b.neckCm}',
          ].join(' · '),
          note: '',
        ),
      for (final r in logRows)
        (
          date: r['date'] as String,
          kind: '用药',
          value: r['state'] == 'taken' ? '已服' : '跳过',
          detail: nameOf[r['drug_id'] as int] ?? '已删除档案',
          note: (r['note'] as String?) ?? '',
        ),
    ]..sort((a, b) {
        final d = a.date.compareTo(b.date);
        if (d != 0) return d;
        return exportKindOrder.indexOf(a.kind).compareTo(exportKindOrder.indexOf(b.kind));
      });
    return out;
  }

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
