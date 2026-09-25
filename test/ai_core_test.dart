import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifeharness/core/ai/ai_client.dart';
import 'package:lifeharness/core/ai/ai_config.dart';
import 'package:lifeharness/core/ai/ai_prompt_pack.dart';
import 'package:lifeharness/core/ai/ai_service.dart';
import 'package:lifeharness/core/ai/ai_validate.dart';
import 'package:lifeharness/core/ai/ai_vault.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AI 核心层单测（纯逻辑 + MockClient，全程零真实网络）。
/// 提示词资产直读仓库文件：与打包进 APK 的是同一份事实源。

AiPromptPack packFromAssets() =>
    AiPromptPack.decode(File('assets/ai_prompts/prompts.json').readAsStringSync());

/// UTF-8 安全的响应构造（http.Response(String) 走 Latin1，含中文体会抛）。
http.Response jresp(Object body, [int status = 200]) => http.Response.bytes(
      utf8.encode(body is String ? body : jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  final pack = packFromAssets();

  group('提示词包', () {
    test('资产可解析：11 个能力点、DeepSeek 默认端点', () {
      expect(pack.version, 1);
      expect(pack.defaultBaseUrl, 'https://api.deepseek.com/v1');
      expect(pack.defaultModel, 'deepseek-flash');
      expect(pack.tasks.length, 11);
      for (final t in pack.tasks) {
        expect(t.system.trim(), isNotEmpty, reason: '${t.id} system');
        expect(t.user.trim(), isNotEmpty, reason: '${t.id} user');
        for (final p in t.placeholders) {
          expect(t.user.contains('{{$p}}'), isTrue,
              reason: '${t.id} user 模板缺占位符 $p');
        }
      }
    });

    test('renderTemplate 填充占位符；未知占位符原样保留', () {
      expect(renderTemplate('你好 {{name}}', {'name': '世界'}), '你好 世界');
      expect(renderTemplate('{{a}}-{{b}}', {'a': '1'}), '1-{{b}}');
    });

    test('templatePlaceholders 提取变量名', () {
      expect(templatePlaceholders('{{x}}和{{y}}{{x}}'), containsAll(['x', 'y']));
    });
  });

  group('输出解析与校验', () {
    test('decodeJsonObject 容忍代码围栏与前后杂语', () {
      expect(decodeJsonObject('```json\n{"a":1}\n```'), {'a': 1});
      expect(decodeJsonObject('结果如下：{"a":{"b":2}} 完毕'), {
        'a': {'b': 2}
      });
      expect(() => decodeJsonObject('没有 JSON'), throwsFormatException);
    });

    test('cleanTextResult 去围栏与包裹引号', () {
      expect(cleanTextResult('```\n正文\n```'), '正文');
      expect(cleanTextResult('"带引号的回复"'), '带引号的回复');
    });

    test('validateAiOutput 按能力点结构校验', () {
      expect(
          validateAiOutput('todo.quadrant', AiExpect.json,
              '{"quadrant":1,"reason":"截止今晚"}', const {}),
          isNull);
      expect(
          validateAiOutput('todo.quadrant', AiExpect.json,
              '{"quadrant":9,"reason":"x"}', const {}),
          contains('quadrant'));
      expect(
          validateAiOutput('inbox.triage', AiExpect.json,
              '{"target":"chat","reason":"x"}', const {}),
          contains('target'));
      expect(
          validateAiOutput('ledger.categorize', AiExpect.json,
              '{"items":[{"name":"A","category":"餐饮"}]}', {
            'items': 'A',
            'cats': '餐饮, 其他'
          }),
          isNull);
      expect(
          validateAiOutput('ledger.categorize', AiExpect.json,
              '{"items":[{"name":"A","category":"未知类"}]}', {
            'items': 'A',
            'cats': '餐饮, 其他'
          }),
          contains('越界'));
      expect(
          validateAiOutput('tool.verify', AiExpect.text, '连接成功', const {}),
          isNull);
    });
  });

  group('AiConfigRepository', () {
    test('默认=总开关关 + DeepSeek 端点；能力授权默认无', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = AiConfigRepository(await SharedPreferences.getInstance());
      final cfg = repo.load();
      expect(cfg.master, isFalse);
      expect(cfg.baseUrl, 'https://api.deepseek.com/v1');
      expect(cfg.model, 'deepseek-flash');
      expect(cfg.capEnabled('todo.quadrant'), isFalse);
      expect(cfg.readyForRequest, isTrue);
    });

    test('开关/授权/覆盖提示词/验证结果 全链路读写', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = AiConfigRepository(prefs);
      await repo.setMaster(true);
      await repo.setCap('todo.quadrant', true);
      await repo.setPromptOverride('todo.quadrant', '新 system', null);
      await repo.setVerifyResult(ok: true, at: 123, latencyMs: 800);
      final cfg = repo.load();
      expect(cfg.capEnabled('todo.quadrant'), isTrue);
      expect(cfg.caps['todo.quadrant'], isTrue);
      expect(cfg.promptOverrides['todo.quadrant'], {'system': '新 system'});
      expect(cfg.verifyOk, isTrue);
      expect(cfg.verifyLatencyMs, 800);
      await repo.clearPromptOverride('todo.quadrant');
      expect(repo.load().promptOverrides.containsKey('todo.quadrant'), isFalse);
    });

    test('损坏 JSON 容忍：不炸 load，按缺省处理', () async {
      SharedPreferences.setMockInitialValues(
          {'ai.caps': 'not-json', 'ai.prompt.todo.quadrant': '{broken'});
      final repo = AiConfigRepository(await SharedPreferences.getInstance());
      expect(repo.load().caps, isEmpty);
      expect(repo.load().promptOverrides, isEmpty);
    });
  });

  group('AiClient 错误归因', () {
    AiClient clientWith(Future<http.Response> Function(http.Request) h) =>
        AiClient(client: MockClient(h));

    test('200 正常回复：内容/延迟/token', () async {
      final c = clientWith((req) async {
        expect(req.headers['Authorization'], 'Bearer sk-test');
        final body = jsonDecode(req.body) as Map;
        expect(body['model'], 'deepseek-flash');
        return jresp({
          'choices': [
            {
              'message': {'content': '连接成功'}
            }
          ],
          'usage': {'prompt_tokens': 9, 'completion_tokens': 4}
        });
      });
      final r = await c.chat(
          baseUrl: 'https://api.deepseek.com/v1',
          model: 'deepseek-flash',
          apiKey: 'sk-test',
          messages: const [
            {'role': 'user', 'content': 'hi'}
          ]);
      expect(r.content, '连接成功');
      expect(r.promptTokens, 9);
      expect(r.completionTokens, 4);
      c.close();
    });

    test('401/404/429/500 归因到 kind 与用户文案', () async {
      for (final (status, kind) in [
        (401, AiFailKind.unauthorized),
        (404, AiFailKind.notFound),
        (429, AiFailKind.rateLimited),
        (500, AiFailKind.server),
      ]) {
        final c = clientWith((_) async => http.Response('{"error":"x"}', status));
        var threw = false;
        try {
          await c.chat(
              baseUrl: 'https://api.deepseek.com/v1',
              model: 'm',
              apiKey: 'k',
              messages: const []);
        } on AiException catch (e) {
          threw = true;
          expect(e.kind, kind, reason: 'HTTP $status');
          expect(e.userMessage, isNotEmpty);
        }
        expect(threw, isTrue, reason: 'HTTP $status 应抛 AiException');
        c.close();
      }
    });

    test('缺 baseUrl/缺 Key 直接拒绝；200 空回复归因 badResponse', () async {
      final c = clientWith((_) async => http.Response('{"choices":[]}', 200));
      await expectLater(
          c.chat(baseUrl: '', model: 'm', apiKey: 'k', messages: const []),
          throwsA(predicate((e) =>
              e is AiException && e.kind == AiFailKind.noBaseUrl)));
      await expectLater(
          c.chat(baseUrl: 'https://x', model: 'm', apiKey: ' ', messages: const []),
          throwsA(predicate((e) =>
              e is AiException && e.kind == AiFailKind.noKey)));
      await expectLater(
          c.chat(
              baseUrl: 'https://x',
              model: 'm',
              apiKey: 'k',
              messages: const []),
          throwsA(predicate((e) =>
              e is AiException && e.kind == AiFailKind.badResponse)));
      c.close();
    });

    test('超时归因 timeout', () async {
      final c = clientWith((_) async {
        await Future.delayed(const Duration(milliseconds: 60));
        return http.Response('{}', 200);
      });
      await expectLater(
          c.chat(
              baseUrl: 'https://x',
              model: 'm',
              apiKey: 'k',
              messages: const [],
              timeout: const Duration(milliseconds: 10)),
          throwsA(predicate((e) =>
              e is AiException && e.kind == AiFailKind.timeout)));
      c.close();
    });
  });

  group('AiService 门控与调用', () {
    Future<AiService> svc({
      Map<String, Object> prefsValues = const {},
      String? apiKey,
      required Future<http.Response> Function(http.Request) handler,
    }) async {
      SharedPreferences.setMockInitialValues(prefsValues);
      return AiService(
        configRepo: AiConfigRepository(await SharedPreferences.getInstance()),
        keyVault: AiKeyVault.inMemory(apiKey: apiKey),
        client: AiClient(client: MockClient(handler)),
        pack: pack,
      );
    }

    const okPrefs = <String, Object>{
      'ai.master': true,
      'ai.caps': '{"todo.quadrant":true}',
    };
    http.Response quadrantOk() => jresp({
          'choices': [
            {
              'message': {'content': '{"quadrant":1,"reason":"今晚截止"}'}
            }
          ],
          'usage': {'prompt_tokens': 1, 'completion_tokens': 1}
        });

    test('总开关关 → AiDenied 且零请求', () async {
      var sent = 0;
      final s = await svc(
          apiKey: 'k',
          handler: (_) {
            sent++;
            return Future.value(quadrantOk());
          });
      await expectLater(
          s.request('todo.quadrant', {'title': 'x'}), throwsA(isA<AiDenied>()));
      expect(sent, 0);
    });

    test('能力未授权 → AiDenied 且零请求', () async {
      var sent = 0;
      final s = await svc(
          prefsValues: const {'ai.master': true},
          apiKey: 'k',
          handler: (_) {
            sent++;
            return Future.value(quadrantOk());
          });
      await expectLater(
          s.request('todo.quadrant', {'title': 'x'}), throwsA(isA<AiDenied>()));
      expect(sent, 0);
    });

    test('无 Key → AiDenied 且零请求', () async {
      var sent = 0;
      final s = await svc(
          prefsValues: okPrefs,
          handler: (_) {
            sent++;
            return Future.value(quadrantOk());
          });
      await expectLater(
          s.request('todo.quadrant', {'title': 'x'}), throwsA(isA<AiDenied>()));
      expect(sent, 0);
    });

    test('三重门控通过 → 渲染模板实发并按结构校验返回', () async {
      late http.Request captured;
      final s = await svc(
          prefsValues: okPrefs,
          apiKey: 'sk-x',
          handler: (req) {
            captured = req;
            return Future.value(quadrantOk());
          });
      final r = await s.request('todo.quadrant', {'title': '今晚交周报'});
      expect(r.requireJson()['quadrant'], 1);
      expect(r.requireText(), isEmpty);
      final body = jsonDecode(captured.body) as Map;
      final msgs = body['messages'] as List;
      expect(msgs.length, 2);
      expect((msgs[1] as Map)['content'], contains('今晚交周报'));
    });

    test('用户覆盖提示词生效（不改代码改请求内容）', () async {
      late http.Request captured;
      SharedPreferences.setMockInitialValues({
        ...okPrefs,
        'ai.prompt.todo.quadrant': jsonEncode(
            {'user': '判断：{{title}}→只回数字象限，输出 {"quadrant":n,"reason":"r"}'}),
      });
      final prefs = await SharedPreferences.getInstance();
      final s = AiService(
        configRepo: AiConfigRepository(prefs),
        keyVault: AiKeyVault.inMemory(apiKey: 'k'),
        client: AiClient(client: MockClient((req) async {
          captured = req;
          return quadrantOk();
        })),
        pack: pack,
      );
      await s.request('todo.quadrant', {'title': '救火'});
      final msgs = (jsonDecode(captured.body) as Map)['messages'] as List;
      expect((msgs[1] as Map)['content'], contains('判断：救火'));
    });

    test('输出不守约定 → AiBadOutput（校验与 CLI 同口径）', () async {
      final s = await svc(
          prefsValues: okPrefs,
          apiKey: 'k',
          handler: (_) async => jresp({
                'choices': [
                  {
                    'message': {'content': '我觉得很重要，算第一象限吧！'}
                  }
                ]
              }));
      await expectLater(s.request('todo.quadrant', {'title': 'x'}),
          throwsA(isA<AiBadOutput>()));
    });

    test('renderForReview 返回审阅用完整 system/user', () async {
      final s = await svc(
          prefsValues: okPrefs,
          apiKey: 'k',
          handler: (_) async => http.Response('{}', 200));
      final (sys, user) = s.renderForReview('todo.quadrant', {'title': '买药'});
      expect(sys, contains('分类器'));
      expect(user, contains('买药'));
    });
  });
}
