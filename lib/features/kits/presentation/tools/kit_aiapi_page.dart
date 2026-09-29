// 工具屏 · AI API 验证（原型 `TOOLS.aiapi` / `ai*` 同源 · 批3）。
//
// 全站**唯一**会真实出站的工具屏：请求参数（服务商 / Base URL / Key / 模型 /
// 提示词 / 协议）当场摊开，发送经 `core/ai/ai_verify_channel.dart` 走
// `AiService.verifyEndpoint`——留痕（运行日志 + AI 使用记录）与精确归因都在那里，
// 本屏只渲染结果。Key 只当次使用：不进落库结构、不进结果文案、不进记录行。
// 「模拟演示」零出站并显式标注不校验 Key。表单落 `kit_tool_data.tool='aiapi'`。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/ai/ai_call_store.dart';
import '../../../../core/ai/ai_config.dart';
import '../../../../core/ai/ai_verify_channel.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/kit_aiapi.dart';
import '../../domain/kit_models.dart';
import '../kit_providers.dart';
import 'kit_tools_kit.dart';

/// 生产通道缝（widget 测试替换 [run] 即可，绝不在测试里发真请求）。
class KitAiapi {
  KitAiapi._();

  static Future<AiVerifyResult> Function(
    WidgetRef ref,
    String baseUrl,
    String model,
    String apiKey,
    String prompt,
    String protocol,
  )
  run = (ref, baseUrl, model, apiKey, prompt, protocol) => aiVerifyCall(
    ref,
    baseUrl: baseUrl,
    model: model,
    apiKey: apiKey,
    prompt: prompt,
    protocol: protocol,
  );

  /// 保险箱里是否已有该端点的 Key（只回布尔，Key 不出通道）。
  static Future<bool> Function(WidgetRef ref, String providerId) hasKey =
      aiVerifyHasKey;

  /// 模拟演示（零出站）。屏侧不自己编结果，统一走 core 通道。
  static Future<AiVerifyResult> Function(String prompt) mock = (prompt) =>
      aiVerifyMock(prompt: prompt);

  static Future<List<AiCallRecord>> Function(WidgetRef ref) history = (ref) =>
      aiVerifyHistory(ref);

  static Future<int> Function(WidgetRef ref) clearHistory =
      aiVerifyClearHistory;

  /// 可选端点（设置里已配置的那几台）。
  static List<AiProvider> Function(WidgetRef ref) presets = aiVerifyPresets;
}

/// AI API 验证屏主体。
class KitAiapiBody extends ConsumerStatefulWidget {
  const KitAiapiBody({super.key});

  @override
  ConsumerState<KitAiapiBody> createState() => _KitAiapiBodyState();
}

