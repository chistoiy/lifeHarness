import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_review.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/linkage/linkage_events.dart';
import '../../../shared/linkage/stats_providers.dart';
import '../domain/inbox_item.dart';
import 'inbox_providers.dart';

/// 模块5 收集箱（原型 p-inbox）：秒记入口 + 未整理列表 + 10 秒四向分流（L6）。
/// →待办 / →日记 / →笔记 / →摘录（选书落 book_quotes · origin=收集箱）全部真实落库；
/// AI 一键分流（批4-B）：对最前 ≤3 条逐条 inbox.triage → 结果确认 → 复用既有转化路径。
class InboxPage extends ConsumerStatefulWidget {
  const InboxPage({super.key});

  @override
  ConsumerState<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends ConsumerState<InboxPage> {
  final _input = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // 仪表盘 FAB「⚡ 记一条想法」跨页直达并聚焦输入框（守 R1）。
    ref.read(eventBusProvider).on<QuickAddEvent>().listen((e) {
      if (!mounted || e.target != 'inbox') return;
      _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add() {
    final v = _input.text.trim();
    if (v.isEmpty) {
      _toast('先写点什么吧');
      return;
    }
    ref.read(inboxDaoProvider).insert(InboxItem(rawText: v, createdAt: DateTime.now()));
    _input.clear();
    ref.invalidate(inboxItemsProvider);
    _toast('⚡ 已秒记入收集箱');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(milliseconds: 1600)));
  }

  Future<void> _triage(InboxItem item, String target, {String? text}) async {
    final dao = ref.read(inboxDaoProvider);
    // 转化正文：AI 分流建议可带清洗后的 draft；手动/空白回落原文。
    final src = (text != null && text.trim().isNotEmpty) ? text.trim() : item.rawText;
    switch (target) {
      case 'todo':
        final t = await ref.read(todoRepositoryProvider).add(
            Todo(title: src, quadrant: Quadrant.q2, tag: '收集箱'));
        await dao.route(item.id!, 'todo', t.id);
        ref.invalidate(todosProvider);
        _toast('✅ 已转为待办（重要不紧急）· 可在四象限改判');
      case 'journal':
        final jrepo = ref.read(journalRepositoryProvider);
        final now = DateTime.now();
        final today = await jrepo.byDay(now);
        final merged = (today == null || today.content.isEmpty)
            ? '📥 $src'
            : '${today.content}\n📥 $src';
        final saved = await jrepo.save(JournalEntry(
            day: now,
            content: merged,
            createdAt: today?.createdAt ?? now,
            updatedAt: now));
        await dao.route(item.id!, 'journal', saved.id);
        ref.invalidate(journalsProvider);
        _toast('📔 已插入今晚日记草稿');
      case 'note':
        final id = await ref.read(noteDaoProvider).insert(Note(
            title: src.length > 20 ? '${src.substring(0, 20)}…' : src,
            content: src,
            folder: '收集箱',
            createdAt: now(),
            updatedAt: now()));
        await dao.route(item.id!, 'note', id);
        _toast('📝 已存为笔记（编辑器 M1 开放）');
      case 'excerpt':
        final rrepo = ref.read(readRepositoryProvider);
        final books = (await rrepo.allBooks()).where((b) => !b.isDeleted).toList()
          ..sort((a, b) =>
              (b.lastReadAt ?? 0).compareTo(a.lastReadAt ?? 0));
        if (books.isEmpty) {
          _toast('书架还没有书 · 先去阅读书架添加一本书');
          return;
        }
        if (!mounted) return;
        final picked = await showModalBottomSheet<String>(
          context: context,
          builder: (sheetCtx) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final b in books)
                  ListTile(
                    key: ValueKey('ibk-${b.id}'),
                    title: Text('《${b.title}》 · ${b.state}',
                        style: const TextStyle(fontSize: 13)),
                    onTap: () => Navigator.of(sheetCtx).pop(b.id),
                  ),
              ],
            ),
          ),
        );
        if (picked == null) return;
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final qid = await rrepo.addQuote(BookQuote(
          bookId: picked,
          kind: BookQuote.kKindThought,
          thought: src,
          origin: '收集箱',
          createdAt: nowMs,
          updatedAt: nowMs,
        ));
        if (qid == null) {
          _toast('这条摘录已存在 · 未重复入账');
          return;
        }
        await dao.route(item.id!, 'quote', qid);
        ref.read(readTickProvider.notifier).state++;
        // excerpt 分支在 switch 内提前 return——这里必须自行 invalidate，否则分流后未整理列表不刷新。
        ref.invalidate(inboxItemsProvider);
        _toast('已存为阅读摘录（联动 L6）');
        return;
    }
    ref.invalidate(inboxItemsProvider);
  }

  /// AI 一键分流（批4-B）：对列表最前 ≤3 条逐条走 inbox.triage。
  /// 每条 = 审阅弹层（aiRunWithReview）→ 结果卡（target/reason/draft）→ 采纳后
  /// 复用既有 [_triage] 路径落库；任一环节取消/放弃即中止整轮。
  bool _aiTriageBusy = false;

  Future<void> _aiTriageAll() async {
    if (_aiTriageBusy) return;
    final items =
        ref.read(inboxItemsProvider).valueOrNull ?? const <InboxItem>[];
    if (items.isEmpty) {
      _toast('收集箱没有待分流的条目');
      return;
    }
    _aiTriageBusy = true;
    try {
      for (final item in items.take(3)) {
        if (!mounted) return;
        final res = await aiRunWithReview(context, ref,
            taskId: 'inbox.triage', vars: {'content': item.rawText});
        if (res == null) return; // 审阅取消或调用失败（已 toast）：中止整轮
        final j = res.json;
        final target = '${j?['target'] ?? ''}';
        final action = _aiTriageAction(target);
        if (action == null) {
          _toast('AI 返回去向不在四向之内 · 已跳过该条');
          continue;
        }
        if (!mounted) return;
        final adopt = await _showTriageSuggestion(
            item, target, '${j?['reason'] ?? ''}', '${j?['draft'] ?? ''}');
        if (adopt != true) return; // 用户放弃建议：中止整轮
        await _triage(item, action, text: '${j?['draft'] ?? ''}');
      }
    } finally {
      _aiTriageBusy = false;
    }
  }

  /// AI target → 既有转化动作口径（quote 走「→摘录」链，落库仍打标 quote）。
  static String? _aiTriageAction(String target) => switch (target) {
        'todo' => 'todo',
        'journal' => 'journal',
        'note' => 'note',
        'quote' => 'excerpt',
        _ => null,
      };

  static String _aiTriageLabel(String target) => switch (target) {
        'todo' => '待办',
        'journal' => '日记',
        'note' => '笔记',
        'quote' => '摘录',
        _ => target,
      };

  Future<bool?> _showTriageSuggestion(
      InboxItem item, String target, String reason, String draft) {
    final scheme = Theme.of(context).colorScheme;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI 分流建议', style: TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('「${item.rawText}」',
                  style: const TextStyle(fontSize: 12.5, height: 1.6)),
              const SizedBox(height: 8),
              Text('去向：${_aiTriageLabel(target)}',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800)),
              if (reason.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('理由：$reason',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
              if (draft.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('建议正文：${draft.trim()}',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
              const SizedBox(height: 6),
              const Text('AI 生成 · 采纳后写入前会再次经该条既有转化路径',
                  style: TextStyle(fontSize: 10.5, color: Colors.amber)),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('放弃')),
          FilledButton(
            key: const ValueKey('ai-triage-adopt'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('采纳并分流'),
          ),
        ],
      ),
    );
  }

  static DateTime now() => DateTime.now();

  Future<void> _dismiss(InboxItem item) async {
    await ref.read(inboxDaoProvider).remove(item.id!);
    ref.invalidate(inboxItemsProvider);
    _toast('🗑 已删除');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final items = ref.watch(inboxItemsProvider).valueOrNull ?? const <InboxItem>[];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('收集箱'),
            Text('灵感与碎片的入口',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.normal,
                    color: scheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search),
            onPressed: () => _toast('全局搜索 · 即将开放'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // 秒记卡（原型：grad 描边 p-0.5 + 内白卡）
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
                gradient: tokens.gradient,
                borderRadius: BorderRadius.circular(18)),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
              decoration: BoxDecoration(
                  color: tokens.card,
                  borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _input,
                    focusNode: _focus,
                    minLines: 2,
                    maxLines: 4,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _add(),
                    style: const TextStyle(fontSize: 14, height: 1.6),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      hintText: '脑中任何念头，扔进来…',
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text('📷 附件 · @ 提及 · （通知栏/桌面可快捷直达）',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 10, color: scheme.onSurfaceVariant)),
                      ),
                      GestureDetector(
                        key: const ValueKey('inbox-add'),
                        onTap: _add,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                              gradient: tokens.gradient,
                              borderRadius: BorderRadius.circular(10)),
                          child: const Text('存入',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('未整理 · ${items.length}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton(
                key: const ValueKey('ai-triage'),
                onPressed: _aiTriageAll,
                child: const Text('AI 一键分流',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              ),
              TextButton(
                onPressed: () => _toast('批量整理 · 规划 V0.5'),
                child: const Text('批量整理',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text('🎉 收集箱已清空，保持住！',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ),
            )
          else
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _inboxCard(context, item),
              ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: tokens.card,
              borderRadius: BorderRadius.circular(tokens.cardRadius),
              border: Border.all(color: tokens.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('🗓 整理节律',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurfaceVariant)),
                const SizedBox(height: 6),
                Text(
                    '每天 21:00 提醒清空收集箱 · 每条 10 秒内分流为：\n待办 / 日记片段 / 笔记 / 阅读摘录（联动 L6）',
                    style: TextStyle(
                        fontSize: 11,
                        height: 1.7,
                        color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _inboxCard(BuildContext context, InboxItem item) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey('inbox-${item.id}'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        border: Border.all(color: tokens.cardBorder),
        boxShadow: tokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.rawText,
              style: const TextStyle(fontSize: 13.5, height: 1.6)),
          const SizedBox(height: 2),
          Text(item.ageLabel(),
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          Wrap(
            spacing: 2,
            children: [
              _tri('→待办', tokens.accent, () => _triage(item, 'todo')),
              _tri('→日记', const Color(0xFF10B981),
                  () => _triage(item, 'journal')),
              _tri('→笔记', const Color(0xFFF59E0B),
                  () => _triage(item, 'note')),
              _tri('→摘录', const Color(0xFF0EA5E9),
                  () => _triage(item, 'excerpt')),
              _tri('✕', const Color(0xFFF43F5E), () => _dismiss(item)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tri(String label, Color color, VoidCallback onTap) {
    return TextButton(
      key: ValueKey('tri-$label'),
      onPressed: onTap,
      style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 34)),
      child: Text(label,
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
    );
  }
}
