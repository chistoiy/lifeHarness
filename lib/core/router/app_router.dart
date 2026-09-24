import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../nav/nav_module.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../../shared/linkage/timer_bar_overlay.dart';
import '../../features/calendar/presentation/calendar_page.dart';
import '../../features/calendar/presentation/category_page.dart';
import '../../features/care/presentation/baby_day_page.dart';
import '../../features/care/presentation/babies_page.dart';
import '../../features/care/presentation/care_page.dart';
import '../../features/care/presentation/care_remind_page.dart';
import '../../features/care/presentation/care_stats_page.dart';
import '../../features/care/presentation/growth_page.dart';
import '../../features/care/presentation/milestone_page.dart';
import '../../features/care/presentation/vaccine_page.dart';
import '../../features/care/presentation/cycle_cal_page.dart';
import '../../features/care/presentation/cycle_stats_page.dart';
import '../../features/care/presentation/sym_history_page.dart';
import '../../features/todo/presentation/widgets/pomo_screen.dart';
import '../../features/todo/presentation/todo_providers.dart' show PomoSession;
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/dashboard/presentation/dashboard_providers.dart';
import '../../features/habit/presentation/habit_detail_page.dart';
import '../../features/habit/presentation/habit_settings_page.dart';
import '../../features/habit/presentation/habit_stat_page.dart';
import '../../features/habit/presentation/habits_page.dart';
import '../../features/inbox/presentation/inbox_page.dart';
import '../../features/journal/presentation/diary_edit_page.dart';
import '../../features/journal/presentation/journal_page.dart';
import '../../features/journal/presentation/journal_providers.dart'
    show noteSelProvider;
import '../../features/journal/presentation/note_edit_page.dart';
import '../../features/ledger/presentation/ledger_add_page.dart';
import '../../features/ledger/presentation/ledger_assets_page.dart';
import '../../features/ledger/presentation/ledger_account_detail_page.dart';
import '../../features/ledger/presentation/ledger_budget_page.dart';
import '../../features/ledger/presentation/ledger_cats_page.dart';
import '../../features/ledger/presentation/ledger_debt_page.dart';
import '../../features/ledger/presentation/ledger_export_page.dart';
import '../../features/ledger/presentation/ledger_import_page.dart';
import '../../features/ledger/presentation/ledger_page.dart';
import '../../features/ledger/presentation/ledger_recur_page.dart';
import '../../features/ledger/presentation/ledger_report_page.dart';
import '../../features/ledger/presentation/ledger_search_page.dart';
import '../../features/ledger/presentation/ledger_set_page.dart';
import '../../features/ledger/presentation/ledger_tx_detail_page.dart';
import '../../features/ledger/presentation/ledger_wish_page.dart';
import '../../features/ledger/presentation/ledger_yearly_page.dart';
import '../../features/read/presentation/book_detail.dart';
import '../../features/read/presentation/book_info_page.dart';
import '../../features/read/presentation/book_mgr_page.dart';
import '../../features/read/presentation/isbn_scan_page.dart';
import '../../features/read/presentation/quotes_lib_page.dart';
import '../../features/read/presentation/read_import_page.dart';
import '../../features/read/presentation/read_lists_page.dart';
import '../../features/read/presentation/read_log_page.dart';
import '../../features/read/presentation/read_settings_page.dart';
import '../../features/read/presentation/read_stat_page.dart';
import '../../features/read/presentation/read_timer_page.dart';
import '../../features/read/presentation/shelf_page.dart';
import '../../features/settings/presentation/notify_settings_page.dart';
import '../../features/settings/presentation/recmg_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/todo/presentation/todo_page.dart';

