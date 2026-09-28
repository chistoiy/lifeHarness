import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/image_attach.dart' show pickAndStoreImage;
import '../../data/isbn_enrich.dart';
import '../../data/read_import.dart' show normIsbn;
import '../../domain/book.dart';
import '../../domain/book_dict.dart';
import '../biblio/biblio_search_page.dart';
import './book_mgr_page.dart';
import '../biblio/isbn_scan_page.dart';
import '../read_providers.dart';
import '../read_sheets.dart' show readToast, isbnMissLabel;
import '../widgets/bs_cover.dart';

/// V1.44 统一入口：有 GoRouter 走路由（线上），无路由（widget 测试/异常栈）
/// 退回 Navigator push，两页同策。语义恒为 push（返回保留来源页）。
Future<void> openBookForm(
  BuildContext context, {
  String? bookId,
  Object? seed,
}) async {
  final r = GoRouter.maybeOf(context);
  if (r != null) {
    final q = bookId == null ? '' : '?id=$bookId';
    await r.push('/read/book-form$q', extra: seed);
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => BookFormPage(bookId: bookId, seed: seed)),
  );
}

/// 添加图书＝先搜后加（原型 shNewOpen→bsrOpen 改道）。
Future<void> openBiblioSearch(BuildContext context) async {
  final r = GoRouter.maybeOf(context);
  if (r != null) {
    await r.push('/read/biblio-search');
    return;
  }
  await Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const BiblioSearchPage()));
}

/// V1.44「先搜后加」· 书籍录入/编辑整页表单（原型 p-bookForm · bfRender）。
/// 五组卡片行式（左标签右输入）：基础信息 / 简介信息 / 书籍管理 / 来源信息 /
/// 购买信息。三种起手式共用一张表单：
/// · [bookId] 非空＝编辑态（repo.bookById 回填，豆瓣评分从 douban_cache 取只读显）；
/// · [seed]＝[DoubanSearchRow] 豆瓣带入：先即时填列表已知字段，再 detailById 拉全字段照填（只填空字段）；
/// · [seed]＝String ISBN：填码走补全链；null＝手动录入。
/// 保存语义与 read_sheets_b2 的 _BookForm 一致（addBook/updateBook · feeTxn、
/// 字典登记、read.newPos 全部在 repo 写路径内 · readTick 广播 · 同款文案）。
class BookFormPage extends ConsumerStatefulWidget {
  const BookFormPage({super.key, this.bookId, this.seed});

  final String? bookId;

  /// DoubanSearchRow（点搜索结果带入）/ String（ISBN 扫码或条码直输）/ null 手动。
  final Object? seed;

  @override
  ConsumerState<BookFormPage> createState() => _BookFormPageState();
}

class _BookFormPageState extends ConsumerState<BookFormPage> {
  Book? _editing; // 编辑态现书（initState 异步回填）
  bool get _isNew => _editing == null;

  final _title = TextEditingController();
  final _author = TextEditingController();
  final _translator = TextEditingController();
  final _publisher = TextEditingController();
  final _pubDate = TextEditingController();
  final _series = TextEditingController();
  final _binding = TextEditingController();
  final _isbn = TextEditingController();
  final _wc = TextEditingController();
  final _intro = TextEditingController();
  final _authorNote = TextEditingController();
  final _grp = TextEditingController();
  final _source = TextEditingController();
  final _pages = TextEditingController();
  final _readPages = TextEditingController();
  final _fee = TextEditingController();
  final _feeDate = TextEditingController();

  late String _state = Book.kStateWant;
  late String _format = Book.kFormatPaper;
  late String _way = Book.defaultWayFor(_format);
  final List<String> _tags = [];
  // V1.46⑧ 行内添加标签：展开态 + 草稿输入（就地内嵌，不走弹层）。
  bool _tagAddOpen = false;
  final _newTag = TextEditingController();
  int _rate = 0;
  String? _cover;
  late int _colorIdx = Random().nextInt(kBsCov.length);

