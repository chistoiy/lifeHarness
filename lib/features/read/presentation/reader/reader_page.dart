import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui; // V1.53.2 放大镜抓帧

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph, RenderRepaintBoundary;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/ai/ai_review.dart' show aiRunWithReview;
import '../../../../core/database/schema/xray.dart' as xs;
import '../../../../core/logging/app_log.dart';
import '../../data/xray/xray_dao.dart' show XrayEntityRow;
import './reader_xray_learn_sheets.dart' show showXrPeekSheet;
import '../../data/epub_doc.dart';
import '../../domain/book.dart';
import '../../domain/book_quote.dart';
import '../../domain/book_session.dart' show BrLoc;
import '../../domain/reader_cfg.dart';
import './epub_state_ui.dart' show showBrDelSheet;
import '../read_providers.dart';
import '../read_sheets.dart' show readToast, showQuoteEditPage;
import './reader_appearance_sheet.dart';
import './reader_bg.dart';
import './reader_bottom_sheets.dart';
import './reader_pager.dart';
import './reader_search_page.dart';
import './reader_sel_layer.dart';
import './reader_loupe.dart'; // V1.53.2 选区放大镜
import '../selection_controller.dart';
import './reader_toc_drawer.dart';

part 'reader_models.dart';
part 'reader_chrome.dart';
part 'reader_sel_ops.dart';
part 'reader_stage.dart';
part 'reader_links.dart';
part 'reader_xray.dart';



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

