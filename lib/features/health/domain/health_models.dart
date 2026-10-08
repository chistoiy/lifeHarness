/// 健康模块领域模型（批0/批1 面：档案 + 五类按日记录 + 目标）。
/// 体征五类（`HealthVital` 及其规格表）随批2.5 落在同目录的 `health_vital.dart`；
/// 症状/报告/提醒三类的模型随各自批次（批3.5）落地，表结构已随 v37 一次建齐。
///
/// 约定：
/// · `date` 一律 `yyyy-MM-dd` 字符串、时刻一律 `HH:mm`（与表内列同形，DAO 不做二次转换）；
/// · 数值列可空的就保持可空——「未记录」与「记录为 0」是两件事（UI 显「—」不是显 0）；
/// · `profileId` 每条记录都带，跨档案不聚合（V1.48.1 §11.1）。
library;

import 'dart:convert';

String? _s(Object? v) => v == null ? null : v as String;
double? _d(Object? v) => v == null ? null : (v as num).toDouble();
int? _i(Object? v) => v == null ? null : (v as num).toInt();

/// 健康档案。「本人」(id=1) 不可删；`rel` 是关系称谓（本人/配偶/父/母/子…）。
class HealthProfile {
  const HealthProfile({
    required this.id,
    required this.name,
    required this.rel,
    this.sex = '',
    this.birth,
    this.heightCm,
    this.baseKg,
    this.restSys,
    this.restDia,
    this.restHr,
    this.note,
    this.archived = false,
  });

  final int id;
  final String name;
  final String rel;
  final String sex;
  final String? birth;
  final double? heightCm;
  final double? baseKg;

  /// 静息基线三值：可被「近 30 天中位数」覆盖（覆盖动作在批2.5，读的是本字段）。
  final int? restSys;
  final int? restDia;
  final int? restHr;
  final String? note;
  final bool archived;

  bool get isSelf => id == 1;

  factory HealthProfile.fromRow(Map<String, Object?> r) => HealthProfile(
        id: r['id'] as int,
        name: r['name'] as String,
        rel: _s(r['rel']) ?? '本人',
        sex: _s(r['sex']) ?? '',
        birth: _s(r['birth']),
        heightCm: _d(r['height_cm']),
        baseKg: _d(r['base_kg']),
        restSys: _i(r['rest_sys']),
        restDia: _i(r['rest_dia']),
        restHr: _i(r['rest_hr']),
        note: _s(r['note']),
        archived: (_i(r['archived']) ?? 0) == 1,
      );

  Map<String, Object?> toRow() => {
        'name': name,
        'rel': rel,
        'sex': sex,
        'birth': birth,
        'height_cm': heightCm,
        'base_kg': baseKg,
        'rest_sys': restSys,
        'rest_dia': restDia,
        'rest_hr': restHr,
        'note': note,
        'archived': archived ? 1 : 0,
      };

  HealthProfile copyWith({int? id, bool? archived}) => HealthProfile(
        id: id ?? this.id,
        name: name,
        rel: rel,
        sex: sex,
        birth: birth,
        heightCm: heightCm,
        baseKg: baseKg,
        restSys: restSys,
        restDia: restDia,
        restHr: restHr,
        note: note,
        archived: archived ?? this.archived,
      );
}

/// 档案标签三类：病史 hist / 过敏 allergy / 长期用药 lmeds（一行一条）。
class ProfileTag {
  const ProfileTag({required this.id, required this.profileId, required this.kind, required this.text, this.sort = 0});
  final int id;
  final int profileId;
  final String kind;
  final String text;
  final int sort;

  static const kinds = ['hist', 'allergy', 'lmeds'];

  factory ProfileTag.fromRow(Map<String, Object?> r) => ProfileTag(
        id: r['id'] as int,
        profileId: r['profile_id'] as int,
        kind: _s(r['kind']) ?? 'hist',
        text: _s(r['text']) ?? '',
        sort: _i(r['sort']) ?? 0,
      );

  Map<String, Object?> toRow() =>
      {'profile_id': profileId, 'kind': kind, 'text': text, 'sort': sort};
}

/// 喝水：一天一行，只存杯数（毫升数在展示层按 cupMl 换算）。
class WaterDay {
  const WaterDay({required this.profileId, required this.date, required this.cups});
  final int profileId;
  final String date;
  final int cups;

  factory WaterDay.fromRow(Map<String, Object?> r) => WaterDay(
        profileId: r['profile_id'] as int,
        date: r['date'] as String,
        cups: _i(r['cups']) ?? 0,
      );
}

