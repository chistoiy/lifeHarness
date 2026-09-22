import 'dart:convert';

import '../nav/nav_module.dart';

/// 深色模式偏好（与主题风格正交，可叠加）。
enum ThemeModeOption {
  system('system'),
  light('light'),
  dark('dark');

  const ThemeModeOption(this.id);
  final String id;

  static ThemeModeOption fromId(String? id) => ThemeModeOption.values
      .firstWhere((e) => e.id == id, orElse: () => ThemeModeOption.system);
}

/// 提醒通知设置（原型 p-sub-notify；M0末A：待办提醒/收集箱整理/日记复盘真实排程，
/// 习惯提醒与免打扰为存储位生效在后续里程碑）。
class NotifySettings {
  const NotifySettings({
    this.todoEvent = true,
    this.leadMin = 10,
    this.overdueEscalate = true,
    this.diaryReview = false,
    this.diaryTime = '21:30',
    this.inboxClean = false,
    this.habits = false,
    this.dnd = false,
  });

  /// 📅 日程与任务提醒总开关（待办 remind_at 排程随此开关）。
  final bool todoEvent;

  /// 默认提前量（分钟；M0 存位，日程事件提醒接入后生效）。
  final int leadMin;

  /// 逾期任务升级提醒（B 批建议卡联动）。
  final bool overdueEscalate;

  /// 📔 日记复盘提醒（每日 diaryTime）。
  final bool diaryReview;
  final String diaryTime;

  /// ⚡ 收集箱清理提醒（每天 21:00）。
  final bool inboxClean;

  /// 🔁 习惯提醒（习惯模块 M1 前为存位）。
  final bool habits;

  /// ⛔ 免打扰时段（23:00–07:00 固定存位，穿透策略 M2）。
  final bool dnd;

  bool get anyDailyOn => diaryReview || inboxClean;

  NotifySettings copyWith({
    bool? todoEvent,
    int? leadMin,
    bool? overdueEscalate,
    bool? diaryReview,
    String? diaryTime,
    bool? inboxClean,
    bool? habits,
    bool? dnd,
  }) =>
      NotifySettings(
        todoEvent: todoEvent ?? this.todoEvent,
        leadMin: leadMin ?? this.leadMin,
        overdueEscalate: overdueEscalate ?? this.overdueEscalate,
        diaryReview: diaryReview ?? this.diaryReview,
        diaryTime: diaryTime ?? this.diaryTime,
        inboxClean: inboxClean ?? this.inboxClean,
        habits: habits ?? this.habits,
        dnd: dnd ?? this.dnd,
      );

  Map<String, Object?> toMap() => {
        'todoEvent': todoEvent,
        'leadMin': leadMin,
        'overdueEscalate': overdueEscalate,
        'diaryReview': diaryReview,
        'diaryTime': diaryTime,
        'inboxClean': inboxClean,
        'habits': habits,
        'dnd': dnd,
      };

  factory NotifySettings.fromMap(Map<String, Object?> m) => NotifySettings(
        todoEvent: m['todoEvent'] as bool? ?? true,
        leadMin: m['leadMin'] as int? ?? 10,
        overdueEscalate: m['overdueEscalate'] as bool? ?? true,
        diaryReview: m['diaryReview'] as bool? ?? false,
        diaryTime: m['diaryTime'] as String? ?? '21:30',
        inboxClean: m['inboxClean'] as bool? ?? false,
        habits: m['habits'] as bool? ?? false,
        dnd: m['dnd'] as bool? ?? false,
      );
}

/// 用户可变设置快照（主题 / 深色模式 / 底部导航 / 提醒通知 / 主页卡片顺序）。
///
/// 骨架阶段持久化用 shared_preferences 模拟；正式版换 settings 表并随备份策略
/// （ADR D11：原型与两环境实现差异抽象为存储接口层）。
class UserSettings {
  const UserSettings({
    required this.themeId,
    required this.mode,
    required this.navIds,
    this.notify = const NotifySettings(),
    this.homeCardOrder = kHomeCardIds,
    this.noteRestoreMode = 'replace',
    this.noteLatex = false,
    this.notePlainLineNum = false,
    this.noteSwipe = false,
  });

  final String themeId;
  final ThemeModeOption mode;
  final List<String> navIds;
  final NotifySettings notify;

