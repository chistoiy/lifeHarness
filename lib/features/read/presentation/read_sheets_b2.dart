part of 'read_sheets.dart';

/// 批2 弹层：书籍表单（含更多资料 · 封面上传 · 字典来源）/
/// 记进度四方式（openProgress）/ 计时明细可改（sheetSess）/
/// 目录粘贴导入（sheetTocImport）。

// ============================ 书籍表单（新增＝编辑同一张） ============================

Future<void> showBookFormSheet(
  BuildContext context,
  WidgetRef ref, {
  Book? editing,
  String defaultState = Book.kStateReading,
}) => _sheet<void>(
  context,
  _BookForm(editing: editing, defaultState: defaultState),
);

class _BookForm extends ConsumerStatefulWidget {
  const _BookForm({this.editing, this.defaultState = Book.kStateReading});
  final Book? editing;
  final String defaultState;

  @override
  ConsumerState<_BookForm> createState() => _BookFormState();
}

class _BookFormState extends ConsumerState<_BookForm> {
  late final TextEditingController _title = TextEditingController(
    text: widget.editing?.title ?? '',
  );
  late final TextEditingController _author = TextEditingController(
    text: widget.editing?.author ?? '',
  );
  late final TextEditingController _pages = TextEditingController(
    text: (widget.editing?.pages ?? 0) > 0 ? '${widget.editing!.pages}' : '',
  );
  late final TextEditingController _translator = TextEditingController(
    text: widget.editing?.translator ?? '',
  );
  late final TextEditingController _publisher = TextEditingController(
    text: widget.editing?.publisher ?? '',
  );
  late final TextEditingController _pubDate = TextEditingController(
    text: widget.editing?.pubDate ?? '',
  );
  late final TextEditingController _series = TextEditingController(
    text: widget.editing?.series ?? '',
  );
  late final TextEditingController _isbn = TextEditingController(
    text: widget.editing?.isbn ?? '',
  );
  late final TextEditingController _source = TextEditingController(
    text: widget.editing?.source ?? '',
  );
  late final TextEditingController _grp = TextEditingController(
    text: widget.editing?.grp ?? '',
  );
  late final TextEditingController _fee = TextEditingController(
    text: (widget.editing?.fee ?? 0) > 0 ? '${widget.editing!.fee}' : '',
  );
  late final TextEditingController _totalLoc = TextEditingController(
    text: widget.editing?.totalLoc != null ? '${widget.editing!.totalLoc}' : '',
  );
  late final TextEditingController _intro = TextEditingController(
    text: widget.editing?.intro ?? '',
  );
  late String _state = widget.editing?.state ?? widget.defaultState;
  late String _format = widget.editing?.format ?? Book.kFormatPaper;
  late String _way = widget.editing?.progressWay ?? Book.defaultWayFor(_format);
  late bool _wayTouched = widget.editing != null;
  late String? _cover = widget.editing?.coverPath;
  bool _moreOpen = false;