/// 睡眠：`date`＝归属日＝醒来日；分期四列全 null＝未记录分期。
class SleepRecord {
  const SleepRecord({
    this.id,
    required this.profileId,
    required this.date,
    required this.bedTime,
    required this.wakeTime,
    required this.durationMin,
    this.quality,
    this.deepMin,
    this.lightMin,
    this.remMin,
    this.awakeMin,
  });

  final int? id;
  final int profileId;
  final String date;
  final String bedTime;
  final String wakeTime;
  final int durationMin;
  final String? quality;
  final int? deepMin;
  final int? lightMin;
  final int? remMin;
  final int? awakeMin;

  /// 分期是否录了（四列任一非空）。
  bool get hasStages => deepMin != null || lightMin != null || remMin != null || awakeMin != null;

  factory SleepRecord.fromRow(Map<String, Object?> r) => SleepRecord(
        id: _i(r['id']),
        profileId: r['profile_id'] as int,
        date: r['date'] as String,
        bedTime: r['bed_time'] as String,
        wakeTime: r['wake_time'] as String,
        durationMin: _i(r['duration_min']) ?? 0,
        quality: _s(r['quality']),
        deepMin: _i(r['deep_min']),
        lightMin: _i(r['light_min']),
        remMin: _i(r['rem_min']),
        awakeMin: _i(r['awake_min']),
      );

  Map<String, Object?> toRow() => {
        'profile_id': profileId,
        'date': date,
        'bed_time': bedTime,
        'wake_time': wakeTime,
        'duration_min': durationMin,
        'quality': quality,
        'deep_min': deepMin,
        'light_min': lightMin,
        'rem_min': remMin,
        'awake_min': awakeMin,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };
}

/// 运动：存储恒公制；`paceSec`/`kcal` 保存时算一次落库（用户可改，改后以存值为准）。
class ExerciseRecord {
  const ExerciseRecord({
    this.id,
    required this.profileId,
    required this.date,
    required this.type,
    this.distanceKm,
    required this.durationMin,
    this.paceSec,
    this.kcal,
    this.note,
    this.source = '手动',
    this.startedAt,
  });

  final int? id;
  final int profileId;
  final String date;
  final String type;
  final double? distanceKm;
  final int durationMin;
  final int? paceSec;
  final int? kcal;
  final String? note;
  final String source;
  final int? startedAt;

  bool get countsAsSession => durationMin >= 10; // §五.9 门槛

  factory ExerciseRecord.fromRow(Map<String, Object?> r) => ExerciseRecord(
        id: _i(r['id']),
        profileId: r['profile_id'] as int,
        date: r['date'] as String,
        type: r['type'] as String,
        distanceKm: _d(r['distance_km']),
        durationMin: _i(r['duration_min']) ?? 0,
        paceSec: _i(r['pace_sec']),
        kcal: _i(r['kcal']),
        note: _s(r['note']),
        source: _s(r['source']) ?? '手动',
        startedAt: _i(r['started_at']),
      );

  Map<String, Object?> toRow() => {
        'profile_id': profileId,
        'date': date,
        'type': type,
        'distance_km': distanceKm,
        'duration_min': durationMin,
        'pace_sec': paceSec,
        'kcal': kcal,
        'note': note,
        'source': source,
        'started_at': startedAt,
      };
}

/// 身体数据：同日重记＝覆盖（UPSERT）；`heightCm` 按行存快照，历史 BMI 不随身高改动漂移。
class BodyRecord {
  const BodyRecord({
    this.id,
    required this.profileId,
    required this.date,
    this.kg,
    this.heightCm,
    this.fatPct,
    this.waistCm,
    this.hipCm,
    this.neckCm,
  });

  final int? id;
  final int profileId;
  final String date;
  final double? kg;
  final double? heightCm;
  final double? fatPct;
  final double? waistCm;
  final double? hipCm;
  final double? neckCm;

  factory BodyRecord.fromRow(Map<String, Object?> r) => BodyRecord(
        id: _i(r['id']),
        profileId: r['profile_id'] as int,
        date: r['date'] as String,
        kg: _d(r['kg']),
        heightCm: _d(r['height_cm']),
        fatPct: _d(r['fat_pct']),
        waistCm: _d(r['waist_cm']),
        hipCm: _d(r['hip_cm']),
        neckCm: _d(r['neck_cm']),
      );

