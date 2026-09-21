import 'package:shared_preferences/shared_preferences.dart';

import 'user_settings.dart';

/// 基于 shared_preferences 的设置存取（骨架阶段的存储接口层）。
class SettingsRepository {
  const SettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _kTheme = 'lh.theme_id';
  static const _kMode = 'lh.theme_mode';
  static const _kNav = 'lh.nav_ids';
  static const _kNotify = 'lh.notify';
  static const _kHomeOrder = 'lh.home_order';
  static const _kNoteRestore = 'lh.note_restore_mode';

  /// 同步读取（[SharedPreferences] 已在启动时一次性加载，getter 同步返回）。
  UserSettings load() {
    final themeId = _prefs.getString(_kTheme);
    final mode = _prefs.getString(_kMode);
    final nav = _prefs.getString(_kNav);
    if (themeId == null && mode == null && nav == null) {
      return UserSettings.defaults;
    }
    return UserSettings.fromMap({
      'themeId': ?themeId,
      'mode': ?mode,
      'navIds': ?nav,
      'notify': ?_prefs.getString(_kNotify),
      'homeOrder': ?_prefs.getString(_kHomeOrder),
      'noteRestoreMode': ?_prefs.getString(_kNoteRestore),
    });
  }

  Future<void> save(UserSettings s) async {
    final m = s.toMap();
    await _prefs.setString(_kTheme, m['themeId']! as String);
    await _prefs.setString(_kMode, m['mode']! as String);
    await _prefs.setString(_kNav, m['navIds']! as String);
    await _prefs.setString(_kNotify, m['notify']! as String);
    await _prefs.setString(_kHomeOrder, m['homeOrder']! as String);
    await _prefs.setString(_kNoteRestore, m['noteRestoreMode']! as String);
  }
}
