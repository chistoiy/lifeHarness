import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/ai/ai_providers.dart' show aiServiceProvider;
import '../../../core/ai/ai_service.dart' show AiDenied;
import '../data/epub_doc.dart';
import '../domain/book.dart';
import '../domain/book_quote.dart';
import '../domain/reader_cfg.dart';
import 'read_providers.dart';
import 'read_sheets.dart' show readToast, showQuoteEditPage;
import 'reader_appearance_sheet.dart';
import 'reader_pager.dart';
import 'reader_search_page.dart';
import 'reader_toc_drawer.dart';

/// 阅读位置（brPos[bid]：{ci,pg} + 书签 bm=[ci,pg,ts]）。
class _Pos {
  _Pos({this.ci = 0, this.pg = 0, this.bm});
  int ci, pg;
  List<int>? bm;

  factory _Pos.decode(String? raw) {
    try {
      final v = raw == null ? null : jsonDecode(raw) as Map<String, dynamic>?;
      if (v == null) return _Pos();
      return _Pos(
        ci: (v['ci'] as num?)?.toInt() ?? 0,
        pg: (v['pg'] as num?)?.toInt() ?? 0,
        bm: (v['bm'] as List?)?.map((e) => (e as num).toInt()).toList(),
      );
    } catch (_) {
      return _Pos();
    }
  }

  String encode() => jsonEncode({'ci': ci, 'pg': pg, if (bm != null) 'bm': bm});
}

/// brSync 关时的划线暂存行（原型 BR_LOCAL_HL · 全量存 kv `reader.hl`）。
/// 与 book_quotes 同构语义：cf 章段区间 + 颜色分类 tg + 稳定 rid。
class _LocalHl {
  const _LocalHl({
    required this.id,
    required this.bookId,
    required this.cf,
    required this.tg,
  });

  final String id;
  final String bookId;
  final QuoteCf cf;
  final String tg;

  Map<String, Object?> toMap() => {
    'id': id,
    'b': bookId,
    'c': cf.c,
    'p0': cf.p0,
    'p1': cf.p1,
    'tg': tg,
  };

  static _LocalHl? fromMap(Map<Object?, Object?> m) {
    final c = m['c'], p0 = m['p0'], p1 = m['p1'];
    if (c is! num || p0 is! num || p1 is! num) return null;
    return _LocalHl(
      id: '${m['id']}',
      bookId: '${m['b']}',
      cf: QuoteCf(c: c.toInt(), p0: p0.toInt(), p1: p1.toInt()),
      tg: '${m['tg']}',
    );
  }

  static List<_LocalHl> decodeAll(String? raw) {
    try {
      final v = raw == null ? null : jsonDecode(raw) as List?;
      if (v == null) return const [];
      return [
        for (final e in v.whereType<Map<Object?, Object?>>())
          ?_LocalHl.fromMap(e),
      ];
    } catch (_) {
      return const [];
    }
  }

  static String encodeAll(List<_LocalHl> l) =>
      jsonEncode([for (final x in l) x.toMap()]);
}

