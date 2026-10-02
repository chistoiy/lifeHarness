import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/app_log.dart';
import '../domain/book.dart';
import '../presentation/reader/reader_pager.dart';
import 'epub_doc.dart';
import 'epub_first_img.dart';
import 'read_repository.dart';

/// 批3.5 · 大书内存模型与预载/清缓存服务。
///
/// 三条拍板口径（需求 V1.50 批3.5）：
/// 1. **整本预载**：导入落库后后台异步「解析 + 全书分页实算」；完成前该书不可点进
///    阅读（封面显进度）；预载完成后二次打开＝秒进（[EpubDocCache] + 分页表命中）。
/// 2. **50/100MB 图文包**：生产路径 [EpubDoc.openFile] 懒归档（条目不点不解压），
///    图片按需解码 + LRU（≤12 张），章文本全量驻留；分页表落盘（[PagStore]），
///    按「外观 cfg + 视口指纹」失效。
/// 3. **单书清缓存**：只回收私有副本 + 封面衍生 + 分页表；记录/书摘划线/计时/
///    进度全保留；**源文件绝不删除**。三态恢复见 [EpubCacheService]。

// ---------- 分页表落盘 ----------

/// 分页表持久层：`docs/epub_pag/<bookId>.json` ＝ 指纹 + perChapter 下标数组。
/// 指纹不一致（外观/视口变化）即失效重算。
class PagStore {
  const PagStore._();

  static const tableVersion = 2;

  /// 外观 cfg + 视口指纹（reader_pager.ReaderLayout 全字段参与）。
  /// R3-2 ③：indMode 三档改变每段显示文本（自带缩进段不再叠加）→ 必须进指纹，
  /// 否则改了缩进设置不重排＝真机假生效。`just` 不入指纹：两端对齐只拉伸行内
  /// 空隙、不改断行，TextPainter 实算高度与左对齐一致（进指纹反而每次白重排）。
  static String fingerprint(ReaderLayout l) =>
      '${l.width.round()}x${l.height.round()}|fs${l.fs}|lh${l.lh}|ls${l.ls}'
      '|mar${l.mar}|fnt${l.font}|ind${l.indent ? 1 : 0}|im${l.indMode}';

  static String dirPath(String docsPath) => p.join(docsPath, 'epub_pag');

  static File fileFor(String docsPath, String bookId) =>
      File(p.join(dirPath(docsPath), '$bookId.json'));

  /// 读取与 [fp] 匹配的分页表（[weights]＝本书各章字符数，进度加权用）；
  /// 无表/坏表/指纹不符返回 null（调用方实算）。未排版章在表里为 null。
  static Future<BookPagination?> load(
    String docsPath,
    String bookId,
    String fp,
    List<int> weights,
  ) async {
    final f = fileFor(docsPath, bookId);
    if (!await f.exists()) return null;
    try {
      final src = await f.readAsString();
      // 真机修⑥：2409 章表数 MB，jsonDecode 移入 isolate，主线程零阻塞。
      return compute(_pagFromJson, (src, fp, weights));
    } catch (_) {
      return null;
    }
  }

  static BookPagination? _pagFromJson((String, String, List<int>) arg) {
    final (src, fp, weights) = arg;
    final v = jsonDecode(src);
    if (v is! Map || v['fp'] != fp || v['v'] != tableVersion) return null;
    final per = v['per'];
    if (per is! List) return null;
    return BookPagination.fromTable(weights, [
      for (final ch in per)
        ch == null
            ? null
            : [
                for (final pg in ch as List)
                  [for (final i in pg as List) (i as num).toInt()],
              ],
    ]);
  }

  static Future<void> save(
    String docsPath,
    String bookId,
    String fp,
    BookPagination pag,
  ) async {
    final dir = Directory(dirPath(docsPath));
    await dir.create(recursive: true);
    await fileFor(docsPath, bookId).writeAsString(
      jsonEncode({
        'v': tableVersion,
        'fp': fp,
        'per': pag.pages,
      }),
      flush: true,
    );
  }

