/// 健康模块纯函数（口径唯一出处＝《docs/健康管理模块开发计划-20260927.md》§五 + 需求清单模块 12「核心口径」）。
///
/// 全部无副作用、不读库、不读设置：分母（目标值）一律由调用方传进来，
/// 「改目标后历史不重算失真」这条口径才守得住（§2.2 派生不落库）。
/// 日期一律 `yyyy-MM-dd` 字符串（与表内 date 列同形），时刻一律 `HH:mm`。
library;

import 'dart:math' as math;

/// 日期 → `yyyy-MM-dd`（本地日，趋势按自然日 00:00 切分）。
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// `HH:mm` → 当日分钟数；非法输入返回 null（调用侧按「未填」处理，不猜）。
int? hhmmToMin(String? s) {
  if (s == null) return null;
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!), mi = int.parse(m.group(2)!);
  if (h > 23 || mi > 59) return null;
  return h * 60 + mi;
}

String minToHhmm(int min) =>
    '${(min ~/ 60) % 24}:${(min % 60).toString().padLeft(2, '0')}';

/// 睡眠时长（分钟）＝醒来 − 入睡，≤0 补 1440（跨天在写入侧算一次，读取侧不再判）。
int sleepDurationMin(String bed, String wake) {
  final b = hhmmToMin(bed), w = hhmmToMin(wake);
  if (b == null || w == null) return 0;
  final d = w - b;
  return d <= 0 ? d + 1440 : d;
}

/// 「按时入睡」＝入睡时刻 ≤ 界线（默认 23:30）。入睡时刻在界线之前才算，
/// 凌晨（如 00:20）属「晚睡」——所以 0 点后的时刻一律判不过（换算成 ≥1440 的「昨夜轴」）。
bool fellAsleepOnTime(String bed, String line) {
  final b = hhmmToMin(bed), l = hhmmToMin(line);
  if (b == null || l == null) return false;
  final bedAxis = b < 4 * 60 ? b + 1440 : b; // 00:00–03:59 归昨夜
  final lineAxis = l < 4 * 60 ? l + 1440 : l;
  return bedAxis <= lineAxis;
}

/// 分期四段之和与总时长差 >20min → 需要提示核对（不阻断保存，§五.3）。
bool stagesOffByMoreThan20({
  required int? deep,
  required int? light,
  required int? rem,
  required int? awake,
  required int totalMin,
}) {
  if (deep == null && light == null && rem == null && awake == null) return false; // 未记录分期
  final sum = (deep ?? 0) + (light ?? 0) + (rem ?? 0) + (awake ?? 0);
  return (sum - totalMin).abs() > 20;
}

/// BMI = kg ÷ (cm/100)²；身高缺失算不出（返回 null，UI 显「—」，不拿 170 兜底）。
double? bmi({required double? kg, required double? cm}) {
  if (kg == null || cm == null || kg <= 0 || cm <= 0) return null;
  final h = cm / 100.0;
  return double.parse((kg / (h * h)).toStringAsFixed(1));
}

/// 分级口径（需求 V1.48）：偏瘦 <18.5 · 正常 <24 · 超重 <28 · 肥胖 ≥28。
String bmiLevel(double b) =>
    b < 18.5 ? '偏瘦' : (b < 24 ? '正常' : (b < 28 ? '超重' : '肥胖'));

/// MET 表（§五.6）：kcal 估算 = 分钟 × MET。用户填了 kcal 以其为准，不在此判。
const Map<String, double> metByType = {
  '跑步': 10.5,
  '骑行': 7.5,
  '游泳': 9.0,
  '力量': 5.0,
  '球类': 7.0,
  '瑜伽': 3.4,
  '步行': 4.2,
  '其他': 5.0,
};

/// 无距离类型（力量/瑜伽/其他）：距离与配速一律置灰（§五.4）。
const Set<String> distanceFreeTypes = {'力量', '瑜伽', '其他'};

int estKcal(String type, int durationMin) =>
    (durationMin * (metByType[type] ?? metByType['其他']!)).round();

/// 配速存「秒/公里」；距离≤0 或时长≤0 算不出。
int? paceSecOf({required double? distanceKm, required int? durationMin}) {
  if (distanceKm == null || durationMin == null) return null;
  if (distanceKm <= 0 || durationMin <= 0) return null;
  return (durationMin * 60 / distanceKm).round();
}

/// 配速解析：容忍 `6'00"`、`6:00`、`600` 三种写法（§五.5）。
/// 两组数字＝分+秒；只有一组时按「末两位是秒、其余是分」读（`600` → 6 分 00 秒，不是 600 分）。
int? parsePaceSec(String raw) {
  final groups = RegExp(r'\d+').allMatches(raw).toList();
  if (groups.isEmpty) return null;
  if (groups.length >= 2) {
    return int.parse(groups[0].group(0)!) * 60 + (int.parse(groups[1].group(0)!) % 60);
  }
  final s = groups[0].group(0)!;
  if (s.length <= 2) return int.parse(s) * 60;
  return int.parse(s.substring(0, s.length - 2)) * 60 + int.parse(s.substring(s.length - 2));
}

String paceLabel(int? paceSec) =>
    paceSec == null ? '—' : "${paceSec ~/ 60}′${(paceSec % 60).toString().padLeft(2, '0')}″";

