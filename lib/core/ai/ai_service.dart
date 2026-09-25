/// AI 能力编排层（纯 Dart）：门控（总开关×能力授权×Key）→ 模板渲染 →
/// 客户端调用 → 输出结构校验。UI 侧「发送内容审阅弹层」用 [renderForReview]
/// 拿到将要发出的完整文本（原则 4：发送前可审阅）。
library;

import 'ai_client.dart';
import 'ai_config.dart';
import 'ai_prompt_pack.dart';
import 'ai_validate.dart';
import 'ai_vault.dart';

/// 一次能力调用的产出。
class AiCallResult {
  const AiCallResult({
    required this.reply,
    required this.taskId,
    this.json,
    this.text,
  });

  final AiReply reply;
  final String taskId;

  /// expect=json 时的解析结果；text 时为 null。
  final Map<String, dynamic>? json;
  final String? text;

  Map<String, dynamic> requireJson() {
    final j = json;
    if (j == null) throw AiException(AiFailKind.badResponse, '结果非 JSON');
    return j;
  }

  String requireText() => text ?? '';
}

/// 输出校验不通过（模型回复不守格式）。
class AiBadOutput implements Exception {
  const AiBadOutput(this.reason);
  final String reason;
  @override
  String toString() => 'AI 输出不合约定：$reason';
}

class AiDenied implements Exception {
  const AiDenied(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

class AiService {
  AiService({
    required AiConfigRepository configRepo,
    required AiKeyVault keyVault,
    required AiClient client,
    required AiPromptPack pack,
  }) : _repo = configRepo,
       _vault = keyVault,
       _client = client,
       _pack = pack;

  final AiConfigRepository _repo;
  final AiKeyVault _vault;
  final AiClient _client;
  final AiPromptPack _pack;

  /// 生效提示词任务：默认包 + 用户覆盖（逐段 system/user 独立覆盖）。
  AiPromptTask effectiveTask(String taskId) {
    final base = _pack.taskById(taskId);
    if (base == null) {
      throw ArgumentError.value(taskId, 'taskId', '未注册的 AI 能力点');
    }
    final ov = _repo.load().promptOverrides[taskId] ?? const {};
    return AiPromptTask(
      id: base.id,
      module: base.module,
      name: base.name,
      system: ov['system'] ?? base.system,
      user: ov['user'] ?? base.user,
      expect: base.expect,
      placeholders: base.placeholders,
      sample: base.sample,
    );
  }

  List<AiPromptTask> get tasks => _pack.tasks;

  /// 渲染审阅文本：(system, user) 两段完整内容。
  (String system, String user) renderForReview(
      String taskId, Map<String, String> vars) {
    final t = effectiveTask(taskId);
    return (t.system, renderTemplate(t.user, vars));
  }

  /// 发起一次能力调用：三重门控任一不过即 [AiDenied]（零请求）。
  /// [temperature] 由调用方按任务形态给（生成类可高些）。
  Future<AiCallResult> request(
    String taskId,
    Map<String, String> vars, {
    double? temperature,
  }) async {
    final cfg = _repo.load();
    if (!cfg.master) {
      throw const AiDenied('AI 总开关未开启：请先到 设置 → AI 增强 打开');
    }
    if (!cfg.capEnabled(taskId)) {
      throw AiDenied('该能力未授权（${effectiveTask(taskId).name}）：'
          '请在 AI 增强页的能力矩阵中开启');
    }
    final key = (await _vault.read())?.trim() ?? '';
    if (key.isEmpty) {
      throw const AiDenied('请先在 设置 → AI 增强 配置并验证 API Key');
    }
    final t = effectiveTask(taskId);
    final reply = await _client.chat(
      baseUrl: cfg.baseUrl,
      model: cfg.model,
      apiKey: key,
      temperature: temperature ?? (t.expect == AiExpect.text ? 0.7 : 0.2),
      messages: [
        {'role': 'system', 'content': t.system},
        {'role': 'user', 'content': renderTemplate(t.user, vars)},
      ],
    );
    final err = validateAiOutput(taskId, t.expect, reply.content, vars);
    if (err != null) throw AiBadOutput(err);
    return AiCallResult(
      reply: reply,
      taskId: taskId,
      json: t.expect == AiExpect.json
          ? decodeJsonObject(reply.content)
          : null,
      text: t.expect == AiExpect.text
          ? cleanTextResult(reply.content)
          : null,
    );
  }

  /// 连通性验证（小工具·AI API 验证 / 设置页重新验证）：不过能力门控，
  /// 直接用传入参数发一次最简请求。
  Future<AiReply> verifyEndpoint({
    required String baseUrl,
    required String model,
    required String apiKey,
    required String prompt,
  }) =>
      _client.chat(
        baseUrl: baseUrl,
        model: model,
        apiKey: apiKey,
        temperature: 0.2,
        timeout: const Duration(seconds: 20),
        messages: [
          {'role': 'system', 'content': '你是接口连通性验证助手。按用户要求作答，回答保持简短。'},
          {'role': 'user', 'content': prompt},
        ],
      );
}