  /// 主页卡片顺序（原型 DASH_IDS；M0末C 自由编排持久化）。
  final List<String> homeCardOrder;

  /// 笔记快照恢复方式（V1.29轮1·记录管理）：
  /// replace=直接替换当前正文（替换前自动留快照）· copy=新增为副本笔记。
  final String noteRestoreMode;

  /// V1.29轮9k·记录管理：MD 预览 LaTeX 公式渲染开关（默认关=按原文显示 $..$/$$..$$）。
  final bool noteLatex;

  /// V1.29轮9p·笔记⋯弹层：纯文本行号开关（仅 kind=plain 生效，默认关）。
  final bool notePlainLineNum;

  /// V1.29轮10-2·记录管理：编辑页左右滑动切换上下篇开关（默认关=轮8②常开改为可选）。
  final bool noteSwipe;

  /// 可编排卡片 id 全集（顺序之外新增卡片按此兜底补齐）。
  static const List<String> kHomeCardIds = [
    'greeting',
    'mood',
    'events',
    'inboxBar',
    'chart',
    'grid',
  ];

  List<NavModule> get navModules => navIds.map(NavModule.fromId).toList();

  static const UserSettings defaults = UserSettings(
    themeId: 'minimal',
    mode: ThemeModeOption.system,
    // 今天/我的固定，中间三个可切换栏目（最多 5，需求 V1.5）。
    navIds: ['today', 'todo', 'calendar', 'journal', 'settings'],
  );

  UserSettings copyWith({
    String? themeId,
    ThemeModeOption? mode,
    List<String>? navIds,
    NotifySettings? notify,
    List<String>? homeCardOrder,
    String? noteRestoreMode,
    bool? noteLatex,
    bool? notePlainLineNum,
    bool? noteSwipe,
  }) =>
      UserSettings(
        themeId: themeId ?? this.themeId,
        mode: mode ?? this.mode,
        navIds: navIds ?? this.navIds,
        notify: notify ?? this.notify,
        homeCardOrder: homeCardOrder ?? this.homeCardOrder,
        noteRestoreMode: noteRestoreMode ?? this.noteRestoreMode,
        noteLatex: noteLatex ?? this.noteLatex,
        notePlainLineNum: notePlainLineNum ?? this.notePlainLineNum,
        noteSwipe: noteSwipe ?? this.noteSwipe,
      );

  Map<String, Object> toMap() => {
        'themeId': themeId,
        'mode': mode.id,
        'navIds': navIds.join(','),
        'notify': jsonEncode(notify.toMap()),
        'homeOrder': homeCardOrder.join(','),
        'noteRestoreMode': noteRestoreMode,
        'noteLatex': noteLatex,
        'notePlainLineNum': notePlainLineNum,
        'noteSwipe': noteSwipe,
      };

  factory UserSettings.fromMap(Map<String, Object?> m) => UserSettings(
        themeId: m['themeId'] as String? ?? defaults.themeId,
        mode: ThemeModeOption.fromId(m['mode'] as String?),
        navIds: (m['navIds'] as String?)?.split(',').where((s) => s.isNotEmpty).toList() ??
            defaults.navIds,
        notify: _decodeNotify(m['notify'] as String?),
        homeCardOrder: _sanitizeHomeOrder(m['homeOrder'] as String?),
        noteRestoreMode:
            (m['noteRestoreMode'] as String?) == 'copy' ? 'copy' : 'replace',
        noteLatex: m['noteLatex'] as bool? ?? false,
        notePlainLineNum: m['notePlainLineNum'] as bool? ?? false,
        noteSwipe: m['noteSwipe'] as bool? ?? false,
      );

  /// 校验存储顺序：剔除未知 id、补齐缺失卡片（版本升级新增卡自动排尾部）。
  static List<String> _sanitizeHomeOrder(String? raw) {
    if (raw == null || raw.isEmpty) return kHomeCardIds;
    final saved =
        raw.split(',').where(kHomeCardIds.contains).toList().toSet();
    final missing = kHomeCardIds.where((id) => !saved.contains(id));
    return [...saved, ...missing];
  }

  static NotifySettings _decodeNotify(String? raw) {
    if (raw == null || raw.isEmpty) return const NotifySettings();
    try {
      return NotifySettings.fromMap(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return const NotifySettings();
    }
  }
}
