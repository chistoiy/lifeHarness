import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifeharness/core/ai/ai_client.dart';
import 'package:lifeharness/core/ai/ai_config.dart';
import 'package:lifeharness/core/ai/ai_prompt_pack.dart';
import 'package:lifeharness/core/ai/ai_service.dart';
import 'package:lifeharness/core/ai/ai_summary.dart';
import 'package:lifeharness/core/ai/ai_vault.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// C01「仅摘要发送」拍板口径守护（纯逻辑 + 零真实网络）。
AiPromptPack _pack() => AiPromptPack.decode(
    File('assets/ai_prompts/prompts.json').readAsStringSync());

const _tail = '结尾唯一标记 XYZ-7788';

void main() {
  group('C01 摘要值', () {
    test('短文本原样；长文本只留开头并给省略回执', () {
      expect(summarizeValue('今天写了点东西'), '今天写了点东西');
      final long = '今天' * 100 + _tail;
      final out = summarizeValue(long);
      expect(out, startsWith('今天' * 20));
      expect(out, contains('已省略'));
      expect(out, contains('原文 ${long.length} 字'));
      expect(out, isNot(contains(_tail)));
    });

    test('多行只取前三行，保留换行结构', () {
      final long = '第一行\n第二行\n第三行\n第四行\n${'补充' * 100}';
      final out = summarizeValue(long);
      expect(out.split('…').first, '第一行\n第二行\n第三行');
    });
  });

  group('C01 策略适用范围', () {
    test('白名单内且开启才生效；非白名单/关闭/短值一律原样', () {
      final long = '正文' * 100 + _tail;
      final vars = {'content': long};
      expect(applySummaryPolicy('journal.reflect', vars, enabled: true)['content'],
          contains('已省略'));
      expect(applySummaryPolicy('schedule.weekly_review', vars, enabled: true),
          vars,
          reason: '聚合统计类能力点不重复处理');
      expect(applySummaryPolicy('journal.reflect', vars, enabled: false), vars);
      expect(applySummaryPolicy('journal.reflect', {'content': '短'},
          enabled: true), {'content': '短'});
    });

    test('不改调用方传入的 vars', () {
      final vars = {'content': '正文' * 100};
      applySummaryPolicy('journal.reflect', vars, enabled: true);
      expect(vars['content'], '正文' * 100);
    });
  });

  group('C01 唯一渲染出口接入', () {
    test('默认摘要；关闭开关后恢复全文', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = AiConfigRepository(prefs);
      final svc = AiService(
        configRepo: repo,
        keyVault: AiKeyVault.inMemory(apiKey: 'k'),
        client: AiClient(client: MockClient((_) async => http.Response('{}', 200))),
        pack: _pack(),
      );
      final vars = {'content': '今天' * 100 + _tail};

      final (_, brief) = svc.renderForSend('journal.reflect', vars);
      expect(brief, contains('已省略'));
      expect(brief, isNot(contains(_tail)));
      expect(brief, contains('请生成反思段落'),
          reason: '提示词模板不能被摘要截掉');

      await repo.setSummaryOnly(false);
      final (_, full) = svc.renderForSend('journal.reflect', vars);
      expect(full, contains(_tail));
      expect(full, isNot(contains('已省略')));
    });

    test('子批B：身份串脱敏开关——关＝原样发送，默认开＝手机号打码', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = AiConfigRepository(prefs);
      final svc = AiService(
        configRepo: repo,
        keyVault: AiKeyVault.inMemory(apiKey: 'k'),
        client: AiClient(client: MockClient((_) async => http.Response('{}', 200))),
        pack: _pack(),
      );
      final vars = {'content': '联系电话 13800138000 请回电'};
      final (_, masked) = svc.renderForSend('journal.reflect', vars);
      expect(masked, isNot(contains('13800138000')));

      await repo.setRedactIdents(false);
      final (_, raw) = svc.renderForSend('journal.reflect', vars);
      expect(raw, contains('13800138000'));
    });
  });
}
