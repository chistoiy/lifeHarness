import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/settings/presentation/log_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// 日志页「来源 × 关键词 × 级别」三重筛选（真机反馈：看不出是谁报的错）。
/// 原型 p-logs 齿轮弹层「筛选」Tab 的 srcRow / logKwInp / 级别分段。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    AppLog.reset();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  tearDown(AppLog.reset);

  Future<void> openLogPage(WidgetTester tester) async {
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.go('/log'),
                child: const Text('goto-log'),
              ),
            ),
          ),
        ),
      ),
      GoRoute(path: '/log', builder: (_, _) => const LogPage()),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle5(tester);
    await tester.tap(find.text('goto-log'));
    await settle5(tester);
    await useSurface(tester, const Size(900, 2600));
    await settle5(tester);
  }

  Finder logLines() => find.descendant(
        of: find.byKey(const ValueKey('log-list')),
        matching: find.textContaining(
            RegExp(r'^\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.')),
      );

  int lineCount(WidgetTester tester) => logLines().evaluate().length;

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('log-settings-gear')));
    await settle5(tester);
  }

  Future<void> closeSheet(WidgetTester tester) async {
    // 点弹层上方 barrier 空白（barrierDismissible 默认开）关闭底部弹层。
    await tester.tapAt(const Offset(450, 4));
    await settle5(tester);
  }

  testWidgets('来源胶囊：按窗口内实际来源生成，「系统」收尾', (tester) async {
    AppLog.add('PROPFIND /sync → 207', src: '同步');
    AppLog.add('429 退避重发', level: LhLevel.warn, src: '同步');
    AppLog.add('AI 调用成功（read.toc）', src: 'AI');
    AppLog.add('手工一行');
    await openLogPage(tester);
    await openSheet(tester);

    expect(find.byKey(const ValueKey('log-src-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('log-src-同步')), findsOneWidget);
    expect(find.byKey(const ValueKey('log-src-AI')), findsOneWidget);
    expect(find.byKey(const ValueKey('log-src-系统')), findsOneWidget);
    await closeSheet(tester);
  });

  testWidgets('点来源胶囊只看该来源；再点回全部', (tester) async {
    for (var i = 0; i < 3; i++) {
      AppLog.add('同步行$i', src: '同步');
    }
    AppLog.add('AI 行', src: 'AI');
    AppLog.add('阅读 行', src: '阅读');
    await openLogPage(tester);
    expect(lineCount(tester), 5);

    await openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('log-src-同步')));
    await settle5(tester);
    await closeSheet(tester);
    expect(lineCount(tester), 3, reason: '关键词×来源：只剩同步 3 行');

    await openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('log-src-同步')));
    await settle5(tester);
    await closeSheet(tester);
    expect(lineCount(tester), 5,
        reason: '再点同一胶囊取消筛选（互斥单选口径）');
  });

  testWidgets('关键词 + 来源 + 级别三重叠加', (tester) async {
    AppLog.add('PROPFIND /sync → 207', src: '同步');
    AppLog.add('PROPFIND 失败 500', level: LhLevel.error, src: '同步');
    AppLog.add('PROPFIND 无关行', src: '阅读');
    AppLog.add('同步摘要 · 上传 3', src: '同步');
    await openLogPage(tester);

    await openSheet(tester);
    await tester.enterText(find.byKey(const ValueKey('log-kw')), 'PROPFIND');
    await settle5(tester);
    await closeSheet(tester);
    expect(lineCount(tester), 3, reason: '关键词命中 3 行');

    await openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('log-src-阅读')));
    await settle5(tester);
    await closeSheet(tester);
    expect(lineCount(tester), 1, reason: '关键词 × 来源');

    await openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('log-src-同步')));
    await settle5(tester);
    await tester.tap(find.text('错误'));
    await settle5(tester);
    await closeSheet(tester);
    expect(lineCount(tester), 1, reason: '关键词 × 来源 × 级别三重叠加');
  });

  testWidgets('无匹配时窗口空态：0 条而不是崩', (tester) async {
    AppLog.add('只有一行', src: '同步');
    await openLogPage(tester);
    await openSheet(tester);
    await tester.enterText(find.byKey(const ValueKey('log-kw')), '查无此词');
    await settle5(tester);
    await closeSheet(tester);
    expect(lineCount(tester), 0);
    expect(find.text('无匹配日志'), findsOneWidget);
  });
}
