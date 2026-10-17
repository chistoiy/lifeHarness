/// 小组件模块 批A · 按实例绑定存储（工单 §2 绑定层 · 评估件 §2.3 层3）。
///
/// 规格＝docs/handoff/小组件模块-批A按实例绑定与打卡试点.md §0 ③/§2。
///
/// **存储形态**：SharedPreferences 映射，**键带桌面实例 id**（一实例一键），
/// 外加一枚全局默认键（老实例回落）。**不动 DB schema、不进备份**（工单 §0 ③：
/// 跨设备同步本轮不做；桌面偏好与 `desktop.*` 同口径独立于口径设置整包导出）。
///
/// **为什么一实例一键而不是单键大 map**：原生 Provider 只读自己那一枚
/// （`onUpdate` 时按 appWidgetId 直取，零解析整表）；实例删除回收＝删自己
/// 那一枚（`onDeleted` 原生侧删键，Dart 侧 [prune] 双保险）。
///
/// **键前缀口径**：Dart 侧 `desktop.widget_bind.<id>`（无 `flutter.` 前缀，
/// shared_preferences 插件自行加）；原生侧读 `FlutterSharedPreferences` 时
/// 带 `flutter.` 前缀——与 `LhWidget.FLUTTER_KEY_PREFIX` 同口径。
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/widget_binding.dart';

/// 按实例绑定的读写口（App 内「先选后落」配置页与绑定解析共用）。
class WidgetBindingStore {
  const WidgetBindingStore(this._prefs);

  final SharedPreferences _prefs;

  /// 读一个实例的绑定目标；无记录/脏数据 ⇒ null（按未绑定处理）。
  WidgetTarget? targetOf(int appWidgetId) =>
      WidgetTarget.decode(_prefs.getString(widgetBindingKeyOf(appWidgetId)));

  /// 全局默认绑定（老实例回落 · R2）。无/脏 ⇒ null。
  WidgetTarget? get globalDefault =>
      WidgetTarget.decode(_prefs.getString(kWidgetBindDefaultKey));

  /// 全部在册绑定（配置页列表用；按 key 前缀扫描，**跳过默认键**）。
  ///
  /// 脏值一律跳过（宁少不错——配置页少列一条好过把猜测值显示成绑定）。
  Map<int, WidgetBinding> loadAll() {
    final out = <int, WidgetBinding>{};
    for (final key in _prefs.getKeys()) {
      if (!key.startsWith(kWidgetBindKeyPrefix)) continue;
      final tail = key.substring(kWidgetBindKeyPrefix.length);
      if (tail.isEmpty || tail == 'default') continue;
      final id = int.tryParse(tail);
      if (id == null || id <= 0) continue;
      final t = WidgetTarget.decode(_prefs.getString(key));
      if (t == null || !t.isValid) continue;
      out[id] = WidgetBinding(appWidgetId: id, target: t);
    }
    return out;
  }

  /// 绑定（覆盖同实例旧值）。目标无效 ⇒ 不写（防把半成品状态落盘）。
  Future<void> bind(int appWidgetId, WidgetTarget target) async {
    if (appWidgetId <= 0 || !target.isValid) return;
    await _prefs.setString(widgetBindingKeyOf(appWidgetId), target.encode());
  }

  /// 解绑（移除该实例的绑定键）。
  Future<void> unbind(int appWidgetId) async {
    await _prefs.remove(widgetBindingKeyOf(appWidgetId));
  }

  /// 写/清全局默认绑定（null＝清除）。
  Future<void> setGlobalDefault(WidgetTarget? target) async {
    if (target == null || !target.isValid) {
      await _prefs.remove(kWidgetBindDefaultKey);
      return;
    }
    await _prefs.setString(kWidgetBindDefaultKey, target.encode());
  }

  /// 实例删除回收（原生 `onDeleted` 删键之外的 Dart 侧双保险）。
  ///
  /// [liveIds]＝在役实例 id 集（由原生 `AppWidgetManager.getAppWidgetIds`
  /// 经 MethodChannel 给出；调用方负责取数，本类不碰平台通道）。
  /// 返回被清掉的实例 id（空集＝无需回收）。
  Future<Set<int>> prune(Set<int> liveIds) async {
    final dead = deadInstanceIds(loadAll(), liveIds);
    for (final id in dead) {
      await _prefs.remove(widgetBindingKeyOf(id));
    }
    return dead;
  }

  /// 解析一个实例的生效目标（实例绑定优先，回落全局默认）。
  WidgetBindingResolution resolve(int appWidgetId) => resolveWidgetBinding(
        loadAll(),
        appWidgetId,
        globalDefault: globalDefault,
      );

  /// 与原生侧的键口径交叉自检用：默认键与字段分隔符原值。
  ///
  /// （守护测试 `test/widget_binding_test.dart` 钉这俩常量与待办行编码
  /// `desktop_widget.dart` 的 `kTodoFieldSep` **同值**——控制字符分隔符
  /// 禁两处各写一个；原生 Provider 读键时带 `flutter.` 前缀。）
  static String get defaultKey => kWidgetBindDefaultKey;

  static String get fieldSep => kWidgetBindFieldSep;
}
