/// C07 · 设备体征接入（Health Connect 只读）的域层映射与灰位口径。
///
/// 本轮**只落纯函数**：不引 `health` 包、不接系统授权、不发任何读取请求。
/// 四条口径写在最近处：
/// · **只读、不回写设备**——[kDeviceImportWritesBack] 恒 false，映射产物只进本地库；
/// · **来源标「设备导入」**——运动 `source` 列直接写 [kDeviceImportSource]；
///   身体/睡眠没有来源列，由 [DeviceImportPlan.source] 在预览与撤销提示里统一标注；
/// · **同日同型去重**——键＝`日期|类型`（运动再带运动类型）；同键保留**当天最后一条**，
///   其余计入 [DeviceImportPlan.skipped]（不静默丢，导入页要显示跳过数）；
/// · **可撤销**——[DeviceImportPlan.keys] 即本批写入键，[undoDeviceImport] 按这些键
///   从既有记录里剔除；撤销只删本批，不碰历史手录。
///
/// 灰位：[deviceImportAvailable] 恒 false，设置页只显示「需系统健康授权」的灰条，
/// 点击不生效（与运动来源「设备导入」灰位同一口径）。
library;

import 'health_ex.dart' show exTypes;
import 'health_models.dart';
import 'health_vital.dart';

/// 来源标记（运动 source 列与预览标注共用）。
const String kDeviceImportSource = '设备导入';

/// 需系统健康授权（Health Connect）才能真实读取。
const String kDeviceImportAuthNote = '需系统健康授权（Health Connect）';

/// 本轮不接真实读取：入口保持灰位。
const bool deviceImportAvailable = false;

/// 只读快照，绝不回写设备。
const bool kDeviceImportWritesBack = false;

/// 设备指标四类（映射到现有五类＋体征）。
enum DeviceMetric { weight, sleep, exercise, heartRate }

/// 一条来自设备的原始样本（由未来的授权适配层填充；本轮测试直接构造）。
class DeviceSample {
  const DeviceSample({
    required this.metric,
    required this.date,
    this.time = '',
    this.kg,
    this.durationMin,
    this.distanceKm,
    this.kcal,
    this.exerciseType,
    this.bedTime = '',
    this.wakeTime = '',
    this.bpm,
    this.deepMin,
    this.lightMin,
    this.remMin,
    this.awakeMin,
    this.deviceId = '',
  });

  final DeviceMetric metric;

  /// `yyyy-MM-dd`（与健康表同形，不做时区换算）。
  final String date;

  /// `HH:mm`（可空；心率/运动起始时刻用）。
  final String time;

  /// 体重 kg（[DeviceMetric.weight]）。
  final double? kg;

  /// 时长分钟（睡眠/运动）。
  final int? durationMin;
  final double? distanceKm;
  final int? kcal;

  /// 设备给的运动类型（不在 `exTypes` 内时归「其他」，不丢样本）。
  final String? exerciseType;

  /// 睡眠起止（`HH:mm`；设备没给就留空，不臆造时刻）。
  final String bedTime;
  final String wakeTime;

  /// 心率 次/分（[DeviceMetric.heartRate]）。
  final int? bpm;

  /// 睡眠分期（设备给才填）。
  final int? deepMin;
  final int? lightMin;
  final int? remMin;
  final int? awakeMin;

  /// 设备标识（仅本地留痕，不上传）。
  final String deviceId;
}

/// 一条映射产物：键 + 落库记录（四选一，按 metric 取）。
class DeviceMapped {
  const DeviceMapped({
    required this.key,
    required this.metric,
    this.body,
    this.sleep,
    this.exercise,
    this.vital,
  });

  final String key;
  final DeviceMetric metric;
  final BodyRecord? body;
  final SleepRecord? sleep;
  final ExerciseRecord? exercise;
  final HealthVital? vital;
}

/// 一批设备导入计划（预览/确认/撤销共用同一份键集）。
class DeviceImportPlan {
  const DeviceImportPlan({
    required this.entries,
    required this.skipped,
    this.source = kDeviceImportSource,
    this.writesBack = kDeviceImportWritesBack,
  });

  final List<DeviceMapped> entries;

  /// 同键被覆盖/非法被丢弃的样本数（导入页必须显示，不许静默）。
  final int skipped;
  final String source;
  final bool writesBack;

  bool get isEmpty => entries.isEmpty;
  int get count => entries.length;

