/// 健康目标规格单源（批3·原型 `p-goalsH`＋`hGoalPick`／`hGoalsReset`）。
///
/// **存储分治**（工单 §0 的口径，不在这里改主意）：
/// · `prefs`＝喝水／睡眠／每周运动／按时入睡线——工作台「每日目标」卡与达标度环已经在读
///   `HealthSettings` 这四键，另起一份 DB 键就是双源，改一处另一处不动；
/// · `db`＝目标体重／腰／臀／颈——身体属性属于档案，随档案走（`health_goal` 表按 profile_id 存），
///   与「跨档案一律不聚合」同一条线。
library;

enum GoalScope { prefs, db }

class GoalSpec {
  const GoalSpec({
    required this.key,
    required this.label,
    required this.hint,
    required this.unit,
    required this.scope,
    required this.lo,
    required this.hi,
    required this.step,
    this.decimals = 0,
  });

  /// prefs 作用域＝`HealthSettings` 里那四键之一的业务名（water/sleep/week_ex）；
  /// db 作用域＝`health_goal.key` 原文（weight_goal/waist_goal/…）。
  final String key;
  final String label;
  final String hint;
  final String unit;
  final GoalScope scope;
  final double lo;
  final double hi;
  final double step;

  /// 读数小数位（体重档 0.5 → 1 位；整档 → 0 位）。
  final int decimals;

  List<double> get values {
    final out = <double>[];
    for (var v = lo; v <= hi + 1e-9; v += step) {
      out.add(double.parse(v.toStringAsFixed(2)));
    }
    return out;
  }

  List<String> get labels => [for (final v in values) v.toStringAsFixed(decimals)];

  double valueAt(int index) => values[index.clamp(0, values.length - 1)];