/// 全局导航 Key（Shell 内 Navigator 使用）。
final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// go_router 配置：单一 ShellRoute 承载可配置底部导航。
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            HomeShell(currentPath: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const DashboardPage()),
          GoRoute(path: '/todo', builder: (_, _) => const TodoPage()),
          GoRoute(path: '/calendar', builder: (_, _) => const CalendarPage()),
          GoRoute(path: '/journal', builder: (_, _) => const JournalPage()),
          // M1·习惯批1：习惯主页（底部导航池栏目 · 计划 §3 /habits）。
          GoRoute(path: '/habits', builder: (_, _) => const HabitsPage()),
          GoRoute(path: '/inbox', builder: (_, _) => const InboxPage()),
          // 记账批1：主页入底栏导航池（NAV_MODS p-finance 同位）。
          GoRoute(path: '/ledger', builder: (_, _) => const LedgerPage()),
          // 呵护批0：模块顶层壳（周期/宝宝点标题互切不落路由栈 · 红线 2）。
          GoRoute(path: '/care', builder: (_, _) => const CarePage()),
          GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
          GoRoute(path: '/categories', builder: (_, _) => const CategoryPage()),
        ],
      ),
      // 番茄全屏专注页：全屏无底栏（V1.27 T7），extra 传会话。
      GoRoute(
        path: '/pomo',
        builder: (_, s) => PomoScreen(session: s.extra as PomoSession),
      ),
      // 记账批1：记一笔（?kind/cat/date/note/edit/copy · 原型 openL2(opt)）与
      // 流水详情（全屏无底栏，同 p-txDetail 为 stack 页）。
      GoRoute(
        path: '/ledger/add',
        builder: (_, s) {
          final q = s.uri.queryParameters;
          return LedgerAddPage(
            editId: int.tryParse(q['edit'] ?? ''),
            copyId: int.tryParse(q['copy'] ?? ''),
            kind: q['kind'],
            catId: int.tryParse(q['cat'] ?? ''),
            date: q['date'],
            note: q['note'],
          );
        },
      ),
      GoRoute(
        path: '/ledger/tx/:id',
        builder: (_, s) =>
            LedgerTxDetailPage(txnId: int.parse(s.pathParameters['id']!)),
      ),
      // 记账批1d：账单导入五步向导（全屏，同 p-billImport 栈页）。
      GoRoute(
        path: '/ledger/import',
        builder: (_, _) => const LedgerImportPage(),
      ),
      // 记账批2a：L4 统计报表与 L16 年度总结（全屏，同 p-report / p-yearly 栈页）。
      GoRoute(
        path: '/ledger/report',
        builder: (_, _) => const LedgerReportPage(),
      ),
      GoRoute(
        path: '/ledger/yearly',
        builder: (_, _) => const LedgerYearlyPage(),
      ),
      // 记账批2b：L5 预算中心（含 L17 结转；全屏，同 p-budget 栈页）。
      GoRoute(
        path: '/ledger/budget',
        builder: (_, _) => const LedgerBudgetPage(),
      ),
      // 记账批2c：L6 资产总览与 L7 账户详情（含信用卡账期；全屏，同 p-assets / p-assetAcct 栈页）。
      GoRoute(
        path: '/ledger/assets',
        builder: (_, _) => const LedgerAssetsPage(),
      ),
      GoRoute(
        path: '/ledger/account/:id',
        builder: (_, s) => LedgerAccountDetailPage(
          accountId: int.parse(s.pathParameters['id']!),
        ),
      ),
      // 记账批2d：L8 分类管理与 L9 周期账单（到期批量生成；全屏，同 p-cats / p-recur 栈页）。
      GoRoute(
        path: '/ledger/cats',
        builder: (_, _) => const LedgerCatsPage(),
      ),
      GoRoute(
        path: '/ledger/recur',
        builder: (_, _) => const LedgerRecurPage(),
      ),
      // 记账批3a：L10 心愿单与 L11 借出/借入（存入取出不落流水·兑换/还款走统一写路径；全屏，同 p-wish / p-debt 栈页）。
      GoRoute(
        path: '/ledger/wish',
        builder: (_, _) => const LedgerWishPage(),
      ),
      GoRoute(
        path: '/ledger/debt',
        builder: (_, _) => const LedgerDebtPage(),
      ),
      // 记账批3b：L12 搜索筛选与 L15 数据导出（条件即时 AND 过滤 / 流式落盘；
      // 全屏，同 p-txSearch / p-export 栈页）。
      GoRoute(
        path: '/ledger/search',
        builder: (_, _) => const LedgerSearchPage(),
      ),
      GoRoute(
        path: '/ledger/export',
        builder: (_, _) => const LedgerExportPage(),
      ),
      // 记账批3c：L13 记账设置（设置 KV 全量落 DB settings 表 `ledger.` 前缀；
      // 全屏，同 p-lset 栈页）。
      GoRoute(
        path: '/ledger/set',
        builder: (_, _) => const LedgerSetPage(),
      ),
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
      ),
      // 日记编辑页：全屏无底栏（原型 p-diaryEdit 为 stack 页）。
      // V1.28 一天多篇：extra=DiaryEditArg(day 新建当天的第 N+1 篇 | entryId 编辑既有篇)。
      GoRoute(
        path: '/journal/edit',
        builder: (_, s) {
          final a = s.extra;
          return a is DiaryEditArg
              ? DiaryEditPage(day: a.day, entryId: a.entryId)
              : DiaryEditPage(day: a as DateTime?);
        },
      ),
      // M1 批1a 笔记编辑页：全屏纸感（原型 p-noteEdit），extra=noteId（null=新建）。
      GoRoute(
        path: '/note/edit',
        builder: (_, s) {
          final x = s.extra;
          if (x is NoteEditArg) {
            return NoteEditPage(
              noteId: x.noteId,
              initialKind: x.kind,
              initialFolder: x.folder,
            );
          }
          return NoteEditPage(noteId: x as int?);
        },
      ),
      // 提醒通知二级页（原型 p-sub-notify）。
      GoRoute(
        path: '/settings/notify',
        builder: (_, _) => const NotifySettingsPage(),
      ),
      // V1.27 P2 外观二级页（原型 p-sub-appearance：主题/深色/主题色/字号）。
      GoRoute(
        path: '/settings/appearance',
        builder: (_, _) => const AppearanceSettingsPage(),
      ),
      // M1批3 阅读：书架与书籍详情（原型 p-bookshelf / p-bookDetail）。
      GoRoute(path: '/read/shelf', builder: (_, _) => const ShelfPage()),
      // 习惯二级页（批3b/批4 · 计划 §3）：详情与统计，全屏无底栏。
      GoRoute(
        path: '/habit/:id',
        builder: (_, s) =>
            HabitDetailPage(habitId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/habit-stat',
        builder: (_, _) => const HabitStatPage(),
      ),
      GoRoute(
        path: '/habit-set',
        builder: (_, _) => const HabitSettingsPage(),
      ),
      GoRoute(
        path: '/read/book/:id',
        builder: (_, s) => BookDetailPage(
          bookId: s.pathParameters['id']!,
          initialTab: (s.extra as BookDetailArg?)?.tab ?? 'c',
        ),
      ),
      // M1批3·批2：书籍资料页（p-bookInfo）与沉浸计时页（p-readtimer·全屏形态）。
      GoRoute(
        path: '/read/info/:id',
        builder: (_, s) => BookInfoPage(bookId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/read/timer/:id',
        builder: (_, s) => ReadTimerPage(bookId: s.pathParameters['id']!),
      ),
      // 真机验收轮1e：阅读记录页（原型 p-readlog · 计时明细改全屏页）。
      GoRoute(
        path: '/read/log/:id',
        builder: (_, s) => ReadLogPage(bookId: s.pathParameters['id']!),
      ),
      // M1批3·批3 笔记库（原型 p-quotes · 跨书摘录四视图，extra=入口书 id）。
      GoRoute(
        path: '/read/quotes',
        builder: (_, s) => QuotesLibPage(bookId: s.extra as String?),
      ),
      // M1批3·批4 统计与书单（原型 p-readstat / p-booklists / p-booklist）。
      GoRoute(
        path: '/read/stat',
        builder: (_, _) => const ReadStatPage(),
      ),
      GoRoute(
        path: '/read/lists',
        builder: (_, _) => const BookListsPage(),
      ),
      GoRoute(
        path: '/read/list/:id',
        builder: (_, s) =>
            BookListDetailPage(listId: int.parse(s.pathParameters['id']!)),
      ),
      // M1批3·批5 导入向导与阅读设置（原型 p-readimport / p-readset）。
      GoRoute(
        path: '/read/import',
        builder: (_, _) => const ReadImportPage(),
      ),
      GoRoute(
        path: '/read/settings',
        builder: (_, s) => ReadSettingsPage(
          // ?sec= 定位组（书架长按菜单「调整长按菜单」→ 1＝内容显示与排序）。
          initialSec: int.tryParse(s.uri.queryParameters['sec'] ?? '') ?? 0,
        ),
      ),
      // 扫书脊 ISBN 全屏页（保真批F2 · 书籍表单「扫 ISBN」钮 push，命中 pop 回码值）。
      GoRoute(
        path: '/read/scan',
        builder: (_, _) => const IsbnScanPage(),
      ),
      // 书架资料单类管理页：?kind= 决定类（书架维度行「管理X」入口；默认来源）。
      GoRoute(
        path: '/read/mgr',
        builder: (_, s) {
          const kinds = ['source', 'group', 'tag', 'author', 'publisher'];
          final k = s.uri.queryParameters['kind'];
          return BookMgrPage(kind: kinds.contains(k) ? k! : 'source');
        },
      ),
      // V1.29批A4 记录管理二级页（原型 p-sub-recmg：四段设置归位 + 通用）。
      GoRoute(
        path: '/settings/recmg',
        builder: (_, _) => const RecmgSettingsPage(),
      ),
    ],
  );
});

