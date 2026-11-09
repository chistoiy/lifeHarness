part of 'read_sheets.dart';

// 治理（高保真批6b·刀1）：书籍表单组自 read_sheets_b2.dart 整组迁入本同库
// part（G7c/G7d5 族口径：私有成员不放宽）——原文件回到默认
// 1200 面，size_budget 登记项按口径删除。纯机械搬迁＝零行为变化。

class _BookForm extends ConsumerStatefulWidget {
  const _BookForm({this.editing, this.defaultState = Book.kStateWant});
  final Book? editing;
  final String defaultState;

  @override
  ConsumerState<_BookForm> createState() => _BookFormState();
}

class _BookFormState extends ConsumerState<_BookForm> {
  late final Book? _b = widget.editing;
  late final bool _isNew = _b == null;

  late final TextEditingController _title = TextEditingController(
    text: _b?.title ?? '',
  );
  late final TextEditingController _author = TextEditingController(
    text: _b?.author ?? '',
  );
  late final TextEditingController _publisher = TextEditingController(
    text: _b?.publisher ?? '',
  );
  late final TextEditingController _translator = TextEditingController(
    text: _b?.translator ?? '',
  );
  late final TextEditingController _pubDate = TextEditingController(
    text: _b?.pubDate ?? '',
  );
  late final TextEditingController _series = TextEditingController(
    text: _b?.series ?? '',
  );
  late final TextEditingController _isbn = TextEditingController(
    text: _b?.isbn ?? '',
  );
  late final TextEditingController _source = TextEditingController(
    text: _b?.source ?? '',
  );
  late final TextEditingController _grp = TextEditingController(
    text: _b?.grp ?? '',
  );
  late final TextEditingController _fee = TextEditingController(
    text: (_b?.fee ?? 0) > 0 ? '${_b!.fee}' : '',
  );
  late final TextEditingController _totalLoc = TextEditingController(
    text: _b?.totalLoc != null ? '${_b!.totalLoc}' : '',
  );
  late final TextEditingController _readLoc = TextEditingController(
    text: _b?.readLoc != null ? '${_b!.readLoc}' : '',
  );
  late final TextEditingController _pages = TextEditingController(
    text: (_b?.pages ?? 0) > 0 ? '${_b!.pages}' : '',
  );
  late final TextEditingController _readPages = TextEditingController(
    text: (_b?.readPages ?? 0) > 0 ? '${_b!.readPages}' : '',
  );
  late final TextEditingController _pct = TextEditingController(
    text: _b != null ? '${_b.percent}' : '',
  );
  late final TextEditingController _intro = TextEditingController(
    text: _b?.intro ?? '',
  );
  late final TextEditingController _note = TextEditingController(
    text: _b?.note ?? '',
  );

  late String _state = _b?.state ?? widget.defaultState;
  late String _format = _b?.format ?? Book.kFormatPaper;
  late String _way = _b?.progressWay ?? Book.defaultWayFor(_format);
  late String? _cover = _b?.coverPath;
  late int _colorIdx = _b?.colorIdx ?? Random().nextInt(kBsCov.length);
  late final List<String> _tags = [...?_b?.tags];
  late int _rate = (_b?.rating ?? 0).round();
  bool _moreOpen = false;
  // F2-15：保存防重入门（连点只落一次写）。
  bool _busy = false;
  // F2-12（LH-K32）：书名必填的就地错误（非空即显示在字段下方，输入即撤）。
  String? _titleErr;
  // 批F2：ISBN 命中状态位（匹配中… / 已命中 · 自动填充 / 仅填 ISBN · 留空待补 / 离线或未命中 · 留空待补）。
  String _isbnStatus = '';
  Timer? _isbnT;
  int _isbnSeq = 0;
  bool _fillDouban = false; // 阅读设置 read.isbnFill＝「抓豆瓣数据」时联网补全。
  // 豆瓣防封批（2026-09-26 拍板）：二次查询命中本地缓存时不静默采用，
  // 出「用缓存 / 仍联网查询」询问行（''＝不显示）。
  String _dbAskCode = '';
  String _dbAskTitle = '';

