import 'package:go_router/go_router.dart';

import 'mindmap_canvas_page.dart';
import 'mindmap_list_page.dart';

/// 思维导图 · 全屏栈路由（批1 · C14 裁定：画布为 push 路由、顶部自带返回，
/// 模块**不占底栏**（2a）——原型 `#mmNav` 两枚不实装，改由顶部返回承载）。
///
/// 入口侧一律 `push`、不许 `go`（R6：go 会把栈页变成栈底，返回键直接退 app）；
/// 宫格 `_stackRoutes` 已含 `/mindmap`。
List<GoRoute> mindmapPageRoutes() => [
      // 导图列表（原型 mm-list）：`/mindmap`。
      GoRoute(path: '/mindmap', builder: (_, _) => const MindmapListPage()),
      // 画布主屏（原型 mm-canvas）：`?id=` 深链承载连接点② 卡片点击的落点
      // （卡片实体涉日记/摘录页文件＝跨线写区，批 1 只把画布深链接口备好）。
      GoRoute(
        path: '/mindmap/canvas',
        builder: (_, s) => MindmapCanvasPage(
          mapId: int.tryParse(s.uri.queryParameters['id'] ?? '') ?? 0,
        ),
      ),
    ];
