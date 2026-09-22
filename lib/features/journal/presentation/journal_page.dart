import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/grad_fab.dart';
import '../../../shared/widgets/ui_kit.dart' show AppToast;
import '../domain/journal_entry.dart';
import 'diary_edit_page.dart';
import 'journal_providers.dart';
import 'note_edit_page.dart';
import 'note_tab.dart';
import 'widgets/image_attach.dart' show showImageLightbox;
import 'widgets/ins_card.dart';

/// 笔记段 FAB（V1.29轮2 原型 noteFabMenu）：与主页同款竖排三选
/// 📝富文本 / 📃纯文本 / ⌨️MD 文档；新建默认归属当前选中文件夹。
class _NoteFab extends ConsumerStatefulWidget {
  const _NoteFab();

  @override
  ConsumerState<_NoteFab> createState() => _NoteFabState();
}

class _NoteFabState extends ConsumerState<_NoteFab> {
  bool _open = false;

  // 轮10-9：FAB 三选去 emoji=线性图标（与弹层/菜单同语言）。
  static const _acts = [
    (Icons.edit_document, '添加富文本笔记', 'rich'),
    (Icons.notes_outlined, '添加纯文本笔记', 'plain'),
    (Icons.keyboard_outlined, '添加 MD 文档', 'md'),
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final (ico, label, kind) in _acts)
          if (_open)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                key: ValueKey('note-fab-$kind'),
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  setState(() => _open = false);
                  final folder = ref.read(noteFilterProvider).folder;
                  context.push('/note/edit',
                      extra: NoteEditArg(
                          kind: kind,
                          folder: folder == kNoteTrash ? '' : folder));
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                      color: tokens.card,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: tokens.cardBorder),
                      boxShadow: tokens.cardShadow),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(ico, size: 16),
                      const SizedBox(width: 8),
                      Text(label,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ),
        GradFab(
          tooltip: '添加笔记',
          icon: Icon(_open ? Icons.close : Icons.add,
              color: Colors.white, size: 26),
          onTap: () => setState(() => _open = !_open),
        ),
      ],
    );
  }
}

/// 模块3 记录页（原型 p-records · V1.29轮5）：无段切换行，
/// 标题随当前段显「记录 · X」，右上 ⇄ 钮开四能力菜单。
/// 日记（M0/V1.28）与笔记列表管理（M1 批1a）为真实数据；阅读/影音游留占位。
class JournalPage extends ConsumerWidget {
  const JournalPage({super.key});

  static const kRecordLabels = {
    'diary': '日记',
    'note': '笔记',
    'book': '阅读',
    'media': '影音游',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(recordTabProvider);
    final tokens = context.tokens;

    return Scaffold(
      appBar: AppBar(
        title: Text('记录 · ${kRecordLabels[tab]}'),
        actions: [
          // ⇄ 四能力切换（仅记录页；当前项高亮✓）
          // 轮10-9：菜单条目改圆角行卡+选中底色（与弹层/抽屉同语言·accent 随主题）。
          PopupMenuButton<String>(
            key: const ValueKey('rec-switch'),
            tooltip: '切换 日记/笔记/阅读/影音游',
            icon: const Icon(Icons.sync_alt),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18)),
            onSelected: (v) =>
                ref.read(recordTabProvider.notifier).state = v,
            itemBuilder: (_) => [
              for (final e in kRecordLabels.entries)
                PopupMenuItem<String>(
                  value: e.key,
                  height: 46,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: e.key == tab
                          ? tokens.accent.withValues(alpha: .12)
                          : null,
                    ),
                    child: Row(
                      children: [
                        Text(e.value,
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: e.key == tab ? tokens.accent : null)),
                        const Spacer(),
                        if (e.key == tab)
                          Icon(Icons.check, size: 17, color: tokens.accent),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search),
            onPressed: () => ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(
                  content: Text('全局搜索 · 即将开放'),
                  duration: Duration(milliseconds: 1500))),
          ),
        ],
      ),
      floatingActionButton: tab == 'note'
          ? const _NoteFab()
          : GradFab(
              tooltip: '写今天的日记',
              icon: const Icon(Icons.add, color: Colors.white, size: 26),
              onTap: () =>
                  context.push('/journal/edit', extra: const DiaryEditArg()),
            ),
      body: switch (tab) {
        'diary' => const _DiaryTab(),
        'note' => const NoteTab(),
        'book' => const _TabSoon('📚', '阅读 · 书架/摘录/目录计时', '规划 V0.5 · M1'),
        _ => const _TabSoon('🎬', '影音游 · 与阅读同构', '规划 V1.1 · M3'),
      },
    );
  }
}

