import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/book.dart';
import '../domain/book_quote.dart';
import '../domain/shelf_query.dart';
import 'read_actions.dart';
import 'read_providers.dart';
import 'read_sheets.dart';
import 'widgets/bs_cover.dart';

/// 书架视图循环 5 态（封面墙3 · 封面墙4 · 书脊 · 时间线 · 列表）。
const kShelfViews = ['wall', 'wall4', 'spine', 'time', 'rows'];
const kShelfViewLabels = {
  'wall': '封面墙',
  'wall4': '封面墙·4列',
  'spine': '书脊',
  'time': '时间线',
  'rows': '列表',
};

/// 排序 / 维度键（与原型 SH_SORTS / SH_DIMS 对齐）。
const kShelfSorts = [
  ('recent', '最近阅读'),
  ('prog', '按进度'),
  ('rate', '按评分'),
  ('added', '入架顺序'),
  ('name', '书名（拼音）'),
  ('pages', '总页数'),
];
const kShelfDims = [
  ('none', '默认'),
  ('st', '状态'),
  ('tag', '标签'),
  ('rate', '评分'),
  ('author', '作者'),
  ('pub', '出版社'),
  ('src', '来源'),
  ('grp', '分组'),
];

class ShelfUI {
  const ShelfUI({
    this.view = 'wall',
    this.st,
    this.kw = '',
    this.dim = 'none',
    this.dimVal = '',
    this.sort = 'recent',
    this.batch = false,
    this.sel = const {},
    this.yearBoxOpen = false,
  });

  final String view;
  final String? st;
  final String kw;
  final String dim;
  final String dimVal;
  final String sort;
  final bool batch;
  final Set<String> sel;
  final bool yearBoxOpen;

  ShelfUI copyWith({
    String? view,
    String? Function()? st,
    String? kw,
    String? dim,
    String? dimVal,
    String? sort,
    bool? batch,
    Set<String>? sel,
    bool? yearBoxOpen,
  }) => ShelfUI(
    view: view ?? this.view,
    st: st != null ? st() : this.st,
    kw: kw ?? this.kw,
    dim: dim ?? this.dim,
    dimVal: dimVal ?? this.dimVal,
    sort: sort ?? this.sort,
    batch: batch ?? this.batch,
    sel: sel ?? this.sel,
    yearBoxOpen: yearBoxOpen ?? this.yearBoxOpen,
  );

  ShelfQuery toQuery() =>
      ShelfQuery(state: st, kw: kw, dim: dim, dimVal: dimVal, sort: sort);
}

final shelfUiProvider = StateProvider<ShelfUI>((ref) => const ShelfUI());

/// 书架页（原型 p-bookshelf · §3.1 信息架构：目标卡→搜索行→分区chips→封面墙）。
class ShelfPage extends ConsumerStatefulWidget {
  const ShelfPage({super.key});

  @override
  ConsumerState<ShelfPage> createState() => _ShelfPageState();
}

class _ShelfPageState extends ConsumerState<ShelfPage> {
  final _kwCtl = TextEditingController();
  bool _tabBooted = false;