/// V1.27 G1 返回语义（纯函数便于守护）：
/// 主页编排态 → endEdit（V1.28⑥：返回=退出编排并保存，不退 app）；
/// 非主页 → goToday（逐级返回最终落主页）；主页 2s 内二次返回 → exit；首次 → remind。
String shellBackAction(
  String currentPath, {
  bool dashEditing = false,
  DateTime? lastBackAt,
  DateTime? at,
}) {
  if (currentPath != NavModule.today.path) return 'goToday';
  if (dashEditing) return 'endEdit';
  final n = at ?? DateTime.now();
  if (lastBackAt != null &&
      n.difference(lastBackAt) < const Duration(seconds: 2)) {
    return 'exit';
  }
  return 'remind';
}

/// 底部导航（原型规范：线性图标 + 文字在下 + 选中态主题色 + 顶部小横条；
/// 栏目可配置，今天/我的固定，≤5）。
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.currentPath, required this.child});

  final String currentPath;
  final Widget child;

  /// G1：今天页二次返回退出计时（原型 _lastBackTs 2s 窗口）。
  static DateTime? _lastBackAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navModules = ref.watch(
      settingsControllerProvider.select((s) => s.navModules),
    );
    final tokens = context.tokens;

    final selectedIndex = navModules.indexWhere((m) => m.path == currentPath);
    // V1.28⑥：主页编排态下返回键=退出编排并保存（不进二次退出判定）。
    final dashEditing = ref.watch(dashDraftProvider) != null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // V1.29轮9：笔记批量多选态下返回=先退出多选（不导航不退出 app）
        if (ref.read(noteSelProvider).isNotEmpty) {
          ref.read(noteSelProvider.notifier).state = const {};
          return;
        }
        // V1.27 G1：返回=最终回主页；今天页二次返回退出（SnackBar 全局同款风格）
        switch (shellBackAction(
          currentPath,
          dashEditing: dashEditing,
          lastBackAt: _lastBackAt,
        )) {
          case 'goToday':
            _lastBackAt = null;
            context.go(NavModule.today.path);
          case 'endEdit':
            _lastBackAt = null;
            ref.read(dashDraftProvider.notifier).commit();
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(
                  content: Text('主页布局已保存 · 下次启动保持此顺序'),
                  duration: Duration(milliseconds: 1600),
                ),
              );
          case 'exit':
            _lastBackAt = null;
            SystemNavigator.pop();
          default:
            _lastBackAt = DateTime.now();
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(
                  content: Text('再按一次返回键退出 LifeHarness'),
                  duration: Duration(milliseconds: 2000),
                ),
              );
        }
      },
      child: Scaffold(
        body: TimerBarOverlay(child: child),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: tokens.navBg,
            border: Border(top: BorderSide(color: tokens.navBorder)),
          ),
          child: SafeArea(
            child: SizedBox(
              // 原型 nav 高度 70px
              height: 70,
              child: Row(
                children: [
                  for (var i = 0; i < navModules.length; i++)
                    Expanded(
                      child: _NavTab(
                        module: navModules[i],
                        selected: i == selectedIndex,
                        accent: tokens.accent,
                        onTap: () {
                          final m = navModules[i];
                          if (m.path != currentPath) context.go(m.path);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.module,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final NavModule module;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface;
    final color = selected ? accent : base.withValues(alpha: .62);
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 选中态顶部小横条指示
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 16,
            height: 3,
            decoration: BoxDecoration(
              color: selected ? accent : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 5),
          Icon(
            selected ? module.iconActive : module.icon,
            size: 22,
            color: color,
          ),
          const SizedBox(height: 2),
          Text(
            module.label,
            style: TextStyle(
              fontSize: 10.5,
              color: color,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
