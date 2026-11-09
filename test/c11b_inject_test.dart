import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifeharness/core/ai/ai_client.dart';
import 'package:lifeharness/core/ai/ai_config.dart';
import 'package:lifeharness/core/ai/ai_prompt_pack.dart';
import 'package:lifeharness/core/ai/ai_service.dart';
import 'package:lifeharness/core/ai/ai_vault.dart';
import 'package:lifeharness/core/ai/local_recall.dart';
import 'package:lifeharness/core/ai/local_recall_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// C11b：本地召回「装配 → 注入 prompt → 审阅可见」的接线守护。
/// 全程 MockClient 捕获真实请求体，零网络；正负两档同例都断。
AiPromptPack _pack() => AiPromptPack.decode(
    File('assets/ai_prompts/prompts.json').readAsStringSync());

http.Response _resp(String text) => http.Response.bytes(
      utf8.encode(jsonEncode({
        'choices': [
          {
            'message': {'content': text}
          }
        ],
        'usage': {'prompt_tokens': 3, 'completion_tokens': 2}
      })),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

const _basePrefs = <String, Object>{
  'ai.master': true,
  'ai.caps': '{"journal.reflect":true}',
};

/// 全文里才有的唯一尾巴：短片段不得带出，用于证「不上传全库」。
const _tail = 'TAIL-ONLY-IN-FULLTEXT-9988';

List<RecallDoc> _docs() => [
      RecallDoc(
        id: 'note:1',
        title: '汽车保养笔记',
        body: '保养${'甲' * 240} $_tail',
      ),
    ];

class _FakeSource implements LocalRecallSource {
  _FakeSource(this.docs);

  final List<RecallDoc> docs;
  int loads = 0;

  @override
  Future<List<RecallDoc>> load() async {
    loads++;
    return docs;
  }
}

Future<AiService> _svc({
  required Map<String, Object> prefs,
  LocalRecallSource? source,
  required void Function(http.Request) onRequest,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  return AiService(
    configRepo: AiConfigRepository(await SharedPreferences.getInstance()),
    keyVault: AiKeyVault.inMemory(apiKey: 'sk-test'),
    client: AiClient(client: MockClient((req) async {
      onRequest(req);
      // 夹具回复必须 ≥15 字：ai_validate 有输出下限，短回复会被判「不合约定」，
      // 那是夹具问题不是注入实现问题（C01 批同款坑）。
      return _resp('这是一段反思草稿，用来验证引用注入是否落在正确的请求体里，长度足够通过输出校验。');
    })),
    pack: _pack(),
    recallSource: source,
  );
}

String _userOf(http.Request req) {
  final msgs = (jsonDecode(req.body) as Map)['messages'] as List;
  return (msgs[1] as Map)['content'] as String;
}

void main() {
  final hits = localRecall(query: '保养', docs: _docs());
  const vars = {'content': '保养'};

  test('开·显式命中：请求体含引用标记与来源，不含全文尾巴；审阅同源', () async {
    late http.Request captured;
    final svc = await _svc(
      prefs: _basePrefs,
      onRequest: (r) => captured = r,
    );
    expect(hits, isNotEmpty, reason: '前置：召回源应有命中');

    await svc.request('journal.reflect', vars, recalls: hits);
    final sent = _userOf(captured);
    expect(sent, contains('本地参考片段'));
    expect(sent, contains('《汽车保养笔记》'));
    expect(sent, contains('保养'));
    expect(sent, isNot(contains(_tail)), reason: '只发短片段，不上传全文');

    final (_, reviewed) =
        svc.renderForReview('journal.reflect', vars, recalls: hits);
    expect(reviewed, sent, reason: '审阅所见＝实际所发（C01 同源）');
  });

  test('关·显式命中：请求体与审阅均零引用标记', () async {
    late http.Request captured;
    final svc = await _svc(
      prefs: {..._basePrefs, 'ai.local_recall': false},
      onRequest: (r) => captured = r,
    );

    await svc.request('journal.reflect', vars, recalls: hits);
    final sent = _userOf(captured);
    expect(sent, isNot(contains('本地参考片段')));
    expect(sent, isNot(contains('《汽车保养笔记》')));
    expect(sent, contains('保养'), reason: '原始用户输入仍应保留');

    final (_, reviewed) =
        svc.renderForReview('journal.reflect', vars, recalls: hits);
    expect(reviewed, isNot(contains('本地参考片段')));
    expect(reviewed, sent);
  });

  test('开·自动装配：不传 recalls 也从本地源召回并注入', () async {
    final source = _FakeSource(_docs());
    late http.Request captured;
    final svc = await _svc(
      prefs: _basePrefs,
      source: source,
      onRequest: (r) => captured = r,
    );

    await svc.request('journal.reflect', vars);
    final sent = _userOf(captured);
    expect(source.loads, 1);
    expect(sent, contains('本地参考片段'));
    expect(sent, contains('《汽车保养笔记》'));
    expect(sent, isNot(contains(_tail)));
  });

  test('关·自动装配：不读源、零召回、prompt 不含引用段', () async {
    final source = _FakeSource(_docs());
    late http.Request captured;
    final svc = await _svc(
      prefs: {..._basePrefs, 'ai.local_recall': false},
      source: source,
      onRequest: (r) => captured = r,
    );

    await svc.request('journal.reflect', vars);
    final sent = _userOf(captured);
    expect(source.loads, 0, reason: '开关关＝连本地源都不读');
    expect(sent, isNot(contains('本地参考片段')));
    expect(sent, isNot(contains('《汽车保养笔记》')));
  });
}
