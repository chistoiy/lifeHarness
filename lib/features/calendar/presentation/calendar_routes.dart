// 治理G6：自 core/router/app_router.dart 按域下沉（path/builder 零改动）。
import 'package:go_router/go_router.dart';

import 'calendar_page.dart';
import 'category_page.dart';
import 'time_stats_page.dart';


/// 底部导航壳内路由（原 ShellRoute 登记 · 治理G6 下沉）
List<GoRoute> calendarShellRoutes() => [
        GoRoute(path: '/calendar', builder: (_, _) => const CalendarPage()),
        GoRoute(path: '/categories', builder: (_, _) => const CategoryPage())
];

/// 全屏栈路由（治理G6 下沉）
List<GoRoute> calendarPageRoutes() => [
        // V1.52 批4：时间账本（时间页顶栏柱状图标 push 进入 · 栈路由不走 go，R6）。
          GoRoute(
            path: '/time-stats',
            builder: (_, _) => const TimeStatsPage(),
          )
];
