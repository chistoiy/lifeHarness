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

/// 用户可变设置快照（主题 / 深色模式 / 底部导航）。
///
/// 骨架阶段持久化用 shared_preferences 模拟；正式版换 settings 表并随备份策略
/// （ADR D11：原型与两环境实现差异抽象为存储接口层）。
class UserSettings {
  const UserSettings({
    required this.themeId,
    required this.mode,
    required this.navIds,
  });

  final String themeId;
  final ThemeModeOption mode;
  final List<String> navIds;

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
  }) =>
      UserSettings(
        themeId: themeId ?? this.themeId,
        mode: mode ?? this.mode,
        navIds: navIds ?? this.navIds,
      );

  Map<String, Object> toMap() => {
        'themeId': themeId,
        'mode': mode.id,
        'navIds': navIds.join(','),
      };

  factory UserSettings.fromMap(Map<String, Object?> m) => UserSettings(
        themeId: m['themeId'] as String? ?? defaults.themeId,
        mode: ThemeModeOption.fromId(m['mode'] as String?),
        navIds: (m['navIds'] as String?)?.split(',').where((s) => s.isNotEmpty).toList() ??
            defaults.navIds,
      );
}
