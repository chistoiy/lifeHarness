import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/book.dart';
import '../presentation/reader_pager.dart';
import 'epub_doc.dart';
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

  static const tableVersion = 1;

  /// 外观 cfg + 视口指纹（reader_pager.ReaderLayout 全字段参与）。
  static String fingerprint(ReaderLayout l) =>
      '${l.width.round()}x${l.height.round()}|fs${l.fs}|lh${l.lh}|ls${l.ls}'
      '|mar${l.mar}|fnt${l.font}';

  static String dirPath(String docsPath) => p.join(docsPath, 'epub_pag');

  static File fileFor(String docsPath, String bookId) =>
      File(p.join(dirPath(docsPath), '$bookId.json'));

  /// 读取与 [fp] 匹配的分页表；无表/坏表/指纹不符返回 null（调用方实算）。
  static Future<BookPagination?> load(String docsPath, String bookId, String fp) async {
    final f = fileFor(docsPath, bookId);
    if (!await f.exists()) return null;
    try {
      final v = jsonDecode(await f.readAsString());
      if (v is! Map || v['fp'] != fp || v['v'] != tableVersion) return null;
      final per = v['per'];
      if (per is! List) return null;
      return BookPagination.fromTable([
        for (final ch in per)
          [
            for (final pg in ch as List)
              [for (final i in pg as List) (i as num).toInt()],
          ],
      ]);
    } catch (_) {
      return null;
    }
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
        'per': pag.perChapter,
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

// ---------- 预载文档缓存（秒进） ----------

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
    Future<void> Function()? pump,
  }) : _pump = pump ?? _defaultPump;

  final ReadRepository repo;

  /// 落盘根目录（应用 docs）；widget 测试注入临时目录，不碰真实 path_provider。
  String? docsPath;

  /// 测试注入：替换真实解析（同 pickHook 惯例；FakeAsync 下禁真 IO）。
  final Future<EpubDoc> Function(String path)? parseOverride;

  final Future<void> Function() _pump;

  final Map<String, PreloadInfo> _info = {};
  final Set<String> _running = {};
  final EpubDocCache docs = EpubDocCache();

  PreloadInfo? info(String bookId) => _info[bookId];

  /// 预载到终态（rdy/失败回退）时回调——provider 用它 bump readTick 重取书籍。
  void Function(String bookId)? onBookSettled;

  static Future<void> _defaultPump() =>
      Future.delayed(const Duration(milliseconds: 8));

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
      // ① 解析（懒归档：open 只读中央目录，文本逐章解压、图片零驻留）
      final doc = await (parseOverride ??
              ((path) async => EpubDoc.openFile(path)))(ep.path);
      docs.put(b.id, doc);
      await _mark(b, EpubRef.stPreload, 45);
      // ② 全书分页实算（TextPainter 必须主 isolate；逐章分片让出 UI）
      final per = <List<List<int>>>[];
      final chs = doc.chapters;
      for (var i = 0; i < chs.length; i++) {
        per.add(EpubPager.layoutChapter(chs[i].paras, layout));
        if (i % 6 == 5) {
          await _mark(b, EpubRef.stPreload, 45 + ((i + 1) * 50 ~/ chs.length));
          await _pump();
        }
      }
      // ③ 分页表落盘 + 就绪
      await PagStore.save(docs0!, b.id, PagStore.fingerprint(layout), BookPagination.fromTable(per));
      await _mark(b, EpubRef.stReady, 100);
      onBookSettled?.call(b.id);
    } catch (e) {
      _info[b.id] = PreloadInfo(pr: 0, error: '$e');
      // 解析失败回 rdy 态不阻塞书架（进阅读时再报错给原因）；保留进度字段清零。
      try {
        await _mark(b, EpubRef.stReady, 0, notify: false);
      } catch (_) {}
      onBookSettled?.call(b.id);
      if (kDebugMode) debugPrint('preload fail ${b.id}: $e');
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

  /// 指纹命中的落盘分页表（秒进）；无表/坏表/指纹不符/目录不可用＝null（调用方实算）。
  Future<BookPagination?> loadPag(String bookId, ReaderLayout l) async {
    try {
      final d = await _docs0();
      return PagStore.load(d!, bookId, PagStore.fingerprint(l));
    } catch (e) {
      if (kDebugMode) debugPrint('loadPag fail $bookId: $e');
      return null;
    }
  }

  Future<void> savePag(String bookId, ReaderLayout l, BookPagination pag) async {
    try {
      final d = await _docs0();
      await PagStore.save(d!, bookId, PagStore.fingerprint(l), pag);
    } catch (e) {
      if (kDebugMode) debugPrint('savePag fail $bookId: $e');
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

  /// 约可释放字节数＝私有副本 + 封面衍生 + 分页表（源文件不计、绝不删）。
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
    sum += await PagStore.sizeOf(await _docs(), b.id);
    return sum;
  }

  /// 清理：回收三类缓存文件；记录/书摘划线/计时/进度/外观全保留；原文件不动。
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
    await PagStore.remove(docs0, b.id);
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
