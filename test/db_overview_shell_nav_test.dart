/// B-4 概览屏「按模块查看」直达在**真 HomeShell + 真路由表 + ffi 真库**下的
/// 渲染冒烟：壳内 tab（记账）与栈路由（书架）两条直达都必须渲染出正文。
/// 真机 6066 的白屏在本 harness **不复现**：push 壳 tab 在 widget 环境照样渲染
/// （连「概览屏也由 push 进入」的对照也试过，仍绿）；且应用侧三处全局错误捕获
/// 已挂（`error_capture`），真机日志页在两次白屏时段零异常行——即白屏无 Dart
/// 异常，是 release 真包上的渲染/路由态差异，widget 侧够不着。
/// 因此本用例是「直达必须出正文」的**近似回归面**，最终判定在复测包真机门。
///
/// 全 app 唯一用例（一文件一条）。**一切真异步（建库/读主题资产）一律放
/// setUpAll**：在 testWidgets 的 FakeAsync 区里 await 真 I/O 会永挂
/// （实测连前置 print 都不落盘，10 分钟零帧）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeharness/app.dart';
import 'package:lifeharness/core/backup/db_overview.dart';
import 'package:lifeharness/core/router/app_router.dart'
    show dbOverviewBackupSizeReaderProvider;
import 'package:lifeharness/core/database/app_database.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/theme/theme_repository.dart';
import 'package:lifeharness/shared/trash/trash_models.dart';
import 'package:lifeharness/shared/trash/trash_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// 有界推帧（不判收敛）：仪表盘开着时 pumpAndSettle 永不收敛（存量呼吸动画）。
Future<void> pumpFrames(WidgetTester tester, [int n = 30]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// 只钉导航不测扫描：scanner 给固定画像（含记账/阅读两条模块行）。
class _FakeScanner implements DbOverviewScanner {
  @override
  Future<DbOverview> scan() async => const DbOverview(
        rows: [
          DbOverviewRow(
              table: 'ledger_txns', label: '账单流水', module: '记账', rows: 160),
          DbOverviewRow(
              table: 'books', label: '书籍在册', module: '阅读', rows: 6),
        ],
        totalRows: 166,
        regenerableRows: 0,
        byModule: [
          (module: '记账', rows: 160, tables: 6),
          (module: '阅读', rows: 6, tables: 4),
        ],
        emptyTableCount: 0,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('DbOverviewScanner.${invocation.memberName}');
}

void main() {
  late Directory tmp;
  late SharedPreferences prefs;
  late ThemeRegistry registry;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('dbo_nav');
    await AppDatabase.instance.open(pathOverride: tmp.path);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    registry = await const ThemeRepository().loadAll();
  });

  tearDownAll(() async {
    await AppDatabase.instance.close();
    await tmp.delete(recursive: true);
  });

  Future<void> openOverview(WidgetTester tester) async {
    await useSurface(tester, const Size(480, 1280));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        themeRegistryProvider.overrideWithValue(registry),
        dbOverviewScannerProvider.overrideWithValue(_FakeScanner()),
        trashItemsProvider.overrideWith((ref) async => const <TrashItem>[]),
        dbOverviewBackupSizeReaderProvider.overrideWithValue(() async => null),
      ],
      child: const LifeHarnessApp(),
    ));
    await pumpFrames(tester);
    tester.element(find.text('今天').first).go('/settings/db-overview');
    await pumpFrames(tester);
    expect(find.text('数据库概览'), findsOneWidget, reason: '应落在概览屏');
  }

  // 全 app 唯一用例：两条直达路径同用例内跑（底栏切枚可回壳态，不重开 app）。
  testWidgets('概览屏直达：壳内 tab 出正文、栈路由不回归', (tester) async {
    await openOverview(tester);

    // ① 壳内 tab（记账）：直达必须渲染记账主页正文，不许只剩底栏。
    await tester.ensureVisible(find.byKey(const ValueKey('dbo-mod-记账')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('dbo-mod-记账')));
    await pumpFrames(tester);
    expect(find.text('本地账本 · 全离线'), findsOneWidget,
        reason: '直达落点必须出正文（真机 6066 白屏＝只剩底栏）');

    // ② 回概览再直达栈路由（阅读·书架）：push 保栈口径不回归。
    tester.element(find.text('今天').last).go('/settings/db-overview');
    await pumpFrames(tester);
    expect(find.text('数据库概览'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('dbo-mod-阅读')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('dbo-mod-阅读')));
    await pumpFrames(tester);
    expect(find.text('今年读完'), findsOneWidget, reason: '书架页应渲染');

    // 收尾排空 sqflite 的 10s 看门狗假定时器（真库查询在 FakeAsync 区留下的），
    // 否则判「Pending timers」。
    await tester.pump(const Duration(seconds: 11));
  });
}