  int indexOf(double v) {
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < values.length; i++) {
      final d = (values[i] - v).abs();
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  /// 行首读数：数值档带单位（「8 杯」「65 kg」）。
  String read(double v) => '${v.toStringAsFixed(decimals)} $unit';

  /// 未设目标时的占位（围度三项默认没有目标＝「—」，不拿档表中点冒充）。
  String get unsetText => '—';
}

/// 数值目标四行（按时入睡线是时刻，另走 `bedLineLabels`）。
///
/// 档位说明：喝水／睡眠沿用工作台「每日目标」卡的同一张档表（1~12 杯／4~12 小时整档），
/// 原型这里的 4~14 与 6~10 步 0.5 会让两处出现两套档，且 prefs 存的是整小时、半档落不进去。
const goalNumberSpecs = <GoalSpec>[
  GoalSpec(
      key: 'water',
      label: '每日喝水',
      hint: '达成率分母 = 目标杯数',
      unit: '杯',
      scope: GoalScope.prefs,
      lo: 1,
      hi: 12,
      step: 1),
  GoalSpec(
      key: 'sleep',
      label: '睡眠时长',
      hint: '按醒来日归属 · 跨天自动标注',
      unit: '小时',
      scope: GoalScope.prefs,
      lo: 4,
      hi: 12,
      step: 1),
  GoalSpec(
      key: 'week_ex',
      label: '每周运动次数',
      hint: '≥10 分钟计 1 次',
      unit: '次',
      scope: GoalScope.prefs,
      lo: 1,
      hi: 7,
      step: 1),
  GoalSpec(
      key: 'weight_goal',
      label: '目标体重',
      hint: '身体数据页显示差值',
      unit: 'kg',
      scope: GoalScope.db,
      lo: 45,
      hi: 95,
      step: 0.5,
      decimals: 1),
];

/// 围度三项目标（原型「围度目标」卡；`health_goal` 按档案存）。
const goalGirthSpecs = <GoalSpec>[
  GoalSpec(
      key: 'waist_goal',
      label: '腰围',
      hint: '随体重记录选填',
      unit: 'cm',
      scope: GoalScope.db,
      lo: 55,
      hi: 110,
      step: 1),
  GoalSpec(
      key: 'hip_goal',
      label: '臀围',
      hint: '随体重记录选填',
      unit: 'cm',
      scope: GoalScope.db,
      lo: 70,
      hi: 120,
      step: 1),
  GoalSpec(
      key: 'neck_goal',
      label: '颈围',
      hint: '随体重记录选填',
      unit: 'cm',
      scope: GoalScope.db,
      lo: 30,
      hi: 45,
      step: 1),
];

GoalSpec goalSpec(String key) =>
    [...goalNumberSpecs, ...goalGirthSpecs].firstWhere((s) => s.key == key);

/// 「恢复默认目标」的八项（原型 `hGoalsReset` 一行写死的那组）。
const goalDefaults = <String, double>{
  'water': 8,
  'sleep': 8,
  'week_ex': 3,
  'weight_goal': 65,
  'waist_goal': 76,
  'hip_goal': 93,
  'neck_goal': 36,
};
const String bedLineDefault = '23:30';

/// 按时入睡线档表＝24 小时 × 15 分钟（原型 `hTimes()`）。
List<String> get bedLineLabels => [
      for (var h = 0; h < 24; h++)
        for (final m in const [0, 15, 30, 45])
          '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}'
    ];

/// 解析不出（脏值／空）时停在默认档 23:30 对应位置，不落 00:00。
int bedLineIndex(String? hhmm) {
  final i = bedLineLabels.indexOf(hhmm ?? '');
  return i >= 0 ? i : bedLineLabels.indexOf(bedLineDefault);
}

String bedLineAt(int index) => bedLineLabels[index.clamp(0, bedLineLabels.length - 1)];

// ==================== 今日四项达标（原型 `hRenderGoals` 的 conds） ====================

class GoalCheck {
  const GoalCheck(this.name, this.done);
  final String name;
  final bool done;
}

/// 环上的 `n/4`：喝水达杯数／睡眠达时长／**当日有 ≥10 分钟的运动**／用药计划全部已服。
/// 睡眠没记录＝不达标（null 不当 0 用，但也不因为没睡就红字警告——只是不计入）。
List<GoalCheck> goalTodayChecks({
  required int cups,
  required double waterGoal,
  required int? sleepMin,
  required double sleepGoalHours,
  required List<int> exerciseMin,
  required int plannedSlots,
  required int takenSlots,
}) =>
    [
      GoalCheck('喝水', cups >= waterGoal),
      GoalCheck('睡眠', sleepMin != null && sleepMin >= sleepGoalHours * 60),
      GoalCheck('运动', exerciseMin.any((m) => m >= 10)),
      GoalCheck('用药', plannedSlots > 0 && takenSlots >= plannedSlots),
    ];

String goalRingTx(List<GoalCheck> cs) =>
    '${cs.where((c) => c.done).length}/${cs.length}';

/// hero 副行（原型 `goalSum`）：四项读数同一行。
String goalSummaryTx({
  required int cups,
  required double waterGoal,
  required int? sleepMin,
  required double sleepGoalHours,
  required int exerciseCount,
  required int plannedSlots,
  required int takenSlots,
}) {
  final sleepTx = sleepMin == null ? '—' : (sleepMin / 60).toStringAsFixed(1);
  return '喝水 $cups/${waterGoal.toStringAsFixed(0)} · '
      '睡眠 $sleepTx/${sleepGoalHours.toStringAsFixed(0)}h · '
      '运动 $exerciseCount 次 · '
      '用药 $takenSlots/${plannedSlots == 0 ? '未排' : '$plannedSlots 服'}';
}

/// 围度行读数＝「最近实测 / 目标」（原型 `gWaist`），两侧都可能没有＝两个「—」并出来，
/// 不拿 0 也不拿档表中点填。
String girthReadTx(double? measured, double? goal) =>
    '${measured == null ? '—' : measured.toStringAsFixed(0)} / '
    '${goal == null ? '—' : goal.toStringAsFixed(0)}';
