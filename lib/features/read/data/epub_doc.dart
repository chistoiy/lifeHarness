import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart' show InputFileStream;
import 'package:collection/collection.dart';
import 'package:html/dom.dart' as h;
import 'package:html/parser.dart' as hparser;
import 'package:xml/xml.dart';

/// 本地 EPUB 解析（V1.50 阅读器批1 · 选型验证结论＝自研容器层）。
///
/// 选型记录（批1 交付说明）：pub.dev 现有 epubx（归档停更、只给裸元数据）、
/// flutter_epub_viewer 等皆 WebView 整页渲染，与「分页引擎实算 + 划词 CFI」
/// 路线冲突；本项目已有 archive(ZIP) 且 xml/html 在锁文件内，容器层自研
/// 约 300 行、全部可单测。**EPUB 解析＝archive+自研，不引第三方 reader 包。**
///
/// 口径：
/// - 仅 EPUB2/3；zip 坏包/非 EPUB/DRM 在 [EpubDoc.parse] 即拒绝（[EpubFormatException]）；
/// - DRM 判定＝META-INF/encryption.xml 出现白名单（IDPF/Adobe 字体混淆）以外的
///   EncryptionMethod URI；
/// - 目录同源：[toc] 与书籍两级目录（book_toc_nodes）互转在导入器完成；
/// - 正文逐段抽取（[EpubPara]），段落下标即 CFI 的 `段` 维（批2 分页/批3 划词共用）。
class EpubFormatException implements Exception {
  const EpubFormatException(this.reason);
  final String reason;
  @override
  String toString() => 'EpubFormatException: $reason';
}

/// 段落类型（渲染语义：正文/标题/引文/插图）。
enum EpubParaKind { text, heading, quote, image }

/// 段落内联链接（a 元素 · 相对段落文本的字符区间 · V1.50 内链直跳/外链三策略）。
class EpubLink {
  const EpubLink({
    required this.start,
    required this.end,
    required this.href,
    required this.external,
    this.annotation = false,
    this.sameDoc = false,
  });

  final int start;
  final int end;

  /// 内链＝解析后的 zip 内路径（含锚点已剥）；外链＝原样 URL。
  final String href;

  /// href 带 scheme（http:/mailto:/tel:/…）或协议相对 //host——决定**行为**
  /// （跳浏览器还是跳章），R3-2 ④ 的**上色**判定看 [usesLinkColor]。
  final bool external;

  /// R3-2 ① 注释/脚注引用（自身 epub:type 含 note/footnote、类名含
  /// note|footnote|annotation）：按正文色 + 小一号，绝不套链接绿。
  final bool annotation;

  /// R3-2 ④ 站内锚点：指向本文档自身（纯 `#fragment` 或解析后同文件）。
  final bool sameDoc;

  /// R3-2 ④ 链接色只给「外链」＝带 scheme 或跨章；站内锚点与注释引用一律正文色。
  /// 判定收在模型层（工单：别散在 UI），渲染处只读它。
  bool get usesLinkColor => !annotation && (external || !sameDoc);
}

/// 一个内容段落（章内下标即 CFI 段落号）。
class EpubPara {
  const EpubPara({
    required this.kind,
    this.text = '',
    this.headingLevel = 0,
    this.imgSrc = '',
    this.alt = '',
    this.links = const [],
    this.annotation = false,
    this.ownIndent = false,
  });

  final EpubParaKind kind;
  final String text;

  /// 标题级别 1~6（kind==heading 时有效）。
  final int headingLevel;

  /// 插图资源在 zip 内的解析后路径（kind==image 时有效）。
  final String imgSrc;

  /// 图片题注（figcaption）或 alt。
  final String alt;

  /// 段内链接（字符区间对齐 [text]）。
  final List<EpubLink> links;

  /// R3-2 ① 注释/脚注体段落（`epub:type` 含 footnote/note · `<aside>` · 类名含
  /// note|footnote|annotation，含祖先容器）：渲染按**正文色 + 小一号**。
  /// 正文与引文两类参与（标题另有字号档，测量与上色必须同源，见 paraStyle）。
  final bool annotation;

  /// R3-2 ③ 书内自带首行缩进（段内 `style:text-indent` 或正文以全角空格起头）：
  /// indMode=auto（跟随原书）时**不再叠加**我们的两全角缩进；按段判定不一刀切。
  final bool ownIndent;

  int get charCount => kind == EpubParaKind.image ? 0 : text.length;
}

/// 目录命中项（level 1=部分/2=小节，与 TocNode 两级同构）。
class EpubTocItem {
  const EpubTocItem({
    required this.label,
    required this.href,
    required this.level,
  });

