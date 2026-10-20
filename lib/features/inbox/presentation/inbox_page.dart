import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_review.dart';
import '../../../core/database/app_database.dart';
import '../../../core/logging/app_log.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/linkage/linkage_events.dart';
import '../../../shared/linkage/stats_providers.dart';
// UIUX批（2026-10-12）：搜索钮接全局搜索半屏（守 R1：经 shared/linkage 出口）。
import '../../../shared/linkage/search_mounts.dart';
import '../../mindmap/data/mindmap_dao.dart';
import '../domain/inbox_item.dart';
import 'inbox_providers.dart';

/// 导图 DAO（第五向「→导图」用；导图模块自身走画布页注入，这边只在分流时取一次）。
final mindmapDaoProvider =
    Provider<MindmapDao>((ref) => MindmapDao(AppDatabase.instance.db));

/// 模块5 收集箱（原型 p-inbox）：秒记入口 + 未整理列表 + 10 秒四向分流（L6）。
/// →待办 / →日记 / →笔记 / →摘录（选书落 book_quotes · origin=收集箱）全部真实落库；
/// AI 一键分流（批4-B）：对最前 ≤3 条逐条 inbox.triage → 结果确认 → 复用既有转化路径。
/// 第五向 →导图（批P2）：条目成为目标图根节点下第一层，补齐导图侧拉取的另一半。
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

  /// 日志用摘要：只取前 16 字，避免整段原文进环形缓冲。
  static String _brief(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').length > 16
          ? '${s.replaceAll(RegExp(r'\s+'), ' ').substring(0, 16)}…'
          : s.replaceAll(RegExp(r'\s+'), ' ');

  /// 第五向 · 转导图节点（批P2 / 工单 §5 第 9 条）。
  ///
  /// 口径（原型 S10 已过门）：选目标图 → 条目文本成为**该图根节点下第一层**，
  /// 原条目 `routed_to='mindmap'` 留在收集箱（与另四向同款：分流只打标、不删除）。
  ///
  /// 「根节点下第一层」的落法＝挂到该图**第一棵树的根**下；图里没有任何根
  /// （空图）时先补一个「中心主题」再挂——空图直接挂成游离根就失了「第一层」
  /// 的语义，也看不出它属于哪张图。
  Future<void> _toMindmap(InboxItem item) async {
    final dao = ref.read(mindmapDaoProvider);
    final maps = await dao.listLive();
    if (!mounted) return;
    final picked = await showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: maps.isEmpty
            ? const Padding(
                padding: EdgeInsets.fromLTRB(20, 22, 20, 26),
                child: Text(
                  '还没有导图 · 先去思维导图建一张，再回来转',
                  key: ValueKey('ibk-mm-empty'),
                  style: TextStyle(fontSize: 13),
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 6),
                    child: Text('转成哪张图的节点',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                  ),
                  for (final (m, cnt) in maps)
                    ListTile(
                      key: ValueKey('ibk-mm-${m.id}'),
                      dense: true,
                      title: Text(m.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5)),
                      trailing: Text('$cnt 节点',
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(sheetCtx)
                                  .colorScheme
                                  .onSurfaceVariant)),
                      onTap: () => Navigator.of(sheetCtx).pop(m.id),
                    ),
                ],
              ),
      ),
    );
    if (picked == null || !mounted) return;
    // 取该图第一棵树的根（多根图的「中心主题」口径：sort 最小者）。
    final nodes = await dao.nodesOf(picked);
    final roots = nodes.where((n) => n.parentId == null).toList()
      ..sort((a, b) => a.sort.compareTo(b.sort));
    int? parentId;
    if (roots.isEmpty) {
      final center = await dao.addNode(
          mapId: picked, parentId: null, title: '中心主题');
      parentId = center.id;
    } else {
      parentId = roots.first.id;
    }
    final text = item.rawText.trim();
    final title = text.split('\n').first;
    await dao.addNode(
      mapId: picked,
      parentId: parentId,
      title: title.isEmpty ? '（空条目）' : title,
      note: text.contains('\n') ? text : '',
    );
    await ref.read(inboxDaoProvider).route(item.id!, 'mindmap', picked);
    ref.invalidate(inboxItemsProvider);
    AppLog.addKey(
        '收集箱分流→导图节点：图 #$picked 根 #$parentId（原条 #${item.id}）');
    _toast('已转为导图节点 · 原条目留在收集箱');
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
        AppLog.addKey('收集箱分流→待办：#${t.id} 「${_brief(src)}」（原条 #${item.id}）');
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
        AppLog.addKey('收集箱分流→今晚日记：#${saved.id}（原条 #${item.id}）');
        _toast('📔 已插入今晚日记草稿');
      case 'note':
        final id = await ref.read(noteDaoProvider).insert(Note(
            title: src.length > 20 ? '${src.substring(0, 20)}…' : src,
            content: src,
            folder: '收集箱',
            createdAt: now(),
            updatedAt: now()));
        await dao.route(item.id!, 'note', id);
        AppLog.addKey('收集箱分流→笔记：#$id（原条 #${item.id}）');
        _toast('📝 已存为笔记（编辑器 M1 开放）');
      case 'excerpt':
        final rrepo = ref.read(readRepositoryProvider);
        final books = (await rrepo.allBooks()).where((b) => !b.isDeleted).toList()
          ..sort((a, b) =>
              (b.lastReadAt ?? 0).compareTo(a.lastReadAt ?? 0));
        if (books.isEmpty) {
          AppLog.add('收集箱分流→摘录被拒：书架无在读书目', level: LhLevel.warn);
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
          AppLog.add('收集箱分流→摘录未入账（同书同句已存在）', level: LhLevel.warn);
          _toast('这条摘录已存在 · 未重复入账');
          return;
        }
        await dao.route(item.id!, 'quote', qid);
        ref.read(readTickProvider.notifier).state++;
        // excerpt 分支在 switch 内提前 return——这里必须自行 invalidate，否则分流后未整理列表不刷新。
        ref.invalidate(inboxItemsProvider);
        AppLog.addKey('收集箱分流→阅读摘录：#$qid · 书 $picked（原条 #${item.id}）');
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
    // 未落任何模块就删掉＝原文只存在于这一条里，事后想查必须有痕迹。
    AppLog.addKey('收集箱条目直接删除：#${item.id} 「${_brief(item.rawText)}」');
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
            // UIUX批（2026-10-12）：僵尸钮兑现——接全局搜索半屏（笔记＋日记）。
            onPressed: () => showGlobalSearch(context, ref),
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
              // 第五向（批P2）：需求模块 18 要的双向里，收集箱侧这一半。
              // 配色不新增硬编码：导图入口用主题主色（与「→待办」同为模块主操作色系），
              // 色值棘轮基线因此不涨（新增色值须人审，一枚按钮不值得）。
              _tri('→导图', tokens.accent, () => _toMindmap(item)),
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
