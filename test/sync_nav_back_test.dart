/// V1.41 R2 项④：导航返回退出 app 修复（settings_page `/sync`、`/log`；
/// sync_page `/sync/history`、`/log` 四处 `context.go` → `context.push`）。
///
/// 全量 SettingsPage 依赖主题注册表/DB/天气等重桩，不宜在导航微测里拉起。
/// 本测复刻 app 真实路由拓扑——`/settings` 在 ShellRoute 内、`/sync`·`/log`
/// 为顶层栈路由（见 app_router.dart），用一个走同款 `context.push` 的替身设置页，
/// 钉死「在 shell+stack 拓扑下 push 会保留上一页、系统返回回上一页而非退出 app；
/// 旧的 go 会把栈替换掉致返回键退出」这一行为类。真正的四处源行改动另由
/// sync_page_ui_test.dart「导航返回退出修复」组用真实 SyncPage 覆盖。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 以替身设置页复刻 app 拓扑：`/settings` 入 ShellRoute，`/log`·`/sync` 顶层栈；
  /// [nav] 注入 push（修复态）或 go（旧 bug 态）验证返回语义差异。
  Future<void> bootNav(WidgetTester tester,
      {required void Function(BuildContext, String) nav}) async {
    final router = GoRouter(initialLocation: '/settings', routes: [
      ShellRoute(
        builder: (_, _, child) => child,
        routes: [
          GoRoute(
            path: '/settings',
            builder: (context, _) => Scaffold(
              appBar: AppBar(title: const Text('设置替身')),
              body: Column(
                children: [
                  TextButton(
                      key: const ValueKey('entry-log'),
                      onPressed: () => nav(context, '/log'),
                      child: const Text('进日志')),
                  TextButton(
                      key: const ValueKey('entry-sync'),
                      onPressed: () => nav(context, '/sync'),
                      child: const Text('进同步')),
                ],
              ),
            ),
          ),
        ],
      ),
      GoRoute(
          path: '/log',
          builder: (_, _) => Scaffold(
              appBar: AppBar(title: const Text('LOG')),
              body: const Center(child: Text('LOG-STUB')))),
      GoRoute(
          path: '/sync',
          builder: (_, _) => Scaffold(
              appBar: AppBar(title: const Text('SYNC')),
              body: const Center(child: Text('SYNC-STUB')))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)));
    await settle5(tester);
  }

  testWidgets('push：从设置页进 /log 后系统返回回设置页（R2④ 修复态）',
      (tester) async {
    await bootNav(tester, nav: (ctx, path) => ctx.push(path));
    expect(find.text('设置替身'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('entry-log')));
    await settle5(tester);
    expect(find.text('LOG-STUB'), findsOneWidget);

    await tester.pageBack();
    await settle5(tester);
    expect(find.text('设置替身'), findsOneWidget,
        reason: 'push 压栈保留 /settings：返回键回设置页而非退出 app');
  });

  testWidgets('push：从设置页进 /sync 后系统返回回设置页', (tester) async {
    await bootNav(tester, nav: (ctx, path) => ctx.push(path));
    await tester.tap(find.byKey(const ValueKey('entry-sync')));
    await settle5(tester);
    expect(find.text('SYNC-STUB'), findsOneWidget);

    await tester.pageBack();
    await settle5(tester);
    expect(find.text('设置替身'), findsOneWidget);
  });

  testWidgets('回归反证：旧 go 替换栈 → 进 /log 后设置页已不在栈、返回键无处可回',
      (tester) async {
    await bootNav(tester, nav: (ctx, path) => ctx.go(path));
    await tester.tap(find.byKey(const ValueKey('entry-log')));
    await settle5(tester);
    expect(find.text('LOG-STUB'), findsOneWidget);
    // go 把 /settings 换下栈：/log 成根、无系统返回钮（返回即退出 app）。
    expect(find.text('设置替身'), findsNothing,
        reason: 'go 把 /settings 换下栈：/log 成根、返回即退出 app——正是被修复的 bug');
  });
}
