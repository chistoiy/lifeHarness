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

  /// 批5③（2026-10-12）·笔记段筛选/视图持久化（文件夹 / 排序键 / 方向 / 视图档）。
  static const _kNoteFolder = 'lh.note_folder';
  static const _kNoteSort = 'lh.note_sort';
  static const _kNoteSortAsc = 'lh.note_sort_asc';
  static const _kNoteViewCols = 'lh.note_view_cols';

  static const _kWeatherCity = 'lh.weather_city';

  /// R14-12·我的页资料（本地模式无账号：昵称/签名只是偏好，不建表、不进业务备份口径）。
  static const _kProfileNick = 'lh.profile_nick';
  static const _kProfileBio = 'lh.profile_bio';


  /// V1.57 批E·回收站自动清理期限（天；0=不清理）。垃圾箱屏与待办页入口行同源读它。
  static const _kTrashKeep = 'lh.trash_keep_days';

  /// V1.65·底栏手势：总开关（默认关）/ 线索形态 'a'|'b' / 线索距底 px。
  static const _kNavGestureOn = 'lh.nav_gesture_on';
  static const _kNavLineStyle = 'lh.nav_line_style';
  static const _kNavLineGap = 'lh.nav_line_gap';

  /// 「我的」页版式（2026-10-12）：'hero'|'chapters'|'minimal'，默认 hero。
  static const _kMyLayout = 'lh.my_layout';

  /// 同步读取（[SharedPreferences] 已在启动时一次性加载，getter 同步返回）。
  UserSettings load() {
    // V1.58 小工具整模块下架：历史遗留 lh.kit（四项模块开关）读到即清，
    // 不留「有用户配置」假信号（照 care.rm.lock 先例）。
    if (_prefs.containsKey('lh.kit')) _prefs.remove('lh.kit');
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
        _prefs.getString(_kNoteFolder) == null &&
        _prefs.getString(_kNoteSort) == null &&
        _prefs.getBool(_kNoteSortAsc) == null &&
        _prefs.getInt(_kNoteViewCols) == null &&
        _prefs.getString(_kWeatherCity) == null &&
        _prefs.getString(_kProfileNick) == null &&
        _prefs.getInt(_kTrashKeep) == null &&
        _prefs.getBool(_kNavGestureOn) == null &&
        _prefs.getString(_kNavLineStyle) == null &&
        _prefs.getInt(_kNavLineGap) == null &&
        _prefs.getString(_kMyLayout) == null) {
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
      'noteFolder': ?_prefs.getString(_kNoteFolder),
      'noteSort': ?_prefs.getString(_kNoteSort),
      'noteSortAsc': ?_prefs.getBool(_kNoteSortAsc),
      'noteViewCols': ?_prefs.getInt(_kNoteViewCols),
      'weatherCity': ?_prefs.getString(_kWeatherCity),
      'profileNick': ?_prefs.getString(_kProfileNick),
      'profileBio': ?_prefs.getString(_kProfileBio),
      'trashKeepDays': ?_prefs.getInt(_kTrashKeep),
      'navGestureOn': ?_prefs.getBool(_kNavGestureOn),
      'navLineStyle': ?_prefs.getString(_kNavLineStyle),
      'navLineGap': ?_prefs.getInt(_kNavLineGap),
      'myLayout': ?_prefs.getString(_kMyLayout),
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
    await _prefs.setString(_kNoteFolder, m['noteFolder']! as String);
    await _prefs.setString(_kNoteSort, m['noteSort']! as String);
    await _prefs.setBool(_kNoteSortAsc, m['noteSortAsc']! as bool);
    await _prefs.setInt(_kNoteViewCols, m['noteViewCols']! as int);
    await _prefs.setString(_kWeatherCity, m['weatherCity']! as String);
    await _prefs.setString(_kProfileNick, m['profileNick']! as String);
    await _prefs.setString(_kProfileBio, m['profileBio']! as String);
    await _prefs.setInt(_kTrashKeep, m['trashKeepDays']! as int);
    await _prefs.setBool(_kNavGestureOn, m['navGestureOn']! as bool);
    await _prefs.setString(_kNavLineStyle, m['navLineStyle']! as String);
    await _prefs.setInt(_kNavLineGap, m['navLineGap']! as int);
    await _prefs.setString(_kMyLayout, m['myLayout']! as String);
  }
}
