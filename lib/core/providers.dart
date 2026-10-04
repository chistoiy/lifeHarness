import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backup/backup_service.dart';
import 'backup/db_overview.dart';
import 'media/media_usage_scanner.dart';
import 'host/event_bus.dart';
import 'host/mount_point.dart';
import 'host/module_registry.dart';
import 'nav/nav_module.dart';
import 'settings/settings_controller.dart';
import 'settings/settings_repository.dart';
import 'settings/user_settings.dart';
import 'theme/app_theme.dart';
import 'theme/theme_repository.dart';

export 'router/app_router.dart' show appRouterProvider;
export 'theme/theme_repository.dart' show ThemeBundle, ThemeRegistry;

/// 启动期一次性注入的 SharedPreferences 实例（main 中 override）。
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('需在 main 中 overrideWithValue'),
);

/// 全部主题的内存注册表（main 启动时加载并 override）。
final themeRegistryProvider = Provider<ThemeRegistry>(
  (ref) => throw UnimplementedError('需在 main 中 overrideWithValue'),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(sharedPreferencesProvider)),
);

/// 备份服务（V1.41 Task 10）：目录/库/prefs 在 main 组合根装配并
/// overrideWithValue；widget 测试注入 fake（如 /sync 半屏用例）。
final backupServiceProvider = Provider<BackupService>(
  (ref) => throw UnimplementedError('需在 main 中 overrideWithValue（测试注入 fake）'),
);

/// R5c 图片存储清理扫描器：媒体根目录/库在 main 组合根装配；
/// widget 测试注入 fake（真实 I/O 不进 widget 测试红线）。
final mediaScannerProvider = Provider<MediaUsageScanner>(
  (ref) =>
      throw UnimplementedError('需在 main 中 overrideWithValue（测试注入 fake）'),
);

/// B-4 数据库概览扫描器（工单 §7-3）：活库在 main 组合根装配；
/// widget 测试注入 fake（真实库扫描不进 widget 测试红线）。
final dbOverviewScannerProvider = Provider<DbOverviewScanner>(
  (ref) =>
      throw UnimplementedError('需在 main 中 overrideWithValue（测试注入 fake）'),
);

final settingsControllerProvider =
    NotifierProvider<SettingsController, UserSettings>(SettingsController.new);

/// 事件总线（应用级单例，随容器销毁自动 dispose）。
final eventBusProvider = Provider<EventBus>((ref) {
  final bus = EventBus();
  ref.onDispose(bus.dispose);
  return bus;
});

/// 当前主题包（仅随 themeId 变化重建）。
final currentThemeBundleProvider = Provider<ThemeBundle>((ref) {
  final registry = ref.watch(themeRegistryProvider);
  final id = ref.watch(settingsControllerProvider.select((s) => s.themeId));
  return registry.of(id);
});

/// 生效的 [ThemeMode]（forceDark 主题强制深色）。
final appThemeModeProvider = Provider<ThemeMode>((ref) {
  final bundle = ref.watch(currentThemeBundleProvider);
  if (bundle.forceDark) return ThemeMode.dark;
  switch (ref.watch(settingsControllerProvider.select((s) => s.mode))) {
    case ThemeModeOption.light:
      return ThemeMode.light;
    case ThemeModeOption.dark:
      return ThemeMode.dark;
    case ThemeModeOption.system:
      return ThemeMode.system;
  }
});

final lightThemeProvider = Provider<ThemeData>((ref) {
  final bundle = ref.watch(currentThemeBundleProvider);
  return AppTheme.build(bundle.light, isDark: false);
});

final darkThemeProvider = Provider<ThemeData>((ref) {
  final bundle = ref.watch(currentThemeBundleProvider);
  return AppTheme.build(bundle.dark, isDark: true);
});

/// 宿主模块注册表（内置模块启动注册，供挂载点解析）。
final moduleRegistryProvider = Provider<ModuleRegistry>((ref) {
  final reg = ModuleRegistry();
  for (final m in NavModule.values) {
    reg.register(HostModule(
      id: m.id,
      title: m.label,
      routePath: m.path,
      mount: {MountPoint.navSlot: m.index},
    ));
  }
  return reg;
});
