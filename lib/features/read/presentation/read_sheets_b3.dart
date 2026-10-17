part of 'read_sheets.dart';

/// 批3 弹层：摘录表单（真机验收轮1d：半屏弹层改全屏页 · 新增＝编辑同一张 ·
/// 书/章节/页码/创建时间/原文/想法/识图·加图·剪贴板/颜色分类/标签多选 · §3.4 表单三处联动）/
/// 摘录操作弹层（sheetQuoteOps · L5 分流）/ 艾宾浩斯复习（sheetReview 翻面卡）。

// ============================ 摘录操作弹层（sheetQuoteOps · L5） ============================

Future<void> showQuoteOpsSheet(
  BuildContext context,
  WidgetRef ref,
  BookQuote q,
) => _sheet<void>(
  context,
  Consumer(
    builder: (sheetCtx, ref, _) {
      final cs = Theme.of(
        sheetCtx,
      ).colorScheme;
      final books = ref.watch(booksProvider).valueOrNull ?? const <Book>[];
      final b = books.where((x) => x.id == q.bookId).firstOrNull;
      final repo = ref.read(readRepositoryProvider);

      Future<void> act(
        Future<void> Function() run, {
        String? toastMsg,
        bool close = true,
      }) async {
        await run();
        ref.read(readTickProvider.notifier).state++;
        if (close && sheetCtx.mounted) Navigator.of(sheetCtx).pop();
        if (close && context.mounted && toastMsg != null) {
          readToast(context, toastMsg);
        }
      }

      void edit() {
        Navigator.of(sheetCtx).pop();
        showQuoteEditPage(context, ref, editing: q);
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SheetTitle(q.kind == BookQuote.kKindMark ? '划线操作' : '感想操作'),
          Text(
            '${b?.title ?? ''} · ${q.chapter ?? '未分章'}'
            '${q.page == null ? '' : ' · P${q.page}'}',
            style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          _OpRow(
            keyName: 'qo-star',
            icon: q.starred ? Icons.star_rounded : Icons.star_border_rounded,
            text: '收藏 / 取消收藏',
            trailing: q.starred ? '已收藏' : null,
            onTap: () => act(
              () => repo.setQuoteStarred(q.id!, !q.starred),
              toastMsg: q.starred ? '已取消收藏' : '已收藏 · 复习卡优先出这条',
            ),
          ),
          _OpRow(
            keyName: 'qo-edit',
            icon: Icons.edit_outlined,
            text: '编辑',
            onTap: edit,
          ),
          if (b != null) ...[
            _OpRow(
              keyName: 'qo-diary',
              icon: Icons.book_outlined,
              text: '插入今日日记',
              onTap: () => act(
                () => repo.quoteToDiary(q, b).then((_) {}),
                toastMsg: '已插入今日日记草稿',
              ),
            ),
            _OpRow(
              keyName: 'qo-todo',
              icon: Icons.check_circle_outline,
              text: '生成待办',
              onTap: () => act(
                () => repo.quoteToTodo(q, b).then((_) {}),
                toastMsg: '已生成待办（无截止日）',
              ),
            ),
            _OpRow(
              keyName: 'qo-note',
              icon: BsIcons.list,
              text: '转存为笔记',
              onTap: () => act(
                () => repo.quoteToNote(q, b).then((_) {}),
                toastMsg: '已转存为笔记',
              ),
            ),
          ],
          _OpRow(
            keyName: 'qo-copy',
            icon: Icons.copy_all_outlined,
            text: '复制原文',
            onTap: () => act(() async {
              await Clipboard.setData(
                ClipboardData(
                  text: q.thought == null ? q.body : '${q.body}\n\n${q.thought}',
                ),
              );
            }, toastMsg: '原文已复制', close: false),
          ),
          _OpRow(
            keyName: 'qo-del',
            icon: BsIcons.trash,
            text: '删除',
            danger: true,
            onTap: () => act(
              () => repo.softDeleteQuote(q.id!),
              toastMsg: '已删除这条记录',
            ),
          ),
          const SizedBox(height: 12),
        ],
      );
    },
  ),
);

class _OpRow extends StatelessWidget {
  const _OpRow({
    required this.keyName,
    required this.icon,
    required this.text,
    required this.onTap,
    this.trailing,
    this.danger = false,
  });
  final String keyName;
  final IconData icon;
  final String text;
  final String? trailing;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        key: ValueKey(keyName),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: danger ? cs.error : cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: danger ? cs.error : cs.onSurface,
                  ),
                ),
              ),
              if (trailing != null)
                Text(
                  trailing!,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF59E0B),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================ 摘录复习（艾宾浩斯 1/3/7 · 3D 翻面卡） ============================

/// 原型 qtReview(4880)：到期队列为空不开弹层，直接 toast。
Future<void> showReviewSheet(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(readRepositoryProvider);
  final due = await repo.dueReviews();
  if (!context.mounted) return;
  if (due.isEmpty) {
    readToast(context, '还没有到期的摘录');
    return;
  }
  await _sheet<void>(context, const _ReviewSheet());
}

