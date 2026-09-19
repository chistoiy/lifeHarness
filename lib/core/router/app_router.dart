import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers.dart';
import '../theme/app_theme.dart';
import '../../features/calendar/presentation/calendar_page.dart';
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
        ],
      ),
    ],
  );
});

/// 底部导航骨架：根据用户设置的可配置栏目渲染（今天/我的固定，≤5）。
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
      body: child,
      bottomNavigationBar: NavigationBar(
        backgroundColor: tokens.navBg,
        surfaceTintColor: Colors.transparent,
        indicatorColor: tokens.accent.withValues(alpha: 0.14),
        elevation: 0,
        selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
        onDestinationSelected: (i) {
          final m = navModules[i];
          if (m.path != currentPath) context.go(m.path);
        },
        destinations: [
          for (final m in navModules)
            NavigationDestination(
              icon: Icon(m.icon),
              selectedIcon: Icon(m.iconActive),
              label: m.label,
            ),
        ],
      ),
    );
  }
}
