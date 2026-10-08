import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/load_error_state.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/media_repo_note.dart';
import '../domain/media_item.dart';
import '../domain/media_note.dart';
import 'media_note_edit_sheet.dart';
import 'media_providers.dart';
import 'media_review_sheet.dart';

/// 影音笔记库（原型 `m-notes` · 词典 LH-C18 · 路由 `/media/notes` · 批5）。
///
/// 三条口径写在最近处：
/// - **四视图吃同一份筛选结果**（工单 §1.1）：列表只取一次 `mediaNotesProvider`，
///   卡片／行／按条目／截图墙都画这份数据，计数行也只从这份算——
///   「四视图各自重算过滤，切视图数字漂移」＝刀3 钉的那条，屏侧不留第二条查询；
/// - **六路筛选收在一枚筛选钮**（拍板①）：屏面只留搜索行＋筛选钮（带激活计数）＋已选摘要行，
///   类型／kind／条目／标星／标签六组条件全在半屏面板里改，「应用筛选」一次性落；
/// - **空态两档分话术**：库里零笔记 vs 当前筛选零命中（一句「没有笔记」盖不住两种成因）。
class MediaNotesPage extends ConsumerWidget {
  const MediaNotesPage({super.key});

  static const Key kEntryAll = ValueKey('mdn-view-seg');
  static const Key kFilterRow = ValueKey('mdn-filter-row');
  static const Key kFilterBtn = ValueKey('mdn-filter-btn');
  static const Key kSummary = ValueKey('mdn-summary');
  static const Key kBody = ValueKey('mdn-body');
  static const Key kCount = ValueKey('mdn-count');
  static const Key kReview = ValueKey('mdn-review-btn');
  static const Key kAdd = ValueKey('mdn-add-btn');