/// 阅读主屏（V1.50 · 事实源 `#p-readerPage` BR-2 + V1.51 目录侧边抽屉）。
///
/// 批2 全量：分页引擎实算（字号/行距/字距/边距即时重排页数）、翻页⇄滚动双模式、
/// 左右滑动/边缘点按翻页、CFI 位置记忆恢复、全书进度条拖动定位、目录侧边抽屉三态、
/// 图片放大保存、内链直跳/外链三策略、命中「上/下一处」、进页自动计时/退出结算。
/// 批3 划词菜单与同库、批4 外观面板/逐书记忆/TTS/自动翻页/常亮在其上接入。
class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  Book? _book;
  EpubDoc? _doc;
  String? _err;
  bool _ownTimer = false;

  // 批4 外观：全局 cfg + 逐书补丁合并生效（原型 brSt(bid)）。
  ReaderCfg _cfg = ReaderCfg.defaults;
  ReaderCfg _global = ReaderCfg.defaults;
  Map<String, dynamic> _bookPatch = const {};
  Timer? _autoT;
  bool _brightOwned = false; // 本页启用过常亮才负责关闭
  _Pos _pos = _Pos();
  BookPagination? _pag;
  Size _viewport = Size.zero;

  // chrome / 反馈
  bool _chrome = false;
  String? _flash;
  Timer? _flashT;
  int _sessSecs = 0;
  Timer? _clock;
  DateTime? _t0;

  // 抽屉
  bool _drawerOpen = false;
  final TocDrawerState _drState = TocDrawerState();

  // 命中导航（搜本书/全书检索共用）
  List<({int ci, int pi, String text})> _hits = const [];
  int _hitI = -1;
  String _hitQ = '';
  ({int ci, int pg, int pi})? _hitMark; // 当前高亮段

  // 批3 划词/划线（原型 brV.sel + BS_QUOTES.cf + BR_LOCAL_HL）。
  ({int ci, int p0, int p1})? _sel; // 同章段落闭区间
  bool _hlPop = false; // 色板展开
  bool _brSync = true; // read.brSync：划线自动存为书摘
  List<BookQuote> _hlQuotes = const []; // 本书已入库划线行（cf≠null）
  List<_LocalHl> _localHl = const []; // brSync 关时暂存

  final _scrollCtrl = ScrollController();

  String get _clockText {
    final m = _sessSecs ~/ 60;
    final s = _sessSecs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _clock?.cancel();
    _flashT?.cancel();
    _autoT?.cancel();
    if (_brightOwned) {
      _brightOwned = false;
      unawaited(_wake(false));
    }
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final repo = ref.read(readRepositoryProvider);
    final b = await repo.bookById(widget.bookId);
    if (!mounted) return;
    if (b == null || !b.local || b.epub == null) {
      setState(() => _err = '这本书没有可用的本地 EPUB 文件');
      return;
    }
    setState(() => _book = b);
    // 批3.5 入口守卫（防御：正常路径书架/详情已拦截）：预载中不可进、
    // 已清缓存回书架走三态恢复。
    final ep = b.epub!;
    if (ep.state == EpubRef.stPreload) {
      setState(() => _err = '正在预载整本书 · 完成后可进入');
      return;
    }
    if (ep.cleared) {
      setState(() => _err = '本地副本已清理 · 回书架点封面重新载入');
      return;
    }
    // 真机修⑥：文档解析（或等书架预热）与外观/位置读取并行，
    // 冷启动重进时省掉一段串行等待。
    final svc = ref.read(epubPreloadProvider);
    final docF = () async {
      var d = svc.docs.get(b.id);
      if (d == null) {
        await svc.warming(b.id);
        d = svc.docs.get(b.id);
      }
      // 批5 秒开：无内存文档先吃排版快照（读索引+当前章＝毫秒级）；
      // 快照也没有才整本解析，且解析结果回灌快照让下次也秒开。
      d ??= await svc.snap(b);
      if (d == null) {
        d = await ref.read(epubDocLoaderProvider)(b.epub!.path);
        unawaited(svc.saveSnap(b, d));
      }
      return d;
    }();
    // 立即挂接错误：解析异常延后到 try 里再抛，避免成未处理异步错误。
    final docR = Completer<(EpubDoc?, Object?)>();
    docF.then(
      (d) => docR.complete((d, null)),
      onError: (Object e, StackTrace _) => docR.complete((null, e)),
    );
    // 外观/位置先读，渲染即按记忆恢复（CFI 自动定位 · V1.50 口径③）。
    // 批4：全局 reader.cfg + 逐书 reader.cfg.<id> 补丁合并生效。
    final fGlobal = repo.kv('reader.cfg');
    final fPatch = repo.kv('reader.cfg.${b.id}');
    final fBright = repo.kv('read.brBright');
    final fPos = repo.kv('reader.pos.${b.id}');
    final fSync = repo.kv('read.brSync');
    final fHl = repo.kv('reader.hl');
    final fQuotes = repo.quotesOf(b.id);
    _global = ReaderCfg.decode(await fGlobal);
    _bookPatch = brDecodePatch(await fPatch);
    _cfg = ReaderCfg.mergePatch(_global, _bookPatch);
    // 设置组 read.brBright ⇄ 面板常亮（原型 rsFlip/brMoreBright 双向）。
    if (await fBright == 'true' && !_cfg.bright) {
      _cfg = _cfg.copyWith(bright: true);
    }
    _pos = _Pos.decode(await fPos);
    // 划线同库数据（批3）：同步开关 + 本书划线行 + brSync 关时暂存。
    _brSync = await fSync != 'false';
    _localHl = _LocalHl.decodeAll(await fHl);
    _hlQuotes = (await fQuotes)
        .where((q) => q.deletedAt == null && q.cf != null)
        .toList();
    if (!mounted) return;
    setState(() {});
    // 进阅读器自动开始计时；他处已在计时则沿用该计时条（原型 brV.ownT）。
    final running = await repo.runningSession();
    if (running == null) {
      await repo.startSession(b.id);
      _ownTimer = true;
    }
    _t0 = DateTime.now();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      // 时钟胶囊只在 chrome/抽屉可见时展示；平时不整页重建（大书滑动掉帧根因之一）。
      if (!mounted || _t0 == null) return;
      final secs = DateTime.now().difference(_t0!).inSeconds;
      if (_chrome || _drawerOpen) {
        setState(() => _sessSecs = secs);
      } else {
        _sessSecs = secs;
      }
    });
    try {
      // 秒进：预载缓存命中直接用（分页表也已落盘）；未命中走懒归档再开。
      final (doc0, docErr) = await docR.future;
      if (docErr != null) throw docErr;
      final doc = doc0!;
      // 现开的文档也回灌缓存（真机修⑥）：退出重进不再二次整本解析。
      svc.docs.put(b.id, doc);
      if (!mounted) return;
      setState(() => _doc = doc);
      // 首帧已定 _viewport 时 LayoutBuilder 不会再触发；此处直接建分页。
      _rebuildPag();
      if (_pag == null) _clampPos();
      // 批4：常亮与自动翻页按生效外观接入。
      _syncBright();
      _syncAuto();
    } on EpubFormatException catch (e) {
      if (mounted) setState(() => _err = e.reason);
    } catch (_) {
      if (mounted) setState(() => _err = '文件无法读取');
    }
  }

  void _clampPos() {
    final doc = _doc;
    if (doc == null || doc.chapters.isEmpty) return;
    _pos.ci = _pos.ci.clamp(0, doc.chapters.length - 1);
    if (_cfg.mode == 'page') {
      final n = _pag?.chapterPages(_pos.ci) ?? 1;
      _pos.pg = _pos.pg.clamp(0, n - 1);
    }
  }

  String get _posKey => 'reader.pos.${widget.bookId}';

  void _savePos() {
    unawaited(ref.read(readRepositoryProvider).setKv(_posKey, _pos.encode()));
  }

  /// 结算：本页开启的计时才由本页结束；进度按全局页百分比写回书籍记录。
  void _leave() {
    _clock?.cancel();
    if (!_ownTimer) return;
    final repo = ref.read(readRepositoryProvider);
    final doc = _doc;
    final pag = _pag;
    unawaited(repo.endSession(widget.bookId));
    if (doc != null && pag != null && _book != null) {
      final pct = pag.pct(_pos.ci, _pos.pg);
      final b = _book!;
      final pages = b.pages > 0 ? b.pages : pag.total;
      unawaited(
        repo.saveProgress(
          widget.bookId,
          Book.kWayPage,
          (pages * pct / 100).round().toDouble(),
          chapterTitle: doc.chapters[_pos.ci].title,
        ),
      );
    }
    ref.read(readTickProvider.notifier).state++;
  }

  // ---------- 翻页/定位 ----------

  void _flip(int d) {
    final doc = _doc;
    final pag = _pag;
    if (doc == null || pag == null) return;
    if (_cfg.mode == 'scroll') {
      // 滚动模式：翻≈一屏。
      final vp = _viewport.height - 120;
      _scrollCtrl.jumpTo(
        (_scrollCtrl.hasClients ? _scrollCtrl.offset : 0) + d * vp,
      );
      return;
    }
    final n = pag.chapterPages(_pos.ci);
    final np = _pos.pg + d;
    if (np >= n) {
      if (_pos.ci >= doc.chapters.length - 1) {
        _markFinished();
        return;
      }
      setState(() {
        _pos.ci++;
        _pos.pg = 0;
        _flash = doc.chapters[_pos.ci].title;
      });
    } else if (np < 0) {
      if (_pos.ci == 0) {
        setState(() => _pos.pg = 0);
        _savePos();
        return;
      }
      setState(() {
        _pos.ci--;
        _pos.pg = pag.chapterPages(_pos.ci) - 1;
        _flash = doc.chapters[_pos.ci].title;
      });
    } else {
      setState(() => _pos.pg = np);
    }
    _savePos();
    _flashT?.cancel();
    _flashT = Timer(const Duration(milliseconds: 1300), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  /// 最后一夜读完：标记已读并 toast（原型 brFlip 尾页口径）。
  void _markFinished() {
    final doc = _doc;
    final pag = _pag;
    if (doc == null || pag == null) return;
    setState(() {
      _pos.pg = pag.chapterPages(_pos.ci) - 1;
    });
    _savePos();
    unawaited(
      ref.read(readRepositoryProvider).setBookState(widget.bookId, Book.kStateDone),
    );
    ref.read(readTickProvider.notifier).state++;
    if (mounted) {
      readToast(context, '已读完最后一页 · 《${_book?.title ?? ''}》标记为已读');
    }
  }

  void _gotoChapter(int ci) {
    setState(() {
      _pos.ci = ci;
      _pos.pg = 0;
      _drawerOpen = false;
      _flash = _doc?.chapters[ci].title;
    });
    _savePos();
    _flashT?.cancel();
    _flashT = Timer(const Duration(milliseconds: 1300), () {
      if (mounted) setState(() => _flash = null);
    });
    if (_cfg.mode == 'scroll') _scrollToPara(ci, 0);
  }

  /// 全书全局页定位（进度条 seek · brSeek 同语义）。
  void _seek(int g) {
    final pag = _pag;
    if (pag == null) return;
    final p = pag.gPosTo(g);
    setState(() {
      _pos.ci = p.ci;
      _pos.pg = p.pg;
    });
    _savePos();
  }

  void _scrollToPara(int ci, int pi) {
    // 滚动模式：按段落序号近似定位（每段约 5 行容量下限，误差可接受）。
    final doc = _doc;
    if (doc == null || !_scrollCtrl.hasClients) return;
    var idx = 0;
    for (var c = 0; c < ci; c++) {
      idx += doc.chapters[c].paras.length + 1;
    }
    idx += 1 + pi;
    final est = (idx * _cfg.fs * _cfg.lh * 3).clamp(
      0.0,
      _scrollCtrl.position.maxScrollExtent,
    );
    _scrollCtrl.jumpTo(est.toDouble());
  }

  // ---------- 批3 划词/划线（原型 brSelect / brAddHl / brDelHl · L5 同库） ----------

  static const _kBrDict = {
    '锚定': ('ān dìng', '动', '在判断中过度依赖最先获得的数值。'),
    '折扣': ('zhé kòu', '名', '未来奖励在当下估值中的缩水。'),
    '联想': ('lián xiǎng', '名', '一个概念激活后向评价、情绪、动作扩散的链条。'),
  };

  String get _selTxt {
    final sel = _sel;
    final doc = _doc;
    if (sel == null || doc == null) return '';
    final ps = doc.chapters[sel.ci].paras;
    return [
      for (var i = sel.p0; i <= sel.p1 && i < ps.length; i++) ps[i].text,
    ].join('\n');
  }

  /// 真机反馈（2026-09-28）：中区点按几乎必命中段落识别器，工具条永远关不掉
  /// ——同段再点＝收起；点其它段落＝移动选区（原型 brSelHide 语义的移动端补齐）。
  void _selectPara(int ci, int pi) => setState(() {
    final s = _sel;
    if (s != null && s.ci == ci && s.p0 == pi && s.p1 == pi) {
      _sel = null;
      _hlPop = false;
      return;
    }
    _sel = (ci: ci, p0: pi, p1: pi);
    _hlPop = false;
  });

  void _growSel(int d) {
    final sel = _sel;
    final doc = _doc;
    if (sel == null || doc == null) return;
    final n = doc.chapters[sel.ci].paras.length;
    setState(() {
      _sel = d > 0
          ? (ci: sel.ci, p0: sel.p0, p1: (sel.p1 + 1).clamp(0, n - 1))
          : (ci: sel.ci, p0: (sel.p0 - 1).clamp(0, n - 1), p1: sel.p1);
      _hlPop = false;
    });
  }

  void _clearSel() => setState(() {
    _sel = null;
    _hlPop = false;
  });

  /// 段生效划线（原型 brHlAt：库内行优先，多条取最后；回落暂存行）。
  ({String tg, Color c, bool hasThought})? _hlAt(int ci, int pi) {
    ({String tg, Color c, bool hasThought})? hit;
    for (final h in _localHl) {
      if (h.bookId == widget.bookId && h.cf.covers(ci, pi)) {
        hit = (
          tg: h.tg,
          c: Color(0xFF000000 | (BookQuote.hexToInt(BookQuote.colorHex[h.tg]) ?? 0xFDE047)),
          hasThought: false,
        );
      }
    }
    for (final q in _hlQuotes) {
      if (q.cf!.covers(ci, pi)) {
        hit = (
          tg: q.tag,
          c: Color(0xFF000000 | q.colorInt),
          hasThought: (q.thought ?? '').isNotEmpty,
        );
      }
    }
    return hit;
  }

  Future<void> _reloadHls() async {
    final repo = ref.read(readRepositoryProvider);
    _brSync = (await repo.kv('read.brSync')) != 'false';
    _hlQuotes = (await repo.quotesOf(widget.bookId))
        .where((q) => q.deletedAt == null && q.cf != null)
        .toList(growable: false);
    _localHl = _LocalHl.decodeAll(await repo.kv('reader.hl'));
    if (mounted) setState(() {});
  }

  Future<void> _addHl(String tg) async {
    final sel = _sel;
    final doc = _doc;
    final pag = _pag;
    final body = _selTxt;
    if (sel == null || doc == null || body.isEmpty) return;
    final repo = ref.read(readRepositoryProvider);
    final cf = QuoteCf(c: sel.ci, p0: sel.p0, p1: sel.p1);
    final rid = 'r${DateTime.now().millisecondsSinceEpoch}';
    if (_brSync) {
      // 硬约束①：划线即一条「划线」型书摘直接进既有摘录表，携带 cf+rid。
      final now = DateTime.now().millisecondsSinceEpoch;
      await repo.addQuote(
        BookQuote(
          bookId: widget.bookId,
          kind: BookQuote.kKindMark,
          tag: tg,
          body: body,
          chapter: doc.chapters[sel.ci].title,
          page: pag == null ? null : pag.gPos(sel.ci, 0) + 1,
          cf: cf,
          rid: rid,
          origin: '阅读器',
          createdAt: now,
          updatedAt: now,
        ),
      );
    } else {
      // brSync 关：暂存本地全量 kv，开库后由渲染层按 cf 生效（原型 BR_LOCAL_HL）。
      final next = [
        ..._localHl,
        _LocalHl(id: rid, bookId: widget.bookId, cf: cf, tg: tg),
      ];
      await repo.setKv('reader.hl', _LocalHl.encodeAll(next));
    }
    await _reloadHls();
    if (!mounted) return;
    setState(() {
      _sel = null;
      _hlPop = false;
    });
    ref.read(readTickProvider.notifier).state++;
    _showFlash('已划线（$tg）· 同步进本书书摘');
    readToast(context, '高亮即一条划线书摘 · 笔记库可查（联动 L5）');
  }

  Future<void> _delHl() async {
    final sel = _sel;
    if (sel == null) return;
    final repo = ref.read(readRepositoryProvider);
    var n = 0;
    // 删除互清：删划线＝软删对应书摘行（笔记库同款可撤销语义）。
    for (final q in _hlQuotes) {
      final cf = q.cf!;
      if (q.id != null && cf.c == sel.ci && cf.p0 == sel.p0 && cf.p1 == sel.p1) {
        await repo.softDeleteQuote(q.id!);
        n++;
      }
    }
    final keep = _localHl.where((h) {
      final cf = h.cf;
      return !(h.bookId == widget.bookId && cf.c == sel.ci && cf.p0 == sel.p0 && cf.p1 == sel.p1);
    }).toList();
    if (keep.length != _localHl.length) {
      n += _localHl.length - keep.length;
      await repo.setKv('reader.hl', _LocalHl.encodeAll(keep));
    }
    await _reloadHls();
    if (!mounted) return;
    setState(() => _sel = null);
    ref.read(readTickProvider.notifier).state++;
    readToast(context, n > 0 ? '已删除划线（书摘同步移除）' : '此处没有划线可删');
  }

  void _actCopy() {
    final t = _selTxt;
    if (t.isEmpty) return;
    Clipboard.setData(ClipboardData(text: t));
    _clearSel();
    readToast(context, '已复制 ${t.length} 字');
  }

  void _actShare() {
    final sel = _sel;
    final doc = _doc;
    if (sel == null || doc == null) return;
    final txt =
        '$_selTxt\n\n——《${_book?.title ?? ''}》${doc.chapters[sel.ci].title} · ${_cfi(sel.ci, sel.p0)}';
    Clipboard.setData(ClipboardData(text: txt));
    _clearSel();
    readToast(context, '分享文本已复制 · 含出处引用');
  }

  void _actQuote(bool thought) {
    final sel = _sel;
    final doc = _doc;
    final pag = _pag;
    if (sel == null || doc == null) return;
    final body = _selTxt;
    final ch = doc.chapters[sel.ci].title;
    final pg = pag == null ? null : pag.gPos(sel.ci, 0) + 1;
    _clearSel();
    showQuoteEditPage(
      context,
      ref,
      bookId: widget.bookId,
      preBody: body,
      preChapter: ch,
      prePage: pg,
      focusThought: thought,
    );
  }

  /// 词典取词（原型 BR_DICT：去空白 ≤4 字 · 互含模糊匹配 · 未收录回退）。
  void _actDict() {
    final sel = _sel;
    if (sel == null) return;
    final w = _selTxt.replaceAll(RegExp(r'\s'), '');
    final word = w.length > 4 ? w.substring(0, 4) : w;
    String? hitKey;
    for (final k in _kBrDict.keys) {
      if (word.contains(k) || k.contains(word)) {
        hitKey = k;
        break;
      }
    }
    final e = hitKey == null ? null : _kBrDict[hitKey];
    final bodyText = _selTxt;
    _clearSel();
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sc) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
          child: Column(
            key: const ValueKey('sheetBrDict'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                word.isEmpty ? '选词' : word,
                key: const ValueKey('brDcWord'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                e == null ? '— · 短语' : '${e.$1} · ${e.$2}',
                key: const ValueKey('brDcPh'),
                style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 10),
              Text(
                e?.$3 ?? '（本地词典未收录该词 · 可下载扩展词库）',
                style: const TextStyle(fontSize: 12.5, height: 1.6),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sc).pop(),
                      child: const Text('关闭'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('brDcToQuote'),
                      onPressed: () {
                        Navigator.of(sc).pop();
                        showQuoteEditPage(
                          context,
                          ref,
                          bookId: widget.bookId,
                          preBody: bodyText,
                          preThought:
                              '【$word】${e?.$3 ?? '释义见本地词典包'}',
                          focusThought: true,
                        );
                      },
                      child: const Text('释义填入想法'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// AI 解读：三重门控通过后调 read.quote_insight（摘录感想生成）。
  void _actAi() {
    final sel = _sel;
    final doc = _doc;
    if (sel == null || doc == null) return;
    final quote = _selTxt;
    final book = _book?.title ?? doc.title;
    _clearSel();
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sc) => _BrAiSheet(
        bookId: widget.bookId,
        quote: quote,
        book: book,
        onToQuote: (insight) {
          Navigator.of(sc).pop();
          showQuoteEditPage(
            context,
            ref,
            bookId: widget.bookId,
            preBody: quote.length > 120 ? quote.substring(0, 120) : quote,
            preThought: '【AI 解读】$insight',
            focusThought: true,
          );
        },
      ),
    );
  }

  // ---------- 外观（批4：A± 逐书 · 主题/模式全局 · 草稿制面板 · 常亮 · 自动翻页） ----------

  Future<void> _persistGlobal() async {
    await ref.read(readRepositoryProvider).setKv('reader.cfg', _global.encode());
  }

  Future<void> _persistPatch([Map<String, dynamic> add = const {}]) async {
    _bookPatch = {..._bookPatch, ...add};
    await ref
        .read(readRepositoryProvider)
        .setKv('reader.cfg.${widget.bookId}', jsonEncode(_bookPatch));
  }

  void _applyMerged() => _cfg = ReaderCfg.mergePatch(_global, _bookPatch);

  /// 原型 brFsNudge：字号写逐书补丁（只覆盖 fs）。
  void _nudgeFont(int d) {
    final fs = (_cfg.fs + d).clamp(14.0, 30.0);
    setState(() => _cfg = _cfg.copyWith(fs: fs));
    _rebuildPagChapterFirst();
    unawaited(_persistPatch({'fs': fs}));
  }

  /// 原型 brThemeCycle：主题循环写全局（custom 回落日间起步）。
  void _cycleTheme() {
    final i = kBrThemeOrder.indexOf(_cfg.theme);
    final next = kBrThemeOrder[i < 0 ? 0 : (i + 1) % kBrThemeOrder.length];
    final (bg, fg) = (kBrThemes[next]!.$2, kBrThemes[next]!.$3);
    setState(() {
      _global = _global.copyWith(
        theme: next,
        bg: '#${(bg.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
        fg: '#${(fg.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
      );
      _applyMerged();
    });
    unawaited(_persistGlobal());
    _rebuildPagChapterFirst();
    _showFlash('主题 · ${kBrThemes[next]!.$1}');
  }

  void _toggleMode() {
    setState(() {
      _global = _global.copyWith(
        mode: _cfg.mode == 'page' ? 'scroll' : 'page',
      );
      _applyMerged();
    });
    _savePos();
    unawaited(_persistGlobal());
    _rebuildPag();
    _syncAuto();
  }

  /// 外观钮 → 草稿制面板（原型 sheetBrAppearance）。
  void _openAppearance() {
    showReaderAppearance(
      context,
      current: _cfg,
      onSave: (draft, scopeBook) async {
        setState(() {
          if (scopeBook) {
            _bookPatch = draft.toMap();
            _applyMerged();
          } else {
            _global = draft;
            _applyMerged();
          }
        });
        if (scopeBook) {
          unawaited(_persistPatch());
        } else {
          unawaited(_persistGlobal());
        }
        // 面板常亮回写设置组键（原型 brMoreBright → BS_SET.brBright）。
        unawaited(
          ref
              .read(readRepositoryProvider)
              .setKv('read.brBright', draft.bright ? 'true' : 'false'),
        );
        _rebuildPag();
        _syncBright();
        _syncAuto();
        readToast(
          context,
          scopeBook ? '本书外观已保存 · 逐书独立记忆' : '全局默认已更新 · 未覆写的书即时生效',
        );
      },
    );
  }

  /// 常亮：本页启用过才在退出时关闭（不打扰其它模块的常亮策略）；
  /// 插件不可用（测试环境/桌面）静默降级，只保留设置值。
  Future<void> _wake(bool on) async {
    try {
      if (on) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {}
  }

  void _syncBright() {
    if (_cfg.bright) {
      _brightOwned = true;
      unawaited(_wake(true));
    } else if (_brightOwned) {
      _brightOwned = false;
      unawaited(_wake(false));
    }
  }

  /// 自动翻页定时器（原型 brAutoStart：选区/抽屉打开时跳过；滚动模式逐屏下滚）。
  void _syncAuto() {
    _autoT?.cancel();
    _autoT = null;
    if (!_cfg.auto || _doc == null) return;
    _autoT = Timer.periodic(Duration(seconds: _cfg.autoSecs.clamp(3, 60)), (_) {
      if (!mounted || _sel != null || _drawerOpen || _doc == null) return;
      if (_cfg.mode == 'scroll') {
        final h = _viewport.height - 60;
        final cur = _scrollCtrl.hasClients ? _scrollCtrl.offset : 0.0;
        unawaited(
          _scrollCtrl.hasClients
              ? _scrollCtrl.animateTo(
                  cur + h,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                )
              : Future<void>.value(),
        );
      } else {
        _flip(1);
      }
    });
  }

  int _pagGen = 0;

  void _rebuildPag() {
    final doc = _doc;
    if (doc == null || _viewport.width <= 0) return;
    final gen = ++_pagGen;
    final l = _layout();
    unawaited(_applyPag(doc, l, gen));
  }

  /// 分页表优先（批3.5 指纹命中＝秒进）；未命中分片实算（真机修⑤：
  /// 2409 章大全集整本同步实算＝改字体后卡死数十秒；当前章先行渲染，
  /// 其余逐 3 章让出 UI 后台补齐后落盘）。
  /// 真机修⑥：表加载（读文件+compute 解码几万页）期间不再空转圈——
  /// 先同步铺「当前章实算+其余章占位」上屏，表命中后整体换入（同指纹不跳版）。
  Future<void> _applyPag(EpubDoc doc, ReaderLayout l, int gen) async {
    final svc = ref.read(epubPreloadProvider);
    final ci0 = _pos.ci.clamp(0, doc.chapters.length - 1);
    if (_pag == null) {
      final fresh = BookPagination.fromTable([
        for (var i = 0; i < doc.chapters.length; i++)
          i == ci0
              ? EpubPager.layoutChapter(doc.chapters[i].paras, l)
              : const [<int>[]],
      ]);
      setState(() {
        _pag = fresh;
        _clampPos();
      });
      if (svc.docsPath == null) {
        unawaited(_fillPag(doc, l, fresh, gen, skipCi: ci0));
        return;
      }
    }
    BookPagination? pag;
    if (svc.docsPath != null) {
      try {
        pag = await svc.loadPag(widget.bookId, l);
      } catch (_) {}
      if (!mounted || gen != _pagGen) return;
    }
    if (pag != null) {
      setState(() {
        _pag = pag;
        _clampPos();
      });
      return;
    }
    // 表未命中：继续用已上屏的占位表分片补齐。
    unawaited(_fillPag(doc, l, _pag!, gen, skipCi: ci0));
  }

  /// 逐章分片实算全书分页（当前章优先），完成后落盘。
  Future<void> _fillPag(
    EpubDoc doc,
    ReaderLayout l,
    BookPagination pag,
    int gen, {
    int skipCi = -1,
  }) async {
    if (skipCi >= 0 && skipCi < doc.chapters.length) {
      pag.perChapter[skipCi] = EpubPager.layoutChapter(
        doc.chapters[skipCi].paras,
        l,
      );
      if (mounted && gen == _pagGen) setState(_clampPos);
    }
    for (var i = 0; i < doc.chapters.length; i++) {
      if (i == skipCi) continue;
      if (!mounted || gen != _pagGen) return;
      pag.perChapter[i] = EpubPager.layoutChapter(doc.chapters[i].paras, l);
      if (i % 3 == 2) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (!mounted || gen != _pagGen) return;
    setState(_clampPos);
    final svc = ref.read(epubPreloadProvider);
    if (svc.docsPath != null) unawaited(svc.savePag(widget.bookId, l, pag));
  }

  /// 外观变化增量重排（批3.5 口径：当前章毫秒级即时，其余章后台补齐后落盘）。
  void _rebuildPagChapterFirst() {
    final doc = _doc;
    final pag = _pag;
    if (doc == null || pag == null || _viewport.width <= 0) {
      _rebuildPag();
      return;
    }
    final l = _layout();
    final ci = _pos.ci.clamp(0, doc.chapters.length - 1);
    final gen = ++_pagGen;
    unawaited(_fillPag(doc, l, pag, gen, skipCi: ci));
  }

  ReaderLayout _layout() => ReaderLayout(
    width: _viewport.width,
    height: _viewport.height,
    fs: _cfg.fs,
    lh: _cfg.lh,
    ls: _cfg.ls,
    mar: _cfg.mar,
    font: _cfg.font,
  );

  // ---------- 链接/图片 ----------

  /// 内链直跳：目标 href 命中 spine 章即跳章（原型 brGotoCh 链）。
  void _onLink(EpubLink l) {
    if (!l.external) {
      final doc = _doc;
      if (doc == null) return;
      final ci = doc.chapters.indexWhere((c) => c.href == l.href);
      if (ci >= 0) {
        _gotoChapter(ci);
      } else {
        _showFlash('目标章节不在正文流');
      }
      return;
    }
    _onExtLink(l.href);
  }

  Future<void> _onExtLink(String url) async {
    final repo = ref.read(readRepositoryProvider);
    final mode = await repo.kv('read.brLink') ?? '询问';
    if (!mounted) return;
    if (mode == '禁止') {
      _showFlash('外链已被禁止 · 可在阅读设置改为询问/允许');
      return;
    }
    if (mode == '允许') {
      _openUrl(url);
      return;
    }
    // 询问：sheetBrLink 半屏（原型：即将离开阅读器 + URL 卡 + 策略提示 +
    // 取消/允许一次 双钮）。
    final cs = Theme.of(context).colorScheme;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sc) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
          child: Column(
            key: const ValueKey('sheetBrLink'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '即将离开阅读器',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Container(
                key: const ValueKey('brLkUrl'),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(url, style: const TextStyle(fontSize: 11, height: 1.6)),
              ),
              const SizedBox(height: 6),
              Text(
                '策略可在「阅读设置 · 本地阅读器」改为 禁止 / 询问 / 允许',
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sc).pop(false),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('brLkOpen'),
                      onPressed: () => Navigator.of(sc).pop(true),
                      child: const Text('允许一次'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true) _openUrl(url);
  }

  Future<void> _openUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) _showFlash('没有可打开该链接的应用');
    }
  }

  void _openImage(EpubPara para) {
    final bytes = _doc?.imageBytes(para.imgSrc);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black,
      isScrollControlled: true,
      builder: (sc) => SafeArea(
        child: SizedBox(
          key: const ValueKey('sheetBrImg'),
          height: MediaQuery.sizeOf(sc).height * .8,
          child: Column(
            children: [
              Expanded(
                child: InteractiveViewer(
                  maxScale: 4,
                  child: Center(
                    child: bytes == null
                        ? const Text('（缺图）',
                            style: TextStyle(color: Colors.white54))
                        : Image.memory(
                            Uint8List.fromList(bytes),
                            fit: BoxFit.contain,
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  para.alt.isEmpty ? '插图' : para.alt,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white70,
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    key: const ValueKey('brImgSave'),
                    onPressed: () async {
                      if (bytes == null) return;
                      final base = await getApplicationDocumentsDirectory();
                      final dir = Directory('${base.path}${Platform.pathSeparator}share')
                        ..createSync(recursive: true);
                      final ext = p.extension(para.imgSrc).replaceFirst('.', '').toLowerCase();
                      final suffix = const {'jpg', 'jpeg', 'png', 'gif', 'webp'}.contains(ext) ? '.$ext' : '.png';
                      final out = File(
                        '${dir.path}${Platform.pathSeparator}epub_img_'
                        '${DateTime.now().millisecondsSinceEpoch}$suffix',
                      );
                      out.writeAsBytesSync(bytes);
                      if (sc.mounted) Navigator.of(sc).pop();
                    },
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: const Text('保存'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(sc).pop(),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFlash(String msg) {
    setState(() => _flash = msg);
    _flashT?.cancel();
    _flashT = Timer(const Duration(milliseconds: 1300), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  // ---------- 命中导航 ----------

  /// 全书检索整页（顶栏放大镜）：pop 回结果即挂上/下一处并跳原文。
  Future<void> _openSearch() async {
    final doc = _doc;
    if (doc == null) return;
    final r = await Navigator.of(context).push(
      MaterialPageRoute<BrSearchResult>(
        builder: (_) => ReaderSearchPage(
          doc: doc,
          title: _book?.title ?? doc.title,
        ),
      ),
    );
    if (r == null || !mounted) return;
    setState(() {
      _hits = r.hits;
      _hitQ = r.q;
      _chrome = true;
    });
    _jumpHit(r.idx);
  }

  void _jumpHit(int i) {
    if (i < 0 || i >= _hits.length) return;
    final h = _hits[i];
    final pag = _pag;
    setState(() {
      _hitI = i;
      _drawerOpen = false;
      if (_cfg.mode == 'page' && pag != null) {
        _pos.ci = h.ci;
        _pos.pg = pag.pageOfPara(h.ci, h.pi);
        _hitMark = (ci: h.ci, pg: _pos.pg, pi: h.pi);
      } else {
        _pos.ci = h.ci;
        _hitMark = (ci: h.ci, pg: 0, pi: h.pi);
      }
    });
    _savePos();
    if (_cfg.mode == 'scroll') _scrollToPara(h.ci, h.pi);
  }

  void _hitStep(int d) {
    if (_hits.isEmpty) return;
    var i = _hitI + d;
    if (i < 0) i = _hits.length - 1;
    if (i >= _hits.length) i = 0;
    _jumpHit(i);
  }

  // ---------- 构建 ----------

  @override
  Widget build(BuildContext context) {
    final th = _cfg.theme == 'custom'
        ? ('自定义', _cfg.bgColor, _cfg.textColor)
        : (kBrThemes[_cfg.theme] ?? kBrThemes['day']!);
    return PopScope(
      // 抽屉开启时返回键先收抽屉；页面真出栈才结算（原型 Escape→brTocClose）。
      canPop: !_drawerOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          setState(() => _drawerOpen = false);
          return;
        }
        _leave();
      },
      child: Scaffold(
        backgroundColor: th.$2,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // 点按分派：左/右 16% 翻页、中区收放 chrome（原型 br-zone 口径）。
          // 用单一祖先监听而非覆盖热区：正文/插图/链接等子级识别器在
          // 手势竞技场中先行加入天然优先，纯文本无识别器则落到这里。
          onTapUp: (d) {
            if (_drawerOpen || _doc == null || _err != null) return;
            final s = _viewport;
            final p = d.localPosition;
            if (p.dy < s.height * .15 || p.dy > s.height * .85) return;
            // 中区点按：有选区则先清空；无选区才切换 chrome。
            if (p.dx >= s.width * .16 && p.dx <= s.width * .84) {
              if (_sel != null) {
                _clearSel();
              } else {
                setState(() => _chrome = !_chrome);
              }
              return;
            }
            if (p.dx < s.width * .16) {
              _flip(-1);
            } else if (p.dx > s.width * .84) {
              _flip(1);
            }
          },
          onHorizontalDragEnd: (e) {
            if (_drawerOpen) return;
            final v = e.velocity.pixelsPerSecond.dx;
            final off = e.primaryVelocity ?? 0;
            if (off < -150 || (v < 0 && v < -0.4)) {
              _flip(1);
            } else if (off > 150 || (v > 0 && v > 0.4)) {
              _flip(-1);
            }
          },
          child: LayoutBuilder(
            builder: (_, box) {
              final size = Size(box.maxWidth, box.maxHeight);
              if (size != _viewport) {
                _viewport = size;
                _rebuildPag();
              }
              return SafeArea(
                bottom: false,
                child: Stack(
                  children: [
                    // 热区可视化占位（键供测试/调试；手势统一走 body 层分派）。
                    if (_doc != null && _err == null) ...[
                      Positioned(
                        left: 0,
                        top: size.height * .15,
                        bottom: size.height * .15,
                        width: size.width * .16,
                        child: const ColoredBox(
                          key: ValueKey('brZoneL'),
                          color: Colors.transparent,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: size.height * .15,
                        bottom: size.height * .15,
                        width: size.width * .16,
                        child: const ColoredBox(
                          key: ValueKey('brZoneR'),
                          color: Colors.transparent,
                        ),
                      ),
                      Positioned(
                        left: size.width * .16,
                        right: size.width * .16,
                        top: size.height * .15,
                        bottom: size.height * .15,
                        child: const ColoredBox(
                          key: ValueKey('brZoneC'),
                          color: Colors.transparent,
                        ),
                      ),
                    ],
                    Positioned.fill(child: _stage(th)),
                    if (_doc != null && _err == null) ...[
                      if (_chrome) _topBar(th),
                      if (_chrome && _pag != null) _bottomBar(th, size),
                      if (_flash != null) _flashBar(th),
                      if (_sel != null) _selOverlay(size),
                    ],
                    if (_drawerOpen && _doc != null && _pag != null)
                      ReaderTocDrawer(
                        state: _drState,
                        bookId: widget.bookId,
                        doc: _doc!,
                        pager: _pag!,
                        ci: _pos.ci,
                        pg: _pos.pg,
                        onGoto: _gotoChapter,
                        onAddBookmark: () {
                          setState(() => _pos.bm = [_pos.ci, _pos.pg, DateTime.now().millisecondsSinceEpoch]);
                          _savePos();
                          _showFlash('书签已添加 · ${_cfi(_pos.ci, _pos.pg)}');
                        },
                        onSearchJump: (hits, idx, q) {
                          setState(() {
                            _hits = hits;
                            _hitI = idx;
                            _hitQ = q;
                          });
                          _jumpHit(idx);
                        },
                        onClose: () => setState(() => _drawerOpen = false),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String _cfi(int ci, int pg) => '${EpubDoc.cfiPrefix}/${ci + 2}/$pg';

  Widget _topBar((String, Color, Color) th) {
    final doc = _doc!;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        key: const ValueKey('br-top'),
        color: const Color(0xDB0F172A),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  key: const ValueKey('br-back'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        _book?.title ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '${doc.chapters[_pos.ci.clamp(0, doc.chapters.length - 1)].title} · ${_cfg.mode == 'page' ? '翻页' : '滚动'}模式',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.white.withValues(alpha: .6),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Container(
                    key: const ValueKey('br-sess-chip'),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _clockText,
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.white,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                // 全书检索入口（双入口之一；另一入口＝抽屉「搜本书」Tab）。
                IconButton(
                  key: const ValueKey('brBtnSearch'),
                  visualDensity: VisualDensity.compact,
                  onPressed: _openSearch,
                  icon: const Icon(Icons.search_rounded, size: 17, color: Colors.white),
                ),
              ],
            ),
            if (_hits.isNotEmpty && _hitI >= 0)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 2),
                child: Row(
                  key: const ValueKey('brHitsBar'),
                  children: [
                    Text(
                      '${_hitI + 1}/${_hits.length} 处匹配 · “$_hitQ”',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: .75),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      key: const ValueKey('brHitPrev'),
                      onPressed: () => _hitStep(-1),
                      child: const Text('上一处', style: TextStyle(fontSize: 10, color: Colors.white)),
                    ),
                    TextButton(
                      key: const ValueKey('brHitNext'),
                      onPressed: () => _hitStep(1),
                      child: const Text('下一处', style: TextStyle(fontSize: 10, color: Colors.white)),
                    ),
                    IconButton(
                      key: const ValueKey('brHitClear'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() {
                        _hits = const [];
                        _hitI = -1;
                        _hitMark = null;
                      }),
                      icon: const Icon(Icons.close_rounded, size: 14, color: Colors.white60),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar((String, Color, Color) th, Size size) {
    final pag = _pag!;
    final n = pag.chapterPages(_pos.ci);
    final gp = pag.gPos(_pos.ci, _pos.pg);
    final total = pag.total;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        key: const ValueKey('br-bottom'),
        color: const Color(0xDB0F172A),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    _cfi(_pos.ci, _pos.pg),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white70,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${_pos.pg + 1}/$n 页 · 第 ${gp + 1}/$total 页 · ${pag.pct(_pos.ci, _pos.pg)}%',
                  key: const ValueKey('brPgLbl'),
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.white70,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                key: const ValueKey('brProg'),
                value: gp.toDouble()
                    .clamp(0.0, (total - 1).toDouble())
                    .toDouble(),
                min: 0,
                max: (total - 1)
                    .toDouble()
                    .clamp(1.0, (1 << 30).toDouble())
                    .toDouble(),
                onChanged: (v) => _seek(v.round()),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _chromeBtn('brBtnToc', '目录', () => setState(() => _drawerOpen = true)),
                // 窄屏五钮并排放不下时整体缩放（不换行、不溢出）。
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      children: [
                        _chromeBtn('brBtnA-', 'A-', () => _nudgeFont(-1)),
                        const SizedBox(width: 6),
                        _chromeBtn('brBtnA+', 'A+', () => _nudgeFont(1)),
                        const SizedBox(width: 6),
                        _chromeBtn(
                          'brBtnTheme',
                          _cfg.theme == 'custom'
                              ? '自定义'
                              : (kBrThemes[_cfg.theme] ?? kBrThemes['day']!).$1,
                          _cycleTheme,
                        ),
                        const SizedBox(width: 6),
                        _chromeBtn('brBtnMode', _cfg.mode == 'page' ? '滚动' : '翻页', _toggleMode),
                        const SizedBox(width: 6),
                        // 批4：外观草稿制面板入口（原型八宫格「外观」同语义）。
                        _chromeBtn('brBtnAp', '外观', _openAppearance),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chromeBtn(String key, String label, VoidCallback onTap) {
    return GestureDetector(
      key: ValueKey(key),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ),
    );
  }

  Widget _flashBar((String, Color, Color) th) {
    return Positioned(
      bottom: 120,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          key: const ValueKey('brFlash'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xDB0F172A),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            _flash!,
            style: const TextStyle(fontSize: 10, color: Colors.white),
          ),
        ),
      ),
    );
  }

  // ---------- 舞台（翻页/滚动） ----------

  Widget _stage((String, Color, Color) th) {
    if (_err != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _err!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE11D48),
                ),
              ),
              const SizedBox(height: 14),
              TextButton(
                key: const ValueKey('br-err-back'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      );
    }
    final doc = _doc;
    final pag = _pag;
    if (doc == null || pag == null) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }
    if (_cfg.mode == 'scroll') {
      return ListView(
        key: const ValueKey('br-scroll'),
        controller: _scrollCtrl,
        padding: EdgeInsets.fromLTRB(_cfg.mar, _cfg.mar + 30, _cfg.mar, _cfg.mar + 56),
        children: [
          for (var ci = 0; ci < doc.chapters.length; ci++) ...[
            for (var pi = 0; pi < doc.chapters[ci].paras.length; pi++)
              _para(th, doc, ci, doc.chapters[ci].paras[pi], pi),
          ],
        ],
        // 滚动模式可见章跟踪（chrome 副标题近似）。
      );
    }
    final pages = pag.perChapter[_pos.ci];
    final pg = _pos.pg.clamp(0, pages.length - 1);
    final isLast = _pos.ci == doc.chapters.length - 1 && pg == pages.length - 1;
    return AnimatedSwitcher(
      key: const ValueKey('br-pageflip'),
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(.06, 0), end: Offset.zero)
              .chain(CurveTween(curve: Curves.easeOut))
              .animate(anim),
          child: child,
        ),
      ),
      child: Container(
        key: ValueKey('page-$_pos.ci-$pg'),
        alignment: Alignment.center,
        padding: EdgeInsets.fromLTRB(_cfg.mar, _cfg.mar + 40, _cfg.mar, _cfg.mar + 46),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final pi in pages[pg]) _para(th, doc, _pos.ci, doc.chapters[_pos.ci].paras[pi], pi),
            if (isLast)
              const Padding(
                padding: EdgeInsets.only(top: 18),
                child: Text(
                  '—— 全书完 ——',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.black38),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 选区浮条（原型 brSelBar/brColorPop）：前扩｜七操作｜后扩 + 5色板/删划线。
  Widget _selOverlay(Size size) {
    const dark = Color(0xE60F172A);
    const brand = Color(0xFFA5B4FC);
    Widget chip(String k, String label, IconData icon, VoidCallback? onTap, {bool accent = false}) =>
        InkWell(
          key: ValueKey(k),
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: accent ? brand : Colors.white),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    color: accent ? brand : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        );
    return Positioned(
      top: size.height * .15,
      left: 0,
      right: 0,
      child: Column(
        children: [
          if (_hlPop)
            Container(
              key: const ValueKey('brColorPop'),
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: dark, borderRadius: BorderRadius.circular(14)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final tg in BookQuote.colorTags)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        key: ValueKey('brColor-$tg'),
                        onTap: () => _addHl(tg),
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: Color(
                              0xFF000000 |
                                  (BookQuote.hexToInt(
                                            BookQuote.colorHex[tg],
                                          ) ??
                                          0xFDE047),
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white38),
                          ),
                        ),
                      ),
                    ),
                  TextButton(
                    key: const ValueKey('brDelHl'),
                    onPressed: _delHl,
                    child: const Text(
                      '删划线',
                      style: TextStyle(
                        fontSize: 9.5,
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            key: const ValueKey('brSelBar'),
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            decoration: BoxDecoration(color: dark, borderRadius: BorderRadius.circular(16)),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  chip('brGrowL', '前扩', Icons.chevron_left_rounded, () => _growSel(-1), accent: true),
                  chip('brSelCopy', '复制', Icons.copy_rounded, _actCopy),
                  chip('brSelHl', '划线', Icons.format_color_text_rounded, () => setState(() => _hlPop = !_hlPop)),
                  chip('brSelQuote', '书摘', Icons.note_alt_outlined, () => _actQuote(false)),
                  chip('brSelThink', '感想', Icons.edit_outlined, () => _actQuote(true)),
                  chip('brSelAi', 'AI 解读', Icons.auto_awesome_rounded, _actAi),
                  chip('brSelDict', '词典', Icons.book_outlined, _actDict),
                  chip('brSelShare', '分享', Icons.ios_share, _actShare),
                  chip('brGrowR', '后扩', Icons.chevron_right_rounded, () => _growSel(1), accent: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _para((String, Color, Color) th, EpubDoc doc, int ci, EpubPara p, int pi) {
    final isHit =
        _hitMark != null && _hitMark!.ci == ci && _hitMark!.pi == pi;
    // 批3：划线色底（原型 background: c+'44'）与选中段高亮；点段即划词。
    final hl = p.kind == EpubParaKind.image ? null : _hlAt(ci, pi);
    final s = _sel;
    final inSel = s != null && s.ci == ci && pi >= s.p0 && pi <= s.p1;
    Widget wrap(Widget child) => GestureDetector(
      key: ValueKey('brpTap-$ci-$pi'),
      behavior: HitTestBehavior.translucent,
      onTap: () => _selectPara(ci, pi),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        decoration: hl == null && !inSel
            ? null
            : BoxDecoration(
                color: inSel
                    ? const Color(0x4D6366F1)
                    : hl!.c.withValues(alpha: .27),
                borderRadius: BorderRadius.circular(3),
              ),
        child: (hl?.hasThought ?? false)
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  child,
                  // 原型 br-pulse 橙点：该划线带感想，点按提示去书摘库查看。
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 2),
                    child: GestureDetector(
                      key: ValueKey('brHlDot-$ci-$pi'),
                      onTap: () => readToast(context, '该划线已在书摘库 · 详情页可查看'),
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF97316),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : child,
      ),
    );
    switch (p.kind) {
      case EpubParaKind.image:
        final bytes = doc.imageBytes(p.imgSrc);
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: GestureDetector(
            key: ValueKey('brImg-$ci-$pi'),
            onTap: () => _openImage(p),
            child: Column(
              children: [
                if (bytes != null)
                  Image.memory(Uint8List.fromList(bytes), fit: BoxFit.contain)
                else
                  Container(
                    height: 140,
                    color: Colors.black12,
                    alignment: Alignment.center,
                    child: const Icon(Icons.image_outlined, size: 28, color: Colors.black26),
                  ),
                if (p.alt.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      p.alt,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: p.text.isEmpty ? 10.5 : 12,
                        color: th.$3.withValues(alpha: .55),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      case EpubParaKind.heading:
        // 段间距放检测器外：空隙带仍归 body 分派（中区点按开收 chrome）。
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 12),
          child: wrap(
            Text(
              p.text,
              style: TextStyle(
                fontSize: _cfg.fs * 1.25,
                height: _cfg.lh,
                fontFamily: _cfg.fontFamily,
                fontWeight: FontWeight.w800,
                color: th.$3,
              ),
            ),
          ),
        );
      case EpubParaKind.quote:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: wrap(
            Container(
              padding: const EdgeInsets.only(left: 11),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: th.$3, width: 3)),
              ),
              child: Text(
                p.text,
                style: TextStyle(
                  fontSize: _cfg.fs,
                  height: _cfg.lh,
                  letterSpacing: _cfg.ls,
                  fontFamily: _cfg.fontFamily,
                  color: th.$3.withValues(alpha: .85),
                ),
              ),
            ),
          ),
        );
      case EpubParaKind.text:
        return Padding(
          key: ValueKey('brp-$ci-$pi'),
          padding: const EdgeInsets.only(bottom: 8),
          child: wrap(
            Text.rich(
              _textSpan(th, doc, ci, p, pi, isHit),
              textAlign: TextAlign.justify,
            ),
          ),
        );
    }
  }

  /// 段渲染：2em 缩进 + 链接 span（点击区）+ 命中底色。
  TextSpan _textSpan(
    (String, Color, Color) th,
    EpubDoc doc,
    int ci,
    EpubPara p,
    int pi,
    bool hit,
  ) {
    final base = TextStyle(
      fontSize: _cfg.fs,
      height: _cfg.lh,
      letterSpacing: _cfg.ls,
      fontFamily: _cfg.fontFamily,
      color: th.$3,
    );
    final display = paraDisplayText(p);
    final linkStyle = base.copyWith(
      color: const Color(0xFF6366F1),
      decoration: TextDecoration.underline,
      decorationColor: const Color(0xFF6366F1).withValues(alpha: .7),
    );
    final markStyle = base.copyWith(
      backgroundColor: const Color(0xFF6366F1).withValues(alpha: .28),
    );
    final children = <InlineSpan>[];
    // 事件流：链接起/止 + 命中起/止（显示文本偏移＝原始 +2 缩进）。
    final events = <(int, int, EpubLink?)>[
      for (final l in p.links) ...[
        (l.start + 2, 0, l),
        (l.end + 2, 1, l),
      ],
      if (hit && _hitQ.isNotEmpty) ...[
        for (var idx = p.text.indexOf(_hitQ); idx >= 0; idx = p.text.indexOf(_hitQ, idx + 1)) ...[
          (idx + 2, 2, null),
          (idx + 2 + _hitQ.length, 3, null),
        ],
      ],
    ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    var cursor = 0;
    var inLink = 0;
    var inMark = 0;
    void flush(int to) {
      if (to <= cursor) return;
      final t = display.substring(cursor.clamp(0, display.length), to.clamp(0, display.length));
      if (t.isEmpty) {
        cursor = to;
        return;
      }
      final style = inLink > 0 ? linkStyle : (inMark > 0 ? markStyle : base);
      final link = p.links.firstWhere(
        (l) => l.start + 2 == cursor || (cursor >= l.start + 2 && cursor < l.end + 2),
        orElse: () => EpubLink(start: -1, end: -1, href: '', external: false),
      );
      children.add(
        TextSpan(
          text: t,
          style: style,
          recognizer: (inLink > 0 && link.start >= 0)
              ? (TapGestureRecognizer()..onTap = () => _onLink(link))
              : null,
        ),
      );
      cursor = to;
    }
    for (final (at, kind, _) in events) {
      flush(at);
      switch (kind) {
        case 0:
          inLink++;
        case 1:
          inLink = (inLink - 1).clamp(0, 1 << 20);
        case 2:
          inMark++;
        case 3:
          inMark = (inMark - 1).clamp(0, 1 << 20);
      }
    }
    flush(display.length);
    return TextSpan(style: base, children: children);
  }
}

/// AI 解读弹层（原型 sheetBrAi）：门控→请求→展示 insight；可复制/填想法。
class _BrAiSheet extends ConsumerStatefulWidget {
  const _BrAiSheet({
    required this.bookId,
    required this.quote,
    required this.book,
    required this.onToQuote,
  });

  final String bookId;
  final String quote;
  final String book;
  final void Function(String insight) onToQuote;

  @override
  ConsumerState<_BrAiSheet> createState() => _BrAiSheetState();
}

class _BrAiSheetState extends ConsumerState<_BrAiSheet> {
  String? _insight;
  String? _err;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final ai = ref.read(aiServiceProvider);
    final denial = await ai.gate('read.quote_insight');
    if (!mounted) return;
    if (denial != null) {
      setState(() => _err = denial);
      return;
    }
    setState(() {});
    try {
      final r = await ai.request('read.quote_insight', {
        'quote': widget.quote,
        'book': widget.book,
      });
      if (!mounted) return;
      final m = r.json;
      final txt = m != null ? '${m['insight'] ?? ''}' : (r.text ?? '').trim();
      setState(() => _insight = txt.isEmpty ? '（返回为空）' : txt);
    } on Object catch (e) {
      if (mounted) {
        setState(() => _err = e is AiDenied ? e.reason : '解读失败 · 稍后再试');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
        child: Column(
          key: const ValueKey('sheetBrAi'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AI 解读',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              widget.quote,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            SizedBox(
              key: const ValueKey('brAiOut'),
              height: 108,
              child: _err != null
                  ? Text(_err!, style: const TextStyle(fontSize: 12, height: 1.6))
                  : _insight == null
                  ? Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '正在结合上下文解读…',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    )
                  : SingleChildScrollView(
                      child: Text(
                        _insight!,
                        style: const TextStyle(fontSize: 13, height: 1.7),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('brAiCopy'),
                    onPressed: _insight == null
                        ? null
                        : () {
                            Clipboard.setData(ClipboardData(text: _insight!));
                            readToast(context, '解读已复制');
                          },
                    child: const Text('复制'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('brAiToQuote'),
                    onPressed: _insight == null
                        ? null
                        : () => widget.onToQuote(_insight!),
                    child: const Text('填为感想'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
