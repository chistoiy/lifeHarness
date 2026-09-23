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

/// 就地内嵌通用滚轮列（原型 wReg 口径：任意标签序列 · 步长不强制 5）。
/// 保真批D：页码/创建时间/目标时分双滚轮一律就地展开，禁二段弹层。
class _ColWheel extends StatefulWidget {
  const _ColWheel({
    this.keyName,
    required this.items,
    required this.initialIndex,
    required this.onChanged,
  });
  final String? keyName;
  final List<String> items;
  final int initialIndex;
  final ValueChanged<int> onChanged;

  @override
  State<_ColWheel> createState() => _ColWheelState();
}

class _ColWheelState extends State<_ColWheel> {
  late final FixedExtentScrollController _ctl = FixedExtentScrollController(
    initialItem: widget.initialIndex.clamp(0, widget.items.length - 1),
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListWheelScrollView.useDelegate(
        key: widget.keyName == null ? null : ValueKey<String>(widget.keyName!),
        controller: _ctl,
        itemExtent: 30,
        squeeze: 1.05,
        diameterRatio: 2.4,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: widget.onChanged,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: widget.items.length,
          builder: (context, i) => Center(
            child: Text(
              widget.items[i],
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuoteFormState extends ConsumerState<_QuoteForm> {
  late final TextEditingController _body = TextEditingController(
    text: widget.editing?.body ?? '',
  );
  late final TextEditingController _thought = TextEditingController(
    text: widget.editing?.thought ?? '',
  );
  final TextEditingController _newTag = TextEditingController();
  /// 保真批D：页码/创建时间一律就地滚轮（铁律 · 禁键盘输入与日历二段弹层）。
  late int? _pageVal = widget.editing?.page;
  bool _pageOpen = false;
  late DateTime _date = widget.editing != null
      ? DateTime.fromMillisecondsSinceEpoch(widget.editing!.createdAt)
      : DateTime.now();
  bool _dateOpen = false;
  late String _tag =
      widget.editing?.tag ?? BookQuote.kTagKey; // 新建默认「重点」（原型 qeOpen）
  late String? _chap = widget.editing?.chapter;
  late final List<String> _imgs = [...?widget.editing?.imagePaths];
  late final Set<String> _qtags = {...?widget.editing?.tags};
  List<String> _chapters = const [];
  bool _chapterLoaded = false;
  /// 手动改过页码后换书不再覆写（联动仅对未触碰字段生效）。
  late bool _pageTouched = widget.editing != null;
  /// read.rateFmt（§6 书摘创建）：新建摘录是否自动带出当前进度页码。
  bool _rateFmt = true;
  /// read.clipAuto：读剪贴板时是否按来源模板自动识别书名/页码。
  bool _clipAuto = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadChapters());
    () async {
      final repo = ref.read(readRepositoryProvider);
      final fmt = (await repo.kv('read.rateFmt')) ?? 'true';
      final clip = (await repo.kv('read.clipAuto')) ?? 'true';
      if (mounted) {
        setState(() {
          _rateFmt = fmt == 'true';
          _clipAuto = clip == 'true';
        });
      }
    }();
  }

  @override
  void dispose() {
    _body.dispose();
    _thought.dispose();
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
    if (_pageTouched || !_rateFmt) return;
    final v = b.progressWay == Book.kWayPos && b.readLoc != null
        ? b.readLoc!.round()
        : b.readPages;
    _pageVal = v > 0 ? v : null;
  }

  /// 创建时间就地滚轮（保真批D：禁 showDatePicker 二段弹层）。
  void _setDate({int? y, int? m, int? d}) {
    final days = DateTime(y ?? _date.year, (m ?? _date.month) + 1, 0).day;
    setState(() {
      _date = DateTime(
        y ?? _date.year,
        m ?? _date.month,
        (d ?? _date.day).clamp(1, days),
      );
    });
  }

  Future<void> _ocr() async {
    // read.ocr 关闭时直给设置指引（§6 书摘创建）。
    final on =
        ((await ref.read(readRepositoryProvider).kv('read.ocr')) ?? 'true') ==
        'true';
    if (!mounted) return;
    if (!on) {
      if (mounted) readToast(context, '识图取文已在阅读设置里关闭');
      return;
    }
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
    // read.clipAuto 开：按「——《书名》 + P页码（+ 章节：X）」脚注模板识别来源并拆解。
    final src = _clipAuto
        ? RegExp(r'——《([^》\n]+)》').firstMatch(t)?.group(1)
        : null;
    var body = t;
    String? chapHit;
    if (src != null) {
      body = t
          .split('\n')
          .where((l) => !l.contains('——《'))
          .join('\n')
          .trim();
      final pg = RegExp(r'P(\d+)').firstMatch(t)?.group(1);
      if (pg != null && !_pageTouched && _pageVal == null) {
        _pageVal = int.tryParse(pg);
        _pageTouched = true;
      }
      chapHit = RegExp(r'章节[:：]\s*([^\n\s]+)').firstMatch(t)?.group(1);
      if (chapHit != null && (_chap == null || _chap!.isEmpty)) {
        _chap = chapHit;
      }
    }
    if (!mounted) return;
    setState(
      () => _body.text = _body.text.isEmpty ? body : '${_body.text}\n$body',
    );
    readToast(
      context,
      src == null ? '已读取剪贴板' : '已识别来源：$src · 页码与章节自动带出',
    );
  }

  Future<void> _addImage() async {
    final path = await pickAndStoreImage(
      context,
      bg: Theme.of(context).colorScheme.surfaceContainerLow,
      fg: Theme.of(context).colorScheme.onSurface,
    );
    if (path != null && mounted) {
      setState(() => _imgs.add(path));
      readToast(context, '已添加图片 · 随摘录一起导出');
    }
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
      readToast(context, '至少写一点什么');
      return null;
    }
    final page = _pageVal;
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
    final (q, b) = r;
    final repo = ref.read(readRepositoryProvider);
    final total = widget.editing == null
        ? (await repo.quotesOf(b.id)).length
        : 0;
    if (!mounted) return;
    Navigator.of(context).pop();
    readToast(
      context,
      widget.editing == null
          ? '已保存 · 《${b.title}》 现共 $total 条 · 可做日记素材（L5）'
          : '笔记已更新',
    );
  }

  Future<void> _quick(int to) async {
    // 0=插今日日记 1=生成待办：先落库再分流（L5 · 原型 toast 逐字）。
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
    readToast(
      context,
      to == 0 ? '已插入今日日记草稿（联动 L5）' : '已生成待办：查证该观点（联动 L5）',
    );
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
    if (widget.editing == null && !_pageTouched && _pageVal == null) {
      _syncPageFromBook(cur);
    }
    final chapOpts = {..._chapters, ?_chap}.toList();
    final tagOpts = {...dictTags.map((t) => t.name), ..._qtags}.toList();
    final adding = widget.editing == null;
    // 真机验收轮1 · 原型 sheetQuoteEdit 同步重排：正文/想法置顶加大、快速录入，
    // 书/章节/页码/创建时间等非主要数据收进下方分隔区（metaBlocks）。
    final metaBlocks = <Widget>[
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
              // 页码：点框就地展开数字滚轮（铁律 · 禁键盘输入二段式）。
              Expanded(
                child: GestureDetector(
                  key: const ValueKey('qef-page'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _pageOpen = !_pageOpen),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _pageOpen
                            ? context.tokens.accent
                            : cs.outlineVariant.withValues(alpha: .4),
                      ),
                    ),
                    child: Text(
                      _pageVal == null ? '页码' : 'P$_pageVal',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_pageOpen)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                height: 92,
                child: _NumWheel(
                  keyName: 'qef-page-wheel',
                  value: _pageVal ?? 5,
                  max: (((cur.pages > 0 ? cur.pages : 300) + 24) ~/ 25) * 25,
                  onChanged: (v) => setState(() {
                    _pageVal = v;
                    _pageTouched = true;
                  }),
                ),
              ),
            ),
          const SizedBox(height: 10),
          // 创建时间：默认今天＋今天快捷键；点框就地展开 年/月/日 三列滚轮。
          Row(
            children: [
              Text('创建时间', style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  key: const ValueKey('qef-date'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _dateOpen = !_dateOpen),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _dateOpen
                            ? context.tokens.accent
                            : cs.outlineVariant.withValues(alpha: .4),
                      ),
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
          if (_dateOpen)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: _ColWheel(
                      keyName: 'qef-date-y',
                      items: [
                        for (var y = 2015; y <= 2100; y++) '$y 年',
                      ],
                      initialIndex: _date.year - 2015,
                      onChanged: (i) => _setDate(y: 2015 + i),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _ColWheel(
                      keyName: 'qef-date-m',
                      items: [for (var m = 1; m <= 12; m++) '$m 月'],
                      initialIndex: _date.month - 1,
                      onChanged: (i) => _setDate(m: i + 1),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _ColWheel(
                      keyName: 'qef-date-d',
                      items: [for (var d = 1; d <= 31; d++) '$d 日'],
                      initialIndex: _date.day - 1,
                      onChanged: (i) => _setDate(d: i + 1),
                    ),
                  ),
                ],
              ),
            ),
    ];
    final mq = MediaQuery.of(context);
    final cap = mq.size.height * .86 - mq.viewInsets.bottom;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: cap < 240 ? 240 : cap),
      child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SheetTitle(adding ? '新增摘录 · 《${cur.title}》' : '编辑笔记'),
          // 正文/想法置顶加大：打开表单即可直接录入（键盘避让 · 弹层随 viewInsets 抬升）。
          _field(_body, '原文摘录…', lines: 5, keyName: 'qef-body', autofocus: adding),
          const SizedBox(height: 10),
          _field(_thought, '我的想法（可选，与摘录同条存储）', lines: 3, keyName: 'qef-thought'),
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
          RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              children: const [
                TextSpan(text: '标签'),
                TextSpan(
                  text: '（可多选 · 用于笔记库筛选）',
                  style: TextStyle(fontSize: 10.5),
                ),
              ],
            ),
          ),
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
          // 非主要数据分隔区（原型 border-t pt-2）：书 / 章节·页码 / 创建时间。
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: .5),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: metaBlocks,
            ),
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

/// 就地数字滚轮已改用 _ColWheel / _NumWheel（read_sheets.dart）。

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