  /// 四档视图（键名照原型 `mNoteView`：card/list/byitem/wall）。
  static const List<(String, String)> views = [
    ('card', '卡片'),
    ('list', '行'),
    ('byitem', '按条目'),
    ('wall', '截图墙'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(mediaNotesProvider);
    final total = ref.watch(mediaNoteTotalProvider).valueOrNull ?? 0;
    final view = ref.watch(mediaNoteViewProvider);
    final filter = ref.watch(mediaNoteFilterProvider);
    final titles = _titleMap(ref);

    return Scaffold(
      appBar: AppBar(
        title: const Text('影音笔记库'),
        actions: [
          // 复习钮：角标读数＝吃同一份筛选的到期队列长度（屏侧不自己数）。
          _ReviewBadge(
            onOpen: () => showMediaReviewSheet(context, ref),
          ),
          IconButton(
            key: kAdd,
            icon: const Icon(Icons.add),
            onPressed: () => showMediaNoteEditSheet(context, ref),
          ),
        ],
      ),
      body: notes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => LoadErrorBanner(
          title: '笔记库没加载出来',
          error: e,
          onRetry: () => ref.invalidate(mediaNotesProvider),
        ),
        data: (list) => Column(
          children: [
            _topBar(context, ref, filter),
            Expanded(
              child: list.isEmpty
                  ? EmptyDashRow(
                      key: const ValueKey('mdn-empty'),
                      text: total == 0
                          ? '还没有影音笔记 · 点右上＋记一条'
                          : '当前筛选没有笔记',
                      onTap: total == 0 ? () => showMediaNoteEditSheet(context, ref) : null,
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      children: [
                        _countRow(context, list.length, view),
                        _seg(context, ref, view),
                        const SizedBox(height: 10),
                        ..._body(context, ref, view, list, titles),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 条目 id → 标题（四视图与摘要行都用这一份，别在各视图里各查一遍）。
  Map<String, String> _titleMap(WidgetRef ref) {
    final items = ref.watch(mediaAllItemsProvider).valueOrNull ?? const <MediaItem>[];
    return {for (final x in items) x.id: x.title};
  }

  // ==================== 顶部：搜索行＋筛选钮＋摘要行（拍板①） ====================

  Widget _topBar(BuildContext context, WidgetRef ref, MediaNoteFilter f) {
    final scheme = Theme.of(context).colorScheme;
    final active = _activeCount(f);
    return Padding(
      key: kFilterRow,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('mdn-query'),
            controller: TextEditingController(text: f.query)
              ..selection = TextSelection.collapsed(offset: f.query.length),
            onSubmitted: (v) =>
                ref.read(mediaNoteFilterProvider.notifier).state = nfQuery(f, v),
            onChanged: (v) =>
                ref.read(mediaNoteFilterProvider.notifier).state = nfQuery(f, v),
            decoration: InputDecoration(
              hintText: '搜正文 · 批注 · 条目名',
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 16),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: scheme.outlineVariant),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              PillChip(
                key: kFilterBtn,
                label: active == 0 ? '筛选' : '筛选 · $active',
                selected: active > 0,
                onTap: () => showMediaNoteFilterSheet(context, ref),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _summaryText(f, _titleMap(ref)),
                  key: kSummary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                ),
              ),
              if (active > 0)
                TextButton(
                  key: const ValueKey('mdn-clear'),
                  onPressed: () => ref.read(mediaNoteFilterProvider.notifier).state =
                      kMediaNoteFilterAll,
                  child: const Text('清空', style: TextStyle(fontSize: 11)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  int _activeCount(MediaNoteFilter f) =>
      (f.type != null ? 1 : 0) +
      (f.kind != null ? 1 : 0) +
      (f.itemId != null ? 1 : 0) +
      (f.tag != null ? 1 : 0) +
      (f.starred ? 1 : 0);

  String _summaryText(MediaNoteFilter f, Map<String, String> titles) {
    final parts = <String>[
      if (f.type != null) (MediaNote.typeLabels[f.type] ?? f.type!),
      if (f.kind != null) MediaItem.labelOf(f.kind!),
      if (f.itemId != null) '《${titles[f.itemId] ?? '已删条目'}》',
      if (f.tag != null) f.tag!,
      if (f.starred) '只看标星',
    ];
    return parts.isEmpty ? '未加筛选 · 看在册全部笔记' : '已选：${parts.join(' · ')}';
  }

  Widget _countRow(BuildContext context, int n, String view) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: kCount,
      padding: const EdgeInsets.only(bottom: 6),
      child: Text('$n 条 · ${views.firstWhere((v) => v.$1 == view).$2}',
          style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
    );
  }

  Widget _seg(BuildContext context, WidgetRef ref, String view) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      key: kEntryAll,
      children: [
        for (final (k, label) in views)
          Expanded(
            child: InkWell(
              key: ValueKey('mdn-view-$k'),
              borderRadius: BorderRadius.circular(10),
              onTap: () => ref.read(mediaNoteViewProvider.notifier).state = k,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: view == k ? scheme.primary : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: view == k ? scheme.onPrimary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ==================== 四视图（同一份 list，只换画法） ====================

  List<Widget> _body(BuildContext context, WidgetRef ref, String view,
          List<MediaNote> list, Map<String, String> titles) =>
      switch (view) {
        'card' => [
            for (final n in list) _card(context, ref, n, titles, false),
          ],
        'list' => [
            for (final n in list) _rowLine(context, ref, n, titles),
          ],
        'wall' => [
            for (final n in list) _wallTile(context, ref, n, titles),
          ],
        _ => _groupedByItem(context, ref, list, titles),
      };

  /// 按条目分组（默认档）：每组标题带每组计数，组内画卡形但不带行内动作——
  /// 动作在行视图与卡片视图给，分组视图里再嵌一层按钮会把组结构挤散（原型同形）。
  List<Widget> _groupedByItem(BuildContext context, WidgetRef ref,
      List<MediaNote> list, Map<String, String> titles) {
    final groups = <String, List<MediaNote>>{};
    for (final n in list) {
      (groups[n.itemId] ??= <MediaNote>[]).add(n);
    }
    return [
      for (final e in groups.entries) ...[
        Padding(
          key: ValueKey('mdn-group-${e.key}'),
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Text('《${titles[e.key] ?? '已删条目'}》 · ${e.value.length} 条',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
        ),
        for (final n in e.value) _card(context, ref, n, titles, true),
      ],
    ];
  }

  Widget _card(BuildContext context, WidgetRef ref, MediaNote n,
      Map<String, String> titles, bool compact) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: ValueKey('mdn-card-${n.id}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showMediaReviewSheet(context, ref, singleNoteId: n.id),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(12),
            border: Border(
              left: BorderSide(color: mediaNoteTypeColor(n.noteType), width: 3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                compact
                    ? '${n.atMin == null ? '' : '${mediaNoteAtTx(n.atMin)} · '}${MediaNote.typeLabels[n.noteType] ?? ''}'
                    : '${MediaNote.typeLabels[n.noteType] ?? ''} · ${titles[n.itemId] ?? '已删条目'}',
                style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(n.body,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, height: 1.5)),
              if (!compact) _actions(context, ref, n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rowLine(BuildContext context, WidgetRef ref, MediaNote n,
      Map<String, String> titles) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: ValueKey('mdn-row-${n.id}'),
      borderRadius: BorderRadius.circular(10),
      onTap: () => showMediaReviewSheet(context, ref, singleNoteId: n.id),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: mediaNoteTypeColor(n.noteType), shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${MediaItem.labelOf(n.kind)}·${titles[n.itemId] ?? '已删条目'}'
                '${n.atMin == null ? '' : '·${mediaNoteAtTx(n.atMin)}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Text(n.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5)),
            ),
            _star(context, ref, n),
            _trash(context, ref, n),
          ],
        ),
      ),
    );
  }

  Widget _wallTile(BuildContext context, WidgetRef ref, MediaNote n,
      Map<String, String> titles) {
    final scheme = Theme.of(context).colorScheme;
    final has = n.imagePaths.isNotEmpty;
    return Padding(
      key: ValueKey('mdn-wall-${n.id}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showMediaReviewSheet(context, ref, singleNoteId: n.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (has)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(n.imagePaths.first),
                  height: 132,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _noShotBox(scheme),
                ),
              )
            else
              _noShotBox(scheme),
            const SizedBox(height: 4),
            Text('${MediaNote.typeLabels[n.noteType] ?? ''} · ${titles[n.itemId] ?? '已删条目'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _noShotBox(ColorScheme scheme) => Container(
        height: 132,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Center(
          child: Text('无截图', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        ),
      );

  /// 行内动作（卡片视图才带；点星就地翻、删除走 LH-S31 确认式）。
  Widget _actions(BuildContext context, WidgetRef ref, MediaNote n) => Row(
        children: [
          _star(context, ref, n),
          const Spacer(),
          if (n.tag != null)
            Text(n.tag!,
                style: TextStyle(fontSize: 9.5, color: Theme.of(context).colorScheme.primary)),
          const SizedBox(width: 8),
          Text(_dayTx(n.createdAt),
              style: TextStyle(fontSize: 9.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(width: 6),
          _trash(context, ref, n),
        ],
      );

  Widget _star(BuildContext context, WidgetRef ref, MediaNote n) => IconButton(
        key: ValueKey('mdn-star-${n.id}'),
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        icon: Icon(
          n.starred ? Icons.star : Icons.star_border,
          color: n.starred ? const Color(0xFFF59E0B) : null,
        ),
        onPressed: () async {
          await ref.read(mediaRepositoryProvider).setNoteStarred(n.id!, !n.starred);
          _bump(ref);
          if (!context.mounted) return;
        },
      );

  Widget _trash(BuildContext context, WidgetRef ref, MediaNote n) => IconButton(
        key: ValueKey('mdn-del-${n.id}'),
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        icon: const Icon(Icons.delete_outline),
        onPressed: () async {
          final ok = await lhConfirm(context, '删掉这条影音笔记？该条目的名场面时间线里也会一并消失。');
          if (!ok || !context.mounted) return;
          await ref.read(mediaRepositoryProvider).deleteNote(n.id!);
          _bump(ref);
          if (!context.mounted) return;
          AppToast.show(context, '已删除笔记');
        },
      );

  void _bump(WidgetRef ref) {
    final tick = ref.read(mediaTickProvider.notifier);
    tick.state = tick.state + 1;
  }

  String _dayTx(int ms) {
    if (ms == 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.month}/${d.day}';
  }
}

/// 复习钮（带到期角标；读数来自 `mediaDueCountProvider`，屏侧不自己数）。
class _ReviewBadge extends ConsumerWidget {
  const _ReviewBadge({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = ref.watch(mediaDueCountProvider).valueOrNull ?? 0;
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          key: MediaNotesPage.kReview,
          icon: const Icon(Icons.style_outlined),
          onPressed: onOpen,
        ),
        if (due > 0)
          Positioned(
            right: 6,
            top: 7,
            child: Container(
              key: const ValueKey('mdn-review-badge'),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$due',
                  style: const TextStyle(
                      fontSize: 8.5, color: Colors.white, fontWeight: FontWeight.w900)),
            ),
          ),
      ],
    );
  }
}

/// 半屏筛选面板（拍板①：六组条件收在这枚钮后面）。
Future<void> showMediaNoteFilterSheet(
  BuildContext context,
  WidgetRef ref,
) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NoteFilterSheet(),
    );

class _NoteFilterSheet extends ConsumerStatefulWidget {
  const _NoteFilterSheet();

  @override
  ConsumerState<_NoteFilterSheet> createState() => _NoteFilterSheetState();
}

class _NoteFilterSheetState extends ConsumerState<_NoteFilterSheet> {
  /// 面板内改的是草稿，「应用筛选」才落到屏——边改边查会让六组条件各帧来自不同快照。
  late MediaNoteFilter _draft = ref.read(mediaNoteFilterProvider);

  static const List<(String?, String)> _kinds = [
    (null, '不限 kind'),
    (MediaItem.kMovie, '电影'),
    (MediaItem.kSeries, '剧集'),
    (MediaItem.kMusic, '音乐'),
    (MediaItem.kGame, '游戏'),
  ];

  void _apply() {
    ref.read(mediaNoteFilterProvider.notifier).state = _draft;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final facet = ref.watch(mediaNoteFacetProvider).valueOrNull ?? const <({String itemId, int count})>[];
    final tags = ref.watch(mediaNoteTagsProvider).valueOrNull ?? const <String>[];
    final titles = <String, String>{
      for (final x in ref.watch(mediaAllItemsProvider).valueOrNull ?? const <MediaItem>[])
        x.id: x.title,
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        key: const ValueKey('mdn-sheet'),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('筛选影音笔记',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              _group('类型', [
                (null, '全部'),
                for (final t in MediaNote.noteTypes)
                  (t, MediaNote.typeLabels[t] ?? t),
              ], _draft.type, (v) => _draft = nfType(_draft, v)),
              _group('类别', [for (final (k, l) in _kinds) (k, l)], _draft.kind,
                  (v) => _draft = nfKind(_draft, v)),
              _group('条目', [
                (null, '全部条目'),
                for (final f in facet)
                  (f.itemId, '${titles[f.itemId] ?? '已删条目'} ${f.count}'),
              ], _draft.itemId, (v) => _draft = nfItem(_draft, v), scroll: true),
              _group('标签', [
                (null, '全部'),
                for (final t in tags) (t, t),
              ], _draft.tag, (v) => _draft = nfTag(_draft, v), scroll: true),
              const SizedBox(height: 10),
              InkWell(
                key: const ValueKey('mdn-star-toggle'),
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _draft = nfStarred(_draft, !_draft.starred)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const Text('只看看过的（标星）',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Switch(
                          value: _draft.starred,
                          onChanged: (v) =>
                              setState(() => _draft = nfStarred(_draft, v))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      key: const ValueKey('mdn-filter-cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton(
                      key: const ValueKey('mdn-filter-reset'),
                      onPressed: () => setState(() => _draft = kMediaNoteFilterAll),
                      child: const Text('清空条件'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('mdn-filter-apply'),
                      onPressed: _apply,
                      child: const Text('应用筛选'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _group(String label, List<(String?, String)> options, String? selected,
      void Function(String?) pick,
      {bool scroll = false}) {
    final chips = [
      for (final (v, l) in options)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: PillChip(
            key: ValueKey('mdn-f-$label-$l'),
            label: l,
            selected: selected == v,
            onTap: () => setState(() => pick(v)),
          ),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          if (scroll)
            SizedBox(
              height: 34,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: chips),
              ),
            )
          else
            Wrap(spacing: 6, runSpacing: 6, children: chips),
        ],
      ),
    );
  }
}
