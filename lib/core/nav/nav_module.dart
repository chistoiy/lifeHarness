import 'package:flutter/material.dart';

/// 可挂载到底部导航的模块（骨架阶段先纳入 V0.1 已实现的页面）。
///
/// 正式版底部导航最多 5 个。`today`（今天）与 `settings`（我的）是**锚栏目**：
/// 2026-10-15 产品改口前是「两枚都固定不可关」，新口径＝**两枚可关其一，
/// 但不能两个都关**（[isAnchor] / `SettingsController.toggleNav` 的 `needAnchor`）。
/// 其余栏目用户在设置页开关（需求 V1.5）。此处仅定义目录与默认序。
enum NavModule {
  today('today', '今天', Icons.home_outlined, Icons.home, '/'),
  todo('todo', '待办', Icons.check_circle_outline, Icons.check_circle, '/todo'),
  calendar(
      'calendar', '时间', Icons.schedule, Icons.calendar_month, '/calendar'),
  journal('journal', '记录', Icons.book_outlined, Icons.book, '/journal'),
  habit('habit', '习惯', Icons.autorenew, Icons.loop, '/habits'),
  inbox('inbox', '收集箱', Icons.inbox_outlined, Icons.inbox, '/inbox'),
  ledger('ledger', '记账', Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet, '/ledger'),
  // V1.42 批2：物品价值（每日成本 · 专版 P7 · NAV_MODS p-items 同位）。
  items('items', '物品', Icons.inventory_2_outlined, Icons.inventory_2,
      '/items'),
  // V1.42 批1：重要日子（专版 P8 · 底栏池栏目，NAV_MODS p-days 同位）。
  days('days', '日子', Icons.celebration_outlined, Icons.celebration, '/days'),
  // V1.42 批3：目标 OKR（专版 P10 · NAV_MODS p-goals 同位）。
  goals('goals', '目标', Icons.explore_outlined, Icons.explore, '/goals'),
  settings('settings', '我的', Icons.person_outline, Icons.person, '/settings');

  const NavModule(this.id, this.label, this.icon, this.iconActive, this.path);

  final String id;
  final String label;
  final IconData icon;
  final IconData iconActive;
  final String path;

  static NavModule fromId(String id) =>
      NavModule.values.firstWhere((m) => m.id == id, orElse: () => NavModule.today);

  /// 是否「锚栏目」（今天 / 我的）。
  ///
  /// 产品 2026-10-15 改口：这两枚**可关其一**（旧口径是两枚都固定），
  /// 但**不能两个都关**——底栏一个锚都不剩时，用户就没有「回主页 / 进设置」的
  /// 常驻出口了。约束由 `SettingsController.toggleNav` 兜底，UI 只负责提示。
  bool get isAnchor => this == NavModule.today || this == NavModule.settings;

  /// 默认底栏序列（今天/我的固定 + 中间三栏）。
  static const List<NavModule> defaultNav = [
    NavModule.today,
    NavModule.todo,
    NavModule.calendar,
    NavModule.journal,
    NavModule.settings,
  ];
}
