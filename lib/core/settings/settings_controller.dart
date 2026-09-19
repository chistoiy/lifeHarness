import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../nav/nav_module.dart';
import '../providers.dart';
import 'user_settings.dart';

/// 设置变更控制器（Riverpod 2 Notifier）。
///
/// 依赖 [settingsRepositoryProvider]（其底层 SharedPreferences 于 main 中 override 注入）。
class SettingsController extends Notifier<UserSettings> {
  /// 固定不可移除的底栏项。
  static const Set<NavModule> _pinned = {NavModule.today, NavModule.settings};
  static const int _maxNav = 5;

  @override
  UserSettings build() => ref.read(settingsRepositoryProvider).load();

  Future<void> setTheme(String themeId) async {
    if (themeId == state.themeId) return;
    state = state.copyWith(themeId: themeId);
    await _persist();
  }

  Future<void> setMode(ThemeModeOption mode) async {
    if (mode == state.mode) return;
    state = state.copyWith(mode: mode);
    await _persist();
  }

  /// 切换某栏目是否在底栏：固定项不可关；超出 5 个时拒绝并返回 false。
  Future<bool> toggleNav(NavModule module) async {
    final current = [...state.navIds];
    final present = current.contains(module.id);
    if (present && _pinned.contains(module)) return false; // 固定项不允许移除
    if (!present) {
      if (current.length >= _maxNav) return false; // 已达上限
      current.add(module.id);
    } else {
      current.remove(module.id);
    }
    state = state.copyWith(navIds: current);
    await _persist();
    return true;
  }

  Future<void> resetNav() async {
    state = state.copyWith(navIds: NavModule.defaultNav.map((m) => m.id).toList());
    await _persist();
  }

  Future<void> _persist() => ref.read(settingsRepositoryProvider).save(state);
}
