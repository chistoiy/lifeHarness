import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/care/domain/care_models.dart';
import 'package:lifeharness/features/care/domain/growth_calc.dart';

/// 呵护批5 · WHO 参考带推导纯函数用例（确定性数值断言）。
void main() {
  group('gMed 插值', () {
    test('端点与线性内插', () {
      expect(gMed(GMetric.w, 0), 3.3);
      expect(gMed(GMetric.w, 18), 10.7);
      expect(gMed(GMetric.w, 0.5), closeTo(3.9, 1e-9));
      expect(gMed(GMetric.w, 99), 10.7); // 超界钳位
    });
  });

  group('P/SD/Z 推导', () {
    test('中位数处 P≈50、Z=0', () {
      final med = gMed(GMetric.w, 6);
      final z = gZ(false, GMetric.w, 6, med);
      expect(z, closeTo(0, 1e-9));
      expect(gPercentile(z), closeTo(50, 1));
    });
    test('三模文案词条同构', () {
      final med = gMed(GMetric.w, 6);
      expect(growthStatText(false, GMetric.w, 6, med, 0), '处于 P50 百分位');
      expect(growthStatText(false, GMetric.w, 6, med + 5, 1), startsWith('高于均值 +'));
      expect(growthStatText(false, GMetric.w, 6, med - 5, 2), startsWith('Z 分数 −'));
    });
  });

  group('跨带预警（30 天内 ≥2 主带）', () {
    final birth = DateTime(2026, 1, 7);
    CareMeasure at(String day, double w) =>
        CareMeasure(babyId: 1, day: day, w: w, h: 70, head: 44, rec: '妈妈');

    test('下跨 4 带触发，含就诊参考与免责', () {
      // 月龄约 7.4 时 med(w)≈8.35；女宝 8.35×[.80,.93,1,1.08]。
      final hi = at('2026-08-20', 10.5); // P97 以上 → idx4
      final lo = at('2026-09-05', 6.0); // P3 以下 → idx0
      final warn = growthCrossWarn(
          isFemale: true, m: GMetric.w, birth: birth, measures: [hi, lo]);
      expect(warn, isNotNull);
      expect(warn, contains('下跨 4 条主百分位带'));
      expect(warn, contains('不构成医疗建议'));
    });

    test('31 天间隔或 1 带内不触发', () {
      final a = at('2026-08-01', 8.4);
      final b = at('2026-09-01', 8.5); // 31 天
      expect(
          growthCrossWarn(
              isFemale: true, m: GMetric.w, birth: birth, measures: [a, b]),
          isNull);
      final c = at('2026-08-10', 8.6); // 同带微升
      expect(
          growthCrossWarn(
              isFemale: true, m: GMetric.w, birth: birth, measures: [a, c]),
          isNull);
    });
  });

  test('growthSeries 按月龄升序 + 值映射正确', () {
    final birth = DateTime(2026, 1, 7);
    final pts = growthSeries(m: GMetric.h, birth: birth, measures: [
      CareMeasure(babyId: 1, day: '2026-09-01', w: 8, h: 70, head: 44),
      CareMeasure(babyId: 1, day: '2026-03-01', w: 5.6, h: 60, head: 38),
    ]);
    expect(pts.length, 2);
    expect(pts.first.$1, lessThan(pts.last.$1));
    expect(pts.first.$2, 60);
    expect(pts.last.$2, 70);
  });

  test('growthBandIdx 边界分档', () {
    final med = gMed(GMetric.w, 6);
    final bd = gBands(true);
    expect(growthBandIdx(true, GMetric.w, 6, med * bd[0]), 0); // 恰在 P3 线上=不算越线
    expect(growthBandIdx(true, GMetric.w, 6, med), 2); // P3~P25~P50：med=P50 线上
    expect(growthBandIdx(true, GMetric.w, 6, med * 1.16), 4);
  });
}
