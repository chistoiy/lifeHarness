import 'package:go_router/go_router.dart';

import 'media_shelf_page.dart';

/// 影音游 · 全屏栈路由（批2）。
///
/// 模块**不新增底部 tab**（需求 V1.25：影音游＝记录页第四 tab），因此这里全部是栈页，
/// 入口侧一律 `push`、不许 `go`（R6：go 会把栈页变成栈底，返回键直接退 app）。
List<GoRoute> mediaPageRoutes() => [
  // 影音架（原型 m-shelf · 专版首屏 rep）：`?kind=` 可带类型深链。
  GoRoute(
    path: '/media/shelf',
    builder: (_, s) => MediaShelfPage(
      initialKind: s.uri.queryParameters['kind'],
    ),
  ),
];