  static Future<void> remove(String docsPath, String bookId) async {
    final f = fileFor(docsPath, bookId);
    if (await f.exists()) await f.delete();
  }

  static Future<int> sizeOf(String docsPath, String bookId) async {
    final f = fileFor(docsPath, bookId);
    return f.existsSync() ? f.lengthSync() : 0;
  }
}

// ---------- 排版快照落盘（批5 秒开） ----------

/// 解析结果按「章」粒度落盘：`docs/epub_snap/<bookId>/`（index.json + data.bin +
/// cover.bin）。指纹＝源文件 size|mtime，源不变则打开只需「读索引 + 当前章」，
/// 整本不再重新解析（微信读书「导入时排版、打开时加载」口径；anx-reader 的
/// foliate-js「只排当前章」以快照章节粒度落地）。图片仍走懒归档按需解码。
class DocStore {
  const DocStore._();

  /// v2：轮4① 章节标题回落链（toc→文件名→章内首个标题）落盘后，
  /// 旧快照里的 part1394 类标题全部作废 → 版本 +1 让存量快照失效重解。
  /// v3：R3-2 止血四条新增段级语义（注释体 / 自带缩进 / 链接站内-注释标记）。
  /// 旧快照缺这些字段会**一律按 false 解出**＝注释体仍当正文、缩进仍叠加＝假生效，
  /// 所以必须 +1 让存量快照整体失效重解（而不是兼容读默认值）。
  static const snapVersion = 3;

  static String dirFor(String docsPath, String bookId) =>
      p.join(docsPath, 'epub_snap', bookId);

  /// 源文件指纹（不存在/不可读＝空串，快照视为失效）。
  static String fingerprint(String srcPath) {
    try {
      final f = File(srcPath);
      if (!f.existsSync()) return '';
      final st = f.statSync();
      return '${st.size}|${st.modified.millisecondsSinceEpoch}';
    } catch (_) {
      return '';
    }
  }

  static List _paraJson(EpubPara x) => [
    x.kind.index,
    x.text,
    x.headingLevel,
    x.imgSrc,
    x.alt,
    [
      for (final l in x.links) [
        l.start,
        l.end,
        l.href,
        l.external ? 1 : 0,
        // R3-2 ①④：注释引用与站内锚点（上色判定随快照一起落盘）。
        l.annotation ? 1 : 0,
        l.sameDoc ? 1 : 0,
      ],
    ],
    // R3-2 ①③：段级注释体与书内自带缩进标记。
    x.annotation ? 1 : 0,
    x.ownIndent ? 1 : 0,
  ];

  static int _flag(List src, int i) => i < src.length ? src[i] as int : 0;

  static EpubPara _paraFromJson(List a) => EpubPara(
    kind: EpubParaKind.values[a[0] as int],
    text: a[1] as String,
    headingLevel: a[2] as int,
    imgSrc: a[3] as String,
    alt: a[4] as String,
    links: [
      for (final l in (a.length > 5 ? a[5] as List : const []))
        EpubLink(
          start: l[0] as int,
          end: l[1] as int,
          href: l[2] as String,
          external: (l[3] as int) == 1,
          annotation: _flag(l, 4) == 1,
          sameDoc: _flag(l, 5) == 1,
        ),
    ],
    annotation: _flag(a, 6) == 1,
    ownIndent: _flag(a, 7) == 1,
  );

