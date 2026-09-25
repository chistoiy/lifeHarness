/// AI 客户端（纯 Dart）：OpenAI 兼容 Chat Completions 唯一出口。
///
/// 端点自治：只请求用户配置的 Base URL，无任何自建埋点/旁路上报。
/// 失败精确归因（401 Key / 404 模型名或端点 / 429 限流 / 超时 / 网络不通），
/// 归因文案直接给验证工具与能力点调用方展示；Key 永不进日志。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

enum AiFailKind {
  noBaseUrl,
  noKey,
  badRequest, // 400 等：请求体/参数被端点拒绝
  unauthorized, // 401/403
  notFound, // 404/410：模型名或路径不存在
  rateLimited, // 429/503
  timeout,
  unreachable,
  badResponse, // 200 但解析不出内容
  server, // 5xx 其余
}

class AiException implements Exception {
  AiException(this.kind, this.detail);

  final AiFailKind kind;
  final String detail;

  /// 面向用户的精确归因（验证工具失败态展示口径）。
  String get userMessage => switch (kind) {
        AiFailKind.noBaseUrl => '✖ 请填写 Base URL',
        AiFailKind.noKey => '✖ 未配置 API Key',
        AiFailKind.badRequest => '✖ 请求被端点拒绝（400）：$detail',
        AiFailKind.unauthorized => '✖ Key 无效或未授权（401/403）',
        AiFailKind.notFound => '✖ 端点或模型名不存在（404）：请核对模型名',
        AiFailKind.rateLimited => '✖ 限流（429/503）：请稍后再试',
        AiFailKind.timeout => '✖ 请求超时：端点无响应',
        AiFailKind.unreachable => '✖ 无法连接端点：检查地址与网络',
        AiFailKind.badResponse => '✖ 响应解析失败：$detail',
        AiFailKind.server => '✖ 端点服务异常（$detail）',
      };

  @override
  String toString() => 'AiException(${kind.name}): $detail';
}

class AiReply {
  const AiReply({
    required this.content,
    required this.latencyMs,
    required this.promptTokens,
    required this.completionTokens,
  });

  final String content;
  final int latencyMs;
  final int promptTokens;
  final int completionTokens;
}

typedef AiMessages = List<Map<String, String>>;

class AiClient {
  AiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  void close() => _client.close();

  /// 发一次 Chat Completions。baseUrl 不带尾斜杠；timeout 缺省 90s
  /// （深度生成类任务如目录补全可能 >30s）。
  Future<AiReply> chat({
    required String baseUrl,
    required String model,
    required String apiKey,
    required AiMessages messages,
    Duration timeout = const Duration(seconds: 90),
    double temperature = 0.4,
  }) async {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) throw AiException(AiFailKind.noBaseUrl, baseUrl);
    final key = apiKey.trim();
    if (key.isEmpty) throw AiException(AiFailKind.noKey, 'empty key');
    final sw = Stopwatch()..start();
    http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('$base/chat/completions'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $key',
            },
            body: jsonEncode({
              'model': model.trim(),
              'messages': messages,
              'temperature': temperature,
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw AiException(AiFailKind.timeout, 'timeout ${timeout.inSeconds}s');
    } on SocketException {
      throw AiException(AiFailKind.unreachable, base);
    } on HttpException catch (e) {
      throw AiException(AiFailKind.unreachable, e.message);
    }
    sw.stop();
    final status = res.statusCode;
    // 统一 UTF-8 解码读体（Latin1 直读会在中文错误体上抛异常）。
    final bodyText = utf8.decode(res.bodyBytes, allowMalformed: true);
    if (status != 200) {
      throw AiException(_kindOfStatus(status), _briefBody(bodyText));
    }
    Map<String, dynamic> j;
    try {
      j = jsonDecode(bodyText) as Map<String, dynamic>;
    } catch (_) {
      throw AiException(AiFailKind.badResponse, '非 JSON 响应体');
    }
    final choices = j['choices'] as List?;
    final content = choices == null || choices.isEmpty
        ? null
        : ((choices.first as Map)['message']?['content'] as String?)?.trim();
    if (content == null || content.isEmpty) {
      // 端点报错常以 200+error 字段回传，尽量带出原因。
      final err = j['error'];
      throw AiException(
          AiFailKind.badResponse,
          err is Map ? '${err['code'] ?? ''} ${err['message'] ?? ''}'.trim()
              : '回复内容为空');
    }
    final usage = (j['usage'] as Map?) ?? const {};
    return AiReply(
      content: content,
      latencyMs: sw.elapsedMilliseconds,
      promptTokens: (usage['prompt_tokens'] as num?)?.toInt() ?? 0,
      completionTokens: (usage['completion_tokens'] as num?)?.toInt() ?? 0,
    );
  }

  static AiFailKind _kindOfStatus(int s) => switch (s) {
        401 || 403 => AiFailKind.unauthorized,
        404 || 410 => AiFailKind.notFound,
        429 || 503 => AiFailKind.rateLimited,
        400 => AiFailKind.badRequest,
        >= 500 => AiFailKind.server,
        _ => AiFailKind.badResponse,
      };

  static String _briefBody(String body) {
    final flat = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 160 ? flat : '${flat.substring(0, 160)}…';
  }
}