class _TabSoon extends StatelessWidget {
  const _TabSoon(this.emoji, this.title, this.plan);

  final String emoji, title, plan;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 40)),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(plan,
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text('敬请期待',
              style: TextStyle(fontSize: 11, color: tokens.accent, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// 日记 tab：心情月历卡 · 写今天入口 · 筛选 · 列表/INS 双布局 · 那年今日。
/// 轮13：长按条目/卡片进入批量选中（底部 已选N篇+删除+关闭 · 返回先退多选）。
class _DiaryTab extends ConsumerStatefulWidget {
  const _DiaryTab();

  @override
  ConsumerState<_DiaryTab> createState() => _DiaryTabState();
}

class _DiaryTabState extends ConsumerState<_DiaryTab> {
  bool _selMode = false;
  final Set<int> _sel = {};

  void _enterSel(int id) => setState(() {
        _selMode = true;
        _sel.add(id);
      });

  void _toggleSel(int id) => setState(() {
        _sel.contains(id) ? _sel.remove(id) : _sel.add(id);
        if (_sel.isEmpty) _selMode = false;
      });

  void _exitSel() => setState(() {
        _selMode = false;
        _sel.clear();
      });

  /// 批量删除：确认弹层 → 逐篇删（分节随删）→ 刷新列表。
  Future<void> _batchDelete() async {
    final n = _sel.length;
    final yes = await showDialog<bool>(
      context: context,
      builder: (bc) => AlertDialog(
        title: Text('删除选中的 $n 篇日记？'),
        content: const Text('删除后不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(bc).pop(false),
              child: const Text('取消')),
          TextButton(
            key: const ValueKey('diary-del-batch-ok'),
            onPressed: () => Navigator.of(bc).pop(true),
            child:
                const Text('删除', style: TextStyle(color: Color(0xFFF43F5E))),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await ref.read(journalRepositoryProvider).removeAll(_sel);
    if (!mounted) return;
    _exitSel();
    ref.invalidate(journalsProvider);
    AppToast.show(context, '已删除 $n 篇日记');
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final tokens = context.tokens;
    final entriesAsync = ref.watch(journalsProvider);
    final streak = ref.watch(journalStreakProvider).valueOrNull ?? 0;
    final filter = ref.watch(journalFilterProvider);
    final insMode = ref.watch(journalInsProvider);
    final entries = entriesAsync.valueOrNull ?? const <JournalEntry>[];

    final shown = switch (filter) {
      'all' => entries,
      'todo' => entries.where((e) => e.todoLines().isNotEmpty).toList(),
      _ => entries
          .where((e) => e.tags.any((t) => t == filter || '#$t' == filter))
          .toList(),
    };

    final tags = <String>{
      for (final e in entries) ...e.tags,
    }.take(4).map((t) => '#$t').toList();

    final now = DateTime.now();
    final today = entries.where((e) => JournalEntry.sameDay(e.day, now)).firstOrNull;
    final monthEntries =
        entries.where((e) => e.day.year == now.year && e.day.month == now.month).toList();

    return PopScope(
      canPop: !_selMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitSel(); // 轮13：多选态返回=先退出多选
      },
      child: Column(
        children: [
          Expanded(
            child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        // 渐变心情月历卡（原型 moodCard：标题+回顾钮+30 色条+脚注）
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              gradient: tokens.gradient,
              borderRadius: BorderRadius.circular(24),
              boxShadow: tokens.cardShadow),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('${now.month}月 · 已记录 ${monthEntries.length} 篇',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _soon(context, '心情月历 / 词云回顾 · 规划 V1.x'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .2),
                          borderRadius: BorderRadius.circular(999)),
                      child: const Text('📊 回顾',
                          style: TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 36,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var d = 1; d <= DateTime(now.year, now.month + 1, 0).day; d++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1),
                          child: GestureDetector(
                            onTap: () => context
                                .push('/journal/edit', extra: DiaryEditArg(day: DateTime(now.year, now.month, d))),
                            child: Container(
                              height: 36 * _barHeight(now, d, entries),
                              decoration: BoxDecoration(
                                color: _barColor(now, d, entries),
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(3)),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '连续记录 $streak 天 · '
                '${_dominantMoodText(monthEntries)} · 点色条看当天',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: .8), fontSize: 10),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 写今天的日记（原型入口卡）
        _card(
          context,
          child: InkWell(
            borderRadius: BorderRadius.circular(tokens.cardRadius),
            onTap: () => context.push('/journal/edit', extra: const DiaryEditArg()),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: tokens.accent.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Text('✍️', style: TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('写今天的日记',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                        Text(
                          today == null
                              ? '开始今天的记录 · 输入 ☐ 可插入待办'
                              : '今日已写 ${today.plainBody.length} 字 · 继续编辑',
                          style: TextStyle(
                              fontSize: 11,
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const Text('›', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // V1.29轮9g：本行=列表⇄INS 切换钮 + 筛选钮（右）·筛选点击弹底部浮层 全部/☐待办/标签
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              key: const ValueKey('diary-view'),
              tooltip: insMode ? '切换到列表' : '切换到 INS 卡片流',
              onPressed: () => ref.read(journalInsProvider.notifier).state =
                  !insMode,
              icon: Icon(insMode ? Icons.menu : Icons.grid_view, size: 22),
            ),
            IconButton(
              key: const ValueKey('diary-filter'),
              tooltip: '筛选',
              onPressed: () => _diaryFilterSheet(context, ref, filter, tags),
              icon: Icon(
                filter == 'all'
                    ? Icons.filter_alt_outlined
                    : Icons.filter_alt,
                size: 22,
                color: filter == 'all'
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : tokens.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Center(
              child: Text(
                entries.isEmpty ? '还没有日记 · 点上方「写今天的日记」开始' : '该筛选下暂无日记',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          )
        else if (insMode)
          for (final e in shown)
            InsDiaryCard(
                entry: e,
                selected: _sel.contains(e.id),
                onLongPress: () => _enterSel(e.id!),
                onOpen: () => _selMode
                    ? _toggleSel(e.id!)
                    : context.push('/journal/edit',
                        extra: DiaryEditArg(entryId: e.id)))
        else
          for (final e in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _card(
                context,
                child: InkWell(
                  borderRadius: BorderRadius.circular(tokens.cardRadius),
                  onLongPress: () => _enterSel(e.id!),
                  onTap: () => _selMode
                      ? _toggleSel(e.id!)
                      : context.push('/journal/edit',
                          extra: DiaryEditArg(entryId: e.id)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Stack(
                      children: [
                        Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('${e.day.year}-${_two(e.day.month)}-${_two(e.day.day)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 14)),
                            const SizedBox(width: 6),
                            Text('周${_weekdays[e.day.weekday - 1]}',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                            const Spacer(),
                            if (moodEmoji(e.mood) != null) ...[
                              Text(moodEmoji(e.mood)!,
                                  style: const TextStyle(fontSize: 18)),
                              const SizedBox(width: 4),
                              Text(moodLabel(e.mood) ?? '',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          e.content.isEmpty ? '（只打了心情卡）' : e.previewText,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, height: 1.6),
                        ),
                        // 批2a：有图篇在预览下挂 4 缩略（>4 末格 +N）
                        if (e.imagePaths.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _DiaryThumbs(entry: e),
                        ],
                        const SizedBox(height: 8),
                        // 轮12-11：关联信息=右下角小图标（保存时间左侧），点击展开
                        _DiaryMeta(entry: e),
                      ],
                        ),
                        // 轮13：多选态选中 ✓ 角标
                        if (_sel.contains(e.id))
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              key: ValueKey('jsel-${e.id}'),
                              width: 22,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: tokens.accent),
                              child: const Icon(Icons.check,
                                  size: 14, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        // 那年今日
        FutureBuilder(
          future: ref.read(journalRepositoryProvider).onThisDayLastYear(),
          builder: (context, snap) {
            final old = snap.data;
            if (old == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: GestureDetector(
                onTap: () => context.push('/journal/edit', extra: DiaryEditArg(entryId: old.id)),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: tokens.accent.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(16)),
                  child: Text(
                    '🗓 那年今日 · ${old.day.year}-${_two(old.day.month)}-${_two(old.day.day)}\n'
                    '「${old.previewText.replaceAll('\n', ' ').clampText(24)}」点击查看',
                    style: const TextStyle(fontSize: 11, height: 1.6),
                  ),
                ),
              ),
            );
          },
        ),
      ],
            ),
          ),
          if (_selMode) _selBar(),
        ],
      ),
    );
  }

  /// 轮13 · 批量选中底栏：已选 N 篇 + 删除（玫红线性图标）+ 关闭 ✕（与笔记同款简约图标）。
  Widget _selBar() {
    final tokens = context.tokens;
    return Container(
      key: const ValueKey('diary-sel-bar'),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: tokens.card,
        border: Border(top: BorderSide(color: tokens.cardBorder)),
      ),
      child: Row(
        children: [
          Text('已选 ${_sel.length} 篇',
              key: const ValueKey('diary-sel-count'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          const Spacer(),
          IconButton(
            key: const ValueKey('diary-del-batch'),
            tooltip: '删除',
            onPressed: _batchDelete,
            icon: const Icon(Icons.delete_outline,
                size: 22, color: Color(0xFFF43F5E)),
          ),
          IconButton(
            key: const ValueKey('diary-sel-exit'),
            tooltip: '取消',
            onPressed: _exitSel,
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    );
  }

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  static String _two(int v) => v.toString().padLeft(2, '0');

  double _barHeight(DateTime now, int day, List<JournalEntry> entries) {
    final e = entries
        .where((x) => x.day.year == now.year && x.day.month == now.month && x.day.day == day)
        .firstOrNull;
    if (e == null) return .12;
    final mood = e.mood;
    return mood == null ? .35 : 0.35 + mood / kJournalMoods.length * 0.65;
  }

  Color _barColor(DateTime now, int day, List<JournalEntry> entries) {
    final e = entries
        .where((x) => x.day.year == now.year && x.day.month == now.month && x.day.day == day)
        .firstOrNull;
    if (e == null) return Colors.white.withValues(alpha: .22);
    const palette = [
      Color(0xFF6366F1), Color(0xFF2DD4BF), Color(0xFFF59E0B),
      Color(0xFFFB7185), Color(0xFF8B5CF6), Color(0xFF0EA5E9), Color(0xFFF43F5E),
    ];
    return palette[((e.mood ?? 1) - 1) % palette.length];
  }

  String _dominantMoodText(List<JournalEntry> monthEntries) {
    final counts = <int, int>{};
    for (final e in monthEntries) {
      if (e.mood != null) counts[e.mood!] = (counts[e.mood!] ?? 0) + 1;
    }
    if (counts.isEmpty) return '本月还没有心情记录';
    final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    return '本月心情以 ${moodEmoji(top)} ${moodLabel(top)} 居多';
  }

  /// V1.29轮9g：筛选=底部浮层选择（全部/☐待办/标签·当前项✓）。
  Future<void> _diaryFilterSheet(
      BuildContext context, WidgetRef ref, String cur, List<String> tags) async {
    final opts = ['全部', '☐ 待办', ...tags];
    String valOf(String o) => switch (o) {
          '全部' => 'all',
          '☐ 待办' => 'todo',
          _ => o,
        };
    String labelOf(String v) => switch (v) {
          'all' => '全部',
          'todo' => '☐ 待办',
          _ => v,
        };
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (bc) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text('筛选',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            for (final o in opts)
              ListTile(
                key: ValueKey('df-opt-$o'),
                title: Row(
                  children: [
                    Text(o,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: valOf(o) == cur
                                ? bc.tokens.accent
                                : null)),
                    if (valOf(o) == cur) ...[
                      const Spacer(),
                      Icon(Icons.check, size: 18, color: bc.tokens.accent),
                    ],
                  ],
                ),
                onTap: () => Navigator.of(bc).pop(o),
              ),
          ],
        ),
      ),
    );
    if (pick == null) return;
    ref.read(journalFilterProvider.notifier).state = valOf(pick);
    if (context.mounted) AppToast.show(context, '筛选：${labelOf(pick)}');
  }

  Widget _card(BuildContext context, {required Widget child}) {
    final tokens = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        border: Border.all(color: tokens.cardBorder),
        boxShadow: tokens.cardShadow,
      ),
      child: child,
    );
  }

  void _soon(BuildContext context, String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text('$what · 敬请期待'),
          duration: const Duration(milliseconds: 1500)));
  }
}

/// 轮12-11 · 列表行底栏：标签 chips + 关联小图标（☑ N 收起态·点击展开明细）+ 保存时间。
class _DiaryMeta extends StatefulWidget {
  const _DiaryMeta({required this.entry});

  final JournalEntry entry;

  @override
  State<_DiaryMeta> createState() => _DiaryMetaState();
}

class _DiaryMetaState extends State<_DiaryMeta> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final n = e.todoLines().length;
    String two(int v) => v.toString().padLeft(2, '0');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final t in e.tags.take(3))
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: tokens.cardBorder),
                  ),
                  child: Text('#$t',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ),
            const Spacer(),
            if (n > 0)
              IconButton(
                key: ValueKey('jref-${e.id}'),
                tooltip: '本页关联',
                visualDensity: VisualDensity.compact,
                constraints:
                    const BoxConstraints(minWidth: 40, minHeight: 28),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                onPressed: () => setState(() => _open = !_open),
                icon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.link,
                        size: 14,
                        color: _open ? tokens.accent : scheme.onSurfaceVariant),
                    const SizedBox(width: 3),
                    Text('$n',
                        style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            Text(
              '${two(e.updatedAt.hour)}:${two(e.updatedAt.minute)} 保存',
              style: TextStyle(
                  fontSize: 10, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        if (_open && n > 0)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: tokens.accent.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border(left: BorderSide(color: tokens.accent, width: 3)),
            ),
            child: Text('本页关联 · ☑ $n 个待办同步',
                style: TextStyle(
                    fontSize: 11, color: scheme.onSurfaceVariant)),
          ),
      ],
    );
  }
}

/// 批2a · 日记行缩略条：一行 4 枚 44×44（>4 末格盖 +N · 点图看大图）。
class _DiaryThumbs extends StatelessWidget {
  const _DiaryThumbs({required this.entry});

  final JournalEntry entry;

  @override
  Widget build(BuildContext context) {
    final paths = entry.imagePaths;
    final shown = paths.take(4).toList();
    return Row(
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          GestureDetector(
            key: ValueKey('jimg-${entry.id}-$i'),
            onTap: () => showImageLightbox(context, shown[i]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(File(shown[i]),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const ColoredBox(
                            color: Color(0x14000000),
                            child: Center(
                                child: Text('丢失',
                                    style: TextStyle(fontSize: 9))))),
                    if (i == 3 && paths.length > 4)
                      Positioned.fill(
                        child: ColoredBox(
                          color: const Color(0x73000000),
                          child: Center(
                              child: Text('+${paths.length - 4}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12))),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const Spacer(),
      ],
    );
  }
}

extension on String {
  String clampText(int n) => length <= n ? this : '${substring(0, n)}…';
}