  @override
  void dispose() {
    for (final c in [
      _title,
      _author,
      _pages,
      _translator,
      _publisher,
      _pubDate,
      _series,
      _isbn,
      _source,
      _grp,
      _fee,
      _totalLoc,
      _intro,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static String? _nz(String s) => s.trim().isEmpty ? null : s.trim();

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      readToast(context, '书名不能为空');
      return;
    }
    final b = widget.editing;
    final now = DateTime.now().millisecondsSinceEpoch;
    final repo = ref.read(readRepositoryProvider);
    final book = Book(
      id: b?.id ?? '',
      title: _title.text.trim(),
      author: _author.text.trim().isEmpty
          ? (b?.author ?? '佚名')
          : _author.text.trim(),
      translator: _nz(_translator.text),
      publisher: _nz(_publisher.text),
      pubDate: _nz(_pubDate.text),
      series: _nz(_series.text),
      isbn: _nz(_isbn.text),
      coverPath: _cover,
      colorIdx: b?.colorIdx ?? Random().nextInt(8),
      state: _state,
      format: _format,
      progressWay: _way,
      pages: int.tryParse(_pages.text.trim()) ?? 0,
      readPages: b?.readPages ?? 0,
      totalLoc: double.tryParse(_totalLoc.text.trim()),
      readLoc: b?.readLoc,
      chapter: b?.chapter,
      rating: b?.rating ?? 0,
      fee: double.tryParse(_fee.text.trim()) ?? 0,
      feeTxnId: b?.feeTxnId,
      source: _nz(_source.text),
      grp: _nz(_grp.text),
      tags: b?.tags ?? const [],
      startedAt: b?.startedAt,
      endedAt: b?.endedAt,
      lastReadAt: b?.lastReadAt,
      intro: _nz(_intro.text),
      authorNote: b?.authorNote,
      note: b?.note,
      finalNote: b?.finalNote,
      sumQuote: b?.sumQuote,
      sumView: b?.sumView,
      sumGain: b?.sumGain,
      createdAt: b?.createdAt ?? now,
      updatedAt: now,
    );
    if (b == null) {
      await repo.addBook(book);
    } else {
      await repo.updateBook(book);
    }
    if (!mounted) return;
    ref.read(readTickProvider.notifier).state++;
    Navigator.of(context).pop();
    readToast(context, b == null ? '已加入书架 · ${book.title}' : '已保存');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final srcs =
        ref.watch(dictProvider(DictEntry.kSource)).valueOrNull ??
        const <DictEntry>[];
    final grps =
        ref.watch(dictProvider(DictEntry.kGroup)).valueOrNull ??
        const <DictEntry>[];
    final b = widget.editing;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SheetTitle(b == null ? '新书上架' : '编辑信息', onSave: _save),
          _field(_title, '书名', keyName: 'bkf-title'),
          const SizedBox(height: 10),
          _field(_author, '作者', keyName: 'bkf-author'),
          const SizedBox(height: 12),
          Text(
            '分区',
            style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          _Chips(
            items: Book.states,
            selected: {_state},
            keys: Book.states,
            onPick: (v) => setState(() => _state = v),
          ),
          const SizedBox(height: 12),
          Text(
            '类型',
            style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          _Chips(
            items: Book.formats,
            selected: {_format},
            keys: Book.formats,
            onPick: (v) => setState(() {
              _format = v;
              if (!_wayTouched) _way = Book.defaultWayFor(v);
            }),
          ),
          const SizedBox(height: 12),
          Text(
            '进度方式',
            style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          _Chips(
            items: const ['按页', '按位置', '按章节', '按百分比'],
            selected: {
              switch (_way) {
                Book.kWayPage => '按页',
                Book.kWayPos => '按位置',
                Book.kWayChap => '按章节',
                _ => '按百分比',
              },
            },
            keys: const [
              'bkf-way-page',
              'bkf-way-pos',
              'bkf-way-chap',
              'bkf-way-pct',
            ],
            onPick: (v) => setState(() {
              _way = switch (v) {
                '按页' => Book.kWayPage,
                '按位置' => Book.kWayPos,
                '按章节' => Book.kWayChap,
                _ => Book.kWayPct,
              };
              _wayTouched = true;
            }),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: _field(_pages, '总页数', keyName: 'bkf-pages')),
              const SizedBox(width: 10),
              Expanded(
                child: _field(_totalLoc, '总位置(loc)', keyName: 'bkf-loc'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 封面（色板封面默认 · 可上传相册/拍照替换）
          Row(
            children: [
              GestureDetector(
                key: const ValueKey('bkf-cover'),
                onTap: () async {
                  final path = await pickAndStoreImage(
                    context,
                    bg: cs.surfaceContainerLow,
                    fg: cs.onSurface,
                  );
                  if (path != null && mounted) setState(() => _cover = path);
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: _cover != null && _cover!.isNotEmpty
                      ? Image.file(
                          File(_cover!),
                          width: 40,
                          height: 56,
                          fit: BoxFit.cover,
                        )
                      : BsCover(
                          book:
                              b ??
                              Book(
                                id: '',
                                title: _title.text,
                                createdAt: 0,
                                updatedAt: 0,
                              ),
                          width: 40,
                          height: 56,
                          radius: 6,
                          showAuthor: false,
                          showBadge: false,
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _cover == null || _cover!.isEmpty
                      ? '更换封面（相册 / 拍照）'
                      : '已上传封面 · 点击更换',
                  style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                ),
              ),
              if (_cover != null && _cover!.isNotEmpty)
                IconButton(
                  key: const ValueKey('bkf-cover-reset'),
                  onPressed: () => setState(() => _cover = null),
                  icon: const Icon(BsIcons.trash, size: 16),
                ),
            ],
          ),
          const SizedBox(height: 4),
          GestureDetector(
            key: const ValueKey('bkf-more'),
            onTap: () => setState(() => _moreOpen = !_moreOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _moreOpen
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '更多资料',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_moreOpen) ...[
            _field(_translator, '译者', keyName: 'bkf-translator'),
            const SizedBox(height: 10),
            _field(_publisher, '出版社', keyName: 'bkf-publisher'),
            const SizedBox(height: 10),
            _field(_pubDate, '出版日期', keyName: 'bkf-pubdate'),
            const SizedBox(height: 10),
            _field(_series, '系列', keyName: 'bkf-series'),
            const SizedBox(height: 10),
            _field(_isbn, 'ISBN', keyName: 'bkf-isbn'),
            const SizedBox(height: 10),
            _field(_source, '来源', keyName: 'bkf-source'),
            if (srcs.isNotEmpty) ...[
              const SizedBox(height: 6),
              _Chips(
                items: srcs.map((e) => e.name).toList(),
                selected: {_source.text},
                keys: [for (final e in srcs) 'bkf-src-${e.name}'],
                onPick: (v) => setState(() => _source.text = v),
              ),
            ],
            const SizedBox(height: 10),
            _field(_grp, '分组', keyName: 'bkf-grp'),
            if (grps.isNotEmpty) ...[
              const SizedBox(height: 6),
              _Chips(
                items: grps.map((e) => e.name).toList(),
                selected: {_grp.text},
                keys: [for (final e in grps) 'bkf-grp-${e.name}'],
                onPick: (v) => setState(() => _grp.text = v),
              ),
            ],
            const SizedBox(height: 10),
            _field(_fee, '购书费用', keyName: 'bkf-fee'),
            const SizedBox(height: 10),
            _field(_intro, '简介', lines: 3, keyName: 'bkf-intro'),
          ],
          const SizedBox(height: 6),
          FilledButton(
            key: const ValueKey('bkf-save'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            onPressed: _save,
            child: Text(b == null ? '加入书架' : '保存'),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

// ============================ 记进度（openProgress 四方式） ============================

Future<void> showProgressSheet(BuildContext context, WidgetRef ref, Book b) =>
    _sheet<void>(context, _ProgressForm(b: b));

class _ProgressForm extends ConsumerStatefulWidget {
  const _ProgressForm({required this.b});
  final Book b;

  @override
  ConsumerState<_ProgressForm> createState() => _ProgressFormState();
}

class _ProgressFormState extends ConsumerState<_ProgressForm> {
  late String _way = widget.b.progressWay == Book.kWayMin
      ? Book.kWayPage
      : widget.b.progressWay;
  late final TextEditingController _value = TextEditingController(
    text: _initialValue(),
  );
  String? _chapter;

  String _initialValue() {
    final b = widget.b;
    return switch (b.progressWay) {
      Book.kWayPos => b.readLoc != null ? '${b.readLoc!.round()}' : '',
      Book.kWayPct => '${b.percent}',
      _ => b.readPages > 0 ? '${b.readPages}' : '',
    };
  }

  static const _labels = {
    Book.kWayPage: '按页',
    Book.kWayPos: '按位置',
    Book.kWayPct: '按百分比',
    Book.kWayChap: '按章节',
  };

  Future<void> _save() async {
    final repo = ref.read(readRepositoryProvider);
    if (_way == Book.kWayChap) {
      final toc = await repo.tocOf(widget.b.id);
      final secs = toc.where((n) => !n.isPart).toList();
      final pick =
          _chapter ??
          (widget.b.chapter != null &&
                  secs.any((s) => s.title == widget.b.chapter)
              ? widget.b.chapter
              : secs.isNotEmpty
              ? secs.first.title
              : null);
      if (pick == null) {
        if (mounted) readToast(context, '还没有目录 · 请先导入');
        return;
      }
      final node = secs.firstWhere((s) => s.title == pick);
      await repo.saveProgress(
        widget.b.id,
        _way,
        null,
        chapterTitle: pick,
        chapterStartPage: node.startPage,
      );
    } else {
      final v = double.tryParse(_value.text.trim());
      if (v == null) {
        if (mounted) readToast(context, '请填写有效数值');
        return;
      }
      await repo.saveProgress(widget.b.id, _way, v);
    }
    if (!mounted) return;
    ref.read(readTickProvider.notifier).state++;
    Navigator.of(context).pop();
    final nb = await repo.bookById(widget.b.id);
    if (mounted && nb != null) {
      readToast(context, '《${nb.title}》· ${nb.percent}%');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final b = widget.b;
    final toc = ref.watch(tocProvider(b.id)).valueOrNull ?? const <TocNode>[];
    final secs = toc.where((n) => !n.isPart).toList();
    final fc = ProgressForecast.of(b);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SheetTitle('记进度 · 《${b.title}》', onSave: _save),
          _Chips(
            items: _labels.values.toList(),
            selected: {_labels[_way]!},
            keys: const ['pgw-page', 'pgw-pos', 'pgw-pct', 'pgw-chap'],
            onPick: (v) => setState(() {
              _way = _labels.entries.firstWhere((e) => e.value == v).key;
            }),
          ),
          const SizedBox(height: 12),
          if (_way != Book.kWayChap)
            _field(_value, switch (_way) {
              Book.kWayPos => '当前位置（loc，共 ${b.totalLoc ?? 0}）',
              Book.kWayPct => '百分比（0~100）',
              _ => '当前页码（共 ${b.pages} 页）',
            }, keyName: 'pgf-value')
          else if (secs.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              alignment: Alignment.center,
              child: Text(
                '还没有目录 · 可在书籍详情页导入',
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in secs)
                      GestureDetector(
                        key: ValueKey('pgc-${s.id}'),
                        onTap: () => setState(() => _chapter = s.title),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: (_chapter ?? b.chapter) == s.title
                                ? tokens.accent.withValues(alpha: .12)
                                : cs.surfaceContainerHighest,
                          ),
                          child: Text(
                            s.title,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: (_chapter ?? b.chapter) == s.title
                                  ? tokens.accent
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: BkPctBar(book: b)),
              const SizedBox(width: 8),
              Text(
                '${b.percent}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '均速 ${fc.pagesPerDay <= 0 ? '—' : fc.pagesPerDay.toStringAsFixed(1)} 页/天 · '
            '剩 ${fc.remainPages} 页 · ${forecastLabel(fc)}',
            style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

// ============================ 计时明细（sheetSess · 行内可改可删可补记） ============================

Future<void> showSessionsSheet(BuildContext context, WidgetRef ref, Book b) =>
    _sheet<void>(context, _SessList(b: b));

class _SessList extends ConsumerWidget {
  const _SessList({required this.b});
  final Book b;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final sessions =
        (ref.watch(sessionsOfProvider(b.id)).valueOrNull ??
                const <BookSession>[])
            .where((s) => s.endedAt != null)
            .toList()
            .reversed
            .toList();
    final agg = ref.watch(workbenchProvider).valueOrNull?.agg[b.id];
    return Consumer(
      builder: (sheetCtx, ref, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SheetTitle('计时明细 · 《${b.title}》'),
          Text(
            '${bsFmt(agg?.minutes ?? 0)} · ${agg?.times ?? 0} 次',
            style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 340),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final s in sessions) _SessRow(b: b, s: s),
                  if (sessions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        '还没有计时记录',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            key: const ValueKey('sess-add'),
            onPressed: () async {
              await ref
                  .read(readRepositoryProvider)
                  .addManualSession(
                    bookId: b.id,
                    day: DateTime.now(),
                    minutes: 20,
                    fromPage: b.readPages > 0 ? b.readPages : null,
                  );
              if (!sheetCtx.mounted) return;
              ref.read(readTickProvider.notifier).state++;
              readToast(sheetCtx, '已补记一次 · 20 分钟');
            },
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('补记一次'),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _SessRow extends ConsumerStatefulWidget {
  const _SessRow({required this.b, required this.s});
  final Book b;
  final BookSession s;

  @override
  ConsumerState<_SessRow> createState() => _SessRowState();
}

class _SessRowState extends ConsumerState<_SessRow> {
  late final TextEditingController _min = TextEditingController(
    text: '${widget.s.minutes}',
  );
  late final TextEditingController _from = TextEditingController(
    text: '${widget.s.fromPage ?? ''}',
  );
  late final TextEditingController _to = TextEditingController(
    text: '${widget.s.toPage ?? ''}',
  );

  @override
  void dispose() {
    _min.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  /// 任一字段提交：以分钟+日期重排区间（日期不变）。
  Future<void> _apply({int? minutes, int? fromPage, int? toPage}) async {
    final s = widget.s;
    await ref
        .read(readRepositoryProvider)
        .editSession(
          s.id!,
          startedAtMs: s.startedAt,
          minutes: minutes ?? s.minutes,
          fromPage: fromPage,
          toPage: toPage,
        );
    if (!mounted) return;
    ref.read(readTickProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = DateTime.fromMillisecondsSinceEpoch(widget.s.startedAt);
    final dateTxt =
        '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        key: ValueKey('sess-${widget.s.id}'),
        children: [
          GestureDetector(
            key: ValueKey('sessd-${widget.s.id}'),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: d,
                firstDate: DateTime(d.year - 3),
                lastDate: DateTime.now(),
              );
              if (picked == null) return;
              final ms = DateTime(
                picked.year,
                picked.month,
                picked.day,
                d.hour,
                d.minute,
              ).millisecondsSinceEpoch;
              await ref
                  .read(readRepositoryProvider)
                  .editSession(
                    widget.s.id!,
                    startedAtMs: ms,
                    minutes: widget.s.minutes,
                  );
              if (!mounted) return;
              ref.read(readTickProvider.notifier).state++;
            },
            child: SizedBox(
              width: 56,
              child: Text(
                dateTxt,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 54,
            child: TextField(
              key: ValueKey('sessmin-${widget.s.id}'),
              controller: _min,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 11.5),
              decoration: const InputDecoration(isDense: true, hintText: '分'),
              onSubmitted: (v) => _apply(minutes: int.tryParse(v.trim())),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: TextField(
                    key: ValueKey('sessfrom-${widget.s.id}'),
                    controller: _from,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 11.5),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '起',
                    ),
                    onSubmitted: (v) =>
                        _apply(fromPage: int.tryParse(v.trim())),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text('→', style: TextStyle(fontSize: 11)),
                ),
                SizedBox(
                  width: 52,
                  child: TextField(
                    key: ValueKey('sessto-${widget.s.id}'),
                    controller: _to,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 11.5),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '止',
                    ),
                    onSubmitted: (v) => _apply(toPage: int.tryParse(v.trim())),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('sessdel-${widget.s.id}'),
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              await ref
                  .read(readRepositoryProvider)
                  .deleteSession(widget.s.id!);
              if (!mounted) return;
              ref.read(readTickProvider.notifier).state++;
            },
            icon: Icon(
              Icons.remove_circle_outline_rounded,
              size: 17,
              color: cs.error,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================ 目录粘贴导入（sheetTocImport） ============================

Future<void> showTocImportSheet(
  BuildContext context,
  WidgetRef ref,
  String bookId, {
  String? bookTitle,
}) => _sheet<void>(context, _TocImport(bookId: bookId, bookTitle: bookTitle));

class _TocImport extends ConsumerStatefulWidget {
  const _TocImport({required this.bookId, this.bookTitle});
  final String bookId;
  final String? bookTitle;

  @override
  ConsumerState<_TocImport> createState() => _TocImportState();
}

class _TocImportState extends ConsumerState<_TocImport> {
  final _ctl = TextEditingController();
  List<ParsedTocPart> _parsed = const [];

  int get _secCount => _parsed.fold(0, (t, p) => t + p.sections.length);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetTitle(
          '导入目录${widget.bookTitle != null ? ' · 《${widget.bookTitle}》' : ''}',
        ),
        TextField(
          key: const ValueKey('toe-text'),
          controller: _ctl,
          maxLines: 7,
          style: const TextStyle(fontSize: 12, height: 1.6),
          decoration: InputDecoration(
            hintText: '粘贴目录文本：第X部/篇/卷、Part、罗马数字行＝部分；其余行＝小节',
            hintStyle: const TextStyle(fontSize: 11.5),
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
          onChanged: (v) => setState(() => _parsed = parseTocText(v)),
        ),
        const SizedBox(height: 8),
        Text(
          _ctl.text.trim().isEmpty
              ? '等待粘贴'
              : '${_parsed.length} 个部分 · $_secCount 节',
          key: const ValueKey('toe-preview'),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        FilledButton(
          key: const ValueKey('toe-ok'),
          onPressed: _parsed.isEmpty
              ? null
              : () async {
                  final repo = ref.read(readRepositoryProvider);
                  await repo.replaceToc(widget.bookId, _parsed);
                  await repo.tocPrune(widget.bookId);
                  if (!mounted) return;
                  ref.read(readTickProvider.notifier).state++;
                  Navigator.of(this.context).pop();
                  readToast(
                    this.context,
                    '目录已导入 · ${_parsed.length} 部分/$_secCount 节',
                  );
                },
          child: const Text('确认替换'),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// 编辑目录就地改行（详情页目录卡编辑态用）。
class TocEditRow extends StatefulWidget {
  const TocEditRow({
    super.key,
    required this.node,
    required this.onRename,
    required this.onMove,
    required this.onDelete,
    this.onAddSection,
  });
  final TocNode node;
  final ValueChanged<String> onRename;
  final ValueChanged<int> onMove; // -1/+1
  final VoidCallback onDelete;
  final VoidCallback? onAddSection;

  @override
  State<TocEditRow> createState() => _TocEditRowState();
}

class _TocEditRowState extends State<TocEditRow> {
  late final TextEditingController _ctl = TextEditingController(
    text: widget.node.title,
  );

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget ic(String key, IconData i, VoidCallback? cb) => IconButton(
      key: ValueKey(key),
      visualDensity: VisualDensity.compact,
      onPressed: cb,
      icon: Icon(i, size: 15, color: cs.onSurfaceVariant),
    );
    return Padding(
      padding: EdgeInsets.only(left: widget.node.isPart ? 0 : 18, bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: ValueKey('tce-${widget.node.id}'),
              controller: _ctl,
              style: TextStyle(
                fontSize: widget.node.isPart ? 12 : 11.5,
                fontWeight: widget.node.isPart
                    ? FontWeight.w800
                    : FontWeight.w500,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
              ),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) widget.onRename(v.trim());
              },
            ),
          ),
          ic(
            'tcup-${widget.node.id}',
            Icons.arrow_upward_rounded,
            () => widget.onMove(-1),
          ),
          ic(
            'tcdown-${widget.node.id}',
            Icons.arrow_downward_rounded,
            () => widget.onMove(1),
          ),
          if (widget.onAddSection != null)
            ic(
              'tcadd-${widget.node.id}',
              Icons.add_rounded,
              widget.onAddSection,
            ),
          ic(
            'tcdel-${widget.node.id}',
            Icons.remove_circle_outline_rounded,
            widget.onDelete,
          ),
        ],
      ),
    );
  }
}
