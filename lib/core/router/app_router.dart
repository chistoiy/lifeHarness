import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../nav/nav_module.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../../shared/linkage/timer_bar_overlay.dart';
import '../../features/calendar/presentation/calendar_page.dart';
import '../../features/calendar/presentation/category_page.dart';
import '../../features/todo/presentation/widgets/pomo_screen.dart';
import '../../features/todo/presentation/todo_providers.dart' show PomoSession;
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/inbox/presentation/inbox_page.dart';
import '../../features/journal/presentation/diary_edit_page.dart';
import '../../features/journal/presentation/journal_page.dart';
import '../../features/settings/presentation/notify_settings_page.dart';
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
        ],
      ),
      // 番茄全屏专注页：全屏无底栏（V1.27 T7），extra 传会话。
      GoRoute(
          path: '/pomo',
          builder: (_, s) => PomoScreen(session: s.extra as PomoSession)),
      // 日记编辑页：全屏无底栏（原型 p-diaryEdit 为 stack 页），extra 传 DateTime 指定日期。
      GoRoute(
        path: '/journal/edit',
        builder: (_, s) => DiaryEditPage(day: s.extra as DateTime?),
      ),
      // 提醒通知二级页（原型 p-sub-notify）。
      GoRoute(
        path: '/settings/notify',
        builder: (_, _) => const NotifySettingsPage(),
      ),
      // V1.27 P2 外观二级页（原型 p-sub-appearance：主题/深色/主题色/字号）。
      GoRoute(
        path: '/settings/appearance',
        builder: (_, _) => const AppearanceSettingsPage(),
      ),
    ],
  );
});

/// V1.27 G1 返回语义（纯函数便于守护）：
/// 非主页 → goToday（逐级返回最终落主页）；主页 2s 内二次返回 → exit；首次 → remind。
String shellBackAction(String currentPath, {DateTime? lastBackAt, DateTime? at}) {
  if (currentPath != NavModule.today.path) return 'goToday';
  final n = at ?? DateTime.now();
  if (lastBackAt != null &&
      n.difference(lastBackAt) < const Duration(seconds: 2)) {
    return 'exit';
  }
  return 'remind';
}

/// 底部导航（原型规范：线性图标 + 文字在下 + 选中态主题色 + 顶部小横条；
/// 栏目可配置，今天/我的固定，≤5）。
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.currentPath, required this.child});

  final String currentPath;
  final Widget child;

  /// G1：今天页二次返回退出计时（原型 _lastBackTs 2s 窗口）。
  static DateTime? _lastBackAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navModules =
        ref.watch(settingsControllerProvider.select((s) => s.navModules));
    final tokens = context.tokens;

    final selectedIndex = navModules.indexWhere((m) => m.path == currentPath);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // V1.27 G1：返回=最终回主页；今天页二次返回退出（SnackBar 全局同款风格）
        switch (shellBackAction(currentPath, lastBackAt: _lastBackAt)) {
          case 'goToday':
            _lastBackAt = null;
            context.go(NavModule.today.path);
          case 'exit':
            _lastBackAt = null;
            SystemNavigator.pop();
          default:
            _lastBackAt = DateTime.now();
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(
                  content: Text('再按一次返回键退出 LifeHarness'),
                  duration: Duration(milliseconds: 2000)));
        }
      },
      child: Scaffold(
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