  final String label;

  /// 已解析为 zip 内路径并去锚点。
  final String href;
  final int level;
}

/// 一章（spine 顺序项）：标题取目录首命中，回落文件原名。
class EpubChapter {
  const EpubChapter({
    required this.href,
    required this.title,
    required this.paras,
  });

  final String href;
  final String title;
  final List<EpubPara> paras;

  int get charCount => paras.fold(0, (s, p) => s + p.charCount);
}

/// 章元数据廉价源（V1.53.1 轮4）：懒章表实现它——标题/字符数**不加载段落**
/// 即可读，避免进度权重、目录抽屉等全量遍历把整本书 materialize 回内存。
abstract class ChapterMetaSource {
  List<String> get chapterTitles;
  List<int> get chapterCharCounts;
}

/// 解析结果快照（不可变）。
class EpubDoc {
  const EpubDoc({
    required this.format,
    required this.title,
    required this.author,
    this.publisher,
    this.pubDate,
    this.language,
    this.description,
    this.coverBytes,
    this.coverName,
    required this.toc,
    required this.chapters,
    required this.imageCount,
    required this.totalChars,
    this.fontCount = 0,
    this.bookmarkCount = 0,
    this.images = const {},
    this.lazy,
  });

  /// 'EPUB2' | 'EPUB3'（OPF package@version）。
  final String format;
  final String title;
  final String author;
  final String? publisher;

  /// dc:date 原样（yyyy / yyyy-MM 等形态不定）。
  final String? pubDate;
  final String? language;
  final String? description;

  /// 封面字节与 zip 内文件名（无法定位封面时为 null）。
  final List<int>? coverBytes;
  final String? coverName;

  /// 目录（nav/ncx 两级；无目录时为空——导入器按「每章一节点」回落）。
  final List<EpubTocItem> toc;

  /// manifest 内嵌字体条目数（核对步「内嵌字体 N」实数）。
  final int fontCount;

  /// ncx pageList 书签数（EPUB3 常规无书签源＝0）。
  final int bookmarkCount;

  /// 包内图片字节（key＝zip 内路径；正文/插图放大/封面共用）。
  /// 懒归档（[EpubDoc.openFile]）下此表不预填——图片经 [imageBytes] 按需解码 + LRU。
  final Map<String, Uint8List> images;

  /// spine 文档顺序的章节正文。
  final List<EpubChapter> chapters;
  final int imageCount;
  final int totalChars;

  /// 懒归档句柄（仅 [openFile] 路径非空；测试/内存路径为 null）。
  final LazyEpubArchive? lazy;

  /// 每章起始全局段落的 CFI 章序即 chapters 下标（`epub/2/{章序+2}/{段}`）。
  static const cfiPrefix = 'epub/2';

  /// 插图字节获取：内存表命中优先，懒归档走 LRU（≤[kEpubImageLruMax] 张驻留）。
  Uint8List? imageBytes(String src) {
    final eager = images[src];
    if (eager != null) return eager;
    return lazy?.image(src);
  }

  /// R14-4 A 档：正文（spine 章序）里第一张插图的包内路径；跳过封面，
  /// 前 [maxChapters] 章内找不到即认为无图返回 null（懒章表按章读快照，成本可控）。
  String? firstBodyImageSrc({int maxChapters = 24}) {
    final n = chapters.length < maxChapters ? chapters.length : maxChapters;
    for (var ci = 0; ci < n; ci++) {
      for (final para in chapters[ci].paras) {
        if (para.kind == EpubParaKind.image && para.imgSrc.isNotEmpty) {
          return para.imgSrc;
        }
      }
    }
    return null;
  }

  /// 章标题（廉价：懒章表从索引直读，不加载段落）。
  List<String> get chapterTitles => chapters is ChapterMetaSource
      ? (chapters as ChapterMetaSource).chapterTitles
      : [for (final c in chapters) c.title];

  /// 各章字符数（廉价：懒章表从索引直读；进度权重与估算页数用它）。
  List<int> get chapterCharCounts => chapters is ChapterMetaSource
      ? (chapters as ChapterMetaSource).chapterCharCounts
      : [for (final c in chapters) c.charCount];

