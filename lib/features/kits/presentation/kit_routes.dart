import 'package:go_router/go_router.dart';

import 'kit_tool_page.dart';
import 'kits_page.dart';

/// 底部导航壳内路由（原型「工具」栏目 · 变更单 §八 B3：底栏栏目池可挂载）。
List<GoRoute> kitShellRoutes() => [
  GoRoute(path: '/kits', builder: (_, _) => const KitsPage()),
];

/// 全屏栈路由（工具屏无底栏，专注操作）。
List<GoRoute> kitPageRoutes() => [
  GoRoute(
    path: '/kits/tool/:key',
    builder: (_, s) => KitToolPage(toolKey: s.pathParameters['key']!),
  ),
];
