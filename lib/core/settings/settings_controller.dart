import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../nav/nav_collapse.dart';
import '../nav/nav_module.dart';
import '../providers.dart';
import 'user_settings.dart';

/// 底栏开关结果。
///
/// 为什么不是 `bool`：两种拒绝要提示**不同的话**（「最多 5 个」vs「今天/我的至少要留一个」），
/// 合成一个 false 会让 UI 只能瞎猜。2026-10-15 产品放开锚栏目后新增 [needAnchor]。
enum NavToggleResult {
  ok,

  /// 已达 5 个上限。
  maxReached,

  /// 「今天」「我的」至少要留一个（关完一个锚都不剩）。
  needAnchor,
}

/// 设置变更控制器（Riverpod 2 Notifier）。
///
/// 依赖 [settingsRepositoryProvider]（其底层 SharedPreferences 于 main 中 override 注入）。
class SettingsController extends Notifier<UserSettings> {
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

  /// 切换某栏目是否在底栏。
  ///
  /// 两条拒绝（2026-10-15 口径）：
  /// - 已满 5 个时再开 → [NavToggleResult.maxReached]；
  /// - 关掉后「今天」「我的」一个都不剩 → [NavToggleResult.needAnchor]。
  ///
  /// 锚栏目**不再**是「常开不可点」：可关其一，只要另一个还在。
  Future<NavToggleResult> toggleNav(NavModule module) async {
    final current = [...state.navIds];
    final present = current.contains(module.id);
    if (!present) {
      if (current.length >= _maxNav) return NavToggleResult.maxReached;
      current.add(module.id);
    } else {
      final left = current.where((id) => id != module.id);
      if (!left.any((id) => NavModule.fromId(id).isAnchor)) {
        return NavToggleResult.needAnchor;
      }
      current.remove(module.id);
    }
    state = state.copyWith(navIds: current);
    await _persist();
    return NavToggleResult.ok;
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

  /// V1.57 E 批 · 回收站自动清理期限（30/7/90 天 · 0=不清理，默认 30）。
  Future<void> setTrashKeepDays(int days) async {
    state = state.copyWith(trashKeepDays: days);
    await _persist();
  }

  /// 编辑页左右滑动切换上下篇（V1.29轮10-2·记录管理，默认关）。
  Future<void> setNoteSwipe(bool on) async {
    state = state.copyWith(noteSwipe: on);
    await _persist();
  }

  /// 批5③（2026-10-12）·笔记段筛选持久化：当前文件夹 / 排序键 / 方向**一次写回**
  /// （三档是一组状态，分三次 persist 会写三遍 prefs）。排序键未知值收敛 'updated'。
  Future<void> setNoteFilter(
      {required String folder, required String sort, required bool asc}) async {
    final s =
        const {'updated', 'created', 'title'}.contains(sort) ? sort : 'updated';
    if (folder == state.noteFolder &&
        s == state.noteSort &&
        asc == state.noteSortAsc) {
      return;
    }
    state = state.copyWith(noteFolder: folder, noteSort: s, noteSortAsc: asc);
    await _persist();
  }

  /// 批5③·笔记视图档（0=列表 / 2/3=卡片列数；越界收敛到 0）。同值不写盘。
  Future<void> setNoteViewCols(int cols) async {
    final v = const {0, 2, 3}.contains(cols) ? cols : 0;
    if (v == state.noteViewCols) return;
    state = state.copyWith(noteViewCols: v);
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

  /// V1.65·底栏手势总开关（双指张开＝收起底栏 / 捏合＝还原）。默认关；
  /// 关＝壳层整层手势不工作（不改变老用户行为）。
  Future<void> setNavGesture(bool on) async {
    if (on == state.navGestureOn) return;
    state = state.copyWith(navGestureOn: on);
    await _persist();
  }

  /// V1.65·收起后线索形态：'a' 细握把（默认）/ 'b' 胶囊折角 / 'none' 不画（2026-10-18）。
  /// 未知值收敛到 'a'（口径函数与 `fromMap` 共用 `navCueStyleOf`，禁两处各写一份）。
  Future<void> setNavLineStyle(String style) async {
    final v = navCueStyleOf(style);
    if (v == state.navLineStyle) return;
    state = state.copyWith(navLineStyle: v);
    await _persist();
  }

  /// V1.65·线索距屏幕底部（px）。越界值收敛到档位闭区间，界面不出现越界读数。
  Future<void> setNavLineGap(int gap) async {
    final v = gap.clamp(kNavLineGapMin, kNavLineGapMax);
    if (v == state.navLineGap) return;
    state = state.copyWith(navLineGap: v);
    await _persist();
  }

  /// 「我的」页版式（hero/chapters/minimal）。未知值收敛到默认 'hero'，
  /// 同值不写盘（与 setNavLineStyle 同口径）。
  Future<void> setMyLayout(String v) async {
    final lay = const {'hero', 'chapters', 'minimal'}.contains(v) ? v : 'hero';
    if (lay == state.myLayout) return;
    state = state.copyWith(myLayout: lay);
    await _persist();
  }

  /// 演示残留批（2026-10-12）·记录管理「默认新建模板」：三档循环
  /// （cycleRecSet：纯文本/KPT 复盘/晨间三问），脏值收敛 '纯文本'，同值不写盘。
  Future<void> setJournalDefaultTpl(String v) async {
    final t = const {'纯文本', 'KPT 复盘', '晨间三问'}.contains(v)
        ? v
        : '纯文本';
    if (t == state.journalDefaultTpl) return;
    state = state.copyWith(journalDefaultTpl: t);
    await _persist();
  }

  /// 语义断链批 #27（2026-10-12）·记录页日记段持久化：筛选键（'all'|'todo'|标签名，
  /// 空值收敛 'all'）与 INS 布局开关。同值不写盘。
  Future<void> setJournalFilter(String v) async {
    final f = v.trim().isEmpty ? 'all' : v.trim();
    if (f == state.journalFilter) return;
    state = state.copyWith(journalFilter: f);
    await _persist();
  }

  Future<void> setJournalIns(bool on) async {
    if (on == state.journalIns) return;
    state = state.copyWith(journalIns: on);
    await _persist();
  }

  /// 时间模块批1（C2/B9）：时间页月历展开态（true=展开·默认）。
  /// 用户手动切换时由时间页写入；切视图档不改它。
  Future<void> setCalMonthExpanded(bool on) async {
    if (on == state.calMonthExpanded) return;
    state = state.copyWith(calMonthExpanded: on);
    await _persist();
  }

  Future<void> _persist() => ref.read(settingsRepositoryProvider).save(state);
}
