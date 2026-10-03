import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/app_log.dart';
import '../domain/book.dart';
import '../presentation/reader/reader_pager.dart';
import 'epub_css.dart';
import 'epub_doc.dart';
import 'epub_first_img.dart';
import 'read_repository.dart';

/// 批3.5 · 大书内存模型与预载/清缓存服务（V1.60 §3G 改造后口径）。
///
/// 三条拍板口径（需求 V1.50 批3.5 ＋ V1.60 §3G）：
/// 1. **整本预载**：导入落库后后台异步「解析 + 排版快照 + 封面衍生」——V1.60 起
///    **预载链不再建分页表**（表随首次开书后台按章续算）；预载中点封面可直接进入
///    阅读（[warming] 与在跑的解析并路）；预载完成后二次打开＝秒进（[EpubDocCache]）。
/// 2. **50/100MB 图文包**：生产路径 [EpubDoc.openFile] 懒归档（条目不点不解压），
///    图片按需解码 + LRU（≤12 张），章文本全量驻留；分页表落盘（[PagStore]），
///    按「外观 cfg + 视口指纹」失效。
/// 3. **单书清缓存**：只回收私有副本 + 封面衍生 + 分页表；记录/书摘划线/计时/
///    进度全保留；**源文件绝不删除**。三态恢复见 [EpubCacheService]。

// ---------- 分页表落盘（V1.60 · 按章分片） ----------

/// 分页表持久层：`docs/epub_pag/<bookId>/`＝`index.json`（版本＋指纹＋章数）
/// ＋ `ch_<i>.json`（单章页表分片）。分片口径（§3G 结论二，2026-10-04 拍板）：
/// 旧单文件全书表一次取表随体积涨到约 1 秒（新书 7ms），**开书/续算一律只按章
/// 读写**，取表成本不再随书体积增长；全书表由首次开书后的后台续算逐章补齐
/// （导入/预载链不再建表）。
/// 指纹不一致（外观/视口变化）＝整档作废：下一次分片写入时重置目录。
class PagStore {
  const PagStore._();

  /// v3（LH-F01）：三值族映射从泛族（'serif'/'sans-serif'）换成与原型同串的中文链，
  /// 而指纹进的是 **枚举值** `fnt${l.font}`——值没变、实排变了，不升版本旧分页表
  /// 会继续命中，真机表现为「改了字体页码/偏移与实排不符」。
  /// v4（批三刀2）：段内 span 级原书语义（分层注释色/小字/专名线）进上屏排版，
  /// 而指纹进的是配置项——样式数据变了、配置没变，旧表继续命中＝按无样式排版画有样式书。
  /// v5（§3H-A）：页载荷从「段下标」升成**块三元组 [pi,from,to]**（超长段跨页续排），
  /// 形状变了必须让所有旧表整体失效；同批还有可视高口径（减顶部安全区）与
  /// 段外距/测量宽/统一行盒三处同源修正，每一处都足以让旧页对不上新字。
  /// v6（V1.60 §3G）：单文件全书表改**按章分片目录**——旧 v5 单文件与本版无相容性，
  /// 首次分片写入即出清旧文件；开书只读当前章，全书由首次开书后台续算补齐。
  static const tableVersion = 6;

  /// 外观 cfg + 视口指纹（reader_pager.ReaderLayout 全字段参与）。
  /// R3-2 ③：indMode 三档改变每段显示文本（自带缩进段不再叠加）→ 必须进指纹，
  /// 否则改了缩进设置不重排＝真机假生效。`just` 不入指纹：两端对齐只拉伸行内
  /// 空隙、不改断行，TextPainter 实算高度与左对齐一致（进指纹反而每次白重排）。
  /// R3-6：s2t 同 indMode 口径——它换的是上屏字符（逐字等长但字形度量可能不同）。
  /// 批三刀3：`orig`（跟随原书样式）同口径进指纹——它改的是**每段的字号比与线**，
  /// 断行直接变；漏进去＝切了开关不重排＝真机假生效。
  static String fingerprint(ReaderLayout l) =>
      '${l.width.round()}x${l.height.round()}|fs${l.fs}|lh${l.lh}|ls${l.ls}'
      '|mar${l.mar}|fnt${l.font}|ind${l.indent ? 1 : 0}|im${l.indMode}'
      '|s2t${l.s2t}|og${l.orig ? 1 : 0}';

