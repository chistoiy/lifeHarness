import 'dart:math' as math;

import 'health_calc.dart';
import 'health_models.dart';

/// 运动规格单源（批4 · 原型 `index-health.html` 的 `HT.exTypes`/`HT.distTypes`/`HT_KCAL` 与
/// `hExMode`/`hExCalc`/`hRenderExLog` 三处 JS）。页面、弹层、工作台卡、趋势图**都从这里取**，
/// 不在四处各写一遍档位与口径。

/// 八类运动（顺序＝原型 chips 顺序，力量/瑜伽/其他＝无距离类）。
const List<String> exTypes = ['跑步', '骑行', '游泳', '力量', '球类', '瑜伽', '步行', '其他'];

/// 距离类四判（原型 `HT.distTypes`）；其余四类只填时长，距离与配速置灰（§五.4）。
const Set<String> exDistanceTypes = {'跑步', '骑行', '游泳', '步行'};

bool hasDistance(String type) => exDistanceTypes.contains(type);

/// 数据来源三档；「设备导入」＝§九.6 只留字段与入口灰位，本批不可选。
const List<String> exSources = ['手动', '计时', '设备导入'];
bool exSourceEnabled(String src) => src != '设备导入';

/// 三模 seg＝**哪一项是被算出来的**（值名直接接 `deriveExercise` 的 mode 串，不再多绕一层）。
/// 档位标签按用户填的那两量命名（原型 `data-m`）：
/// · `pace`（「按距离」）＝填距离＋时长 → 算配速；
/// · `distance`（「按时长」）＝填时长＋配速 → 算距离；
/// · `duration`（「按配速」）＝填距离＋配速 → 算时长。
enum ExMode {
  pace,
  distance,
  duration;

  String get label => switch (this) {
        ExMode.pace => '按距离',
        ExMode.distance => '按时长',
        ExMode.duration => '按配速',
      };

  /// 本档下**只读回显**的那一列（派生项即使只读也要回显，否则残留上一模式的值——原型注释原话）。
  String get readOnlyField => switch (this) {
        ExMode.pace => 'pace',
        ExMode.distance => 'km',
        ExMode.duration => 'min',
      };
}

ExMode exModeOf(String? key) => ExMode.values.firstWhere(
      (m) => m.name == key,
      orElse: () => ExMode.pace,
    );

/// 三模互算：知二算一，算不出的项保持用户填的原值（不悄悄清空）。
/// 无距离类型一律把距离与配速折成 null（保存与回显同一条判据，别两处各判一次）。
({double? km, int? min, int? paceSec}) exTriad({
  required String type,
  required ExMode mode,
  double? km,
  int? min,
  int? paceSec,
}) {
  if (!hasDistance(type)) return (km: null, min: min, paceSec: null);
  return deriveExercise(mode: mode.name, km: km, min: min, paceSec: paceSec);
}

/// 弹层底部的闭合回显（原型 `heCalc`）。`unit` 只改后缀与换算，不改判据。
String exCalcTx({
  required String type,
  required ExMode mode,
  double? km,
  int? min,
  int? paceSec,
  String unit = 'km',
}) {
  if (!hasDistance(type)) return '该类型不计距离 · 只需填时长';
  final t = exTriad(type: type, mode: mode, km: km, min: min, paceSec: paceSec);
  if ((t.km ?? 0) > 0 && (t.min ?? 0) > 0 && t.paceSec != null) {
    return '三值闭合 · 均配速 ${paceLabelFor(t.paceSec, unit)} ${exDistUnitTx(unit)} · '
        '估算消耗 ${estKcal(type, t.min!)} kcal';
  }
  return '还需填一项';
}

/// 距离单位后缀（原型写死 `/km`，§五.10 要求派生值跟着档位走）。
String exDistUnitTx(String unit) => unit == 'mile' ? '/mile' : '/km';

/// 距离展示：存储恒公制，mile 档只换读数（1 位小数，与 `num1` 同口径）。
String exKmTx(double km, String unit) => num1(kmToDisplay(km, unit));

/// 配速展示：秒/公里 → 当前距离单位下的「每英里」要 ×1.609（＝÷0.621371）。
String paceLabelFor(int? paceSec, String unit) {
  if (paceSec == null) return '—';
  if (paceSec <= 0) return '—';
  return paceLabel(unit == 'mile' ? (paceSec / 0.621371).round() : paceSec);
}

/// 窗口切片（本周＝7 天、本月＝30 天，与体征页同一算法）。升序入、升序出。
List<ExerciseRecord> exWindow(List<ExerciseRecord> all,
    {required int days, required String today}) {
  final from = dayKey(
      DateTime.parse(today).subtract(Duration(days: days - 1))); // 含今天往回 days 天
  return all.where((e) => e.date.compareTo(from) >= 0 && e.date.compareTo(today) <= 0).toList();
}

