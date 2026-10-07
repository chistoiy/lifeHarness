import 'package:go_router/go_router.dart';

import 'health_home_page.dart';
import 'health_sleep_page.dart';
import 'health_vitals_page.dart';

/// 健康 · 模块路由（批2 起逐屏补，路径与 `docs/健康管理模块开发计划-20260927.md` §三 路由表同形）。
///
/// 健康**不新增底部 tab**（需求 V1.48：模块入口走主页宫格），所以这里全是栈页：
/// 入口侧一律 `push`，不许 `go`（R6：go 会把栈页变成栈底，返回键直接退 app）。
/// 宫格那枚的分派见 `features/dashboard/presentation/dashboard_page.dart` 的 `_stackRoutes`。
List<GoRoute> healthPageRoutes() => [
  // 健康工作台（原型 p-health）：批2 首屏，喝水/睡眠两卡 + 达标概览。
  GoRoute(
    path: '/health',
    builder: (_, _) => const HealthHomePage(),
  ),
  // 睡眠记录（原型 p-sleepLog）：近 7 天柱状＋流水，点行就地改。
  GoRoute(
    path: '/health/sleep',
    builder: (_, _) => const HealthSleepPage(),
  ),
  // 体征记录（原型 p-vitals · 批2.5）：`?kind=` 决定进来先选哪枚指标（工作台体征条带进来）。
  GoRoute(
    path: '/health/vitals',
    builder: (_, s) => HealthVitalsPage(initialKind: s.uri.queryParameters['kind']),
  ),
];