  /// 解析入口（测试/小包）：ZIP 全量字节→容器→OPF→NCX/nav→正文逐段。
  ///
  /// [bytes] EPUB 文件全量字节。坏包/非 EPUB 抛 [EpubFormatException]；
  /// DRM 加密同样抛（reason 固定前缀「DRM」，向导据此展示拒开文案）。
  /// 生产路径请用 [openFile]（懒归档，图片不整包进内存）。
  static EpubDoc parse(List<int> bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const EpubFormatException('文件不是有效的 ZIP/EPUB 容器');
    }
    final files = <String, List<int>>{
      for (final f in archive)
        if (f.isFile) f.name: _archivedBytes(f),
    };
    return _build(_MapSource(files));
  }

  /// 生产入口（批3.5 · 50/100MB 图文包）：懒归档打开——只读中央目录，
  /// 条目不点不解压；章文本逐条解码全量驻留（几 MB 级），图片经 [imageBytes]
  /// 按需解码 + LRU 双约束；[onChapter] 逐章回调（整本预载进度/分片让出 UI）。
  static Future<EpubDoc> openFile(
    String path, {
    void Function(int done, int total)? onChapter,
  }) async {
    late final LazyEpubArchive lz;
    try {
      lz = LazyEpubArchive.open(path);
    } catch (_) {
      throw const EpubFormatException('文件不是有效的 ZIP/EPUB 容器');
    }
    try {
      return _build(lz, lazy: lz, onChapter: onChapter);
    } catch (e) {
      lz.dispose();
      rethrow;
    }
  }

  /// 后台 isolate 解析（真机反馈 2026-09-28：22MB 书主 isolate 同步解析卡死）：
  /// isolate 内 openFile → 释放文件句柄 → 纯数据快照跨 isolate 传回 →
  /// 主 isolate 重挂懒归档（只读中央目录，毫秒级）。坏包/DRM 异常原样抛回。
  static Future<EpubDoc> openFileDetached(String path) async {
    final core = await Isolate.run(() async {
      final d = await openFile(path);
      d.lazy?.dispose();
      return d._copyNoLazy();
    });
    final lz = LazyEpubArchive.open(path);
    return core._withLazy(lz);
  }

  EpubDoc _copyNoLazy() => EpubDoc(
    format: format,
    title: title,
    author: author,
    publisher: publisher,
    pubDate: pubDate,
    language: language,
    description: description,
    coverBytes: coverBytes,
    coverName: coverName,
    toc: toc,
    chapters: chapters,
    imageCount: imageCount,
    totalChars: totalChars,
    fontCount: fontCount,
    bookmarkCount: bookmarkCount,
    images: const {},
  );

  EpubDoc _withLazy(LazyEpubArchive lz) => EpubDoc(
    format: format,
    title: title,
    author: author,
    publisher: publisher,
    pubDate: pubDate,
    language: language,
    description: description,
    coverBytes: coverBytes,
    coverName: coverName,
    toc: toc,
    chapters: chapters,
    imageCount: imageCount,
    totalChars: totalChars,
    fontCount: fontCount,
    bookmarkCount: bookmarkCount,
    images: const {},
    lazy: lz,
  );

  static EpubDoc _build(
    _Source files, {
    LazyEpubArchive? lazy,
    void Function(int done, int total)? onChapter,
  }) {
    // mimetype：存在即校验（历史宽松包偶有缺失，缺失不拒）。
    final mime = files.bytes('mimetype');
    if (mime != null &&
        !utf8.decode(mime, allowMalformed: true)
            .startsWith('application/epub+zip')) {
      throw const EpubFormatException('mimetype 声明不是 epub');
    }
    _assertNoDrm(files);

    final container = _xml(_str(files.bytes('META-INF/container.xml')));
    final opfPath = container
        ?.findAllElements('rootfile')
        .firstOrNull
        ?.getAttribute('full-path');
    if (opfPath == null || !files.has(opfPath)) {
      throw const EpubFormatException('缺 META-INF/container.xml 或 OPF');
    }
    final opf = _xml(_str(files.bytes(opfPath)));
    if (opf == null) throw const EpubFormatException('OPF 解析失败');
    // 注意：XmlDocument.root 不保证是 <package>（xml 6.x 下取不到其属性），
    // 版本判定必须按元素查找。
    final pkg = opf.findAllElements('package').firstOrNull;
    final format =
        (pkg?.getAttribute('version') ?? '').startsWith('3')
        ? 'EPUB3'
        : 'EPUB2';
    final opfDir = _dirName(opfPath);

    // manifest / spine
    final manifest = <String, ({String href, String type, String props})>{};
    for (final it in opf.findAllElements('item')) {
      final id = it.getAttribute('id');
      final href = it.getAttribute('href');
      if (id == null || href == null) continue;
      manifest[id] = (
        href: _resolve(opfDir, href),
        type: it.getAttribute('media-type') ?? '',
        props: it.getAttribute('properties') ?? '',
      );
    }
    final spineIds = opf
        .findAllElements('spine')
        .expand((s) => s.findAllElements('itemref'))
        .map((r) => r.getAttribute('idref'))
        .whereType<String>()
        .toList();

    final md = opf.findAllElements('metadata').firstOrNull;
    String? meta(String tag) =>
        md?.findAllElements(tag).firstOrNull?.innerText.trim();
    final title = meta('dc:title') ?? opfPath.split('/').last;

    // 封面三来源：EPUB3 cover-image 属性 → EPUB2 meta name=cover → guide type=cover。
    // （manifest 表的 href 已解析过，guide 是原始相对值——只对 guide 再做一次解析。）
    String? coverPath;
    for (final m in manifest.values) {
      if (m.props.split(RegExp(r'\s+')).contains('cover-image')) {
        coverPath = m.href;
      }
    }
    coverPath ??= () {
      final id = md
          ?.findAllElements('meta')
          .where((e) => e.getAttribute('name') == 'cover')
          .firstOrNull
          ?.getAttribute('content');
      return id == null ? null : manifest[id]?.href;
    }();
    coverPath ??= opf
        .findAllElements('guide')
        .expand((g) => g.findAllElements('reference'))
        .where((r) => r.getAttribute('type') == 'cover')
        .firstOrNull
        ?.getAttribute('href')
        ?.split('#')
        .first;
    if (coverPath != null && !manifest.values.any((m) => m.href == coverPath)) {
      // guide 来源：解析为 zip 内路径
      coverPath = _resolve(opfDir, coverPath);
    }
    final coverBytes = coverPath == null ? null : files.bytes(coverPath);

    // 目录：nav 优先（EPUB3），回落 ncx（EPUB2）。
    final toc = <EpubTocItem>[];
    final navItem = manifest.values
        .where((m) => m.props.split(RegExp(r'\s+')).contains('nav'))
        .firstOrNull;
    final ncxItem = manifest.values
        .where((m) => m.type == 'application/x-dtbncx+xml')
        .firstOrNull;
    if (navItem != null && files.has(navItem.href)) {
      toc.addAll(_parseNav(_str(files.bytes(navItem.href)!), navItem.href));
    } else if (ncxItem != null && files.has(ncxItem.href)) {
      toc.addAll(_parseNcx(_xml(_str(files.bytes(ncxItem.href)!)), ncxItem.href));
    }

    // 章节正文：spine 中指向 XHTML 的项逐段抽取；标题取目录首命中。
    final chapters = <EpubChapter>[];
    var imageCount = manifest.values.where((m) => m.type.startsWith('image/')).length;
    final spineDocs = spineIds
        .map((id) => manifest[id])
        .whereType<({String href, String type, String props})>()
        .where((m) => m.type.contains('html') && files.has(m.href))
        .toList();
    for (final m in spineDocs) {
      final raw = files.bytes(m.href);
      if (raw == null) continue;
      final paras = _extractParas(_str(raw), m.href);
      var viaToc = toc
          .where((t) => t.href == m.href)
          .firstOrNull
          ?.label;
      if (viaToc == null) {
        // 合集书常见：toc 与 spine 仅差目录前缀/大小写 → 按文件名再配一次。
        final bn = m.href.split('/').last.toLowerCase();
        viaToc = toc
            .where((t) => t.href.split('/').last.toLowerCase() == bn)
            .firstOrNull
            ?.label;
      }
      // 轮4①：目录仍没命中（合集目录常只指向每本书首文件）→ 回落章内首个
      // 标题段（如「第二十一章」），比文件名 part1394 可读得多。
      String? firstHeading;
      for (final p in paras) {
        if (p.kind == EpubParaKind.heading && p.text.trim().isNotEmpty) {
          final t = p.text.trim();
          firstHeading = t.length > 30 ? '${t.substring(0, 30)}…' : t;
          break;
        }
      }
      final title =
          viaToc ??
          firstHeading ??
          m.href.split('/').last.replaceAll(RegExp(r'\.x?html$'), '');
      chapters.add(
        EpubChapter(
          href: m.href,
          title: title,
          paras: paras,
        ),
      );
      onChapter?.call(chapters.length, spineDocs.length);
    }
    if (imageCount == 0) {
      // 少数包不进 manifest 声明，兜底按扩展名统计。
      imageCount = files.names
          .where((k) => RegExp(r'\.(jpe?g|png|gif|webp|svg)$', caseSensitive: false)
              .hasMatch(k))
          .length;
    }
    final totalChars = chapters.fold(0, (s, c) => s + c.charCount);
    if (chapters.isEmpty || totalChars == 0) {
      throw const EpubFormatException('包内没有可读的文本文档');
    }
    final fontCount = manifest.values
        .where((m) =>
            m.type.contains('font') ||
            RegExp(r'\.(woff2?|ttf|otf)$', caseSensitive: false).hasMatch(m.href))
        .length;
    var bookmarkCount = 0;
    if (ncxItem != null && files.has(ncxItem.href)) {
      bookmarkCount =
          _xml(_str(files.bytes(ncxItem.href)!))
              ?.findAllElements('pageList')
              .expand((l) => l.findAllElements('pageTarget'))
              .length ??
          0;
    }
    // 图片字节驻留策略：内存路径（parse）整表预填；懒归档（openFile）空表 +
    // imageBytes 按需 LRU——百 MB 图文包不再整包解码进内存。
    final images = lazy != null
        ? const <String, Uint8List>{}
        : <String, Uint8List>{
            for (final m in manifest.values)
              if (m.type.startsWith('image/') && files.bytes(m.href) != null)
                m.href: Uint8List.fromList(files.bytes(m.href)!),
          };
    // 真机反馈（大书滑动卡）：文本条目解压副本在抽取完成后立即释放，
    // 归档侧不再双份驻留（String/封面字节引用仍有效）。
    lazy?.releaseDecoded();
    return EpubDoc(
      format: format,
      title: title,
      author: meta('dc:creator') ?? '佚名',
      publisher: meta('dc:publisher'),
      pubDate: meta('dc:date'),
      language: meta('dc:language'),
      description: meta('dc:description'),
      coverBytes: coverBytes,
      coverName: coverPath,
      toc: toc,
      chapters: chapters,
      imageCount: imageCount,
      totalChars: totalChars,
      fontCount: fontCount,
      bookmarkCount: bookmarkCount,
      images: images,
      lazy: lazy,
    );
  }

  /// 加密声明检查：encryption.xml 内出现白名单外算法即 DRM 拒开。
  static void _assertNoDrm(_Source files) {
    final raw = files.bytes('META-INF/encryption.xml');
    if (raw == null) return;
    final doc = _xml(_str(raw));
    if (doc == null) return;
    const fontObfuscation = {
      'http://www.idpf.org/2004/embedded-fonts', // IDPF 字体混淆（可读）
      'http://ns.adobe.com/pdf/enc#RC', // Adobe 字体混淆（可读）
    };
    for (final em in doc.findAllElements('EncryptionMethod')) {
      final uri = em.getAttribute('Algorithm') ?? em.getAttribute('URI') ?? '';
      if (!fontObfuscation.contains(uri) && uri.isNotEmpty) {
        throw const EpubFormatException('DRM 加密书籍不支持 · 请购买无 DRM 版本');
      }
    }
  }
}

