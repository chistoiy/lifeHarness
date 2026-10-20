import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/settings/presentation/log_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// V1.53.4 R14-11 · 日志页三条口径的回归钉桩（原型 fbfe639 同步落地）：
///  ① 单栏行内流（不再左右分栏，长内容占满整行）；
///  ② 倒序（最新在上）；
///  ③ 堆栈行默认折叠，「展开堆栈/收起堆栈」可切换，复制仍走全量。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  Future<void> seedPrefs() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  }

  setUp(() => AppLog.reset());
  tearDown(() => AppLog.reset());

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

  /// 日志窗内整行的纯文本（行 key 在 GestureDetector 上；来源胶囊是行内 WidgetSpan
  /// 的独立 Text，按「以日期开头」过滤掉）。
  List<String> rendered(WidgetTester tester) => find
      .descendant(
          of: find.byKey(const ValueKey('log-list')), matching: find.byType(Text))
      .evaluate()
      .map((el) => ((el.widget as Text).textSpan ??
              TextSpan(text: (el.widget as Text).data))
          .toPlainText()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim())
      .where((s) => RegExp(r'^\d{2}-\d{2} ').hasMatch(s))
      .toList();

  /// 整行主 Text（排除来源胶囊那枚短 Text）。
  List<Text> renderedWidgets(WidgetTester tester) => find
      .descendant(
          of: find.byKey(const ValueKey('log-list')), matching: find.byType(Text))
      .evaluate()
      .map((el) => el.widget as Text)
      .where((t) => RegExp(r'^\d{2}-\d{2} ').hasMatch(
          (t.textSpan ?? TextSpan(text: t.data)).toPlainText().replaceAll(RegExp(r'\s+'), ' ').trim()))
      .toList();

  const stack = '#0 NavigatorState._routeNamed (navigator.dart:4646) | '
      '#1 NavigatorState.pushNamed (navigator.dart:4714) | '
      '#2 _ReaderPageState._openMoreSheet (reader_page.dart:579)';

  testWidgets('R14-11 · 单栏行内流：整行一个 Text.rich，不再分栏', (tester) async {
    await seedPrefs();
    AppLog.add('单栏验证行');
    await openLogPage(tester);

    final mains = renderedWidgets(tester);
    expect(mains.length, 1, reason: '整行只有主 Text（来源胶囊是行内 WidgetSpan 的短 Text）');
    final w = mains.single;
    expect((w.textSpan! as TextSpan).children, isNotNull,
        reason: '行内流靠 TextSpan 子件，不是 Row 分栏');
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('log-list')), matching: find.byType(Row)),
        findsNothing);
    final plain = w.textSpan!.toPlainText();
    expect(plain, contains('单栏验证行'));
    expect(
        RegExp(r'^\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} INFO ').hasMatch(
            plain.replaceAll('\n', ' ')),
        isTrue,
        reason: '时间戳/级别与正文同一段行内流（来源为行内胶囊子件）');
  });

  testWidgets('R14-11 · 倒序：最新一行在最上', (tester) async {
    await seedPrefs();
    AppLog.add('最旧一条');
    AppLog.add('中间一条');
    AppLog.add('最新一条');
    await openLogPage(tester);

    final rows = rendered(tester);
    expect(rows.length, 3);
    expect(rows.first, contains('最新一条'));
    expect(rows[1], contains('中间一条'));
    expect(rows.last, contains('最旧一条'));
    // 页头明示排序口径。
    expect(find.textContaining('最新在上'), findsOneWidget);
  });

  testWidgets('R14-11 · 堆栈行默认折叠，可展开/收起', (tester) async {
    await seedPrefs();
    AppLog.addStack(stack);
    await openLogPage(tester);

    // 折叠态：堆栈段整段不建 Text，只留「展开堆栈」钮。
    expect(find.byKey(const ValueKey('log-stack')), findsNothing);
    expect(find.byKey(const ValueKey('log-stk-open')), findsOneWidget);
    expect(find.text('收起堆栈'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('log-stk-open')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('log-stack')), findsOneWidget);
    expect(find.textContaining('NavigatorState._routeNamed'), findsOneWidget);
    expect(find.byKey(const ValueKey('log-stk-close')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('log-stk-close')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('log-stack')), findsNothing);
    expect(find.byKey(const ValueKey('log-stk-open')), findsOneWidget);
  });
}
