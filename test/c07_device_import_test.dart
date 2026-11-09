import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/health/domain/health_device_import.dart';

/// C07 设备体征接入域层守护：Health Connect 四类样本 → 现有五类＋体征。
///
/// 五条口径＝产品单：来源标「设备导入」、同日同型去重（保留当天最后一条）、
/// 可撤销（只删本批键）、不回写设备、灰位未开放。每条正档 true 与负档 false
/// 同例都断。
void main() {
  test('① 体重 → BodyRecord：正档落 kg / 负档非法值跳过', () {
    final plan = mapDeviceSamples(
      const [
        DeviceSample(
          metric: DeviceMetric.weight,
          date: '2026-11-09',
          kg: 68.4,
          deviceId: 'scale-1',
        ),
        DeviceSample(metric: DeviceMetric.weight, date: '2026-11-09', kg: 0),
        DeviceSample(metric: DeviceMetric.weight, date: '2026-11-10'),
      ],
      profileId: 1,
    );

    expect(plan.entries, hasLength(1), reason: '正档：合法体重一条');
    final body = plan.entries.single.body;
    expect(body, isNotNull, reason: '正档：映射到 BodyRecord');
    expect(body!.kg, 68.4, reason: '正档：kg 原样');
    expect(body.date, '2026-11-09', reason: '正档：归属日');
    expect(body.profileId, 1, reason: '正档：跨档案不聚合');
    expect(plan.skipped, 2, reason: '负档：kg=0 与缺失各计一次跳过');
  });

  test('② 睡眠 → SleepRecord：正档时长/分期 / 负档无时长跳过', () {
    final plan = mapDeviceSamples(
      const [
        DeviceSample(
          metric: DeviceMetric.sleep,
          date: '2026-11-09',
          bedTime: '23:20',
          wakeTime: '07:05',
          durationMin: 465,
          deepMin: 92,
          remMin: 110,
        ),
        DeviceSample(metric: DeviceMetric.sleep, date: '2026-11-10'),
      ],
      profileId: 1,
    );

    expect(plan.entries, hasLength(1), reason: '正档：一条睡眠');
    final s = plan.entries.single.sleep!;
    expect(s.durationMin, 465, reason: '正档：时长');
    expect(s.bedTime, '23:20', reason: '正档：入睡时刻');
    expect(s.wakeTime, '07:05', reason: '正档：醒来时刻');
    expect(s.hasStages, isTrue, reason: '正档：设备给了分期');
    expect(s.deepMin, 92);
    expect(s.remMin, 110);
    expect(plan.skipped, 1, reason: '负档：无时长样本不进计划');
  });

  test('③ 运动 → ExerciseRecord：正档来源「设备导入」/ 负档类型与时长兜底', () {
    final plan = mapDeviceSamples(
      const [
        DeviceSample(
          metric: DeviceMetric.exercise,
          date: '2026-11-09',
          exerciseType: '跑步',
          durationMin: 32,
          distanceKm: 5.2,
          kcal: 310,
        ),
        DeviceSample(
          metric: DeviceMetric.exercise,
          date: '2026-11-09',
          exerciseType: '滑雪',
          durationMin: 40,
        ),
        DeviceSample(
          metric: DeviceMetric.exercise,
          date: '2026-11-09',
          exerciseType: '骑行',
          durationMin: 0,
        ),
      ],
      profileId: 1,
    );

    expect(plan.entries, hasLength(2), reason: '正档：两类有效运动');
    final run = plan.entries
        .map((e) => e.exercise!)
        .firstWhere((e) => e.type == '跑步');
    expect(run.source, '设备导入', reason: '正档：来源标记');
    expect(run.distanceKm, 5.2, reason: '正档：距离');
    expect(run.kcal, 310, reason: '正档：热量');
    final unknown = plan.entries
        .map((e) => e.exercise!)
        .firstWhere((e) => e.type == '其他');
    expect(unknown.distanceKm, isNull,
        reason: '负档：未知类型归「其他」，无距离');
    expect(plan.skipped, 1, reason: '负档：0 时长不落库');
  });

  test('④ 心率 → 体征 hr：正档 val/note / 负档越界跳过', () {
    final plan = mapDeviceSamples(
      const [
        DeviceSample(
          metric: DeviceMetric.heartRate,
          date: '2026-11-09',
          time: '09:30',
          bpm: 72,
        ),
        DeviceSample(
          metric: DeviceMetric.heartRate,
          date: '2026-11-09',
          bpm: 0,
        ),
        DeviceSample(
          metric: DeviceMetric.heartRate,
          date: '2026-11-09',
          bpm: 400,
        ),
      ],
      profileId: 1,
    );

    expect(plan.entries, hasLength(1), reason: '正档：一条心率');
    final v = plan.entries.single.vital!;
    expect(v.kind, 'hr', reason: '正档：并入现有体征心率');
    expect(v.val, 72, reason: '正档：读数');
    expect(v.time, '09:30', reason: '正档：测量时刻');
    expect(v.note, '设备导入', reason: '正档：无来源列的体征用备注留痕');
    expect(plan.skipped, 2, reason: '负档：0 与 400 都越界');
  });

  test('⑤ 同日同型去重：正档保留最后一条 / 负档跨日跨型不误删', () {
    final plan = mapDeviceSamples(
      const [
        DeviceSample(
            metric: DeviceMetric.weight, date: '2026-11-09', kg: 68.4),
        DeviceSample(
            metric: DeviceMetric.weight, date: '2026-11-09', kg: 68.1),
        DeviceSample(
            metric: DeviceMetric.weight, date: '2026-11-10', kg: 68.0),
        DeviceSample(
            metric: DeviceMetric.exercise,
            date: '2026-11-09',
            exerciseType: '跑步',
            durationMin: 30),
        DeviceSample(
            metric: DeviceMetric.exercise,
            date: '2026-11-09',
            exerciseType: '骑行',
            durationMin: 45),
      ],
      profileId: 1,
    );

    final weights = plan.entries.where((e) => e.metric == DeviceMetric.weight);
    expect(weights, hasLength(2), reason: '负档：不同日期各自保留');
    expect(
      weights.firstWhere((e) => e.body!.date == '2026-11-09').body!.kg,
      68.1,
      reason: '正档：同日保留最后一条（当天最新）',
    );
    expect(plan.entries.where((e) => e.metric == DeviceMetric.exercise),
        hasLength(2), reason: '负档：同日不同运动类型不去重');
    expect(plan.skipped, 1, reason: '正档：被覆盖的一条计入跳过');
    expect(plan.keys.toSet().length, plan.keys.length, reason: '负档：键集无重复');
  });

  test('⑥ 撤销与只读：正档只删本批键 / 负档不碰历史与设备', () {
    final plan = mapDeviceSamples(
      const [
        DeviceSample(
            metric: DeviceMetric.weight, date: '2026-11-09', kg: 68.4),
        DeviceSample(metric: DeviceMetric.heartRate, date: '2026-11-09', bpm: 72),
      ],
      profileId: 1,
    );
    const existing = <String>[
      '2026-11-09|weight',
      '2026-11-09|hr',
      '2026-11-08|weight',
    ];

    final left = undoDeviceImport<String>(existing, plan, (k) => k);
    expect(left, ['2026-11-08|weight'], reason: '正档：只删本批两条');
    expect(left.contains('2026-11-09|weight'), isFalse,
        reason: '负档：本批键必须清掉');
    expect(
      undoDeviceImport<String>(existing, const DeviceImportPlan(
        entries: <DeviceMapped>[],
        skipped: 0,
      ), (k) => k),
      existing,
      reason: '负档：空批次不动既有记录',
    );

    expect(plan.writesBack, isFalse, reason: '正档：计划声明不回写设备');
    expect(kDeviceImportWritesBack, isFalse, reason: '负档：常量锁死只读');
    expect(plan.source, '设备导入', reason: '正档：来源统一标注');
    expect(deviceImportAvailable, isFalse, reason: '负档：灰位未开放');
    expect(kDeviceImportAuthNote.contains('系统健康授权'), isTrue,
        reason: '正档：灰位文案写明授权前提');
  });
}