// ---------- 归档访问抽象（批3.5） ----------

/// zip 条目访问抽象：内存整表 vs 懒归档。
abstract class _Source {
  List<int>? bytes(String path);
  bool has(String path);
  Iterable<String> get names;
}

class _MapSource implements _Source {
  _MapSource(this.m);
  final Map<String, List<int>> m;
  @override
  List<int>? bytes(String path) => m[path];
  @override
  bool has(String path) => m.containsKey(path);
  @override
  Iterable<String> get names => m.keys;
}

/// 图片 LRU 驻留上限（批3.5 口径：≤12 张双约束）。
const int kEpubImageLruMax = 12;

/// 懒归档：InputFileStream + 中央目录索引，条目不点不解压（archive 3.6.1 的
/// `ArchiveFile.content` 即按需 inflate）；图片解码走 LRU（超出
/// [kEpubImageLruMax] 张即淘汰并 clear() 释放驻留字节），文本读取后常驻（几 MB 级）。
class LazyEpubArchive implements _Source {
  LazyEpubArchive._(this._stream, this._archive) {
    for (final f in _archive) {
      if (f.isFile) _idx[f.name] = f;
    }
  }

  final InputFileStream _stream;
  final Archive _archive;
  final Map<String, ArchiveFile> _idx = {};
  final LinkedHashMap<String, Uint8List> _lru = LinkedHashMap();
  final Set<String> _decodedPaths = {};