class _ReviewSheet extends ConsumerStatefulWidget {
  const _ReviewSheet();

  @override
  ConsumerState<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<_ReviewSheet> {
  List<BookQuote>? _list;
  Map<int, ({int stage, int? nextAt})> _rv = const {};
  int _at = 0;
  bool _flip = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repo = ref.read(readRepositoryProvider);
    final list = await repo.dueReviews();
    final rv = await repo.reviewMap();
    if (!mounted) return;
    setState(() {
      _list = list;
      _rv = rv;
    });
  }

  String _label(int? nextAt) {
    if (nextAt == null) return '已掌握';
    final days = ((nextAt - DateTime.now().millisecondsSinceEpoch) /
                (24 * 3600 * 1000))
            .ceil();
    if (days <= 0) return '今天';
    return '$days 天后';
  }

  Future<void> _pick(int lv) async {
    final q = _list![_at];
    final repo = ref.read(readRepositoryProvider);
    String msg;
    switch (lv) {
      case 0:
        await repo.resetReview(q.id!);
        msg = '排到今天重练';
      case 1:
        await repo.holdReview(q.id!, 3);
        msg = '3 天后再问';
      default:
        await repo.bumpReview(q.id!);
        final r = await repo.reviewOf(q.id!);
        // _label 已含「N 天后」后缀，直接拼「延长」（原型口径：7 天后延长）。
        msg = r?.nextAt == null ? '已掌握 · 不再出现在复习' : '${_label(r!.nextAt)}延长';
    }
    if (!mounted) return;
    readToast(context, msg);
    // 本轮档已定：回到队首复查，直到整队都不再到期（档位在库中持久推进）。
    setState(() {
      _at = 0;
      _flip = false;
    });
    _reloadQuiet();
  }

  /// 打完档后静默重取到期队（可能已空 → 收尾退出）。
  Future<void> _reloadQuiet() async {
    final repo = ref.read(readRepositoryProvider);
    final list = await repo.dueReviews();
    final rv = await repo.reviewMap();
    if (!mounted) return;
    if (list.isEmpty) {
      ref.read(readTickProvider.notifier).state++;
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _list = list;
      _rv = rv;
      _at = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = _list;
    if (list == null) return const SizedBox(height: 160);
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 28),
        child: Text(
          '还没有到期的摘录',
          style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
        ),
      );
    }
    final q = list[_at];
    final b = (ref.watch(booksProvider).valueOrNull ?? const <Book>[])
        .where((x) => x.id == q.bookId)
        .firstOrNull;
    final md = DateTime.fromMillisecondsSinceEpoch(q.createdAt);
    // 3D 翻面（原型 2529 .rv flip：RotationY 0→π，正面原文/背面想法）。
    Widget face({required bool back}) => Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 188),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: back
            ? context.tokens.accent.withValues(alpha: .07)
            : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
      ),
      child: back
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  q.thought == null || q.thought!.isEmpty
                      ? '（这条还没写想法 · 现在补一句？）'
                      : q.thought!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, height: 1.7),
                ),
                const SizedBox(height: 12),
                Text(
                  '下次复习：${_label(_rv[q.id]?.nextAt)}',
                  key: const ValueKey('rv-next'),
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  q.kind == BookQuote.kKindMark ? '「${q.body}」' : q.body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.75,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${b?.title ?? ''} · ${q.chapter ?? '未分章'} · '
                  '${md.month.toString().padLeft(2, '0')}-'
                  '${md.day.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                Text(
                  '点卡片翻面看自己的想法',
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurfaceVariant.withValues(alpha: .7),
                  ),
                ),
              ],
            ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: _SheetTitle('摘录复习 · 艾宾浩斯'),
            ),
            Text(
              '${_at + 1} / ${list.length}',
              key: const ValueKey('rv-idx'),
              style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
            ),
          ],
        ),
        GestureDetector(
          key: const ValueKey('rv-card'),
          onTap: () => setState(() => _flip = !_flip),
          child: TweenAnimationBuilder<double>(
            key: const ValueKey('rv-flip'),
            tween: Tween(begin: 0, end: _flip ? 1 : 0),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInOut,
            builder: (context, t, _) => Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0015)
                ..rotateY(pi * t),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0015)
                  ..rotateY(t > .5 ? pi : 0),
                child: t > .5 ? face(back: true) : face(back: false),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('rv-forgot'),
                onPressed: () => _pick(0),
                child: const Text('忘了', style: TextStyle(color: Color(0xFFF43F5E))),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('rv-vague'),
                onPressed: () => _pick(1),
                child: const Text('模糊'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('rv-know'),
                onPressed: () => _pick(2),
                child: const Text('记得', style: TextStyle(color: Color(0xFF0D9488))),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}
