import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/core/ai/ai_verify_channel.dart';
import 'package:lifeharness/features/kits/domain/kit_aiapi.dart';

/// V1.47 批3e · AI API 验证域层 + core 通道的纯函数面。
/// 真实请求不在这里跑（屏侧用例走注入缝），只钉「该发什么 / 结果怎么读 / 落库存什么」。
void main() {
  group('1 · 表单与请求口径', () {
    test('缺 Base URL 与缺 Key 各有文案', () {
      expect(kitAiapiCheck(baseUrl: '  ', hasKey: true), '请填写 Base URL');
      expect(
        kitAiapiCheck(baseUrl: 'https://a/v1', hasKey: false),
        '请先填入 API Key（或使用模拟演示查看交互效果）',
      );
      expect(kitAiapiCheck(baseUrl: 'https://a/v1', hasKey: true), null);
    });

    test('按协议拼实际请求路径（尾斜杠先摘）', () {
      expect(
        aiVerifyEndpointUrl(baseUrl: 'https://a/v1///', protocol: 'openai'),
        'https://a/v1/chat/completions',
      );
      expect(
        aiVerifyEndpointUrl(baseUrl: 'https://a/v1', protocol: kKitAiapiProtoAnthropic),
        'https://a/v1/messages',
      );
      expect(aiVerifyEndpointUrl(baseUrl: ' ', protocol: 'openai'), '');
    });

    test('进行中的说明行含协议与模型名', () {
      expect(
        kitAiapiRequestLine(url: 'https://a/v1/chat/completions', protocol: 'openai', model: 'deepseek-flash'),
        'POST https://a/v1/chat/completions · OpenAI 兼容 · model=deepseek-flash …',
      );
      expect(
        kitAiapiRequestLine(url: 'u', protocol: kKitAiapiProtoAnthropic, model: ' '),
        'POST u · Anthropic Messages API（协议适配） · model=default …',
      );
    });
  });

  group('2 · 结果口径', () {
    test('三态首行', () {
      expect(kitAiapiHead(ok: true, ms: 321), '✔ 200 OK · 321 ms');
      expect(kitAiapiHead(ok: false, ms: 88, status: '401'), '✖ HTTP 401 · 88 ms');
      expect(kitAiapiHead(ok: false, ms: 88), '✖ 请求未通过 · 88 ms');
      expect(kitAiapiHead(ok: true, ms: 812, mock: true), '✔ 200 OK（模拟）· 812 ms');
    });

    test('token 用量：缺数据给 n/a，模拟标注模拟值', () {
      expect(kitAiapiUsage(inTok: 9, outTok: 4, ok: true), 'usage: 9 + 4 tokens');
      expect(kitAiapiUsage(inTok: 0, outTok: 0, ok: true), 'usage: n/a');
      expect(kitAiapiUsage(inTok: 5, outTok: 6, ok: false), 'usage: n/a');
      expect(
        kitAiapiUsage(inTok: 9, outTok: 4, ok: true, mock: true),
        'usage: 9 + 4 tokens（模拟值）',
      );
    });

    test('结论行三档 · 模拟绝不写成「验证通过」', () {
      expect(kitAiapiVerdict(ok: true, mock: true), '模拟演示 · 不发真实请求 · 不校验 Key');
      expect(kitAiapiVerdict(ok: true, mock: false), contains('验证通过'));
      expect(kitAiapiVerdict(ok: false, mock: false), '未通过 · 按上方归因排查后再试');
    });

    test('结果行序：首行→归因→细节→回复→用量→结论', () {
      final lines = kitAiapiResultLines(
        head: '✖ HTTP 404',
        reply: '',
        usage: 'usage: n/a',
        verdict: '未通过',
        error: '✖ 端点或模型名不存在（404）',
        detail: '{"error":"model_not_found"}',
      );
      expect(lines, [
        '✖ HTTP 404',
        '✖ 端点或模型名不存在（404）',
        '{"error":"model_not_found"}',
        'usage: n/a',
        '未通过',
      ]);
    });

    test('记录行按真实留痕字段拼装', () {
      final now = DateTime(2026, 9, 30, 12);
      final ts = now.subtract(const Duration(minutes: 3)).millisecondsSinceEpoch;
      expect(
        kitAiapiHistLine(provider: '小工具', model: 'AI 端点验证', ok: true, ms: 321, err: '', ts: ts, now: now),
        '3 分钟前 · 小工具/AI 端点验证 · ✔ 321ms',
      );
      expect(
        kitAiapiHistLine(provider: '小工具', model: 'AI 端点验证', ok: false, ms: 0, err: '401', ts: ts, now: now),
        contains('✖ 401'),
      );
    });
  });

  group('3 · 落库结构（不存 Key）', () {
    test('round-trip · 提示词留空回落默认 · 非法协议回落 openai', () {
      final d = kitAiapiEncode(
        providerId: 'deepseek',
        baseUrl: 'https://a/v1',
        model: 'x',
        prompt: '只回 OK',
        protocol: kKitAiapiProtoAnthropic,
      );
      expect(d.containsKey('aiKey'), isFalse);
      final s = KitAiapiState.decode(d);
      expect(
        (s.providerId, s.baseUrl, s.model, s.prompt, s.protocol),
        ('deepseek', 'https://a/v1', 'x', '只回 OK', kKitAiapiProtoAnthropic),
      );
      final def = KitAiapiState.decode({'aiProto': 'grpc'});
      expect(def.prompt, kKitAiapiPromptDefault);
      expect(def.protocol, kKitAiapiProtoOpenai);
      expect((def.baseUrl, def.model, def.providerId), ('', '', ''));
      expect(KitAiapiState.decode({'aiPrompt': ''}).prompt, kKitAiapiPromptDefault);
    });
  });

  group('4 · core 通道纯函数', () {
    test('模拟结果标 mock=true 且回复按提示词回落', () async {
      final r = await aiVerifyMock(delay: Duration.zero);
      expect(r.mock, isTrue);
      expect(r.ok, isTrue);
      expect(r.reply, '连接成功');
      expect(r.head, '✔ 200 OK（模拟）· 812ms');
      expect(r.usage, contains('模拟值'));
      final other = await aiVerifyMock(delay: Duration.zero, prompt: '只回 OK');
      expect(other.reply, '模拟回复 · 未发出请求');
    });

    test('AiVerifyResult 失败态不给假用量', () {
      const r = AiVerifyResult(ok: false, ms: 40, error: '✖ 超时', detail: 'timeout');
      expect(r.head, '✖ 请求未通过 · 40ms');
      expect(r.usage, 'usage: n/a');
    });
  });
}
