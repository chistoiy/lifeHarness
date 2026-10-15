/// 桌面模块 · L0 动作表 ＋ L1 `lh://` 寻址契约的唯一真源。
///
/// 规格＝docs/handoff/桌面模块-冻结版开发方案-20261013.md §2.0 / §前置 A.3
/// （与 NFC 档 §前置 A.3 同源同口径，改一处必须同步另一处 · doclint 守护）。
///
/// **红线（C15）**：本表是**唯一入口定义**——长按菜单 / 铺桌面 / 小组件 / URL 四路
/// 都只能引用它，禁止各写一份跳转逻辑（防行为分叉）。构造 `lh://` URI 时**一律取
/// [DesktopAction.scheme] 原值**，禁在别处手写字面量（守护 `desktop_ns_registry_test`）。
///
/// **C18 带参三级分级**：导航类（nav）可带参直接执行；写入类（记一笔/打卡…）带参
/// **只做预填，提交须 App 内确认**；删除类一律不进 URL。本模块只落地「写入类只预填」。
library;

/// 带参等级（C18）。
enum LaunchArgGrade {
  /// 导航类：可直接执行。
  nav,

  /// 写入类：只预填，提交须 App 内确认。
  writePrefill,
}

/// 一条动作＝id ⇄ 名称 ⇄ 路由 ⇄ lh:// path（§2.0）。
class DesktopAction {
  const DesktopAction({
    required this.id,
    required this.label,
    required this.shortLabel,
    required this.path,
    required this.scheme,
    required this.grade,
    required this.ns,
    required this.fullScreen,
  });

  /// 动作 id（同时是 `setDynamicShortcuts` / `requestPinShortcut` 的稳定键）。
  final String id;

  /// 全名（设置页勾选列表用）。
  final String label;

  /// 短标签（长按菜单 / 铺桌面图标标签用；桌面侧标签 ≤6 字）。
  final String shortLabel;

  /// App 内目标路由（`context.go` 的 path；禁直接 import 对方 feature · R1）。
  final String path;

  /// `lh://…` 形态（**唯一字符串来源**）。
  final String scheme;

  /// 带参等级（C18）。
  final LaunchArgGrade grade;

  /// 所属 ns（取自 [kDesktopNamespaces]，禁散落字面量 · C19）。
  final String ns;

  /// 目标是否为**全屏栈路由**（无底栏，注册在 `<模块>PageRoutes()` 里）。
  ///
  /// **消费端的导航语义由此决定**（V1.67 真机伤）：全屏栈路由必须用 `push`
  /// ——`go` 会把栈底那条壳页一并换掉，页内 `Navigator.pop()` 无处可去 ⇒
  /// **返回黑屏且退不出去**（真机报障：从快捷方式进日记编辑页后返回黑屏）。
  /// 壳内路由（注册在 `<模块>ShellRoutes()` 里，等价底栏 tab）用 `go`，栈顶唯一。
  ///
  /// 取值不得手写猜：由 `desktop_actions_test` 与**真实路由表**交叉核对
  /// （`*ShellRoutes()` / `*PageRoutes()` 的 path 集合）。
  final bool fullScreen;
}

/// `lh://` 的 ns 常量表（C19/B17）。
///
/// 新功能**只允许「加 ns」**，由所属模块在本表外追加并回写冻结档；
/// **禁**把新入口塞进既有 ns。表外 ns 按未知 path 走 `unknownRouteFallback`。
const Set<String> kDesktopNamespaces = <String>{
  'inbox',
  'todo',
  'journal',
  'ledger',
  'items',
  'habit',
  'today',
  // NFC 模块（批2 起）引入：只放行不解释——本模块只解析出 cardId 并原样投给 Dart，
  // 业务含义与 cardId 格式校验归 NFC 模块（B35）。
  'nfc',
};

/// 自有 scheme（V1.67）。原生侧常量 [`LH_SCHEME`]，禁用第二处字面量。
const String kLhScheme = 'lh';

/// 未知 path 的兜底路由名（B4）。
const String kUnknownRouteFallback = 'unknownRouteFallback';