  Map<String, Object?> toRow() => {
        'profile_id': profileId,
        'date': date,
        'kg': kg,
        'height_cm': heightCm,
        'fat_pct': fatPct,
        'waist_cm': waistCm,
        'hip_cm': hipCm,
        'neck_cm': neckCm,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };
}

/// 用药档案：`times` 是 `HH:mm` 数组；删除＝置 archived，打卡流水保留。
class DrugPlan {
  const DrugPlan({
    this.id,
    required this.profileId,
    required this.name,
    this.spec,
    this.unit = '片',
    this.dose = 1,
    this.times = const [],
    this.remind = false,
    this.endDate,
    this.archived = false,
  });

  final int? id;
  final int profileId;
  final String name;
  final String? spec;
  final String unit;
  final double dose;
  final List<String> times;
  final bool remind;
  final String? endDate;
  final bool archived;

  factory DrugPlan.fromRow(Map<String, Object?> r) => DrugPlan(
        id: _i(r['id']),
        profileId: r['profile_id'] as int,
        name: r['name'] as String,
        spec: _s(r['spec']),
        unit: _s(r['unit']) ?? '片',
        dose: _d(r['dose']) ?? 1,
        times: (() {
          final raw = _s(r['times']);
          if (raw == null || raw.isEmpty) return const <String>[];
          try {
            return (jsonDecodeList(raw)).cast<String>();
          } catch (_) {
            // catch-ok: 脏 times 列按「无时刻」处理，不让一条坏数据炸掉整张用药列表（无网络、无副作用）。
            return const <String>[];
          }
        })(),
        remind: (_i(r['remind']) ?? 0) == 1,
        endDate: _s(r['end_date']),
        archived: (_i(r['archived']) ?? 0) == 1,
      );

  Map<String, Object?> toRow() => {
        'profile_id': profileId,
        'name': name,
        'spec': spec,
        'unit': unit,
        'dose': dose,
        'times': jsonEncodeList(times),
        'remind': remind ? 1 : 0,
        'end_date': endDate,
        'archived': archived ? 1 : 0,
      };
}

/// 用药打卡：state ∈ taken/skipped。
class DrugLog {
  const DrugLog({
    this.id,
    required this.profileId,
    required this.drugId,
    required this.date,
    required this.time,
    required this.state,
    this.note,
  });

  final int? id;
  final int profileId;
  final int drugId;
  final String date;
  final String time;
  final String state;
  final String? note;

  factory DrugLog.fromRow(Map<String, Object?> r) => DrugLog(
        id: _i(r['id']),
        profileId: r['profile_id'] as int,
        drugId: r['drug_id'] as int,
        date: r['date'] as String,
        time: r['time'] as String,
        state: r['state'] as String,
        note: _s(r['note']),
      );
}

/// 症状与不适（批3.5 · 原型 `p-symptom` / `sheetHSymptom`）：**同日可多条**，编辑按 id 更新（无唯一索引）。
///
/// 四条列面口径写在最近处：
/// · `parts` 存**全量**多选结果（库里以 `,` 连接）——原型只取 `parts[0]||'全身'`，实现按「全量存·全量显示·筛选按包含」，
///   空选择才落「全身」（偏离一条＝批3.5 工单 §2）；
/// · `photos` 是应用目录绝对路径的 JSON 数组（脏数据按空处理，同 [DrugPlan] 的 `times` 口径）；
/// · `trig` / `descTxt` 两个列名是 v37 DDL 刻意避开 SQL 关键词（`trigger`/`desc`），模型侧就叫 `trig`/`desc`；
/// · `level` 是疼痛 0~10 的整数档，`ongoing` 才决定它进不进「正在发作」卡。
class SymptomRecord {
  const SymptomRecord({
    this.id,
    required this.profileId,
    required this.date,
    this.time = '',
    required this.name,
    this.level = 0,
    this.parts = const [],
    this.durationMin,
    this.trig,
    this.relief,
    this.desc,
    this.ongoing = false,
    this.drugRelated = false,
    this.photos = const [],
    this.createdAt = 0,
  });

  final int? id;
  final int profileId;
  final String date;

  /// `HH:mm`，开始时刻（原型 `s.t`）。
  final String time;
  final String name;

  /// 疼痛 0~10。
  final int level;
  final List<String> parts;
  final int? durationMin;
  final String? trig;
  final String? relief;
  final String? desc;
  final bool ongoing;
  final bool drugRelated;
  final List<String> photos;
  final int createdAt;

  /// 主部位＝多选的第一枚（展示与「部位筛选」都按全量包含判，这里只给个兜底称谓）。
  String get primaryPart => parts.isEmpty ? '全身' : parts.first;