class _KitAiapiBodyState extends ConsumerState<KitAiapiBody> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _key = TextEditingController();
  final TextEditingController _model = TextEditingController();
  final TextEditingController _prompt = TextEditingController();

  String _provId = '';
  String _proto = kKitAiapiProtoOpenai;
  bool _loaded = false;
  bool _busy = false;
  String _reqLine = '';
  List<String> _lines = const [];
  List<AiCallRecord> _hist = const [];

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _model.dispose();
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final st = KitAiapiState.decode(
      await ref.read(kitRepositoryProvider).toolData(kitToolKeyAiapi),
    );
    final presets = KitAiapi.presets(ref);
    final hit = presets.where((p) => p.id == st.providerId).toList();
    // 库里没端点时跟随当前激活服务商，避免一进来就是空地址。
    final base = hit.isNotEmpty
        ? hit.first
        : (presets.isEmpty ? null : presets.first);
    if (!mounted) return;
    setState(() {
      _provId = base?.id ?? st.providerId;
      _url.text = st.baseUrl.isEmpty ? (base?.baseUrl ?? '') : st.baseUrl;
      _model.text = st.model.isEmpty ? (base?.model ?? '') : st.model;
      _prompt.text = st.prompt;
      // 库里选的不是这台端点时，协议跟随端点自身配置（协议是端点属性不是用户偏好）。
      _proto = base == null || st.providerId == base.id
          ? st.protocol
          : base.protocol;
      _loaded = true;
    });
    await _reloadHist();
  }

  Future<void> _reloadHist() async {
    final h = await KitAiapi.history(ref);
    if (!mounted) return;
    setState(() => _hist = h);
  }

  Future<void> _persist() => ref
      .read(kitRepositoryProvider)
      .setToolData(
        kitToolKeyAiapi,
        kitAiapiEncode(
          providerId: _provId,
          baseUrl: _url.text.trim(),
          model: _model.text.trim(),
          prompt: _prompt.text.trim(),
          protocol: _proto,
        ),
      );

  void _pickProvider(String id) {
    final p = KitAiapi.presets(ref).where((e) => e.id == id).toList();
    if (p.isEmpty) {
      setState(() => _provId = '');
      return;
    }
    setState(() {
      _provId = id;
      _url.text = p.first.baseUrl;
      _model.text = p.first.model;
      _proto = p.first.protocol;
    });
    _persist();
  }

  Future<void> _run({required bool mock}) async {
    if (_busy) return;
    final prompt = _prompt.text.trim().isEmpty
        ? kKitAiapiPromptDefault
        : _prompt.text.trim();
    if (mock) {
      setState(() {
        _busy = true;
        _reqLine = '模拟请求中…（零出站）';
        _lines = const [];
      });
      final r = await KitAiapi.mock(prompt);
      if (!mounted) return;
      _show(r);
      return;
    }
    final storedKey = await KitAiapi.hasKey(ref, _provId);
    if (!mounted) return;
    final hasKey = _key.text.trim().isNotEmpty || storedKey;
    final bad = kitAiapiCheck(baseUrl: _url.text, hasKey: hasKey);
    if (bad != null) {
      setState(() {
        _reqLine = '';
        _lines = kitAiapiResultLines(
          head: kitAiapiHead(ok: false, ms: 0),
          error: '✖ $bad',
          verdict: kitAiapiVerdict(ok: false, mock: false),
        );
      });
      AppToast.show(context, bad);
      return;
    }
    await _persist();
    final url = aiVerifyEndpointUrl(
      baseUrl: _url.text.trim(),
      protocol: _proto,
    );
    setState(() {
      _busy = true;
      _reqLine = kitAiapiRequestLine(
        url: url,
        protocol: _proto,
        model: _model.text,
      );
      _lines = const [];
    });
    // 空 Key 输入 = 用保险箱里那台端点的 Key（屏侧不读明文，交通道内部取用）。
    final r = await KitAiapi.run(
      ref,
      _url.text.trim(),
      _model.text.trim(),
      _key.text.trim(),
      prompt,
      _proto,
    );
    if (!mounted) return;
    _show(r, endpoint: url);
  }

  void _show(AiVerifyResult r, {String endpoint = ''}) {
    setState(() {
      _busy = false;
      _reqLine = endpoint.isEmpty ? '' : 'POST $endpoint';
      _lines = kitAiapiResultLines(
        head: kitAiapiHead(ok: r.ok, ms: r.ms, mock: r.mock),
        reply: r.reply,
        usage: kitAiapiUsage(
          inTok: r.inTok,
          outTok: r.outTok,
          ok: r.ok,
          mock: r.mock,
        ),
        verdict: kitAiapiVerdict(ok: r.ok, mock: r.mock),
        error: r.error,
        detail: r.detail,
      );
    });
    _reloadHist();
  }

  Future<void> _clearHist() async {
    final n = await KitAiapi.clearHistory(ref);
    if (!mounted) return;
    AppToast.show(context, '验证记录已清空 $n 条（Key 存于系统保险箱，不随记录导出）');
    await _reloadHist();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final presets = KitAiapi.presets(ref);
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        kitToolNote(
          '供「设置 → AI 增强」使用：验证服务商 / Key / 模型是否可用。'
          '默认 OpenAI 兼容 Chat Completions 协议，请求仅发往下方填写的地址。',
          key: const ValueKey('kit-aiapi-intro'),
        ),
        const SizedBox(height: 8),
        DropdownButtonHideUnderline(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border.all(color: tokens.cardBorder),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButton<String>(
              key: const ValueKey('kit-aiapi-provider'),
              isExpanded: true,
              value: presets.any((p) => p.id == _provId) ? _provId : null,
              hint: const Text('自定义端点', style: TextStyle(fontSize: 12)),
              items: [
                for (final p in presets)
                  DropdownMenuItem(
                    value: p.id,
                    child: Text(
                      '${p.name} · ${p.model}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) _pickProvider(v);
              },
            ),
          ),
        ),
        _field(
          'kit-aiapi-url',
          _url,
          'Base URL，如 https://xxx.com/v1',
          onChanged: (_) => _persist(),
        ),
        Row(
          children: [
            Expanded(
              child: _field(
                'kit-aiapi-key',
                _key,
                'API Key · sk-…（只当次使用）',
                obscure: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _field(
                'kit-aiapi-model',
                _model,
                '模型名',
                onChanged: (_) => _persist(),
              ),
            ),
          ],
        ),
        Row(
          children: [
            KitToolChip(
              keyName: 'kit-aiapi-proto-openai',
              label: 'OpenAI 兼容',
              on: _proto == kKitAiapiProtoOpenai,
              onTap: () {
                setState(() => _proto = kKitAiapiProtoOpenai);
                _persist();
              },
            ),
            const SizedBox(width: 6),
            KitToolChip(
              keyName: 'kit-aiapi-proto-anthropic',
              label: 'Anthropic Messages',
              on: _proto == kKitAiapiProtoAnthropic,
              onTap: () {
                setState(() => _proto = kKitAiapiProtoAnthropic);
                _persist();
              },
            ),
          ],
        ),
        _field(
          'kit-aiapi-prompt',
          _prompt,
          '验证提示词',
          maxLines: 2,
          onChanged: (_) => _persist(),
        ),
        Row(
          children: [
            kitToolBtn(
              context,
              _busy ? '验证中…' : '发送真实验证请求',
              _busy ? null : () => _run(mock: false),
              keyName: 'kit-aiapi-go',
            ),
            kitToolBtn(
              context,
              '模拟演示',
              _busy ? null : () => _run(mock: true),
              keyName: 'kit-aiapi-mock',
              small: true,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            key: const ValueKey('kit-aiapi-res'),
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 74),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_reqLine.isNotEmpty)
                  Text(
                    _reqLine,
                    key: const ValueKey('kit-aiapi-req'),
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Color(0xFF94A3B8),
                      height: 1.6,
                    ),
                  ),
                if (_lines.isEmpty && _reqLine.isEmpty)
                  const Text(
                    '结果将显示在此：模型回复 / 延迟 / token 用量，或精确错误原因'
                    '（401 Key 无效 / 429 限流 / 404 模型名 / 网络不可达）。',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Color(0x80E2E8F0),
                      height: 1.6,
                    ),
                  ),
                for (var i = 0; i < _lines.length; i++)
                  Text(
                    _lines[i],
                    key: ValueKey('kit-aiapi-line-$i'),
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      height: 1.6,
                      color: _lineColor(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
        kitToolNote(
          '协议双适配：OpenAI 兼容与 Anthropic Messages（x-api-key + anthropic-version）。'
          '端点、模型与协议按本机配置实发；验证通过后设置页 AI 能力矩阵方可逐项开启。',
          key: const ValueKey('kit-aiapi-proto-note'),
        ),
        const SizedBox(height: 10),
        kitToolSection(
          '验证记录 · 本机',
          trailing: [
            kitToolBtn(
              context,
              '清空',
              _hist.isEmpty ? null : _clearHist,
              keyName: 'kit-aiapi-hist-clear',
              small: true,
            ),
          ],
        ),
        if (_hist.isEmpty)
          kitToolNote(
            _loaded ? '尚无验证记录 · 验证成功才会留档' : '正在读本机记录…',
            key: const ValueKey('kit-aiapi-hist-empty'),
          )
        else
          for (var i = 0; i < _hist.length; i++)
            Text(
              kitAiapiHistLine(
                provider: _hist[i].module,
                model: _hist[i].name,
                ok: _hist[i].status == AiCallStore.statusOk,
                ms: _hist[i].ms,
                err: _hist[i].err,
                ts: _hist[i].ts,
                now: now,
              ),
              key: ValueKey('kit-aiapi-hist-$i'),
              style: const TextStyle(
                fontSize: 10.5,
                color: Colors.grey,
                height: 1.7,
              ),
            ),
        kitToolBtn(
          context,
          '前往 AI 增强设置 ›',
          () {
            context.push('/settings/ai');
            AppToast.show(context, 'AI 增强设置：总开关 / 能力矩阵逐项授权 / 提示词管理');
          },
          keyName: 'kit-aiapi-setting',
          small: true,
        ),
      ],
    );
  }

  Color _lineColor(int i) {
    if (_lines.isEmpty) return const Color(0xFFE2E8F0);
    final t = _lines[i];
    if (t.startsWith('✔')) return const Color(0xFF86EFAC);
    if (t.startsWith('✖')) return const Color(0xFFFB7185);
    if (t.startsWith('usage') || t.startsWith('POST')) {
      return const Color(0xFF94A3B8);
    }
    return const Color(0xFFE2E8F0);
  }

  Widget _field(
    String keyName,
    TextEditingController c,
    String hint, {
    bool obscure = false,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: TextField(
      key: ValueKey(keyName),
      controller: c,
      obscureText: obscure,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 12),
      onChanged: onChanged,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}