  /// 已解码驻留的图片数（回归断言「open 不解压图片」用）。
  int get cachedImageCount => _lru.length;

  /// 累计解码次数（文本+图片；同一条目只计一次）。
  int get decodedTotal => _decodedPaths.length;

  static LazyEpubArchive open(String path) {
    final stream = InputFileStream(path);
    return LazyEpubArchive._(stream, ZipDecoder().decodeBuffer(stream));
  }

  @override
  List<int>? bytes(String path) {
    final f = _idx[path];
    if (f == null) return null;
    _decodedPaths.add(path); // 首次访问触发按需解压（archive 3.6.1 惰性 inflate）
    final c = f.content;
    if (c == null) return null;
    return c is List<int> ? c : (c as List).cast<int>();
  }

  /// 图片按需解码 + LRU 双约束（≤12 张驻留，逐出即释放）。
  Uint8List? image(String path) {
    final hit = _lru[path];
    if (hit != null) return hit;
    final raw = bytes(path);
    if (raw == null) return null;
    final u = raw is Uint8List ? raw : Uint8List.fromList(raw);
    _lru[path] = u;
    while (_lru.length > kEpubImageLruMax) {
      final oldest = _lru.keys.first;
      _lru.remove(oldest);
      _idx[oldest]?.clear(); // 释放归档内解压驻留
    }
    return u;
  }

