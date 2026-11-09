/// B-4 真机走查抓到的 P0 复现（6066·雷电）：概览屏「按模块查看」行直达对
/// **壳内 tab 路由**（/ledger 等 13 条）用 `context.push`，落点只剩底栏白屏；
/// 栈路由（/read/shelf）push 正常。本文件用最小真路由钉死两条口径：
/// 壳 tab → `go`；栈页 → `push`（保「返回=回概览」）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeharness/core/backup/db_overview.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/settings/presentation/db_overview_page.dart';
import 'package:lifeharness/shared/trash/trash_providers.dart';

import 'helpers.dart';

class _FakeScanner implements DbOverviewScanner {
  @override
  Future<DbOverview> scan() async => DbOverview(
        rows: const [
          DbOverviewRow(
              table: 'ledger_txns', label: '账单流水', module: '记账', rows: 160),
        ],
        totalRows: 160,
        regenerableRows: 0,
        byModule: const [(module: '记账', rows: 160, tables: 1)],
        emptyTableCount: 0,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('DbOverviewScanner.${invocation.memberName}');
}

Widget _page(String title) => Scaffold(
      appBar: AppBar(title: Text('$title·页')),
      body: Center(child: Text(title)),
    );

/// 最小真路由：一条 ShellRoute（builder 带底栏占位，形态与 HomeShell 同构）
/// 挂 /ledger，栈层挂 /read/shelf，另设一条与概览同层的设置栈页。
RouterConfig<Object> _router() => GoRouter(
      initialLocation: '/settings/db-overview',
      routes: [
        ShellRoute(
          builder: (context, state, child) => Scaffold(
            body: child,
            bottomNavigationBar: const SizedBox(
                height: 56, child: Center(child: Text('FAKE-BOTTOM-NAV'))),
          ),
          routes: [
            GoRoute(path: '/ledger', builder: (_, _) => _page('记账')),
          ],
        ),
        GoRoute(
          path: '/read/shelf',
          builder: (_, _) => _page('书架'),
        ),
        GoRoute(
          path: '/settings/db-overview',
          builder: (_, _) => DbOverviewPage(backupSizeReader: () async => null),
        ),
      ],
    );

Future<void> _openOverview(WidgetTester tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      dbOverviewScannerProvider.overrideWithValue(_FakeScanner()),
      trashItemsProvider.overrideWith((ref) async => const []),
    ],
    child: MaterialApp.router(routerConfig: _router()),
  ));
  await settle5(tester);
  expect(find.byKey(const ValueKey('dbo-mod-记账')), findsOneWidget);
}

void main() {
  testWidgets('记账行（壳内 tab）直达：落点必须渲染记账主页，不许只剩底栏',
      (tester) async {
    await _openOverview(tester);
    await tester.tap(find.byKey(const ValueKey('dbo-mod-记账')));
    await settle5(tester);
    expect(find.text('记账'), findsOneWidget,
        reason: '壳内 tab 必须用 go 直达（真机 push 只剩底栏）');
    expect(find.text('FAKE-BOTTOM-NAV'), findsOneWidget);
  });

  testWidgets('阅读行（栈路由）直达：push 保栈，返回键回概览', (tester) async {
    final o = DbOverview(
      rows: const [],
      totalRows: 0,
      regenerableRows: 0,
      byModule: const [(module: '阅读', rows: 6, tables: 1)],
      emptyTableCount: 0,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dbOverviewScannerProvider
            .overrideWithValue(_ScannerOf(o)),
        trashItemsProvider.overrideWith((ref) async => const []),
      ],
      child: MaterialApp.router(routerConfig: _router()),
    ));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('dbo-mod-阅读')));
    await settle5(tester);
    expect(find.text('书架'), findsOneWidget);
    await tester.pageBack();
    await settle5(tester);
    expect(find.text('数据库概览'), findsOneWidget,
        reason: '栈页直达的返回必须落回概览屏');
  });

  test('常驻守护：直达表每条路径真实登记，壳/栈分派集合与各 *ShellRoutes() 一致',
      () {
    final routesDir = Directory('lib/features');
    expect(routesDir.existsSync(), isTrue, reason: '需在仓库根跑');
    final shellPaths = <String>{};
    final allPaths = <String>{};
    for (final f in routesDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('_routes.dart'))) {
      final src = f.readAsStringSync();
      final shellBlock = RegExp(
              r'List<GoRoute> \w+ShellRoutes\(\) => \[.*?\n\];',
              dotAll: true)
          .allMatches(src);
      for (final b in shellBlock) {
        allPaths.addAll(RegExp(r"path: '(/[^']*)'")
            .allMatches(b.group(0)!)
            .map((m) => m.group(1)!));
        shellPaths.addAll(RegExp(r"path: '(/[^']*)'")
            .allMatches(b.group(0)!)
            .map((m) => m.group(1)!));
      }
      allPaths.addAll(RegExp(r"path: '(/[^']*)'")
          .allMatches(src)
          .map((m) => m.group(1)!));
    }
    // ① 直达表每条路径（去 query）都必须在路由表里真实登记。
    for (final e in kDbOverviewModuleRoutes.entries) {
      final path = e.value.split('?').first;
      expect(allPaths, contains(path),
          reason: '模块「${e.key}」直达路径 $path 未登记，点了必白屏/落兜底');
    }
    // ② 壳集合分派口径：直达表里属于壳 tab 的恰为 kDbOverviewShellPaths。
    for (final e in kDbOverviewModuleRoutes.entries) {
      final path = e.value.split('?').first;
      expect(kDbOverviewShellPaths.contains(path), shellPaths.contains(path),
          reason: '模块「${e.key}」$path 的壳/栈归类与路由登记不符');
    }
  });
}

class _ScannerOf implements DbOverviewScanner {
  _ScannerOf(this.result);
  final DbOverview result;

  @override
  Future<DbOverview> scan() async => result;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('DbOverviewScanner.${invocation.memberName}');
}
