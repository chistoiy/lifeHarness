import 'package:shared_preferences/shared_preferences.dart';

/// 健康模块设置项（键名/默认/生效点＝《开发计划》§六，一张表看全，别在 UI 里散落字符串）。
///
/// 两条纪律：
/// · **单位只影响展示与输入**，存储恒公制（§五.10），所以这里存的 kg/km 不参与任何换算；
/// · 两个提醒时刻（`daily_summary_at`/`weight_remind_at`）**先存不排程**——排程接线在批8，
///   本文件只保证「设了就当场落库、读得回来」，不冒充已排程。
class HealthSettings {
  HealthSettings(this._prefs);

  final SharedPreferences _prefs;

  static const kWaterGoal = 'health.water_goal'; // 杯
  static const kCupMl = 'health.cup_ml';
  static const kSleepGoal = 'health.sleep_goal'; // 小时
  static const kBedLine = 'health.bed_line'; // HH:mm
  static const kWeekExGoal = 'health.week_ex_goal'; // 次/周
  static const kKgUnit = 'health.kg_unit'; // kg | 斤
  static const kKmUnit = 'health.km_unit'; // km | mile
  static const kStageLog = 'health.stage_log'; // 睡眠分期是否录入
  static const kMissedGrace = 'health.missed_grace_min';
  static const kDailySummaryAt = 'health.daily_summary_at';
  static const kWeightRemindAt = 'health.weight_remind_at';
  static const kShowDashCard = 'health.show_dash_card';
  static const kFabQuickWater = 'health.fab_quick_water'; // 延后项，键先占位
  static const kIncludeInBackup = 'health.include_in_backup';
  static const kActiveProfile = 'health.active_profile';
  static const kSymNames = 'health.sym_names'; // 批3.5a 常用症状自定义名单（种子十枚在域层）

  /// 默认值（与需求清单模块 12 逐项对齐；围度目标无默认＝未设）。
  static const defaults = <String, Object>{
    kWaterGoal: 8,
    kCupMl: 250,
    kSleepGoal: 8,
    kBedLine: '23:30',
    kWeekExGoal: 3,
    kKgUnit: 'kg',
    kKmUnit: 'km',
    kStageLog: false,
    kMissedGrace: 30,
    kDailySummaryAt: '21:30',
    kWeightRemindAt: '08:00',
    kShowDashCard: true,
    kFabQuickWater: true,
    kIncludeInBackup: true,
    kActiveProfile: 1,
  };

  int waterGoal() => _prefs.getInt(kWaterGoal) ?? defaults[kWaterGoal] as int;
  int cupMl() => _prefs.getInt(kCupMl) ?? defaults[kCupMl] as int;
  int sleepGoalHours() => _prefs.getInt(kSleepGoal) ?? defaults[kSleepGoal] as int;
  String bedLine() => _prefs.getString(kBedLine) ?? defaults[kBedLine] as String;
  int weekExGoal() => _prefs.getInt(kWeekExGoal) ?? defaults[kWeekExGoal] as int;
  String kgUnit() => _prefs.getString(kKgUnit) ?? defaults[kKgUnit] as String;
  String kmUnit() => _prefs.getString(kKmUnit) ?? defaults[kKmUnit] as String;
  bool stageLog() => _prefs.getBool(kStageLog) ?? defaults[kStageLog] as bool;
  int missedGraceMin() => _prefs.getInt(kMissedGrace) ?? defaults[kMissedGrace] as int;
  String dailySummaryAt() => _prefs.getString(kDailySummaryAt) ?? defaults[kDailySummaryAt] as String;
  String weightRemindAt() => _prefs.getString(kWeightRemindAt) ?? defaults[kWeightRemindAt] as String;
  bool showDashCard() => _prefs.getBool(kShowDashCard) ?? defaults[kShowDashCard] as bool;
  bool includeInBackup() => _prefs.getBool(kIncludeInBackup) ?? defaults[kIncludeInBackup] as bool;
  int activeProfileId() => _prefs.getInt(kActiveProfile) ?? defaults[kActiveProfile] as int;

  /// 自定义症状名（种子十枚固定在 `domain/health_symptom.dart`，这里只装用户加的）。
  List<String> symCustomNames() => _prefs.getStringList(kSymNames) ?? const [];

  Future<void> setWaterGoal(int v) => _prefs.setInt(kWaterGoal, v);
  Future<void> setCupMl(int v) => _prefs.setInt(kCupMl, v);
  Future<void> setSleepGoal(int v) => _prefs.setInt(kSleepGoal, v);
  Future<void> setBedLine(String v) => _prefs.setString(kBedLine, v);
  Future<void> setWeekExGoal(int v) => _prefs.setInt(kWeekExGoal, v);
  Future<void> setKgUnit(String v) => _prefs.setString(kKgUnit, v);
  Future<void> setKmUnit(String v) => _prefs.setString(kKmUnit, v);
  Future<void> setStageLog(bool v) => _prefs.setBool(kStageLog, v);
  Future<void> setMissedGrace(int v) => _prefs.setInt(kMissedGrace, v);
  Future<void> setDailySummaryAt(String v) => _prefs.setString(kDailySummaryAt, v);
  Future<void> setWeightRemindAt(String v) => _prefs.setString(kWeightRemindAt, v);
  Future<void> setShowDashCard(bool v) => _prefs.setBool(kShowDashCard, v);
  Future<void> setIncludeInBackup(bool v) => _prefs.setBool(kIncludeInBackup, v);
  Future<void> setActiveProfileId(int v) => _prefs.setInt(kActiveProfile, v);
  Future<void> setSymCustomNames(List<String> v) => _prefs.setStringList(kSymNames, v);

  /// 一杯折多少毫升（展示与导出用；库内永远只有杯数）。
  int waterMl(int cups) => cups * cupMl();
}
