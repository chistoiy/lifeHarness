part of 'read_sheets.dart';

/// 批3 弹层：摘录表单（新增＝编辑同一张 · 书/章节/页码/创建时间/原文/想法/
/// 识图·加图·剪贴板/颜色分类/标签多选 · §3.4 表单三处联动）/
/// 摘录操作弹层（sheetQuoteOps · L5 分流）/ 艾宾浩斯复习（sheetReview 翻面卡）。

// ============================ 摘录表单（唯一一张 · 新增＝编辑） ============================

Future<void> showQuoteEditSheet(
  BuildContext context,
  WidgetRef ref, {
  String? bookId,
  BookQuote? editing,
}) => _sheet<void>(
  context,
  _QuoteForm(bookId: bookId, editing: editing),
);

class _QuoteForm extends ConsumerStatefulWidget {
  const _QuoteForm({this.bookId, this.editing});
  final String? bookId;
  final BookQuote? editing;

  @override
  ConsumerState<_QuoteForm> createState() => _QuoteFormState();
}

class _QuoteFormState extends ConsumerState<_QuoteForm> {
  late final TextEditingController _body = TextEditingController(
    text: widget.editing?.body ?? '',
  );
  late final TextEditingController _thought = TextEditingController(
    text: widget.editing?.thought ?? '',
  );
  late final TextEditingController _page = TextEditingController(
    text: widget.editing?.page != null ? '${widget.editing!.page}' : '',
  );
  final TextEditingController _newTag = TextEditingController();
  /// 编辑既有摘录时创建时间原值；新建默认今天（表单可改 · §3.3）。
  late DateTime _date = widget.editing != null
      ? DateTime.fromMillisecondsSinceEpoch(widget.editing!.createdAt)
      : DateTime.now();
  late String _tag = widget.editing?.tag ?? BookQuote.kTagReso;
  late String? _chap = widget.editing?.chapter;
  late final List<String> _imgs = [...?widget.editing?.imagePaths];
  late final Set<String> _qtags = {...?widget.editing?.tags};
  List<String> _chapters = const [];
  bool _chapterLoaded = false;
  /// 手动改过页码后换书不再覆写（联动仅对未触碰字段生效）。
  late bool _pageTouched = widget.editing != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadChapters());
  }

  @override
  void dispose() {
    _body.dispose();
    _thought.dispose();
    _page.dispose();
    _newTag.dispose();
    super.dispose();
  }

  Book? _bookOf(List<Book> books, String id) =>
      books.where((b) => b.id == id).firstOrNull;

  /// 章节下拉取本书 book_toc_nodes（含部分名 · 无目录提示先导入 §3.3）。
  Future<void> _loadChapters() async {
    if (_chapterLoaded) return;
    final id = _pickedId;
    if (id == null) return;
    _chapterLoaded = true;
    final nodes = await ref.read(readRepositoryProvider).tocOf(id);
    if (!mounted) return;
    final opts = <String>{};
    for (final g in tocTree(nodes)) {
      if (g.part.title.isNotEmpty) opts.add(g.part.title);
      for (final s in g.sections) {
        if (s.title.isNotEmpty) opts.add(s.title);
      }
    }
    setState(() {
      _chapters = opts.toList();
      _chapterLoaded = true;
    });
  }

  String? _pickedId;

  void _pickBook(List<Book> books, String id) {
    setState(() {
      _pickedId = id;
      _chap = null;
      _chapterLoaded = false;
      _chapters = const [];
    });
    _loadChapters();
  }

  /// 换书联动：页码按当前进度带出（read.rateFmt 默认开 · §3.4 三处同步）。
  void _syncPageFromBook(Book b) {
    if (_pageTouched) return;
    final v = b.progressWay == Book.kWayPos && b.readLoc != null
        ? b.readLoc!.round()
        : b.readPages;
    _page.text = v > 0 ? '$v' : '';
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _ocr() async {
    // 设备侧 OCR 未接入：入口保留、置灰降级为手动粘贴（§9 风险2 · 不阻塞保存）。
    readToast(context, '未接入识图引擎 · 请用「读剪贴板」或手动粘贴');
  }

  Future<void> _fromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text?.trim() ?? '';
    if (t.isEmpty) {
      if (mounted) readToast(context, '剪贴板没有文字');
      return;
    }
    setState(
      () => _body.text = _body.text.isEmpty ? t : '${_body.text}\n$t',
    );
    if (mounted) readToast(context, '已读取剪贴板');
  }

  Future<void> _addImage() async {
    final path = await pickAndStoreImage(
      context,
      bg: Theme.of(context).colorScheme.surfaceContainerLow,
      fg: Theme.of(context).colorScheme.onSurface,
    );
    if (path != null && mounted) setState(() => _imgs.add(path));
  }

  /// 组一条摘录（保存与 L5 快捷动作共用）。
  BookQuote? _compose(List<Book> books) {
    final b = _bookOf(books, _pickedId ?? '');
    if (b == null) {
      readToast(context, '先选一本要记录的书');
      return null;
    }
    final bodyT = _body.text.trim();
    final th = _thought.text.trim();
    if (bodyT.isEmpty && th.isEmpty) {
      readToast(context, '原文与想法至少填一项');
      return null;
    }
    final page = int.tryParse(_page.text.trim());
    return BookQuote(
      id: widget.editing?.id,
      bookId: b.id,
      kind: bodyT.isEmpty ? BookQuote.kKindThought : BookQuote.kKindMark,
      tag: _tag,
      tags: _qtags.toList(),
      body: bodyT.isEmpty ? th : bodyT,
      thought: bodyT.isEmpty ? null : (th.isEmpty ? null : th),
      chapter: (_chap == null || _chap!.isEmpty) ? null : _chap,
      page: (page == null || page <= 0) ? null : page,
      imagePaths: _imgs,
      starred: widget.editing?.starred ?? false,
      origin: widget.editing?.origin,
      dedupHash: widget.editing?.dedupHash,
      createdAt: _date.millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 落库并返回（书一并带出）；查重命中给提示返回 null。
  Future<(BookQuote, Book)?> _persist(List<Book> books) async {
    final q = _compose(books);
    if (q == null) return null;
    final b = _bookOf(books, q.bookId)!;
    final repo = ref.read(readRepositoryProvider);
    if (widget.editing == null) {
      final id = await repo.addQuote(q);
      if (id == null) {
        if (mounted) readToast(context, '这条摘录已存在 · 未重复入账');
        return null;
      }
    } else {
      final ok = await repo.updateQuote(q);
      if (!ok) {
        if (mounted) readToast(context, '这条摘录已存在 · 未重复入账');
        return null;
      }
    }
    if (!mounted) return null;
    ref.read(readTickProvider.notifier).state++;
    return (q, b);
  }

  Future<void> _save() async {
    final books = ref.read(booksProvider).valueOrNull ?? const <Book>[];
    final r = await _persist(books);
    if (r == null || !mounted) return;
    Navigator.of(context).pop();
    readToast(context, widget.editing == null ? '已记录这条摘录' : '笔记已更新');
  }

  Future<void> _quick(int to) async {
    // 0=插今日日记 1=生成待办：先落库再分流（L5）。
    final books = ref.read(booksProvider).valueOrNull ?? const <Book>[];
    final r = await _persist(books);
    if (r == null || !mounted) return;
    final (q, b) = r;
    final repo = ref.read(readRepositoryProvider);
    if (to == 0) {
      await repo.quoteToDiary(q, b);
    } else {
      await repo.quoteToTodo(q, b);
    }
    ref.read(readTickProvider.notifier).state++;
    if (!mounted) return;
    Navigator.of(context).pop();
    readToast(context, to == 0 ? '已保存并插入今日日记' : '已保存并生成待办');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final books =
        (ref.watch(booksProvider).valueOrNull ?? const <Book>[])
            .where((b) => !b.isDeleted)
            .toList();
    final dictTags =
        ref.watch(dictProvider(DictEntry.kTag)).valueOrNull ??
        const <DictEntry>[];
    if (books.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetTitle('新增摘录'),
            Text(
              '书架上还没有书 · 先添加一本',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                showAddBookSheet(context, ref);
              },
              child: const Text('添加一本'),
            ),
          ],
        ),
      );
    }
    // 默认书：编辑态原书 ＞ 指定 bookId ＞ 在读最近阅读那本（§3.3）。
    _pickedId ??=
        widget.editing?.bookId ??
        widget.bookId ??
        ShelfSort.byLastRead(
          books.where((b) => b.state == Book.kStateReading).toList(),
        ).firstOrNull?.id ??
        books.first.id;
    final cur = _bookOf(books, _pickedId!) ?? books.first;
    if (!_chapterLoaded && _chapters.isEmpty) _loadChapters();
    // 新建时页码按当前进度带出（read.rateFmt 默认开）。
    if (widget.editing == null && !_pageTouched && _page.text.isEmpty) {
      _syncPageFromBook(cur);
    }
    final chapOpts = {..._chapters, ?_chap}.toList();
    final tagOpts = {...dictTags.map((t) => t.name), ..._qtags}.toList();
    final adding = widget.editing == null;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SheetTitle(
            adding ? '新增摘录 · 《${cur.title}》' : '编辑笔记',
            onSave: _save,
          ),
          // 选书下拉：换书时 标题 / 章节 / 页码 三处联动（§3.4）。
          DropdownButtonFormField<String>(
            key: const ValueKey('qef-book'),
            initialValue: cur.id,
            isExpanded: true,
            borderRadius: BorderRadius.circular(14),
            decoration: _deco('书'),
            items: [
              for (final b in books)
                DropdownMenuItem(
                  value: b.id,
                  child: Text('${b.title} · ${b.author}', overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) {
              if (v == null) return;
              _pickBook(books, v);
              final nb = _bookOf(books, v);
              if (nb != null) _syncPageFromBook(nb);
            },
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('qef-chap'),
                  initialValue: (_chap != null && chapOpts.contains(_chap))
                      ? _chap
                      : null,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(14),
                  hint: Text(
                    _chapterLoaded && chapOpts.isEmpty
                        ? '未分章 · 可先在书籍详情页导入目录'
                        : '章节（未分章）',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  decoration: _deco(null),
                  items: [
                    for (final c in chapOpts)
                      DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _chap = v),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 88,
                child: _fieldNum(_page, '页码', keyName: 'qef-page',
                    onChanged: (_) => _pageTouched = true),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 创建时间：默认今天＋今天快捷键，可改（§3.3 补记场景）。
          Row(
            children: [
              Text('创建时间', style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  key: const ValueKey('qef-date'),
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '${_date.year}-${_date.month.toString().padLeft(2, '0')}-'
                      '${_date.day.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                key: const ValueKey('qef-today'),
                onPressed: () => setState(() => _date = DateTime.now()),
                child: const Text('今天', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _field(_body, '原文摘录…', lines: 3, keyName: 'qef-body'),
          const SizedBox(height: 10),
          _field(_thought, '我的想法（与原文同条存储）', lines: 2, keyName: 'qef-thought'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('qef-ocr'),
                  onPressed: _ocr,
                  child: const Text('识图取文', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('qef-img'),
                  onPressed: _addImage,
                  child: const Text('加图片', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('qef-clip'),
                  onPressed: _fromClipboard,
                  child: const Text('读剪贴板', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
          if (_imgs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < _imgs.length; i++)
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            File(_imgs[i]),
                            width: 64,
                            height: 84,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: GestureDetector(
                            key: ValueKey('qef-img-del-$i'),
                            onTap: () => setState(() => _imgs.removeAt(i)),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: cs.scrim.withValues(alpha: .55),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.close_rounded,
                                  size: 12, color: cs.onPrimary),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text('划线颜色分类', style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          _Chips(
            items: BookQuote.colorTags,
            selected: {_tag},
            keys: BookQuote.colorTags.map((t) => 'qef-tag-$t').toList(),
            onPick: (v) => setState(() => _tag = v),
          ),
          const SizedBox(height: 12),
          Text('标签', style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _field(_newTag, '新标签', keyName: 'qef-tag-new'),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const ValueKey('qef-tag-add'),
                onPressed: () {
                  final t = _newTag.text.trim();
                  if (t.isEmpty) return;
                  setState(() {
                    _qtags.add(t);
                    _newTag.clear();
                  });
                },
                icon: const Icon(BsIcons.add, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in tagOpts)
                GestureDetector(
                  key: ValueKey('qef-mt-$t'),
                  onTap: () => setState(
                    () => _qtags.contains(t) ? _qtags.remove(t) : _qtags.add(t),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: _qtags.contains(t)
                          ? context.tokens.accent.withValues(alpha: .12)
                          : cs.surfaceContainerHighest,
                      border: Border.all(
                        color: _qtags.contains(t)
                            ? context.tokens.accent
                            : cs.outlineVariant.withValues(alpha: .5),
                      ),
                    ),
                    child: Text(
                      '#$t',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: _qtags.contains(t)
                            ? context.tokens.accent
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('qef-diary'),
                  onPressed: () => _quick(0),
                  child: const Text('插今日日记', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('qef-todo'),
                  onPressed: () => _quick(1),
                  child: const Text('生成待办', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('qef-save'),
                  onPressed: _save,
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

InputDecoration _deco(String? label) => InputDecoration(
  labelText: label,
  labelStyle: const TextStyle(fontSize: 12.5),
  filled: true,
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide.none,
  ),
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
);

TextField _fieldNum(
  TextEditingController c,
  String label, {
  String? keyName,
  ValueChanged<String>? onChanged,
}) => TextField(
  key: keyName == null ? null : ValueKey(keyName),
  controller: c,
  keyboardType: TextInputType.number,
  onChanged: onChanged,
  decoration: InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(fontSize: 12.5),
    filled: true,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  ),
);

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
        showQuoteEditSheet(context, ref, editing: q);
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

// ============================ 摘录复习（艾宾浩斯 1/3/7 · 翻面卡） ============================

Future<void> showReviewSheet(BuildContext context, WidgetRef ref) =>
    _sheet<void>(context, const _ReviewSheet());

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
        final l = _label(r?.nextAt);
        msg = l == '已掌握' ? '已掌握 · 不再出现在复习' : '$l后延长';
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
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 188),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _flip
                  ? context.tokens.accent.withValues(alpha: .07)
                  : cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: .4),
              ),
            ),
            child: _flip
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        q.thought == null || q.thought!.isEmpty
                            ? '（这条还没写想法）'
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
                        q.kind == BookQuote.kKindMark
                            ? '「${q.body}」'
                            : q.body,
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
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
                        ),
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
