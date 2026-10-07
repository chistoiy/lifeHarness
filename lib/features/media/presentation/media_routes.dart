import 'package:go_router/go_router.dart';

import 'media_detail_page.dart';
import 'media_shelf_page.dart';
import 'media_timer_page.dart';

/// 影音游 · 全屏栈路由（批2 架面 · 批3 详情/计时）。
///
/// 模块**不新增底部 tab**（需求 V1.25：影音游＝记录页第四 tab），因此这里全部是栈页，
/// 入口侧一律 `push`、不许 `go`（R6：go 会把栈页变成栈底，返回键直接退 app）。
List<GoRoute> mediaPageRoutes() => [
  // 影音架（原型 m-shelf · 专版首屏 rep）：`?kind=` 可带类型深链。
  GoRoute(
    path: '/media/shelf',
    builder: (_, s) => MediaShelfPage(
      initialKind: s.uri.queryParameters['kind'],
      initialQuery: s.uri.queryParameters['q'],
    ),
  ),
  // 条目详情（原型 m-detail）：点架卡/速览的正式落面。
  GoRoute(
    path: '/media/item/:id',
    builder: (_, s) => MediaDetailPage(itemId: s.pathParameters['id']!),
  ),
  // 沉浸计时（原型 m-timer）：入口＝详情页计时钮（timerUI=full 直落本页；
  // capsule 档起停走悬浮条，进本页只作展开视图）。
  GoRoute(
    path: '/media/timer/:id',
    builder: (_, s) => MediaTimerPage(itemId: s.pathParameters['id']!),
  ),
];
