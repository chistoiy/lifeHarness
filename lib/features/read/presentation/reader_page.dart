import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/epub_doc.dart';
import '../domain/book.dart';
import 'read_providers.dart';
import 'read_sheets.dart' show readToast;
import 'reader_pager.dart';
import 'reader_toc_drawer.dart';

/// 阅读主题色（原型 BR_THEMES；自定义底色字色随批4 外观面板）。
const kBrThemes = {
  'day': ('日间', Color(0xFFFAF6EE), Color(0xFF3B3630)),
  'eye': ('护眼', Color(0xFFCFE6CF), Color(0xFF2F4A33)),
  'night': ('夜间', Color(0xFF101317), Color(0xFF9AA4B0)),
};
const _kThemeOrder = ['day', 'eye', 'night'];

/// 阅读器全局外观 KV（原型 lh_reader_bs_v1.cfg · 逐书覆盖批4）：
/// fs/lh/ls/mar/theme/mode。
class _Cfg {
  _Cfg({
    this.fs = 19,
    this.lh = 1.62,
    this.ls = 0.4,
    this.mar = 22,
    this.theme = 'day',
    this.mode = 'page',
  });

  final double fs, lh, ls, mar;
  final String theme, mode;

  factory _Cfg.decode(String? raw) {
    try {
      final v = raw == null ? null : jsonDecode(raw) as Map<String, dynamic>?;
      if (v == null) return _Cfg();
      double d(String k, double f) => (v[k] as num?)?.toDouble() ?? f;
      return _Cfg(
        fs: d('fs', 19),
        lh: d('lh', 1.62),
        ls: d('ls', 0.4),
        mar: d('mar', 22),
        theme: _kThemeOrder.contains(v['theme']) ? v['theme'] as String : 'day',
        mode: v['mode'] == 'scroll' ? 'scroll' : 'page',
      );
    } catch (_) {
      return _Cfg();
    }
  }

  String encode() => jsonEncode({'fs': fs, 'lh': lh, 'ls': ls, 'mar': mar, 'theme': theme, 'mode': mode});

  _Cfg copyWith({double? fs, double? lh, double? ls, double? mar, String? theme, String? mode}) => _Cfg(
    fs: fs ?? this.fs,
    lh: lh ?? this.lh,
    ls: ls ?? this.ls,
    mar: mar ?? this.mar,
    theme: theme ?? this.theme,
    mode: mode ?? this.mode,
  );
}

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

  _Cfg _cfg = _Cfg();
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
    // 外观/位置先读，渲染即按记忆恢复（CFI 自动定位 · V1.50 口径③）。
    _cfg = _Cfg.decode(await repo.kv('reader.cfg'));
    _pos = _Pos.decode(await repo.kv('reader.pos.${b.id}'));
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
      if (mounted && _t0 != null) {
        setState(() => _sessSecs = DateTime.now().difference(_t0!).inSeconds);
      }
    });
    try {
      final doc = await ref.read(epubDocLoaderProvider)(b.epub!.path);
      if (!mounted) return;
      setState(() => _doc = doc);
      // 首帧已定 _viewport 时 LayoutBuilder 不会再触发；此处直接建分页。
      _rebuildPag();
      if (_pag == null) _clampPos();
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

  // ---------- 外观（A-/A+/主题循环/模式切换；完整面板批4） ----------

  Future<void> _persistCfg() async {
    await ref.read(readRepositoryProvider).setKv('reader.cfg', _cfg.encode());
  }

  void _nudgeFont(int d) {
    setState(() {
      _cfg = _cfg.copyWith(fs: (_cfg.fs + d).clamp(14.0, 30.0));
    });
    _rebuildPag();
    unawaited(_persistCfg());
  }

  void _cycleTheme() {
    final i = _kThemeOrder.indexOf(_cfg.theme);
    final next = _kThemeOrder[(i + 1) % _kThemeOrder.length];
    setState(() => _cfg = _cfg.copyWith(theme: next));
    unawaited(_persistCfg());
  }

  void _toggleMode() {
    setState(() => _cfg = _cfg.copyWith(mode: _cfg.mode == 'page' ? 'scroll' : 'page'));
    _savePos();
    unawaited(_persistCfg());
    _rebuildPag();
  }

  void _rebuildPag() {
    final doc = _doc;
    if (doc == null || _viewport.width <= 0) return;
    setState(() {
      _pag = BookPagination.of(doc, _layout());
      _clampPos();
    });
  }

  ReaderLayout _layout() => ReaderLayout(
    width: _viewport.width,
    height: _viewport.height,
    fs: _cfg.fs,
    lh: _cfg.lh,
    ls: _cfg.ls,
    mar: _cfg.mar,
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
    // 询问：sheetBrLink 半屏（URL + 打开/取消 · 含输入框弹层无关，无需 viewInsets）。
    final ok = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sc) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            key: const ValueKey('sheetBrLink'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '外部链接',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                url,
                style: const TextStyle(fontSize: 11.5, height: 1.4),
              ),
              const SizedBox(height: 14),
              FilledButton(
                key: const ValueKey('brLkOpen'),
                onPressed: () => Navigator.of(sc).pop(true),
                child: const Text('在系统浏览器打开'),
              ),
              TextButton(
                onPressed: () => Navigator.of(sc).pop(false),
                child: const Text('取消'),
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
    final bytes = _doc?.images[para.imgSrc];
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
    final th = kBrThemes[_cfg.theme]!;
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
            if (p.dx < s.width * .16) {
              _flip(-1);
            } else if (p.dx > s.width * .84) {
              _flip(1);
            } else {
              setState(() => _chrome = !_chrome);
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
                      if (_chrome) _bottomBar(th, size),
                      if (_flash != null) _flashBar(th),
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
                Row(
                  children: [
                    _chromeBtn('brBtnA-', 'A-', () => _nudgeFont(-1)),
                    const SizedBox(width: 6),
                    _chromeBtn('brBtnA+', 'A+', () => _nudgeFont(1)),
                    const SizedBox(width: 6),
                    _chromeBtn('brBtnTheme', kBrThemes[_cfg.theme]!.$1, _cycleTheme),
                    const SizedBox(width: 6),
                    _chromeBtn('brBtnMode', _cfg.mode == 'page' ? '滚动' : '翻页', _toggleMode),
                  ],
                ),
                // 外观完整面板批4 接入（此处不放灰钮）。
                const SizedBox(width: 44),
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

  Widget _para((String, Color, Color) th, EpubDoc doc, int ci, EpubPara p, int pi) {
    final isHit =
        _hitMark != null && _hitMark!.ci == ci && _hitMark!.pi == pi;
    switch (p.kind) {
      case EpubParaKind.image:
        final bytes = doc.images[p.imgSrc];
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
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 12),
          child: Text(
            p.text,
            style: TextStyle(
              fontSize: _cfg.fs * 1.25,
              height: _cfg.lh,
              fontWeight: FontWeight.w800,
              color: th.$3,
            ),
          ),
        );
      case EpubParaKind.quote:
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
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
              color: th.$3.withValues(alpha: .85),
            ),
          ),
        );
      case EpubParaKind.text:
        return Padding(
          key: ValueKey('brp-$ci-$pi'),
          padding: const EdgeInsets.only(bottom: 8),
          child: Text.rich(
            _textSpan(th, doc, ci, p, pi, isHit),
            textAlign: TextAlign.justify,
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
