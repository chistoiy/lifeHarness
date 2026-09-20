import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../nav/nav_module.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../../shared/linkage/timer_bar_overlay.dart';
import '../../features/calendar/presentation/calendar_page.dart';
import '../../features/calendar/presentation/category_page.dart';
import '../../features/todo/presentation/widgets/pomo_screen.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/inbox/presentation/inbox_page.dart';
import '../../features/journal/presentation/journal_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/todo/presentation/todo_page.dart';

/// 全局导航 Key（Shell 内 Navigator 使用）。
final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// go_router 配置：单一 ShellRoute 承载可配置底部导航。
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            HomeShell(currentPath: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const DashboardPage()),
          GoRoute(path: '/todo', builder: (_, _) => const TodoPage()),
          GoRoute(path: '/calendar', builder: (_, _) => const CalendarPage()),
          GoRoute(path: '/journal', builder: (_, _) => const JournalPage()),
          GoRoute(path: '/inbox', builder: (_, _) => const InboxPage()),
          GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
          GoRoute(path: '/categories', builder: (_, _) => const CategoryPage()),
          GoRoute(path: '/pomo', builder: (_, s) => PomoScreen(session: s.extra as dynamic)),
        ],
      ),
    ],
  );
});

/// 底部导航（原型规范：线性图标 + 文字在下 + 选中态主题色 + 顶部小横条；
/// 栏目可配置，今天/我的固定，≤5）。
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.currentPath, required this.child});

  final String currentPath;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navModules =
        ref.watch(settingsControllerProvider.select((s) => s.navModules));
    final tokens = context.tokens;

    final selectedIndex = navModules.indexWhere((m) => m.path == currentPath);

    return Scaffold(
      body: TimerBarOverlay(child: child),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: tokens.navBg,
          border: Border(top: BorderSide(color: tokens.navBorder)),
        ),
        child: SafeArea(
          child: SizedBox(
            // 原型 nav 高度 70px
            height: 70,
            child: Row(
              children: [
                for (var i = 0; i < navModules.length; i++)
                  Expanded(
                    child: _NavTab(
                      module: navModules[i],
                      selected: i == selectedIndex,
                      accent: tokens.accent,
                      onTap: () {
                        final m = navModules[i];
                        if (m.path != currentPath) context.go(m.path);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.module,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final NavModule module;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface;
    final color = selected ? accent : base.withValues(alpha: .62);
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 选中态顶部小横条指示
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 16,
            height: 3,
            decoration: BoxDecoration(
              color: selected ? accent : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 5),
          Icon(selected ? module.iconActive : module.icon, size: 22, color: color),
          const SizedBox(height: 2),
          Text(
            module.label,
            style: TextStyle(
              fontSize: 10.5,
              color: color,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
