import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../features/dashboard/presentation/dashboard_routes.dart';
import '../../features/todo/presentation/todo_routes.dart';
import '../../features/calendar/presentation/calendar_routes.dart';
import '../../features/journal/presentation/journal_routes.dart';
import '../../features/habit/presentation/habit_routes.dart';
import '../../features/kits/presentation/kit_routes.dart';
import '../../features/inbox/presentation/inbox_routes.dart';
import '../../features/ledger/presentation/ledger_routes.dart';
import '../../features/care/presentation/care_routes.dart';
import '../../features/days/presentation/days_routes.dart';
import '../../features/items/presentation/items_routes.dart';
import '../../features/goals/presentation/goals_routes.dart';
import '../../features/settings/presentation/settings_routes.dart';
import '../../features/read/presentation/read_routes.dart';
import '../ai/ai_review.dart' show aiRootNavKey;

import '../nav/nav_module.dart';

import '../providers.dart';

import '../theme/app_theme.dart';

import '../../shared/linkage/timer_bar_overlay.dart';

// V1.52 批4：时间账本（L4 分类时长统计 · 日/周/月/年四档）。

import '../../features/dashboard/presentation/dashboard_providers.dart';

import '../../features/journal/presentation/journal_providers.dart'

    show noteSelProvider;

/// 全局导航 Key（Shell 内 Navigator 使用）。

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// go_router 配置：单一 ShellRoute 承载可配置底部导航。

final appRouterProvider = Provider<GoRouter>((ref) {

  // AI 通道弹层（审阅/进度/结果）一律挂这个根栈：分支页的对话框要盖住底栏，

  // 且「开关同源」才有唯一答案（见 ai_review.aiRootNavKey 的两道护栏）。

  aiRootNavKey.value = _rootKey;

  return GoRouter(

    navigatorKey: _rootKey,

    initialLocation: '/',

    routes: [

      ShellRoute(

        builder: (context, state, child) =>

            HomeShell(currentPath: state.uri.path, child: child),

        routes: [

          ...dashboardShellRoutes(),

          ...todoShellRoutes(),

          ...calendarShellRoutes(),

          ...journalShellRoutes(),

          ...habitShellRoutes(),
          ...kitShellRoutes(),

          ...inboxShellRoutes(),

          ...ledgerShellRoutes(),

          ...careShellRoutes(),

          ...daysShellRoutes(),

          ...itemsShellRoutes(),

          ...goalsShellRoutes(),

          ...settingsShellRoutes(),

        ],

      ),

      ...todoPageRoutes(),

      ...calendarPageRoutes(),

      ...journalPageRoutes(),

      ...habitPageRoutes(),
      ...kitPageRoutes(),

      ...ledgerPageRoutes(),

      ...carePageRoutes(),

      ...daysPageRoutes(),

      ...itemsPageRoutes(),

      ...goalsPageRoutes(),

      ...readPageRoutes(),

      ...settingsPageRoutes(),

    ],

  );

});

/// V1.27 G1 返回语义（纯函数便于守护）：

/// 主页编排态 → endEdit（V1.28⑥：返回=退出编排并保存，不退 app）；

/// 底栏外模块主页 → goToday（逐级返回最终落主页，真机反馈修正）；

/// V1.46 真机反馈⑥：从主页(go)进入的模块页（含底栏内栏目）返回先回主页——

/// 只有底栏点进的栏目页与今天页才走「提醒→二次退出」。

String shellBackAction(

  String currentPath, {

  bool inNav = false,

  bool enteredFromToday = false,

  bool dashEditing = false,

  DateTime? lastBackAt,

  DateTime? at,

}) {

  if (currentPath != NavModule.today.path && (!inNav || enteredFromToday)) {

    return 'goToday';

  }

  if (dashEditing) return 'endEdit';

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

  /// V1.46⑥：「从主页进入」判定——上一次壳层路径是今天页时，本模块页的

  /// 返回先回主页（底栏点进的仍走栏目二次退出语义）。

  static String? _prevPath;

  static bool _fromToday = false;

  @override

  Widget build(BuildContext context, WidgetRef ref) {

    if (_prevPath != currentPath) {

      _fromToday = _prevPath == NavModule.today.path;

      _prevPath = currentPath;

    }

    final navModules = ref.watch(

      settingsControllerProvider.select((s) => s.navModules),

    );

    final tokens = context.tokens;

    final selectedIndex = navModules.indexWhere((m) => m.path == currentPath);

    // V1.28⑥：主页编排态下返回键=退出编排并保存（不进二次退出判定）。

    final dashEditing = ref.watch(dashDraftProvider) != null;

    return PopScope(

      canPop: false,

      onPopInvokedWithResult: (didPop, _) {

        if (didPop) return;

        // V1.29轮9：笔记批量多选态下返回=先退出多选（不导航不退出 app）

        if (ref.read(noteSelProvider).isNotEmpty) {

          ref.read(noteSelProvider.notifier).state = const {};

          return;

        }

        // V1.27 G1：返回=最终回主页；今天页二次返回退出（SnackBar 全局同款风格）

        switch (shellBackAction(

          currentPath,

          inNav: navModules.any((m) => m.path == currentPath),

          enteredFromToday: _fromToday,

          dashEditing: dashEditing,

          lastBackAt: _lastBackAt,

        )) {

          case 'goToday':

            _lastBackAt = null;

            context.go(NavModule.today.path);

          case 'endEdit':

            _lastBackAt = null;

            ref.read(dashDraftProvider.notifier).commit();

            ScaffoldMessenger.of(context)

              ..hideCurrentSnackBar()

              ..showSnackBar(

                const SnackBar(

                  content: Text('主页布局已保存 · 下次启动保持此顺序'),

                  duration: Duration(milliseconds: 1600),

                ),

              );

          case 'exit':

            _lastBackAt = null;

            SystemNavigator.pop();

          default:

            _lastBackAt = DateTime.now();

            ScaffoldMessenger.of(context)

              ..hideCurrentSnackBar()

              ..showSnackBar(

                const SnackBar(

                  content: Text('再按一次返回键退出 LifeHarness'),

                  duration: Duration(milliseconds: 2000),

                ),

              );

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

          Icon(

            selected ? module.iconActive : module.icon,

            size: 22,

            color: color,

          ),

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

