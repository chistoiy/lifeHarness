import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/grad_fab.dart';
import '../domain/journal_entry.dart';
import 'diary_edit_page.dart';
import 'journal_providers.dart';
import 'note_edit_page.dart';
import 'note_tab.dart';
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

  static const _acts = [
    ('📝', '添加富文本笔记', 'rich'),
    ('📃', '添加纯文本笔记', 'plain'),
    ('⌨️', '添加 MD 文档', 'md'),
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
                  child: Text('$ico $label',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800)),
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
          PopupMenuButton<String>(
            key: const ValueKey('rec-switch'),
            tooltip: '切换 日记/笔记/阅读/影音游',
            icon: const Icon(Icons.sync_alt),
            onSelected: (v) =>
                ref.read(recordTabProvider.notifier).state = v,
            itemBuilder: (_) => [
              for (final e in kRecordLabels.entries)
                PopupMenuItem(
                  value: e.key,
                  child: Row(
                    children: [
                      Text(e.value,
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: e.key == tab ? tokens.accent : null)),
                      if (e.key == tab) ...[
                        const Spacer(),
                        Icon(Icons.check, size: 18, color: tokens.accent),
                      ],
                    ],
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
class _DiaryTab extends ConsumerWidget {
  const _DiaryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final entriesAsync = ref.watch(journalsProvider);
    final streak = ref.watch(journalStreakProvider).valueOrNull ?? 0;
    final filter = ref.watch(journalFilterProvider);
    final insMode = ref.watch(journalInsProvider);
    final entries = entriesAsync.valueOrNull ?? const <JournalEntry>[];

    final shown = filter == 'all'
        ? entries
        : entries
            .where((e) => e.tags.any((t) => t == filter || t == filter.replaceFirst('#', '')))
            .toList();

    final tags = <String>{
      for (final e in entries) ...e.tags,
    }.take(4).map((t) => '#$t').toList();

    final now = DateTime.now();
    final today = entries.where((e) => JournalEntry.sameDay(e.day, now)).firstOrNull;
    final monthEntries =
        entries.where((e) => e.day.year == now.year && e.day.month == now.month).toList();

    return ListView(
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
                              : '今日已写 ${today.content.length} 字 · 继续编辑',
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
        // V1.29轮7：筛选 + 列表/INS 切换合并为一行右侧双钮
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            PopupMenuButton<String>(
              key: const ValueKey('diary-filter'),
              tooltip: '筛选',
              color: tokens.card,
              icon: Icon(
                Icons.filter_alt_outlined,
                size: 22,
                color: filter == 'all'
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : tokens.accent,
              ),
              onSelected: (f) =>
                  ref.read(journalFilterProvider.notifier).state = f,
              itemBuilder: (_) => [
                for (final f in ['all', ...tags])
                  PopupMenuItem(
                    value: f,
                    child: Row(
                      children: [
                        Text(f == 'all' ? '全部' : f,
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: f == filter ? tokens.accent : null)),
                        if (f == filter) ...[
                          const Spacer(),
                          Icon(Icons.check, size: 18, color: tokens.accent),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
            IconButton(
              key: const ValueKey('diary-view'),
              tooltip: insMode ? '切换到列表' : '切换到 INS 卡片流',
              onPressed: () => ref.read(journalInsProvider.notifier).state =
                  !insMode,
              icon: Icon(insMode ? Icons.menu : Icons.grid_view, size: 22),
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
                entry: e, onOpen: () => context.push('/journal/edit', extra: DiaryEditArg(entryId: e.id)))
        else
          for (final e in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _card(
                context,
                child: InkWell(
                  borderRadius: BorderRadius.circular(tokens.cardRadius),
                  onTap: () => context.push('/journal/edit', extra: DiaryEditArg(entryId: e.id)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
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
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            for (final t in e.tags.take(3))
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: _chip(context, label: '#$t', on: false, onTap: () {}),
                              ),
                            const Spacer(),
                            Text(
                              '☑ ${e.todoLines().length} · '
                              '${_two(e.updatedAt.hour)}:${_two(e.updatedAt.minute)} 保存',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                            ),
                          ],
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

  Widget _chip(BuildContext context,
      {required String label, required bool on, required VoidCallback onTap}) {
    final tokens = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: on ? tokens.accent : tokens.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? tokens.accent : tokens.cardBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: on ? Colors.white : Theme.of(context).colorScheme.onSurface),
        ),
      ),
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

extension on String {
  String clampText(int n) => length <= n ? this : '${substring(0, n)}…';
}
