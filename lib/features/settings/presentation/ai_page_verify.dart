part of 'ai_page.dart';

// 治理G7d⑤：连通性验证页自 ai_page 整块外提（行为零改动）。
// AiVerifyPage(State)：三态＝通过/凭据错误/网络失败；tool.verify 不受能力矩阵门控（R8 豁免）。

/// 小工具 · AI API 验证（原型 aiapi）：真实发一次最简请求 + 精确归因。
class AiVerifyPage extends ConsumerStatefulWidget {
  const AiVerifyPage({super.key});

  @override
  ConsumerState<AiVerifyPage> createState() => _AiVerifyPageState();
}

class _AiVerifyPageState extends ConsumerState<AiVerifyPage> {
  final _url = TextEditingController();
  final _model = TextEditingController();
  final _key = TextEditingController();
  final _prompt = TextEditingController(text: '请只回复四个字：连接成功');
  bool _busy = false;
  String _protocol = 'openai';
  String? _result;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefill());
  }

  Future<void> _prefill() async {
    final cfg = ref.read(aiConfigProvider);
    final key = await ref.read(aiKeyVaultProvider).read(cfg.active.id) ?? '';
    if (!mounted) return;
    _url.text = cfg.baseUrl;
    _model.text = cfg.model;
    _protocol = cfg.protocol;
    _key.text = key;
    setState(() {});
  }

  /// 验证成功后 Key 该存进哪条服务商：地址能对上就对号，对不上存当前端点。
  String _keySlotFor(String url) {
    final norm = aiNormBase(url);
    for (final p in ref.read(aiConfigProvider).providers) {
      if (aiNormBase(p.baseUrl) == norm) return p.id;
    }
    return ref.read(aiConfigProvider).active.id;
  }

  @override
  void dispose() {
    _url.dispose();
    _model.dispose();
    _key.dispose();
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _result = '⏳ POST ${_url.text.trim()}'
          '${_protocol == 'anthropic' ? '/messages' : '/chat/completions'} · '
          'model=${_model.text.trim()} …';
      _ok = false;
    });
    final svc = ref.read(aiServiceProvider);
    try {
      final r = await svc.verifyEndpoint(
        baseUrl: _url.text.trim(),
        model: _model.text.trim(),
        apiKey: _key.text.trim(),
        prompt: _prompt.text.trim().isEmpty ? '请只回复四个字：连接成功' : _prompt.text.trim(),
        protocol: _protocol,
      );
      // 验证通过：Key 落对应服务商的加密槽 + 端点回写配置 + 状态记档。
      await ref.read(aiKeyVaultProvider)
          .write(_key.text.trim(), providerId: _keySlotFor(_url.text));
      await ref.read(aiConfigProvider.notifier).setEndpoint(_url.text.trim(), _model.text.trim(), protocol: _protocol);
      await ref.read(aiConfigProvider.notifier).setVerifyResult(
          ok: true, at: DateTime.now().millisecondsSinceEpoch, latencyMs: r.latencyMs);
      AppLog.add('AI 端点验证成功 · ${r.latencyMs}ms · '
          '入 ${r.promptTokens}/出 ${r.completionTokens} tokens');
      if (!mounted) return;
      setState(() {
        _ok = true;
        _result = '✓ ${r.latencyMs}ms · 200 OK\n'
            '模型回复：${r.content}\n'
            'usage: ${r.promptTokens} + ${r.completionTokens} tokens\n'
            '验证通过 · 可回 AI 增强页逐项开启能力矩阵';
      });
    } on AiException catch (e) {
      // 验证失败同样进日志：日志页是「所有报错一处可查」的落点。
      AppLog.add('AI 端点验证失败：${e.kind.name}: ${e.detail}',
          level: LhLevel.error);
      await ref.read(aiConfigProvider.notifier).setVerifyResult(
          ok: false, at: DateTime.now().millisecondsSinceEpoch, reason: e.userMessage);
      if (!mounted) return;
      setState(() {
        _ok = false;
        _result = '${e.userMessage}\n${e.detail}';
      });
    } catch (e) {
      AppLog.add('AI 端点验证未预期错误：$e', level: LhLevel.error);
      if (!mounted) return;
      setState(() {
        _ok = false;
        _result = '✕ 未预期错误：$e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI API 验证')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('供「设置 → AI 增强」使用：验证服务商 / Key / 模型是否可用。'
              '默认采用 OpenAI 兼容 Chat Completions 协议，请求仅发往下方填写的地址。',
              style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.6)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in ref.watch(aiConfigProvider).providers)
                ChoiceChip(
                  key: ValueKey('ai-verify-chip-${p.id}'),
                  label: Text(p.name, style: const TextStyle(fontSize: 11.5)),
                  selected: aiNormBase(_url.text) == aiNormBase(p.baseUrl),
                  onSelected: (_) => setState(() {
                    _url.text = p.baseUrl;
                    _model.text = p.model;
                    _protocol = p.protocol;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
              key: const ValueKey('ai-verify-url'),
              controller: _url,
              style: const TextStyle(fontSize: 12.5),
              decoration: const InputDecoration(
                  isDense: true, labelText: 'Base URL', hintText: 'https://api.xxx.com/v1')),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                    key: const ValueKey('ai-verify-key'),
                    controller: _key,
                    obscureText: true,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: const InputDecoration(isDense: true, labelText: 'API Key')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                    key: const ValueKey('ai-verify-model'),
                    controller: _model,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: const InputDecoration(isDense: true, labelText: '模型名')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
              key: const ValueKey('ai-verify-prompt'),
              controller: _prompt,
              maxLines: 2,
              style: const TextStyle(fontSize: 12.5),
              decoration: const InputDecoration(
                  isDense: true, labelText: '验证提示词', hintText: '请只回复四个字：连接成功')),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('ai-verify-send'),
                  onPressed: _busy ? null : _send,
                  icon: const Icon(Icons.send_outlined, size: 16),
                  label: Text(_busy ? '请求中…' : '真实发送验证'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            key: const ValueKey('ai-verify-res'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.35)),
            ),
            child: Text(
              _result ?? '结果将显示在此：模型回复 / 延迟 / token 用量，'
                  '或精确错误原因（401 Key 无效 / 404 模型名 / 429 限流 / 超时）。',
              style: TextStyle(
                  fontSize: 11,
                  height: 1.6,
                  fontFamily: 'monospace',
                  color: _result == null
                      ? Colors.grey
                      : _ok
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF43F5E)),
            ),
          ),
        ],
      ),
    );
  }
}
