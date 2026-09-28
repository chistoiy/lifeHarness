import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/ai_call_store.dart';
import '../../../core/ai/ai_client.dart';
import '../../../core/ai/ai_config.dart';
import '../../../core/ai/ai_prompt_pack.dart';
import '../../../core/ai/ai_providers.dart';
import '../../../core/ai/token_stats.dart';
import '../../../core/logging/app_log.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';

part 'ai_page_usage.dart';
part 'ai_page_verify.dart';
part 'ai_page_prompts.dart';
part 'ai_page_widgets.dart';
part 'ai_page_form.dart';

/// AI 增强二级页（原型 p-sub-ai）：服务商 · Key 配置 · 总开关 · 能力矩阵 · 提示词管理。
/// 新页面按「UI 禁 emoji」规范用纯文字/线性图标（原型 emoji 位不直译）。
///
/// 治理G7d⑤：本库按类群整块外提为 part（行为零改动）——主文件留 AI 增强主页
/// （AiSettingsPage/State + 能力矩阵 kAiCapRows + 协议名共用函数），其余群：
/// ai_page_usage（使用记录与 token 台账）· ai_page_verify（连通性验证页）·
/// ai_page_prompts（提示词管理两页）· ai_page_form（服务商表单弹层）·
/// ai_page_widgets（服务商行/小按钮/卡片壳等公共小件）。
/// 注意：test/architecture_test.dart 的 R7/R8 守护按「本目录 ai_ 前缀族」豁免与解析，
/// kAiCapRows 必须留在本文件（R8 现场解析锚）。

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
          // —— AI 使用记录入口（V1.53 · 原型 p-aiUsage 的入口卡）——
          const _AiUsageEntryCard(),
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
