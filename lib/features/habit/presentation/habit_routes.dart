// 治理G6：自 core/router/app_router.dart 按域下沉（path/builder 零改动）。
import 'package:go_router/go_router.dart';

import 'habit_detail_page.dart';
import 'habit_settings_page.dart';
import 'habit_stat_page.dart';
import 'habits_page.dart';


/// 底部导航壳内路由（原 ShellRoute 登记 · 治理G6 下沉）
List<GoRoute> habitShellRoutes() => [
        // M1·习惯批1：习惯主页（底部导航池栏目 · 计划 §3 /habits）。
              GoRoute(path: '/habits', builder: (_, _) => const HabitsPage())
];

/// 全屏栈路由（治理G6 下沉）
List<GoRoute> habitPageRoutes() => [
        // 习惯二级页（批3b/批4 · 计划 §3）：详情与统计，全屏无底栏。
          GoRoute(
            path: '/habit/:id',
            builder: (_, s) =>
                HabitDetailPage(habitId: s.pathParameters['id']!),
          ),
        GoRoute(
            path: '/habit-stat',
            builder: (_, _) => const HabitStatPage(),
          ),
        GoRoute(
            path: '/habit-set',
            builder: (_, _) => const HabitSettingsPage(),
          )
];
