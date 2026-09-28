part of 'ai_page.dart';

// 治理G7d⑤：服务商添加/编辑弹层自 ai_page 整块外提（行为零改动）。
// _AiProviderFormSheet(State)：端点/模型/协议/Key 校验，弹层内红字反馈（页面 SnackBar 被模态遮挡＝既定坑）。

/// 服务商添加/编辑弹层（原型 `sheetAiProv`）。
/// 弹层内的校验反馈走行内红字：页面 SnackBar 会被模态遮罩挡住看不见（既定坑）。
class _AiProviderFormSheet extends ConsumerStatefulWidget {
  const _AiProviderFormSheet({required this.isCurrent, this.provider});

  final AiProvider? provider;
  final bool isCurrent;

  @override
  ConsumerState<_AiProviderFormSheet> createState() =>
      _AiProviderFormSheetState();
}

class _AiProviderFormSheetState extends ConsumerState<_AiProviderFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _model;
  late final TextEditingController _key;
  late String _protocol;
  bool _keyMasked = true;
  bool _httpOk = false;
  bool _busy = false;
  String? _err;
  String _res = '「测试连接」向该 Base URL 发一次最小请求，回真实状态码与耗时。';
  int _resState = 0; // 0=中性 1=通过 -1=失败
  String _storedTail = '';

  bool get _isEdit => widget.provider != null;

  @override
  void initState() {
    super.initState();
    final p = widget.provider;
    _name = TextEditingController(text: p?.name ?? '');
    _url = TextEditingController(text: p?.baseUrl ?? '');
    _model = TextEditingController(text: p?.model ?? '');
    _key = TextEditingController();
    _protocol = p?.protocol ?? 'openai';
    _httpOk = p?.isPlainHttp ?? false;
    if (p != null) _loadStoredKey(p.id);
  }

  /// 已存 Key 以掩码预填（只认该服务商自己的槽位，不含旧全局 Key）。
  Future<void> _loadStoredKey(String id) async {
    final own = await ref.read(aiKeyVaultProvider).readOwn(id) ?? '';
    if (!mounted || own.isEmpty) return;
    _key.text = own;
    setState(() => _storedTail = own.length <= 4 ? own : own.substring(own.length - 4));
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  bool get _plainHttp => _url.text.trim().toLowerCase().startsWith('http://');

  String? get _validateError {
    if (_name.text.trim().isEmpty) return '请填写服务商名称';
    final u = _url.text.trim();
    if (!RegExp(r'^https?://').hasMatch(u)) {
      return 'Base URL 需以 http:// 或 https:// 开头';
    }
    if (_model.text.trim().isEmpty) return '请填写模型名';
    if (u.toLowerCase().startsWith('http://') && !_httpOk) {
      return 'http 明文端点需先确认是局域网/回环地址';
    }
    return null;
  }

  Future<void> _save() async {
    final err = _validateError;
    if (err != null) {
      setState(() => _err = err);
      return;
    }
    final url = aiNormBase(_url.text);
    final id = _isEdit ? widget.provider!.id : AiConfig.newId(url);
    final vault = ref.read(aiKeyVaultProvider);
    final key = _key.text.trim();
    await ref.read(aiConfigProvider.notifier).saveProvider(AiProvider(
          id: id,
          name: _name.text.trim(),
          baseUrl: url,
          model: _model.text.trim(),
          protocol: _protocol,
          builtin: widget.provider?.builtin ?? false,
        ));
    // 空值＝清除该条 Key（与「清空后保存＝删除该 Key」的提示同口径）。
    if (key.isEmpty) {
      await vault.clear(providerId: id);
    } else {
      await vault.write(key, providerId: id);
    }
    if (!_isEdit) await ref.read(aiConfigProvider.notifier).useProvider(id);
    if (!mounted) return;
    Navigator.pop(context, 'saved');
  }

  /// 删除：交回页面走两段式确认（弹层自己关掉）。
  void _requestDelete() =>
      Navigator.pop(context, 'delete:${widget.provider!.id}');

  Future<void> _ping() async {
    final err = _validateError;
    if (err != null) {
      setState(() => _err = err);
      return;
    }
    final url = aiNormBase(_url.text);
    final model = _model.text.trim();
    setState(() {
      _busy = true;
      _err = null;
      _resState = 0;
      _res = 'POST $url'
          '${_protocol == 'anthropic' ? '/messages' : '/chat/completions'}'
          ' · model=$model …';
    });
    try {
      final r = await ref.read(aiServiceProvider).verifyEndpoint(
            baseUrl: url,
            model: model,
            // 本地端点常不需 Key：占位串让请求真发出去，好拿端点自己的归因。
            apiKey: _key.text.trim().isEmpty ? 'probe' : _key.text.trim(),
            prompt: 'ping',
            protocol: _protocol,
          );
      if (!mounted) return;
      setState(() {
        _resState = 1;
        _res = '✓ ${r.latencyMs}ms · 端点可用\n模型回复：${r.content}';
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _resState = -1;
        _res = '${e.userMessage}\n${e.detail}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resState = -1;
        _res = '✕ 未预期错误：$e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Text(text,
            style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: Colors.grey)),
      );

  InputDecoration _inp([String? hint]) => InputDecoration(
      isDense: true,
      hintText: hint,
      border: const OutlineInputBorder());

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_isEdit ? '编辑服务商 · ${widget.provider!.name}' : '添加服务商',
              key: const ValueKey('ai-prov-form-title'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('名称'),
                  TextField(
                      key: const ValueKey('ai-prov-f-name'),
                      controller: _name,
                      style: const TextStyle(fontSize: 12.5),
                      decoration: _inp('自己看得懂就行，如「公司中转站」「家里 Ollama」')),
                  _label('Base URL（必填 · 按端点要求填完整前缀）'),
                  TextField(
                      key: const ValueKey('ai-prov-f-url'),
                      controller: _url,
                      style: const TextStyle(
                          fontSize: 12, fontFamily: 'monospace'),
                      decoration: _inp('https://relay.example.com/v1'),
                      onChanged: (_) => setState(() {})),
                  const SizedBox(height: 4),
                  const Text('请求会拼 /chat/completions（OpenAI 兼容）或 /messages（Anthropic）；'
                      '中转站要别的后缀（如 /v1/api）直接写进 Base URL 即可。',
                      style:
                          TextStyle(fontSize: 10, color: Colors.grey, height: 1.5)),
                  _label('模型名（必填）'),
                  TextField(
                      key: const ValueKey('ai-prov-f-model'),
                      controller: _model,
                      style: const TextStyle(
                          fontSize: 12, fontFamily: 'monospace'),
                      decoration: _inp('deepseek-chat / qwen2.5:7b')),
                  _label('协议'),
                  Row(
                    children: [
                      PillChip(
                          key: const ValueKey('ai-prov-proto-openai'),
                          label: 'OpenAI 兼容',
                          selected: _protocol == 'openai',
                          onTap: () => setState(() => _protocol = 'openai')),
                      const SizedBox(width: 8),
                      PillChip(
                          key: const ValueKey('ai-prov-proto-anthropic'),
                          label: 'Anthropic Messages',
                          selected: _protocol == 'anthropic',
                          onTap: () => setState(() => _protocol = 'anthropic')),
                    ],
                  ),
                  _label('API Key（该服务商单独保存）'),
                  TextField
                      (
                    key: const ValueKey('ai-prov-f-key'),
                    controller: _key,
                    obscureText: _keyMasked,
                    style: const TextStyle(
                        fontSize: 12, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                        isDense: true,
                        hintText:
                            _storedTail.isEmpty ? '未设置 · 填入即保存' : '••••',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          key: const ValueKey('ai-prov-f-eye'),
                          icon: Icon(
                              _keyMasked
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 18),
                          onPressed: () =>
                              setState(() => _keyMasked = !_keyMasked),
                        )),
                  ),
                  Text(
                      _storedTail.isEmpty
                          ? '该服务商还没有 Key · 填入后即刻存入系统加密区'
                          : '已存 Key（末 4 位 $_storedTail）· 覆盖即改，清空后保存＝删除该 Key',
                      key: const ValueKey('ai-prov-key-hint'),
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  if (_plainHttp)
                    Container(
                      key: const ValueKey('ai-prov-http-row'),
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFFF59E0B)
                                .withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                              child: Text(
                                  '地址是 http 明文：仅建议局域网/回环端点，公网请用 https',
                                  style: TextStyle(
                                      fontSize: 10.5, height: 1.4))),
                          Switch(
                            key: const ValueKey('ai-prov-http-ok'),
                            value: _httpOk,
                            onChanged: (v) => setState(() => _httpOk = v),
                          ),
                        ],
                      ),
                    ),
                  Container(
                    key: const ValueKey('ai-prov-res'),
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(10),
                    constraints: const BoxConstraints(minHeight: 40),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: Colors.grey.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      _res,
                      style: TextStyle(
                          fontSize: 10.5,
                          height: 1.5,
                          fontFamily: 'monospace',
                          color: _resState > 0
                              ? const Color(0xFF10B981)
                              : _resState < 0
                                  ? const Color(0xFFF43F5E)
                                  : Colors.grey),
                    ),
                  ),
                  if (_err != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(_err!,
                          key: const ValueKey('ai-prov-form-err'),
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFF43F5E))),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          key: const ValueKey('ai-prov-ping'),
                          onPressed: _busy ? null : _ping,
                          child: Text(_busy ? '测试中…' : '测试连接',
                              style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                      if (_isEdit && !widget.isCurrent) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          key: const ValueKey('ai-prov-form-del'),
                          onPressed: _busy ? null : _requestDelete,
                          child: const Text('删除',
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFFEF4444))),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const ValueKey('ai-prov-save'),
                      onPressed: _busy ? null : _save,
                      child: const Text('保存服务商'),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