class _ReaderPageState extends ConsumerState<ReaderPage>
    with WidgetsBindingObserver {
  Book? _book;
  EpubDoc? _doc;
  String? _err;
  bool _ownTimer = false;

  /// 轮5.4：本页是否已把全局读书计时条挂起（ dispose 时按此还原）。
  bool _readerCounted = false;

  /// 轮5.2②：本页在跑会话 id + 起始位置快照（退出时自动结算，写起止章节/页/百分比）。
  int? _sessId;
  BrLoc? _sessFrom;

  /// read.brMinSecs：短于该秒数的阅读不记时长也不记会话（默认 30 · 设置组可调）。
  int _minSecs = 30;

  /// 出页后的结算提示：页面已销毁，用离开前抓住的 messenger。
  ScaffoldMessengerState? _ms;

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
  /// R14-6：顶/底栏实测高度（BrSizeProbe 回灌；选区工具条让位约束 cT/cB 用）。
  double _topBarH = 0, _bottomBarH = 0;
  // 「回到进书位置」锚点：进书时的 (ci,pg)；拖离后进度弹层给出入口（轮5.2①）。
  ({int ci, int pg})? _homePos;
  bool _backPill = false;
  /// 轮5.2①：目录/内链跳章前的位置（原型 _brJumpFrom）。
  /// 入口只放抽屉一行 + 进度弹层，正文不再悬浮任何胶囊。
  ({int ci, int pg, String title})? _jumpFrom;
  String? _flash;
  Timer? _flashT;
  int _sessSecs = 0;
  Timer? _clock;
  DateTime? _t0;

  // 抽屉
  bool _drawerOpen = false;
  final TocDrawerState _drState = TocDrawerState();
  late SelectionController _selController; // V1.53.2 性能批 1

  /// V1.53.2 选区放大镜：正文抓帧边界 + 手指落点（Stack 局部坐标）+ 快照。
  final GlobalKey _contentBoundaryKey = GlobalKey(debugLabel: 'brLoupeBoundary');
  Offset? _loupeFocal;
  ui.Image? _loupeImage;


  // 命中导航（搜本书/全书检索共用）
  List<({int ci, int pi, String text})> _hits = const [];
  int _hitI = -1;
  String _hitQ = '';
  ({int ci, int pg, int pi})? _hitMark; // 当前高亮段

  // 批3 划词/划线（原型 brV.sel + BS_QUOTES.cf + BR_LOCAL_HL）。
  // 轮4③：同章闭区间 + 首/尾段内字符偏移（长按默认命中一句 · 轮5① 扩选改为首尾手柄拖动）。
  bool _hlPop = false; // 色板展开
  // 长按落点 → 句边界需要段内命中偏移；'ci:pi' → 段 Text GlobalKey。
  final Map<String, GlobalKey> _paraKeys = {};
  // 轮5①：手柄要按全局坐标落位，需要 Stack 的 RenderBox 做 globalToLocal。
  final GlobalKey _stackKey = GlobalKey(debugLabel: 'brStack');
  // 轮4③：最后一次长按段（同段再长按＝收起的判定锚）。
  int _lpCi = -1, _lpPi = -1;
  /// V1.53.4 ①：手柄跨页扩选的翻页守护位——翻页后新页尚未渲染期间吞掉拖动事件，
  /// 渲染落定（postFrame）后恢复命中，防止一帧内连翻多页。
  bool _selFlipPending = false;
  bool _brSync = true; // read.brSync：划线自动存为书摘
  /// V1.53.4④ 长按选择粒度（read.brSelGran · 默认 选字；选句＝命中整句）。
  String _brSelGran = '选字';
  /// V1.53.4⑤ 选区工具条顺序与显隐（read.brSelBar · 默认全量 8 项）。
  List<String> _brSelTools = kBrSelDefaultTools;
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
    WidgetsBinding.instance.addObserver(this);
    _selController = SelectionController(); // V1.53.2 性能批 1
    _boot();
    // 轮5.4：进阅读页挂起全局读书计时条（首帧后再写，避开 initState 取 container）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(readerOpenProvider.notifier).state++;
      _readerCounted = true;
      // V1.54 批A：书架长按「生成/管理全书索引」跳进来的书，落地即开 X-Ray 段。
      if (ref.read(readerXrOpenTabProvider) == widget.bookId) {
        ref.read(readerXrOpenTabProvider.notifier).state = null;
        openXrTab();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // §8 生命周期：退后台自动暂停解析（断点已落库），回前台一键恢复。
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      xrNoteBackground();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_readerCounted) {
      try {
        ref.read(readerOpenProvider.notifier).state--;
      } catch (_) {
        // 容器先于本页销毁（测试拆树）：计数随容器一起消失。
      }
    }
    _clock?.cancel();
    _flashT?.cancel();
    _autoT?.cancel();
    _pagSaveT?.cancel();
    if (_brightOwned) {
      _brightOwned = false;
      unawaited(_wake(false));
    }
    _loupeImage?.dispose();
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
    final fMin = repo.kv('read.brMinSecs');
    // V1.53.4④⑤ 选区设置：长按粒度（默认选字）与工具条名单（默认 8 项全开）。
    final fGran = repo.kv('read.brSelGran');
    final fBar = repo.kv('read.brSelBar');
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
    _homePos = (ci: _pos.ci, pg: _pos.pg);
    _backPill = false;
    // 划线同库数据（批3）：同步开关 + 本书划线行 + brSync 关时暂存。
    _brSync = await fSync != 'false';
    _minSecs = int.tryParse(await fMin ?? '') ?? 30;
    _brSelGran = await fGran ?? '选字';
    _brSelTools = brSelToolsDecode(await fBar);
    _localHl = _LocalHl.decodeAll(await fHl);
    _hlQuotes = (await fQuotes)
        .where((q) => q.deletedAt == null && q.cf != null)
        .toList();
    if (!mounted) return;
    setState(() {});
    // 进阅读器自动开始计时；他处已在计时则沿用该计时条（原型 brV.ownT）。
    // 真机反馈（2026-09-28）：在跑会话属于「别书」（含崩溃遗留的挂死行）时
    // 接管＝startSession 内部先收口那行再为本书开新行；本书在跑则沿用。
    // 修复前：别书在跑 → 本页不记时长、进度也不落库。
    final running = await repo.runningSession();
    if (running != null && running.bookId == b.id) {
      // 他处已为本书开计时：沿用该会话（起止快照补在同一行上）。
      _sessId = running.id;
    } else {
      final ses = await repo.startSession(b.id);
      _ownTimer = true;
      _sessId = ses.id;
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
      // 轮5.2②：分页就绪＝位置可算 → 回填会话起始快照（此后无需手填）。
      _sessFrom = _locSnap();
      final sid = _sessId;
      if (sid != null && _sessFrom != null) {
        await repo.stampSessionStart(sid, _sessFrom!);
      }
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

  /// 当前位置快照（轮5.2②：会话起止自动记录 · 原型 brLocSnap）。
  BrLoc? _locSnap() {
    final doc = _doc, pag = _pag;
    if (doc == null || pag == null || doc.chapters.isEmpty) return null;
    final ci = _pos.ci.clamp(0, doc.chapters.length - 1);
    return BrLoc(
      page: pag.gPosEst(ci, _pos.pg) + 1,
      pct: pag.pct(ci, _pos.pg).toDouble(),
      chapter: doc.chapters[ci].title,
    );
  }

  /// 结算：本页开启的计时才由本页结束；进度无条件写回书籍记录
  /// （真机反馈 2026-09-28：修复前 _ownTimer=false 连进度都不落库）。
  /// 轮5.2②：起止位置随会话自动落库；短于 read.brMinSecs 的会话整条丢弃
  /// （不记时长、不入明细），但进度仍然保存。
  void _leave() {
    _clock?.cancel();
    final own = _ownTimer;
    final repo = ref.read(readRepositoryProvider);
    final doc = _doc;
    final pag = _pag;
    final to = _locSnap();
    final from = _sessFrom ?? to;
    final gate = _minSecs;
    final secs = _t0 == null ? 0 : DateTime.now().difference(_t0!).inSeconds;
    final ms = _ms;
    final title = _book?.title ?? '';
    unawaited(() async {
      final closed = own
          ? await repo.endSession(
              widget.bookId,
              to: to,
              minSecs: gate,
            )
          : null;
      if (doc != null && pag != null && _book != null) {
        final pct = pag.pct(_pos.ci, _pos.pg);
        final b = _book!;
        final pages = b.pages > 0 ? b.pages : pag.estTotal;
        unawaited(
          repo.saveProgress(
            widget.bookId,
            Book.kWayPage,
            (pages * pct / 100).round().toDouble(),
            chapterTitle: doc.chapters[_pos.ci].title,
          ),
        );
      }
      // 结算提示只属于本页自己计时的会话（沿用他处计时时不抢话）。
      if (ms == null || !own) return;
      final span = from != null && to != null && to.chapter != from.chapter
          ? '${from.chapter}→${to.chapter}'
          : (to?.chapter ?? '');
      final msg = closed == null
          ? '《$title》本次 $secs 秒 · 短于 $gate 秒不计入计时'
          : '《$title》本次 ${closed.minutes} 分钟 · 自动记 $span'
              ' P${from?.page ?? 0}→P${to?.page ?? 0}'
              ' · ${from?.pct?.round() ?? 0}%→${to?.pct?.round() ?? 0}%';
      ms
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(milliseconds: 2200),
            content: Text(msg),
          ),
        );
    }());
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
      _pos.ci++;
      _ensureCur(); // 跨章＝按需实算新章（毫秒级）
      setState(() {
        _pos.pg = 0;
        _flash = doc.chapters[_pos.ci].title;
      });
    } else if (np < 0) {
      if (_pos.ci == 0) {
        setState(() => _pos.pg = 0);
        _savePos();
        return;
      }
      _pos.ci--;
      _ensureCur();
      setState(() {
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
    final doc = _doc;
    // 轮5③：跳章前记一份来源位置（同原型 brGotoCh），抽屉里给「回到刚才在读」。
    final from = doc == null || ci >= doc.chapters.length
        ? null
        : (
            ci: _pos.ci,
            pg: _pos.pg,
            title: doc.chapters[_pos.ci.clamp(0, doc.chapters.length - 1)].title,
          );
    setState(() {
      if (from != null && from.ci != ci) _jumpFrom = from;
      _pos.ci = ci;
      _pos.pg = 0;
      _drawerOpen = false;
      _flash = doc?.chapters[ci].title;
    });
    _ensureCur();
    _savePos();
    _flashT?.cancel();
    _flashT = Timer(const Duration(milliseconds: 1300), () {
      if (mounted) setState(() => _flash = null);
    });
    if (_cfg.mode == 'scroll') _scrollToPara(ci, 0);
  }

  /// 轮5③/5.2①：回到跳章前的位置（入口＝目录抽屉行 / 进度弹层按钮）。
  void _goBackJump() {
    final f = _jumpFrom;
    if (f == null) return;
    setState(() {
      _jumpFrom = null;
      _pos.ci = f.ci;
      _pos.pg = f.pg;
      _drawerOpen = false;
      _flash = f.title;
    });
    _ensureCur();
    _savePos();
    _flashT?.cancel();
    _flashT = Timer(const Duration(milliseconds: 1300), () {
      if (mounted) setState(() => _flash = null);
    });
    if (_cfg.mode == 'scroll') _scrollToPara(f.ci, f.pg);
  }

  /// 进度分数定位（0~1，字节加权 · V1.53.1 轮4 foliate 模型；进度条 seek）。
  void _seek(double f) {
    final pag = _pag;
    final doc = _doc;
    if (pag == null || doc == null) return;
    final p = pag.fracTo(f);
    setState(() {
      _pos.ci = p.ci;
      _pos.pg = p.pg;
    });
    _ensureCur();
    final h = _homePos;
    setState(() {
      _backPill = h != null && (h.ci != _pos.ci || h.pg != _pos.pg);
    });
    _savePos();
  }

  void _goHome() {
    final h = _homePos;
    if (h == null) return;
    setState(() {
      _pos.ci = h.ci;
      _pos.pg = h.pg;
      _backPill = false;
    });
    _savePos();
    _showFlash('已返回原进度');
  }

  // ---------- V1.53.2 轮5.1 · 底栏三图标（目录/进度/外观·面板升格为弹层） ----------

  /// 进度弹层（原型 sheetBrProg）：统计三格 + 全书滑条 + 明细/自动翻页/回进书位。
  void _openProgressSheet() {
    final doc = _doc;
    final pag = _pag;
    if (doc == null || pag == null) return;
    final f = pag.frac(_pos.ci, _pos.pg);
    final pct = (f * 100).round().clamp(0, 100);
    // 剩余字数 ÷ 400 字/分钟（经验阅读速率）→ ETA。
    final leftChars = (pag.totalChars * (1 - f)).round();
    final etaMin = leftChars ~/ 400;
    final eta = pct >= 100
        ? '已读完'
        : pct <= 0
        ? '刚开始读'
        : etaMin >= 60
        ? '约${(etaMin / 60).ceil()}小时后读完'
        : '约${etaMin < 1 ? 1 : etaMin}分钟后读完';
    final h = _homePos;
    showBrProgressSheet(
      context,
      d: BrProgData(
        pct: pct,
        eta: eta,
        sessMin: (_sessSecs / 60).ceil(),
        notes: _hlQuotes.length,
        frac: f,
        auto: _cfg.auto,
        homeLbl: h != null && (h.ci != _pos.ci || h.pg != _pos.pg)
            ? '回到进书位置'
            : null,
      ),
      onSeek: _seek, // 弹层内已把 0~1000 滑条值换算成 0~1 分数
      onDetail: () => context.push('/read/log/${widget.bookId}'),
      onAuto: _toggleAutoQuick,
      homeProbe: () => _backPill ? '回到进书位置' : null,
      onHome: _goHome,
    );
  }

  /// 本书操作弹层（原型 sheetBrMore）：顶栏 ⋯ 的唯一入口。
  void _openMoreSheet() {
    final ctx = context;
    showBrMoreSheet(
      ctx,
      quotes: _hlQuotes.length,
      mode: _cfg.mode,
      bright: _cfg.bright,
      onToc: () => setState(() => _drawerOpen = true),
      // V1.54 批A · 屏5 入口（more.frag 行）：状态字＋开 X-Ray 段。
      xrStatus: xrStatusLabel(),
      onXray: openXrTab,
      onSearch: _openSearch,
      onQuotes: () =>
          context.push('/read/quotes', extra: widget.bookId),
      onLog: () => ctx.push('/read/log/${widget.bookId}'),
      onStat: () => ctx.push('/read/stat'),
      onDetail: () => ctx.push('/read/book/${widget.bookId}'),
      onAppearance: _openAppearance,
      onDelete: _openDelete,
      onReadSet: () => ctx.push('/read/settings?sec=5'),
      onMode: (m) {
        if (m == _cfg.mode) return;
        _setMode(m);
      },
      onBright: (v) {
        setState(() => _cfg = _cfg.copyWith(bright: v));
        unawaited(_persistPatch({'bright': v}));
        unawaited(
          ref
              .read(readRepositoryProvider)
              .setKv('read.brBright', v ? 'true' : 'false'),
        );
        _syncBright();
      },
    );
  }

  /// 阅读模式（翻页⇄滚动）：写全局默认（原型 brCfg.mode + brPersist）。
  void _setMode(String m) {
    setState(() {
      _global = _global.copyWith(mode: m);
      _applyMerged();
    });
    _savePos();
    unawaited(_persistGlobal());
    _rebuildPag();
    _syncAuto();
    _showFlash(m == 'page' ? '翻页模式' : '滚动模式');
  }

  /// 自动翻页快捷开关（进度弹层「开启/暂停」·间隔在外观弹层里调）。
  void _toggleAutoQuick() {
    final on = !_cfg.auto;
    setState(() => _cfg = _cfg.copyWith(auto: on));
    unawaited(_persistPatch({'auto': on}));
    _syncAuto();
    readToast(
      context,
      on
          ? '自动翻页已开启 · ${_cfg.autoSecs} 秒/页 · 间隔可在外观弹层调整'
          : '自动翻页已关闭',
    );
  }

  void _scrollToPara(int ci, int pi) {
    // 滚动模式：按段落序号近似定位。V1.53.1 轮4：只累加当前渲染窗口
    // （前 8 章起）内的段落，避免为算偏移 materialize 前面所有章。
    final doc = _doc;
    if (doc == null || !_scrollCtrl.hasClients) return;
    final lo = ci - 8 < 0 ? 0 : ci - 8;
    var idx = 0;
    for (var c = lo; c < ci; c++) {
      idx += doc.chapters[c].paras.length + 1;
    }
    idx += 1 + pi;
    final est = (idx * _cfg.fs * _cfg.lh * 3).clamp(
      0.0,
      _scrollCtrl.position.maxScrollExtent,
    );
    _scrollCtrl.jumpTo(est.toDouble());
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

  /// 外观弹层（原型 sheetBrAppearance · 轮5.1 起为唯一外观入口）。
  /// 保存时按作用域落库：本书＝整份补丁，全部书籍＝全局默认。
  void _openAppearance() {
    showReaderAppearance(
      context,
      current: _cfg,
      onSave: (draft, scopeBook, pickedImage) async {
        var d = draft;
        // 相册图落进应用私有目录（草稿期用临时路径预览，退出即失效）。
        if (pickedImage != null && pickedImage.isNotEmpty) {
          try {
            final dir = await getApplicationSupportDirectory();
            final bg = Directory(p.join(dir.path, 'reader_bg'));
            await bg.create(recursive: true);
            final ext = p.extension(pickedImage).isEmpty
                ? '.jpg'
                : p.extension(pickedImage);
            final dst = p.join(
              bg.path,
              'bg_${DateTime.now().millisecondsSinceEpoch}$ext',
            );
            await File(pickedImage).copy(dst);
            d = d.copyWith(bgImg: dst);
          } catch (_) {
            d = d.copyWith(bgImg: '');
          }
        }
        if (!mounted) return;
        setState(() {
          if (scopeBook) {
            _bookPatch = d.toMap();
            _applyMerged();
          } else {
            _global = d;
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
              .setKv('read.brBright', d.bright ? 'true' : 'false'),
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

  /// 本书操作弹层「删除」：两口径弹层沿用详情页同一条通道；
  /// 删除成功后本地副本已摘除，阅读页无内容可读 → 出栈（出栈即结算计时）。
  Future<void> _openDelete() async {
    final b = _book;
    if (b == null) return;
    await showBrDelSheet(context, ref, b);
    if (!mounted) return;
    final nb = await ref.read(readRepositoryProvider).bookById(widget.bookId);
    if (!mounted) return;
    if (nb == null || !nb.local || nb.epub == null) {
      Navigator.of(context).pop();
    }
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
      if (!mounted || _selController.sel != null || _drawerOpen || _doc == null) return;
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
  Timer? _pagSaveT;

  void _rebuildPag() {
    final doc = _doc;
    if (doc == null || _viewport.width <= 0) return;
    final gen = ++_pagGen;
    final l = _layout();
    unawaited(_applyPag(doc, l, gen));
  }

  List<int> _weights(EpubDoc doc) => doc.chapterCharCounts;

  /// V1.53.1 轮4（foliate 模型）：分页**按章懒排**。打开＝当前章同步实算上屏
  /// （毫秒级，一章而已），落盘表后台合并（允许部分章缺）；不再有任何整本循环
  /// ——那正是大书打开后书摘/抽屉卡顿的主线程霸占者（真机反馈⑤⑥的最终形态）。
  Future<void> _applyPag(EpubDoc doc, ReaderLayout l, int gen) async {
    final svc = ref.read(epubPreloadProvider);
    final fresh = BookPagination.lazy(_weights(doc));
    _ensure(fresh, doc, l, _pos.ci.clamp(0, doc.chapters.length - 1));
    setState(() {
      _pag = fresh;
      _clampPos();
    });
    if (svc.docsPath == null) return;
    BookPagination? tab;
    try {
      tab = await svc.loadPag(widget.bookId, l, _weights(doc));
    } catch (_) {}
    if (!mounted || gen != _pagGen || tab == null) return;
    final cur = _pag;
    if (cur == null) return;
    for (var i = 0; i < cur.pages.length && i < tab.pages.length; i++) {
      if (cur.pages[i] == null) cur.pages[i] = tab.pages[i];
    }
    setState(_clampPos);
  }

  /// 指定章未排版则实算（同步读快照章 + TextPainter，单章毫秒级）。
  void _ensure(BookPagination pag, EpubDoc doc, ReaderLayout l, int ci) {
    if (ci < 0 || ci >= doc.chapters.length || pag.laidOut(ci)) return;
    pag.setChapter(ci, EpubPager.layoutChapter(doc.chapters[ci].paras, l));
    _pagSaveTick();
  }

  /// 确保当前章已排版（翻页/跳章/ seek 落章后统一走这里）。
  void _ensureCur() {
    final doc = _doc, pag = _pag;
    if (doc == null || pag == null) return;
    _ensure(pag, doc, _layout(), _pos.ci.clamp(0, doc.chapters.length - 1));
  }

  /// 分页表防抖落盘（连翻多章后 2s 写一次，不逐章打盘）。
  void _pagSaveTick() {
    _pagSaveT?.cancel();
    _pagSaveT = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      final svc = ref.read(epubPreloadProvider);
      final pag = _pag;
      if (svc.docsPath != null && pag != null) {
        unawaited(svc.savePag(widget.bookId, _layout(), pag));
      }
    });
  }

  ReaderLayout _layout() => ReaderLayout(
    width: _viewport.width,
    height: _viewport.height,
    fs: _cfg.fs,
    lh: _cfg.lh,
    ls: _cfg.ls,
    mar: _cfg.mar,
    font: _cfg.font,
    indent: _cfg.indent,
  );


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
    final doc = _doc;
    if (_cfg.mode == 'page' && pag != null && doc != null) {
      _ensure(pag, doc, _layout(), h.ci); // 命中章未排版先实算，再定位段
    }
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

  /// 左右滑动翻页（无选区、无抽屉时才挂）。
  void _onSwipe(DragEndDetails e) {
    final v = e.velocity.pixelsPerSecond.dx;
    final off = e.primaryVelocity ?? 0;
    if (off < -150 || (v < 0 && v < -0.4)) {
      _flip(1);
    } else if (off > 150 || (v > 0 && v > 0.4)) {
      _flip(-1);
    }
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
    final th = brThemeResolved(_cfg);
    final bar = brBarOf(th.$2, th.$3);
    // 出页后的结算提示要用还活着的 messenger（离开前抓住）。
    _ms ??= ScaffoldMessenger.of(context);
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
              if (_selController.sel != null) {
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
          // 轮5①：有选区时**不挂**滑动翻页识别器——否则手柄横向拖动会在手势竞技场
          // 里被父级 HorizontalDragGestureRecognizer 抢先认领，手柄拖不动（真机同理）。
          onHorizontalDragEnd: _selController.sel == null && !_drawerOpen ? _onSwipe : null,
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
                  key: _stackKey,
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
                    Positioned.fill(
                      child: RepaintBoundary(
                        key: _contentBoundaryKey,
                        child: BrBackdrop(
                          key: const ValueKey('brStage'),
                          cfg: _cfg,
                          base: th.$2,
                          child: _stage(th),
                        ),
                      ),
                    ),
                    // 亮度遮罩（V1.53 轮3：模拟系统亮度，只压正文不压 chrome）。
                    if (_cfg.lum < 100)
                      Positioned.fill(
                        key: const ValueKey('brLumMask'),
                        child: IgnorePointer(
                          child: ColoredBox(
                            color: Colors.black.withValues(
                              alpha: (100 - _cfg.lum) / 100 * .55,
                            ),
                          ),
                        ),
                      ),
                    if (_doc != null && _err == null) ...[
                      if (_chrome) _topBar(bar),
                      if (_chrome && _pag != null) _bottomBar(bar, size),
                      if (_flash != null) _flashBar(bar),
                      if (_selController.sel != null) ...brSelLayer(
                        size: size,
                        hlPop: _hlPop,
                        place: _selBarPlace(size),
                        skin: brSelSkinOf(th.$2),
                        onCopy: _actCopy,
                        onToggleHl: () => setState(() => _hlPop = !_hlPop),
                        onQuote: _actQuote,
                        onDict: _actDict,
                        onTts: () => readToast(context, '朗读能力规划中 · 暂未上线'),
                        onAi: _actAi,
                        onShare: _actShare,
                        onColor: _addHl,
                        onDelete: _delHl,
                        onXray: xrSelToLearn,
                        tools: _brSelTools,
                        handle: (end) =>
                            brHandleWidget(
                              end,
                              _selAnchor(end),
                              (g) {
                                _dragSel(end: end, global: g);
                                _loupeAtEnd(end);
                              },
                              onDragStart: (g) => _loupeAtEnd(end),
                              onDragEnd: () => _setLoupe(null),
                            ),
                      ),
                      // V1.53.2 选区放大镜：拖动手柄期间跟随手指显示。
                      if (_loupeFocal != null)
                        ReaderLoupe(
                          image: _loupeImage,
                          focal: _loupeFocal!,
                          contentLogicalSize: size,
                          stackSize: size,
                        ),
                      // 轮5.2①：正文不再悬浮任何胶囊——「回到进书位置」在进度弹层，
                      // 「回到刚才在读」在目录抽屉（跳章返回）。
                    ],
                    if (_drawerOpen && _doc != null && _pag != null && _book != null)
                      ReaderTocDrawer(
                        state: _drState,
                        book: _book!,
                        doc: _doc!,
                        pager: _pag!,
                        ci: _pos.ci,
                        pg: _pos.pg,
                        onGoto: _gotoChapter,
                        onXrJump: xrJumpTo,
                        backLbl: _jumpFrom?.title,
                        onBackJump: _jumpFrom == null ? null : _goBackJump,
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

}
