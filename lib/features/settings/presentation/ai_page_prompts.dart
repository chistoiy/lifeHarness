part of 'ai_page.dart';

// 治理G7d⑤：提示词管理两页自 ai_page 整块外提（行为零改动）。
// AiPromptsPage 按模块分组列表 + AiPromptEditPage(State) 八字段编辑与覆盖保存。

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
