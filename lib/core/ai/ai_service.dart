/// AI 能力编排层（纯 Dart）：门控（总开关×能力授权×Key）→ 模板渲染 →
/// 客户端调用 → 输出结构校验。UI 侧「发送内容审阅弹层」用 [renderForReview]
/// 拿到将要发出的完整文本（原则 4：发送前可审阅）。
library;

import 'ai_call_store.dart';
import 'ai_client.dart';
import 'ai_config.dart';
import 'ai_prompt_pack.dart';
import 'ai_validate.dart';
import 'ai_vault.dart';

/// 取消票据：调用方（AI 通道）在用户点「取消」时置位，[AiService.request] 收尾时
/// 据此把这一行记成「取消」而不是「成功」——应答确实回来了，但用户已经不等了，
/// 结果不会被写进业务数据，记录里也不该显示成一次成功调用。
class AiCancelToken {
  bool cancelled = false;
}

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
    AiCallStore? calls,
  }) : _repo = configRepo,
       _vault = keyVault,
       _client = client,
       _pack = pack,
       _calls = calls;

  final AiConfigRepository _repo;
  final AiKeyVault _vault;
  final AiClient _client;
  final AiPromptPack _pack;

  /// V1.53 使用记录（可空＝无库环境，如未开库的 widget 测试）。
  final AiCallStore? _calls;
  bool _prunedOnce = false;

  /// 落一行使用记录。**任何写库异常都吞掉**：留痕失败绝不能改变调用结果或把
  /// 成功的服务员请求变成业务异常（记录是旁路，不是主路）。
  Future<void> _record({
    required String taskId,
    String? module,
    String? name,
    required String status,
    int inTok = 0,
    int outTok = 0,
    int ms = 0,
    String sys = '',
    String usr = '',
    String out = '',
    String err = '',
  }) async {
    final store = _calls;
    if (store == null) return;
    final cfg = _repo.load();
    var cut = false;
    String body(String s) {
      if (!cfg.recordBody) return '';
      if (s.length <= AiCallStore.maxBodyChars) return s;
      cut = true;
      return s.substring(0, AiCallStore.maxBodyChars);
    }

    try {
      await store.insert(AiCallRecord(
        ts: DateTime.now().millisecondsSinceEpoch,
        taskId: taskId,
        module: module ?? '未归类',
        name: name ?? taskId,
        status: status,
        inTok: inTok,
        outTok: outTok,
        ms: ms,
        sys: body(sys),
        usr: body(usr),
        out: body(out),
        // 原因不是「正文」：停记正文时也要能查清为什么没成。
        err: err,
        cut: cut,
      ));
      if (!_prunedOnce) {
        _prunedOnce = true;
        await store.prune(cfg.callKeepDays);
      }
    } catch (_) {
      // 旁路失败静默：调用结果优先。
    }
  }

  /// 门控前移的入口（[aiRunWithReview]）在拒绝时也要留痕：零请求同样入账。
  Future<void> recordDenied(String taskId, String reason) async {
    final t = _pack.taskById(taskId);
    await _record(
      taskId: taskId,
      module: t?.module,
      name: t?.name,
      status: AiCallStore.statusDenied,
      err: reason,
    );
  }

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

  /// 三重门控预检（总开关×能力授权×Key）：返回拒绝原因，null=可发起。
  /// UI 入口在弹「发送审阅」前先调它——未授权即刻 toast，不进审阅流程。
  Future<String?> gate(String taskId) async {
    final cfg = _repo.load();
    if (!cfg.master) {
      return 'AI 总开关未开启：请先到 设置 → AI 增强 打开';
    }
    // 与请求路径同源判定（不含 master，此处 master 已判过）。
    if (cfg.caps[taskId] != true) {
      return '该能力未授权（${effectiveTask(taskId).name}）：'
          '请在 AI 增强页的能力矩阵中开启';
    }
    final key = (await _vault.read(cfg.active.id))?.trim() ?? '';
    if (key.isEmpty) {
      return '请先在 设置 → AI 增强 为「${cfg.active.name}」配置并验证 API Key';
    }
    return null;
  }

  /// 发起一次能力调用：三重门控任一不过即 [AiDenied]（零请求）。
  /// [temperature] 由调用方按任务形态给（生成类可高些）。
  /// [cancel] 由 AI 通道在用户点「取消」时置位，用于把这一行记成「取消」。
  Future<AiCallResult> request(
    String taskId,
    Map<String, String> vars, {
    double? temperature,
    AiCancelToken? cancel,
  }) async {
    final denial = await gate(taskId);
    if (denial != null) {
      await recordDenied(taskId, denial);
      throw AiDenied(denial);
    }
    final provider = _repo.load().active;
    final key = (await _vault.read(provider.id))!.trim();
    final t = effectiveTask(taskId);
    final userText = renderTemplate(t.user, vars);
    final sw = Stopwatch()..start();
    final AiReply reply;
    try {
      reply = await _client.chat(
        baseUrl: provider.baseUrl,
        model: provider.model,
        apiKey: key,
        protocol: provider.protocol,
        temperature: temperature ?? (t.expect == AiExpect.text ? 0.7 : 0.2),
        messages: [
          {'role': 'system', 'content': t.system},
          {'role': 'user', 'content': userText},
        ],
      );
    } on AiException catch (e) {
      // 失败同样入账（含发送内容）：使用记录页要能查清「发出去了什么、为什么没回」。
      await _record(
        taskId: t.id,
        module: t.module,
        name: t.name,
        status: AiCallStore.statusFail,
        ms: sw.elapsedMilliseconds,
        sys: t.system,
        usr: userText,
        err: '${e.userMessage} ${e.detail}',
      );
      rethrow;
    }
    final bad = validateAiOutput(taskId, t.expect, reply.content, vars);
    final status = bad != null
        ? AiCallStore.statusFail
        : (cancel?.cancelled ?? false)
            ? AiCallStore.statusCancel
            : AiCallStore.statusOk;
    await _record(
      taskId: t.id,
      module: t.module,
      name: t.name,
      status: status,
      inTok: reply.promptTokens,
      outTok: reply.completionTokens,
      ms: reply.latencyMs,
      sys: t.system,
      usr: userText,
      out: reply.content,
      err: bad ?? '',
    );
    if (bad != null) throw AiBadOutput(bad);
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

  /// 连通性验证（小工具·AI API 验证 / 服务商表单「测试连接」）：不过能力门控，
  /// 直接用传入参数发一次最简请求。**同样入使用记录**（module=小工具），
  /// 因为用户关心的正是「这个端点到底通不通、什么时候试的」。
  Future<AiReply> verifyEndpoint({
    required String baseUrl,
    required String model,
    required String apiKey,
    required String prompt,
    String protocol = 'openai',
  }) async {
    final t = _pack.taskById('tool.verify');
    const system = '你是接口连通性验证助手。按用户要求作答，回答保持简短。';
    final sw = Stopwatch()..start();
    try {
      final reply = await _client.chat(
        baseUrl: baseUrl,
        model: model,
        apiKey: apiKey,
        protocol: protocol,
        temperature: 0.2,
        timeout: const Duration(seconds: 20),
        messages: [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': prompt},
        ],
      );
      await _record(
        taskId: 'tool.verify',
        module: t?.module ?? '小工具',
        name: 'AI 端点验证',
        status: AiCallStore.statusOk,
        inTok: reply.promptTokens,
        outTok: reply.completionTokens,
        ms: reply.latencyMs,
        sys: system,
        usr: prompt,
        out: reply.content,
      );
      return reply;
    } on AiException catch (e) {
      await _record(
        taskId: 'tool.verify',
        module: t?.module ?? '小工具',
        name: 'AI 端点验证',
        status: AiCallStore.statusFail,
        ms: sw.elapsedMilliseconds,
        sys: system,
        usr: prompt,
        err: '${e.userMessage} ${e.detail}',
      );
      rethrow;
    }
  }
}