/// 动作表全集（§2.0 · 编译期常量）。
///
/// 顺序即设置页勾选列表的展示顺序（原型 `p-sub-desktop` 同序）。
const List<DesktopAction> kDesktopActions = <DesktopAction>[
  DesktopAction(
    id: 'inbox',
    label: '速记',
    shortLabel: '速记',
    path: '/inbox',
    scheme: 'lh://inbox/new',
    grade: LaunchArgGrade.writePrefill,
    ns: 'inbox',
    fullScreen: false,
  ),
  DesktopAction(
    id: 'todo',
    label: '记待办',
    shortLabel: '待办',
    path: '/todo',
    scheme: 'lh://todo/new',
    grade: LaunchArgGrade.writePrefill,
    ns: 'todo',
    fullScreen: false,
  ),
  DesktopAction(
    id: 'ledger',
    label: '记一笔',
    shortLabel: '记一笔',
    path: '/ledger/add',
    scheme: 'lh://ledger/add',
    grade: LaunchArgGrade.writePrefill,
    ns: 'ledger',
    fullScreen: true, // /ledger/add 注册在 ledgerPageRoutes()——全屏栈路由
  ),
  DesktopAction(
    id: 'habit',
    label: '打卡',
    shortLabel: '打卡',
    path: '/habits',
    scheme: 'lh://habit/check',
    grade: LaunchArgGrade.writePrefill,
    ns: 'habit',
    fullScreen: false,
  ),
  DesktopAction(
    id: 'journal',
    label: '写日记',
    shortLabel: '日记',
    path: '/journal/edit',
    scheme: 'lh://journal/edit',
    grade: LaunchArgGrade.writePrefill,
    ns: 'journal',
    fullScreen: true, // /journal/edit 注册在 journalPageRoutes()——全屏栈路由
  ),
  DesktopAction(
    id: 'items',
    label: '记物品',
    shortLabel: '物品',
    path: '/items',
    scheme: 'lh://items/new',
    grade: LaunchArgGrade.writePrefill,
    ns: 'items',
    fullScreen: false,
  ),
  DesktopAction(
    id: 'today',
    label: '回今天页',
    shortLabel: '今天',
    path: '/',
    scheme: 'lh://today',
    grade: LaunchArgGrade.nav,
    ns: 'today',
    fullScreen: false,
  ),
];

/// 长按菜单默认 4 枚（§2.0）。
const List<String> kDefaultMenuActionIds = <String>[
  'inbox',
  'todo',
  'ledger',
  'habit',
];

/// 长按菜单系统硬限 4（§4.1）。第 5 项勾选须被拒并提示。
const int kMenuMax = 4;

/// 白名单全集（§4.3 批 1 冻结）：`lh://<ns>/<key>` 的 key 段 → 动作 id。
/// 一字不多；扩容只允许「加 ns」并回写冻结档（C19）。
const Map<String, String> kLaunchPathWhitelist = <String, String>{
  'inbox/new': 'inbox',
  'todo/new': 'todo',
  'journal/edit': 'journal',
  'ledger/add': 'ledger',
  'items/new': 'items',
  'habit/check': 'habit',
  'today': 'today',
};

/// id → 动作。查表走这里，禁各写一份 switch。
final Map<String, DesktopAction> desktopActionById = <String, DesktopAction>{
  for (final a in kDesktopActions) a.id: a,
};

/// scheme 原值 → 动作（原生侧与测试用同一份，禁手写字符串比对）。
final Map<String, DesktopAction> desktopActionByScheme =
    <String, DesktopAction>{
  for (final a in kDesktopActions) a.scheme: a,
};

/// 按 id 查动作；查不到返回 null（**不抛**——未知 id 走兜底路由 B4）。
DesktopAction? desktopActionOf(String id) => desktopActionById[id];

/// 拼 `lh://` URI：**只取动作表 Scheme 列原值**（C15/C16·禁散落字面量）。
///
/// [args] 一律带进 URI——**导航类带参可直接执行，写入类带参只被目标页当预填**，
/// C18 的分级体现在「执行语义」而非「是否收参」（两档都收参，收了都要落到
/// [LaunchRoute.args] 交目标页判）。
Uri desktopLaunchUri(String actionId, {Map<String, String>? args}) {
  final a = desktopActionOf(actionId);
  if (a == null) throw ArgumentError('未知动作 id：$actionId（禁手写 URI，禁表外动作）');
  if (args == null || args.isEmpty) return Uri.parse(a.scheme);
  return Uri.parse(a.scheme).replace(queryParameters: <String, String>{...args});
}

