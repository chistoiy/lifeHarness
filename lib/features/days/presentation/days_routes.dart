// 治理G6：自 core/router/app_router.dart 按域下沉（path/builder 零改动）。
import 'package:go_router/go_router.dart';

import 'day_detail_page.dart';
import 'day_edit_page.dart';
import 'day_remind_page.dart';
import 'days_page.dart';


/// 底部导航壳内路由（原 ShellRoute 登记 · 治理G6 下沉）
List<GoRoute> daysShellRoutes() => [
        // V1.42 批1：重要日子主页（底栏池栏目 · 专版 p-days）。
              GoRoute(path: '/days', builder: (_, _) => const DaysPage())
];

/// 全屏栈路由（治理G6 下沉）
List<GoRoute> daysPageRoutes() => [
        // V1.42 批1：日子栈页（专版 p-dayDetail / p-dayEdit / p-dayRemind）。
          // 模块内跳转走 Navigator.push；此处登记供外部直达（仪表盘/设置入口）。
          GoRoute(
            path: '/days/detail',
            builder: (_, s) =>
                DayDetailPage(dayId: int.parse(s.uri.queryParameters['id']!)),
          ),
        GoRoute(
            path: '/days/edit',
            builder: (_, s) =>
                DayEditPage(dayId: int.tryParse(s.uri.queryParameters['id'] ?? '')),
          ),
        GoRoute(
            path: '/days/remind',
            builder: (_, _) => const DayRemindPage(),
          )
];