  static String dirPath(String docsPath) => p.join(docsPath, 'epub_pag');

  /// 旧版（v≤5）单文件路径：v6 起只用于回收与体积兼容统计，不再写入。
  static File fileFor(String docsPath, String bookId) =>
      File(p.join(dirPath(docsPath), '$bookId.json'));

  static String bookDir(String docsPath, String bookId) =>
      p.join(dirPath(docsPath), bookId);

  static File _indexFile(String docsPath, String bookId) =>
      File(p.join(bookDir(docsPath, bookId), 'index.json'));

  static File _chapterFile(String docsPath, String bookId, int ci) =>
      File(p.join(bookDir(docsPath, bookId), 'ch_$ci.json'));

  static bool _indexOk(Object? j, String fp) =>
      j is Map && j['v'] == tableVersion && j['fp'] == fp;

  static Object? _readIndex(String docsPath, String bookId) {
    final f = _indexFile(docsPath, bookId);
    if (!f.existsSync()) return null;
    try {
      return jsonDecode(f.readAsStringSync());
    } catch (_) {
      // catch-ok: 坏索引＝无表语义（与旧「坏表实算兜回」同口径）。
      return null;
    }
  }

  /// 本书分片档是否存在且命中当前指纹（开书日志「落盘表=命中|未命中」读数用；
  /// 只读几 KB 的 index，不是取表）。
  static Future<bool> hit(String docsPath, String bookId, String fp) async =>
      _indexOk(_readIndex(docsPath, bookId), fp);

