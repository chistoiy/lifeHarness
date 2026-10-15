import 'package:shared_preferences/shared_preferences.dart';

import '../platform/desktop_actions.dart';
import 'user_settings.dart';

/// 默认 4 枚（转发动作表，避免本仓出现第二份「默认」定义）。
List<String> defaultDesktopMenuIds() =>
    List<String>.from(kDefaultMenuActionIds);

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

  // ===== 桌面模块批1（2026-10-15 · 冻结档 §2.1 F1-6）=====
  // 三键：长按菜单勾选（逗号分隔动作 id）/ 铺到桌面已铺（同样逗号分隔）/ 小组件两开关＋隐藏金额。
  // ⚠ **独立于 UserSettings**：桌面偏好不进「口径设置整包导出」（备份口径不含桌面入口，
  //   换机后按默认 4 枚重建即可），故走独立读写口，**不动既有键**。
  static const String kDeskMenuKey = 'desktop.menu';
  static const String kDeskPinnedKey = 'desktop.pinned';
  static const String kDeskWidgetSummaryKey = 'desktop.widget_summary';
  static const String kDeskWidgetQuickKey = 'desktop.widget_quick';
  static const String kDeskHideAmountKey = 'desktop.hide_amount';

  /// 批3 · 两枚新2×2 的「是否添加这枚」总开关。
  static const String kDeskWidgetTodoListKey = 'desktop.widget_todo_list';
  static const String kDeskWidgetLedgerKey = 'desktop.widget_ledger';

  /// 批3 · 勾圈闭环的补写队列（原生写库失败时暂存，App 启动时排空）。
  static const String kDeskPendingTogglesKey = 'desktop.widget_pending_toggles';

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

  /// 演示残留批（2026-10-12）·记录管理「默认新建模板」（模板名，'纯文本'=自由书写）。
  static const _kJournalDefTpl = 'lh.journal_default_tpl';

  /// 语义断链批 #27（2026-10-12）·记录页日记段持久化：筛选键 / INS 布局。
  static const _kJournalFilter = 'lh.journal_filter';
  static const _kJournalIns = 'lh.journal_ins';

  /// 时间模块批1（2026-10-13）·C2/B9：时间页月历展开态（true=展开·默认）。
  /// 首次进模块默认展开；用户手动切换后持久化（跨会话记住）；与视图档解耦。
  static const _kCalMonthExpanded = 'lh.cal_month_expanded';

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
        _prefs.getString(_kMyLayout) == null &&
        _prefs.getString(_kJournalDefTpl) == null &&
        _prefs.getString(_kJournalFilter) == null &&
        _prefs.getBool(_kJournalIns) == null &&
        _prefs.getBool(_kCalMonthExpanded) == null) {
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
      'journalDefaultTpl': ?_prefs.getString(_kJournalDefTpl),
      'journalFilter': ?_prefs.getString(_kJournalFilter),
      'journalIns': ?_prefs.getBool(_kJournalIns),
      'calMonthExpanded': ?_prefs.getBool(_kCalMonthExpanded),
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
    await _prefs.setString(_kJournalDefTpl, m['journalDefaultTpl']! as String);
    await _prefs.setString(_kJournalFilter, m['journalFilter']! as String);
    await _prefs.setBool(_kJournalIns, m['journalIns']! as bool);
    await _prefs.setBool(_kCalMonthExpanded, m['calMonthExpanded']! as bool);
  }

  /// V1.66 批2 · 口径设置整包导出（备份包 `config/settings.json` 的唯一来源）。
  ///
  /// 形状 = [UserSettings.toMap]（全口径字段、扁平 JSON 值）。**凭据绝不在此
  /// 层**：云 token/应用密码存系统加密保险箱，本仓 never 持有——本方法天然
  /// 去凭据，无需额外剔除逻辑（评估件 §五·4 口径）。
  Map<String, Object?> exportAll() => load().toMap();

  /// 口径设置整包导入（恢复链 `config/settings.json` 的落点）。
  ///
  /// 缺键由 [UserSettings.fromMap] 走 defaults 兜底；未知键忽略（跨版本
  /// 前向兼容）。不触碰「有用户配置」判据之外的 prefs 键（备份提示串等
  /// 运行态不入此通道）。
  Future<void> importAll(Map<String, Object?> m) => save(UserSettings.fromMap(m));

  // ===== 桌面模块批1（2026-10-15）· 桌面偏好独立读写口 =====
  //
  // 为什么不进 [UserSettings]：口径设置整包导出（备份 `config/settings.json`）
  // 是「业务口径」，桌面入口属设备能力偏好，换机后按默认 4 枚重建即可，
  // 进备份反而会让旧机布局污染新机。故**独立于 UserSettings，只加 desktop.* 键，
  // 不动既有键**（冻结档 §6.1）。

  /// 长按菜单勾选的动作 id（最多 [kMenuMax] 枚；空/缺键回落默认 4 枚）。
  ///
  /// 读回时做两道护栏：**去重** ＋ **截断到 4**（老版本或外部写入越界都不炸）。
  List<String> loadDesktopMenu() {
    final raw = _prefs.getString(kDeskMenuKey);
    if (raw == null || raw.isEmpty) return defaultDesktopMenuIds();
    final ids = raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return defaultDesktopMenuIds();
    return ids.take(kMenuMax).toList();
  }

  Future<void> saveDesktopMenu(List<String> ids) =>
      _prefs.setString(kDeskMenuKey, ids.take(kMenuMax).join(','));

  /// 已铺到桌面的动作 id（不限量；与菜单勾选互不影响）。
  Set<String> loadDesktopPinned() {
    final raw = _prefs.getString(kDeskPinnedKey);
    if (raw == null || raw.isEmpty) return <String>{};
    return raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  Future<void> saveDesktopPinned(Set<String> ids) =>
      _prefs.setString(kDeskPinnedKey, (ids.toList()..sort()).join(','));

  /// 2×2 今日概览小组件开关（默认开）。
  bool loadDesktopWidgetSummary() =>
      _prefs.getBool(kDeskWidgetSummaryKey) ?? true;
  Future<void> saveDesktopWidgetSummary(bool v) =>
      _prefs.setBool(kDeskWidgetSummaryKey, v);

  /// 4×1 快捷记录小组件开关（默认开）。
  bool loadDesktopWidgetQuick() =>
      _prefs.getBool(kDeskWidgetQuickKey) ?? true;
  Future<void> saveDesktopWidgetQuick(bool v) =>
      _prefs.setBool(kDeskWidgetQuickKey, v);

  /// 隐藏金额（B7/C8：开启时小组件金额位显示为 ••••，不泄露到桌面）。默认关。
  bool loadDesktopHideAmount() => _prefs.getBool(kDeskHideAmountKey) ?? false;
  Future<void> saveDesktopHideAmount(bool v) =>
      _prefs.setBool(kDeskHideAmountKey, v);

  /// 2×2 待办清单小组件开关（批3 · 默认开）。
  bool loadDesktopWidgetTodoList() =>
      _prefs.getBool(kDeskWidgetTodoListKey) ?? true;
  Future<void> saveDesktopWidgetTodoList(bool v) =>
      _prefs.setBool(kDeskWidgetTodoListKey, v);

  /// 2×2 记账概览小组件开关（批3 · 默认开）。
  bool loadDesktopWidgetLedger() => _prefs.getBool(kDeskWidgetLedgerKey) ?? true;
  Future<void> saveDesktopWidgetLedger(bool v) =>
      _prefs.setBool(kDeskWidgetLedgerKey, v);

  // ---- 待办勾圈的补写队列（原生 [TodoActionReceiver] 写库失败时的兜底）----
  //
  // 桌面点勾圈是在**原生广播**里直接 UPDATE sqlite 的；若那一刻 App 没起过、
  // 或库被 sqflite 独占，写入会失败。此时 Receiver 把 id 存进
  // `desktop.widget_pending_toggles`，等 App 下次启动排空补写 ⇒ 闭环最终一致。
  // ⚠ 键名与原生 `LhWidget.PREF_PENDING_TOGGLES` 逐字一致（守护测试交叉核对）。

  List<int> loadDesktopPendingToggles() => (_prefs.getString(kDeskPendingTogglesKey) ?? '')
      .split(',')
      .map((e) => int.tryParse(e.trim()))
      .whereType<int>()
      .where((id) => id > 0)
      .toSet()
      .toList();

  Future<void> saveDesktopPendingToggles(List<int> ids) => _prefs.setString(
        kDeskPendingTogglesKey,
        ids.isEmpty ? '' : (ids.toSet().toList()..sort()).join(','),
      );
}
