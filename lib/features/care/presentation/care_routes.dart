// 治理G6：自 core/router/app_router.dart 按域下沉（path/builder 零改动）。
import 'package:go_router/go_router.dart';

import 'baby_day_page.dart';
import 'babies_page.dart';
import 'care_page.dart';
import 'care_remind_page.dart';
import 'care_stats_page.dart';
import 'growth_page.dart';
import 'vaccine_page.dart';
import 'cycle_cal_page.dart';
import 'cycle_stats_page.dart';
import 'sym_history_page.dart';
import 'milestone_page.dart';

/// 底部导航壳内路由（原 ShellRoute 登记 · 治理G6 下沉）
List<GoRoute> careShellRoutes() => [
        // 呵护批0：模块顶层壳（周期/宝宝点标题互切不落路由栈 · 红线 2）。
              GoRoute(path: '/care', builder: (_, _) => const CarePage())
];

/// 全屏栈路由（治理G6 下沉）
List<GoRoute> carePageRoutes() => [
        // 呵护批0：照护汇总（原型 p-babyStats 栈页 · 批7 实装内容）。
          GoRoute(
            path: '/care/stats',
            builder: (_, _) => const CareStatsPage(),
          ),
        // 呵护批1：她·周期四栈页（原型 p-cycleCal / p-cycleStats / p-symHistory / p-careRemind）。
          GoRoute(
            path: '/care/cycle/cal',
            builder: (_, _) => const CycleCalPage(),
          ),
        GoRoute(
            path: '/care/cycle/stats',
            builder: (_, _) => const CycleStatsPage(),
          ),
        GoRoute(
            path: '/care/sym',
            builder: (_, _) => const SymHistoryPage(),
          ),
        GoRoute(
            path: '/care/remind',
            builder: (_, _) => const CareRemindPage(),
          ),
        // 呵护批2：宝宝档案（原型 p-babies 栈页）。
          GoRoute(
            path: '/care/babies',
            builder: (_, _) => const BabiesPage(),
          ),
        // 呵护批4：全天记录（原型 p-babyDay 栈页；hero 数据位/今日时间线入口）。
          GoRoute(
            path: '/care/day',
            builder: (_, _) => const CareBabyDayPage(),
          ),
        // 呵护批5：生长曲线（原型 p-growth 栈页）。
          GoRoute(
            path: '/care/growth',
            builder: (_, _) => const GrowthPage(),
          ),
        // 呵护批6：疫苗计划 + 发育里程碑（原型 p-vaccine / p-milestones 栈页）。
          GoRoute(
            path: '/care/vaccine',
            builder: (_, _) => const VaccinePage(),
          ),
        GoRoute(
            path: '/care/milestones',
            builder: (_, _) => const MilestonesPage(),
          )
];