  /// 保存快照（覆盖式）。data.bin＝各章段落 JSON 的 UTF-8 拼接。
  static Future<void> save(
    String docsPath,
    String bookId,
    String fp,
    EpubDoc doc,
  ) async {
    if (fp.isEmpty) return;
    final dir = Directory(dirFor(docsPath, bookId));
    await dir.create(recursive: true);
    final spine = <Map<String, Object>>[];
    final raf =
        await File(p.join(dir.path, 'data.bin')).open(mode: FileMode.write);
    var off = 0;
    try {
      for (final c in doc.chapters) {
        final b =
            utf8.encode(jsonEncode([for (final x in c.paras) _paraJson(x)]));
        spine.add({
          'href': c.href,
          'title': c.title,
          'n': c.paras.length,
          'chars': c.charCount,
          'off': off,
          'len': b.length,
        });
        await raf.writeFrom(b);
        off += b.length;
      }
    } finally {
      await raf.close();
    }
    final idx = <String, Object?>{
      'v': snapVersion,
      'fp': fp,
      'format': doc.format,
      'title': doc.title,
      'author': doc.author,
      'pub': doc.publisher,
      'date': doc.pubDate,
      'lang': doc.language,
      'desc': doc.description,
      'covN': doc.coverName,
      'imgC': doc.imageCount,
      'chars': doc.totalChars,
      'fontC': doc.fontCount,
      'bmC': doc.bookmarkCount,
      'toc': [
        for (final t in doc.toc) [t.label, t.href, t.level],
      ],
      'spine': spine,
    };
    await File(p.join(dir.path, 'index.json'))
        .writeAsString(jsonEncode(idx));
    final cov = doc.coverBytes;
    if (cov != null) {
      await File(p.join(dir.path, 'cover.bin')).writeAsBytes(cov);
    }
  }

  /// 指纹相符才载入；否则 null（调用方走解析）。[srcPath] 给出时重挂懒归档
  /// 供图；源文件丢失仍返回纯文本快照（插图渲染自然走缺图占位）。
  static Future<EpubDoc?> load(
    String docsPath,
    String bookId,
    String fp, {
    String? srcPath,
  }) async {
    if (fp.isEmpty) return null;
    final dir = dirFor(docsPath, bookId);
    final idxF = File(p.join(dir, 'index.json'));
    if (!await idxF.exists()) return null;
    final Map<String, Object?> m;
    try {
      m = (jsonDecode(await idxF.readAsString()) as Map).cast<String, Object?>();
    } catch (_) {
      return null;
    }
    if (m['v'] != snapVersion || m['fp'] != fp) return null;
    final List<Object?> sp;
    try {
      sp = m['spine'] as List;
    } catch (_) {
      return null;
    }
    final refs = <_ChRef>[
      for (final s in sp)
        _ChRef(
          (s as Map)['href'] as String,
          s['title'] as String,
          s['n'] as int,
          (s['chars'] as num?)?.toInt() ?? 0,
          s['off'] as int,
          s['len'] as int,
        ),
    ];
    List<EpubTocItem> toc;
    try {
      toc = [
        for (final t in (m['toc'] as List))
          EpubTocItem(label: t[0] as String, href: t[1] as String, level: t[2] as int),
      ];
    } catch (_) {
      toc = const [];
    }
    LazyEpubArchive? lz;
    if (srcPath != null) {
      try {
        lz = LazyEpubArchive.open(srcPath);
      } catch (_) {
        lz = null;
      }
    }
    Uint8List? cover;
    try {
      final cf = File(p.join(dir, 'cover.bin'));
      if (await cf.exists()) cover = await cf.readAsBytes();
    } catch (_) {}
    return EpubDoc(
      format: m['format'] as String,
      title: m['title'] as String,
      author: m['author'] as String,
      publisher: m['pub'] as String?,
      pubDate: m['date'] as String?,
      language: m['lang'] as String?,
      description: m['desc'] as String?,
      coverBytes: cover,
      coverName: m['covN'] as String?,
      toc: toc,
      chapters: _LazyChapterList(dir, refs),
      imageCount: (m['imgC'] as int?) ?? 0,
      totalChars: (m['chars'] as int?) ?? 0,
      fontCount: (m['fontC'] as int?) ?? 0,
      bookmarkCount: (m['bmC'] as int?) ?? 0,
      lazy: lz,
    );
  }

