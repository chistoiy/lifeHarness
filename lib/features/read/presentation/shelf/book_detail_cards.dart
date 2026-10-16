part of 'book_detail.dart';

// 治理（高保真批6b·刀3）：三态弹层群关联面自 book_detail 拆出——
// ① _localEpubStrip/_cacheRow（紧凑条＋本地副本与缓存行，原型 brDstrip/brDcache）
//   ＋书摘卡群 _noQuotes/_quoteCard/_qMeta 落同库扩展 _BookDetailCards（G7c 族·
//   行为零改动·直访私有字段）；② showBrLocalInfo（本地文件与缓存说明半屏）整组迁入
// （G7d5 族口径·顶层函数不放宽）。主文件回默认 1200 面，size_budget 登记项按口径删除。

extension _BookDetailCards on _BookDetailPageState {
  /// 本地文件紧凑条（V1.53.2 轮5.3 · 原型 brDstrip）：原「本地 EPUB」整卡
  /// 上移到信息行之下并压成两行 —— 一行格式/体积/说明钮，一行进度/位置/划线 + 三动作。
  /// 未就绪（预载中/已清缓存）时仍保留批3.5 的四态行，重载/重选入口不丢。
  Widget _localEpubStrip(ColorScheme cs, Book b, int hlCount) {
    final ep = b.epub;
    if (ep == null) return const SizedBox.shrink();
    final tokens = context.tokens;
    final sizeMb = '${(ep.size / (1024 * 1024)).toStringAsFixed(1)} MB';
    Widget mini(String key, IconData ic, Color fg, VoidCallback onTap) =>
        GestureDetector(
          key: ValueKey(key),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              border: Border.all(color: fg.withValues(alpha: .35)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(ic, size: 14, color: fg),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('brDstrip'),
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: tokens.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tokens.cardBorder),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      ep.fmt,
                      style: const TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$sizeMb · 无 DRM · 图文混排',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  GestureDetector(
                    key: const ValueKey('brDinfo'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => showBrLocalInfo(context, ref, b, hlCount),
                    child: Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Text(
                        '?',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '进度 ${b.percent}% · 位置 ${bsPosLabel(b)} · 划线 $hlCount 处',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                    ),
                  ),
                  GestureDetector(
                    key: const ValueKey('br-d-open'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () async {
                      if (await brTapGuarded(context, ref, b)) return;
                      if (mounted) context.push('/read/reader/${b.id}');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        gradient: tokens.gradient,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        '打开阅读器',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  mini('br-d-search', Icons.search_rounded, cs.onSurface, () =>
                      brOpenBookSearch(context, ref, b)),
                  const SizedBox(width: 6),
                  mini('br-d-del', Icons.delete_outline_rounded,
                      const Color(0xFFE11D48), () async {
                    // 轮4：弹层 resolve 时提交已落库。全删（或纸质/电子书写 keep
                    // 直接进回收站）后书行已没——详情页不再有空壳可留，出栈回书架；
                    // 本地书 keep＝留架摘缓存，页面随 readTick 重取自然转为无缓存态。
                    await showBrDelSheet(context, ref, b);
                    if (!mounted) return;
                    final nb =
                        await ref.read(readRepositoryProvider).bookById(b.id);
                    if (!mounted) return;
                    if (nb == null || nb.isDeleted) Navigator.of(context).pop();
                  }),
                ],
              ),
            ],
          ),
        ),
        if (ep.state != 'rdy') _cacheRow(cs, b, ep),
      ],
    );
  }

  /// 本地副本与缓存行（原型 brDcache · 批3.5 四态：预载中/已清可读/已清丢失/就绪）。
  Widget _cacheRow(ColorScheme cs, Book b, EpubRef ep) {
    final tokens = context.tokens;
    Widget body;
    switch (ep.state) {
      case 'pre':
        body = Column(
          key: const ValueKey('br-dcache-pre'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '整本预载中 · 分页后台续算 · 点封面可直接进入阅读',
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: Consumer(
                builder: (_, ref2, _) {
                  ref2.watch(epubPreloadProvider);
                  final pr =
                      (ref2.read(epubPreloadProvider).info(b.id)?.pr ?? ep.pr)
                          .clamp(0, 100) /
                      100;
                  return LinearProgressIndicator(
                    value: pr,
                    minHeight: 4,
                    backgroundColor: cs.surfaceContainerHighest,
                  );
                },
              ),
            ),
          ],
        );
      case 'cl':
        final srcOk = (ep.srcPath != null && File(ep.srcPath!).existsSync());
        body = Column(
          key: ValueKey(srcOk ? 'br-dcache-cl' : 'br-dcache-lost'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              srcOk
                  ? '本地副本已清理 · 源文件仍可读 · 记录与书摘完整保留'
                  : '本地副本已清理 · 原文件已不存在 · 记录与书摘完整保留',
              style: TextStyle(
                fontSize: 10,
                height: 1.5,
                color: srcOk ? cs.onSurfaceVariant : const Color(0xFFE11D48),
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              key: ValueKey(srcOk ? 'br-d-reload' : 'br-d-repick'),
              onTap: () => srcOk
                  ? brShowReloadSheet(context, ref, b)
                  : brShowLostSheet(context, ref, b),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  gradient: srcOk ? tokens.gradient : null,
                  color: srcOk ? null : const Color(0xFFF59E0B),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  srcOk ? '重新载入本地副本' : '重新选择文件',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        );
      default:
        body = Row(
          key: const ValueKey('br-dcache-rdy'),
          children: [
            Expanded(
              child: Text(
                '本地副本 + 分页缓存 · 源文件在原始位置保留',
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
            ),
            GestureDetector(
              key: const ValueKey('br-d-clearcache'),
              onTap: () => brShowCacheSheet(context, ref, b),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0x59D97706)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '清理缓存',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFD97706),
                  ),
                ),
              ),
            ),
          ],
        );
    }
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: const Color(0xFFD97706), width: 3),
        ),
      ),
      child: body,
    );
  }


  Widget _noQuotes(ColorScheme cs, dynamic tokens, Book b) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 26),
    decoration: BoxDecoration(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
    ),
    child: Column(
      children: [
        Text('还没有摘录', style: TextStyle(fontSize: 12, color: cs.onSurface)),
        const SizedBox(height: 8),
        GestureDetector(
          key: const ValueKey('bd-add-quote'),
          onTap: () => showQuoteSheet(context, ref, bookId: b.id),
          child: Text(
            '记一条',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: tokens.accent as Color,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _quoteCard(ColorScheme cs, BookQuote q) => GestureDetector(
    key: ValueKey('bd-q-${q.id}'),
    behavior: HitTestBehavior.opaque,
    // §3.4：摘录卡 → 摘录操作弹层（收藏/编辑/转日记/转待办/转笔记/复制/删除）。
    onTap: () => showQuoteOpsSheet(context, ref, q),
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3.5,
            height: q.body.length > 40 ? 60 : 34,
            decoration: BoxDecoration(
              color: Color(0xFF000000 | q.colorInt),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  q.kind == BookQuote.kKindMark ? '「${q.body}」' : q.body,
                  style: kFontBody.apply(TextStyle(
                    fontSize: 12.5,
                    height: 1.55,
                    color: cs.onSurface,
                  )),
                ),
                if (q.thought != null && q.thought!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      q.thought!,
                      style: kFontBody.apply(TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        fontStyle: FontStyle.italic,
                        color: cs.onSurfaceVariant,
                      )),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Row(
                    children: [
                      Expanded(child: _qMeta(cs, q)),
                      // 只在已收藏时显示小星（§3.3 卡片平铺动作清空）。
                      if (q.starred)
                        const Icon(
                          Icons.star_rounded,
                          size: 14,
                          color: Color(0xFFF59E0B),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _qMeta(ColorScheme cs, BookQuote q) {
    final d = DateTime.fromMillisecondsSinceEpoch(q.createdAt);
    return Text(
      [
        if ((q.chapter ?? '').isNotEmpty) q.chapter!,
        if (q.page != null) '${q.page} 页',
        '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      ].join(' · '),
      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
    );
  }

}


/// 轮5.3 · 本地文件与缓存说明半屏（详情页紧凑条「?」入口 · 原型 sheetBrLocalInfo）。
///
/// 原「本地 EPUB」整卡的说明文字收进这里，正文只留两行紧凑条；
/// 清理缓存沿用批3.5 三态弹层（源文件永不删除）。
Future<void> showBrLocalInfo(
  BuildContext context,
  WidgetRef ref,
  Book b,
  int hlCount,
) async {
  final ep = b.epub;
  if (ep == null) return;
  final cs = Theme.of(context).colorScheme;
  final sizeMb = '${(ep.size / (1024 * 1024)).toStringAsFixed(1)} MB';
  final stateTxt = switch (ep.state) {
    'pre' => '整本预载中（点封面可直接进入阅读 · 后台续算）',
    'cl' => '本地副本已清理 · 记录与书摘保留',
    _ => '本地副本 + 分页缓存已就绪',
  };
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true, // F3-10 弹层骨架
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sc) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          key: const ValueKey('sheetBrLocalInfo'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  '本地文件与缓存',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text(
                  ep.fmt,
                  key: const ValueKey('brLiFmt'),
                  style: TextStyle(
                    fontSize: 9.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '文件路径',
              style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                ep.path,
                key: const ValueKey('brLiPath'),
                style: const TextStyle(fontSize: 10.5, height: 1.5),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '体积 / 加密 / 版式',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  '$sizeMb · 无 DRM · 图文混排',
                  key: const ValueKey('brLiMeta'),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '阅读位置 / 划线 / 进度',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  '${bsPosLabel(b)} · $hlCount 处 · ${b.percent}%',
                  key: const ValueKey('brLiPos'),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '删除时询问阅读数据去留：默认保留（释放源文件与缓存，卡片留在书架，重新导入自动挂回），'
              '或全量删除（阅读数据一并删除，书籍记录进回收站）。',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.6,
                color: cs.onSurfaceVariant,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '缓存：$stateTxt · 只回收分页表与私有副本，随时可重新载入。',
                key: const ValueKey('brLiCache'),
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.6,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('brLiOk'),
                    onPressed: () => Navigator.of(sc).pop(),
                    child: const Text('知道了'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('brLiClean'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFD97706),
                      side: const BorderSide(color: Color(0x66D97706)),
                    ),
                    onPressed: () {
                      Navigator.of(sc).pop();
                      brShowCacheSheet(context, ref, b);
                    },
                    child: const Text('清理缓存'),
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