  /// 本批写入键（撤销只认它）。
  List<String> get keys => List<String>.unmodifiable(
        entries.map((e) => e.key),
      );
}

/// 同日同型去重键（运动带类型；其余按日期 + 指标）。
String deviceDedupKey(DeviceSample s) => switch (s.metric) {
      DeviceMetric.weight => '${s.date}|weight',
      DeviceMetric.sleep => '${s.date}|sleep',
      DeviceMetric.heartRate => '${s.date}|hr',
      DeviceMetric.exercise => '${s.date}|exercise|${_exType(s)}',
    };

String _exType(DeviceSample s) {
  final t = (s.exerciseType ?? '').trim();
  return exTypes.contains(t) ? t : '其他';
}

/// 设备样本 → 现有五类＋体征（纯函数）。
///
/// 非法值（体重 ≤0、时长 ≤0、心率越界）直接跳过并计入 `skipped`；
/// 同键保留输入顺序里的最后一条（设备常按时间升序返回，最后＝当天最新）。
DeviceImportPlan mapDeviceSamples(
  List<DeviceSample> samples, {
  required int profileId,
}) {
  final byKey = <String, DeviceMapped>{};
  var skipped = 0;

  for (final s in samples) {
    final mapped = _mapOne(s, profileId);
    if (mapped == null) {
      skipped++;
      continue;
    }
    if (byKey.containsKey(mapped.key)) skipped++; // 同键覆盖：旧值算跳过
    byKey[mapped.key] = mapped;
  }

  return DeviceImportPlan(
    entries: List<DeviceMapped>.unmodifiable(byKey.values),
    skipped: skipped,
  );
}

DeviceMapped? _mapOne(DeviceSample s, int profileId) {
  switch (s.metric) {
    case DeviceMetric.weight:
      final kg = s.kg;
      if (kg == null || kg <= 0 || kg > 500) return null;
      return DeviceMapped(
        key: deviceDedupKey(s),
        metric: s.metric,
        body: BodyRecord(profileId: profileId, date: s.date, kg: kg),
      );
    case DeviceMetric.sleep:
      final min = s.durationMin;
      if (min == null || min <= 0) return null;
      return DeviceMapped(
        key: deviceDedupKey(s),
        metric: s.metric,
        sleep: SleepRecord(
          profileId: profileId,
          date: s.date,
          bedTime: s.bedTime,
          wakeTime: s.wakeTime,
          durationMin: min,
          deepMin: s.deepMin,
          lightMin: s.lightMin,
          remMin: s.remMin,
          awakeMin: s.awakeMin,
        ),
      );
    case DeviceMetric.exercise:
      final min = s.durationMin;
      if (min == null || min <= 0) return null;
      final type = _exType(s);
      final km = s.distanceKm;
      return DeviceMapped(
        key: deviceDedupKey(s),
        metric: s.metric,
        exercise: ExerciseRecord(
          profileId: profileId,
          date: s.date,
          type: type,
          distanceKm: (km != null && km > 0) ? km : null,
          durationMin: min,
          kcal: (s.kcal != null && s.kcal! > 0) ? s.kcal : null,
          source: kDeviceImportSource,
          startedAt: null,
        ),
      );
    case DeviceMetric.heartRate:
      final bpm = s.bpm;
      if (bpm == null || bpm < 20 || bpm > 250) return null;
      return DeviceMapped(
        key: deviceDedupKey(s),
        metric: s.metric,
        vital: HealthVital(
          profileId: profileId,
          date: s.date,
          time: s.time.isEmpty ? '00:00' : s.time,
          kind: 'hr',
          val: bpm.toDouble(),
          slot: '日间',
          note: kDeviceImportSource,
        ),
      );
    default:
      return null;
  }
}

/// 撤销本批：从既有记录里剔除 [plan] 的键，返回剩余（纯函数，不碰库）。
///
/// [keyOf] 由调用方给出「既有记录 → 去重键」的映射（例如
/// `(r) => '${r.date}|weight'`），与 [deviceDedupKey] 同式。
List<T> undoDeviceImport<T>(
  List<T> existing,
  DeviceImportPlan plan,
  String Function(T) keyOf,
) {
  if (plan.isEmpty) return List<T>.of(existing);
  final keys = plan.keys.toSet();
  return [
    for (final r in existing)
      if (!keys.contains(keyOf(r))) r,
  ];
}
