import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/ai_client.dart';
import '../../../core/ai/ai_config.dart';
import '../../../core/ai/ai_prompt_pack.dart';
import '../../../core/ai/ai_providers.dart';
import '../../../core/ai/token_stats.dart';
import '../../../core/logging/app_log.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';

/// AI 增强二级页（原型 p-sub-ai）：服务商 · Key 配置 · 总开关 · 能力矩阵 · 提示词管理。
/// 新页面按「UI 禁 emoji」规范用纯文字/线性图标（原型 emoji 位不直译）。

/// 协议展示名（服务商行与表单共用）。
String aiProtocolLabel(String protocol) =>
    protocol == 'anthropic' ? 'Anthropic Messages' : 'OpenAI 兼容';

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
  bool _keyMasked = true;

  /// 已填入 [_keyCtrl] 的服务商 id（切换当前端点后需重填）。
  String? _keyFilledFor;

  /// 各服务商是否**自己**存过 Key（未存者沿用旧全局 Key）。
  final Set<String> _ownKeyIds = {};
  bool _keyStatesLoadedFor = false;

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  /// 载入「当前端点」的 Key 到输入框（掩码展示）。
  Future<void> _loadKey(String providerId) async {
    if (_keyFilledFor == providerId) return;
    final k = await ref.read(aiKeyVaultProvider).read(providerId) ?? '';
    if (!mounted || k.isEmpty) return;
    _keyCtrl.text = k;
    _keyFilledFor = providerId;
    setState(() {});
  }

  /// 服务商列表的 Key 状态行（加密区只读探测，内存版测试注入即刻返回）。
  Future<void> _loadKeyStates() async {
    final vault = ref.read(aiKeyVaultProvider);
    final ids = <String>[];
    for (final p in ref.read(aiConfigProvider).providers) {
      if (await vault.hasOwnKey(p.id)) ids.add(p.id);
    }
    if (!mounted) return;
    setState(() {
      _ownKeyIds
        ..clear()
        ..addAll(ids);
      _keyStatesLoadedFor = true;
    });
  }

  Future<void> _saveKey() async {
    final pid = ref.read(aiConfigProvider).active.id;
    final k = _keyCtrl.text.trim();
    final vault = ref.read(aiKeyVaultProvider);
    if (k.isEmpty) {
      await vault.clear(providerId: pid);
      _keyFilledFor = pid;
      _refreshKeyStates();
      if (!mounted) return;
      AppToast.show(context, 'Key 为空：已清除当前端点存的 Key');
      return;
    }
    final ok = await vault.write(k, providerId: pid);
    _keyFilledFor = pid;
    _refreshKeyStates();
    if (!mounted) return;
    AppToast.show(context, ok ? 'Key 已存入系统加密区' : 'Key 写入失败：保险箱异常');
  }

  void _refreshKeyStates() {
    _keyStatesLoadedFor = false;
    _loadKeyStates();
  }

  /// 打开服务商添加/编辑弹层（V1.53.1：预置也只是种子，同样可改地址）。
  Future<void> _openProviderForm({AiProvider? provider}) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height -
            MediaQuery.of(context).padding.top -
            24,
      ),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => Padding(
        // 含输入框：viewInsets 必须取弹层自身 context，键盘才不盖住输入框。
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom),
        child: SafeArea(
            child: _AiProviderFormSheet(
                provider: provider,
                isCurrent: provider != null &&
                    provider.id == ref.read(aiConfigProvider).active.id)),
      ),
    );
    if (!mounted || result == null) return;
    if (result.startsWith('delete:')) {
      final id = result.substring('delete:'.length);
      final p = ref
          .read(aiConfigProvider)
          .providers
          .where((e) => e.id == id)
          .firstOrNull;
      if (p != null) await _deleteProvider(p);
      return;
    }
    _keyFilledFor = null; // 端点/Key 可能已变，强制重填
    _refreshKeyStates();
    AppToast.show(context, '已保存 · 端点即刻生效（业务模块无需任何改动）');
  }

  /// 删除服务商：两段式确认，当前端点拒删（防把唯一可用配置删没）。
  Future<void> _deleteProvider(AiProvider p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除', style: TextStyle(fontSize: 15)),
        content: Text('删除「${p.name}」？其独立 Key 会从加密区一并清除，'
            '已发出的 AI 记录不受影响。', style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            key: const ValueKey('ai-prov-del-confirm'),
            style:
                FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final done =
        await ref.read(aiConfigProvider.notifier).deleteProvider(p.id);
    if (!mounted) return;
    if (!done) {
      _keyFilledFor = null;
      setState(() {});
      AppToast.show(context, '当前端点不可删除：先选用其他服务商');
      return;
    }
    _keyFilledFor = null;
    _refreshKeyStates();
    AppToast.show(context, '已删除「${p.name}」（其 Key 一并从加密区清除）');
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(aiConfigProvider);
    ref.watch(aiKeyVaultProvider); // 触发首次载入
    final active = cfg.active;
    _loadKey(active.id);
    if (!_keyStatesLoadedFor) _loadKeyStates();
    return Scaffold(
      appBar: AppBar(title: const Text('AI 增强')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // —— 服务商管理（V1.53.1：预置=首次种子，可增可改可删可切换）——
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                        child: Text('服务商管理',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w800))),
                    TextButton(
                      key: const ValueKey('ai-prov-add'),
                      onPressed: () => _openProviderForm(),
                      child: const Text('+ 添加服务商',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                for (final p in cfg.providers)
                  _ProviderRow(
                    provider: p,
                    isCurrent: p.id == active.id,
                    keyState: _ownKeyIds.contains(p.id)
                        ? '已单独保存'
                        : (p.id == active.id && _keyCtrl.text.trim().isNotEmpty
                            ? '沿用旧全局 Key'
                            : '未填'),
                    onUse: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await ref
                          .read(aiConfigProvider.notifier)
                          .useProvider(p.id);
                      if (!mounted) return;
                      _keyFilledFor = null;
                      setState(() {});
                      messenger
                        ..hideCurrentSnackBar()
                        ..showSnackBar(SnackBar(
                            content: Text('已切换到「${p.name}」· 后续请求走该端点与其 Key'),
                            persist: false));
                    },
                    onEdit: () => _openProviderForm(provider: p),
                    onDelete: () => _deleteProvider(p),
                  ),
                const Text(
                    '预置只是默认值，不是白名单：官方、中转站/自建网关、局域网 Ollama 都能添加，'
                    'Base URL、模型名、协议都可改。请求只发往你填的地址，应用自身零埋点。',
                    style: TextStyle(fontSize: 10, color: Colors.grey, height: 1.5)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // —— Key 配置（原型：当前端点摘要 + 掩码 Key + 验证状态 + 重新验证钮）——
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Key 配置',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Container(
                  key: const ValueKey('ai-cur-endpoint'),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '当前端点：${active.name} · ${active.baseUrl} · ${active.model}'
                    ' · ${aiProtocolLabel(active.protocol)}',
                    style: const TextStyle(fontSize: 11, height: 1.5),
                  ),
                ),
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
                    Expanded(
                      child: TextButton(
                        key: const ValueKey('ai-prov-edit-current'),
                        onPressed: () => _openProviderForm(provider: active),
                        child: const Text('编辑当前服务商',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        key: const ValueKey('ai-prov-add-2'),
                        onPressed: () => _openProviderForm(),
                        child: const Text('+ 新服务商',
                            style: TextStyle(fontSize: 12)),
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

/// 服务商行（原型 `#aiProvList` 的单行）：名称/预置徽 · Base URL ·
/// 模型+协议+Key 状态 · 选用（非当前）/编辑/删（当前端点不给删）。
class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    required this.provider,
    required this.isCurrent,
    required this.keyState,
    required this.onUse,
    required this.onEdit,
    required this.onDelete,
  });

  final AiProvider provider;
  final bool isCurrent;
  final String keyState;
  final VoidCallback onUse;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = provider;
    return Container(
      key: ValueKey('ai-prov-row-${p.id}'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: isCurrent ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Row(
                  children: [
                    Flexible(
                        child: Text(p.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700))),
                    if (p.builtin) ...[
                      const SizedBox(width: 5),
                      const Text('预置',
                          style: TextStyle(fontSize: 9, color: Colors.grey)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 2),
              if (isCurrent)
                Text('● 当前',
                    key: ValueKey('ai-prov-cur-${p.id}'),
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF10B981)))
              else
                _MiniBtn('选用', 'ai-prov-use-${p.id}', onUse),
              _MiniBtn('编辑', 'ai-prov-edit-${p.id}', onEdit),
              if (!isCurrent)
                _MiniBtn('删', 'ai-prov-del-${p.id}', onDelete,
                    color: const Color(0xFFEF4444)),
            ],
          ),
          Text(p.baseUrl,
              key: ValueKey('ai-prov-url-${p.id}'),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 10.5, fontFamily: 'monospace', color: Colors.grey)),
          Row(
            children: [
              Flexible(
                  child: Text(
                      '${p.model} · ${aiProtocolLabel(p.protocol)} · Key $keyState',
                      key: ValueKey('ai-prov-meta-${p.id}'),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 9.5, color: Colors.grey))),
              if (p.isPlainHttp)
                Text('· http 明文（局域网）',
                    key: ValueKey('ai-prov-http-${p.id}'),
                    style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF59E0B))),
            ],
          ),
        ],
      ),
    );
  }
}

/// 行内小按钮（原型 `.mini-btn`）。
class _MiniBtn extends StatelessWidget {
  const _MiniBtn(this.label, this.testKey, this.onTap, {this.color});

  final String label;
  final String testKey;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => TextButton(
        key: ValueKey(testKey),
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label, style: const TextStyle(fontSize: 11)),
      );
}

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
