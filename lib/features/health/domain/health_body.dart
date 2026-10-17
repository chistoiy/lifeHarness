import 'health_calc.dart';
import 'health_models.dart';

/// 身体数据规格单源（批3·原型 `p-body`／`sheetHWeight`）。
///
/// 滚轮档表、读数换算、曲线取样与三统计**只从这里出**——屏与弹层各抄一份档表就是双源，
/// 改档时必有一处忘改（批2.5 的 `vitalRef` 立的同一条规矩）。
class BodyField {
  const BodyField({
    required this.col,
    required this.label,
    required this.lo,
    required this.hi,
    required this.step,
    required this.unit,
  });

  /// 落库列的简称：fat/waist/hip/neck。
  final String col;
  final String label;
  final double lo;
  final double hi;
  final double step;
  final String unit;

  /// 档表（`+1e-9` 容差＝原型 `hNums` 同式：浮点累加会把末档漏掉）。
  List<double> get values {
    final out = <double>[];
    for (var v = lo; v <= hi + 1e-9; v += step) {
      out.add(double.parse(v.toStringAsFixed(2)));
    }
    return out;
  }

  /// 选填柱首位固定「—」＝不写入（原型 `opt()` 的 `['—'].concat(vals)`）。
  List<String> get labels => ['—', for (final v in values) trim(v)];

  /// 档号读数：0＝「—」＝不写入。
  double? valueAt(int index) =>
      index <= 0 ? null : values[(index - 1).clamp(0, values.length - 1)];

  /// 反查最近档；null／越界一律回到 0＝「—」（不把「未填」落成 8% 体脂）。
  int indexOf(double? v) {
    if (v == null) return 0;
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < values.length; i++) {
      final d = (values[i] - v).abs();
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best + 1;
  }

  static String trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

/// 四枚选填柱（原型 `hRecOpen` 的 `opt('hwF'/'hwW'/'hwHp'/'hwNk')` 四行档表）。
const bodyOptionalFields = <BodyField>[
  BodyField(col: 'fat', label: '体脂', lo: 8, hi: 40, step: 0.5, unit: '%'),
  BodyField(col: 'waist', label: '腰围', lo: 50, hi: 120, step: 0.5, unit: 'cm'),
  BodyField(col: 'hip', label: '臀围', lo: 60, hi: 130, step: 0.5, unit: 'cm'),
  BodyField(col: 'neck', label: '颈围', lo: 28, hi: 48, step: 1, unit: 'cm'),
];

BodyField bodyField(String col) =>
    bodyOptionalFields.firstWhere((f) => f.col == col);

// ==================== 体重两柱／身高柱 ====================

/// 体重整数柱 35~120（原型 `hNums(35,120,1)`），小数柱 0~9＝0.1 kg 一档。
const int kgWholeLo = 35;
const int kgWholeHi = 120;
const int heightLo = 140;
const int heightHi = 200;

/// 两柱合读＝录入值（原型 `hBodyPreview` 的 `(hNw('hwKgI')||69)+(hNw('hwKgD')||0)/10`）。
double kgAt(int wholeIndex, int decIndex) => (kgWholeLo + wholeIndex) + decIndex / 10.0;

int kgWholeIndexOf(double kg) => (kg.floor() - kgWholeLo).clamp(0, kgWholeHi - kgWholeLo);

/// 小数位按**四舍五入**归档：`(22-2.8)/0.1` 在 IEEE754 下是 191.999…，`floor` 会少一档（批2.5 实测坑）。
int kgDecIndexOf(double kg) => ((kg - kg.floor()) * 10).round().clamp(0, 9);

List<String> get kgWholeLabels => [for (var v = kgWholeLo; v <= kgWholeHi; v++) '$v'];
List<String> get kgDecLabels => [for (var d = 0; d <= 9; d++) '$d'];

/// 身高柱（140~200 整档）。首位「—」＝不改写身高——见 `heightValueAt` 的说明。
List<String> get heightLabels => ['—', for (var v = heightLo; v <= heightHi; v++) '$v'];

/// 0＝「—」＝不动已有身高（原型是「常开柱＋永远写入」，这里给「—」是为了不让一次没填的身高
/// 变成 170 假值——BMI 会拿它算出「正常」，那才是真编数据）。
double? heightValueAt(int index) => index <= 0 ? null : (heightLo + index - 1).toDouble();

int heightIndexOf(double? cm) =>
    cm == null ? 0 : (cm.round() - heightLo).clamp(0, heightHi - heightLo) + 1;

// ==================== 读数与单位（§五.10：存储恒公制，只影响展示） ====================

String bodyKgTx(double kg, String unit) => (unit == '斤' ? kg * 2 : kg).toStringAsFixed(1);

/// 变化量：带符号＋当前单位（原型 `boWk`/`boRg` 在斤档下也 ×2）。null＝算不出＝「—」。
String bodyDeltaTx(double? diffKg, String unit) {
  if (diffKg == null) return '—';
  final v = unit == '斤' ? diffKg * 2 : diffKg;
  return '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)} $unit';
}

/// 距目标**恒按 kg**（原型 `boG` 就是 `(cur-goal).toFixed(1)+' kg'`，切换单位不动它）。
String bodyGoalTx(double? diffKg) => diffKg == null ? '—' : '${diffKg.toStringAsFixed(1)} kg';

// ==================== 曲线取样与三统计 ====================

/// 窗口切片（`days` 个自然日，含今天）。`all` 必须按 date 升序。
List<BodyRecord> bodyWindow(List<BodyRecord> all, {required int days, required String today}) {
  final from = dayKey(DateTime.parse(today).subtract(Duration(days: days - 1)));
  return all.where((r) => r.date.compareTo(from) >= 0 && r.date.compareTo(today) <= 0).toList();
}

class BodyPoint {
  const BodyPoint({required this.date, required this.dayOffset, required this.kg});

