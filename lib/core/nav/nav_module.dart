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
  journal('journal', '日记', Icons.book_outlined, Icons.book, '/journal'),
  inbox('inbox', '收集箱', Icons.inbox_outlined, Icons.inbox, '/inbox'),
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
