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

  /// 主页卡片自由编排顺序（M0末C；仪表盘「⇄ 编排」保存时写入）。
  Future<void> setHomeOrder(List<String> order) async {
    state = state.copyWith(homeCardOrder: order);
    await _persist();
  }

  /// 笔记快照恢复方式（V1.29 记录管理）：'replace' ⇄ 'copy'。
  Future<void> setNoteRestoreMode(String mode) async {
    state = state.copyWith(noteRestoreMode: mode);
    await _persist();
  }

  /// MD 预览 LaTeX 公式渲染（V1.29轮9k·记录管理，默认关）。
  Future<void> setNoteLatex(bool on) async {
    state = state.copyWith(noteLatex: on);
    await _persist();
  }

  /// 纯文本行号（V1.29轮9p·笔记⋯弹层，仅 kind=plain，默认关）。
  Future<void> setNotePlainLineNum(bool on) async {
    state = state.copyWith(notePlainLineNum: on);
    await _persist();
  }

  /// 编辑页左右滑动切换上下篇（V1.29轮10-2·记录管理，默认关）。
  Future<void> setNoteSwipe(bool on) async {
    state = state.copyWith(noteSwipe: on);
    await _persist();
  }

  /// 日记天气城市（M1批2e·设置页一次选定；编码 `name|lat|lon`，''=未设置）。
  Future<void> setWeatherCity(String city) async {
    state = state.copyWith(weatherCity: city);
    await _persist();
  }

  /// 我的页资料（R14-12）：昵称 + 一句话签名。只进设置项 KV，不建表不迁移；
  /// 头像首字、页面副标题与「今天」页问候语都随这一份数据联动。
  Future<void> setProfile({required String nick, required String bio}) async {
    state = state.copyWith(profileNick: nick, profileBio: bio);
    await _persist();
  }

  /// 提醒通知设置（M0末A）。副作用（权限申请/排程同步）由 settings feature 层执行，
  /// core 不触达 feature（R2）。
  Future<void> setNotify(NotifySettings n) async {
    state = state.copyWith(notify: n);
    await _persist();
  }

  /// V1.47 批1 · 小工具合集模块开关（原型 sheetKitSet）。
  /// 只落 prefs（kit 四项属偏好）；足迹/收藏/编排/插件登记走 kit_* 表。
  Future<void> setKit(KitSettings k) async {
    state = state.copyWith(kit: k);
    await _persist();
  }

  Future<void> _persist() => ref.read(settingsRepositoryProvider).save(state);
}
