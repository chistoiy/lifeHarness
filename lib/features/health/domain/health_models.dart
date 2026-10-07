/// 健康模块领域模型（批0/批1 面：档案 + 五类按日记录 + 目标）。
/// 体征/症状/报告/提醒四类的模型随各自批次（批2.5/批3.5）落地，表结构已随 v37 一次建齐。
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

/// 目标键（§六）：缺键＝未设，读取侧回落默认，不写库。
class GoalKeys {
  static const water = 'water'; // 杯/日
  static const sleep = 'sleep'; // 小时/日
  static const weekEx = 'week_ex'; // 次/周
  static const weight = 'weight'; // kg
  static const waist = 'waist'; // cm
  static const hip = 'hip'; // cm
  static const neck = 'neck'; // cm
  static const all = [water, sleep, weekEx, weight, waist, hip, neck];
}

/// times / photos / files 三列的 JSON 编解码收在一处（脏数据不炸列表：解不出按空处理）。
List<String> jsonDecodeList(String raw) {
  final v = jsonDecode(raw);
  if (v is! List) return const [];
  return v.map((e) => e.toString()).toList();
}

String jsonEncodeList(List<String> xs) => jsonEncode(xs);
