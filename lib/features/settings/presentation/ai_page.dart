import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/ai_client.dart';
import '../../../core/ai/ai_prompt_pack.dart';
import '../../../core/ai/ai_providers.dart';
import '../../../core/ai/token_stats.dart';
import '../../../core/logging/app_log.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';

/// AI 增强二级页（原型 p-sub-ai）：服务商 · Key 配置 · 总开关 · 能力矩阵 · 提示词管理。
/// 新页面按「UI 禁 emoji」规范用纯文字/线性图标（原型 emoji 位不直译）。

/// 预置服务商（原型 AI_PROVIDERS 同表；DeepSeek 默认模型按拍板用 deepseek-flash）。
const kAiProviders = <({String name, String url, String model, String protocol})>[
  (name: 'DeepSeek', url: 'https://api.deepseek.com/v1', model: 'deepseek-flash', protocol: 'openai'),
  (name: 'OpenAI', url: 'https://api.openai.com/v1', model: 'gpt-4o-mini', protocol: 'openai'),
  (name: 'Anthropic', url: 'https://api.anthropic.com/v1', model: 'claude-3-5-haiku-latest', protocol: 'anthropic'),
  (name: 'Moonshot Kimi', url: 'https://api.moonshot.cn/v1', model: 'moonshot-v1-8s', protocol: 'openai'),
  (name: '通义千问', url: 'https://dashscope.aliyuncs.com/compatible-mode/v1', model: 'qwen-turbo', protocol: 'openai'),
  (name: '智谱 GLM', url: 'https://open.bigmodel.cn/api/paas/v4', model: 'glm-4-flash', protocol: 'openai'),
  (name: 'Ollama（本地）', url: 'http://127.0.0.1:11434/v1', model: 'qwen2.5:7b', protocol: 'openai'),
];

/// 能力矩阵行（原型分组 · 一行可含多个能力点；V2 行灰置不可开）。
const kAiCapRows = <({String label, List<String> tasks, bool v2})>[
  (label: '待办：自然语言速记 + AI 判象限 + 拆子任务', tasks: ['todo.nl_parse', 'todo.quadrant', 'todo.subtask'], v2: false),
  (label: '日记：复盘生成 / 反思草稿', tasks: ['journal.reflect'], v2: false),
  (label: '阅读：目录 AI 补全 / 摘录感想', tasks: ['read.toc', 'read.quote_insight'], v2: false),
  (label: '收集箱：智能分流建议', tasks: ['inbox.triage'], v2: false),
  (label: '周报 AI 点评（只发聚合数据）', tasks: ['schedule.weekly_review'], v2: false),
  (label: '呵护：周期趋势解读（仅聚合统计）', tasks: ['care.cycle_insight'], v2: false),
  (label: '记账 / 物品智能归类（V2）', tasks: ['ledger.categorize'], v2: true),
];

class AiSettingsPage extends ConsumerStatefulWidget {
  const AiSettingsPage({super.key});

