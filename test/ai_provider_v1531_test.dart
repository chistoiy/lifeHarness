import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifeharness/core/ai/ai_client.dart';
import 'package:lifeharness/core/ai/ai_config.dart';
import 'package:lifeharness/core/ai/ai_prompt_pack.dart';
import 'package:lifeharness/core/ai/ai_providers.dart';
import 'package:lifeharness/core/ai/ai_service.dart';
import 'package:lifeharness/core/ai/ai_vault.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/settings/presentation/ai_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// V1.53.1 · AI 服务商可增删改（预置=种子不是白名单 · Key 按服务商分域）。
/// 纯逻辑组：AiConfigRepository / AiKeyVault / AiService 端点与 Key 归属。
/// 组件组：AI 增强页服务商卡与编辑弹层（MockClient，零真实网络）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AiConfigRepository> repo([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    return AiConfigRepository(await SharedPreferences.getInstance());
  }

  group('AiConfigRepository 服务商列表', () {
    test('无落盘数据＝预置种子 7 条，当前 DeepSeek', () async {
      final cfg = await repo().then((r) => r.load());
      expect(cfg.providers.length, 7);
      expect(cfg.active.id, 'deepseek');
      expect(cfg.baseUrl, 'https://api.deepseek.com/v1');
      expect(cfg.model, 'deepseek-flash');
      expect(cfg.active.builtin, isTrue);
      expect(cfg.providers.firstWhere((p) => p.id == 'ollama').isPlainHttp,
          isTrue,
          reason: '本地 Ollama 端点＝http 明文，UI 需标黄并二次确认');
    });

    test('旧版单值端点迁移：对得上预置归位，对不上合成 custom 并保持当前', () async {
      final hit = await repo({'ai.base_url': 'https://api.moonshot.cn/v1/'})
          .then((r) => r.load());
      expect(hit.active.id, 'kimi');

      final relay = await repo({
        'ai.base_url': 'https://relay.example.com/v1/api',
        'ai.model': 'deepseek-chat',
        'ai.protocol': 'openai',
      }).then((r) => r.load());
      expect(relay.active.id, kAiCustomProviderId);
      expect(relay.baseUrl, 'https://relay.example.com/v1/api');
      expect(relay.model, 'deepseek-chat');
      // 迁移不丢旧端点：预置仍在列表里，可随时切回。
      expect(relay.providers.any((p) => p.id == 'deepseek'), isTrue);
    });

    test('增/改/切/删：当前端点拒删，其余删除即刻落盘', () async {
      final r = await repo();
      await r.saveProvider(const AiProvider(
          id: 'relay',
          name: '公司中转站',
          baseUrl: 'https://relay.example.com/v1/api',
          model: 'deepseek-chat'));
      final afterAdd = r.load();
      expect(afterAdd.providers.length, 8);
      expect(afterAdd.providers.any((p) => p.id == 'relay'), isTrue);

      await r.saveProvider(const AiProvider(
              id: 'relay',
              name: '公司中转站',
              baseUrl: 'https://relay2.example.com/v1',
              model: 'deepseek-chat')
          .copyWith(name: '公司中转站（改名）'));
      expect(r.load().providers.firstWhere((p) => p.id == 'relay').name,
          '公司中转站（改名）');

      expect(await r.useProvider('relay'), isTrue);
      expect(await r.useProvider('not-exist'), isFalse);
      expect(r.load().active.id, 'relay');
      expect(await r.deleteProvider('relay'), isFalse, reason: '当前端点不可删');
      expect(await r.deleteProvider('deepseek'), isTrue);
      expect(await r.deleteProvider('deepseek'), isFalse, reason: '已不存在');
      expect(r.load().providers.any((p) => p.id == 'deepseek'), isFalse);
      // 整表落盘（不再写旧的单值键）。
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), contains('ai.providers'));
      expect(prefs.getString('ai.base_url'), isNull);
    });

    test('脏 providers JSON 回落种子：不炸 load', () async {
      final cfg = await repo({'ai.providers': '{不是数组}'})
          .then((r) => r.load());
      expect(cfg.providers.length, 7);
    });
  });

  group('AiKeyVault 按服务商分域', () {
    test('自己的槽位优先，未填回落旧全局 Key', () async {
      final v = AiKeyVault.inMemory(apiKey: 'sk-legacy');
      expect(await v.read('deepseek'), 'sk-legacy');
      expect(await v.hasOwnKey('deepseek'), isFalse);

      expect(await v.write('sk-ds', providerId: 'deepseek'), isTrue);
      expect(await v.read('deepseek'), 'sk-ds');
      expect(await v.readOwn('deepseek'), 'sk-ds');
      expect(await v.hasOwnKey('deepseek'), isTrue);
      expect(await v.read('ollama'), 'sk-legacy', reason: '其他端点仍用旧全局 Key');

      await v.clear(providerId: 'deepseek');
      expect(await v.readOwn('deepseek'), isNull);
      expect(await v.read('deepseek'), 'sk-legacy');
    });
  });

  group('AiService 端点与 Key 归属', () {
    final pack = AiPromptPack.decode(
        File('assets/ai_prompts/prompts.json').readAsStringSync());

    http.Response quadrantOk() => http.Response.bytes(
        utf8.encode(jsonEncode({
          'choices': [
            {
              'message': {'content': '{"quadrant":1,"reason":"今晚截止"}'}
            }
          ],
          'usage': {'prompt_tokens': 1, 'completion_tokens': 1}
        }),
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'});

    const master = <String, Object>{
      'ai.master': true,
      'ai.caps': '{"todo.quadrant":true}',
    };

    test('切到局域网 Ollama 后：请求地址与该条可用 Key 同源（未填回落旧全局）',
        () async {
      SharedPreferences.setMockInitialValues({});
      final r = AiConfigRepository(await SharedPreferences.getInstance());
      await r.saveProvider(const AiProvider(
          id: 'lan',
          name: '家里 Ollama',
          baseUrl: 'http://192.168.31.20:11434/v1',
          model: 'qwen2.5:7b'));
      await r.useProvider('lan');
      final providersJson = jsonEncode(
          r.load().providers.map((e) => e.toJson()).toList());

      String? auth;
      String? url;
      SharedPreferences.setMockInitialValues({
        ...master,
        'ai.providers': providersJson,
        'ai.activeProvider': 'lan',
      });
      final vault = AiKeyVault.inMemory(apiKey: 'sk-legacy');
      final s = AiService(
        configRepo: AiConfigRepository(await SharedPreferences.getInstance()),
        keyVault: vault,
        client: AiClient(client: MockClient((req) async {
          auth = req.headers['Authorization'];
          url = req.url.toString();
          return quadrantOk();
        })),
        pack: pack,
      );
      await s.request('todo.quadrant', {'title': '今晚交周报'});
      expect(url, 'http://192.168.31.20:11434/v1/chat/completions');
      expect(auth, 'Bearer sk-legacy', reason: '该端点没自己的 Key：沿用旧全局 Key');

      await vault.write('sk-lan', providerId: 'lan');
      await s.request('todo.quadrant', {'title': '今晚交周报'});
      expect(auth, 'Bearer sk-lan', reason: '配了独立 Key 即以它为准');
    });

    test('当前端点没有 Key（其他端点有）→ gate 拒绝且零请求', () async {
      var sent = 0;
      final vault = AiKeyVault.inMemory();
      await vault.write('sk-ds', providerId: 'deepseek');
      SharedPreferences.setMockInitialValues(master);
      final prefs = await SharedPreferences.getInstance();
      final repo = AiConfigRepository(prefs);
      await repo.useProvider('anthropic');
      final s = AiService(
        configRepo: repo,
        keyVault: vault,
        client: AiClient(client: MockClient((_) async {
          sent++;
          return quadrantOk();
        })),
        pack: pack,
      );
      expect(await s.gate('todo.quadrant'), contains('Anthropic claude'));
      await expectLater(s.request('todo.quadrant', {'title': 't'}),
          throwsA(isA<AiDenied>()));
      expect(sent, 0);
      // 切回有 Key 的端点即可用。
      await repo.useProvider('deepseek');
      expect(await s.gate('todo.quadrant'), isNull);
    });
  });

  // ——— 组件层：AI 增强页服务商卡 ———
  final pack = AiPromptPack.decode(
      File('assets/ai_prompts/prompts.json').readAsStringSync());
  late SharedPreferences prefs;
  late AiKeyVault vault;
  late ProviderContainer container;

  Future<void> pumpPage(WidgetTester tester,
      {Map<String, Object> initialPrefs = const {},
      Future<http.Response> Function(http.Request)? handler}) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    prefs = await SharedPreferences.getInstance();
    vault = AiKeyVault.inMemory();
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      aiPromptPackProvider.overrideWithValue(pack),
      aiKeyVaultProvider.overrideWithValue(vault),
      aiClientProvider.overrideWithValue(
          AiClient(client: handler == null ? MockClient((_) async => http.Response('{}', 500)) : MockClient(handler))),
    ]);
    final router = GoRouter(initialLocation: '/settings/ai', routes: [
      GoRoute(
          path: '/',
          builder: (_, _) => const SizedBox.shrink(),
          routes: [
            GoRoute(
                path: 'settings/ai',
                builder: (_, _) => const AiSettingsPage()),
          ]),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router)));
    await settle5(tester);
  }

  List<dynamic> storedProviders() =>
      jsonDecode(prefs.getString('ai.providers') ?? '[]') as List<dynamic>;

  /// 打开「选择服务商」半屏（V1.62：页面上只留当前一行，整份清单住在选单里）。
  Future<void> openPicker(WidgetTester tester) async {
    final f = find.byKey(const ValueKey('ai-cur-endpoint'));
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-prov-row-deepseek')), findsOneWidget,
        reason: '选单没开成：多半是提示条盖住了当前行');
  }

  Future<void> openForm(WidgetTester tester, String addKey) async {
    // 行内按钮（编辑/删）在选单里：目标不在页面上时先开选单，用例其余步骤照旧。
    if (find.byKey(ValueKey(addKey)).evaluate().isEmpty) await openPicker(tester);
    await tester.ensureVisible(find.byKey(ValueKey(addKey)));
    await tester.tap(find.byKey(ValueKey(addKey)));
    await tester.pumpAndSettle();
  }

  /// 服务商表单比视口长：tap/enterText 前必须滚进视口（既定坑）。
  Future<void> tapKey(WidgetTester tester, String k) async {
    final f = find.byKey(ValueKey(k));
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> typeKey(WidgetTester tester, String k, String v) async {
    final f = find.byKey(ValueKey(k));
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.enterText(f, v);
    await tester.pumpAndSettle();
  }

  testWidgets('服务商收成一行：页面不铺开，选单里才是 7 行清单',
      (tester) async {
    await useSurface(tester, const Size(560, 2000));
    await pumpPage(tester);
    // 页面上只有当前那一行（V1.62 产品令：不要全列表展示）。
    expect(find.byKey(const ValueKey('ai-cur-endpoint')), findsOneWidget);
    expect(find.text('DeepSeek · OpenAI 兼容'), findsOneWidget);
    expect(find.textContaining('Key '), findsWidgets,
        reason: '当前行带 Key 状态读数');
    expect(find.byKey(const ValueKey('ai-prov-row-deepseek')), findsNothing,
        reason: '清单不在页面上铺开');
    expect(find.text('Key 配置'), findsNothing, reason: '重复的 Key 配置卡已摘');
    expect(find.byKey(const ValueKey('ai-key-field')), findsNothing);
    // 验证状态与重新验证钮留在服务商卡里（API 验证入口不许丢）。
    expect(find.text('验证状态'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-verify-btn')), findsOneWidget);

    await openPicker(tester);
    expect(find.byKey(const ValueKey('ai-prov-row-deepseek')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-prov-row-ollama')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-prov-cur-deepseek')), findsOneWidget);
    expect(find.text('预置'), findsNWidgets(7));
    expect(
        find.byKey(const ValueKey('ai-prov-meta-ollama')),
        findsWidgets,
        reason: 'ollama 行有模型·协议·Key 状态文案');
    expect(find.byKey(const ValueKey('ai-prov-http-ollama')), findsOneWidget);
    // 当前端点不给删（其他行给）。
    expect(find.byKey(const ValueKey('ai-prov-del-deepseek')), findsNothing);
    expect(find.byKey(const ValueKey('ai-prov-del-glm')), findsOneWidget);
  });

  testWidgets('添加服务商：缺项行内报错拒存 · 补齐后落盘并自动选用',
      (tester) async {
    await useSurface(tester, const Size(560, 2000));
    await pumpPage(tester);
    await openForm(tester, 'ai-prov-add');
    expect(find.byKey(const ValueKey('ai-prov-form-title')), findsOneWidget);

    // 空名称 → 行内提示（模态弹层里页面 SnackBar 被遮罩挡住，故走行内红字）。
    await tapKey(tester, 'ai-prov-save');
    expect(find.byKey(const ValueKey('ai-prov-form-err')), findsOneWidget);
    expect(storedProviders(), isEmpty);

    await typeKey(tester, 'ai-prov-f-name', '公司中转站');
    await typeKey(tester, 'ai-prov-f-url', 'relay.example.com/v1/api');
    await tapKey(tester, 'ai-prov-save');
    expect(find.textContaining('http:// 或 https://'), findsOneWidget);

    await typeKey(tester, 'ai-prov-f-url', 'https://relay.example.com/v1/api');
    await tapKey(tester, 'ai-prov-save');
    expect(find.text('请填写模型名'), findsOneWidget);

    await typeKey(tester, 'ai-prov-f-model', 'deepseek-chat');
    await typeKey(tester, 'ai-prov-f-key', 'sk-relay');
    await tapKey(tester, 'ai-prov-save');
    expect(await pollText(tester, '已保存 · 端点即刻生效（业务模块无需任何改动）'), isTrue);
    await clearToasts(tester);

    final stored = storedProviders();
    expect(stored.length, 8);
    final relay = stored.firstWhere((e) => (e as Map)['name'] == '公司中转站') as Map;
    expect(relay['baseUrl'], 'https://relay.example.com/v1/api');
    expect(prefs.getString('ai.activeProvider'), relay['id'],
        reason: '新增即选用（原型 aiProvUse 同口径）');
    expect(await vault.readOwn('${relay['id']}'), 'sk-relay');
    expect(find.text('公司中转站 · OpenAI 兼容'), findsOneWidget,
        reason: '新增即选用，服务商卡那一行当场换人');
  });

  testWidgets('http 明文端点：未确认拒存，确认后落盘且行上标黄',
      (tester) async {
    await useSurface(tester, const Size(560, 2000));
    await pumpPage(tester);
    await openForm(tester, 'ai-prov-add');
    await typeKey(tester, 'ai-prov-f-name', '家里 Ollama');
    await typeKey(tester, 'ai-prov-f-url', 'http://192.168.31.9:11434/v1');
    await typeKey(tester, 'ai-prov-f-model', 'qwen2.5:7b');
    expect(find.byKey(const ValueKey('ai-prov-http-row')), findsOneWidget);

    await tapKey(tester, 'ai-prov-save');
    expect(find.textContaining('http 明文端点需先确认'), findsOneWidget);
    expect(storedProviders(), isEmpty);

    await tapKey(tester, 'ai-prov-http-ok');
    await tapKey(tester, 'ai-prov-save');
    await clearToasts(tester);
    expect(storedProviders().length, 8);
    final id = (storedProviders().last as Map)['id'];
    await openPicker(tester);
    expect(find.byKey(ValueKey('ai-prov-http-$id')), findsOneWidget,
        reason: '选单里必须一次看全所有行（含新加的那家）');
  });

  testWidgets('编辑预置条目：改地址与协议即刻生效（业务模块零改动）',
      (tester) async {
    await useSurface(tester, const Size(560, 2000));
    await pumpPage(tester);
    await openForm(tester, 'ai-prov-edit-glm');
    expect(find.text('编辑服务商 · 智谱 GLM'), findsOneWidget);
    await typeKey(tester, 'ai-prov-f-url', 'https://open.bigmodel.cn/api/paas/v4/');
    await typeKey(tester, 'ai-prov-f-model', 'glm-4.5-air');
    await tapKey(tester, 'ai-prov-proto-anthropic');
    await tapKey(tester, 'ai-prov-save');
    await clearToasts(tester);
    final glm = storedProviders()
        .firstWhere((e) => (e as Map)['id'] == 'glm') as Map;
    expect(glm['baseUrl'], 'https://open.bigmodel.cn/api/paas/v4',
        reason: '末尾斜杠归一化');
    expect(glm['model'], 'glm-4.5-air');
    expect(glm['protocol'], 'anthropic');
    expect(container.read(aiConfigProvider).providers
        .firstWhere((p) => p.id == 'glm')
        .isAnthropic, isTrue);
    await openPicker(tester);
    expect(find.textContaining('glm-4.5-air · Anthropic Messages'),
        findsOneWidget);
  });

  testWidgets('删除非当前服务商：两段式确认 · Key 连带清除', (tester) async {
    await useSurface(tester, const Size(560, 2000));
    await pumpPage(tester);
    // 先给 kimi 存一把独立 Key（编辑弹层）。
    await openForm(tester, 'ai-prov-edit-kimi');
    await typeKey(tester, 'ai-prov-f-key', 'sk-kimi');
    await tapKey(tester, 'ai-prov-save');
    await clearToasts(tester);
    expect(await vault.readOwn('kimi'), 'sk-kimi');

    await openPicker(tester);
    await tapKey(tester, 'ai-prov-del-kimi');
    expect(find.byKey(const ValueKey('ai-prov-del-confirm')), findsOneWidget,
        reason: '破坏性操作两段式');
    await tapKey(tester, 'ai-prov-del-confirm');
    expect(storedProviders().any((e) => (e as Map)['id'] == 'kimi'), isFalse);
    expect(await vault.readOwn('kimi'), isNull);
    // 删除会先收起选单（两段式确认在页面层）：重新开选单才谈「行不再出现」。
    await openPicker(tester);
    expect(find.byKey(const ValueKey('ai-prov-row-kimi')), findsNothing);
    await clearToasts(tester);
  });

  testWidgets('表单里 Key 默认掩码 · 眼睛切明文 · 编辑时掩码预填', (tester) async {
    await useSurface(tester, const Size(560, 2000));
    await pumpPage(tester);
    await openForm(tester, 'ai-prov-edit-openai');
    var field = tester.widget<TextField>(find.byKey(const ValueKey('ai-prov-f-key')));
    expect(field.obscureText, isTrue);
    expect(find.text('该服务商还没有 Key · 填入后即刻存入系统加密区'), findsOneWidget);

    await typeKey(tester, 'ai-prov-f-key', 'sk-openai-abcdef');
    await tapKey(tester, 'ai-prov-save');
    await clearToasts(tester);

    await openForm(tester, 'ai-prov-edit-openai');
    await settle5(tester);
    field = tester.widget<TextField>(find.byKey(const ValueKey('ai-prov-f-key')));
    expect(field.obscureText, isTrue, reason: '已存 Key 仍以掩码回填');
    expect(field.controller!.text, 'sk-openai-abcdef');
    expect(find.textContaining('已存 Key（末 4 位 cdef）'), findsOneWidget);
    await tapKey(tester, 'ai-prov-f-eye');
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('ai-prov-f-key')))
            .obscureText,
        isFalse);
  });
}
