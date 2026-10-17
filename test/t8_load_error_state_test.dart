import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:lifeharness/shared/widgets/load_error_state.dart';

import 'helpers.dart';

/// 交互整改 T8（加载失败别装空）常驻用例。
///
/// 版式事实源＝记账专版 L1 顶部卡 `#finErr`（2026-10-05 产品过门「照此接 care/todo 两线」）。
/// 原来三处高频页的 error 分支是 `Text('加载失败：$e')`——原始异常直接甩给用户，
/// 既读不懂也没有出口；本件把「人话标题 · 未受影响安抚 · 重试 · 查看详情」钉成一份实现。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> mount(WidgetTester tester,
      {required Object err, required void Function() onRetry}) async {
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => LoadErrorBanner(
            title: '这个账本没加载出来', error: err, onRetry: onRetry),
      ),
      GoRoute(
        path: '/log',
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('日志页桩'))),
      ),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await settle5(tester);
  }

  group('1 · 版式四件套', () {
    testWidgets('标题＋人话原因句＋重试＋查看详情都在，且不外泄异常类名', (tester) async {
      var retried = 0;
      await mount(tester,
          err: Exception('TimeoutException after 0:00:03: Future not completed'),
          onRetry: () => retried++);
      expect(find.byKey(const ValueKey('load-error-title')), findsOneWidget);
      expect(find.text('这个账本没加载出来'), findsOneWidget);
      final reason = find.byKey(const ValueKey('load-error-reason'));
      expect(reason, findsOneWidget);
      final txt = (tester.widget<Text>(reason)!).data ?? '';
      expect(txt, contains('本机数据未受影响'),
          reason: '安抚句必须在：用户要先知道数据没丢');
      expect(txt, contains('请求超时'), reason: '原因句走 humanizeError');
      expect(txt, isNot(contains('TimeoutException')),
          reason: '原始类名不许出现在给用户看的那一行');
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('查看详情'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('load-error-retry')));
      await settle5(tester);
      expect(retried, 1, reason: '重试只触发取数，不导航');
      expect(find.text('日志页桩'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('load-error-detail')));
      await settle5(tester);
      expect(find.text('日志页桩'), findsOneWidget, reason: '查看详情＝去日志页找全量');
    });

    testWidgets('图标是线性描边、全卡无 emoji', (tester) async {
      await mount(tester, err: Exception('boom'), onRetry: () {});
      expect(find.byIcon(Icons.report_outlined), findsOneWidget);
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ');
      expect(RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true)
          .hasMatch(texts), isFalse, reason: 'UI 禁 emoji 图标');
    });

    testWidgets('认不出的异常原样回落，不编造解释', (tester) async {
      await mount(tester, err: Exception('sqlite busy'), onRetry: () {});
      final txt = (tester
              .widget<Text>(find.byKey(const ValueKey('load-error-reason')))!)
          .data!;
      expect(txt, startsWith('本机数据未受影响 · '));
      expect(txt.length, greaterThan('本机数据未受影响 · '.length));
    });
  });

  group('2 · 源码守护（三线接线＋只有一份实现）', () {
    String read(String rel) => File('lib/$rel').readAsStringSync();

    test('三线 error 分支都换成失败态，且不再甩原始异常', () {
      final cases = {
        'features/ledger/presentation/ledger_page.dart': '这个账本没加载出来',
        'features/care/presentation/vaccine_page.dart': '疫苗接种计划没加载出来',
        'features/todo/presentation/todo_page.dart': '待办清单没加载出来',
      };
      for (final e in cases.entries) {
        final src = read(e.key);
        expect(src, contains('LoadErrorBanner('), reason: '${e.key} 未接失败态');
        expect(src, contains(e.value), reason: '${e.key} 缺语境标题');
        expect(src, contains('ref.invalidate('), reason: '${e.key} 重试要重取数');
        expect(src, isNot(contains("Text('加载失败：")),
            reason: '${e.key} 不许回潮成甩原始异常');
      }
    });

    test('失败态全仓只有一份实现', () {
      final hits = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) =>
              f.readAsStringSync().contains('class LoadErrorBanner'))
          .length;
      expect(hits, 1, reason: '版式分叉＝逐页各画一张，改一处漏 N 处');
    });
  });
}