  /// 豆瓣评分（10 分制 · 只读行；来自搜索行/详情页/本地缓存，不做换算冒充）。
  double? _doubanRating;

  // ISBN 补全链（口径沿用 _BookForm：状态文案 + 防抖 + 询问行）。
  String _isbnStatus = '';
  Timer? _isbnT;
  int _isbnSeq = 0;
  bool _fillDouban = false;
  String _dbAskCode = '';
  String _dbAskTitle = '';

  // 简介信息折叠（有内容默认展开 · 原型 details open）。
  bool _introOpen = false;
  bool _anOpen = false;

  @override
  void initState() {
    super.initState();
    final seed = widget.seed;
    final id = widget.bookId;
    if (id != null) {
      _loadEdit(id);
    } else if (seed is DoubanSearchRow) {
      _fillFromRow(seed);
      _enrichFromDetail(seed.subjectId);
    } else if (seed is String && seed.trim().isNotEmpty) {
      _isbn.text = seed.trim();
      // 等首帧把「ISBN 补全」设置读进 _fillDouban 再触发补全链。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onIsbnChanged(fromScan: true);
      });
    }
  }

  @override
  void dispose() {
    _isbnT?.cancel();
    for (final c in [
      _title, _author, _translator, _publisher, _pubDate, _series, _binding,
      _isbn, _wc, _intro, _authorNote, _grp, _source, _pages, _readPages,
      _fee, _feeDate, _newTag,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static String? _nz(String s) => s.trim().isEmpty ? null : s.trim();

  // ---- 标签行内添加（V1.46⑧ · 就地内嵌，禁两段式弹层）----

  /// 确认钮逻辑：空名/重名只 toast 不新增；成功＝dictAdd 落字典＋立即选中
  /// ＋readTick 广播刷新 chips 行。重名/空名判定即在此页面逻辑里做。
  Future<void> _addTag() async {
    final name = _newTag.text.trim();
    if (name.isEmpty) {
      readToast(context, '标签名不能为空');
      return;
    }
    final dict =
        ref.read(dictProvider(DictEntry.kTag)).valueOrNull ??
        const <DictEntry>[];
    if (dict.any((e) => e.name == name)) {
      readToast(context, '标签已存在');
      return;
    }
    await ref.read(readRepositoryProvider).dictAdd(DictEntry.kTag, name);
    if (!mounted) return;
    setState(() {
      if (!_tags.contains(name)) _tags.add(name);
      _tagAddOpen = false;
      _newTag.clear();
    });
    ref.read(readTickProvider.notifier).state++;
  }

  // ---- 回填 ----

  Future<void> _loadEdit(String id) async {
    final repo = ref.read(readRepositoryProvider);
    final b = await repo.bookById(id);
    if (!mounted || b == null) return;
    setState(() {
      _editing = b;
      _title.text = b.title;
      _author.text = b.author;
      _translator.text = b.translator ?? '';
      _publisher.text = b.publisher ?? '';
      _pubDate.text = b.pubDate ?? '';
      _series.text = b.series ?? '';
      _binding.text = b.binding ?? '';
      _isbn.text = b.isbn ?? '';
      _wc.text = b.wordCount > 0 ? '${b.wordCount}' : '';
      _intro.text = b.intro ?? '';
      _authorNote.text = b.authorNote ?? '';
      _grp.text = b.grp ?? '';
      _source.text = b.source ?? '';
      _pages.text = b.pages > 0 ? '${b.pages}' : '';
      _readPages.text = b.readPages > 0 ? '${b.readPages}' : '';
      _fee.text = b.fee > 0 ? '${b.fee}' : '';
      _feeDate.text = b.feeDate ?? '';
      _state = b.state;
      _format = b.format;
      _way = b.progressWay;
      _tags
        ..clear()
        ..addAll(b.tags);
      _rate = b.rating.round();
      _cover = b.coverPath;
      _colorIdx = b.colorIdx;
      _introOpen = _intro.text.trim().isNotEmpty;
      _anOpen = _authorNote.text.trim().isNotEmpty;
    });
    // 豆瓣评分只读行：从本地缓存行取（编辑态不新发网络请求）。
    final isbn = b.isbn;
    if (isbn != null && isbn.trim().isNotEmpty) {
      final row = await repo.doubanCacheRow(isbn);
      if (!mounted) return;
      setState(() => _doubanRating = (row?['rating'] as num?)?.toDouble());
    }
  }

  /// 点搜索结果带入：列表已知字段即时填（用户可当场改）。
  void _fillFromRow(DoubanSearchRow r) {
    setState(() {
      _title.text = r.title;
      _author.text = r.author ?? '';
      _publisher.text = r.publisher ?? '';
      _pubDate.text = r.pubDate ?? '';
      _doubanRating = r.rating;
      final fee = double.tryParse(
        RegExp(r'[\d.]+').firstMatch(r.price ?? '')?.group(0) ?? '',
      );
      if (fee != null && _fee.text.trim().isEmpty) _fee.text = '$fee';
      _introOpen = _intro.text.trim().isNotEmpty;
      _anOpen = _authorNote.text.trim().isNotEmpty;
    });
  }

  /// 豆瓣带入：按 subject_id 拉详情页全字段照填（定价→购入价格 · 来源默认豆瓣）。
  Future<void> _enrichFromDetail(String subjectId) async {
    final seq = ++_isbnSeq;
    setState(() => _isbnStatus = '匹配中…');
    final meta = await IsbnEnrich.detailById(
      subjectId,
      fetch: ref.read(isbnPageFetcherProvider),
    );
    if (!mounted || seq != _isbnSeq) return;
    if (meta == null) {
      // 详情没取到：列表行字段已填，口径写清是「按书名匹配」不是命中条码。
      setState(
        () => _isbnStatus = DoubanGuard.active()
            ? isbnMissLabel(IsbnMiss.blocked)
            : '按书名匹配 · 已填充',
      );
      return;
    }
    String? coverPath;
    if (meta.coverUrl != null && (_cover == null || _cover!.isEmpty)) {
      coverPath = await IsbnEnrich.saveCover(
        meta,
        meta.isbn ?? subjectId,
        fetchBytes: ref.read(isbnBytesFetcherProvider),
      );
      if (!mounted || seq != _isbnSeq) return;
    }
    _applyDouban(meta, viaTitle: false, coverPath: coverPath, cached: false);
    setState(() => _source.text = _source.text.trim().isEmpty ? '豆瓣' : _source.text);
  }

  // ---- ISBN 补全链（口径与 _BookForm 一致）----

  Future<void> _scanIsbn() async {
    String? code;
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      code = await router.push<String>('/read/scan');
    } else {
      code = await Navigator.of(
        context,
      ).push<String>(MaterialPageRoute(builder: (_) => const IsbnScanPage()));
    }
    if (!mounted || code == null) return;
    _isbn.text = code;
    readToast(context, '已扫描书脊 ISBN');
    _onIsbnChanged(fromScan: true);
  }

  Future<void> _isbnCover() async {
    final v = _isbn.text.trim(); // 两态都以输入框现值为准（改完即可重取）。
    if (v.length < 8) {
      readToast(context, '先填 ISBN（至少 8 位）');
      return;
    }
    setState(() => _isbnStatus = '取图中…');
    await _lookupFill(v, coverOnly: true);
  }

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
    // 缓存优先判定（纯本地，不发网络请求）：命中→询问；取图直接吃已落盘封面。
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
      title: _title.text.trim(),
      author: _author.text.trim(),
    );
    if (!mounted || seq != _isbnSeq) return;
    final meta = out.meta;
    if (meta == null) {
      setState(() => _isbnStatus = isbnMissLabel(out.miss));
      if (coverOnly) readToast(context, '未取到封面');
      return;
    }
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
    await repo.doubanCachePut(
      code,
      meta,
      coverPath: coverPath,
      viaSuggest: out.viaSuggest,
    );
    if (!mounted || seq != _isbnSeq) return;
    _applyDouban(
      meta,
      viaTitle: out.viaSuggest,
      coverPath: coverPath,
      coverOnly: coverOnly,
      cached: false,
    );
  }

  /// 询问行「用缓存」：本地行直接回填，不发任何豆瓣请求。
  Future<void> _dbUseCache() async {
    final code = _dbAskCode;
    if (code.isEmpty) return;
    final hit = await ref.read(readRepositoryProvider).doubanCacheRow(code);
    if (!mounted) return;
    if (hit == null) {
      await _lookupFill(code, coverOnly: false, fromCacheAsk: true);
      return;
    }
    final meta = IsbnEnrich.metaFromRow(hit);
    final cp = hit['cover_path'] as String?;
    String? coverPath = (cp != null && File(cp).existsSync()) ? cp : null;
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

  /// 豆瓣元数据落表单：只填空字段，不覆盖用户已敲内容。
  /// V1.44 效率口径「豆瓣能给的全部照填」：比旧 sheet 多填译者/丛书/装帧/
  /// 字数/ISBN/简介/作者简介，且定价落「购入价格」。
  void _applyDouban(
    IsbnBookMeta meta, {
    required bool viaTitle,
    String? coverPath,
    bool coverOnly = false,
    required bool cached,
  }) {
    setState(() {
      _dbAskCode = '';
      if (coverPath != null) _cover = coverPath;
      if (!coverOnly) {
        void fill(
          TextEditingController c,
          String? v, {
          void Function(String)? also,
        }) {
          if (c.text.trim().isEmpty && (v ?? '').isNotEmpty) {
            c.text = v!;
            also?.call(v);
          }
        }

        fill(_title, meta.title);
        fill(_author, meta.author);
        fill(_publisher, meta.publisher);
        fill(_pubDate, meta.pubDate);
        fill(_translator, meta.translator);
        fill(_series, meta.series);
        fill(_binding, meta.binding);
        fill(_isbn, meta.isbn);
        fill(_intro, meta.intro);
        fill(_authorNote, meta.authorNote);
        if (_pages.text.trim().isEmpty && meta.pages != null) {
          _pages.text = '${meta.pages}';
        }
        if (_wc.text.trim().isEmpty && meta.wordCount != null) {
          _wc.text = '${meta.wordCount}';
        }
        if (_fee.text.trim().isEmpty && meta.priceValue != null) {
          _fee.text = '${meta.priceValue}';
        }
        if (meta.rating != null) _doubanRating = meta.rating;
        _introOpen = _introOpen || _intro.text.trim().isNotEmpty;
        _anOpen = _anOpen || _authorNote.text.trim().isNotEmpty;
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

  // ---- 封面 ----

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

  // ---- 保存（语义与 _BookForm._save 一致 · 复用 repo 写路径）----

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      readToast(context, '书名必填');
      return;
    }
    if (widget.bookId != null && _editing == null) return; // 还没载入完
    final b = _editing;
    final now = DateTime.now().millisecondsSinceEpoch;
    final repo = ref.read(readRepositoryProvider);
    final isbn = _nz(_isbn.text);

    // 同 ISBN 已在书架（编辑态除外）：不产生重复书，直接转它的编辑表单。
    if (b == null && isbn != null && normIsbn(isbn).isNotEmpty) {
      final books = await repo.allBooks();
      final dup = books.where(
        (e) =>
            !e.isDeleted &&
            normIsbn(e.isbn).isNotEmpty &&
            normIsbn(e.isbn) == normIsbn(isbn),
      ).firstOrNull;
      if (dup != null) {
        if (!mounted) return;
        readToast(context, '这本书已在书架 · 直接改它的资料');
        final router = GoRouter.maybeOf(context);
        if (router != null) {
          router.pushReplacement('/read/book-form?id=${dup.id}');
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => BookFormPage(bookId: dup.id)),
          );
        }
        return;
      }
    }

    final way = _way;
    int pages;
    int rp;
    String state = _state;
    // 本页不暴露位置输入（旧 sheet 折叠区才有）：编辑态保留现值，新增态为空。
    final totLoc = b?.totalLoc;
    final rdLoc = b?.readLoc;
    if (b == null) {
      // 原型 shSaveNew：pg＝总页数（空则 300）· rp＝min(pg, 已读页)。
      pages = int.tryParse(_pages.text.trim()) ?? 300;
      rp = (int.tryParse(_readPages.text.trim()) ?? 0).clamp(0, pages);
    } else {
      // 原型 shSaveEdit：pg 空则保留 · rp 空则保留 · 读满自动落「已读」。
      pages = int.tryParse(_pages.text.trim()) ?? b.pages;
      final inputRp = int.tryParse(_readPages.text.trim());
      rp = inputRp == null || pages <= 0 ? b.readPages : inputRp.clamp(0, pages);
      if (pages > 0 && rp >= pages) state = Book.kStateDone;
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
      binding: _nz(_binding.text),
      isbn: isbn,
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
      rating: _rate.toDouble(),
      fee: double.tryParse(_fee.text.trim()) ?? 0,
      feeTxnId: b?.feeTxnId,
      source: _nz(_source.text),
      grp: _nz(_grp.text),
      tags: _tags,
      startedAt: b?.startedAt,
      endedAt: b?.endedAt,
      lastReadAt: b?.lastReadAt,
      intro: _nz(_intro.text),
      authorNote: _nz(_authorNote.text),
      note: b?.note,
      finalNote: b?.finalNote,
      sumQuote: b?.sumQuote,
      sumView: b?.sumView,
      sumGain: b?.sumGain,
      wordCount: int.tryParse(_wc.text.trim()) ?? b?.wordCount ?? 0,
      feeDate: _nz(_feeDate.text),
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
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    readToast(
      context,
      b == null
          ? '《${book.title}》已加入书架 · '
                '${state == Book.kStateReading ? '可直接开始计时' : '在「$state」分区'}'
          : '书籍信息已保存',
    );
  }

  // ---- UI 积木（行式＝左标签右输入 · 字号色值对照现有 sheet）----

  Widget _sec(String t) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Text(
      t,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _card(List<Widget> rows) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: .5,
                color: context.tokens.cardBorder,
              ),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _row(String label, Widget child) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: child),
      ],
    ),
  );

  Widget _in(
    TextEditingController c,
    String keyName, {
    String? hint,
    TextInputType? kb,
    bool bold = false,
    ValueChanged<String>? onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      key: ValueKey(keyName),
      controller: c,
      textAlign: TextAlign.right,
      keyboardType: kb,
      style: TextStyle(
        fontSize: 13,
        fontWeight: bold ? FontWeight.w700 : null,
      ),
      onChanged: onChanged,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        border: InputBorder.none,
      ),
    );
  }

  Widget _chips(
    List<String> items,
    Set<String> selected,
    String keyPrefix,
    ValueChanged<String> onPick,
  ) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final v in items)
        GestureDetector(
          key: ValueKey('$keyPrefix-$v'),
          onTap: () => onPick(v),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: selected.contains(v)
                  ? context.tokens.accent.withValues(alpha: .12)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border.all(
                color: selected.contains(v)
                    ? context.tokens.accent
                    : context.tokens.cardBorder,
              ),
            ),
            child: Text(
              v,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected.contains(v)
                    ? context.tokens.accent
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
    ],
  );

  Widget _mini(String key, String label, VoidCallback onTap) => GestureDetector(
    key: ValueKey(key),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
      ),
    ),
  );

  /// 来源/分组下拉（复用 sheet _dictChips 的资料库选择交互：点选一个，
  /// 末项「＋ 新增…」进对应资料管理页）。
  Widget _dictDropdown(String kind, String keyName, TextEditingController c) {
    final cs = Theme.of(context).colorScheme;
    final dict =
        ref.watch(dictProvider(kind)).valueOrNull ?? const <DictEntry>[];
    final isSrc = kind == DictEntry.kSource;
    final cur = c.text.trim();
    // 现值不在字典（如豆瓣带入的「豆瓣」）也要显示，不静默清空。
    final entries = <(String, String)>[
      (cur.isEmpty ? (isSrc ? '未选择来源' : '未选择分组') : cur, cur),
      for (final e in dict)
        if (e.name != cur) (e.name, e.name),
      (isSrc ? '＋ 新增来源…' : '＋ 新增分组…', '__add__'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .5)),
      ),
      child: DropdownButton<String>(
        key: ValueKey(keyName),
        isExpanded: true,
        underline: const SizedBox.shrink(),
        borderRadius: BorderRadius.circular(16),
        style: TextStyle(fontSize: 12.5, color: cs.onSurface),
        value: cur,
        items: [
          for (final (label, v) in entries)
            DropdownMenuItem(
              value: v,
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) {
          if (v == '__add__') {
            final kindSeg = isSrc ? 'source' : 'group';
            final router = GoRouter.maybeOf(context);
            if (router != null) {
              router.push('/read/mgr?kind=$kindSeg');
            } else {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => BookMgrPage(kind: kindSeg)));
            }
            return;
          }
          setState(() => c.text = v ?? '');
        },
      ),
    );
  }

  /// 可折叠多行框（简介信息 · 原型 details；有内容默认展开）。
  Widget _fold({
    required String label,
    required String keyName,
    required TextEditingController c,
    required String hint,
    required bool open,
    required ValueChanged<bool> onToggle,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          key: ValueKey('$keyName-fold'),
          behavior: HitTestBehavior.opaque,
          onTap: () => onToggle(!open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(
                  open ? Icons.expand_more_rounded : Icons.chevron_right_rounded,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              key: ValueKey(keyName),
              controller: c,
              maxLines: 6,
              minLines: 3,
              style: const TextStyle(fontSize: 12, height: 1.6),
              decoration: InputDecoration(
                isDense: true,
                hintText: hint,
                hintStyle: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: .5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _starRow() {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        for (var i = 1; i <= 5; i++)
          GestureDetector(
            key: ValueKey('bf-rate-$i'),
            onTap: () => setState(() => _rate = i),
            child: Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Icon(
                Icons.star_rounded,
                size: 18,
                color: i <= _rate
                    ? const Color(0xFFF5A623)
                    : cs.outlineVariant,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text(
            _rate == 0 ? '未评分' : '$_rate',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  /// 标签行（V1.46⑧）：① 选项来自标签字典（多选 toggle，现状保持）；
  /// ② 行尾「＋ 添加标签」chip 就地展开输入行（禁两段式弹层），确认后
  /// dictAdd 落字典并立即选中、readTick 刷新 chips；③ 编辑态回填走 [_tags]（不变）。
  Widget _tagsBlock(List<DictEntry> tagDict) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        key: const ValueKey('bf-tags'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '标签',
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in tagDict)
                GestureDetector(
                  key: ValueKey('bf-tag-${e.name}'),
                  onTap: () => setState(
                    () => _tags.contains(e.name)
                        ? _tags.remove(e.name)
                        : _tags.add(e.name),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: _tags.contains(e.name)
                          ? context.tokens.accent.withValues(alpha: .12)
                          : cs.surfaceContainerHighest,
                      border: Border.all(
                        color: _tags.contains(e.name)
                            ? context.tokens.accent
                            : context.tokens.cardBorder,
                      ),
                    ),
                    child: Text(
                      '#${e.name}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _tags.contains(e.name)
                            ? context.tokens.accent
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              // 行尾「＋ 添加标签」chip：点开就地展开输入行。
              GestureDetector(
                key: const ValueKey('bf-tag-add'),
                onTap: () => setState(() => _tagAddOpen = !_tagAddOpen),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: _tagAddOpen
                        ? context.tokens.accent.withValues(alpha: .12)
                        : cs.surfaceContainerHighest,
                    border: Border.all(
                      color: _tagAddOpen
                          ? context.tokens.accent
                          : context.tokens.cardBorder,
                    ),
                  ),
                  child: Text(
                    '＋ 添加标签',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _tagAddOpen
                          ? context.tokens.accent
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              if (tagDict.isEmpty)
                Text(
                  '还没有标签 · 点「＋ 添加标签」就地新建',
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
            ],
          ),
          // 就地展开的输入行（同页内嵌，非弹层）。
          if (_tagAddOpen)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('bf-tag-name'),
                      controller: _newTag,
                      autofocus: true,
                      style: const TextStyle(fontSize: 12.5),
                      onSubmitted: (_) => _addTag(),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '输入标签名',
                        hintStyle: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurfaceVariant,
                        ),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withValues(
                          alpha: .5,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _mini('bf-tag-add-ok', '确认', () => _addTag()),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _coverBlock() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        children: [
          Stack(
            children: [
              ClipRRect(
                key: const ValueKey('bf-cover'),
                borderRadius: BorderRadius.circular(8),
                child: _cover != null && _cover!.isNotEmpty
                    ? Image.file(File(_cover!), width: 64, height: 90, fit: BoxFit.cover)
                    : BsCover(
                        book: Book(
                          id: '',
                          title: _title.text,
                          colorIdx: _colorIdx,
                          createdAt: 0,
                          updatedAt: 0,
                        ),
                        width: 64,
                        height: 90,
                        radius: 8,
                        showAuthor: false,
                        showBadge: false,
                      ),
              ),
              if (_cover != null && _cover!.isNotEmpty)
                Positioned(
                  right: -4,
                  top: -4,
                  child: GestureDetector(
                    key: const ValueKey('bf-cov-clear'),
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
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _mini('bf-cov-file', '上传', () => _pickCover()),
              const SizedBox(width: 6),
              _mini('bf-cov-cam', '拍照', () => _pickCover(camera: true)),
              const SizedBox(width: 6),
              _mini('bf-cov-isbn', 'ISBN 取图', _isbnCover),
            ],
          ),
          Text(
            '设置封面',
            style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 阅读设置「ISBN 补全」＝抓豆瓣数据 时才联网（与 sheet 同口径）。
    _fillDouban =
        (ref.watch(readKvProvider(('read.isbnFill', '仅填 ISBN'))).valueOrNull ??
                '仅填 ISBN') ==
            '抓豆瓣数据';
    final tagDict =
        ref.watch(dictProvider(DictEntry.kTag)).valueOrNull ??
        const <DictEntry>[];
    final started = _editing?.startedAt;
    final startedText = started == null
        ? '设为在读时自动记录'
        : () {
            final d = DateTime.fromMillisecondsSinceEpoch(started);
            String two(int n) => n.toString().padLeft(2, '0');
            return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
          }();

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          // 标题三态（原型 bfRender）：编辑 / 豆瓣带入 / 手动。
          widget.bookId != null
              ? '编辑书籍信息'
              : (widget.seed != null ? '添加到书架' : '手动录入'),
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            key: const ValueKey('bf-save'),
            onPressed: _save,
            child: Text(
              widget.bookId != null ? '保存' : '添加',
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          _coverBlock(),
          _sec('基础信息'),
          _card([
            _row('书名（必填）', _in(_title, 'bf-title', hint: '输入书籍名称')),
            _row('作者', _in(_author, 'bf-author', hint: '输入作者名字')),
            _row('译者', _in(_translator, 'bf-translator', hint: '请输入译者名字')),
            _row('出版社', _in(_publisher, 'bf-publisher', hint: '请输入出版社名称')),
            _row('出版日期', _in(_pubDate, 'bf-pubDate', hint: '如 2015-06')),
            _row('丛书 / 分类', _in(_series, 'bf-series', hint: '请输入丛书或分类')),
            _row('装帧', _in(_binding, 'bf-binding', hint: '平装 / 精装')),
            // ISBN：行内扫码钮 + 输入 + 补全状态行 + 缓存询问行（原型 bfRender）。
            _row(
              'ISBN',
              Row(
                children: [
                  GestureDetector(
                    key: const ValueKey('bf-isbn-scan'),
                    onTap: _scanIsbn,
                    child: Icon(
                      Icons.center_focus_strong_outlined,
                      size: 17,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _in(
                      _isbn,
                      'bf-isbn',
                      hint: 'ISBN / 豆瓣 subject_id',
                      bold: true,
                      onChanged: (_) => _onIsbnChanged(),
                    ),
                  ),
                ],
              ),
            ),
            if (_isbnStatus.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _isbnStatus,
                  key: const ValueKey('bf-isbn-status'),
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
              ),
            if (_dbAskCode.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  key: const ValueKey('bf-cache-ask'),
                  children: [
                    Expanded(
                      child: Text(
                        '本地已有《$_dbAskTitle》缓存',
                        style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                      ),
                    ),
                    _mini('bf-cache-use', '用缓存', _dbUseCache),
                    const SizedBox(width: 6),
                    _mini('bf-cache-net', '仍联网查询', _dbRefetch),
                  ],
                ),
              ),
            _row('书籍评分', _starRow()),
            _row('字数', _in(_wc, 'bf-wc', hint: '请输入书籍字数', kb: TextInputType.number)),
            if (_doubanRating != null)
              _row(
                '豆瓣评分',
                Text(
                  '$_doubanRating 分',
                  key: const ValueKey('bf-dbrate'),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF5A623),
                  ),
                ),
              ),
          ]),
          _sec('简介信息'),
          _card([
            _fold(
              label: '作者简介',
              keyName: 'bf-authorNote',
              c: _authorNote,
              hint: '请输入作者简介',
              open: _anOpen,
              onToggle: (v) => setState(() => _anOpen = v),
            ),
            Divider(height: 1, thickness: .5, color: context.tokens.cardBorder),
            _fold(
              label: '书籍简介',
              keyName: 'bf-intro',
              c: _intro,
              hint: '请输入书籍简介',
              open: _introOpen,
              onToggle: (v) => setState(() => _introOpen = v),
            ),
          ]),
          _sec('书籍管理'),
          _card([
            _row('分组', _dictDropdown(DictEntry.kGroup, 'bf-grp', _grp)),
            _tagsBlock(tagDict),
            Divider(height: 1, thickness: .5, color: context.tokens.cardBorder),
            _row(
              '阅读状态',
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 2),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _chips(Book.states, {_state}, 'bf-st', (v) {
                    setState(() {
                      _state = v;
                      if (_isNew) _way = Book.defaultWayFor(_format);
                    });
                  }),
                ),
              ),
            ),
            _row(
              '标记在读的时间',
              Text(
                startedText,
                key: const ValueKey('bf-started'),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
            _row(
              '书籍类型',
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 2),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _chips(Book.formats, {_format}, 'bf-fmt', (v) {
                    setState(() {
                      _format = v;
                      // 原型 ebxSet：仅新书联动默认进度方式。
                      if (_isNew) _way = Book.defaultWayFor(v);
                    });
                  }),
                ),
              ),
            ),
            _row(
              '已读页码',
              _in(_readPages, 'bf-rp', hint: '请输入已读页码', kb: TextInputType.number),
            ),
            _row(
              '总页码',
              _in(_pages, 'bf-pg', hint: '请输入总页码', kb: TextInputType.number),
            ),
          ]),
          _sec('来源信息'),
          _card([
            _row('来源', _dictDropdown(DictEntry.kSource, 'bf-src', _source)),
          ]),
          _sec('购买信息'),
          _card([
            _row('购入日期', _in(_feeDate, 'bf-feeDate', hint: '如 2024-05')),
            _row(
              '购入价格',
              _in(_fee, 'bf-fee', hint: '请输入书籍的价格', kb: TextInputType.number),
            ),
          ]),
        ],
      ),
    );
  }
}
