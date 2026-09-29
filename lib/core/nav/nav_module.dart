import 'package:flutter/material.dart';

/// 可挂载到底部导航的模块（骨架阶段先纳入 V0.1 已实现的页面）。
///
/// 正式版底部导航最多 5 个，`today`（今天）与 `settings`（我的）固定；
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
  // V1.47 模块14：小工具合集（原型 NAV_MODS「工具」栏同位 · 底栏栏目池可挂载）。
  kits('kits', '工具', Icons.grid_view_outlined, Icons.grid_view, '/kits'),
  settings('settings', '我的', Icons.person_outline, Icons.person, '/settings');

  const NavModule(this.id, this.label, this.icon, this.iconActive, this.path);

  final String id;
  final String label;
  final IconData icon;
  final IconData iconActive;
  final String path;

  static NavModule fromId(String id) =>
      NavModule.values.firstWhere((m) => m.id == id, orElse: () => NavModule.today);

  /// 默认底栏序列（今天/我的固定 + 中间三栏）。
  static const List<NavModule> defaultNav = [
    NavModule.today,
    NavModule.todo,
    NavModule.calendar,
    NavModule.journal,
    NavModule.settings,
  ];
}