  @override
  void dispose() {
    _kwCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(shelfUiProvider);
    // read.openTab（§6 外观与启动）：进书架默认落到的分区；原型 BS_SET 默认「在读」，未设过同样生效。
    if (!_tabBooted) {
      _tabBooted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final t = await ref.read(readRepositoryProvider).kv('read.openTab') ??
            '在读';
        if (mounted &&
            ref.read(shelfUiProvider).st == null &&
            Book.states.contains(t)) {
          ref.read(shelfUiProvider.notifier).state =
              ref.read(shelfUiProvider).copyWith(st: () => t);
        }
      });
    }
    final tokens = context.tokens;
    final cs = Theme.of(context).colorScheme;
    final all = (ref.watch(booksProvider).valueOrNull ?? const <Book>[])
        .where((b) => !b.isDeleted)
        .toList();
    final w = ref.watch(workbenchProvider).valueOrNull;
    final counts = ShelfQuery.countsByState(all);
    final list = ui.toQuery().apply(all);
    final dimVals = ui.dim == 'none'
        ? const <String>[]
        : ShelfQuery.dimValues(ui.dim, all);

    return Scaffold(
      appBar: AppBar(
        title: const Text('书架'),
        actions: [
          IconButton(
            key: const ValueKey('sh-manage'),
            tooltip: '管理',
            onPressed: () => ref.read(shelfUiProvider.notifier).state = ui
                .copyWith(batch: !ui.batch, sel: const {}),
            icon: Icon(
              ui.batch ? BsIcons.check : BsIcons.manage,
              color: ui.batch ? tokens.accent : null,
            ),
          ),
        ],
      ),
      floatingActionButton: ui.batch
          ? null
          : GradShelfFab(onTap: () => showAddBookSheet(context, ref)),
      bottomNavigationBar: ui.batch ? _batchBar(ui, cs, tokens) : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
        children: [
          _goalCard(w, tokens),
          const SizedBox(height: 10),
          // 搜索行：输入 + 视图循环 + ⇅ 面板
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    key: const ValueKey('sh-kw'),
                    controller: _kwCtl,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: InputDecoration(
                      hintText: '搜索书名 / 作者',
                      hintStyle: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                      prefixIcon: const Icon(BsIcons.search, size: 17),
                      prefixIconConstraints: const BoxConstraints(minWidth: 36),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      filled: true,
                      fillColor: cs.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (v) => ref.read(shelfUiProvider.notifier).state =
                        ref.read(shelfUiProvider).copyWith(kw: v),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _roundBtn(
                'sh-view',
                BsIcons.view,
                kShelfViewLabels[ui.view]!,
                () {
                  final next =
                      kShelfViews[(kShelfViews.indexOf(ui.view) + 1) %
                          kShelfViews.length];
                  ref.read(shelfUiProvider.notifier).state = ref
                      .read(shelfUiProvider)
                      .copyWith(view: next);
                },
              ),
              const SizedBox(width: 8),
              _roundBtn(
                'sh-panel',
                BsIcons.swap,
                '排序与分组',
                () => _openPanel(context, ui),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 分区 chips（带计数·常驻一行）
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final s in ['全部', ...Book.states])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      key: ValueKey('sh-chip-$s'),
                      onTap: () =>
                          ref.read(shelfUiProvider.notifier).state = ref
                              .read(shelfUiProvider)
                              .copyWith(st: () => s == '全部' ? null : s),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: (s == '全部' && ui.st == null) || ui.st == s
                              ? tokens.accent.withValues(alpha: .12)
                              : cs.surfaceContainerHigh,
                          border: Border.all(
                            color: (s == '全部' && ui.st == null) || ui.st == s
                                ? tokens.accent
                                : Colors.transparent,
                          ),
                        ),
                        child: Text(
                          s == '全部'
                              ? '全部 ${all.length}'
                              : '$s ${counts[s] ?? 0}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: (s == '全部' && ui.st == null) || ui.st == s
                                ? tokens.accent
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 维度值行（只在维度≠默认时出现 §3.1-1）
          if (ui.dim != 'none') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final v in dimVals)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              key: ValueKey('sh-dim-$v'),
                              onTap: () =>
                                  ref.read(shelfUiProvider.notifier).state = ref
                                      .read(shelfUiProvider)
                                      .copyWith(
                                        dimVal: ui.dimVal == v ? '' : v,
                                      ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color: ui.dimVal == v
                                      ? tokens.accent
                                      : cs.surfaceContainerHigh,
                                ),
                                child: Text(
                                  v,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: ui.dimVal == v
                                        ? Colors.white
                                        : cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                GestureDetector(
                  key: const ValueKey('sh-dim-reset'),
                  onTap: () => ref.read(shelfUiProvider.notifier).state = ref
                      .read(shelfUiProvider)
                      .copyWith(dim: 'none', dimVal: ''),
                  child: Text(
                    '回到默认',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: tokens.accent,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          if (list.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 30),
              decoration: _cardDeco(context),
              child: Center(
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant,
                    ),
                    children: [
                      const TextSpan(text: '没有符合条件的书 · '),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: GestureDetector(
                          key: const ValueKey('sh-reset'),
                          onTap: () {
                            _kwCtl.clear();
                            ref.read(shelfUiProvider.notifier).state =
                                const ShelfUI();
                          },
                          child: Text(
                            '清空筛选',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: tokens.accent,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (ui.dim != 'none' && ui.dimVal.isEmpty)
            ..._dimGroups(ui, list, cs, tokens)
          else
            _body(ui, list, cs, tokens),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '${list.length} 本 · ${ui.st ?? '全部'}',
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDeco(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
    );
  }

  Widget _goalCard(WorkbenchData? w, dynamic tokens) {
    final done = w?.doneThisYear ?? 0;
    final goal = w?.goalBooks ?? 50;
    final ui = ref.watch(shelfUiProvider);
    final need = (goal - done).clamp(0, goal);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(context),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 52,
                height: 52,
                child: CustomPaint(
                  painter: _GoalRingPainter(
                    frac: goal == 0 ? 0 : (done / goal).clamp(0.0, 1.0),
                    color: (tokens as dynamic).accent,
                  ),
                  child: Center(
                    child: Text(
                      '${goal == 0 ? 0 : (done / goal * 100).round()}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: (tokens as dynamic).accent,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '年度目标 · ${DateTime.now().year}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$done / $goal 本 · ${need > 0 ? '还差 $need 本' : '目标已达成'}',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                key: const ValueKey('sh-goal-adjust'),
                onTap: () => showGoalSheet(context, ref),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: (tokens as dynamic).accent),
                  ),
                  child: Text(
                    '调整',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: (tokens as dynamic).accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (done > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  key: const ValueKey('sh-yearbox-toggle'),
                  onTap: () => ref.read(shelfUiProvider.notifier).state = ui
                      .copyWith(yearBoxOpen: !ui.yearBoxOpen),
                  child: Text(
                    ui.yearBoxOpen ? '今年读完 ▴' : '今年读完 ▾',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: (tokens as dynamic).accent,
                    ),
                  ),
                ),
              ),
            ),
          if (ui.yearBoxOpen && w != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final b
                      in w.books
                          .where(
                            (b) =>
                                !b.isDeleted &&
                                b.state == Book.kStateDone &&
                                b.endedAt != null &&
                                DateTime.fromMillisecondsSinceEpoch(
                                      b.endedAt!,
                                    ).year ==
                                    DateTime.now().year,
                          )
                          .toList())
                    GestureDetector(
                      onTap: () => context.push('/read/book/${b.id}'),
                      child: Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              kBsCov[b.paletteIdx].$1,
                              kBsCov[b.paletteIdx].$2,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Tooltip(
                          message: b.title,
                          child: const Icon(
                            Icons.book_outlined,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _roundBtn(String key, IconData ic, String tip, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tip,
      child: GestureDetector(
        key: ValueKey(key),
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Icon(ic, size: 17, color: cs.onSurface),
        ),
      ),
    );
  }

  void _openPanel(BuildContext context, ShelfUI ui) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Consumer(
            builder: (_, ref2, _) {
              Widget section(String label) => Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 6),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(sheetCtx).colorScheme.onSurfaceVariant,
                  ),
                ),
              );
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '排序与分组',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(sheetCtx).colorScheme.onSurface,
                    ),
                  ),
                  section('排序'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (k, t) in kShelfSorts)
                        _panelChip(
                          sheetCtx,
                          'panel-sort-$k',
                          t,
                          ui.sort == k,
                          () {
                            ref2.read(shelfUiProvider.notifier).state = ref2
                                .read(shelfUiProvider)
                                .copyWith(sort: k);
                            Navigator.of(sheetCtx).pop();
                          },
                        ),
                    ],
                  ),
                  section('分组维度'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (k, t) in kShelfDims)
                        _panelChip(
                          sheetCtx,
                          'panel-dim-$k',
                          t,
                          ui.dim == k,
                          () {
                            ref2.read(shelfUiProvider.notifier).state = ref2
                                .read(shelfUiProvider)
                                .copyWith(dim: k, dimVal: '');
                            Navigator.of(sheetCtx).pop();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _panelChip(
    BuildContext context,
    String key,
    String label,
    bool on,
    VoidCallback onTap,
  ) => GestureDetector(
    key: ValueKey(key),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: on
            ? context.tokens.accent.withValues(alpha: .12)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border.all(
          color: on ? context.tokens.accent : Colors.transparent,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: on ? context.tokens.accent : null,
        ),
      ),
    ),
  );

  /// 维度分组渲染（值 → 该组内容）。
  List<Widget> _dimGroups(
    ShelfUI ui,
    List<Book> list,
    ColorScheme cs,
    dynamic tokens,
  ) {
    final q = ui.toQuery();
    final groups = <String, List<Book>>{};
    for (final b in list) {
      for (final v in q.dimValuesOf(b)) {
        (groups[v] ??= []).add(b);
      }
    }
    return [
      for (final g in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 4),
          child: Text(
            '${g.key} · ${g.value.length} 本',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        _body(ui, g.value, cs, tokens, pfx: '${g.key}-'),
        const SizedBox(height: 8),
      ],
    ];
  }

  Widget _body(
    ShelfUI ui,
    List<Book> list,
    ColorScheme cs,
    dynamic tokens, {
    String pfx = '',
  }) {
    // read.wallCols（§6 外观与启动）：封面墙列数随设置 3/4/5；wall4 为固定 4 列紧凑态。
    final wallKv =
        int.tryParse(
              ref.watch(readKvProvider(('read.wallCols', '3'))).valueOrNull ??
              '3',
            ) ??
            3;
    final wallCols = ui.view == 'wall4' ? 4 : wallKv;
    return switch (ui.view) {
      'spine' => _spineView(list, pfx),
      'time' => _timelineView(list, cs),
      'rows' => Column(
        children: [for (final b in list) _rowItem(ui, b, cs, tokens, pfx: pfx)],
      ),
      _ => GridView.count(
        key: ValueKey('sh-grid-$wallCols-$pfx'),
        crossAxisCount: wallCols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: .62,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        children: [
          for (final b in list) _wallCard(ui, b, cs, tokens, pfx: pfx),
        ],
      ),
    };
  }

  Widget _tapWrap(
    ShelfUI ui,
    Book b, {
    required Widget child,
    String pfx = '',
  }) => GestureDetector(
    key: ValueKey('sh-item-$pfx${b.id}'),
    onTap: () => ui.batch ? _selTap(ui, b) : context.push('/read/book/${b.id}'),
    onLongPress: ui.batch ? null : () => showLongPressSheet(context, ref, b),
    child: child,
  );

  void _selTap(ShelfUI ui, Book b) {
    final sel = {...ui.sel};
    sel.contains(b.id) ? sel.remove(b.id) : sel.add(b.id);
    ref.read(shelfUiProvider.notifier).state = ui.copyWith(sel: sel);
  }

  Widget _wallCard(
    ShelfUI ui,
    Book b,
    ColorScheme cs,
    dynamic tokens, {
    String pfx = '',
  }) => _tapWrap(
    ui,
    b,
    pfx: pfx,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: BsCover(
                  book: b,
                  width: double.infinity,
                  height: double.infinity,
                  onBadgeTap: ui.batch
                      ? null
                      : () => cycleBookState(context, ref, b),
                ),
              ),
              if (ui.batch)
                Positioned(
                  right: 5,
                  bottom: 5,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ui.sel.contains(b.id)
                          ? tokens.accent as Color
                          : Colors.white70,
                    ),
                    child: ui.sel.contains(b.id)
                        ? const Icon(
                            BsIcons.check,
                            size: 12,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 5, bottom: 4),
          child: Text(
            b.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 4),
        BkPctBar(book: b),
      ],
    ),
  );

  Widget _rowItem(
    ShelfUI ui,
    Book b,
    ColorScheme cs,
    dynamic tokens, {
    String pfx = '',
  }) {
    final qn = (ref.watch(allQuotesProvider).valueOrNull ?? const <BookQuote>[])
        .where((q) => q.bookId == b.id)
        .length;
    return _tapWrap(
      ui,
      b,
      pfx: pfx,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: _cardDeco(context),
        child: Row(
          children: [
            BsCover(
              book: b,
              width: 36,
              height: 52,
              radius: 7,
              showAuthor: false,
              badgeSize: 7,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    b.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${b.author} · ${b.pages} 页 · $qn 条笔记',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                  if (b.state == Book.kStateReading) ...[
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: b.percent / 100,
                        minHeight: 4,
                        backgroundColor: cs.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: bsStateColor(b.state).withValues(alpha: .12),
              ),
              child: Text(
                b.state,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: bsStateColor(b.state),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _spineView(List<Book> list, String pfx) {
    double h(Book b) => switch (b.state) {
      '在读' => 112,
      '已读' => 132,
      '弃读' => 78,
      _ => 96,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: _cardDeco(context),
      child: SizedBox(
        height: 150,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final b in list)
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: _tapWrap(
                    ref.watch(shelfUiProvider),
                    b,
                    pfx: pfx,
                    child: GestureDetector(
                      child: Container(
                        width: 30,
                        height: h(b),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              kBsCov[b.paletteIdx].$3,
                              kBsCov[b.paletteIdx].$3.withValues(alpha: .8),
                            ],
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: RotatedBox(
                                quarterTurns: 3,
                                child: Text(
                                  b.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 4,
                              child: Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: b.state == Book.kStateReading
                                      ? Colors.white
                                      : Colors.white38,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timelineView(List<Book> list, ColorScheme cs) {
    final quotes =
        ref.watch(allQuotesProvider).valueOrNull ?? const <BookQuote>[];
    final byId = {for (final b in list) b.id: b};
    final events = <(DateTime, String)>[];
    for (final b in list) {
      if (b.startedAt != null) {
        events.add((
          DateTime.fromMillisecondsSinceEpoch(b.startedAt!),
          '开始读《${b.title}》',
        ));
      }
      if (b.state == Book.kStateDone && b.endedAt != null) {
        events.add((
          DateTime.fromMillisecondsSinceEpoch(b.endedAt!),
          '读完《${b.title}》',
        ));
      }
    }
    for (final q in quotes.where((q) => byId.containsKey(q.bookId))) {
      events.add((
        DateTime.fromMillisecondsSinceEpoch(q.createdAt),
        '摘录 · 《${byId[q.bookId]!.title}》',
      ));
    }
    events.sort((a, b) => b.$1.compareTo(a.$1));
    // 时间线窗口（§6 read.tlRange 本月/近半年/全年 × read.tlDays 7/14/30 取交集）。
    final range =
        ref
            .watch(readKvProvider(('read.tlRange', '近半年')))
            .valueOrNull ??
        '近半年';
    final rangeDays = switch (range) {
      '本月' => 31,
      '近半年' => 183,
      _ => 366,
    };
    final tlDays =
        int.tryParse(
              ref.watch(readKvProvider(('read.tlDays', '14'))).valueOrNull ??
              '14',
            ) ??
            14;
    final win = tlDays < rangeDays ? tlDays : rangeDays;
    events.removeWhere(
      (e) => e.$1.isBefore(DateTime.now().subtract(Duration(days: win))),
    );
    final days = <String, List<String>>{};
    for (final (d, t) in events) {
      final k =
          '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      (days[k] ??= []).add(t);
    }
    if (days.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 30),
        decoration: _cardDeco(context),
        child: Text(
          '还没有阅读事件',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final g in days.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 46,
                  child: Text(
                    g.key,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: _cardDeco(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final t in g.value)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              t,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget? _batchBar(ShelfUI ui, ColorScheme cs, dynamic tokens) {
    if (!ui.batch) return null;
    final ids = ui.sel.toList();
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: Row(
          children: [
            Text(
              '已选 ${ids.length}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: cs.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            for (final s in Book.states)
              TextButton(
                key: ValueKey('bat-$s'),
                onPressed: ids.isEmpty
                    ? null
                    : () async {
                        await ref
                            .read(readRepositoryProvider)
                            .bulkSetState(ids, s);
                        ref.read(readTickProvider.notifier).state++;
                        if (mounted) {
                          readToast(context, '已移入 $s');
                          ref.read(shelfUiProvider.notifier).state = ui
                              .copyWith(batch: false, sel: const {});
                        }
                      },
                child: Text('→$s', style: const TextStyle(fontSize: 11.5)),
              ),
          ],
        ),
      ),
    );
  }
}

/// 书架 FAB（＋ 新书）。
class GradShelfFab extends StatelessWidget {
  const GradShelfFab({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return GestureDetector(
      key: const ValueKey('sh-add'),
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: tokens.gradient,
          boxShadow: [
            BoxShadow(
              color: tokens.accent.withValues(alpha: .35),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
      ),
    );
  }
}

/// 长按书籍菜单：项与顺序来自设置（read.longPress · §6 · sheetLongPress 弹层自带
/// 「调整长按菜单」入口）。可选全集＝LP_ALL，未勾选项不渲染。
const kLpAll = ['计时', '记摘录', '改分区', '移书单', '标记读完', '多选', '删除'];
const kLpDefault = '计时,记摘录,改分区,移书单,删除';

Future<void> showLongPressSheet(BuildContext context, WidgetRef ref, Book b) {
  return showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Consumer(
          builder: (_, ref2, _) {
            final raw =
                ref2
                    .watch(readKvProvider(('read.longPress', kLpDefault)))
                    .valueOrNull ??
                kLpDefault;
            final items =
                raw.split(',').where(kLpAll.contains).toList();
            Widget row(String key, String label, VoidCallback onTap) =>
                ListTile(
                  key: ValueKey(key),
                  dense: true,
                  title: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: onTap,
                );
            Widget rowFor(String name) => switch (name) {
              '计时' => row('lp-timer', '计时', () {
                Navigator.of(sheetCtx).pop();
                readTimerTap(ref2, context, target: b);
              }),
              '记摘录' => row('lp-quote', '记摘录', () {
                Navigator.of(sheetCtx).pop();
                showQuoteSheet(context, ref2, bookId: b.id);
              }),
              '改分区' => row('lp-state', '改分区 · ${b.state}', () {
                Navigator.of(sheetCtx).pop();
                cycleBookState(context, ref2, b);
              }),
              '移书单' => row('lp-list', '移书单', () {
                Navigator.of(sheetCtx).pop();
                showMoveToListSheet(context, ref2, b);
              }),
              '标记读完' => row('lp-done', '标记读完', () async {
                await ref2.read(readRepositoryProvider).bulkSetState(
                  [b.id],
                  Book.kStateDone,
                );
                ref2.read(readTickProvider.notifier).state++;
                if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                if (context.mounted) {
                  readToast(context, '《${b.title}》已标记读完 · 自动进年度书单');
                }
              }),
              '多选' => row('lp-multi', '多选', () {
                ref2.read(shelfUiProvider.notifier).state =
                    ref2.read(shelfUiProvider).copyWith(
                      batch: true,
                      sel: {b.id},
                    );
                if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
              }),
              _ => row('lp-del', '删除', () async {
                await ref2.read(readRepositoryProvider).softDeleteBooks([
                  b.id,
                ]);
                ref2.read(readTickProvider.notifier).state++;
                if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                if (context.mounted) readToast(context, '已移除《${b.title}》');
              }),
            };
            return SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '《${b.title}》',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                for (final n in items) rowFor(n),
                TextButton(
                  key: const ValueKey('lp-edit-menu'),
                  onPressed: () {
                    Navigator.of(sheetCtx).pop();
                    if (context.mounted) context.push('/read/settings');
                  },
                  child: Text(
                    '调整长按菜单',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            );
          },
        ),
      ),
    ),
  );
}

class _GoalRingPainter extends CustomPainter {
  _GoalRingPainter({required this.frac, required this.color});
  final double frac;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 4;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = color.withValues(alpha: .15),
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -1.5708,
      6.2832 * frac,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_GoalRingPainter old) => old.frac != frac;
}