/// 解析 `lh://<ns>/<key>[/<arg>…]` 的**归一化寻址段**（如 `ledger/add`）→ 动作 id
/// （C38/C19·L1 解析）。
///
/// ⚠ [path] 传的是**归一化寻址段**（`ledger/add`，不带 scheme/authority），
/// **不是 `Uri.path`**——两者不是一回事，见 [launchSegOf]。
///
/// 三级判定（B17/B4/B5）：
/// 1. ns（段首）不在 [kDesktopNamespaces] → null（表外 ns 按未知 path 走 `unknownRouteFallback`）；
/// 2. `nfc/<cardId>` → 返回 `'nfc:<cardId>'`（**原样透传不解释**，业务含义归 NFC 模块）；
/// 3. 整段查 [kLaunchPathWhitelist] → 命中给动作 id，未命中给 null。
String? resolveLaunchPath(String path) {
  var seg = path.trim();
  while (seg.startsWith('/')) {
    seg = seg.substring(1);
  }
  if (seg.isEmpty) return null;
  final parts = seg.split('/');
  final ns = parts[0];
  if (!kDesktopNamespaces.contains(ns)) return null;
  if (ns == 'nfc') {
    final cardId = parts.length > 1 ? parts[1] : '';
    return cardId.isEmpty ? null : 'nfc:$cardId';
  }
  return kLaunchPathWhitelist[seg];
}

/// 从一条 `lh://<ns>/<key>` URI 提取**归一化寻址段**（`ns/key`）。
///
/// **本函数是「URI 分解口径」的唯一真源**（V1.67 热修）。按 RFC 3986，`lh://` 之后的
/// 首段是 **authority（host）**：`ns` 落在 `host`、`key` 落在 `path`。所以
///
/// ```dart
/// Uri.parse('lh://ledger/add').path   // ⇒ '/add'（ns 丢了！）
/// Uri.parse('lh://ledger/add').host   // ⇒ 'ledger'
/// launchSegOf(Uri.parse('lh://ledger/add')) // ⇒ 'ledger/add' ✓
/// ```
///
/// **只取 `Uri.path` 是 V1.67 真机伤**：ns 校验必失败 ⇒ 意图被静默丢弃 ⇒ 长按菜单／
/// 铺桌面／小组件／外部 `lh://` 四路点击全部落回首页。原生 `MainActivity.enqueueLaunch`
/// 必须按同一口径拼接 `host + path`（守护 `desktop_intent_shape_test`：Dart 侧钉口径、
/// 原生侧钉实现）。
String launchSegOf(Uri uri) {
  final host = uri.host;
  final raw = host.isEmpty ? uri.path : '$host${uri.path}';
  var seg = raw.trim();
  while (seg.startsWith('/')) {
    seg = seg.substring(1);
  }
  return seg;
}

/// 直接解析一条 `lh://…` URI → 动作 id（[launchSegOf] ＋ [resolveLaunchPath]）。
///
/// 非 [`kLhScheme`] / 段空 / 表外 ns / 白名单未命中 → null。
String? resolveLaunchUri(Uri uri) =>
    uri.scheme == kLhScheme ? resolveLaunchPath(launchSegOf(uri)) : null;

/// 一条待投递的启动路由（L3 消费单元）。
class LaunchRoute {
  const LaunchRoute({required this.action, this.args = const <String, String>{}});

  /// 动作 id（`nfc:<cardId>` 形态表示透传给 NFC 模块的卡片）。
  final String action;

  /// 带参（写入类只预填 · C18）。
  final Map<String, String> args;

  bool get isNfc => action.startsWith('nfc:');

  /// 目标是否全屏栈路由 ⇒ 消费端必须 `push`（见 [DesktopAction.fullScreen]）。
  bool get fullScreen => desktopActionOf(action)?.fullScreen ?? false;

  /// 目标路由：动作 id 查表；查不到走兜底（B4）。
  String get route {
    final a = desktopActionOf(action);
    return a?.path ?? kUnknownRouteFallback;
  }
}