import 'package:go_router/go_router.dart';

import 'health_body_page.dart';
import 'health_exercise_page.dart';
import 'health_goals_page.dart';
import 'health_home_page.dart';
import 'health_med_page.dart';
import 'health_report_page.dart';
import 'health_sleep_page.dart';
import 'health_symptom_page.dart';
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
  // 身体数据（原型 p-body · 批3）：体重曲线＋流水，录入用同一张弹层改。
  GoRoute(
    path: '/health/body',
    builder: (_, _) => const HealthBodyPage(),
  ),
  // 运动记录（原型 p-exLog · 批4）：本周/本月窗口＋类型过滤＋流水＋配速趋势。
  GoRoute(
    path: '/health/exercise',
    builder: (_, _) => const HealthExercisePage(),
  ),
  // 症状与不适（原型 p-symptom · 批3.5a）：发作卡＋疼痛直方图＋部位筛选＋词云＋流水。
  GoRoute(
    path: '/health/symptom',
    builder: (_, _) => const HealthSymptomPage(),
  ),
  // 检查报告（原型 p-report · 批3.5b）：统计三位＋月份筛选＋逐份可展开的报告卡。
  GoRoute(
    path: '/health/report',
    builder: (_, _) => const HealthReportPage(),
  ),
  // 健康目标（原型 p-goalsH · 批3）：环形今日四项＋就地滚轮改档。
  GoRoute(
    path: '/health/goals',
    builder: (_, _) => const HealthGoalsPage(),
  ),
  // 用药管理（原型 p-med · 批5）：档案卡列表＋打卡＋近 7 天热力＋设置三行。
  GoRoute(
    path: '/health/med',
    builder: (_, _) => const HealthMedPage(),
  ),
];