  @override
  ConsumerState<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends ConsumerState<AiSettingsPage> {
  final _keyCtrl = TextEditingController();
  bool _keyLoaded = false;
  bool _keyMasked = true;

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadKey() async {
    if (_keyLoaded) return;
    final k = await ref.read(aiKeyVaultProvider).read();
    if (k != null && k.isNotEmpty && mounted) {
      _keyCtrl.text = k;
      _keyLoaded = true;
      setState(() {});
    }
  }

  Future<void> _saveKey() async {
    final k = _keyCtrl.text.trim();
    if (k.isEmpty) {
      AppToast.show(context, 'Key 为空：留空保存将清除已存 Key');
      await ref.read(aiKeyVaultProvider).clear();
      return;
    }
    final ok = await ref.read(aiKeyVaultProvider).write(k);
    if (!mounted) return;
    AppToast.show(context, ok ? 'Key 已存入系统加密区' : 'Key 写入失败：保险箱异常');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final cfg = ref.watch(aiConfigProvider);
    ref.watch(aiKeyVaultProvider); // 触发首次载入
    _loadKey();
    final cur = cfg.baseUrl.replaceAll(RegExp(r'/+$'), '');
    return Scaffold(
      appBar: AppBar(title: const Text('AI 增强')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // —— 服务商管理（原型：预设列表 · 当前标记）——
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('服务商管理',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                for (final p in kAiProviders)
                  ListTile(
                    key: ValueKey('ai-prov-${p.name}'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(p.name,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        '${Uri.parse(p.url).host} · ${p.model}'
                        '${p.protocol == 'anthropic' ? '（Messages 协议）' : ''}',
                        style: const TextStyle(
                            fontSize: 10.5, fontFamily: 'monospace')),
                    trailing: cur == p.url
                        ? Text('● 当前',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: tokens.accent))
                        : const Icon(Icons.unfold_more, size: 16),
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await ref
                          .read(aiConfigProvider.notifier)
                          .setEndpoint(p.url, p.model, protocol: p.protocol);
                      messenger
                        ..hideCurrentSnackBar()
                        ..showSnackBar(SnackBar(content: Text('已切换 ${p.name} · 到验证工具确认连通')));
                    },
                  ),
                const Text('协议：OpenAI 兼容 Chat Completions / Anthropic Messages · '
                    '请求仅发往已配置端点，应用自身零埋点',
                    style: TextStyle(fontSize: 10, color: Colors.grey, height: 1.5)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // —— Key 配置（原型：密文 Key + 模型名 + 验证状态 + 重新验证钮）——
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Key 配置',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('ai-key-field'),
                  controller: _keyCtrl,
                  obscureText: _keyMasked,
                  style: const TextStyle(fontSize: 12.5),
                  decoration: InputDecoration(
                    hintText: 'API Key · sk-…',
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(_keyMasked ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                      onPressed: () => setState(() => _keyMasked = !_keyMasked),
                    ),
                  ),
                  onSubmitted: (_) => _saveKey(),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Expanded(
                        child: Text('模型名', style: TextStyle(fontSize: 12.5))),
                    SizedBox(
                      width: 190,
                      child: TextField(
                        key: const ValueKey('ai-model-field'),
                        controller: TextEditingController(text: cfg.model)
                          ..selection = TextSelection.fromPosition(
                              TextPosition(offset: cfg.model.length)),
                        style: const TextStyle(fontSize: 12.5),
                        decoration: const InputDecoration(
                            isDense: true, hintText: 'deepseek-flash'),
                        onSubmitted: (v) => ref
                            .read(aiConfigProvider.notifier)
                            .setEndpoint(cfg.baseUrl, v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('Key 存系统级加密区：不入备份明文、不落日志、不随同步导出。',
                    style: TextStyle(fontSize: 10, color: Colors.grey, height: 1.5)),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('验证状态', style: TextStyle(fontSize: 12.5)),
                  trailing: Text(
                    cfg.verifyAtMs == null
                        ? '未验证'
                        : (cfg.verifyOk
                            ? '✓ ${_fmtTime(cfg.verifyAtMs!)} 通过 · ${cfg.verifyLatencyMs ?? '?'}ms'
                            : '✕ ${_fmtTime(cfg.verifyAtMs!)} 失败')
                        ,
                    key: const ValueKey('ai-verify-status'),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: cfg.verifyAtMs == null
                            ? Colors.grey
                            : cfg.verifyOk
                                ? const Color(0xFF10B981)
                                : const Color(0xFFF43F5E)),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('ai-verify-btn'),
                    onPressed: () async {
                      final router = GoRouter.of(context);
                      await _saveKey();
                      router.push('/settings/ai/verify');
                    },
                    icon: const Icon(Icons.bolt_outlined, size: 18),
                    label: const Text('重新验证 / 测试新 Key'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // —— 总开关 + 能力矩阵（原型 p-sub-ai 第三卡）——
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                        child: Text('AI 总开关',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w800))),
                    Switch(
                      key: const ValueKey('ai-master-switch'),
                      value: cfg.master,
                      onChanged: (v) async {
                        final messenger = ScaffoldMessenger.of(context);
                        await ref.read(aiConfigProvider.notifier).setMaster(v);
                        messenger
                          ..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(
                              content: Text(v
                                  ? '总开关已开：各能力仍逐项授权'
                                  : '总开关已关：全应用零 AI 请求')));
                      },
                    ),
                  ],
                ),
                const Text('能力矩阵（逐项授权）',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey)),
                const SizedBox(height: 4),
                for (final row in kAiCapRows)
                  Row(
                    children: [
                      Expanded(
                          child: Text(row.label,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: row.v2 ? Colors.grey : null,
                                  fontWeight: FontWeight.w600))),
                      Switch(
                        key: ValueKey('ai-cap-${row.tasks.first}'),
                        value: row.tasks.any((t) => cfg.caps[t] == true),
                        onChanged: row.v2
                            ? null
                            : (v) async {
                                final repo = ref.read(aiConfigRepoProvider);
                                for (final t in row.tasks) {
                                  await repo.setCap(t, v);
                                }
                                ref.invalidate(aiConfigProvider);
                              },
                      ),
                    ],
                  ),
                const Text('隐私：每次调用前弹层展示完整发送内容可审阅；AI 结果带标识，'
                    '写入前需确认。',
                    style: TextStyle(fontSize: 10, color: Colors.grey, height: 1.5)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // —— Token 使用（真机反馈 2026-09-26：想看 token 消耗）——
          const _TokenUsageCard(),
          const SizedBox(height: 12),
          // —— 提示词管理入口（AI批新增 · 原型 p-sub-ai 第四卡）——
          _Card(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('提示词管理',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      const Text('按模块查看与覆盖 System / User 模板，保存即刻生效，'
                          '调整请求内容不需要改代码',
                          style: TextStyle(
                              fontSize: 10.5, color: Colors.grey, height: 1.5)),
                    ],
                  ),
                ),
                TextButton(
                  key: const ValueKey('ai-prompts-entry'),
                  onPressed: () => context.push('/settings/ai/prompts'),
                  child: const Text('按模块调整 ›'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Token 使用卡（真机反馈 2026-09-26：「增加一个 token 使用情况查看」）。
///
/// 口径：只记**真的发出去**的调用；取消/断连这类没拿到应答的计一次调用但不计
/// token（端点没回 usage，编不出来）；明细按「日 × 能力点」存 prefs，随整包备份
/// 换机带走，保留最近 [AiTokenStats.keepDays] 天。
class _TokenUsageCard extends ConsumerStatefulWidget {
  const _TokenUsageCard();

  @override
  ConsumerState<_TokenUsageCard> createState() => _TokenUsageCardState();
}

class _TokenUsageCardState extends ConsumerState<_TokenUsageCard> {
  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清理', style: TextStyle(fontSize: 15)),
        content: const Text('清空本机 AI token 用量明细？不影响后续调用与日志。',
            style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            key: const ValueKey('ai-token-clear-ok'),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AiTokenStats.clear(ref.read(sharedPreferencesProvider));
    if (!mounted) return;
    setState(() {});
    AppToast.show(context, '用量明细已清空');
  }

  Widget _cell(String label, Map<String, Map<String, int>> agg) {
    final t = AiTokenStats.total(agg);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
          const SizedBox(height: 2),
          Text('${t.inTok + t.outTok}',
              key: ValueKey('ai-token-$label'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          Text('入 ${t.inTok} · 出 ${t.outTok} · ${t.calls} 次',
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(sharedPreferencesProvider);
    final table = AiTokenStats.load(prefs);
    final now = DateTime.now();
    final todayKey = AiTokenStats.dayKey(now);
    final weekKeys = {
      for (var i = 0; i < 7; i++)
        AiTokenStats.dayKey(now.subtract(Duration(days: i)))
    };
    final today = AiTokenStats.aggregate([table[todayKey] ?? const {}]);
    final week = AiTokenStats.aggregate([
      for (final e in table.entries)
        if (weekKeys.contains(e.key)) e.value
    ]);
    final all = AiTokenStats.aggregate(table.values);
    final names = {
      // 行名带模块前缀：能力点名（如「智能归类」）脱离模块语境会看不出是谁的。
      for (final t in ref.watch(aiPromptPackProvider).tasks)
        t.id: (t.module.isEmpty ? '' : '${t.module} · ') + t.name
    };
    final rows = all.entries.toList()
      ..sort((a, b) => (b.value['out']! + b.value['in']!)
          .compareTo(a.value['out']! + a.value['in']!));
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                  child: Text('Token 使用',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
              TextButton(
                key: const ValueKey('ai-token-clear'),
                onPressed: all.isEmpty ? null : _clear,
                child: const Text('清理', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cell('今日', today),
              _cell('近 7 天', week),
              _cell('累计', all),
            ],
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('还没有发出的调用',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                children: [
                  for (final r in rows.take(8))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(names[r.key] ?? r.key,
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis),
                          ),
                          Text(
                            '${r.value['in']} / ${r.value['out']}'
                            ' · ${r.value['n']} 次'
                            '${(r.value['f'] ?? 0) > 0 ? ' · 失败 ${r.value['f']}' : ''}',
                            key: ValueKey('ai-token-row-${r.key}'),
                            style: const TextStyle(
                                fontSize: 10.5, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          const Text('入/出＝提示与应答 token；取消或断连只计次不计 token（应答未回就没有用量）。',
              style: TextStyle(fontSize: 10, color: Colors.grey, height: 1.5)),
        ],
      ),
    );
  }
}

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
    final key = await ref.read(aiKeyVaultProvider).read() ?? '';
    if (!mounted) return;
    _url.text = cfg.baseUrl;
    _model.text = cfg.model;
    _protocol = cfg.protocol;
    _key.text = key;
    setState(() {});
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
      // 验证通过：Key 落保险箱 + 端点回写配置 + 状态记档。
      await ref.read(aiKeyVaultProvider).write(_key.text.trim());
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
              for (final p in kAiProviders)
                ChoiceChip(
                  key: ValueKey('ai-verify-chip-${p.name}'),
                  label: Text(p.name, style: const TextStyle(fontSize: 11.5)),
                  selected: _url.text.trim().replaceAll(RegExp(r'/+$'), '') == p.url,
                  onSelected: (_) => setState(() {
                    _url.text = p.url;
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
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _result ?? '结果将显示在此：模型回复 / 延迟 / token 用量，'
                  '或精确错误原因（401 Key 无效 / 404 模型名 / 429 限流 / 超时）。',
              style: TextStyle(
                  fontSize: 11,
                  height: 1.6,
                  fontFamily: 'monospace',
                  color: _result == null
                      ? Colors.white54
                      : _ok
                          ? const Color(0xFF86EFAC)
                          : const Color(0xFFFB7185)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 提示词管理（原型 p-sub-aiPrompts）：模块分组列表 + 覆盖标记。
class AiPromptsPage extends ConsumerWidget {
  const AiPromptsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(aiPromptPackProvider).tasks;
    final cfg = ref.watch(aiConfigProvider);
    final groups = <String, List<AiPromptTask>>{};
    for (final t in tasks) {
      groups.putIfAbsent(t.module, () => []).add(t);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('提示词管理')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('默认模板来自内置资产；覆盖只对本机生效，「恢复默认」随时回退。',
              style: TextStyle(fontSize: 10.5, color: Colors.grey)),
          const SizedBox(height: 10),
          for (final g in groups.entries) ...[
            Text(g.key,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey)),
            const SizedBox(height: 6),
            Container(
              decoration: context.cardDecoration,
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < g.value.length; i++)
                    ListTile(
                      key: ValueKey('ai-prompt-row-${g.value[i].id}'),
                      dense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      title: Text(g.value[i].name,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                      subtitle: Text(g.value[i].id,
                          style:
                              const TextStyle(fontSize: 10.5, fontFamily: 'monospace')),
                      trailing: Text(
                        cfg.promptOverrides.containsKey(g.value[i].id)
                            ? '● 已覆盖 ›'
                            : '默认 ›',
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: cfg.promptOverrides.containsKey(g.value[i].id)
                                ? const Color(0xFFF59E0B)
                                : Colors.grey),
                      ),
                      onTap: () => context.push('/settings/ai/prompts/edit',
                          extra: g.value[i].id),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// 提示词编辑（原型 p-sub-aiPromptEdit）：System/User 两段 + 占位符说明 + 覆盖/恢复。
class AiPromptEditPage extends ConsumerStatefulWidget {
  const AiPromptEditPage({super.key, required this.taskId});

  final String taskId;

  @override
  ConsumerState<AiPromptEditPage> createState() => _AiPromptEditPageState();
}

class _AiPromptEditPageState extends ConsumerState<AiPromptEditPage> {
  late final TextEditingController _sys;
  late final TextEditingController _user;

  @override
  void initState() {
    super.initState();
    // 提示词包与配置均同步可得（main 组合根 override），无需泵帧填充。
    final t = ref.read(aiServiceProvider).effectiveTask(widget.taskId);
    _sys = TextEditingController(text: t.system);
    _user = TextEditingController(text: t.user);
  }

  @override
  void dispose() {
    _sys.dispose();
    _user.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final def = ref.read(aiPromptPackProvider).taskById(widget.taskId)!;
    final notifier = ref.read(aiConfigProvider.notifier);
    final sys = _sys.text;
    final user = _user.text;
    if (sys == def.system && user == def.user) {
      await notifier.clearPromptOverride(widget.taskId);
    } else {
      await notifier.setPromptOverride(
          widget.taskId, sys == def.system ? null : sys, user == def.user ? null : user);
    }
    if (!mounted) return;
    AppToast.show(context, '已保存 · 即刻生效，无需改代码');
    context.pop();
  }

  Future<void> _reset() async {
    final def = ref.read(aiPromptPackProvider).taskById(widget.taskId)!;
    _sys.text = def.system;
    _user.text = def.user;
    await ref.read(aiConfigProvider.notifier).clearPromptOverride(widget.taskId);
    if (!mounted) return;
    AppToast.show(context, '已恢复内置默认模板');
  }

  @override
  Widget build(BuildContext context) {
    final task = ref.read(aiPromptPackProvider).taskById(widget.taskId);
    if (task == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('编辑提示词')),
          body: const Center(child: Text('未注册的能力点')));
    }
    return Scaffold(
      appBar: AppBar(title: Text('${task.name} · 提示词')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(task.id,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.grey))),
              Text('${task.module} · 输出约定：${task.expect == AiExpect.json ? 'JSON 对象' : '纯文稿'}',
                  style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 8),
          Text('占位符：${task.placeholders.map((p) => '{{$p}}').join('  ')}'
              '（保留原样即可注入当次数据）',
              style: const TextStyle(fontSize: 10.5, color: Colors.grey, height: 1.5)),
          const SizedBox(height: 12),
          const Text('System 设定',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          TextField(
            key: const ValueKey('ai-prompt-sys'),
            controller: _sys,
            maxLines: 5,
            style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', height: 1.5),
            decoration: InputDecoration(
                isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
          ),
          const SizedBox(height: 12),
          const Text('User 模板',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          TextField(
            key: const ValueKey('ai-prompt-user'),
            controller: _user,
            maxLines: 12,
            style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', height: 1.5),
            decoration: InputDecoration(
                isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('ai-prompt-reset'),
                  onPressed: _reset,
                  child: const Text('恢复默认'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('ai-prompt-save'),
                  onPressed: _save,
                  child: const Text('保存覆盖'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('保存后该能力点即刻使用此模板发起请求；与默认一致的内容自动清除覆盖。',
              style: TextStyle(fontSize: 10, color: Colors.grey, height: 1.5)),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration,
      child: child,
    );
  }
}

String _fmtTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
