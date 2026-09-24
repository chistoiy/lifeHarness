/// 生长曲线纯函数（原型 GFULL/GBANDS 同构 + 由实测推导 P/SD/Z 与跨带预警）。
///
/// 红线 6：曲线数据全部来自 care_measures 按宝宝分档，不存展示串；
/// WHO 参考带沿用原型方案——以 0-18 月龄 P50 中位数数组 × 8 档系数近似。
library;

import 'dart:math' as math;

import 'care_models.dart';

enum GMetric {
  w('体重', 'kg'),
  h('身高', 'cm'),
  head('头围', 'cm');

  const GMetric(this.name, this.unit);
  final String name;
  final String unit;
}

/// WHO P50 中位数（月龄 0-18 逐月；原型 GFULL.med 同文）。
const Map<GMetric, List<double>> kGrowthMed = {
  GMetric.w: [
    3.3, 4.5, 5.6, 6.4, 7.0, 7.5, 7.9, 8.3, 8.6, 8.9,
    9.2, 9.4, 9.6, 9.8, 10.0, 10.2, 10.4, 10.5, 10.7
  ],
  GMetric.h: [
    49.9, 54.7, 58.4, 61.4, 63.9, 65.9, 67.6, 69.2, 70.6, 71.9,
    73.1, 74.3, 75.4, 76.3, 77.2, 78.0, 78.8, 79.5, 80.2
  ],
  GMetric.head: [
    34.2, 36.3, 38.1, 39.5, 40.8, 41.9, 42.8, 43.7, 44.4, 45.0,
    45.5, 46.0, 46.4, 46.7, 47.0, 47.2, 47.4, 47.6, 47.8
  ],
};

/// 参考带系数（原型 GBANDS：[男宝, 女宝] 8 档，中位=第 5 档 1.0）。
const List<List<double>> kGrowthBandPairs = [
  [.74, .82, .90, .96, 1, 1.05, 1.11, 1.20], // 男
  [.80, .87, .93, .98, 1, 1.03, 1.08, 1.15], // 女
];

List<double> gBands(bool isFemale) => kGrowthBandPairs[isFemale ? 1 : 0];

/// 月龄线性插值（0-18 之外钳位）。
double gMed(GMetric m, double month) {
  final arr = kGrowthMed[m]!;
  if (month <= 0) return arr.first;
  if (month >= arr.length - 1) return arr.last;
  final i = month.floor();
  final t = month - i;
  return arr[i] * (1 - t) + arr[i + 1] * t;
}

/// 近似标准差：P3~P97 ≈ ±1.88σ ⇒ sd ≈ med·(f7−f0)/3.76。
double gSd(bool isFemale, GMetric m, double month) {
  final bd = gBands(isFemale);
  return gMed(m, month) * (bd[7] - bd[0]) / 3.76;
}

double gZ(bool isFemale, GMetric m, double month, double v) =>
    (v - gMed(m, month)) / gSd(isFemale, m, month);

/// 正态 CDF（A&S 7.1.26 erf 近似，|ε|<1.5e-7）。
double gNormCdf(double z) => 0.5 * (1 + _erfAs(z / _sqrt2));

double _erfAs(double x) {
  final sign = x < 0 ? -1.0 : 1.0;
  final ax = x.abs();
  final t = 1 / (1 + 0.3275911 * ax);
  final y = 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t -
              0.284496736) *
          t +
          0.254829592) *
      t *
      math.exp(-ax * ax);
  return sign * y;
}

const double _sqrt2 = 1.4142135623730951;

/// 百分位（1-99 整数）。
int gPercentile(double z) => (gNormCdf(z) * 100).round().clamp(1, 99);

/// 三模显示文案（mode 0=P 百分位 / 1=SD / 2=Z；原型 GVALS 词条同构）。
String growthStatText(bool isFemale, GMetric m, double month, double v, int mode) {
  final z = gZ(isFemale, m, month, v);
  final p = gPercentile(z);
  switch (mode) {
    case 1:
      return '${z >= 0 ? '高于' : '低于'}均值 ${z >= 0 ? '+' : '−'}${z.abs().toStringAsFixed(1)} SD';
    case 2:
      return 'Z 分数 ${z >= 0 ? '+' : '−'}${z.abs().toStringAsFixed(2)}';
    default:
      return '处于 P$p 百分位';
  }
}

String growthPctTag(bool isFemale, GMetric m, double month, double v) =>
    'P${gPercentile(gZ(isFemale, m, month, v))}';

/// 三模短标签（曲线描点旁注/缩略卡信息行用）。
String growthShortTag(bool isFemale, GMetric m, double month, double v, int mode) {
  final z = gZ(isFemale, m, month, v);
  switch (mode) {
    case 1:
      return '${z >= 0 ? '+' : '−'}${z.abs().toStringAsFixed(1)} SD';
    case 2:
      return 'Z${z >= 0 ? '+' : '−'}${z.abs().toStringAsFixed(2)}';
    default:
      return 'P${gPercentile(z)}';
  }
}

/// 主带序号（0=P3以下 … 4=P97以上；边界 med×[f0,f2,f4,f6]，原型标注同构）。
int growthBandIdx(bool isFemale, GMetric m, double month, double v) {
  final bd = gBands(isFemale);
  final med = gMed(m, month);
  final edges = [bd[0], bd[2], bd[4], bd[6]].map((f) => med * f).toList();
  var idx = 0;
  for (final e in edges) {
    if (v > e) idx++;
  }
  return idx;
}

/// 跨带预警：30 天内相邻两次测量跨 ≥2 条主百分位带（升或降）。
/// 返回预警描述（含就诊参考，不构成医疗建议）；未触发返回 null。
String? growthCrossWarn({
  required bool isFemale,
  required GMetric m,
  required DateTime birth,
  required List<CareMeasure> measures,
}) {
  final sorted = [...measures]..sort((a, b) => a.day.compareTo(b.day));
  double valOf(CareMeasure x) => switch (m) {
        GMetric.w => x.w,
        GMetric.h => x.h,
        GMetric.head => x.head,
      };
  for (var i = 1; i < sorted.length; i++) {
    final d0 = DateTime.parse(sorted[i - 1].day);
    final d1 = DateTime.parse(sorted[i].day);
    if (d1.difference(d0).inDays > 30) continue;
    final b0 = growthBandIdx(isFemale, m, careAgeMonths(birth, d0), valOf(sorted[i - 1]));
    final b1 = growthBandIdx(isFemale, m, careAgeMonths(birth, d1), valOf(sorted[i]));
    if ((b1 - b0).abs() >= 2) {
      final dir = b1 > b0 ? '上跨' : '下跨';
      return '${m.name}在 30 天内$dir ${(b1 - b0).abs()} 条主百分位带（'
          'P带 ${b0 + 1} → ${b1 + 1}）。建议儿保就诊参考复核趋势'
          '（本提示为发育观察，不构成医疗建议）。';
    }
  }
  return null;
}

/// 自身测量序列（月龄, 值）按月龄升序。
List<(double, double)> growthSeries({
  required GMetric m,
  required DateTime birth,
  required List<CareMeasure> measures,
}) {
  final pts = measures.map((x) {
    final d = DateTime.parse(x.day);
    return (
      careAgeMonths(birth, d),
      switch (m) {
        GMetric.w => x.w,
        GMetric.h => x.h,
        GMetric.head => x.head,
      }
    );
  }).toList()
    ..sort((a, b) => a.$1.compareTo(b.$1));
  return pts;
}
