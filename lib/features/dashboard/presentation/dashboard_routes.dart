// 治理G6：自 core/router/app_router.dart 按域下沉（path/builder 零改动）。
import 'package:go_router/go_router.dart';

import 'dashboard_page.dart';


/// 底部导航壳内路由（原 ShellRoute 登记 · 治理G6 下沉）
List<GoRoute> dashboardShellRoutes() => [
        GoRoute(path: '/', builder: (_, _) => const DashboardPage())
];