/// 四数据位（原型 `elN/elMin/elKm/elPc`）：次数＝窗口内条数，**周目标的「次数」另算**
/// （§五.9 只数 ≥10 分钟的条数，两处口径不同，别互相顶替）。
({int count, int totalMin, double totalKm, int totalKcal}) exStats(
    List<ExerciseRecord> win) {
  var min = 0, kcal = 0;
  var km = 0.0;
  for (final e in win) {
    min += e.durationMin;
    kcal += e.kcal ?? 0;
    km += e.distanceKm ?? 0;
  }
  return (count: win.length, totalMin: min, totalKm: km, totalKcal: kcal);
}

/// 本周有效次数（≥10 分钟才算一次，同日多条各计一次）。
int exWeekSessions(List<ExerciseRecord> week) =>
    sessionCount([for (final e in week) e.durationMin]);

/// 流水过滤档（原型 `exFilterRow`＝「全部」＋八类；「全部」不是类型名，别混进 `exTypes`）。
const String exAllFilter = '全部';
List<String> exFilterOptions() => [exAllFilter, ...exTypes];

List<ExerciseRecord> exFiltered(List<ExerciseRecord> list, String filter) => [
      for (final e in list)
        if (filter == exAllFilter || e.type == filter) e
    ];

/// 流水排序：仓储给的是 date 升序，屏上按「最新在上」渲染（原型存时就倒序）。
/// 同日保持原序（稳定排：编辑/新增同一天的两条不应因为重排而上下跳）。
List<ExerciseRecord> exListDesc(List<ExerciseRecord> asc) => asc.reversed.toList();

/// 配速趋势取样＝距离类最近 12 条（升序，原型 `filter(e=>e.km).slice(0,12).reverse()`）。
/// 类型判据在这里再过一遍：卡片标题写的是「仅距离类」，一条脏数据（力量带 km）不该把假点绘进曲线。
List<ExerciseRecord> exPaceTrend(List<ExerciseRecord> all) {
  final ds = [
    for (final e in all)
      if (hasDistance(e.type) && (e.distanceKm ?? 0) > 0 && exTrendPaceSec(e) != null) e
  ]..sort((a, b) => a.date.compareTo(b.date));
  return ds.length <= 12 ? ds : ds.sublist(ds.length - 12);
}

/// 趋势/回显用的配速（秒每公里）：存了用存的，没存按 时长÷距离 现算
/// （与仓储的落库回落同一条式子，两处不会算出两个数）。
int? exTrendPaceSec(ExerciseRecord r) =>
    r.paceSec ?? paceSecOf(distanceKm: r.distanceKm, durationMin: r.durationMin);

/// 最快／最慢档（原型 `fmtPace(Math.min/max(...vs))`）：秒每公里越小越快。
({int? fast, int? slow}) exPaceSpread(List<ExerciseRecord> trend) {
  final vs = [for (final e in trend) exTrendPaceSec(e) ?? 0].where((v) => v > 0).toList();
  if (vs.isEmpty) return (fast: null, slow: null);
  return (fast: vs.reduce(math.min), slow: vs.reduce(math.max));
}

/// 趋势空态判据（不足 2 条不画线，别拿一条点连成「趋势」）。
bool exTrendEnough(List<ExerciseRecord> trend) => trend.length >= 2;

/// 计时器秒 → 落库分钟（原型 `Math.max(1, round(...))`：跑不满 1 分钟也记 1 分钟，
/// 否则一条「0 分钟」的记录既进不了流水也进不了周次数）。
int exMinutesOf(int elapsedSeconds) => math.max(1, (elapsedSeconds / 60).round());

/// 流水主行（原型 `${t}${km?' · '+km+' km':''} · ${min}min`）。
String exRowMain(ExerciseRecord r, String unit) =>
    '${r.type}${r.distanceKm == null ? '' : ' · ${exKmTx(r.distanceKm!, unit)} $unit'} · ${r.durationMin}min';

/// 流水副注（日期 · 星期 · kcal · 来源 · 备注）。
String exRowSub(ExerciseRecord r) {
  final parts = <String>['${r.date} ${dayWd(r.date)}'];
  if ((r.kcal ?? 0) > 0) parts.add('${r.kcal} kcal');
  parts.add('来源 ${r.source}');
  final note = r.note?.trim();
  if (note != null && note.isNotEmpty) parts.add(note);
  return parts.join(' · ');
}

/// 保存前的收敛：时长必填、无距离类型不存距离/配速、配速与 kcal 由调用方按
/// `exTriad`＋`estKcal` 现算后传入（仓储那层还有一条同式回落，两处判据要一致）。
ExerciseRecord exDraft({
  int? id,
  required int profileId,
  required String date,
  required String type,
  required ExMode mode,
  double? km,
  int? min,
  int? paceSec,
  int? kcal,
  String? note,
  String source = '手动',
  int? startedAt,
}) {
  final t = exTriad(type: type, mode: mode, km: km, min: min, paceSec: paceSec);
  return ExerciseRecord(
    id: id,
    profileId: profileId,
    date: date,
    type: type,
    distanceKm: t.km,
    durationMin: t.min ?? 0,
    paceSec: t.paceSec,
    kcal: kcal,
    note: note,
    source: source,
    startedAt: startedAt,
  );
}