  /// 快照占用字节（目录不存在＝0）。
  static Future<int> sizeOf(String docsPath, String bookId) async {
    var sum = 0;
    try {
      final dir = Directory(dirFor(docsPath, bookId));
      if (!await dir.exists()) return 0;
      await for (final e in dir.list(recursive: true)) {
        if (e is File) sum += await e.length();
      }
    } catch (_) {}
    return sum;
  }

  static Future<void> remove(String docsPath, String bookId) async {
    try {
      final dir = Directory(dirFor(docsPath, bookId));
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }
}

class _ChRef {
  const _ChRef(this.href, this.title, this.n, this.chars, this.off, this.len);
  final String href;
  final String title;
  final int n;

  /// 章字符数（保存时算好入索引：进度权重不触碰段落）。
  final int chars;
  final int off;
  final int len;
}

/// 章粒度懒读列表：只有被访问的章才 readSync+decode（打开＝只读当前章）。
/// 每次读独立开合文件句柄（章级几十 KB，毫秒级），不做跨页常驻。
/// 标题/字符数走 [_refs] 索引直读（[ChapterMetaSource]），全量遍历不再 materialize。
class _LazyChapterList extends ListBase<EpubChapter> implements ChapterMetaSource {
  _LazyChapterList(this._dir, this._refs);

  final String _dir;
  final List<_ChRef> _refs;
  final Map<int, EpubChapter> _cache = {};

  @override
  List<String> get chapterTitles => [for (final r in _refs) r.title];

  @override
  List<int> get chapterCharCounts => [for (final r in _refs) r.chars];

  @override
  int get length => _refs.length;

  @override
  set length(int v) => throw UnsupportedError('快照章节列表只读');

  @override
  void operator []=(int i, EpubChapter c) =>
      throw UnsupportedError('快照章节列表只读');

  @override
  EpubChapter operator [](int i) {
    final hit = _cache[i];
    if (hit != null) return hit;
    final r = _refs[i];
    var paras = const <EpubPara>[];
    try {
      final raf = File(p.join(_dir, 'data.bin')).openSync();
      try {
        raf.setPositionSync(r.off);
        final bytes = raf.readSync(r.len);
        final raw = jsonDecode(utf8.decode(bytes)) as List;
        paras = [for (final a in raw) DocStore._paraFromJson(a)];
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      paras = const [];
    }
    final c = EpubChapter(href: r.href, title: r.title, paras: paras);
    _cache[i] = c;
    return c;
  }
}


/// 预载完成的书本内存驻留（LRU 上限 [maxLive] 本；被逐出后重开走懒归档再开，
/// 分页表仍在盘上 → 秒进不受影响）。
class EpubDocCache {
  EpubDocCache({this.maxLive = 2});

  final int maxLive;
  final LinkedHashMap<String, EpubDoc> _m = LinkedHashMap();

  EpubDoc? get(String bookId) => _m[bookId];

  void put(String bookId, EpubDoc doc) {
    _m[bookId] = doc;
    while (_m.length > maxLive) {
      final oldest = _m.keys.first;
      final d = _m.remove(oldest);
      d?.lazy?.dispose();
    }
  }

  void remove(String bookId) {
    _m.remove(bookId)?.lazy?.dispose();
  }

  void clear() {
    for (final d in _m.values) {
      d.lazy?.dispose();
    }
    _m.clear();
  }
}

// ---------- 整本预载 ----------

/// 预载进度快照（封面进度条数据源）。
@immutable
class PreloadInfo {
  const PreloadInfo({required this.pr, this.error});
  final int pr; // 0~100
  final String? error;
}

/// 整本预载服务：导入提交后后台跑「解析（isolate）→ 全书分页（分片让出 UI）→
/// 分页表落盘 → 状态置 rdy」。进度经 [info] 暴露给封面；状态持久化在
/// [EpubRef.st]/[EpubRef.pr]（跨重启可见）。
class EpubPreloadService extends ChangeNotifier {
  EpubPreloadService(
    this.repo, {
    this.docsPath,
    this.parseOverride,
    // 兼容旧签名保留；V1.53.1 轮4 起整本预排循环已删（按章懒排），不再需要让帧 pump。
    Future<void> Function()? pump,
  });