  /// 释放所有已解码条目的归档侧副本（文本抽取完成后调用；引用方仍持数据）。
  void releaseDecoded() {
    for (final n in _decodedPaths) {
      _idx[n]?.clear();
    }
  }

  @override
  bool has(String path) => _idx.containsKey(path);

  @override
  Iterable<String> get names => _idx.keys;

  void dispose() {
    _lru.clear();
    try {
      _stream.close();
    } catch (_) {}
  }
}

// ---------- 工具与子解析 ----------

List<int> _archivedBytes(ArchiveFile f) {
  final c = f.content;
  if (c is List<int>) return c;
  return (c as List).cast<int>();
}

String _str(List<int>? bytes) =>
    bytes == null ? '' : utf8.decode(bytes, allowMalformed: true);

XmlDocument? _xml(String s) {
  try {
    return XmlDocument.parse(s);
  } catch (_) {
    return null;
  }
}

String _dirName(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i);
}

/// 相对 href 解析（.. 折叠 + 去 fragment），与 zip 条目名对齐。
String _resolve(String base, String ref) {
  if (ref.startsWith('/')) return ref.substring(1);
  final frag = ref.indexOf('#');
  var r = frag < 0 ? ref : ref.substring(0, frag);
  r = Uri.decodeFull(r);
  final joined = base.isEmpty ? r : '$base/$r';
  final segs = <String>[];
  for (final s in joined.split('/')) {
    if (s == '.' || s.isEmpty) continue;
    if (s == '..') {
      if (segs.isNotEmpty) segs.removeLast();
      continue;
    }
    segs.add(s);
  }
  return segs.join('/');
}

