import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/ai/ai_call_store.dart';
import 'package:lifeharness/core/ai/ai_config.dart';
import 'package:lifeharness/core/ai/ai_verify_channel.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/kits/data/kit_repository.dart';
import 'package:lifeharness/features/kits/presentation/kit_providers.dart';
import 'package:lifeharness/features/kits/presentation/kit_routes.dart';
import 'package:lifeharness/features/kits/presentation/tools/kit_aiapi_page.dart';
import 'package:lifeharness/features/kits/presentation/tools/kit_tools_kit.dart';

/// V1.47 批3e · AI API 验证屏。
/// 真实出站与保险箱读取一律经 KitAiapi 注入缝（测试里零网络、零 Key 明文）；
/// 结果卡的每一行都由域层按缝返回值实拼。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late KitRepository repo;
  late ProviderContainer container;

  const presets = [
    AiProvider(id: 'deepseek', name: 'DeepSeek', baseUrl: 'https://api.deepseek.com/v1', model: 'deepseek-flash'),
    AiProvider(
      id: 'claude',
      name: 'Anthropic',
      baseUrl: 'https://api.anthropic.com/v1',
      model: 'claude-3-5-haiku-latest',
      protocol: 'anthropic',
    ),
  ];
  bool hasKeyResult = false;
  int runCalls = 0;
  int mockCalls = 0;
  String capUrl = '', capModel = '', capKey = '', capPrompt = '', capProto = '';
  AiVerifyResult Function() nextResult = () => const AiVerifyResult(
    ok: true,
    ms: 321,
    reply: '连接成功',
    inTok: 9,
    outTok: 4,
  );
  List<AiCallRecord> hist = const [];

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = KitRepository(db);
    SharedPreferences.setMockInitialValues({});
    hasKeyResult = false;
    runCalls = 0;
    mockCalls = 0;
    capUrl = '';
    capModel = '';
    capKey = '';
    capPrompt = '';
    capProto = '';
    nextResult = () => const AiVerifyResult(ok: true, ms: 321, reply: '连接成功', inTok: 9, outTok: 4);
    hist = const [];
    KitAiapi.presets = (ref) => presets;
    KitAiapi.hasKey = (ref, id) async => hasKeyResult;
    KitAiapi.run = (ref, url, model, key, prompt, protocol) async {
      runCalls++;
      capUrl = url;
      capModel = model;
      capKey = key;
      capPrompt = prompt;
      capProto = protocol;
      return nextResult();
    };
    KitAiapi.mock = (prompt) async {
      mockCalls++;
      return const AiVerifyResult(
        ok: true,
        mock: true,
        ms: 812,
        reply: '连接成功',
        inTok: 9,
        outTok: 4,
      );
    };
    KitAiapi.history = (ref) async => hist;
    KitAiapi.clearHistory = (ref) async {
      hist = const [];
      return 2;
    };
  });
  tearDown(() => db.close());

  Future<void> pumpTool(WidgetTester tester, String key) async {
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        kitRepositoryProvider.overrideWithValue(repo),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/kits/tool/$key',
      routes: [
        ShellRoute(builder: (_, _, child) => child, routes: kitShellRoutes()),
        GoRoute(
          path: '/settings/ai',
          builder: (_, _) => const Scaffold(body: Text('AI 增强设置页')),
        ),
        ...kitPageRoutes(),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await settle5(tester);
  }

  String lineOf(WidgetTester tester, int i) =>
      tester.widget<Text>(find.byKey(ValueKey('kit-aiapi-line-$i'))).data!;

  String fieldOf(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

  group('1 · 表单与请求', () {
    testWidgets('初始态：跟随第一台已配置端点 · 结果卡给占位口径', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'aiapi');
      expect(fieldOf(tester, 'kit-aiapi-url'), 'https://api.deepseek.com/v1');
      expect(fieldOf(tester, 'kit-aiapi-model'), 'deepseek-flash');
      expect(fieldOf(tester, 'kit-aiapi-prompt'), '请只回复四个字：连接成功');
      expect(find.text('结果将显示在此：模型回复 / 延迟 / token 用量，或精确错误原因（401 Key 无效 / 429 限流 / 404 模型名 / 网络不可达）。'), findsOneWidget);
      expect(find.byKey(const ValueKey('kit-aiapi-line-0')), findsNothing);
      expect(line(tester, 'kit-aiapi-hist-empty'), '尚无验证记录 · 验证成功才会留档');
      await drainLogTimer(tester);
    });

    testWidgets('缺 Key 不发请求 · 缺 Base URL 先归因', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'aiapi');
      await tester.tap(find.byKey(const ValueKey('kit-aiapi-go')));
      await settle5(tester);
      expect(runCalls, 0);
      expect(lineOf(tester, 0), '✖ 请求未通过 · 0 ms');
      expect(lineOf(tester, 1), '✖ 请先填入 API Key（或使用模拟演示查看交互效果）');
      await pollText(tester, '请先填入 API Key');
      await clearToasts(tester);

      await tester.enterText(find.byKey(const ValueKey('kit-aiapi-url')), '');
      await tester.enterText(find.byKey(const ValueKey('kit-aiapi-key')), 'sk-1');
      await tester.tap(find.byKey(const ValueKey('kit-aiapi-go')));
      await settle5(tester);
      expect(runCalls, 0);
      expect(lineOf(tester, 1), '✖ 请填写 Base URL');
      await clearToasts(tester);
      await drainLogTimer(tester);
    });

    testWidgets('填 Key 后实发：参数逐项交通道 · 结果四行实拼', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'aiapi');
      await tester.enterText(find.byKey(const ValueKey('kit-aiapi-key')), 'sk-abc');
      await tester.enterText(find.byKey(const ValueKey('kit-aiapi-prompt')), '只回 OK');
      await tester.tap(find.byKey(const ValueKey('kit-aiapi-go')));
      await settle5(tester);
      expect(runCalls, 1);
      expect(
        (capUrl, capModel, capKey, capPrompt, capProto),
        ('https://api.deepseek.com/v1', 'deepseek-flash', 'sk-abc', '只回 OK', 'openai'),
      );
      expect(lineOf(tester, 0), '✔ 200 OK · 321 ms');
      expect(lineOf(tester, 1), '模型回复：连接成功');
      expect(lineOf(tester, 2), 'usage: 9 + 4 tokens');
      expect(lineOf(tester, 3), contains('验证通过'));
      expect(
        find.text('POST https://api.deepseek.com/v1/chat/completions'),
        findsOneWidget,
      );
      await drainLogTimer(tester);
    });

    testWidgets('保险箱已有 Key 时空输入也放行（交通道取用）', (tester) async {
      await useSurface(tester);
      hasKeyResult = true;
      await pumpTool(tester, 'aiapi');
      await tester.tap(find.byKey(const ValueKey('kit-aiapi-go')));
      await settle5(tester);
      expect(runCalls, 1);
      expect(capKey, '');
      await drainLogTimer(tester);
    });

    testWidgets('失败态给精确归因与细节行', (tester) async {
      await useSurface(tester);
      nextResult = () => const AiVerifyResult(
        ok: false,
        ms: 88,
        error: '✖ Key 无效或未授权（401/403）',
        detail: '{"error":{"code":"invalid_api_key"}}',
      );
      await pumpTool(tester, 'aiapi');
      await tester.enterText(find.byKey(const ValueKey('kit-aiapi-key')), 'sk-bad');
      await tester.tap(find.byKey(const ValueKey('kit-aiapi-go')));
      await settle5(tester);
      expect(lineOf(tester, 0), '✖ 请求未通过 · 88 ms');
      expect(lineOf(tester, 1), '✖ Key 无效或未授权（401/403）');
      expect(lineOf(tester, 2), startsWith('{"error"'));
      expect(lineOf(tester, 3), 'usage: n/a');
      expect(lineOf(tester, 4), '未通过 · 按上方归因排查后再试');
      await drainLogTimer(tester);
    });

    testWidgets('模拟演示零出站 · 显式标注不校验 Key', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'aiapi');
      await tester.tap(find.byKey(const ValueKey('kit-aiapi-mock')));
      await settle5(tester);
      expect(runCalls, 0);
      expect(mockCalls, 1);
      expect(lineOf(tester, 0), '✔ 200 OK（模拟）· 812 ms');
      expect(lineOf(tester, 2), 'usage: 9 + 4 tokens（模拟值）');
      expect(lineOf(tester, 3), '模拟演示 · 不发真实请求 · 不校验 Key');
      await drainLogTimer(tester);
    });

    testWidgets('切服务商带出端点与协议 · 表单落库不含 Key', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'aiapi');
      await tester.tap(find.byKey(const ValueKey('kit-aiapi-provider')));
      await settle5(tester);
      await tester.tap(find.text('Anthropic · claude-3-5-haiku-latest'));
      await settle5(tester);
      expect(fieldOf(tester, 'kit-aiapi-url'), 'https://api.anthropic.com/v1');
      expect(fieldOf(tester, 'kit-aiapi-model'), 'claude-3-5-haiku-latest');
      // chip 的键在内层手势上，选中态要从祖先 KitToolChip 读。
      expect(
        tester
            .widget<KitToolChip>(
              find.ancestor(
                of: find.byKey(const ValueKey('kit-aiapi-proto-anthropic')),
                matching: find.byType(KitToolChip),
              ),
            )
            .on,
        isTrue,
      );

      await tester.enterText(find.byKey(const ValueKey('kit-aiapi-key')), 'sk-x');
      await tester.tap(find.byKey(const ValueKey('kit-aiapi-go')));
      await settle5(tester);
      expect(capProto, 'anthropic');
      expect(find.text('POST https://api.anthropic.com/v1/messages'), findsOneWidget);
      final d = await repo.toolData('aiapi');
      expect(d['aiProv'], 'claude');
      expect(d['aiProto'], 'anthropic');
      expect(d.containsKey('aiKey'), isFalse);
      expect(d.containsKey('aiapi'), isFalse);
      await drainLogTimer(tester);
    });

    testWidgets('协议 chip 可手动改 · 覆盖端点默认', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'aiapi');
      await tester.tap(find.byKey(const ValueKey('kit-aiapi-proto-anthropic')));
      await settle5(tester);
      final d = await repo.toolData('aiapi');
      expect(d['aiProto'], 'anthropic');
      await tester.tap(find.byKey(const ValueKey('kit-aiapi-proto-openai')));
      await settle5(tester);
      expect((await repo.toolData('aiapi'))['aiProto'], 'openai');
      await drainLogTimer(tester);
    });
  });

  group('2 · 记录与跳转', () {
    testWidgets('记录行来自真实留痕 · 清空给条数', (tester) async {
      await useSurface(tester);
      hist = [
        AiCallRecord(ts: DateTime.now().millisecondsSinceEpoch, taskId: 'tool.verify', module: '小工具', name: 'AI 端点验证', status: AiCallStore.statusOk, ms: 300),
        AiCallRecord(ts: DateTime.now().millisecondsSinceEpoch, taskId: 'tool.verify', module: '小工具', name: 'AI 端点验证', status: AiCallStore.statusFail, ms: 12, err: 'unauthorized'),
      ];
      await pumpTool(tester, 'aiapi');
      expect(find.byKey(const ValueKey('kit-aiapi-hist-empty')), findsNothing);
      expect(line(tester, 'kit-aiapi-hist-0'), contains('✔ 300ms'));
      expect(line(tester, 'kit-aiapi-hist-1'), contains('✖ unauthorized'));

      await tester.tap(find.byKey(const ValueKey('kit-aiapi-hist-clear')));
      await settle5(tester);
      await pollText(tester, '验证记录已清空 2 条');
      await clearToasts(tester);
      expect(line(tester, 'kit-aiapi-hist-empty'), '尚无验证记录 · 验证成功才会留档');
      await drainLogTimer(tester);
    });

    testWidgets('前往 AI 增强设置：先落表单再跳设置页', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'aiapi');
      await tester.tap(find.byKey(const ValueKey('kit-aiapi-setting')));
      await settle5(tester);
      expect(find.text('AI 增强设置页'), findsOneWidget);
      await drainLogTimer(tester);
    });
  });
}

/// kitToolNote / 记录行都落在 Text 上，按键直接取文案。
String line(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;