  final ReadRepository repo;

  /// 落盘根目录（应用 docs）；widget 测试注入临时目录，不碰真实 path_provider。
  String? docsPath;

  /// 测试注入：替换真实解析（同 pickHook 惯例；FakeAsync 下禁真 IO）。
  final Future<EpubDoc> Function(String path)? parseOverride;

  final Map<String, PreloadInfo> _info = {};
  final Set<String> _running = {};
  final Map<String, Future<void>> _warmTasks = {};
  final EpubDocCache docs = EpubDocCache();

  PreloadInfo? info(String bookId) => _info[bookId];

  /// 书架预热（真机修⑥：重启后内存文档缓存清空，重进要等重新解析）：
  /// 优先读排版快照（批5·毫秒级）；无快照才后台 isolate 解析整本并回灌快照。
  /// 单飞：同书并发只跑一次；[warming] 可等它完成，避免阅读器再起第二路解析。
  Future<void> warm(Book b) {
    final ep = b.epub;
    if (ep == null || ep.path.isEmpty || ep.state != EpubRef.stReady) {
      return Future.value();
    }
    if (docs.get(b.id) != null) return Future.value();
    return _warmTasks[b.id] ??= () async {
      try {
        final dp = docsPath;
        final inj = parseOverride;
        if (dp != null && inj == null) {
          final snap = await DocStore.load(
            dp,
            b.id,
            DocStore.fingerprint(ep.path),
            srcPath: ep.path,
          );
          if (snap != null) {
            docs.put(b.id, snap);
            _warmTasks.remove(b.id);
            return;
          }
        }
        final doc = await (inj ??
                ((path) async => EpubDoc.openFileDetached(path)))(ep.path);
        docs.put(b.id, doc);
        if (dp != null && inj == null) {
          unawaited(() async {
            try {
              await DocStore.save(
                  dp, b.id, DocStore.fingerprint(ep.path), doc);
            } catch (_) {}
          }());
        }
      } catch (_) {}
      _warmTasks.remove(b.id);
    }();
  }

  /// 该书预热任务（没在跑则 null）。
  Future<void>? warming(String bookId) => _warmTasks[bookId];

  /// 批5 · 读排版快照（docsPath 未就绪/测试注入/指纹不符＝null，调用方回落解析）。
  /// 只同步取 [docsPath]，绝不在 widget 测试 FakeAsync 下触发真实 path_provider。
  Future<EpubDoc?> snap(Book b) async {
    final dp = docsPath;
    final ep = b.epub;
    if (dp == null || ep == null || ep.path.isEmpty || parseOverride != null) {
      return null;
    }
    try {
      return await DocStore.load(
        dp,
        b.id,
        DocStore.fingerprint(ep.path),
        srcPath: ep.path,
      );
    } catch (_) {
      return null;
    }
  }

  /// 批5 · 现开路径回灌快照（本次已付解析成本，下次打开＝秒进）。
  Future<void> saveSnap(Book b, EpubDoc doc) async {
    final dp = docsPath;
    final ep = b.epub;
    if (dp == null || ep == null || ep.path.isEmpty || parseOverride != null) {
      return;
    }
    try {
      await DocStore.save(dp, b.id, DocStore.fingerprint(ep.path), doc);
    } catch (_) {}
  }

  /// 回收排版快照（清缓存/删除书共用）。
  Future<void> removeSnap(String bookId) async {
    final dp = docsPath;
    if (dp == null) return;
    await DocStore.remove(dp, bookId);
  }

  /// 预载到终态（rdy/失败回退）时回调——provider 用它 bump readTick 重取书籍。
  void Function(String bookId)? onBookSettled;