/// 运动三模互算：`mode` 决定哪一项是被算出来的（派生项也要回显，别留上一模式的值）。
/// 返回 (距离km, 时长min, 配速秒/公里)；算不出的项为 null。
({double? km, int? min, int? paceSec}) deriveExercise({
  required String mode,
  double? km,
  int? min,
  int? paceSec,
}) {
  switch (mode) {
    case 'distance': // 已知时长+配速，算距离
      if (min == null || paceSec == null || paceSec <= 0) return (km: km, min: min, paceSec: paceSec);
      return (km: double.parse((min * 60 / paceSec).toStringAsFixed(2)), min: min, paceSec: paceSec);
    case 'duration': // 已知距离+配速，算时长
      if (km == null || paceSec == null || paceSec <= 0) return (km: km, min: min, paceSec: paceSec);
      return (km: km, min: (km * paceSec / 60).round(), paceSec: paceSec);
    default: // pace：已知距离+时长，算配速
      return (km: km, min: min, paceSec: paceSecOf(distanceKm: km, durationMin: min));
  }
}

/// 每周运动次数＝本周内 duration_min ≥10 的记录条数（同日多条各计一次，§五.9）。
int sessionCount(List<int> durationMinutes) =>
    durationMinutes.where((m) => m >= 10).length;

/// 综合达标度 = 喝水 40% + 睡眠 35% + 运动 25%，分量封顶 100%；运动是门槛制（§五.1）。
/// 返回 0~100 的整数。分母 ≤0（目标没设）时该分量记 0 分——不拿默认值糊上去。
double dailyScore({
  required int cups,
  required double waterGoalCups,
  required int sleepMin,
  required double sleepGoalMin,
  required int exerciseMin,
  int exerciseThresholdMin = 10,
}) {
  double cap(double r) => r.clamp(0.0, 1.0);
  final w = waterGoalCups <= 0 ? 0.0 : cap(cups / waterGoalCups);
  final s = sleepGoalMin <= 0 ? 0.0 : cap(sleepMin / sleepGoalMin);
  final e = exerciseMin >= exerciseThresholdMin ? 1.0 : 0.0;
  return double.parse(((w * 0.4 + s * 0.35 + e * 0.25) * 100).toStringAsFixed(0));
}

/// 分量得分（趋势页四格与周报用），同样封顶 100。
double partScore({required num got, required num goal}) =>
    goal <= 0 ? 0.0 : double.parse(((got / goal).clamp(0.0, 1.0) * 100).toStringAsFixed(0));

// ==================== 用药计划 / 依从率（§五.8） ====================

/// 某时刻是否已打卡（taken/skipped 都算「有交代」，漏服＝两者都没有且时刻已过宽限期）。
bool slotSettled(Map<String, String> loggedAt, String time) {
  final st = loggedAt[time];
  return st == 'taken' || st == 'skipped';
}

bool slotTaken(Map<String, String> loggedAt, String time) => loggedAt[time] == 'taken';

/// 漏服数＝时刻已过（含宽限 missedGraceMin）且既非已服也非跳过。
int missedSlots({
  required List<String> times,
  required Map<String, String> loggedAt,
  required int nowMin,
  int missedGraceMin = 30,
}) =>
    times.where((t) {
      final m = hhmmToMin(t);
      if (m == null) return false;
      return nowMin > m + missedGraceMin && !slotSettled(loggedAt, t);
    }).length;

/// 依从率 = 已服 ÷ 计划（计划为 0 时返回 null，UI 显「—」，不显示 0%）。
double? compliance({required List<String> times, required Map<String, String> loggedAt}) {
  if (times.isEmpty) return null;
  final taken = times.where((t) => slotTaken(loggedAt, t)).length;
  return double.parse((taken / times.length * 100).toStringAsFixed(0));
}

// ==================== 单位（§五.10：存储恒公制，切换只影响展示与输入） ====================

double kgToDisplay(double kg, String unit) => unit == '斤' ? kg * 2 : kg;
double displayToKg(double v, String unit) => unit == '斤' ? v / 2 : v;
double kmToDisplay(double km, String unit) => unit == 'mile' ? km * 0.621371 : km;
double displayToKm(double v, String unit) => unit == 'mile' ? v / 0.621371 : v;
String num1(double v) => v.toStringAsFixed(1);

// ==================== 体征参考区间（§11.3.1，内置默认常量；异常只作提示不作诊断） ====================

/// kind → (下限, 上限)；血压另按 sys/dia 两值判，这里给收缩压区间。
const Map<String, (double, double)> vitalRef = {
  'bp': (90, 139),
  'hr': (55, 95),
  'spo2': (95, 999),
  'glu': (3.9, 6.1),
  'temp': (36.0, 37.2),
};

/// 返回 'low'/'normal'/'high'；无参考区间或值缺失返回 null（UI 标「未记录」而非「正常」）。
String? vitalLevel(String kind, double? v) {
  final r = vitalRef[kind];
  if (r == null || v == null) return null;
  if (v < r.$1) return 'low';
  if (v > r.$2) return 'high';
  return 'normal';
}

/// 较基线差值标签：「较基线 +6」；无基线返回 null。
String? vsBaseline(double? v, double? base) {
  if (v == null || base == null || base == 0) return null;
  final d = (v - base).round();
  return '较基线 ${d >= 0 ? '+' : ''}$d';
}

/// 疼痛分级（§11.3.4）：0-3 轻 / 4-6 中 / 7-10 重。
String painLevel(int level) => level <= 3 ? '轻' : (level <= 6 ? '中' : '重');

/// 区间补全判定：请求天数超出实测范围时，UI 要标注「超出区间按趋势补全」——
/// 正式版**不造假数据**，无数据日显示空槽（§五.11、§九.2）。
int missingDaysInRange({required int rangeDays, required int daysWithData}) =>
    math.max(0, rangeDays - daysWithData);
