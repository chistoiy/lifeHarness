// 治理G6：自 core/router/app_router.dart 按域下沉（path/builder 零改动）。
import 'package:go_router/go_router.dart';

import 'widgets/pomo_screen.dart';
import 'todo_providers.dart' show PomoSession;
import 'todo_page.dart';


/// 底部导航壳内路由（原 ShellRoute 登记 · 治理G6 下沉）
List<GoRoute> todoShellRoutes() => [
        GoRoute(path: '/todo', builder: (_, _) => const TodoPage())
];

/// 全屏栈路由（治理G6 下沉）
List<GoRoute> todoPageRoutes() => [
        // 番茄全屏专注页：全屏无底栏（V1.27 T7），extra 传会话。
          GoRoute(
            path: '/pomo',
            builder: (_, s) => PomoScreen(session: s.extra as PomoSession),
          )
];
