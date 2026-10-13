part of 'shelf_page.dart';

// 治理G7d1c：主体五视图群自 _ShelfPageState 移入同库扩展（行为零改动·直访私有字段）。
// 圆钮/维度分组 / 视图派发（_body 五态）/ 点按包装与单选切换 / 封面墙卡片 / 列表行。
extension _ShelfViews on _ShelfPageState {
  // ---------------- 主体五视图 ----------------

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

  /// 维度分组渲染（值 → 该组内容）。
  List<Widget> _dimGroups(
    ShelfUI ui,
    List<Book> list,
    BookSession? running,
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
        _body(ui, g.value, running, cs, tokens, pfx: '${g.key}-'),
        const SizedBox(height: 8),
      ],
    ];
  }

  Widget _body(
    ShelfUI ui,
    List<Book> list,
    BookSession? running,
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
        children: [
          for (final b in list)
            _rowItem(ui, b, running, cs, tokens, pfx: pfx),
        ],
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
    // V1.50 分流：本地书点封面＝直接进阅读器（原型 shOpen 包装器同语义），
    // 非本地书行为不变；多选态优先。
    // 批3.5：预载中/已清缓存先走状态守卫（提示或三态弹层），不放行。
    onTap: () async {
      if (ui.batch) {
        _selTap(ui, b);
        return;
      }
      final blocked = await brTapGuarded(context, ref, b);
      if (blocked) return;
      if (!context.mounted) return;
      context.push(b.local ? '/read/reader/${b.id}' : '/read/book/${b.id}');
    },
    // B5（阅读模块批1 · 〇B 触觉锚「长按进管理态」）：长按起手＝一记 mediumImpact，
    // 与影音架 _enterSel 同锚同震；菜单本体不改。
    onLongPress: ui.batch
        ? null
        : () {
            HapticFeedback.mediumImpact();
            showLongPressSheet(context, ref, b);
          },
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
                  showStateOverlay: true,
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

  String _md(int? ms) {
    if (ms == null) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Widget _rowItem(
    ShelfUI ui,
    Book b,
    BookSession? running,
    ColorScheme cs,
    dynamic tokens, {
    String pfx = '',
  }) {
    final qn = (ref.watch(allQuotesProvider).valueOrNull ?? const <BookQuote>[])
        .where((q) => q.bookId == b.id)
        .length;
    // 原型 shListRows 4571：元信息补「读完 MM-DD / 开始 MM-DD」
    final dateSeg = b.startedAt == null
        ? ''
        : ' · ${b.state == Book.kStateDone ? '读完 ${_md(b.endedAt)}' : '开始 ${_md(b.startedAt)}'}';
    final showTimer = b.state == Book.kStateReading && !ui.batch;
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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          b.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      // 原型 brRowBadge：列表行标题后「本地」小胶囊；
                      // 批3.5 三态追加「预载中/已清缓存」琥珀小胶囊。
                      if (b.local) ...[
                        const SizedBox(width: 6),
                        const BrLocalInlineBadge(),
                        if (b.epub != null && b.epub!.state != 'rdy') ...[
                          const SizedBox(width: 4),
                          BrStateInlineBadge(st: b.epub!.state),
                        ],
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${b.author} · ${b.pages} 页 · $qn 条笔记$dateSeg',
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
            // 在读行「开始/结束」计时 mini 钮（原型 4573）
            if (showTimer) ...[
              const SizedBox(width: 8),
              GestureDetector(
                key: ValueKey('sh-row-timer-$pfx${b.id}'),
                onTap: () => readTimerTap(ref, context, target: b),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: cs.surfaceContainerHighest,
                  ),
                  child: Text(
                    running?.bookId == b.id ? '结束' : '开始',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
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
}
