/// 小工具 · AI API 验证通道（批3 · R7 唯一入口口径）。
///
/// 「AI API 验证」屏是**唯一**会真实出站的工具屏，但它依旧不直接取
/// `AiService`/`AiClient`：端点/模型/协议/Key 四个入参在这里交给
/// [AiService.verifyEndpoint]，留痕（运行日志 + ai_calls 使用记录）与精确归因
/// 全部沿用 core/ai 既有那一套。屏侧只拿到 [AiVerifyResult] 这一种形状。
///
/// 为什么要单独一个通道文件（而不是复用 `aiRunWithReview`）：`tool.verify` 的
/// 语义是「拿用户当场填的四个参数试一次连通性」，它必须**绕过**能力门控与
/// 提示词模板（否则改个模型名也要先开总开关），而审阅弹层在这里反而是噪音——
/// 屏上已经把完整请求参数摊开给用户看了。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_call_store.dart';
import 'ai_client.dart';
import 'ai_config.dart';
import 'ai_providers.dart';

/// 一次验证的结果（成功/失败/模拟三态统一形状）。
class AiVerifyResult {
  const AiVerifyResult({
    required this.ok,
    required this.ms,
    this.reply = '',
    this.inTok = 0,
    this.outTok = 0,
    this.error = '',
    this.detail = '',
    this.mock = false,
    this.endpoint = '',
  });

  final bool ok;
  final int ms;
  final String reply;
  final int inTok;
  final int outTok;

  /// 面向用户的归因（[AiException.userMessage] 同口径）。
  final String error;

  /// 技术细节（状态码/原始报文片段），可与 error 分行展示。
  final String detail;

  /// true=本机模拟演示，零出站。
  final bool mock;

  /// 实际请求的完整端点（展示用；Key 永不进这里）。
  final String endpoint;

  /// 结果卡首行。
  String get head => mock
      ? '✔ 200 OK（模拟）· ${ms}ms'
      : ok
      ? '✔ 200 OK · ${ms}ms'
      : '✖ 请求未通过 · ${ms}ms';

  /// token 用量行（缺用量时给 n/a，不编数字）。
  String get usage => (ok || mock)
      ? 'usage: $inTok + $outTok tokens${mock ? '（模拟值）' : ''}'
      : 'usage: n/a';
}

/// 屏侧可选的服务商预设（设置里已配置的真实端点，含预置与用户自增）。
List<AiProvider> aiVerifyPresets(WidgetRef ref) =>
    ref.read(aiConfigProvider).providers;

/// 该服务商在系统保险箱里是否已有 Key（只回布尔，Key 不出通道）。
Future<bool> aiVerifyHasKey(WidgetRef ref, String providerId) async {
  final vault = ref.read(aiKeyVaultProvider);
  // 空 id = 老的全局槽位（read() 自带回落），非空才按服务商槽位查。
  if (providerId.isEmpty) return await vault.read() != null;
  return await vault.readOwn(providerId) != null;
}

/// 真实验证请求（唯一出站口）。失败不抛，统一回 [AiVerifyResult]。
Future<AiVerifyResult> aiVerifyCall(
  WidgetRef ref, {
  required String baseUrl,
  required String model,
  required String apiKey,
  required String prompt,
  String protocol = 'openai',
}) async {
  final svc = ref.read(aiServiceProvider);
  final url = aiVerifyEndpointUrl(baseUrl: baseUrl, protocol: protocol);
  final sw = Stopwatch()..start();
  try {
    final r = await svc.verifyEndpoint(
      baseUrl: baseUrl,
      model: model,
      // 本地端点常不需 Key：占位串让请求真发出去，好拿端点自己的归因。
      apiKey: apiKey.isEmpty ? 'probe' : apiKey,
      prompt: prompt,
      protocol: protocol,
    );
    return AiVerifyResult(
      ok: true,
      ms: r.latencyMs,
      reply: r.content,
      inTok: r.promptTokens,
      outTok: r.completionTokens,
      endpoint: url,
    );
  } on AiException catch (e) {
    return AiVerifyResult(
      ok: false,
      ms: sw.elapsedMilliseconds,
      error: e.userMessage,
      detail: e.detail,
      endpoint: url,
    );
  } catch (e) {
    return AiVerifyResult(
      ok: false,
      ms: sw.elapsedMilliseconds,
      error: '✖ 请求未送达',
      detail: '$e',
      endpoint: url,
    );
  }
}

/// 按协议拼出实际请求路径（屏上展示「POST 哪」；与 AiClient 内部拼接同规则）。
String aiVerifyEndpointUrl({
  required String baseUrl,
  required String protocol,
}) {
  final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  if (base.isEmpty) return '';
  return '$base${protocol == 'anthropic' ? '/messages' : '/chat/completions'}';
}

/// 模拟演示：零出站，字段全部标注为模拟（不给「看起来像真验证」的假结论）。
Future<AiVerifyResult> aiVerifyMock({
  Duration delay = const Duration(milliseconds: 900),
  String prompt = '请只回复四个字：连接成功',
}) async {
  await Future<void>.delayed(delay);
  return AiVerifyResult(
    mock: true,
    ok: true,
    ms: 812,
    reply: prompt.contains('四个字') ? '连接成功' : '模拟回复 · 未发出请求',
    inTok: 9,
    outTok: 4,
  );
}

/// 本机验证记录（读 ai_calls 里 module=小工具 的那几条；与「AI 使用记录」同源）。
Future<List<AiCallRecord>> aiVerifyHistory(
  WidgetRef ref, {
  int limit = 6,
}) async {
  final store = ref.read(aiCallStoreProvider);
  if (store == null) return const [];
  return store.query(const AiCallFilter(module: '小工具'), limit: limit);
}

/// 清空验证记录（只删本模块那几条，不动其他模块的使用记录）。
Future<int> aiVerifyClearHistory(WidgetRef ref) async {
  final store = ref.read(aiCallStoreProvider);
  if (store == null) return 0;
  return store.deleteFiltered(const AiCallFilter(module: '小工具'));
}