  @override
  void initState() {
    super.initState();
    // 输入即时联动：作者提示行、更多资料摘要、封面预览书名。
    for (final c in [_author, _fee, _title]) {
      c.addListener(_onEdit);
    }
  }

  void _onEdit() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _isbnT?.cancel();
    for (final c in [
      _title, _author, _publisher, _translator, _pubDate, _series, _isbn,
      _source, _grp, _fee, _totalLoc, _readLoc, _pages, _readPages, _pct,
      _intro, _note,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static String? _nz(String s) => s.trim().isEmpty ? null : s.trim();

  // 原型 BS_PW：页数 / 位置 / 章节 / 百分比 / 分钟。
  static const _ways = <String, String>{
    Book.kWayPage: '页数',
    Book.kWayPos: '位置',
    Book.kWayChap: '章节',
    Book.kWayPct: '百分比',
    Book.kWayMin: '分钟',
  };

  Future<void> _save() async {
    if (_busy) return;
    if (_title.text.trim().isEmpty) {
      // F2-12（LH-K32）：必填校验落字段下方（就地红字·输入即撤），不再弹提示条
      // —— 模态弹层内的 toast 会被遮罩吞，故一律不走页面提示条。
      setState(() => _titleErr = '书名必填');
      return;
    }
    setState(() => _busy = true);
    final b = _b;
    final now = DateTime.now().millisecondsSinceEpoch;
    final repo = ref.read(readRepositoryProvider);
    final way = _way;
    int pages;
    int rp;
    String state = _state;
    double? totLoc = double.tryParse(_totalLoc.text.trim());
    double? rdLoc = double.tryParse(_readLoc.text.trim());
    if (b == null) {
      // 原型 shSaveNew：pg＝总页数（空则 300）· rp＝min(pg, 已读页)。
      pages = int.tryParse(_pages.text.trim()) ?? 300;
      rp = (int.tryParse(_readPages.text.trim()) ?? 0).clamp(0, pages);
    } else {
      // 原型 shSaveEdit：pg 空则保留 · 进度%→rp · 100% 自动落「已读」。
      pages = int.tryParse(_pages.text.trim()) ?? b.pages;
      final p = (double.tryParse(_pct.text.trim()) ?? b.percent)
          .clamp(0, 100)
          .round();
      rp = pages <= 0 ? b.readPages : (pages * p / 100).round();
      if (p >= 100) state = Book.kStateDone;
      if (way == Book.kWayPos) {
        totLoc = totLoc ?? b.totalLoc;
        rdLoc = rdLoc ?? b.readLoc;
        if (totLoc != null && totLoc > 0 && rdLoc != null) {
          rp = (rdLoc / totLoc * pages).round().clamp(0, pages);
        }
      }
    }
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
      colorIdx: _colorIdx,
      state: state,
      format: _format,
      progressWay: way,
      pages: pages,
      readPages: rp,
      totalLoc: totLoc,
      readLoc: rdLoc,
      chapter: b?.chapter,
      rating: b == null ? 0 : _rate.toDouble(),
      fee: double.tryParse(_fee.text.trim()) ?? 0,
      feeTxnId: b?.feeTxnId,
      source: _nz(_source.text),
      grp: _nz(_grp.text),
      tags: _tags,
      startedAt: b?.startedAt,
      endedAt: b?.endedAt,
      lastReadAt: b?.lastReadAt,
      intro: _nz(_intro.text),
      authorNote: b?.authorNote,
      note: _isNew ? _nz(_note.text) : b?.note,
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
    readToast(
      context,
      b == null
          ? '《${book.title}》已加入书架 · '
                '${_state == Book.kStateReading ? '可直接开始计时' : '在「$_state」分区'}'
          : '书籍信息已保存',
    );
  }

  /// 移出书架（原型 shArchiveEdit：编辑页专用 · 移入弃读而非删除）。
  Future<void> _archive() async {
    final b = _b;
    if (b == null) return;
    await ref.read(readRepositoryProvider).setBookState(b.id, Book.kStateDropped);
    if (!mounted) return;
    ref.read(readTickProvider.notifier).state++;
    Navigator.of(context).pop();
    readToast(context, '《${b.title}》已移到弃读 · 笔记与时长保留');
  }

  // ---- 批F2 · ISBN 扫码与豆瓣补全 ----

  Future<void> _scanIsbn() async {
    final code = await GoRouter.of(context).push<String>('/read/scan');
    if (!mounted || code == null) return;
    _isbn.text = code;
    readToast(context, '已扫描书脊 ISBN');
    _onIsbnChanged(fromScan: true);
  }

  Future<void> _isbnCover() async {
    final v = _isbn.text.trim(); // 编辑态同样以输入框现值为准（改完即可重取）。
    if (v.length < 8) {
      readToast(context, '先填 ISBN（至少 8 位）');
      return;
    }
    setState(() => _isbnStatus = '取图中…');
    await _lookupFill(v, coverOnly: true);
  }

  /// ISBN 输入即时反馈（原型 shIsbnHint）：设置关闭时只存码不联网。
  void _onIsbnChanged({bool fromScan = false}) {
    _isbnT?.cancel();
    final v = _isbn.text.trim();
    if (v.isEmpty) {
      setState(() {
        _isbnStatus = '';
        _dbAskCode = '';
      });
      return;
    }
    if (v.length < 8) {
      setState(() {
        _isbnStatus = '至少 8 位';
        _dbAskCode = '';
      });
      return;
    }
    if (!_fillDouban) {
      setState(() {
        _isbnStatus = '仅填 ISBN · 留空待补';
        _dbAskCode = '';
      });
      return;
    }
    setState(() {
      _isbnStatus = '匹配中…';
      _dbAskCode = '';
    });
    _isbnT = Timer(
      Duration(milliseconds: fromScan ? 0 : 520),
      () => _lookupFill(v, coverOnly: false),
    );
  }

  /// [fromCacheAsk]＝用户在询问行里选了「仍联网查询」，本次不再问缓存。
  Future<void> _lookupFill(
    String code, {
    required bool coverOnly,
    bool fromCacheAsk = false,
  }) async {
    final seq = ++_isbnSeq;
    final repo = ref.read(readRepositoryProvider);
    // 缓存优先判定（纯本地，不发网络请求）：命中→询问；取图请求直接吃
    // 已落盘的封面文件，省一次图床流量。
    final hit = await repo.doubanCacheRow(code);
    if (!mounted || seq != _isbnSeq) return;
    if (hit != null && coverOnly) {
      final cp = hit['cover_path'] as String?;
      if (cp != null && await File(cp).exists()) {
        setState(() {
          _cover = cp;
          _isbnStatus = '封面已取';
        });
        return;
      }
    }
    if (hit != null && !coverOnly && !fromCacheAsk) {
      setState(() {
        _dbAskCode = code;
        _dbAskTitle = '${hit['title'] ?? ''}';
        _isbnStatus = '本地已有缓存';
      });
      return;
    }
    final out = await IsbnEnrich.lookupDetailed(
      code,
      fetch: ref.read(isbnPageFetcherProvider),
      // 书名兜底：ISBN 没登记/整页断连时按书名在豆瓣反查（真机反馈②）。
      title: _title.text.trim(),
      // 联想空结果再用「书名+作者」重试一次（同名书少抓一次整页）。
      author: _author.text.trim(),
    );
    if (!mounted || seq != _isbnSeq) return;
    final meta = out.meta;
    if (meta == null) {
      // 成因分档显示（网络不通 / 访问受限 / 豆瓣未收录），细节（HTTP 码、异常）在日志页可查。
      setState(() => _isbnStatus = isbnMissLabel(out.miss));
      if (coverOnly) readToast(context, '未取到封面');
      return;
    }
    final viaTitle = out.viaSuggest;
    String? coverPath;
    if (meta.coverUrl != null &&
        (coverOnly || _cover == null || _cover!.isEmpty)) {
      coverPath = await IsbnEnrich.saveCover(
        meta,
        code,
        fetchBytes: ref.read(isbnBytesFetcherProvider),
      );
      if (!mounted || seq != _isbnSeq) return;
    }
    // 豆瓣防封批（2026-09-26）：联网命中即写本地缓存（v23 douban_meta ·
    // 只存最小字段集），二次查询先提醒「本地已有数据」由用户选用缓存
    // 还是仍联网（选择交互随原型确认后接入；本行只负责落）。
    await ref.read(readRepositoryProvider).doubanCachePut(
      code,
      meta,
      coverPath: coverPath,
      viaSuggest: viaTitle,
    );
    if (!mounted || seq != _isbnSeq) return;
    _applyDouban(
      meta,
      viaTitle: viaTitle,
      coverPath: coverPath,
      coverOnly: coverOnly,
      cached: false,
    );
  }

  /// 豆瓣元数据落表单（联网命中与缓存命中共用；只填空字段，不覆盖用户已敲内容）。
  void _applyDouban(
    IsbnBookMeta meta, {
    required bool viaTitle,
    String? coverPath,
    required bool coverOnly,
    required bool cached,
  }) {
    setState(() {
      _dbAskCode = '';
      if (coverPath != null) _cover = coverPath;
      if (!coverOnly) {
        if (_title.text.trim().isEmpty) _title.text = meta.title;
        if (_author.text.trim().isEmpty && meta.author != null) {
          _author.text = meta.author!;
        }
        if (_publisher.text.trim().isEmpty && meta.publisher != null) {
          _publisher.text = meta.publisher!;
        }
        if (_pubDate.text.trim().isEmpty && meta.pubDate != null) {
          _pubDate.text = meta.pubDate!;
        }
        if (_pages.text.trim().isEmpty && meta.pages != null) {
          _pages.text = '${meta.pages}';
        }
        // 数据来源说清楚：缓存命中 / 按书名匹配 / 条码直接命中，三种口径不混。
        _isbnStatus = switch ((cached, viaTitle)) {
          (true, _) => '缓存命中 · 已填充',
          (false, true) => '按书名匹配 · 已填充',
          (false, false) => '已命中 · 自动填充',
        };
      } else {
        _isbnStatus = coverPath != null ? '封面已取' : '未取到封面';
      }
    });
    if (coverOnly && _isbnStatus != '封面已取') {
      readToast(context, '未取到封面');
    }
  }

  /// 询问行「用缓存」：本地行直接回填，不发任何豆瓣请求；缓存里没落封面
  /// 但存了图床 URL 时补取一次图（仍是用户点出来的显式动作）。
  Future<void> _dbUseCache() async {
    final code = _dbAskCode;
    if (code.isEmpty) return;
    final hit = await ref.read(readRepositoryProvider).doubanCacheRow(code);
    if (!mounted) return;
    if (hit == null) {
      // 缓存行没了（刚好被清理）：退化为联网查询，不再询问。
      await _lookupFill(code, coverOnly: false, fromCacheAsk: true);
      return;
    }
    final meta = IsbnEnrich.metaFromRow(hit);
    final cp = hit['cover_path'] as String?;
    String? coverPath =
        (cp != null && File(cp).existsSync()) ? cp : null;
    if (coverPath == null &&
        meta.coverUrl != null &&
        (_cover == null || _cover!.isEmpty)) {
      coverPath = await IsbnEnrich.saveCover(
        meta,
        code,
        fetchBytes: ref.read(isbnBytesFetcherProvider),
      );
      if (!mounted) return;
    }
    _applyDouban(
      meta,
      viaTitle: (hit['via_suggest'] as int? ?? 0) == 1,
      coverPath: coverPath,
      coverOnly: false,
      cached: true,
    );
  }

  /// 询问行「仍联网查询」：走完整抓取链（成功后刷新缓存行）。
  void _dbRefetch() {
    final code = _dbAskCode;
    setState(() => _dbAskCode = '');
    if (code.isNotEmpty) {
      _lookupFill(code, coverOnly: false, fromCacheAsk: true);
    }
  }

  Future<void> _pickCover({bool camera = false}) async {
    final cs = Theme.of(context).colorScheme;
    final path = await pickAndStoreImage(
      context,
      bg: cs.surfaceContainerLow,
      fg: cs.onSurface,
      direct: camera ? ImageSource.camera : ImageSource.gallery,
    );
    if (path != null && mounted) setState(() => _cover = path);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final srcs =
        ref.watch(dictProvider(DictEntry.kSource)).valueOrNull ??
        const <DictEntry>[];
    final grps =
        ref.watch(dictProvider(DictEntry.kGroup)).valueOrNull ??
        const <DictEntry>[];
    final tagDict =
        ref.watch(dictProvider(DictEntry.kTag)).valueOrNull ??
        const <DictEntry>[];
    final authors =
        ref.watch(dictProvider(DictEntry.kAuthor)).valueOrNull ??
        const <DictEntry>[];
    final pubs =
        ref.watch(dictProvider(DictEntry.kPublisher)).valueOrNull ??
        const <DictEntry>[];
    final aTxt = _author.text.trim();
    final hasNewAuthor =
        aTxt.isNotEmpty && !authors.any((e) => e.name == aTxt);
    // 批F2：阅读设置「ISBN 补全」＝抓豆瓣数据 时才联网（默认仅填 ISBN）。
    _fillDouban =
        (ref.watch(
                  readKvProvider(('read.isbnFill', '仅填 ISBN')),
                ).valueOrNull ??
                '仅填 ISBN') ==
            '抓豆瓣数据';

    final header = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _isNew ? '添加新书到书架' : '编辑书籍信息',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          // 扫码入口两态都有（2026-09-26 拍板）：编辑态补了 ISBN 行后，
          // 改码最常见的路径是对着书脊重扫，而不是手敲 13 位。
          GestureDetector(
            key: const ValueKey('bkf-scan'),
            onTap: _scanIsbn,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: tokens.accent.withValues(alpha: .5),
                ),
              ),
              child: Text(
                '扫 ISBN',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: tokens.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final authorRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _field(_author, '作者', keyName: 'bkf-author')),
        const SizedBox(width: 8),
        OutlinedButton(
          key: const ValueKey('bkf-pick-author'),
          onPressed: () => _showAuthorPickSheet(context, (a) {
            setState(() => _author.text = a);
            readToast(context, '已选作者：$a');
          }),
          child: const Text('从列表选', style: TextStyle(fontSize: 11)),
        ),
      ],
    );
    final authorHint = Wrap(
      key: const ValueKey('bkf-author-hint'),
      spacing: 0,
      children: [
        Text(
          '作者库 ${authors.length} 位 · ',
          style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
        ),
        GestureDetector(
          onTap: () => _showAuthorPickSheet(context, (a) {
            setState(() => _author.text = a);
            readToast(context, '已选作者：$a');
          }),
          child: Text(
            '从列表选择',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: tokens.accent,
            ),
          ),
        ),
        if (hasNewAuthor)
          Text(
            ' · 保存时将自动登记新作者「$aTxt」',
            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
          ),
      ],
    );
    final pubHint = Text(
      key: const ValueKey('bkf-pub-hint'),
      '出版社库 ${pubs.length} 家 · 新名字保存后自动登记',
      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
    );
    final moreSum =
        '$_format · ${_ways[_way] ?? '页数'}${_fee.text.trim().isNotEmpty ? ' · ¥${_fee.text.trim()}' : ''}';
    final moreBtn = Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          GestureDetector(
            key: const ValueKey('bkf-more'),
            onTap: () => setState(() => _moreOpen = !_moreOpen),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: tokens.cardBorder),
              ),
              child: Text(
                '更多资料',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              moreSum,
              key: const ValueKey('bkf-more-sum'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
    final moreFields = [
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(child: _field(_translator, '译者', keyName: 'bkf-translator')),
          const SizedBox(width: 8),
          Expanded(
            child: _field(_pubDate, '出版日期（如 2015-06）', keyName: 'bkf-pubdate'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      _lbl('书籍类型'),
      _Chips(
        items: Book.formats,
        selected: {_format},
        keys: const ['bkf-fmt-纸质', 'bkf-fmt-电子书', 'bkf-fmt-有声'],
        onPick: (v) => setState(() {
          _format = v;
          // 原型 ebxSet：仅新书联动默认进度方式，编辑保持已选。
          if (_isNew) _way = Book.defaultWayFor(v);
        }),
      ),
      const SizedBox(height: 10),
      _lbl('进度方式'),
      _Chips(
        items: _ways.values.toList(),
        selected: {_ways[_way] ?? '页数'},
        keys: [for (final k in _ways.keys) 'bkf-way-$k'],
        onPick: (v) => setState(
          () => _way = _ways.entries.firstWhere((e) => e.value == v).key,
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _field(_totalLoc, '总位置 / 总页', keyName: 'bkf-loc'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _field(_readLoc, '已读位置', keyName: 'bkf-readloc'),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 72, child: _field(_fee, '¥', keyName: 'bkf-fee')),
        ],
      ),
      const SizedBox(height: 10),
      _field(_series, '系列 / 套装', keyName: 'bkf-series'),
      const SizedBox(height: 10),
      _field(_intro, '书籍简介（导入源可自动带出）', lines: 2, keyName: 'bkf-intro'),
    ];
    final stChips = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _lbl('分区'),
        _Chips(
          items: Book.states,
          selected: {_state},
          keys: [for (final s in Book.states) 'bkf-st-$s'],
          onPick: (v) => setState(() => _state = v),
        ),
      ],
    );
    final tagChips = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _lbl('标签（可多选）'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in tagDict)
              GestureDetector(
                key: ValueKey('bkf-tag-${e.name}'),
                onTap: () => setState(
                  () => _tags.contains(e.name)
                      ? _tags.remove(e.name)
                      : _tags.add(e.name),
                ),
                child: _pill(
                  cs,
                  tokens,
                  '#${e.name}',
                  _tags.contains(e.name),
                ),
              ),
            if (tagDict.isEmpty)
              Text(
                '还没有标签 · 可在书架资料里新增',
                style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ],
    );
    // 真机反馈（2026-09-26）：ISBN 原先只在「添加新书」里有入口，建完就改不了
    // （也再也触发不了豆瓣补全）。现在添加/编辑两态共用这一块：输入即校验、
    // 命中状态就地显示，编辑态同样能改码后重抓。
    final isbnRow = Row(
      children: [
        Expanded(
          child: _field(_isbn, 'ISBN / 豆瓣 subject_id',
              keyName: 'bkf-isbn', onChanged: (_) => _onIsbnChanged()),
        ),
        SizedBox(
          width: 84,
          child: Text(
            _isbnStatus,
            key: const ValueKey('bkf-isbn-status'),
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
    // 豆瓣防封批（2026-09-26 拍板 · 原型 nbCacheAsk/ebCacheAsk）：二次查询
    // 命中本地缓存不静默采用，就地出「用缓存 / 仍联网查询」两个入口。
    final isbnBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        isbnRow,
        if (_dbAskCode.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              key: const ValueKey('bkf-cache-ask'),
              children: [
                Expanded(
                  child: Text(
                    '本地已有《$_dbAskTitle》缓存',
                    style: TextStyle(
                      fontSize: 10,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                _miniBtn(context, 'bkf-cache-use', '用缓存', _dbUseCache),
                const SizedBox(width: 6),
                _miniBtn(context, 'bkf-cache-net', '仍联网查询', _dbRefetch),
              ],
            ),
          ),
      ],
    );
    final covBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _lbl(
          _isNew
              ? '封面（可上传 / 拍照 / 按 ISBN 取图，或直接选书脊色）'
              : '书籍封面',
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: _cover != null && _cover!.isNotEmpty
                      ? Image.file(
                          File(_cover!),
                          width: 44,
                          height: 62,
                          fit: BoxFit.cover,
                        )
                      : BsCover(
                          book: Book(
                            id: '',
                            title: _title.text,
                            colorIdx: _colorIdx,
                            createdAt: 0,
                            updatedAt: 0,
                          ),
                          width: 44,
                          height: 62,
                          radius: 6,
                          showAuthor: false,
                          showBadge: false,
                        ),
                ),
                if (_cover != null && _cover!.isNotEmpty)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: GestureDetector(
                      key: const ValueKey('bkf-cov-clear'),
                      onTap: () {
                        setState(() => _cover = null);
                        readToast(context, '已改回书脊色封面');
                      },
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _miniBtn(context, 'bkf-cov-file', '上传封面',
                          () => _pickCover()),
                      _miniBtn(context, 'bkf-cov-cam', '拍照',
                          () => _pickCover(camera: true)),
                      _miniBtn(context, 'bkf-cov-isbn', 'ISBN 取图',
                          _isbnCover),
                      if (!_isNew)
                        _miniBtn(context, 'bkf-cov-clear2', '清除', () {
                          if (_cover == null || _cover!.isEmpty) return;
                          setState(() => _cover = null);
                          readToast(context, '已改回书脊色封面');
                        }),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (var i = 0; i < kBsCov.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: GestureDetector(
                            key: ValueKey('bkf-cov-$i'),
                            onTap: () => setState(() {
                              _colorIdx = i;
                              _cover = null;
                            }),
                            child: Container(
                              width: 22,
                              height: 30,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [kBsCov[i].$1, kBsCov[i].$2],
                                ),
                                borderRadius: BorderRadius.circular(5),
                                border: (_cover == null ||
                                        _cover!.isEmpty) &&
                                    _colorIdx == i
                                ? Border.all(
                                    color: tokens.accent,
                                    width: 2,
                                  )
                                : null,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (!_isNew)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '无封面时用书脊色块；图片本地保存，超 2MB 自动压到长边 800px',
                        style: TextStyle(
                          fontSize: 9.5,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
    final footer = _isNew
        ? FilledButton(
            key: const ValueKey('bkf-save'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            onPressed: _save,
            child: const Text('加入书架'),
          )
        : Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('bkf-archive'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    foregroundColor: cs.error,
                  ),
                  onPressed: _archive,
                  child: const Text('移出书架', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('bkf-save'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  // F2-15：保存中置灰点不动，连点只落一次写。
                  onPressed: _busy ? null : _save,
                  child: const Text('保存'),
                ),
              ),
            ],
          );

    List<Widget> middle() {
      if (_isNew) {
        return [
          // F2-12（LH-K32）：书名必填错误贴输入框下方（就地红字·输入即撤）。
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(_title, '书名（必填）', keyName: 'bkf-title',
                  onChanged: (_) {
                    if (_titleErr != null) setState(() => _titleErr = null);
                  }),
              FieldError(_titleErr),
            ],
          ),
          const SizedBox(height: 10),
          authorRow,
          const SizedBox(height: 4),
          authorHint,
          const SizedBox(height: 6),
          _field(_publisher, '出版社（可留空，保存后自动登记）',
              keyName: 'bkf-publisher'),
          const SizedBox(height: 10),
          _lbl('来源'),
          _dictChips('bkf-src', srcs, _source.text, (
            v,
          ) => setState(() => _source.text = v)),
          const SizedBox(height: 10),
          _lbl('分组'),
          _dictChips('bkf-grp', grps, _grp.text, (
            v,
          ) => setState(() => _grp.text = v)),
          const SizedBox(height: 4),
          pubHint,
          moreBtn,
          if (_moreOpen) ...moreFields,
          const SizedBox(height: 10),
          isbnBlock,
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _field(_pages, '总页数', keyName: 'bkf-pages')),
              const SizedBox(width: 8),
              Expanded(
                child: _field(_readPages, '已读页（可选）', keyName: 'bkf-read'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          stChips,
          const SizedBox(height: 12),
          tagChips,
          const SizedBox(height: 12),
          covBlock,
          const SizedBox(height: 10),
          _field(_note, '一句话：为什么想读（可选）',
              lines: 2, keyName: 'bkf-note'),
          const SizedBox(height: 10),
          Text(
            '录入后可在详情页开计时；ISBN 命中后按阅读设置「ISBN 补全」开关决定是否抓取豆瓣书目自动填充书名、作者、出版社、页数、封面与评分（ISBN 未登记或整页取不到时按书名在豆瓣反查；关闭或离线时留空待补）',
            style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant),
          ),
        ];
      }
      return [
        covBlock,
        const SizedBox(height: 12),
        // F2-12（LH-K32）：编辑态同源校验（`_save` 共用）·就地红字·输入即撤。
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _field(_title, '书名', keyName: 'bkf-title', onChanged: (_) {
              if (_titleErr != null) setState(() => _titleErr = null);
            }),
            FieldError(_titleErr),
          ],
        ),
        const SizedBox(height: 10),
        authorRow,
        const SizedBox(height: 4),
        authorHint,
        const SizedBox(height: 10),
        _lbl('来源'),
        _dictChips('bkf-src', srcs, _source.text, (v) => setState(
          () => _source.text = _source.text == v ? '' : v,
        )),
        const SizedBox(height: 10),
        _lbl('分组'),
        _dictChips('bkf-grp', grps, _grp.text, (v) => setState(
          () => _grp.text = _grp.text == v ? '' : v,
        )),
        const SizedBox(height: 4),
        pubHint,
        moreBtn,
        if (_moreOpen) ...moreFields,
        const SizedBox(height: 10),
        isbnBlock,
        const SizedBox(height: 10),
        _field(_publisher, '出版社', keyName: 'bkf-publisher'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _field(_pages, '总页数', keyName: 'bkf-pages')),
            const SizedBox(width: 8),
            Expanded(child: _field(_pct, '进度 %', keyName: 'bkf-pct')),
          ],
        ),
        const SizedBox(height: 12),
        stChips,
        const SizedBox(height: 12),
        tagChips,
        const SizedBox(height: 12),
        _lbl('评分'),
        Row(
          children: [
            for (var i = 1; i <= 5; i++)
              GestureDetector(
                key: ValueKey('bkf-rate-$i'),
                onTap: () => setState(() => _rate = i),
                child: Icon(
                  Icons.star_rounded,
                  size: 20,
                  color: i <= _rate
                      ? const Color(0xFFF5A623)
                      : cs.outlineVariant,
                ),
              ),
          ],
        ),
      ];
    }

    // 轮3：保存/移出钮固定在弹层底部，不随长表单滚动（钮永远可见可点）。
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [header, ...middle(), const SizedBox(height: 10)],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: footer,
        ),
      ],
    );
  }
}
