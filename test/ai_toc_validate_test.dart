import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifeharness/core/ai/ai_client.dart';
import 'package:lifeharness/core/ai/ai_prompt_pack.dart';
import 'package:lifeharness/core/ai/ai_validate.dart';

/// 阅读「AI 补全目录」真机报错两处修复的回归（V1.43.1）：
/// ① `read.toc` 空 chapters 是提示词明许的合法产出（该书确实未知就不编造），
///    旧校验器把它判成「chapters 结构错: []」；上限 40 节也拦不住 69 节的实书。
/// ② 端点半途断连时 package:http 抛 [http.ClientException]（不是 SocketException），
///    旧写法漏归因 → toast 直出裸英文原文。
void main() {
  String? tocErr(String chaptersJson) => validateAiOutput(
      'read.toc', AiExpect.json, '{"chapters":$chaptersJson}', const {});

  Future<AiException> chatFailing(Object error) async {
    final client = AiClient(
        client: MockClient((req) async => throw error));
    addTearDown(client.close);
    try {
      await client.chat(
        baseUrl: 'https://api.test/v1',
        model: 'm',
        apiKey: 'sk-t',
        messages: const [
          {'role': 'user', 'content': 'hi'}
        ],
      );
    } on AiException catch (e) {
      return e;
    }
    throw StateError('预期抛 AiException，实际正常返回');
  }

  group('read.toc 校验', () {
    test('空 chapters 合法（AI「未知则返回空」不编造，由调用方给友好回执）', () {
      expect(tocErr('[]'), isNull);
    });

    test('69 节实书不再被旧上限 40 拦掉', () {
      final cs = List.generate(69, (i) => '{"title":"第$i 章"}');
      expect(tocErr('[${cs.join(',')}]'), isNull);
    });

    test('放宽到 120 才拒（仍防端点疯输出）', () {
      final cs = List.generate(121, (i) => '{"title":"第$i 章"}');
      expect(tocErr('[${cs.join(',')}]'), contains('章节过多: 121'));
    });

    test('条目形态仍要守：非 Map / title 非字符串判结构错', () {
      expect(tocErr('[{"title":null}]'), contains('chapters 结构错'));
      expect(tocErr('["第一章"]'), contains('chapters 结构错'));
      expect(tocErr('[{"part":"上","title":"一"}]'), isNull);
    });
  });

  group('AiClient 失败归因', () {
    test('ClientException → aborted 档中文归因（旧写法漏网出裸英文）', () async {
      final e = await chatFailing(http.ClientException(
          'Connection closed while receiving data',
          Uri.parse('https://api.test/v1/chat/completions')));
      expect(e.kind, AiFailKind.aborted);
      expect(e.userMessage, contains('连接被端点中断'));
      expect(e.userMessage, contains('重试'));
      expect(e.detail, contains('Connection closed'));
    });

    test('其它异常类型不被误归因（仍由上层兜底记日志）', () async {
      expect(
          chatFailing(StateError('boom')), throwsA(isNot(isA<AiException>())));
    });
  });
}
