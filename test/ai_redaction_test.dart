import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifeharness/core/ai/ai_client.dart';
import 'package:lifeharness/core/ai/ai_config.dart';
import 'package:lifeharness/core/ai/ai_prompt_pack.dart';
import 'package:lifeharness/core/ai/ai_redaction.dart';
import 'package:lifeharness/core/ai/ai_service.dart';
import 'package:lifeharness/core/ai/ai_vault.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// C01 第 0 批守护：发送前脱敏 + 审阅/实际请求同源（全程零真实网络）。
AiPromptPack packFromAssets() =>
    AiPromptPack.decode(File('assets/ai_prompts/prompts.json').readAsStringSync());

http.Response textOk() => http.Response.bytes(
      utf8.encode(jsonEncode({
        'choices': [
          {
            'message': {'content': '今天和张三的交流让我重新想了想节奏，先把重要不紧急的事排进日程。'}
          }
        ],
        'usage': {'prompt_tokens': 1, 'completion_tokens': 1}
      })),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  group('C01 发送前脱敏', () {
    test('身份与凭据类串一律打码', () {
      final out = redactForSend('联系 13800138000 或 a.b+tag@qq.com，'
          '证件 110101199003072316，sk-abcdefghijklmnopqrst，'
          'Bearer eyJhbGciOiJIUzI1NiJ9，token: abcdef123456');
      expect(out, isNot(contains('13800138000')));
      expect(out, isNot(contains('a.b+tag@qq.com')));
      expect(out, isNot(contains('110101199003072316')));
      expect(out, isNot(contains('sk-abcdefghijklmnopqrst')));
      expect(out, isNot(contains('Bearer eyJhbGciOiJIUzI1NiJ9')));
      expect(out, isNot(contains('token: abcdef123456')));
      expect(out, contains('[手机号]'));
      expect(out, contains('[邮箱]'));
      expect(out, contains('[证件号]'));
      expect(out, contains('[密钥]'));
      expect(out, contains('[已隐藏]'));
    });

    test('业务字段零误伤：金额/日期/书名/标签/商户名原样', () {
      const src = '支出 128.50 元 · 2026-11-06 · 《资治通鉴》 · '
          '标签 工作/阅读 · 商户 楼下咖啡馆 · 订单 20261106000123';
      expect(redactForSend(src), src);
    });

    test('幂等：二次脱敏不再吃掉相邻文本', () {
      const src = '手机 13800138000，邮箱 a@b.com，结束';
      final once = redactForSend(src);
      expect(redactForSend(once), once);
      expect(once, contains('结束'));
    });
  });

  group('C01 审阅与请求同源', () {
    test('审阅所见＝实际发出，且敏感串不出现在请求体里', () async {
      SharedPreferences.setMockInitialValues({
        'ai.master': true,
        'ai.caps': '{"journal.reflect":true}',
      });
      final prefs = await SharedPreferences.getInstance();
      late http.Request captured;
      final svc = AiService(
        configRepo: AiConfigRepository(prefs),
        keyVault: AiKeyVault.inMemory(apiKey: 'k'),
        client: AiClient(client: MockClient((req) async {
          captured = req;
          return textOk();
        })),
        pack: packFromAssets(),
      );
      final vars = {
        'content': '今天和张三 13800138000 聊了，回信发 zs@example.com'
      };
      final (reviewSys, reviewUsr) =
          svc.renderForReview('journal.reflect', vars);
      await svc.request('journal.reflect', vars);

      final msgs = (jsonDecode(captured.body) as Map)['messages'] as List;
      expect((msgs[0] as Map)['content'], reviewSys,
          reason: '审阅的 system 必须是实际发出的 system');
      expect((msgs[1] as Map)['content'], reviewUsr,
          reason: '审阅的 user 必须是实际发出的 user');
      expect(reviewUsr, isNot(contains('13800138000')));
      expect(reviewUsr, isNot(contains('zs@example.com')));
      expect(reviewUsr, contains('今天和张三'));
    });
  });
}