  factory SymptomRecord.fromRow(Map<String, Object?> r) => SymptomRecord(
        id: _i(r['id']),
        profileId: r['profile_id'] as int,
        date: r['date'] as String,
        time: _s(r['time']) ?? '',
        name: r['name'] as String,
        level: _i(r['level']) ?? 0,
        parts: _splitParts(r['parts']),
        durationMin: _i(r['duration_min']),
        trig: _s(r['trig']),
        relief: _s(r['relief']),
        desc: _s(r['desc_txt']),
        ongoing: (_i(r['ongoing']) ?? 0) == 1,
        drugRelated: (_i(r['drug_related']) ?? 0) == 1,
        photos: (() {
          final raw = _s(r['photos']);
          if (raw == null || raw.isEmpty) return const <String>[];
          try {
            return jsonDecodeList(raw);
          } catch (_) {
            // catch-ok: 坏 photos 列按「无图」处理，不让一条脏数据炸掉整张症状流水（无网络、无副作用）。
            return const <String>[];
          }
        })(),
        createdAt: _i(r['created_at']) ?? 0,
      );

  Map<String, Object?> toRow() => {
        'profile_id': profileId,
        'date': date,
        'time': time,
        'name': name,
        'level': level,
        'parts': parts.join(','),
        'duration_min': durationMin,
        'trig': trig,
        'relief': relief,
        'desc_txt': desc,
        'ongoing': ongoing ? 1 : 0,
        'drug_related': drugRelated ? 1 : 0,
        'photos': jsonEncodeList(photos),
        'created_at': createdAt == 0 ? DateTime.now().millisecondsSinceEpoch : createdAt,
      };

  /// 标记结束：发作位落下、持续时长 +15 分钟（原型 `syEnd` 原话「持续时长 +15 分钟」）。
  SymptomRecord ended() => copyWith(ongoing: false, durationMin: (durationMin ?? 0) + 15);

  SymptomRecord copyWith({
    int? id,
    String? date,
    String? time,
    String? name,
    int? level,
    List<String>? parts,
    int? durationMin,
    String? trig,
    String? relief,
    String? desc,
    bool? ongoing,
    bool? drugRelated,
    List<String>? photos,
  }) =>
      SymptomRecord(
        id: id ?? this.id,
        profileId: profileId,
        date: date ?? this.date,
        time: time ?? this.time,
        name: name ?? this.name,
        level: level ?? this.level,
        parts: parts ?? this.parts,
        durationMin: durationMin ?? this.durationMin,
        trig: trig ?? this.trig,
        relief: relief ?? this.relief,
        desc: desc ?? this.desc,
        ongoing: ongoing ?? this.ongoing,
        drugRelated: drugRelated ?? this.drugRelated,
        photos: photos ?? this.photos,
        createdAt: createdAt,
      );
}

List<String> _splitParts(Object? v) {
  final raw = v == null ? '' : v.toString();
  if (raw.trim().isEmpty) return const [];
  return [for (final p in raw.split(',')) if (p.trim().isNotEmpty) p.trim()];
}

/// 检查报告（批3.5b · 表 `health_report`）。
///
/// 三条口径写在最近处：
/// · **检验项不在本模型里**：原型 `rpaPrev` 原话「检验项需建档后逐条录入」，建档一次只写
///   元信息＋附件，检验项是 `ReportMetric` 另表另写（域层 `ReportBundle` 才把两者拼一起）；
/// · `files` 存 JSON 路径数组（图片与 PDF 同存 `note_images/`，不另造目录），
///   `kind` 记末次附件类型（'img'/'pdf'）——读数由 `files` 内容派生，`kind` 只作存储侧标注；
/// · `hospital` 空值落 '—'（原型 `rpaSave` 的 `||'—'`，无医院时卡片副注不至于断一句）。
class HealthReport {
  const HealthReport({
    this.id,
    required this.profileId,
    required this.date,
    required this.name,
    this.hospital,
    this.doctorAdvice,
    this.files = const [],
    this.kind = 'img',
    this.noteRef,
    this.createdAt = 0,
  });

  final int? id;
  final int profileId;

  /// `yyyy-MM-dd`（月份归档轴从这列取）。
  final String date;
  final String name;
  final String? hospital;
  final String? doctorAdvice;
  final List<String> files;

  /// 'img' | 'pdf'。
  final String kind;

  /// 双向链接的笔记 id（批7 共享面接线，本期只落列不写值）。
  final int? noteRef;
  final int createdAt;

