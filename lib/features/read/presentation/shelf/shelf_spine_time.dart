part of 'shelf_page.dart';

// 治理G7d1d：书脊视图与时间线视图自 _ShelfPageState 移入同库扩展（行为零改动）。
// 书脊列（含封面可用性判定 _hasCover）/ 按月分组的阅读时间线。
extension _ShelfSpineTime on _ShelfPageState {
  Widget _spineView(List<Book> list, String pfx) {
    double h(Book b) => switch (b.state) {
      '在读' => 112,
      '已读' => 132,
      '弃读' => 78,
      _ => 96,
    };
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: _cardDeco(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
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
                          // F3-8：命中槽宽 35（书脊视觉 30 居中，邻书间隙 5 归槽内，不互叠）。
                          child: SizedBox(
                            width: 35,
                            height: h(b),
                            child: Center(
                              child: Container(
                                width: 30,
                                height: h(b),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              image: _hasCover(b)
                                  ? DecorationImage(
                                      image: FileImage(File(b.coverPath!)),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                              gradient: _hasCover(b)
                                  ? null
                                  : LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        kBsCov[b.paletteIdx].$3,
                                        kBsCov[b.paletteIdx].$3.withValues(
                                          alpha: .8,
                                        ),
                                      ],
                                    ),
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
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
                                // 原型 shSpine 本地书右下白圆点（u 元素 5px）。
                                if (b.local)
                                  Positioned(
                                    right: 2,
                                    bottom: 2,
                                    child: Container(
                                      key: ValueKey('sh-spine-local-${b.id}'),
                                      width: 5,
                                      height: 5,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 原型 4569 说明行（照抄）
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '书脊高度＝总页数 · 白点＝在读 · 点书脊看详情，长按进多选',
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  bool _hasCover(Book b) =>
      (b.coverPath?.isNotEmpty ?? false) && File(b.coverPath!).existsSync();

  /// 时间线（原型 bsEvents 4614-4622 + shTimeline 4623-4631 全量口径：
  /// 开始 / 读完（+页数+购书 ¥）/ 评分 / 摘录（划线「」·感想前缀·原文 46 字）/ 会话（最近 6 次）
  /// 五类事件；日头「M月D日 · N 条」；每卡 图标 + 事件行 + 书名·作者副行、点卡进详情；
  /// 尾行「共 N 条 · 显示最近 M 天 · 范围可在阅读设置里调」；空态「这段时间没有阅读事件」）。
  Widget _timelineView(List<Book> list, ColorScheme cs) {
    final quotes =
        ref.watch(allQuotesProvider).valueOrNull ?? const <BookQuote>[];
    final sessions =
        ref.watch(shelfSessionsProvider).valueOrNull ??
        const <BookSession>[];
    final byId = {for (final b in list) b.id: b};
    // F1-5：read.tlRange 口径统一为英文枚举（month/half/year，原型 BS_SET 口径）；
    // 兼容旧中文存量值（本月/近半年/全年）→ 映射到同窗口，不再回写。
    final rangeRaw =
        ref.watch(readKvProvider(('read.tlRange', 'half'))).valueOrNull ??
        'half';
    final tlDays =
        int.tryParse(
              ref.watch(readKvProvider(('read.tlDays', '14'))).valueOrNull ??
              '14',
            ) ??
            14;
    // read.tlRange 窗口过滤 → 按日分组倒序 → 取最近 tlDays 天（原型 DS slice 口径）。
    final winDays = switch (rangeRaw) {
      'month' || '本月' => 31,
      'half' || '近半年' => 183,
      _ => 366, // year / 全年 / 未知
    };
    final fromT = DateTime.now().subtract(Duration(days: winDays));
    final events = <_TlEv>[];
    void add(int? ms, IconData ic, String t, Book b) {
      if (ms == null) return;
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
      if (d.isBefore(fromT)) return;
      events.add((d, ic, t, b));
    }
    for (final b in list) {
      add(b.startedAt, Icons.auto_stories_outlined, '开始读《${b.title}》', b);
      if (b.state == Book.kStateDone) {
        final fee = b.fee > 0
            ? ' · 购书 ¥${b.fee % 1 == 0 ? b.fee.toInt() : b.fee}'
            : '';
        add(
          b.endedAt,
          Icons.check_circle_outline,
          '读完《${b.title}》· ${b.pages} 页$fee',
          b,
        );
      }
      if (b.rating > 0) {
        final fin = (b.finalNote ?? '').trim().isNotEmpty
            ? b.finalNote!.trim()
            : (b.authorNote ?? '');
        add(
          b.endedAt ?? b.startedAt ?? b.lastReadAt,
          Icons.star_border,
          '评了 ${b.rating % 1 == 0 ? b.rating.toInt() : b.rating} 分：$fin',
          b,
        );
      }
      for (final q in quotes.where((q) => byId.containsKey(q.bookId))) {
        final t = q.body.length > 46 ? q.body.substring(0, 46) : q.body;
        add(
          q.createdAt,
          Icons.format_quote_outlined,
          q.kind == BookQuote.kKindMark ? '「$t」' : '想法：$t',
          byId[q.bookId]!,
        );
      }
      final closed = sessions
          .where((s) => s.bookId == b.id && s.endedAt != null)
          .toList();
      for (final s in (closed.length > 6
          ? closed.sublist(closed.length - 6)
          : closed)) {
        final pp = s.fromPage != null && s.toPage != null
            ? ' · P${s.fromPage}→${s.toPage}'
            : '';
        // 轮5.2②：会话起止章节/百分比由阅读器退出时自动记录。
        final ch = s.toChapter ?? s.fromChapter;
        final pc = s.fromPct != null && s.toPct != null
            ? ' · ${s.fromPct!.round()}%→${s.toPct!.round()}%'
            : '';
        add(
          s.endedAt,
          Icons.timer_outlined,
          '读了 ${s.billedMinutes} 分钟'
              '${ch == null ? '' : ' · $ch'}$pp$pc',
          b,
        );
      }
    }
    events.sort((a, b) => b.$1.compareTo(a.$1));
    final days = <String, List<_TlEv>>{};
    for (final e in events) {
      final d = e.$1;
      final k =
          '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      (days[k] ??= []).add(e);
    }
    final shown = days.entries.take(tlDays < 1 ? 14 : tlDays).toList();
    if (shown.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: _cardDeco(context),
        child: Text(
          '这段时间没有阅读事件',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (gi, g) in shown.indexed)
          Padding(
            padding: EdgeInsets.only(top: gi == 0 ? 0 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 日头行（原型：M月D日 · N 条 + 分隔线）
                Row(
                  key: ValueKey('sh-tl-day-${g.key}'),
                  children: [
                    Text(
                      '${int.parse(g.key.substring(0, 2))}月${int.parse(g.key.substring(3))}日',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${g.value.length} 条',
                      style: TextStyle(
                        fontSize: 9.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 1,
                        margin: const EdgeInsets.only(left: 8),
                        color: cs.outlineVariant.withValues(alpha: .5),
                      ),
                    ),
                  ],
                ),
                for (final (ei, e) in g.value.indexed)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: GestureDetector(
                      key: ValueKey('sh-tl-ev-${g.key}-$ei'),
                      onTap: () => context.push('/read/book/${e.$4.id}'),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: _cardDeco(context),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              margin: const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: .08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                e.$2,
                                size: 13,
                                color: cs.primary,
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    e.$3,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      height: 1.45,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${e.$4.title} · ${e.$4.author}',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: SizedBox(
            width: double.infinity,
            child: Text(
              '共 ${events.length} 条 · 显示最近 ${shown.length} 天 · 范围可在阅读设置里调',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }
}
