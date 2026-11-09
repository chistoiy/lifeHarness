part of 'ai_page.dart';

// 治理G7d⑤：AI 使用记录卡群自 ai_page 整块外提（行为零改动）。
// _AiUsageEntryCard(State) 按模块分组行 + _TokenUsageCard(State) 三日/七日/三十日 token 台账。

/// AI 使用记录入口卡（V1.53 · 原型 p-sub-ai 的「AI 使用记录」卡）：
/// 四个实算数字（今日次数 / 今日 tokens / 近 7 天次数 / 累计条数）+ 全屏页入口。
/// AI 使用记录入口卡（V1.53 · 原型 p-sub-ai 第四卡）：四个实数摘要 + 全屏页入口。
class _AiUsageEntryCard extends ConsumerStatefulWidget {
  const _AiUsageEntryCard();

  @override
  ConsumerState<_AiUsageEntryCard> createState() => _AiUsageEntryCardState();
}

class _AiUsageEntryCardState extends ConsumerState<_AiUsageEntryCard> {
  int _today = 0, _todayTok = 0, _week = 0, _all = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final store = ref.read(aiCallStoreProvider);
    if (store == null) return;
    final today = await store.sumOf(const AiCallFilter(sinceDays: 0));
    final week = await store.sumOf(const AiCallFilter(sinceDays: 7));
    final all = await store.sumOf(const AiCallFilter());
    if (!mounted) return;
    setState(() {
      _today = today.n;
      _todayTok = today.tokens;
      _week = week.n;
      _all = all.n;
    });
  }

  Widget _cell(String label, String value, String key) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
            const SizedBox(height: 2),
            Text(value,
                key: ValueKey(key),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                  child: Text('AI 使用记录',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
              TextButton(
                key: const ValueKey('ai-usage-entry'),
                onPressed: () async {
                  await context.push('/settings/ai/usage');
                  if (mounted) _load();
                },
                child: const Text('全屏查看 ›'),
              ),
            ],
          ),
          Row(
            children: [
              _cell('今日调用', '$_today', 'ai-usage-k1'),
              _cell('今日 tokens', '$_todayTok', 'ai-usage-k2'),
              _cell('近 7 天调用', '$_week', 'ai-usage-k3'),
              _cell('累计', '$_all', 'ai-usage-k4'),
            ],
          ),
          const SizedBox(height: 6),
          const Text('每次调用留一行（含门控拒绝与取消）：能力点 · 状态 · token · 耗时 · 发送与返回正文。'
              '正文可在记录设置里整体停记或单独清除，Key 永不入库。',
              style: TextStyle(fontSize: 10, color: Colors.grey, height: 1.5)),
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
