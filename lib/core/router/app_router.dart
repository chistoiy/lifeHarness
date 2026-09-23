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
import '../../features/todo/presentation/widgets/pomo_screen.dart';
import '../../features/todo/presentation/todo_providers.dart' show PomoSession;
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/dashboard/presentation/dashboard_providers.dart';
import '../../features/habit/presentation/habit_detail_page.dart';
import '../../features/habit/presentation/habit_stat_page.dart';
import '../../features/habit/presentation/habits_page.dart';
import '../../features/inbox/presentation/inbox_page.dart';
import '../../features/journal/presentation/diary_edit_page.dart';
import '../../features/journal/presentation/journal_page.dart';
import '../../features/journal/presentation/journal_providers.dart'
    show noteSelProvider;
import '../../features/journal/presentation/note_edit_page.dart';
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
          GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
          GoRoute(path: '/categories', builder: (_, _) => const CategoryPage()),
        ],
      ),
      // 番茄全屏专注页：全屏无底栏（V1.27 T7），extra 传会话。
      GoRoute(
        path: '/pomo',
        builder: (_, s) => PomoScreen(session: s.extra as PomoSession),
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
