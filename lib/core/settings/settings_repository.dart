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
  static const _kNoteLatex = 'lh.note_latex';
  static const _kNoteLineNum = 'lh.note_plain_linenum';
  static const _kNoteSwipe = 'lh.note_swipe';
  static const _kWeatherCity = 'lh.weather_city';

  /// R14-12·我的页资料（本地模式无账号：昵称/签名只是偏好，不建表、不进业务备份口径）。
  static const _kProfileNick = 'lh.profile_nick';
  static const _kProfileBio = 'lh.profile_bio';

  /// V1.47 批1·小工具合集模块开关（四项一 JSON，与 notify 同构）。
  static const _kKit = 'lh.kit';

  /// 同步读取（[SharedPreferences] 已在启动时一次性加载，getter 同步返回）。
  UserSettings load() {
    final themeId = _prefs.getString(_kTheme);
    final mode = _prefs.getString(_kMode);
    final nav = _prefs.getString(_kNav);
    final latex = _prefs.getBool(_kNoteLatex);
    // 轮10：任一独立开关位已落盘即视为有用户配置，防单键设置被 defaults 吞掉。
    if (themeId == null &&
        mode == null &&
        nav == null &&
        latex == null &&
        _prefs.getBool(_kNoteLineNum) == null &&
        _prefs.getBool(_kNoteSwipe) == null &&
        _prefs.getString(_kWeatherCity) == null &&
        _prefs.getString(_kProfileNick) == null &&
        _prefs.getString(_kKit) == null) {
      return UserSettings.defaults;
    }
    return UserSettings.fromMap({
      'themeId': ?themeId,
      'mode': ?mode,
      'navIds': ?nav,
      'notify': ?_prefs.getString(_kNotify),
      'homeOrder': ?_prefs.getString(_kHomeOrder),
      'noteRestoreMode': ?_prefs.getString(_kNoteRestore),
      'noteLatex': ?_prefs.getBool(_kNoteLatex),
      'notePlainLineNum': ?_prefs.getBool(_kNoteLineNum),
      'noteSwipe': ?_prefs.getBool(_kNoteSwipe),
      'weatherCity': ?_prefs.getString(_kWeatherCity),
      'profileNick': ?_prefs.getString(_kProfileNick),
      'profileBio': ?_prefs.getString(_kProfileBio),
      'kit': ?_prefs.getString(_kKit),
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
    await _prefs.setBool(_kNoteLatex, m['noteLatex']! as bool);
    await _prefs.setBool(_kNoteLineNum, m['notePlainLineNum']! as bool);
    await _prefs.setBool(_kNoteSwipe, m['noteSwipe']! as bool);
    await _prefs.setString(_kWeatherCity, m['weatherCity']! as String);
    await _prefs.setString(_kProfileNick, m['profileNick']! as String);
    await _prefs.setString(_kProfileBio, m['profileBio']! as String);
    await _prefs.setString(_kKit, m['kit']! as String);
  }
}
