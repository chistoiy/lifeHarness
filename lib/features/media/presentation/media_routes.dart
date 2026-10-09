import 'package:go_router/go_router.dart';

import 'media_detail_page.dart';
import 'media_goal_page.dart';
import 'media_info_page.dart';
import 'media_list_page.dart';
import 'media_lists_page.dart';
import 'media_mgr_page.dart';
import 'media_notes_page.dart';
import 'media_set_page.dart';
import 'media_sesslog_page.dart';
import 'media_shelf_page.dart';
import 'media_stat_page.dart';
import 'media_timer_page.dart';

/// 影音游 · 全屏栈路由（批2 架面 · 批3 详情/计时 · 批5 笔记库）。
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
  // 影音笔记库（原型 m-notes · 词典 LH-C18 · 批5）：入口＝架顶栏与记录页影音段各一行直达。
  GoRoute(path: '/media/notes', builder: (_, _) => const MediaNotesPage()),
  // 全站统计（原型 m-stat · 词典 LH-C21 · 批7）：入口＝工作台图标条「统计」一枚。
  GoRoute(path: '/media/stat', builder: (_, _) => const MediaStatPage()),
  // 影音目标（原型 m-goal · 词典 LH-C22 · 批8a）：入口＝统计屏目标块＋工作台「目标」。
  GoRoute(path: '/media/goal', builder: (_, _) => const MediaGoalPage()),
  // 影音设置（原型 m-set · 词典 LH-C23 · 批8a）：入口＝工作台图标条第 8 枚「设置」。
  GoRoute(path: '/media/settings', builder: (_, _) => const MediaSetPage()),
  // 影音单列表面（原型 m-lists · 批8b）：入口＝工作台直达行；底稿置顶零落库。
  GoRoute(path: '/media/lists', builder: (_, _) => const MediaListsPage()),
  // 影音单详情面（原型 m-list · 批8b）：`:id`＝auto（年度底稿·只读）或手动单 id。
  GoRoute(
    path: '/media/list/:id',
    builder: (_, s) => MediaListPage(listId: s.pathParameters['id']!),
  ),
  // 条目详情（原型 m-detail）：点架卡/速览的正式落面。
  GoRoute(
    path: '/media/item/:id',
    builder: (_, s) => MediaDetailPage(itemId: s.pathParameters['id']!),
  ),
  // 条目资料（原型 m-info · LH-C16）：档案全字段＋一页总结＋明细入口。
  GoRoute(
    path: '/media/item/:id/info',
    builder: (_, s) => MediaInfoPage(itemId: s.pathParameters['id']!),
  ),
  // 计时明细（原型 m-sesslog · LH-C17）：整屏逐条改／删／补记。
  GoRoute(
    path: '/media/item/:id/sessions',
    builder: (_, s) => MediaSesslogPage(itemId: s.pathParameters['id']!),
  ),
  // 沉浸计时（原型 m-timer）：入口＝详情页计时钮（timerUI=full 直落本页；
  // capsule 档起停走悬浮条，进本页只作展开视图）。
  GoRoute(
    path: '/media/timer/:id',
    builder: (_, s) => MediaTimerPage(itemId: s.pathParameters['id']!),
  ),
  // 通用管理器（原型 m-mgr）：`?tab=` 指定类，缺省＝来源。
  GoRoute(
    path: '/media/mgr',
    builder: (_, s) => MediaMgrPage(
      initialTab: s.uri.queryParameters['tab'],
    ),
  ),
];