/// EPUB3 nav（xhtml）：body 下第一个含 a 的 ol 起按嵌套深度记 level（>2 归 2）。
List<EpubTocItem> _parseNav(String xhtml, String navPath) {
  final out = <EpubTocItem>[];
  final doc = hparser.parse(xhtml);
  final navs = doc.querySelectorAll('nav');
  h.Element? nav;
  for (final n in navs) {
    final t = n.attributes['epub:type'] ?? n.attributes['type'];
    if (t == 'toc') {
      nav = n;
      break;
    }
  }
  nav ??= navs.isNotEmpty ? navs.first : doc.body;
  final ol = nav?.querySelector('ol');
  if (ol == null) return out;
  final base = _dirName(navPath);
  void walk(h.Element listEl, int level) {
    for (final li in listEl.children.where((c) => c.localName == 'li')) {
      final a = li.querySelector('a') ?? li.querySelector('span');
      final label = (a?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
      final href = a?.attributes['href'];
      final sub = li.children
          .where((c) => c.localName == 'ol')
          .firstOrNull;
      if (label.isNotEmpty && href != null) {
        out.add(
          EpubTocItem(
            label: label,
            href: _resolve(base, href),
            level: level > 1 ? 2 : 1,
          ),
        );
      }
      if (sub != null) walk(sub, level + 1);
    }
  }
  walk(ol, 1);
  return out;
}

/// EPUB2 ncx navMap：navPoint 递归，深度即 level（>2 归 2），playOrder 仅序参考。
List<EpubTocItem> _parseNcx(XmlDocument? ncx, String ncxPath) {
  final out = <EpubTocItem>[];
  final navMap = ncx?.findAllElements('navMap').firstOrNull;
  if (navMap == null) return out;
  final base = _dirName(ncxPath);
  void walk(Iterable<XmlElement> points, int level) {
    for (final p in points) {
      final label = p
          .findAllElements('text')
          .firstOrNull
          ?.innerText
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final src = p
          .findAllElements('content')
          .firstOrNull
          ?.getAttribute('src');
      if (label != null && label.isNotEmpty && src != null) {
        out.add(
          EpubTocItem(label: label, href: _resolve(base, src), level: level > 1 ? 2 : 1),
        );
      }
      walk(p.findElements('navPoint'), level + 1);
    }
  }
  walk(navMap.findElements('navPoint'), 1);
  return out;
}

/// XHTML → 段落序列（p/div/section/h1-6/blockquote/img/figure/li/aside；其余块并入文本流）。
/// 段内 <a> 记为 [EpubLink]（内链解析成 zip 路径，外链保留原样）。
/// R3-2 止血带出的语义（① 注释体 · ③ 自带缩进 · ④ 站内锚点）在此**一次判定完**，
/// 渲染层只读 [EpubPara.annotation]/[EpubPara.ownIndent]/[EpubLink.usesLinkColor]。
List<EpubPara> _extractParas(String xhtml, String docPath) {
  final out = <EpubPara>[];
  final doc = hparser.parse(xhtml);
  final body = doc.body ?? doc.documentElement;
  if (body == null) return out;
  final base = _dirName(docPath);

  String norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  // ④ 外链＝带 scheme（http:/https:/mailto:/tel:/ftp:/…）或协议相对 //host。
  bool hasScheme(String href) =>
      RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*:').hasMatch(href) ||
      href.startsWith('//');

  // ① 注释体判定（工单 R3-2 原文口径）：epub:type 含 footnote/note ·
  // 类名含 note|footnote|annotation（noteref/notes/annotation-* 都落在这三词里）。
  final noteTypeRe = RegExp(r'footnote|note', caseSensitive: false);
  final noteClassRe = RegExp(r'note|footnote|annotation', caseSensitive: false);
  bool isNoteEl(h.Element el) {
    final t = el.attributes['epub:type'] ?? el.attributes['type'];
    if (t != null && noteTypeRe.hasMatch(t)) return true;
    final c = el.attributes['class'];
    return c != null && noteClassRe.hasMatch(c);
  }

  // ③ 书内自带首行缩进：段内 style 的 text-indent（非 0/none），或正文本身以
  // 全角空格/持续空白起头（中文古籍常见写法）。换行起头的源码缩进不算。
  final textIndentRe = RegExp(
    r'text-indent\s*:\s*([^;]+)',
    caseSensitive: false,
  );
  bool ownIndentOf(h.Element el, String raw) {
    final m = textIndentRe.firstMatch(el.attributes['style'] ?? '');
    final v = m?.group(1)?.trim().toLowerCase();
    if (v != null &&
        v.isNotEmpty &&
        v != 'none' &&
        v != 'inherit' &&
        v != 'initial' &&
        !RegExp(r'^0([.,].*)?$').hasMatch(v)) {
      return true;
    }
    // 段首空白码位：半角空格/制表/NBSP/全角空格（不含换行——源码缩进不算）。
    const leadWs = {0x20, 0x09, 0x00a0, 0x3000};
    var n = 0;
    while (n < raw.length && leadWs.contains(raw.codeUnitAt(n))) {
      n++;
    }
    if (n == 0) return false;
    final lead = raw.substring(0, n);
    // 全角空格/NBSP 单个即算自带缩进；普通空白要 2 个以上。
    return lead.codeUnits.contains(0x3000) ||
        lead.codeUnits.contains(0x00a0) ||
        n >= 2;
  }

  /// 收集元素文本 + 链接区间（a 只取其文字，不取 URL）。
  (String, List<EpubLink>) grab(h.Element el) {
    final sb = StringBuffer();
    final links = <EpubLink>[];
    void walkNode(h.Node n) {
      if (n is h.Text) {
        sb.write(n.text);
        return;
      }
      if (n is! h.Element) return;
      final tag = n.localName ?? '';
      if (tag == 'br') {
        sb.write(' ');
        return;
      }
      final href = n.attributes['href'];
      if (tag == 'a' && href != null && href.isNotEmpty) {
        final s = sb.length;
        for (final c in n.nodes) {
          walkNode(c);
        }
        final isExt = hasScheme(href);
        // ④ sameDoc＝纯 #fragment 或解析后仍落在本文档。**不改 href 口径**
        // （内链点击行为沿用批2 的「命中 spine 章即跳章」，改它会顺手动到跳转语义）。
        final same =
            !isExt && (href.startsWith('#') || _resolve(base, href.split('#').first) == docPath);
        links.add(
          EpubLink(
            start: s,
            end: sb.length,
            href: isExt ? href : _resolve(base, href.split('#').first),
            external: isExt,
            annotation: isNoteEl(n),
            sameDoc: same,
          ),
        );
        return;
      }
      for (final c in n.nodes) {
        walkNode(c);
      }
    }
    for (final c in el.nodes) {
      walkNode(c);
    }
    return (sb.toString(), links);
  }

  void pushText(
    h.Element el,
    EpubParaKind k, {
    int level = 0,
    bool annotation = false,
  }) {
    final (raw, links) = grab(el);
    final s = norm(raw);
    if (s.isEmpty) return;
    // norm 会折叠首尾空白，链接区间按折叠近似保留（渲染端以文本再定位兜底）。
    out.add(
      EpubPara(
        kind: k,
        text: s,
        headingLevel: level,
        links: links,
        annotation: annotation || isNoteEl(el),
        ownIndent: ownIndentOf(el, raw),
      ),
    );
  }

  void pushImg(String src, String alt) {
    if (src.isEmpty) return;
    out.add(
      EpubPara(
        kind: EpubParaKind.image,
        imgSrc: _resolve(base, src),
        alt: norm(alt),
      ),
    );
  }

  /// [note]＝祖先容器已是注释体（`<div class="footnotes">`/`<section epub:type=...>`），
  /// 段级继承下去——这是「按段判断、不一刀切」的另一半。
  void walk(h.Element el, {bool note = false}) {
    final tag = el.localName ?? '';
    final ann = note || isNoteEl(el);
    switch (tag) {
      case 'p':
        pushText(el, EpubParaKind.text, annotation: ann);
      case 'div':
      case 'section':
      case 'article':
      case 'footer':
      case 'header':
        // 容器含子块则下钻（注释语义随之下传），纯文本容器当段落。
        if (el.children.isEmpty) {
          pushText(el, EpubParaKind.text, annotation: ann);
          return;
        }
        for (final c in el.children) {
          walk(c, note: ann);
        }
      case 'aside':
        // ① aside 整块即注释体（工单原文点名）。
        if (el.children.isEmpty) {
          pushText(el, EpubParaKind.text, annotation: true);
        } else {
          for (final c in el.children) {
            walk(c, note: true);
          }
        }
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        pushText(
          el,
          EpubParaKind.heading,
          level: int.parse(tag.substring(1)),
          annotation: ann,
        );
      case 'blockquote':
        if (el.children.where((c) => c.localName == 'p').isEmpty) {
          pushText(el, EpubParaKind.quote, annotation: ann);
        } else {
          for (final c in el.children) {
            if (c.localName == 'p') {
              pushText(c, EpubParaKind.quote, annotation: ann);
            }
          }
        }
      case 'img':
        pushImg(el.attributes['src'] ?? '', el.attributes['alt'] ?? '');
      case 'figure':
        final img = el.querySelector('img');
        final cap = el.querySelector('figcaption');
        if (img != null) {
          pushImg(
            img.attributes['src'] ?? '',
            (cap?.text ?? img.attributes['alt'] ?? ''),
          );
        }
      case 'li':
        pushText(el, EpubParaKind.text, annotation: ann);
        for (final c in el.children) {
          if (c.localName == 'li' ||
              c.localName == 'ul' ||
              c.localName == 'ol') {
            walk(c, note: ann);
          }
        }
      case 'ul':
      case 'ol':
        for (final c in el.children) {
          walk(c, note: ann);
        }
      case 'br':
        break;
      case 'table':
      case 'tr':
      case 'tbody':
      case 'thead':
        for (final c in el.children) {
          walk(c, note: ann);
        }
      default:
        final s = norm(el.text);
        if (s.isNotEmpty) {
          final (raw, links) = grab(el);
          final t = norm(raw);
          if (t.isNotEmpty) {
            out.add(
              EpubPara(
                kind: EpubParaKind.text,
                text: t,
                links: links,
                annotation: ann,
                ownIndent: ownIndentOf(el, raw),
              ),
            );
          }
        }
    }
  }

  for (final c in body.children) {
    walk(c);
  }
  // body 只有裸文本（无包裹元素）时兜底整段。
  if (out.isEmpty && norm(body.text).isNotEmpty) {
    final (raw, links) = grab(body);
    out.add(
      EpubPara(
        kind: EpubParaKind.text,
        text: norm(raw),
        links: links,
        annotation: isNoteEl(body),
        ownIndent: ownIndentOf(body, raw),
      ),
    );
  }
  return out;
}
