import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifeharness/core/ai/ai_client.dart';
import 'package:lifeharness/core/ai/ai_prompt_pack.dart';
import 'package:lifeharness/core/ai/ai_providers.dart';
import 'package:lifeharness/core/ai/ai_vault.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/settings/presentation/ai_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// AI批 · 设置页组（AI 增强 / API 验证 / 提示词管理 / 编辑）。
/// 独立文件防 isolate 污染；验证页用 MockClient，零真实网络。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pack = AiPromptPack.decode(
      File('assets/ai_prompts/prompts.json').readAsStringSync());

  late SharedPreferences prefs;
  late AiKeyVault vault;
  late ProviderContainer container;
  late GoRouter router;

  /// 装配容器与路由（生产同路径 /settings/ai*），并停在 [start] 页。
  Future<void> pumpPage(WidgetTester tester,
      {String start = '/settings/ai',
      Map<String, Object> initialPrefs = const {},
      Future<http.Response> Function(http.Request)? handler}) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    prefs = await SharedPreferences.getInstance();
    vault = AiKeyVault.inMemory();
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      aiPromptPackProvider.overrideWithValue(pack),
      aiKeyVaultProvider.overrideWithValue(vault),
      aiClientProvider.overrideWithValue(AiClient(
        client: MockClient(handler ??
            (req) async {
              // 钉住验证页发出的最小请求形态（OpenAI 兼容 + Bearer Key）。
              final body = jsonDecode(req.body) as Map;
              expect(req.url.path, endsWith('/chat/completions'));
              expect(req.headers['Authorization'], 'Bearer sk-widget');
              expect(body['model'], 'deepseek-flash');
              return http.Response.bytes(
                  utf8.encode(jsonEncode({
                    'choices': [
                      {
                        'message': {'content': '连接成功'}
                      }
                    ],
                    'usage': {'prompt_tokens': 9, 'completion_tokens': 4}
                  })),
                  200,
                  headers: {
                    'content-type': 'application/json; charset=utf-8'
                  });
            }),
      )),
    ]);
    router = GoRouter(
      initialLocation: start,
      routes: [
        GoRoute(
            path: '/',
            builder: (_, _) => const SizedBox.shrink(),
            routes: [
              GoRoute(
                  path: 'settings/ai',
                  builder: (_, _) => const AiSettingsPage(),
                  routes: [
                    GoRoute(
                        path: 'verify',
                        builder: (_, _) => const AiVerifyPage()),
                    GoRoute(
                        path: 'prompts',
                        builder: (_, _) => const AiPromptsPage(),
                        routes: [
                          GoRoute(
                              path: 'edit',
                              builder: (_, s) =>
                                  AiPromptEditPage(taskId: s.extra as String)),
                        ]),
                  ]),
            ]),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router)));
    await settle5(tester);
  }

  String userText(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const ValueKey('ai-prompt-user')))
      .controller!
      .text;

  testWidgets('AI 增强页：默认渲染 + 总开关写盘与提示', (tester) async {
    await useSurface(tester);
    await pumpPage(tester);
    expect(find.text('服务商管理'), findsOneWidget);
    expect(find.text('Key 配置'), findsOneWidget);
    expect(find.text('AI 总开关'), findsOneWidget);
    expect(find.text('DeepSeek'), findsOneWidget);
    expect(find.text('● 当前'), findsOneWidget, reason: '默认端点=DeepSeek');
    expect(find.text('提示词管理'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai-master-switch')));
    await tester.pump();
    expect(prefs.getBool('ai.master'), isTrue);
    expect(await pollText(tester, '总开关已开：各能力仍逐项授权'), isTrue);
    await clearToasts(tester);
  });

  testWidgets('能力矩阵：开待办组 → 三个 todo 任务全部授权', (tester) async {
    await useSurface(tester);
    await pumpPage(tester, initialPrefs: {'ai.master': true});
    await tester.tap(find.byKey(const ValueKey('ai-cap-todo.nl_parse')));
    await tester.pumpAndSettle();
    final caps =
        jsonDecode(prefs.getString('ai.caps') ?? '{}') as Map<String, dynamic>;
    expect(caps['todo.nl_parse'], true);
    expect(caps['todo.quadrant'], true);
    expect(caps['todo.subtask'], true);
  });

  testWidgets('提示词管理：列表→编辑→保存覆盖→徽章与 prefs', (tester) async {
    await useSurface(tester);
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey('ai-prompts-entry')));
    await tester.pumpAndSettle();
    // 11 个能力点行
    expect(find.byKey(const ValueKey('ai-prompt-row-tool.verify')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('ai-prompt-row-ledger.categorize')),
        findsOneWidget);
    expect(find.textContaining('● 已覆盖'), findsNothing);

    await tester
        .tap(find.byKey(const ValueKey('ai-prompt-row-todo.quadrant')));
    await tester.pumpAndSettle();
    expect(userText(tester), contains('象限编号'));

    await tester.enterText(find.byKey(const ValueKey('ai-prompt-user')),
        '自定义：{{title}}→象限 JSON');
    await tester.tap(find.byKey(const ValueKey('ai-prompt-save')));
    await tester.pumpAndSettle();
    final ov = jsonDecode(prefs.getString('ai.prompt.todo.quadrant') ?? '{}')
        as Map<String, dynamic>;
    expect(ov['user'], '自定义：{{title}}→象限 JSON');
    // 回列表：徽章出现（文案含「›」后缀，用 containing）
    expect(find.textContaining('● 已覆盖'), findsOneWidget);
  });

  testWidgets('恢复默认清除覆盖；生效模板回到资产内容', (tester) async {
    await useSurface(tester);
    await pumpPage(tester);
    await prefs.setString(
        'ai.prompt.todo.quadrant', jsonEncode({'user': '旧的覆盖'}));
    final svc = container.read(aiServiceProvider);
    expect(svc.effectiveTask('todo.quadrant').user, '旧的覆盖');
    router.push('/settings/ai/prompts/edit', extra: 'todo.quadrant');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-prompt-reset')));
    await tester.pumpAndSettle();
    expect(prefs.getKeys().contains('ai.prompt.todo.quadrant'), isFalse);
    expect(svc.effectiveTask('todo.quadrant').user, contains('象限编号'));
  });

  testWidgets('API 验证页：发送（MockClient）→ 结果面板 + Key 落保险箱 + 状态记档',
      (tester) async {
    await useSurface(tester);
    await pumpPage(tester, start: '/settings/ai/verify');
    await tester.enterText(
        find.byKey(const ValueKey('ai-verify-key')), 'sk-widget');
    await tester.tap(find.byKey(const ValueKey('ai-verify-send')));
    await tester.pump(); // 进入 busy → 发请求
    await settle5(tester);
    expect(find.textContaining('验证通过'), findsOneWidget);
    expect(find.textContaining('模型回复：连接成功'), findsOneWidget);
    // V1.53.1：Key 按服务商分域落槽（验证页地址对上 DeepSeek 预置 → 存它自己槽位）。
    expect(await vault.readOwn('deepseek'), 'sk-widget');
    final v = jsonDecode(prefs.getString('ai.verify') ?? '{}');
    expect(v['ok'], true);
  });

  testWidgets('验证失败归因：401 → Key 无效文案，不落 Key', (tester) async {
    await useSurface(tester);
    await pumpPage(tester,
        start: '/settings/ai/verify',
        handler: (_) async => http.Response('{"error":"bad key"}', 401));
    await tester.enterText(
        find.byKey(const ValueKey('ai-verify-key')), 'sk-bad');
    await tester.tap(find.byKey(const ValueKey('ai-verify-send')));
    await tester.pump();
    await settle5(tester);
    expect(find.textContaining('Key 无效'), findsOneWidget);
    expect(await vault.read(), isNull);
    final v = jsonDecode(prefs.getString('ai.verify') ?? '{}');
    expect(v['ok'], false);
  });
}