  /// 预载一本书（幂等：同书在跑则直接返回）。[layout] 为分页指纹基准视口/外观。
  Future<void> preload(Book b, ReaderLayout layout) async {
    final ep = b.epub;
    if (ep == null || ep.path.isEmpty) return;
    if (_running.contains(b.id)) return;
    _running.add(b.id);
    _info.remove(b.id); // 上轮错误不残留
    final docs0 = await _docs0();
    try {
      await _mark(b, EpubRef.stPreload, 4);
      // ① 解析（后台 isolate 懒归档：open 只读中央目录，文本逐章解压、图片零驻留）
      final doc = await (parseOverride ??
              ((path) async => EpubDoc.openFileDetached(path)))(ep.path);
      docs.put(b.id, doc);
      // 批5：解析结果按章落盘（下次冷启动打开＝读快照，不再整本重析）。
      if (docs0 != null && parseOverride == null) {
        await DocStore.save(docs0, b.id, DocStore.fingerprint(ep.path), doc);
      }
      await _mark(b, EpubRef.stPreload, 45);
      // ② V1.53.1 轮4（foliate 模型）：**不再整本预排**——分页按章在打开时
      //    懒算；进度百分比按章字符数插值，与全书页数无关。这里只排首章做种子
      //    落盘（2409 章合集的整本循环正是真机书摘/抽屉卡顿的主线程霸占者）。
      final pag = BookPagination.lazy([
        for (final c in doc.chapters) c.charCount,
      ]);
      if (doc.chapters.isNotEmpty) {
        pag.setChapter(0, EpubPager.layoutChapter(doc.chapters[0].paras, layout));
      }
      await PagStore.save(docs0!, b.id, PagStore.fingerprint(layout), pag);
      // R14-4：无真封面的本地书在预载尾步生成 A 档正文首图衍生件（幂等；
      // 清缓存后的恢复重预载也走这里再生）。失败不阻断预载终态。
      if (b.coverPath == null) {
        try {
          final fi = await EpubFirstImg.ensure(
            docsPath: docs0,
            bookId: b.id,
            doc: doc,
            existing: b.firstImgPath,
          );
          if (fi != null && fi != b.firstImgPath) {
            await repo.updateBook(b.copyWith(firstImgPath: fi));
          }
        } catch (e) {
          AppLog.add('首图回落生成失败 书#${b.id}: $e', level: LhLevel.error);
        }
      }
      await _mark(b, EpubRef.stReady, 100);
      onBookSettled?.call(b.id);
    } catch (e) {
      _info[b.id] = PreloadInfo(pr: 0, error: '$e');
      // 解析失败回 rdy 态不阻塞书架（进阅读时再报错给原因）；保留进度字段清零。
      try {
        await _mark(b, EpubRef.stReady, 0, notify: false);
      } catch (_) {}
      onBookSettled?.call(b.id);
      // 真机反馈 R14-10b：原为 debugPrint，release 下无痕 → 统一入 AppLog。
      AppLog.add('预载失败 书#${b.id}: $e', level: LhLevel.error);
    } finally {
      _running.remove(b.id);
    }
  }

  Future<void> _mark(Book b, String st, int pr, {bool notify = true}) async {
    final ep = b.epub!.copyWith(st: st, pr: pr);
    final updated = b.copyWith(epub: ep);
    await repo.updateBook(updated);
    _info[b.id] = PreloadInfo(
      pr: st == EpubRef.stReady ? 100 : pr,
      error: _info[b.id]?.error, // 失败回退路径保留错误原因供 UI/测试
    );
    if (notify) notifyListeners();
  }

  // ---------- 分页表读写（阅读主屏复用；docsPath 未注入时回落真实 docs） ----------

  Future<String?> _docs0() async {
    docsPath ??= (await getApplicationDocumentsDirectory()).path;
    return docsPath;
  }

  /// 指纹命中的落盘分页表（秒进，可含未排版章＝null）；
  /// 无表/坏表/指纹不符/目录不可用＝null（调用方实算）。
  Future<BookPagination?> loadPag(
    String bookId,
    ReaderLayout l,
    List<int> weights,
  ) async {
    try {
      final d = await _docs0();
      return PagStore.load(d!, bookId, PagStore.fingerprint(l), weights);
    } catch (e) {
      AppLog.add('分页缓存读取失败 书#$bookId: $e', level: LhLevel.warn);
      return null;
    }
  }

