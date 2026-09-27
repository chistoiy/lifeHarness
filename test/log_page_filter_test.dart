import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/settings/presentation/log_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// 日志页「来源 × 关键词」筛选（真机反馈 2026-09-26：整屏混在一起看不出是谁报的错）。
/// 原型：index-sync.html p-log 的 srcChips / logKw / logCount。
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
        matching: find.textContaining(RegExp(r'^\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.')),
      );

  int lineCount(WidgetTester tester) => logLines().evaluate().length;

  String countText(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('log-count')))
      .data!;

  testWidgets('来源 chips：按窗口内实际来源生成，「系统」收尾', (tester) async {
    AppLog.add('PROPFIND /sync → 207', src: '同步');
    AppLog.add('429 退避重发', level: LhLevel.warn, src: '同步');
    AppLog.add('AI 调用成功（read.toc）', src: 'AI');
    AppLog.add('手工一行');
    await openLogPage(tester);

    expect(find.byKey(const ValueKey('log-src-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('log-src-同步')), findsOneWidget);
    expect(find.byKey(const ValueKey('log-src-AI')), findsOneWidget);
    expect(find.byKey(const ValueKey('log-src-系统')), findsOneWidget);
    // 每行行首要能看出来源（复制/渲染同一 formatted）。
    expect(
        tester
            .widgetList<Text>(logLines())
            .every((t) => t.data!.contains('] [')),
        isTrue);
  });

  testWidgets('点来源 chip 只看该来源；再点回全部', (tester) async {
    for (var i = 0; i < 3; i++) {
      AppLog.add('同步行$i', src: '同步');
    }
    AppLog.add('AI 行', src: 'AI');
    AppLog.add('阅读 行', src: '阅读');
    await openLogPage(tester);
    expect(lineCount(tester), 5);

    await tester.tap(find.byKey(const ValueKey('log-src-同步')));
    await settle5(tester);
    expect(lineCount(tester), 3);
    expect(
        tester.widgetList<Text>(logLines()).every((t) => t.data!.contains('[同步]')),
        isTrue);
    expect(countText(tester), startsWith('3 条'));

    await tester.tap(find.byKey(const ValueKey('log-src-同步')));
    await settle5(tester);
    expect(lineCount(tester), 5, reason: '再点同一 chip 取消筛选（chips 互斥单选口径）');
  });

  testWidgets('关键词 + 级别 + 来源三重叠加', (tester) async {
    AppLog.add('PROPFIND /sync → 207', src: '同步');
    AppLog.add('PROPFIND 失败 500', level: LhLevel.error, src: '同步');
    AppLog.add('PROPFIND 无关行', src: '阅读');
    AppLog.add('同步摘要 · 上传 3', src: '同步');
    await openLogPage(tester);

    await tester.enterText(find.byKey(const ValueKey('log-kw')), 'PROPFIND');
    await settle5(tester);
    expect(lineCount(tester), 3);

    await tester.tap(find.byKey(const ValueKey('log-src-阅读')));
    await settle5(tester);
    expect(lineCount(tester), 1, reason: '关键词 × 来源');

    await tester.tap(find.byKey(const ValueKey('log-src-同步')));
    await settle5(tester);
    await tester.tap(find.text('错误'));
    await settle5(tester);
    expect(lineCount(tester), 1, reason: '关键词 × 来源 × 级别三重叠加');
    expect(countText(tester), startsWith('1 条'));
  });

  testWidgets('无匹配时窗口空态：0 条而不是崩', (tester) async {
    AppLog.add('只有一行', src: '同步');
    await openLogPage(tester);
    await tester.enterText(find.byKey(const ValueKey('log-kw')), '查无此词');
    await settle5(tester);
    expect(lineCount(tester), 0);
    expect(countText(tester), startsWith('0 条'));
  });
}