  factory HealthReport.fromRow(Map<String, Object?> r) => HealthReport(
        id: _i(r['id']),
        profileId: r['profile_id'] as int,
        date: r['date'] as String,
        name: r['name'] as String,
        hospital: _s(r['hospital']),
        doctorAdvice: _s(r['doctor_advice']),
        files: (() {
          final raw = _s(r['files']);
          if (raw == null || raw.isEmpty) return const <String>[];
          try {
            return jsonDecodeList(raw);
          } catch (_) {
            // catch-ok: 坏 files 列按「无附件」处理，一条脏数据不该炸掉整张报告列表（无网络、无副作用）。
            return const <String>[];
          }
        })(),
        kind: _s(r['kind']) ?? 'img',
        noteRef: _i(r['note_ref']),
        createdAt: _i(r['created_at']) ?? 0,
      );

  Map<String, Object?> toRow() => {
        'profile_id': profileId,
        'date': date,
        'name': name,
        'hospital': hospital,
        'doctor_advice': doctorAdvice,
        'files': jsonEncodeList(files),
        'kind': kind,
        'note_ref': noteRef,
        'created_at': createdAt == 0 ? DateTime.now().millisecondsSinceEpoch : createdAt,
      };
}

/// 报告检验项（批3.5b · 表 `health_report_metric`）。
///
/// **不落状态列**：偏高/偏低按行内 `refLo`/`refHi` 实时算（v37 DDL 注释已定），
/// 判据在 `health_report.dart` 的 `hkFlagOf`，这里只存读数与参考范围。
class ReportMetric {
  const ReportMetric({
    this.id,
    this.reportId,
    required this.name,
    this.value,
    this.unit,
    this.refLo,
    this.refHi,
    this.sort = 0,
  });

  final int? id;
  final int? reportId;
  final String name;
  final double? value;
  final String? unit;
  final double? refLo;
  final double? refHi;

  /// 录入序（原型 `r.ms.push` 追加在尾）：同报告内按这列升序回读。
  final int sort;

  factory ReportMetric.fromRow(Map<String, Object?> r) => ReportMetric(
        id: _i(r['id']),
        reportId: _i(r['report_id']),
        name: r['name'] as String,
        value: _d(r['value']),
        unit: _s(r['unit']),
        refLo: _d(r['ref_lo']),
        refHi: _d(r['ref_hi']),
        sort: _i(r['sort']) ?? 0,
      );

  Map<String, Object?> toRow() => {
        'report_id': reportId,
        'name': name,
        'value': value,
        'unit': unit,
        'ref_lo': refLo,
        'ref_hi': refHi,
        'sort': sort,
      };

  /// 位次由仓储按「现有最大 +1」发（原型是数组 push），模型侧只提供换一位次的能力。
  ReportMetric copyWith({int? id, int? reportId, int? sort}) => ReportMetric(
      id: id ?? this.id,
      reportId: reportId ?? this.reportId,
      name: name,
      value: value,
      unit: unit,
      refLo: refLo,
      refHi: refHi,
      sort: sort ?? this.sort);
}

/// 目标键（计划 §六 键表原文）：缺键＝未设，读取侧回落默认，不写库。
///
/// 存储分治（批3 工单 §0）：`water`/`sleep`/`weekEx` 与按时入睡线的**现行读写口在 prefs**
/// （`HealthSettings`，工作台「每日目标」卡与达标环已在读），本表只装身体属性四键——
/// 身体目标属于档案，跟着档案走（跨档案不聚合）；`health_goal` 表本身仍是通用键值表。
class GoalKeys {
  static const water = 'water'; // 杯/日·prefs
  static const sleep = 'sleep'; // 小时/日·prefs
  static const weekEx = 'week_ex'; // 次/周·prefs
  static const weightGoal = 'weight_goal'; // kg·DB
  static const waistGoal = 'waist_goal'; // cm·DB
  static const hipGoal = 'hip_goal'; // cm·DB
  static const neckGoal = 'neck_goal'; // cm·DB
  static const all = [water, sleep, weekEx, weightGoal, waistGoal, hipGoal, neckGoal];
}

/// times / photos / files 三列的 JSON 编解码收在一处（脏数据不炸列表：解不出按空处理）。
List<String> jsonDecodeList(String raw) {
  final v = jsonDecode(raw);
  if (v is! List) return const [];
  return v.map((e) => e.toString()).toList();
}

String jsonEncodeList(List<String> xs) => jsonEncode(xs);