  /// 单章分片读：无档/指纹不符/该章未排/坏表＝null（调用方实算）。
  static Future<PagChapter?> loadChapter(
    String docsPath,
    String bookId,
    String fp,
    int ci,
  ) async {
    try {
      if (!_indexOk(_readIndex(docsPath, bookId), fp)) return null;
      final f = _chapterFile(docsPath, bookId, ci);
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map || j['v'] != tableVersion || j['fp'] != fp) return null;
      return _chapterFromJson(j['pages']);
    } catch (_) {
      // catch-ok: 坏分片＝该章未排（实算兜回），不打断开书。
      return null;
    }
  }

  /// 单章分片写（首次开书后台续算与翻页实算共用）。
  /// 目录缺失或指纹已变＝整档重置后再写——杜绝新旧指纹分片混排。
  static Future<void> saveChapter(
    String docsPath,
    String bookId,
    String fp,
    int ci,
    PagChapter chapter,
    int chapterCount,
  ) async {
    final idx = _readIndex(docsPath, bookId);
    if (!_indexOk(idx, fp)) {
      final dir = Directory(bookDir(docsPath, bookId));
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
    }
    final n = chapterCount > 0 ? chapterCount : ci + 1;
    await _indexFile(docsPath, bookId).writeAsString(
      jsonEncode({'v': tableVersion, 'fp': fp, 'n': n}),
      flush: true,
    );
    await _chapterFile(docsPath, bookId, ci).writeAsString(
      jsonEncode({
        'v': tableVersion,
        'fp': fp,
        // 块编码沿用 §3H-A 的 2/3 元组分流（PagPiece.encode）。
        'pages': [
          for (final pg in chapter) [for (final b in pg) b.encode()],
        ],
      }),
      flush: true,
    );
    // 旧单文件形态出清（v5 及以前的一次性全书表，升级即作废重建）。
    final legacy = fileFor(docsPath, bookId);
    if (await legacy.exists()) await legacy.delete();
  }

  /// 分片 JSON → 章页表；形状不对抛异常由调用方按「未排」消化。
  static PagChapter? _chapterFromJson(Object? pages) {
    if (pages is! List) return null;
    return [
      for (final pg in pages)
        [
          for (final b in pg as List) PagPiece.decode(b as List),
        ],
    ];
  }

  /// 整本落盘（兼容 API：测试与小书一次性路径；阅读器开书线走分片）。
  static Future<void> save(
    String docsPath,
    String bookId,
    String fp,
    BookPagination pag,
  ) async {
    final dir = Directory(bookDir(docsPath, bookId));
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    await _indexFile(docsPath, bookId).writeAsString(
      jsonEncode({'v': tableVersion, 'fp': fp, 'n': pag.chapterCount}),
      flush: true,
    );
    for (var ci = 0; ci < pag.pages.length; ci++) {
      final ch = pag.pages[ci];
      if (ch == null) continue;
      await _chapterFile(docsPath, bookId, ci).writeAsString(
        jsonEncode({
          'v': tableVersion,
          'fp': fp,
          'pages': [
            for (final pg in ch) [for (final b in pg) b.encode()],
          ],
        }),
        flush: true,
      );
    }
    final legacy = fileFor(docsPath, bookId);
    if (await legacy.exists()) await legacy.delete();
  }

  /// 整本读表（兼容 API；允许部分章缺＝null）。无档/坏档/指纹不符＝null。
  /// 分片读＋解码全在 isolate 内（真机修⑥同源：2409 章级大表不碰主线程）。
  static Future<BookPagination?> load(
    String docsPath,
    String bookId,
    String fp,
    List<int> weights,
  ) async {
    try {
      final idx = _readIndex(docsPath, bookId);
      if (!_indexOk(idx, fp)) return null;
      final n = (idx as Map)['n'];
      return compute(
        _pagFromDir,
        (
          bookDir(docsPath, bookId),
          fp,
          n is num ? n.toInt() : weights.length,
          weights,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static BookPagination? _pagFromDir((String, String, int, List<int>) arg) {
    final (dir, fp, n, weights) = arg;
    try {
      final chapters = <PagChapter?>[];
      for (var ci = 0; ci < n && ci < weights.length; ci++) {
        final f = File(p.join(dir, 'ch_$ci.json'));
        if (!f.existsSync()) {
          chapters.add(null);
          continue;
        }
        final j = jsonDecode(f.readAsStringSync());
        if (j is! Map || j['v'] != tableVersion || j['fp'] != fp) return null;
        chapters.add(_chapterFromJson(j['pages']));
      }
      return BookPagination.fromTable(weights, chapters);
    } catch (_) {
      // catch-ok: 坏表/形状不符＝静默回落整章实算。本函数跑在 compute 起的 isolate 里，
      // 自建日志跨不了 isolate（读表侧本来就允许「无表」同语义）。
      return null;
    }
  }

  static Future<void> remove(String docsPath, String bookId) async {
    final dir = Directory(bookDir(docsPath, bookId));
    if (await dir.exists()) await dir.delete(recursive: true);
    final legacy = fileFor(docsPath, bookId);
    if (await legacy.exists()) await legacy.delete();
  }

  static Future<int> sizeOf(String docsPath, String bookId) async {
    var sum = 0;
    final dir = Directory(bookDir(docsPath, bookId));
    if (dir.existsSync()) {
      for (final e in dir.listSync()) {
        if (e is File) sum += e.lengthSync();
      }
    }
    final legacy = fileFor(docsPath, bookId);
    if (legacy.existsSync()) sum += legacy.lengthSync();
    return sum;
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
  /// v4（批三刀2）：段落模型加了两层原书语义（段级 [EpubPara.style] 与 span 级
  /// [EpubPara.runs]），旧快照一律缺这两项＝分层色与小字全丢＝假生效，必须 +1 整体失效重解。
  /// 载荷形状同时改：data.bin 每章＝`[样式字典, 段落表]`（字典去重；通鉴全书 672k span
  /// 只有个位数种风格，逐段重复写等价于把快照撑大一个量级）。
  static const snapVersion = 4;

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

  // —— 样式编解码（快照内字典去重；JSON 里 null＝该属性没声明）——

  static const _alignCodes = ['left', 'center', 'right', 'justify'];
  static const _decoCodes = ['solid', 'double', 'dotted', 'dashed', 'wavy'];
  static const _borderStyleCodes = [
    'solid',
    'double',
    'dotted',
    'dashed',
    'groove',
    'ridge',
    'inset',
    'outset',
    'hidden',
  ];

  static List _styleJson(EpubStyle s) => [
    s.color?.toARGB32(),
    s.backgroundColor?.toARGB32(),
    s.fontRatio,
    s.weight,
    s.italic ? 1 : 0,
    s.lineRatio,
    s.indentEm,
    s.align == null ? -1 : _alignCodes.indexOf(s.align!),
    s.marginLeftEm,
    s.marginRightEm,
    s.marginTopEm,
    s.marginBottomEm,
    _borderJson(s.borderLeft),
    _borderJson(s.borderRight),
    _borderJson(s.borderTop),
    _borderJson(s.borderBottom),
    s.underline ? 1 : 0,
    s.overline ? 1 : 0,
    s.lineThrough ? 1 : 0,
    s.lineColor?.toARGB32(),
    s.deco == null ? -1 : _decoCodes.indexOf(s.deco!),
  ];

  static List? _borderJson(EpubBorder? b) => b == null
      ? null
      : [
          b.widthEm,
          b.widthPx,
          b.style == null ? -1 : _borderStyleCodes.indexOf(b.style!),
          b.color?.toARGB32(),
        ];

  static Object? _at(List a, int i) => i < a.length ? a[i] : null;

  static double? _dAt(List a, int i) {
    final v = _at(a, i);
    return v is num ? v.toDouble() : null;
  }

  static int? _iAt(List a, int i) {
    final v = _at(a, i);
    return v is num ? v.toInt() : null;
  }

  static EpubStyle _styleFromJson(List a) {
    EpubBorder? bd(int i) {
      final v = _at(a, i);
      if (v is! List) return null;
      final st = _iAt(v, 2);
      if (st != null && st == _borderStyleCodes.length - 1) return EpubBorder.none;
      return EpubBorder(
        widthEm: _dAt(v, 0),
        widthPx: _dAt(v, 1),
        style: st == null || st < 0 ? null : _borderStyleCodes[st],
        color: _iAt(v, 3) == null ? null : Color(_iAt(v, 3)!),
      );
    }

    final al = _iAt(a, 7);
    return EpubStyle(
      color: _iAt(a, 0) == null ? null : Color(_iAt(a, 0)!),
      backgroundColor: _iAt(a, 1) == null ? null : Color(_iAt(a, 1)!),
      fontRatio: _dAt(a, 2),
      weight: _iAt(a, 3),
      italic: _flag(a, 4) == 1,
      lineRatio: _dAt(a, 5),
      indentEm: _dAt(a, 6),
      align: al == null || al < 0 || al >= _alignCodes.length ? null : _alignCodes[al],
      marginLeftEm: _dAt(a, 8),
      marginRightEm: _dAt(a, 9),
      marginTopEm: _dAt(a, 10),
      marginBottomEm: _dAt(a, 11),
      borderLeft: bd(12),
      borderRight: bd(13),
      borderTop: bd(14),
      borderBottom: bd(15),
      underline: _flag(a, 16) == 1,
      overline: _flag(a, 17) == 1,
      lineThrough: _flag(a, 18) == 1,
      lineColor: _iAt(a, 19) == null ? null : Color(_iAt(a, 19)!),
      deco: (() {
        final i = _iAt(a, 20);
        return i == null || i < 0 || i >= _decoCodes.length ? null : _decoCodes[i];
      })(),
    );
  }

  /// [idOf]＝样式interning（同风格只入典一次，段与 runs 都只写下标）。
  static List _paraJson(EpubPara x, int Function(EpubStyle) idOf) => [
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
    // 批三刀2：段级原书样式下标（-1＝无声明）＋ span 区间 [起, 止, 样式下标]。
    x.style == null ? -1 : idOf(x.style!),
    [
      for (final r in x.runs) [r.start, r.end, idOf(r.style)],
    ],
  ];

  static int _flag(List src, int i) => i < src.length ? src[i] as int : 0;

  static EpubPara _paraFromJson(List a, List styles) => EpubPara(
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
    style: _styleAt(a, 8, styles),
    runs: _runsAt(a, 9, styles),
  );

  /// 缺位/越界都回落成「没有原书样式」——快照被截断或字段缺失不许炸（防御读）。
  static EpubStyle? _styleAt(List a, int i, List styles) {
    final id = _iAt(a, i);
    if (id == null || id < 0 || id >= styles.length) return null;
    final s = styles[id];
    return s is List ? _styleFromJson(s) : null;
  }

  static List<EpubStyleRun> _runsAt(List a, int i, List styles) {
    final v = _at(a, i);
    if (v is! List) return const [];
    final out = <EpubStyleRun>[];
    for (final r in v) {
      if (r is! List) continue;
      final st = _styleAt(r, 2, styles);
      final s0 = _iAt(r, 0), s1 = _iAt(r, 1);
      if (st == null || s0 == null || s1 == null || s1 <= s0) continue;
      out.add(EpubStyleRun(start: s0, end: s1, style: st));
    }
    return out;
  }

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
        // 章级样式字典：同风格只存一份，段与 runs 存下标。
        final styles = <List>[];
        final ids = <EpubStyle, int>{};
        int idOf(EpubStyle st) => ids.putIfAbsent(st, () {
              styles.add(_styleJson(st));
              return styles.length - 1;
            });
        final b = utf8.encode(
          jsonEncode([
            styles,
            [for (final x in c.paras) _paraJson(x, idOf)],
          ]),
        );
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
      // 批三刀2：包内声明了我们表达不了的排版项（竖排/多栏/浮动/表格/行内留白…），
      // 随快照落盘，重开也还在——刀3 用它落日志＋该书外观页提示行（不许静默降级）。
      'uns': [
        for (final u in doc.unsupported)
          [u.kind.index, u.property, u.value, u.count],
      ],
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
    final uns = <EpubUnsupported>[];
    final rawUns = m['uns'];
    if (rawUns is List) {
      for (final u in rawUns) {
        if (u is! List || u.length < 3) continue;
        final kind = u[0] is int && u[0] >= 0 && u[0] < EpubUnsupportedKind.values.length
            ? EpubUnsupportedKind.values[u[0] as int]
            : EpubUnsupportedKind.cssStructural;
        uns.add(
          EpubUnsupported(
            kind: kind,
            property: '${u[1]}',
            value: '${u[2]}',
            count: u.length > 3 && u[3] is num ? (u[3] as num).toInt() : 1,
          ),
        );
      }
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
      unsupported: uns,
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
        // v4 载荷＝[样式字典, 段落表]；单表形态（缺字典）按无样式读，不炸。
        final styles = raw.isNotEmpty && raw[0] is List && (raw[0] as List).isNotEmpty &&
                (raw[0] as List).first is List
            ? raw[0] as List
            : const [];
        final rows = raw.length == 2 && raw[1] is List ? raw[1] as List : raw;
        paras = [
          for (final a in rows)
            if (a is List) DocStore._paraFromJson(a, styles),
        ];
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

/// 整本预载服务（V1.60 §3G）：导入提交后后台跑「解析（isolate）→ 排版快照 →
/// 封面衍生 → 状态置 rdy」——**不再建分页表**，表随首次开书按章后台续算
/// （reader_page_pag）。预载中点封面＝可进：[warming] 挂的是这一份解析，开书侧
/// 并路等待、不重复整本解析。进度经 [info] 暴露给封面；状态持久化在
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

  /// 预载一本书（幂等：同书在跑则直接返回）。
  /// [layout] 保留兼容旧调用——V1.60 §3G 起预载链不再建分页表，本参数已不消费。
  Future<void> preload(Book b, ReaderLayout layout) async {
    final ep = b.epub;
    if (ep == null || ep.path.isEmpty) return;
    if (_running.contains(b.id)) return;
    _running.add(b.id);
    _info.remove(b.id); // 上轮错误不残留
    // V1.60（§3G 拍板）：预载中点封面＝直接进阅读。把这一份解析挂进预热位，
    // 开书侧 `await svc.warming` 等的是同一个 future，不再二次整本解析。
    final gate = Completer<void>();
    _warmTasks[b.id] = gate.future;
    final docs0 = await _docs0();
    try {
      await _mark(b, EpubRef.stPreload, 4);
      // ① 解析（后台 isolate 懒归档：open 只读中央目录，文本逐章解压、图片零驻留）
      final doc = await (parseOverride ??
              ((path) async => EpubDoc.openFileDetached(path)))(ep.path);
      docs.put(b.id, doc);
      if (!gate.isCompleted) gate.complete();
      // 批5：解析结果按章落盘（下次冷启动打开＝读快照，不再整本重析）。
      if (docs0 != null && parseOverride == null) {
        await DocStore.save(docs0, b.id, DocStore.fingerprint(ep.path), doc);
      }
      await _mark(b, EpubRef.stPreload, 45);
      // ② V1.60（§3G 拍板）：**导入/预载链到此为止，不再建分页表**——
      //    表改由首次开书后按章后台续算逐片落盘（reader_page_pag），
      //    「第一次加载耗时不限、加载完开书必须秒开」的账在这里付清。
      //    （轮4 教训保留：主线程绝不跑整本循环。）
      // R14-4：无真封面的本地书在预载尾步生成 A 档正文首图衍生件（幂等；
      // 清缓存后的恢复重预载也走这里再生）。失败不阻断预载终态。
      if (b.coverPath == null) {
        try {
          final fi = await EpubFirstImg.ensure(
            docsPath: docs0!,
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
      _warmTasks.remove(b.id);
      if (!gate.isCompleted) gate.complete();
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
  /// 兼容 API：V1.60 起阅读器开书线只走下面的按章分片，整本读表面留给测试与小书路径。
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

  // ---------- V1.60 §3G · 按章分片读写（开书/续算唯一入口） ----------

  /// 分片档是否命中当前指纹（开书日志「落盘表=命中|未命中」读数；只读 index）。
  Future<bool> pagHit(String bookId, ReaderLayout l) async {
    try {
      final d = await _docs0();
      return PagStore.hit(d!, bookId, PagStore.fingerprint(l));
    } catch (e) {
      AppLog.add('分页档状态读取失败 书#$bookId: $e', level: LhLevel.warn);
      return false;
    }
  }

  /// 单章分片读；无档/指纹不符/该章未排＝null（调用方实算）。
  Future<PagChapter?> loadPagChapter(
    String bookId,
    ReaderLayout l,
    int ci,
  ) async {
    try {
      final d = await _docs0();
      return PagStore.loadChapter(d!, bookId, PagStore.fingerprint(l), ci);
    } catch (e) {
      AppLog.add('分页分片读取失败 书#$bookId: $e', level: LhLevel.warn);
      return null;
    }
  }

  /// 单章分片写（后台续算与翻页实算共用；指纹变了整档重置）。
  Future<void> savePagChapter(
    String bookId,
    ReaderLayout l,
    int ci,
    PagChapter chapter,
    int chapterCount,
  ) async {
    try {
      final d = await _docs0();
      await PagStore.saveChapter(
        d!, bookId, PagStore.fingerprint(l), ci, chapter, chapterCount,
      );
    } catch (e) {
      AppLog.add('分页分片写入失败 书#$bookId: $e', level: LhLevel.warn);
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