  final String date;

  /// 距窗口首日的天数（x 轴位置按日期算，不按点序——否则 3 条记录会铺满 365 天窗口）。
  final int dayOffset;
  final double kg;
}

/// 曲线取样＝窗口内的**实测**点。无记录的日子不出点（工单 §1：原型 `htKg()` 的趋势假值不照抄）。
List<BodyPoint> bodyCurve(List<BodyRecord> win, {required int days, required String today}) {
  final from = dayKey(DateTime.parse(today).subtract(Duration(days: days - 1)));
  final base = DateTime.parse(from);
  return [
    for (final r in win)
      if (r.kg != null)
        BodyPoint(
            date: r.date,
            dayOffset: DateTime.parse(r.date).difference(base).inDays.clamp(0, days - 1),
            kg: r.kg!),
  ];
}

/// 轴端＝min(实测, 目标)−0.4 / max(实测, 目标)+0.4（原型 `hBodyChart` 同式；目标线必须落在校刻度内）。
double bodyAxisLo(List<BodyPoint> pts, double? goalKg) {
  final vals = pts.map((p) => p.kg).toList();
  if (goalKg != null) vals.add(goalKg);
  return vals.reduce((a, b) => a < b ? a : b) - 0.4;
}

double bodyAxisHi(List<BodyPoint> pts, double? goalKg) {
  final vals = pts.map((p) => p.kg).toList();
  if (goalKg != null) vals.add(goalKg);
  return vals.reduce((a, b) => a > b ? a : b) + 0.4;
}

/// 周变化基线＝倒数第 8 条实测（原型 `all[len-8]`）。不足 8 条＝算不出（原型此处会印 `NaN`，
/// 我们出「—」——见工单 §1 偏离登记）。曲线统计与录入预览共用这一处取数，不许两处各写各的。
double? bodyWeekBaseline(List<BodyRecord> allAsc) =>
    allAsc.length < 8 ? null : allAsc[allAsc.length - 8].kg;

double? bodyWeekChange(List<BodyRecord> allAsc) =>
    allAsc.isEmpty ? null : _diff(allAsc.last.kg, bodyWeekBaseline(allAsc));

/// 区间变化＝窗口内首末实测之差（需 ≥2 点）。
double? bodyRangeChange(List<BodyRecord> winAsc) {
  final kgv = winAsc.map((r) => r.kg).whereType<double>().toList();
  if (kgv.length < 2) return null;
  return _diff(kgv.last, kgv.first);
}

double? bodyToGoal(List<BodyRecord> allAsc, double? goalKg) =>
    _diff(latestKg(allAsc), goalKg);

double? _diff(double? a, double? b) =>
    (a == null || b == null) ? null : double.parse((a - b).toStringAsFixed(1));

double? latestKg(List<BodyRecord> allAsc) => allAsc.isEmpty ? null : allAsc.last.kg;

/// 档案身高＝最近一次**填过**的身高（BMI 的回落链：本条身高 → 档案最近身高 → 没有就算不出）。
double? latestHeightCm(List<BodyRecord> allAsc) {
  for (final r in allAsc.reversed) {
    if (r.heightCm != null) return r.heightCm;
  }
  return null;
}

/// 本条读数的 BMI（kg × 档案身高回落）；缺任一＝null，UI 出「—」，不拿 170 兜底。
double? bodyBmi(BodyRecord r, double? fallbackHeightCm) =>
    bmi(kg: r.kg, cm: r.heightCm ?? fallbackHeightCm);

String bodyBmiTx(double? b) => b == null ? '—' : b.toStringAsFixed(1);

String bodyLevelTx(double? b) => b == null ? '—' : bmiLevel(b);

/// 计数行：条数只数实测，窗口比实测条数大时**如实说明没测的那几天**（不写「按趋势补全」）。
///
/// 两个计数分开传是必需的：`total`＝该档案全部实测条数，`inWindow`＝当前窗口内有记录的天数
/// （同日唯一索引 ⇒ 窗口条数＝有记录天数）。把 `total` 同时当「窗口内有几天」用，会在
/// 「共 9 条、其中 3 条落在 30 天窗口」这类数据上报出「窗口 30 天内仅 9 天有记录」。
String bodyCountTx({required int total, required int days, required int inWindow}) =>
    inWindow >= days
        ? '共 $total 条实测'
        : '共 $total 条实测 · 窗口 $days 天内仅 $inWindow 天有记录';

/// 列简称 → 记录字段（录入表单按 `BodyField.col` 取值，落库按同一张表拼行；
/// 两处各写一份 switch 就会漏列）。
double? bodyFieldValue(BodyRecord? r, String col) => r == null ? null : switch (col) {
      'fat' => r.fatPct,
      'waist' => r.waistCm,
      'hip' => r.hipCm,
      'neck' => r.neckCm,
      _ => null,
    };

/// 流水行的选填摘要（原型「体脂x% · 腰x · 臀x · 颈x」，缺档不占位）。
String bodyExtrasTx(BodyRecord r) => [
      if (r.fatPct != null) '体脂${BodyField.trim(r.fatPct!)}%',
      if (r.waistCm != null) '腰${BodyField.trim(r.waistCm!)}',
      if (r.hipCm != null) '臀${BodyField.trim(r.hipCm!)}',
      if (r.neckCm != null) '颈${BodyField.trim(r.neckCm!)}',
    ].join(' · ');