  Future<void> savePag(String bookId, ReaderLayout l, BookPagination pag) async {
    try {
      final d = await _docs0();
      await PagStore.save(d!, bookId, PagStore.fingerprint(l), pag);
    } catch (e) {
      AppLog.add('分页缓存写入失败 书#$bookId: $e', level: LhLevel.warn);
    }
  }

  /// 回收分页表（清缓存/删除书共用）。
  Future<void> removePag(String bookId) async {
    try {
      final d = await _docs0();
      await PagStore.remove(d!, bookId);
    } catch (_) {}
  }

  @override
  void dispose() {
    docs.clear();
    super.dispose();
  }
}

// ---------- 单书清缓存与三态恢复 ----------

/// 清缓存结果分类（弹层文案与后续动作路由）。
enum EpubRestore {
  /// 原文件仍可读 → 重新拷贝 + 预载。
  reloadFromSource,

  /// 原文件已不存在 → 引导重选文件（合并导入挂回原记录）。
  needRepick,
}

class EpubCacheService {
  EpubCacheService(this.repo, {this.docsPath});

  final ReadRepository repo;
  String? docsPath;

  Future<String> _docs() async =>
      docsPath ?? (await getApplicationDocumentsDirectory()).path;

  /// 约可释放字节数＝私有副本 + 封面衍生 + 分页表 + 排版快照（源文件不计、绝不删）。
  Future<int> estimateRelease(Book b) async {
    final ep = b.epub;
    if (ep == null) return 0;
    var sum = 0;
    final copy = File(ep.path);
    if (await copy.exists()) sum += await copy.length();
    final cover = b.coverPath;
    if (cover != null && p.basename(cover).startsWith('epub_')) {
      final f = File(cover);
      if (await f.exists()) sum += await f.length();
    }
    final d = await _docs();
    sum += await PagStore.sizeOf(d, b.id);
    sum += await DocStore.sizeOf(d, b.id);
    return sum;
  }

  /// 清理：回收四类缓存文件；记录/书摘划线/计时/进度/外观全保留；原文件不动。
  /// 状态置 [EpubRef.stCleared]，并探测源文件是否仍可读（三态分流用）。
  Future<void> clear(Book b) async {
    final ep = b.epub;
    if (ep == null) return;
    final docs0 = await _docs();
    final copy = File(ep.path);
    if (await copy.exists()) await copy.delete();
    final cover = b.coverPath;
    if (cover != null && p.basename(cover).startsWith('epub_')) {
      final f = File(cover);
      if (await f.exists()) await f.delete();
    }
    // R14-4：同时回收 A 档首图衍生件。
    if (b.firstImgPath != null) {
      final fi = File(b.firstImgPath!);
      if (await fi.exists()) await fi.delete();
    }
    await PagStore.remove(docs0, b.id);
    await DocStore.remove(docs0, b.id);
    await repo.updateBook(
      b.copyWith(epub: ep.copyWith(st: EpubRef.stCleared, pr: 0)),
    );
  }

  /// 已清缓存书的恢复分类：探测源文件（srcPath 优先，回落副本路径记录）。
  Future<EpubRestore> restoreKind(Book b) async {
    final ep = b.epub;
    final src = ep?.srcPath;
    if (src != null && src.isNotEmpty && File(src).existsSync()) {
      return EpubRestore.reloadFromSource;
    }
    return EpubRestore.needRepick;
  }

  /// 源文件仍在 → 重新拷贝私有副本（预载由调用方接续触发）。
  Future<void> recopyFromSource(Book b) async {
    final ep = b.epub;
    if (ep == null || ep.srcPath == null) return;
    final src = File(ep.srcPath!);
    if (!await src.exists()) return;
    await Directory(p.dirname(ep.path)).create(recursive: true);
    await src.copy(ep.path);
  }
}
