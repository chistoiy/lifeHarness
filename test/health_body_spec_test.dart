import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/health/domain/health_body.dart';
import 'package:lifeharness/features/health/domain/health_calc.dart';
import 'package:lifeharness/features/health/domain/health_models.dart';

/// 健康批3 · 身体数据域层常驻用例（工单执行面板第 1、3 项）。
///
/// 盯四条会被改错的口径：
/// · **档表只有一份**（`BodyField`）：弹层四柱与流水摘要都从这里取，屏上抄第二份 35~120 就会漂移；
/// · **「—」＝不写入**：0 档读数必须是 null（刀2 靶：把 0 档当 0 写入 → 体脂凭空 8%）；
/// · **只画实测**：无记录的日子不出点（刀1 靶：照抄原型 `htKg()` 的趋势假值就会画出不存在的下降）；
/// · **缺身高 BMI 出「—」**：不拿 170 兜底，否则 BMI 长期是个假「正常」。
void main() {
  BodyRecord r(String date,
          {double? kg,
          double? h,
          double? fat,
          double? waist,
          double? hip,
          double? neck}) =>
      BodyRecord(
          profileId: 1,
          date: date,
          kg: kg,
          heightCm: h,
          fatPct: fat,
          waistCm: waist,
          hipCm: hip,
          neckCm: neck);

  group('选填柱档表（BodyField）', () {
    test('首位固定「—」＝不写入：valueAt(0)＝null、indexOf(null)＝0', () {
      for (final f in bodyOptionalFields) {
        expect(f.labels.first, '—', reason: '${f.col} 首档必须是「—」');
        expect(f.valueAt(0), isNull, reason: '「—」读出来必须是 null（刀2 靶：落成 0/最小档就造假值）');
        expect(f.indexOf(null), 0, reason: '${f.col} 未填要落回「—」，不能就近归到 8%');
      }
    });

    test('档表上界含末档（浮点累加 +1e-9 容差）', () {
      expect(bodyField('fat').values.last, 40, reason: '少一档就是 39.5，原型 hNums(8,40,0.5) 有 40');
      expect(bodyField('waist').values.last, 120);
      expect(bodyField('hip').values.first, 60);
      expect(bodyField('neck').labels.length, 48 - 28 + 2);
    });

    test('indexOf 就近归档后再 valueAt 往返一致', () {
      for (final f in bodyOptionalFields) {
        for (var i = 1; i < f.values.length; i += 7) {
          expect(f.indexOf(f.values[i]), i + 1, reason: '${f.col} 第 $i 档往返');
          expect(f.valueAt(f.indexOf(f.values[i])), f.values[i]);
        }
      }
    });

    test('越界读数夹在档内（不越界取负 index）', () {
      expect(bodyField('fat').valueAt(9999), bodyField('fat').values.last);
      expect(bodyField('fat').indexOf(100500), bodyField('fat').values.length);
    });

    test('bodyFieldValue 四列都取得到，未知列出 null', () {
      final rec = r('2026-09-18', fat: 18.5, waist: 76.0, hip: 93.0, neck: 36.0);
      expect(bodyFieldValue(rec, 'fat'), 18.5);
      expect(bodyFieldValue(rec, 'waist'), 76);
      expect(bodyFieldValue(rec, 'hip'), 93);
      expect(bodyFieldValue(rec, 'neck'), 36);
      expect(bodyFieldValue(rec, 'nope'), isNull);
      expect(bodyFieldValue(null, 'fat'), isNull);
    });
  });

  group('体重两柱／身高柱', () {
    test('kgAt＝整柱＋小数柱（35 起，0.1 一档）', () {
      expect(kgAt(0, 0), 35);
      expect(kgAt(33, 3), 68.3);
      expect(kgWholeLabels.length, 120 - 35 + 1);
      expect(kgDecLabels.length, 10);
    });

    test('往返：任何一档读出来的 kg 都能滚回同一双柱位', () {
      for (var w = 0; w < kgWholeLabels.length; w += 5) {
        for (var d = 0; d < 10; d++) {
          final kg = kgAt(w, d);
          expect(kgWholeIndexOf(kg), w, reason: '$kg 整柱');
          expect(kgDecIndexOf(kg), d, reason: '$kg 小数柱（floor 会少一档）');
        }
      }
    });

    test('身高柱 0＝「—」＝不改写；140~200 整档', () {
      expect(heightLabels.first, '—');
      expect(heightValueAt(0), isNull);
      expect(heightValueAt(1), 140);
      expect(heightValueAt(heightLabels.length - 1), 200);
      expect(heightIndexOf(null), 0);
      expect(heightIndexOf(172.0), 172 - 140 + 1);
    });

    test('越界体重夹进档（130 kg 不能顶出档表外）', () {
      expect(kgWholeIndexOf(130), 120 - 35);
      expect(kgAt(120 - 35, 0), 120);
    });
  });

  group('单位读数（§五.10：存储恒 kg，只影响展示）', () {
    test('斤＝×2，kg 档不动', () {
      expect(bodyKgTx(68.25, 'kg'), '68.3');
      expect(bodyKgTx(68.2, '斤'), '136.4');
    });

    test('变化量带符号并按单位换算；算不出＝「—」（原型此处出 NaN）', () {
      expect(bodyDeltaTx(1.2, 'kg'), '+1.2 kg');
      expect(bodyDeltaTx(-0.3, 'kg'), '-0.3 kg');
      expect(bodyDeltaTx(0.5, '斤'), '+1.0 斤');
      expect(bodyDeltaTx(null, '斤'), '—');
    });

    test('距目标恒按 kg（切单位不动它）', () {
      expect(bodyGoalTx(2.04), '2.0 kg');
      expect(bodyGoalTx(-1.5), '-1.5 kg');
      expect(bodyGoalTx(null), '—');
    });
  });

  group('曲线取样：只画实测（刀1 靶）', () {
    final today = '2026-09-19';
    final win = [r('2026-09-16', kg: 69.0), r('2026-09-18', kg: 68.5), r('2026-09-19', kg: 68.0)];

    test('x 按日期在窗口里的位置，不按点序（三条记录不铺满 365 天窗）', () {
      final pts = bodyCurve(win, days: 365, today: today);
      expect(pts.map((p) => p.dayOffset).toList(), [365 - 4, 365 - 2, 365 - 1]);
      expect(bodyCurve(win, days: 30, today: today).map((p) => p.dayOffset).toList(),
          [30 - 4, 30 - 2, 30 - 1]);
    });

    test('没有实测 kg 的日子不出点（无记录＝空槽，不插趋势假值）', () {
      final sparse = [r('2026-09-16', kg: 69.0), r('2026-09-17'), r('2026-09-19', kg: 68.0)];
      final pts = bodyCurve(sparse, days: 30, today: today);
      expect(pts.length, 2, reason: '09-17 那条没有体重读数，画点就是编数据');
      expect(pts.map((p) => p.date).toList(), ['2026-09-16', '2026-09-19']);
    });

    test('窗口切片＝days 个自然日含今天，端点闭区间', () {
      expect(bodyWindow(win, days: 30, today: today).length, 3);
      expect(bodyWindow([r('2026-08-01', kg: 70.0), ...win], days: 30, today: today).length, 3);
      expect(bodyWindow([r('2026-08-21', kg: 70.0), ...win], days: 30, today: today).length, 4,
          reason: '21 号在 30 天窗内（08-21~09-19 正好 30 天）');
    });

    test('轴端把目标线也算进去（目标线必须落在刻度内）', () {
      final pts = bodyCurve(win, days: 30, today: today);
      expect(bodyAxisLo(pts, 65.0), closeTo(64.6, 0.0001));
      expect(bodyAxisHi(pts, 65.0), closeTo(69.4, 0.0001));
      expect(bodyAxisLo(pts, null), closeTo(67.6, 0.0001));
      expect(bodyAxisHi(pts, 75.0), closeTo(75.4, 0.0001));
    });
  });

  group('三统计', () {
    test('周变化＝倒数第 8 条实测；不足 8 条算不出（出「—」不是 NaN）', () {
      final eight = [
        for (var i = 0; i < 8; i++) r('2026-09-${(1 + i).toString().padLeft(2, '0')}', kg: 70.0 - i)
      ];
      expect(bodyWeekBaseline(eight), 70, reason: '倒数第 8 条＝最早那条');
      expect(bodyWeekChange(eight), -7.0);
      expect(bodyWeekChange(eight.sublist(0, 7)), isNull);
      expect(bodyWeekBaseline(const []), isNull);
    });

    test('区间变化＝窗口首末之差，单点算不出', () {
      final w = [r('2026-09-16', kg: 69.0), r('2026-09-19', kg: 68.0)];
      expect(bodyRangeChange(w), -1.0);
      expect(bodyRangeChange([r('2026-09-19', kg: 68.0)]), isNull);
      expect(bodyRangeChange(w.sublist(1)), isNull);
    });

    test('距目标与最新读数（空序列全出 null）', () {
      final asc = [r('2026-09-16', kg: 69.0), r('2026-09-19', kg: 68.0)];
      expect(latestKg(asc), 68);
      expect(bodyToGoal(asc, 65.0), 3.0);
      expect(bodyToGoal(asc, null), isNull);
      expect(bodyToGoal(const [], 65), isNull);
      expect(latestKg(const []), isNull);
    });

    test('计数行：条数与窗口内有记录的天数是两个数（总数盖不住窗口内的稀疏）', () {
      expect(bodyCountTx(total: 3, days: 30, inWindow: 3), '共 3 条实测 · 窗口 30 天内仅 3 天有记录');
      // 九条实测里只有 3 天落在 30 天窗口：尾巴上的天数必须是窗口内的 3，不是总数 9
      expect(bodyCountTx(total: 9, days: 30, inWindow: 3), '共 9 条实测 · 窗口 30 天内仅 3 天有记录');
      expect(bodyCountTx(total: 30, days: 30, inWindow: 30), '共 30 条实测',
          reason: '窗口天天有记录＝不加尾巴');
      expect(bodyCountTx(total: 0, days: 90, inWindow: 0), '共 0 条实测 · 窗口 90 天内仅 0 天有记录');
    });
  });

  group('BMI 回落链（缺身高就算不出，不拿 170 兜底）', () {
    test('档案身高＝最近一次填过的那条', () {
      final asc = [r('2026-09-16', kg: 69.0, h: 170.0), r('2026-09-17', kg: 69.0), r('2026-09-19', kg: 68.0, h: 172.0)];
      expect(latestHeightCm(asc), 172.0);
      expect(latestHeightCm([asc[1]]), isNull);
    });

    test('本条没身高 → 用档案最近身高 → 都没有 → null', () {
      final asc = [r('2026-09-16', kg: 69.0, h: 170.0), r('2026-09-19', kg: 68.0)];
      expect(bodyBmi(asc[1], latestHeightCm(asc)), bmi(kg: 68.0, cm: 170.0));
      expect(bodyBmi(asc[1], null), isNull, reason: '两处都缺＝算不出，兜个 170 就是假「正常」');
      expect(bodyBmi(r('2026-09-19'), null), isNull);
      expect(bodyBmiTx(null), '—');
      expect(bodyLevelTx(null), '—');
    });

    test('BMI 分级四档（需求 V1.48 口径）', () {
      expect(bodyLevelTx(bmi(kg: 50.0, cm: 170.0)!), '偏瘦');
      expect(bodyLevelTx(bmi(kg: 68.0, cm: 172.0)!), '正常');
      expect(bodyLevelTx(bmi(kg: 75.0, cm: 172.0)!), '超重');
      expect(bodyLevelTx(bmi(kg: 95.0, cm: 172.0)!), '肥胖');
    });
  });

  test('流水摘要：缺档不占位', () {
    expect(bodyExtrasTx(r('2026-09-19', kg: 68.0)), '');
    expect(bodyExtrasTx(r('2026-09-19', fat: 18.5, waist: 76.0)), '体脂18.5% · 腰76');
    expect(bodyExtrasTx(r('2026-09-19', fat: 18.0, waist: 76.0, hip: 93.0, neck: 36.0)),
        '体脂18% · 腰76 · 臀93 · 颈36');
  });
}
