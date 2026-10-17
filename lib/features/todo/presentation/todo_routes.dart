// 治理G6：自 core/router/app_router.dart 按域下沉（path/builder 零改动）。
import 'package:flutter/material.dart' show MaterialPage;
import 'package:go_router/go_router.dart';

import 'widgets/pomo_screen.dart';
import 'todo_providers.dart' show PomoSession;
import 'todo_page.dart';


/// 底部导航壳内路由（原 ShellRoute 登记 · 治理G6 下沉）
List<GoRoute> todoShellRoutes() => [
        GoRoute(path: '/todo', builder: (_, _) => const TodoPage())
];

/// `/pomo` 的入参闸（T10 路由收口）：专注会话只能由待办/日历页带着
/// [PomoSession] 进来；深链或参数形状不对时回落待办主页，**不再让 `extra as`
/// 抛异常**（那会落 go_router 的工程错误页＝白屏一族）。
String? pomoRedirect(Object? extra) => extra is PomoSession ? null : '/todo';

/// 全屏栈路由（治理G6 下沉）
List<GoRoute> todoPageRoutes() => [
        // 番茄全屏专注页：全屏无底栏（V1.27 T7），extra 传会话。
          // T10 路由收口：`extra` 缺失或形状不对时**不再抛 cast 异常**（那会落
          // go_router 的工程错误页＝白屏一族），直接回落待办主页——
          // 专注会话只能由待办/日历页发起，深链本就不该带着它。
          // 原先这里是待办行上的匿名 `Navigator.push(fullscreenDialog: true)`，
          // 收进路由表后 `fullscreenDialog` 由 pageBuilder 原样保留（观感不变）。
          GoRoute(
            path: '/pomo',
            redirect: (_, s) => pomoRedirect(s.extra),
            pageBuilder: (_, s) => MaterialPage<void>(
              fullscreenDialog: true,
              child: PomoScreen(session: s.extra as PomoSession),
            ),
          )
        // V1.60：待办垃圾箱专屏 `/todo/trash` 已下架，入口改道全局回收站
        //   `/settings/trash?seg=todo`（登记在 settings_routes）。
];
