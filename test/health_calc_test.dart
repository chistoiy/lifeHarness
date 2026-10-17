import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/health/domain/health_calc.dart';

/// 健康模块口径单测（批1）：《开发计划》§五 十一条逐条对上，期望值全部按公式现算。
/// 这些数字是需求口径的机器化落点——改公式必须同时改这里，别只改一边。
void main() {
  group('日期与时刻', () {
    test('dayKey 补零', () {
      expect(dayKey(DateTime(2026, 10, 7)), '2026-10-07');
      expect(dayKey(DateTime(2026, 1, 1)), '2026-01-01');
    });

    test('hhmmToMin 只认 HH:mm，非法一律 null（不猜成 0）', () {
      expect(hhmmToMin('7:05'), 425);
      expect(hhmmToMin('23:30'), 1410);
      expect(hhmmToMin('24:00'), isNull);
      expect(hhmmToMin('9:70'), isNull);
      expect(hhmmToMin('abc'), isNull);
      expect(hhmmToMin(null), isNull);
      expect(minToHhmm(1410), '23:30');
    });
  });

  group('睡眠（§五.2/§五.3）', () {
    test('跨天补 1440：23:00 睡 07:00 起＝480 分钟', () {
      expect(sleepDurationMin('23:00', '07:00'), 480);
      expect(sleepDurationMin('22:15', '06:45'), 510);
    });
    test('同刻视为整一天（≤0 一律 +1440，不出现 0 时长）', () {
      expect(sleepDurationMin('08:00', '08:00'), 1440);
    });
    test('按时入睡：界线前才算，凌晨入睡归昨夜算晚睡', () {
      expect(fellAsleepOnTime('23:00', '23:30'), isTrue);
      expect(fellAsleepOnTime('23:45', '23:30'), isFalse);
      expect(fellAsleepOnTime('00:20', '23:30'), isFalse);
    });
    test('分期四段与总时长差 >20min 才提示；全空＝未记录分期不提示', () {
      expect(stagesOffByMoreThan20(deep: 200, light: 200, rem: 60, awake: 30, totalMin: 480), isFalse);
      expect(stagesOffByMoreThan20(deep: 200, light: 200, rem: 60, awake: 30, totalMin: 440), isTrue);
      expect(stagesOffByMoreThan20(deep: null, light: null, rem: null, awake: null, totalMin: 480), isFalse);
    });
  });

  group('身体数据（§五.7）', () {
    test('BMI 现算并保留一位小数；缺身高不算（不拿 170 兜底）', () {
      expect(bmi(kg: 70, cm: 175), 22.9);
      expect(bmi(kg: 70, cm: null), isNull);
      expect(bmi(kg: null, cm: 175), isNull);
      expect(bmi(kg: 0, cm: 175), isNull);
    });
    test('分级边界：18.5/24/28 各自归位', () {
      expect(bmiLevel(18.4), '偏瘦');
      expect(bmiLevel(18.5), '正常');
      expect(bmiLevel(23.9), '正常');
      expect(bmiLevel(24), '超重');
      expect(bmiLevel(27.9), '超重');
      expect(bmiLevel(28), '肥胖');
    });
  });

  group('运动（§五.4/§五.5/§五.6/§五.9）', () {
    test('MET 表估 kcal；表外类型按「其他」5 算', () {
      expect(estKcal('跑步', 30), 315);
      expect(estKcal('瑜伽', 30), 102); // 30×3.4
      expect(estKcal('太极', 30), 150);
    });
    test('配速存秒/公里；无距离不算', () {
      expect(paceSecOf(distanceKm: 5, durationMin: 30), 360);
      expect(paceSecOf(distanceKm: 0, durationMin: 30), isNull);
      expect(paceSecOf(distanceKm: null, durationMin: 30), isNull);
      expect(paceLabel(360), '6′00″');
      expect(paceLabel(null), '—');
    });
    test('配速三种写法都吃：6\'00" / 6:00 / 600 都＝360 秒', () {
      expect(parsePaceSec('6\'00"'), 360);
      expect(parsePaceSec('6:00'), 360);
      expect(parsePaceSec('600'), 360);
      expect(parsePaceSec('1230'), 750); // 12 分 30 秒
      expect(parsePaceSec('6'), 360);
      expect(parsePaceSec(''), isNull);
    });
    test('三模互算：seg 决定算哪一项，另外两项照传', () {
      final byPace = deriveExercise(mode: 'pace', km: 5, min: 30);
      expect(byPace.paceSec, 360);
      final byDistance = deriveExercise(mode: 'distance', min: 30, paceSec: 360);
      expect(byDistance.km, 5.0);
      final byDuration = deriveExercise(mode: 'duration', km: 5, paceSec: 360);
      expect(byDuration.min, 30);
      // 算不出来的那一项保持 null，绝不留上一次的模式值
      expect(deriveExercise(mode: 'distance', min: 30, paceSec: null).km, isNull);
    });
    test('周次数＝时长 ≥10 分钟的条数（同日多条各计一次）', () {
      expect(sessionCount([5, 10, 30, 9]), 2);
      expect(sessionCount([]), 0);
    });
  });

  group('综合达标度（§五.1）', () {
    test('三项全满＝100；分量超目标封顶不溢出', () {
      expect(
          dailyScore(
              cups: 8, waterGoalCups: 8, sleepMin: 480, sleepGoalMin: 480, exerciseMin: 30),
          100);
      expect(
          dailyScore(
              cups: 16, waterGoalCups: 8, sleepMin: 600, sleepGoalMin: 480, exerciseMin: 30),
          100);
    });
    test('权重 40/35/25：只完成一半喝水＝20 分', () {
      expect(
          dailyScore(
              cups: 4, waterGoalCups: 8, sleepMin: 0, sleepGoalMin: 480, exerciseMin: 0),
          20);
    });
    test('运动是门槛制不是比例制：9 分钟＝0 分，10 分钟＝满分 25', () {
      expect(
          dailyScore(
              cups: 0, waterGoalCups: 8, sleepMin: 0, sleepGoalMin: 480, exerciseMin: 9),
          0);
      expect(
          dailyScore(
              cups: 0, waterGoalCups: 8, sleepMin: 0, sleepGoalMin: 480, exerciseMin: 10),
          25);
    });
    test('目标没设（分母 0）该分量记 0 分，不回落默认', () {
      expect(
          dailyScore(
              cups: 5, waterGoalCups: 0, sleepMin: 300, sleepGoalMin: 0, exerciseMin: 20),
          25);
    });
    test('分量得分单独可取（趋势四格用）', () {
      expect(partScore(got: 4, goal: 8), 50);
      expect(partScore(got: 9, goal: 8), 100);
      expect(partScore(got: 1, goal: 0), 0);
    });
  });

  group('用药（§五.8）', () {
    test('漏服＝时刻已过宽限期且既非已服也非跳过', () {
      expect(
          missedSlots(
              times: const ['08:00', '20:00'],
              loggedAt: const {'08:00': 'taken'},
              nowMin: 9 * 60,
              missedGraceMin: 30),
          0);
      expect(
          missedSlots(
              times: const ['08:00', '20:00'],
              loggedAt: const {},
              nowMin: 9 * 60,
              missedGraceMin: 30),
          1);
      // 宽限内不算漏：08:00 的药在 08:20 仍不算
      expect(
          missedSlots(
              times: const ['08:00'], loggedAt: const {}, nowMin: 8 * 60 + 20, missedGraceMin: 30),
          0);
      // 跳过＝有交代，不算漏
      expect(
          missedSlots(times: const ['08:00'],
              loggedAt: const {'08:00': 'skipped'}, nowMin: 12 * 60),
          0);
    });
    test('依从率＝已服/计划；无计划返回 null（UI 显「—」不显 0%）', () {
      expect(compliance(times: const ['08:00', '20:00'], loggedAt: const {'08:00': 'taken'}), 50);
      expect(compliance(times: const [], loggedAt: const {}), isNull);
    });
  });

  group('单位（§五.10：存储恒公制）', () {
    test('kg↔斤、km↔mile 往返不失真', () {
      expect(kgToDisplay(60, '斤'), 120);
      expect(displayToKg(120, '斤'), 60);
      expect(kgToDisplay(60, 'kg'), 60);
      expect(num1(kmToDisplay(5, 'mile')), '3.1');
      expect(num1(displayToKm(3.106855, 'mile')), '5.0');
    });
  });

  group('体征参考区间（§11.3.1/§11.3.2）', () {
    test('五类区间按内置常量判，越界才报；无值/未知类返回 null', () {
      expect(vitalLevel('bp', 145), 'high');
      expect(vitalLevel('bp', 120), 'normal');
      expect(vitalLevel('hr', 50), 'low');
      expect(vitalLevel('spo2', 94), 'low');
      expect(vitalLevel('glu', 5.0), 'normal');
      expect(vitalLevel('temp', 37.5), 'high');
      expect(vitalLevel('unknown-kind', 5), isNull);
      expect(vitalLevel('bp', null), isNull);
    });
    test('较基线带符号；无基线不编造', () {
      expect(vsBaseline(145, 139), '较基线 +6');
      expect(vsBaseline(133, 139), '较基线 -6');
      expect(vsBaseline(145, null), isNull);
    });
    test('疼痛三档：0-3 轻 / 4-6 中 / 7-10 重', () {
      expect(painLevel(0), '轻');
      expect(painLevel(3), '轻');
      expect(painLevel(4), '中');
      expect(painLevel(6), '中');
      expect(painLevel(7), '重');
    });
    test('区间缺口只数不造假（§五.11 正式版不补数据）', () {
      expect(missingDaysInRange(rangeDays: 30, daysWithData: 12), 18);
      expect(missingDaysInRange(rangeDays: 30, daysWithData: 40), 0);
    });
  });
}
