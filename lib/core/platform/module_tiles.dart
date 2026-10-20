/// 模块瓦片（批C · 1×1 导航型小组件）的**模块目录唯一真源**。
///
/// 规格＝`docs/handoff/小组件模块-批C-1x1模块瓦片-开批规格-20261018.md` §3/§4.2。
///
/// 与读数型小组件的分界（§2）：瓦片**零数据、零刷新、零绑定、零配置**——一枚瓦片
/// 就是一个模块，点了发一条 `lh://modules/<id>` 深链直达该模块首页。所以本文件
/// 只描述「有哪些模块、叫什么、去哪、是壳内 tab 还是全屏栈页」，不碰任何快照/绑定。
///
/// **单源口径**：11 个底栏模块**直接由 [NavModule] 派生**（id/label/path 全在），
/// 禁另抄一份中文名；只有 6 个不占底栏的模块（呵护/阅读/影音/健康/导图/卡片）
/// 手工登记。守护测试钉「表里每条 route 必须在真实路由表存在」与
/// 「shell 标记必须与 `*ShellRoutes()` / `*PageRoutes()` 的归属一致」。
library;

import 'package:flutter/material.dart' show IconData, Icons;

import '../nav/nav_module.dart';

/// 一枚 1×1 模块瓦片。
class ModuleTile {
  const ModuleTile({
    required this.id,
    required this.label,
    required this.route,
    required this.shell,
    required this.icon,
  });

  /// 模块 id（`modules/<id>` 的第二段；同时是原生白名单键）。
  final String id;

  /// 瓦片标签（≤4 字；桌面 1×1 只放得下一行）。
  final String label;

  /// App 内目标路由（模块首页；禁指向二级页）。
  final String route;

  /// `true`＝壳内 tab（有底栏，等价点底栏 ⇒ 消费端用 `go`）；
  /// `false`＝全屏栈页（无底栏 ⇒ 消费端用 `push`）。
  ///
  /// ⚠ 这一位写反就是真机伤（V1.67）：壳内模块用 `push` 会把底栏顶掉，
  /// 全屏页用 `go` 会换掉栈底的壳页 ⇒ 返回黑屏且退不出去。
  final bool shell;

  /// 选择器里的图标（与底栏同形；原生瓦片另有一份 `ic_lh_*` 矢量图）。
  final IconData icon;

  /// 归一化寻址段（`modules/<id>`）——深链与原生白名单都用它。
  String get seg => 'modules/$id';

  /// `lh://` 原值（C15：URI 只此一处拼）。
  String get scheme => 'lh://$seg';

  /// 设置页「添加到桌面」的 pin 入参（`tile:<id>`）。
  ///
  /// 与原生 `MainActivity.widgetClassById` 的 `tile:` 前缀分支逐字一致
  /// （守护 `module_tiles_test` 交叉核对）。
  String get pinId => 'tile:$id';
}

/// 不占底栏的 6 枚（手工登记 · 顺序即选择器里的顺序，排在底栏 11 枚之后）。
///
/// 图标/入口出处见规格 §3「入口形态」列：呵护＝今天页快捷入口；其余五枚
/// 都是「我的」或模块内的二级入口（模块不占底栏，宫格直达 push）。
const List<ModuleTile> kManualModuleTiles = <ModuleTile>[
  ModuleTile(
      id: 'care',
      label: '呵护',
      route: '/care',
      shell: true,
      icon: Icons.child_care_outlined),
  ModuleTile(
      id: 'read',
      label: '阅读',
      route: '/read/shelf',
      shell: false,
      icon: Icons.menu_book_outlined),
  ModuleTile(
      id: 'media',
      label: '影音',
      route: '/media/shelf',
      shell: false,
      icon: Icons.movie_outlined),
  ModuleTile(
      id: 'health',
      label: '健康',
      route: '/health',
      shell: false,
      icon: Icons.monitor_heart_outlined),
  ModuleTile(
      id: 'mindmap',
      label: '导图',
      route: '/mindmap',
      shell: false,
      icon: Icons.account_tree_outlined),
  ModuleTile(
      id: 'nfc',
      label: '卡片',
      route: '/nfc',
      shell: false,
      icon: Icons.nfc_outlined),
];

/// 全部 17 枚（11 底栏派生 ＋ 6 手工）。
///
/// `final`（非 `const`）是因为 label/path 要从枚举实例上取——那是运行期读，
/// 常量表达式里取不到（枚举字段不是 const 表达式）。派生本身仍只此一处。
final List<ModuleTile> kModuleTiles = <ModuleTile>[
  for (final m in NavModule.values)
    ModuleTile(
        id: m.id,
        label: m.label,
        route: m.path,
        shell: true,
        icon: m.icon),
  ...kManualModuleTiles,
];

/// 段 → 瓦片（查表走这里，禁各写一份 switch）。
final Map<String, ModuleTile> moduleTileBySeg = <String, ModuleTile>{
  for (final t in kModuleTiles) t.seg: t,
};

/// **已落原生实现的瓦片**（有 `res/xml/lh_tile_<id>_info.xml` ＋ Manifest receiver
/// ＋ `ModuleTileWidget.kt` 子类的那些）。
///
/// 为什么要这张表：设置页「添加模块瓦片」只能列**真能落桌面**的枚——列了没实现的，
/// 点「添加」系统必然不出弹窗，用户按引导去小部件库也找不到。铺量时（C-2/C-3）
/// 每加一枚 provider 就往这里加一个 id；守护 `module_tiles_test` 钉死
/// 「本表 ≡ 资源与 receiver 实际存在的集合」，漏登记或登记了没实现都红。
const Set<String> kImplementedModuleTileIds = <String>{
  'today',
  'todo', // C-1 试点
  'calendar',
  'journal',
  'habit',
  'inbox',
  'ledger',
  'items',
  'days',
  'goals',
  'settings',
  'care',
  'read',
  'media',
  'health',
  'mindmap',
  'nfc',
};

/// 已落地的瓦片（选择器直接列这一批）。
final List<ModuleTile> kImplementedModuleTiles = <ModuleTile>[
  for (final t in kModuleTiles)
    if (kImplementedModuleTileIds.contains(t.id)) t,
];

/// 壳内（`go`）语义的段集合——[LaunchRoute.fullScreen] 的第三级判定用。
///
/// 与 [kManualModuleTiles]/[NavModule] 的 shell 位**必须逐条一致**（守护
/// `module_tiles_test`），否则壳内模块会被 push 成栈顶、底栏消失。
final Set<String> kShellLaunchSegs = <String>{
  for (final t in kModuleTiles)
    if (t.shell) t.seg,
};
