// 治理G6：自 core/router/app_router.dart 按域下沉（path/builder 零改动）。
import 'package:go_router/go_router.dart';

import 'goal_detail_page.dart';
import 'goal_edit_page.dart';
import 'goal_review_page.dart';
import 'goals_page.dart';


/// 底部导航壳内路由（原 ShellRoute 登记 · 治理G6 下沉）
List<GoRoute> goalsShellRoutes() => [
        // V1.42 批3：目标 OKR 主页（底栏池栏目 · 专版 p-goals）。
              GoRoute(path: '/goals', builder: (_, _) => const GoalsPage())
];

/// 全屏栈路由（治理G6 下沉）
List<GoRoute> goalsPageRoutes() => [
        // V1.42 批3：目标栈页（专版 p-goalDetail / p-goalEdit / p-goalReview）。
          GoRoute(
            path: '/goals/detail',
            builder: (_, s) =>
                GoalDetailPage(goalId: int.parse(s.uri.queryParameters['id']!)),
          ),
        GoRoute(
            path: '/goals/edit',
            builder: (_, s) =>
                GoalEditPage(goalId: int.tryParse(s.uri.queryParameters['id'] ?? '')),
          ),
        GoRoute(
            path: '/goals/review',
            builder: (_, _) => const GoalReviewPage(),
          )
];
