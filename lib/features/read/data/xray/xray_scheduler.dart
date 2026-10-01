/// X-Ray 解析调度器（需求 V1.54 · 设计书 §3/§8 · 交棒话术批A-4）
///
/// 三条骨架口径：
/// - **引擎跑 isolate**（§3 约束）：本文件的 [_IsoXrayWorker] 与主 isolate 走
///   「主线程喂章 ⇄ worker 逐章回执」的乒乓协议；章内先低频剪枝的内存护栏在
///   引擎侧已有（§8），这里只保证**按章流式**（勿整本驻留：主线程每章现取段文本）。
/// - **全局单飞**：同一时刻至多一路解析；开新书的解析请求会先暂停当前任务
///   （断点已逐章落库），优先级 开书 > 分页 > X-Ray——喂每一章前查 [busyProbe]，
///   预载/预热在跑就让路。
/// - **前台跑 · 退后台自动暂停 · 一键恢复**（§8 一期不做后台续跑）：暂停只是
///   停止喂章，worker isolate 原地驻留；进程被杀后 worker 随进程消亡，
///   「继续生成」按 processed_ch 之后重跑区间（引擎统计全局性决定断点是
///   展示语义，重跑走 upsert 幂等，不叠加出场）。
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart' show md5;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../../core/database/schema/xray.dart' as xs;
import '../../../../core/logging/app_log.dart';
import '../../domain/book.dart';
import '../epub_doc.dart';
import 'xray_dao.dart';
import 'xray_engine.dart';
import 'xray_lexicon.dart';

/// 文件内容指纹（F9 归属键）。整读进一次性 isolate 计算：22MB 书峰值 ≈45MB 短驻留，
/// 不在主 isolate 读大文件（FakeAsync 测试经 md5Hook 注入，永不走到这里）。
Future<String> xrayFileMd5(String path) => Isolate.run(() async {
      final bytes = await File(path).readAsBytes();
      return md5.convert(bytes).toString();
    });

/// 一次解析任务的输入（全部纯数据，可跨 isolate 发送）。
class XrayJobSpec {
  const XrayJobSpec({
    required this.totalCh,
    required this.rangeFrom,
    required this.rangeTo,
    required this.totalChars,
    required this.sens,
    required this.added,
    required this.forbidden,
    required this.tocTitles,
    this.word,
    this.wordType,
  });

  final int totalCh;
  final int rangeFrom;
  final int rangeTo;
  final int totalChars;
  final double sens;
  final Set<String> added;
  final Set<String> forbidden;
  final List<String> tocTitles;

  /// 批B 加词补扫模式（F8①）：非空＝不走引擎榜单，只统计该词全书出场（XrayWordScan）。
  final String? word;
  final String? wordType;
}

/// 加词补扫累加器（纯计算·单实现两处用：worker isolate 与测试假通道）。
/// 语境模式检测（§7 回流建议）：出场点后跟 ≤2 字命中称谓词表 → 记模式票；
/// 占比 ≥30% 才产出建议（阈值口径同设计书「≥30% 命中某模式」）。
class XrayWordScan {
  XrayWordScan({
    required this.word,
    required this.type,
    required this.bank,
    this.maxAnchors = 200,
  });

  final String word;
  final String type;
  final XrayWordBank bank;

  /// 补扫锚点保留上限（用户词通常是低频专有词；超限时保前 N 条锚点、计数照加）。
  final int maxAnchors;

  int n = 0;
  final Set<int> _chs = {};
  final List<XrayMention> _m = [];
  final Map<String, int> _pat = {};

  void addChapter(int ci, List<String> paras) {
    for (var pi = 0; pi < paras.length; pi++) {
      final text = paras[pi];
      var idx = 0;
      while (true) {
        final at = text.indexOf(word, idx);
        if (at < 0) break;
        n++;
        _chs.add(ci);
        final after = at + word.length;
        final tail = text.substring(
            after, after + 2 < text.length ? after + 2 : text.length);
        for (final t in bank.titles) {
          if (t.isNotEmpty && tail.startsWith(t)) {
            _pat[t] = (_pat[t] ?? 0) + 1;
            break;
          }
        }
        if (_m.length < maxAnchors) {
          final s = at - 30 < 0 ? 0 : at - 30;
          final e = text.length < after + 40 ? text.length : after + 40;
          _m.add(XrayMention(ci, pi,
              '${s > 0 ? '…' : ''}${text.substring(s, e)}${e < text.length ? '…' : ''}'));
        }
        idx = at + word.length;
      }
    }
  }

  /// [title, pct]：出场上下文 ≥30% 命中同一称谓形态时产出（否则 null）。
  List<Object?>? get pattern {
    if (_pat.isEmpty || n == 0) return null;
    final best = _pat.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final pct = (best.value * 100 / n).round();
    return pct >= 30 ? [best.key, pct] : null;
  }

  Map<String, Object?> payload() => {
        'name': word,
        'type': type,
        'n': n,
        'chs': _chs.length,
        'score': 1.0,
        'ch': 0,
        'toc': 0,
        'al': <String>[],
        'm': [
          for (final m in _m) [m.ch, m.para, m.snippet],
        ],
        'pat': pattern,
      };
}

/// 建议规则卡数据（§7 回流：采纳进全局表 / 忽略）。
class XraySuggestion {
  const XraySuggestion({
    required this.word,
    required this.title,
    required this.pct,
  });
  final String word;
  final String title;
  final int pct;
}

/// worker → 调度器的四类事件（逐章回执即心跳：进度/暂停/取消都从这里驱动）。
class XrayWorkerEvents {
  const XrayWorkerEvents({
    required this.onChapterDone,
    required this.onWantAnchor,
       required this.onResult,
    required this.onFail,
  });
  final void Function(int ci) onChapterDone;
  final void Function(int ci) onWantAnchor;
  final void Function(List<Map<String, Object?>> ents) onResult;
  final void Function(String message) onFail;
}

/// 计算通道抽象：生产＝[_IsoXrayWorker]；测试＝同 isolate 直跑引擎（禁真 isolate，
/// FakeAsync 教训）。工厂注入是这里唯一的缝。
abstract class XrayWorker {
  void feedCollect(int ci, List<String> paras);
  void feedAnchor(int ci, List<String> paras);
  void finishCollect();
  void cancel();
}

typedef XrayWorkerFactory = Future<XrayWorker> Function(
    XrayJobSpec spec, XrayWorkerEvents ev);

/// 面板/角标共用的运行态快照。
class XrayLive {
  XrayLive({
    required this.bookId,
    required this.md5,
    required this.totalCh,
    required this.rangeFrom,
    required this.rangeTo,
  });

  final String bookId;
  final String md5;
  final int totalCh;
  final int rangeFrom;
  final int rangeTo;

  bool running = false;
  int doneCh = 0; // 本次任务已完成章数（区间内计数）
  String? error;

  int get pct {
    final span = rangeTo - rangeFrom + 1;
    if (span <= 0) return 0;
    return (doneCh * 100 / span).round().clamp(0, 100);
  }
}

/// X-Ray 任务调度器（ChangeNotifier：面板头 + 书架角标共用）。
class XrayScheduler extends ChangeNotifier {
  XrayScheduler({
    required this.dao,
    required this.loadDoc,
    this.busyProbe,
    this.md5Hook,
    XrayWorkerFactory? workerFactory,
    this.sens = 1.0,
  }) : workerFactory = workerFactory ?? _IsoXrayWorker.spawn;

  final XrayDao dao;

  /// 取整本书文档（预载服务口径：内存缓存→预热→快照→现解；测试注入直构 EpubDoc）。
  final Future<EpubDoc?> Function(Book book) loadDoc;

  /// 全局单飞让路探针：返回 true＝该书预载/预热在跑，先喂它。
  final bool Function(String bookId)? busyProbe;

  /// 测试注入：替换文件 md5 计算（FakeAsync 禁真 IO）。
  final Future<String> Function(String path)? md5Hook;

  /// 索引灵敏度倍率（§4 设置项「低/中/高」→ 1.6/1.0/0.7；一期默认中，设置页在批C 接）。
  final double sens;

  final XrayWorkerFactory workerFactory;

  final Map<String, XrayRun> _runs = {};
  XrayRun? _cur;

  /// 建议规则卡（bookId → 未消化的回流建议；采纳/忽略即清）。
  final Map<String, XraySuggestion> _suggestions = {};

  XraySuggestion? suggestion(String bookId) => _suggestions[bookId];

  void dismissSuggestion(String bookId) {
    if (_suggestions.remove(bookId) != null) notifyListeners();
  }

  /// 用户层直改（加/删/合并走 DAO 后调用）：数据修订 + 面板刷新。
  void notifyDataChanged() => _bumpRevision();

  /// 终态修订号：解析完成/失败/重置时自增。provider 监听它决定是否重取词条数据
  /// （逐章进度不触发词条重查，只驱动面板头）。
  int get revision => _revision;
  int _revision = 0;

  /// 终态变化外联口（providers 用它 bump xrayRevisionProvider·装配时挂）。
  void Function()? onRevised;

  void _bumpRevision() {
    _revision++;
    onRevised?.call();
    notifyListeners();
  }

  /// 批B 加词全书补扫（F8①）：秒级轻扫（XrayWordScan 单实现），只回填该词出场，
  /// 不动解析任务态；≥30% 称谓形态命中时挂出建议规则卡。
  Future<void> scanWord({
    required Book book,
    required String md5,
    required String word,
    required String type,
  }) async {
    final existing = _runs[book.id];
    if (existing != null && existing.live.running && existing.word == word) return;
    final doc = await loadDoc(book);
    if (doc == null || doc.chapters.isEmpty) return;
    final run = XrayRun(
      bookId: book.id,
      book: book,
      live: XrayLive(
          bookId: book.id,
          md5: md5,
          totalCh: doc.chapters.length,
          rangeFrom: 0,
          rangeTo: doc.chapters.length - 1),
      doc: doc,
      word: word,
      wordType: type,
    );
    _runs[book.id] = run;
    _cur = run;
    unawaited(run._drive(this));
    notifyListeners();
  }

  XrayLive? live(String bookId) => _runs[bookId]?.live;

  /// 该书是否有活体 worker（进程内暂停后可原地续喂）。
  bool hasWorker(String bookId) => _runs[bookId]?._worker != null;

  /// 冷启动收尸（provider 建出来就跑一次）：上个进程留下的 `running` 行转 `pause`。
  Future<void> reconcileStale() async {
    try {
      final n = await dao.reapStaleRunning();
      if (n > 0) {
        AppLog.add('X-Ray 收尸：$n 条中断任务已标记为已暂停');
        notifyListeners();
      }
    } catch (e) {
      // catch-ok: 收尸失败只是少一次状态纠正（面板仍按库内旧态渲染），不该拖垮首次读。
      AppLog.add('X-Ray 收尸失败: $e', level: LhLevel.warn);
    }
  }

  // ---------------------------------------------------------------- md5 补票

  /// 内容指纹（批A-3「MD5 接线补票」）：有则直返；无则对私有副本懒补算。
  /// 路径不可读/测试假路径＝返回 null（调用方按「未解析」空态渲染，绝不抛进 UI）。
  Future<String?> ensureMd5(Book book) async {
    try {
      final have = await dao.bookMd5(book.id);
      if (have != null && have.isNotEmpty) return have;
      final ep = book.epub;
      if (ep == null || ep.path.isEmpty) return null;
      final m = await (md5Hook ?? xrayFileMd5)(ep.path);
      await dao.setBookMd5(book.id, m);
      return m;
    } catch (e) {
      // 路径不可读/测试假路径＝返回 null 交 UI 空态；留痕便于真机排查懒补算失败。
      AppLog.add('指纹懒补算失败 书#${book.id}: $e', level: LhLevel.warn);
      return null;
    }
  }

  // ------------------------------------------------------------------ 生命周期

  /// 启动一次解析（from..to 为**绝对章号闭区间**）。同书在跑＝幂等直返；
  /// 别书在跑＝先暂停它（断点已落库），实现全局单飞。
  Future<void> start({
    required Book book,
    required String md5,
    required int from,
    required int to,
  }) async {
    final existing = _runs[book.id];
    if (existing != null && existing.live.running) return;
    if (_cur != null && _cur!.live.running && _cur!.bookId != book.id) {
      _cur!.pause();
    }
    final doc = await loadDoc(book);
    if (doc == null || doc.chapters.isEmpty) {
      final failed = XrayRun(
          bookId: book.id,
          book: book,
          live: XrayLive(
              bookId: book.id,
              md5: md5,
              totalCh: 0,
              rangeFrom: from,
              rangeTo: to)
            ..error = '书本内容不可用 · 无法解析');
      _runs[book.id] = failed;
      notifyListeners();
      return;
    }
    final total = doc.chapters.length;
    final f = from.clamp(0, total - 1);
    final t = to.clamp(f, total - 1);
    final run = XrayRun(
      bookId: book.id,
      book: book,
      live: XrayLive(
          bookId: book.id,
          md5: md5,
          totalCh: total,
          rangeFrom: f,
          rangeTo: t),
      doc: doc,
    );
    _runs[book.id] = run;
    _cur = run;
    unawaited(run._drive(this));
    notifyListeners();
  }

  /// 暂停当前任务（退后台/切书共用）。worker 驻留，回前台一键恢复。
  void pauseBook(String bookId) {
    _runs[bookId]?.pause();
    if (_cur?.bookId == bookId) notifyListeners();
  }

  /// 同库内部类（XrayRun）驱动刷新的合法通道（notifyListeners 是 protected）。
  void ping() => notifyListeners();

  /// 前台恢复：有活体 worker＝原地续喂；没有（进程重启后）＝从区间起点重跑。
  Future<void> resume(Book book, String md5) async {
    final run = _runs[book.id];
    if (run != null && run._worker != null) {
      run.resumeFeeding();
      notifyListeners();
      return;
    }
    final task = await dao.task(md5);
    await start(
      book: book,
      md5: md5,
      from: 0,
      to: (task?.totalCh ?? 1) - 1,
    );
  }

  /// 中断本次解析（不删已产出数据；任务态落 canceled）。
  void cancel(String bookId) {
    _runs[bookId]?.cancel();
    if (_cur?.bookId == bookId) notifyListeners();
  }

  /// 重置索引（F3）：杀任务 + 清该书三层数据（用户词典不动，DAO 内已钉）。
  Future<void> reset(String bookId, String md5) async {
    _runs[bookId]?.cancel();
    _runs.remove(bookId);
    if (_cur?.bookId == bookId) _cur = null;
    await dao.resetBook(md5);
    _bumpRevision();
    notifyListeners();
  }

  /// 退后台：正在跑的自动暂停（§8；断点已逐章落库，无数据损失）。
  void noteBackground() {
    final c = _cur;
    // 每次退后台留一条「有没有任务/在不在跑」的锚点：真机 16:27 与 16:35 两轮
    // 既没有「自动暂停」也没有「未执行」留痕，无法区分「回调没到」与「到了但
    // 调度器里没有活体任务」（= 实例不是同一个）。
    AppLog.add('X-Ray 退后台检查 任务=${c == null ? '无' : '${c.bookId}·${c.live.running ? "在跑" : "未在跑"}'}');
    if (c != null && c.live.running) {
      AppLog.add('X-Ray 退后台自动暂停 书#${c.bookId}');
      c.pause();
    }
  }

  @override
  void dispose() {
    for (final r in _runs.values) {
      r._worker?.cancel();
    }
    super.dispose();
  }
}

/// 一路解析任务的全部状态。调度语义集中在 [_drive]/[_onChapterDone]/[_pumpNext]，
/// 外部只通过 [XrayScheduler] 的方法触达（暂停/恢复/取消都可从 UI 线程同步调）。
class XrayRun {
  XrayRun({
    required this.bookId,
    required this.book,
    required this.live,
    this.doc,
    this.word,
    this.wordType,
  });

  final String bookId;
  final Book book;
  final XrayLive live;
  final EpubDoc? doc;

  /// 非空＝加词补扫运行（不落 xray_task、结果走 applyScanResult）。
  final String? word;
  final String? wordType;

  bool get isScan => word != null;

  XrayWorker? _worker;
  bool _paused = false;
  bool _cancelled = false;
  bool _collecting = true;
  bool _inFlight = false;
  int _next = -1;
  Future<void> _persistTail = Future.value();

  /// 本次运行耗时（release 无 logcat 通道，用时/词条数只能进自建日志）。
  final Stopwatch _watch = Stopwatch();

  /// 逐章进度落库串行尾巴：sqflite 并发写不保证顺序，processed_ch 必须单调。
  void _queuePersist(Future<void> Function() op) {
    _persistTail = _persistTail.then((_) => op().catchError((_) {}));
  }

  void pause() {
    if (!live.running) return;
    _paused = true;
    // 暂停必须把「在跑」标记一起落回：worker 驻留但不再喂章，若留着 running，
    // 面板头会一直显示「解析中 x%」且按 `!running` 门控的「继续生成」钮永远不出现
    // ——真机退后台回前台就成了没有出口的死状态（2026-10-01 15:49 撞实）。
    live.running = false;
    _queuePersist(() => schedulerDao.patchTaskProgress(
        md5: live.md5, processedCh: live.doneCh, status: xs.xrayStatusPause));
    _sched.ping();
  }

  // XrayRun 需要触达 dao/notify：由调度器在 _drive 里注入（避免到处传参）。
  XrayScheduler? _s;
  XrayScheduler get _sched => _s!;
  XrayDao get schedulerDao => _sched.dao;

  void resumeFeeding() {
    if (!_paused || _cancelled) return;
    _paused = false;
    live.running = true;
    _queuePersist(() => schedulerDao.patchTaskProgress(
        md5: live.md5, processedCh: live.doneCh, status: xs.xrayStatusRunning));
    _sched.ping();
    if (!_inFlight) _pumpNext();
  }

  void cancel() {
    if (isScan || _cancelled || _s == null) {
      // 未起过 _drive 的失败占位任务：只清本地标记，没有落库通道也不需要落。
      _cancelled = true;
      live.running = false;
      return;
    }
    _cancelled = true;
    live.running = false;
    _worker?.cancel();
    _worker = null;
    _queuePersist(() => schedulerDao.patchTaskProgress(
        md5: live.md5, processedCh: live.doneCh, status: xs.xrayStatusCanceled));
  }

  Future<void> _drive(XrayScheduler s) async {
    _s = s;
    final d = doc!;
    try {
      final layer = await s.dao.userLayer(live.md5);
      final toc = d.toc.isNotEmpty
          ? [for (final t in d.toc) t.label]
          : [for (final c in d.chapters) c.title];
      final spec = XrayJobSpec(
        totalCh: live.totalCh,
        rangeFrom: live.rangeFrom,
        rangeTo: live.rangeTo,
        totalChars: d.totalChars,
        sens: s.sens,
        added: layer.added,
        forbidden: layer.forbidden,
        tocTitles: toc,
        word: word,
        wordType: wordType,
      );
      if (isScan) {
        // 补扫不动任务态：跑完直接回填该词。
        live.running = true;
        _next = 0;
        _watch
          ..reset()
          ..start();
        AppLog.add('X-Ray 补扫开始 书#$bookId 词「$word」共 ${live.totalCh} 章');
        _worker = await s.workerFactory(spec, XrayWorkerEvents(
          onChapterDone: _onChapterDone,
          onWantAnchor: _onWantAnchor,
          onResult: _onResult,
          onFail: _onFail,
        ));
        _pumpNext();
        return;
      }
      await s.dao.upsertTask(
        md5: live.md5,
        totalCh: live.totalCh,
        rangeStart: live.rangeFrom,
        rangeEnd: live.rangeTo,
        status: xs.xrayStatusRunning,
        processedCh: live.doneCh,
      );
      live.running = true;
      _next = live.rangeFrom;
      _watch
        ..reset()
        ..start();
      AppLog.add('X-Ray 解析开始 书#$bookId 章 ${live.rangeFrom}..${live.rangeTo}'
          '/${live.totalCh} · ${d.totalChars} 字');
      _worker = await s.workerFactory(spec, XrayWorkerEvents(
        onChapterDone: _onChapterDone,
        onWantAnchor: _onWantAnchor,
        onResult: _onResult,
        onFail: _onFail,
      ));
      _pumpNext();
    } catch (e) {
      // catch-ok: 异常转交 _onFail——任务态 failed + live.error + 面板中断弹层，
      // 不是静默吞噬，是**上报路径本身**。
      _onFail('$e');
    }
  }

  /// 喂下一章前的三道闸：已取消 / 被暂停 / 全局让路（预载在跑）。
  void _pumpNext() {
    if (_cancelled || _paused || _inFlight) return;
    if (_sched.busyProbe?.call(bookId) ?? false) {
      // 让路：50ms 后再试（开书与分页优先，§8）。
      Timer(const Duration(milliseconds: 50), () {
        if (!_cancelled) _pumpNext();
      });
      return;
    }
    final d = doc!;
    try {
      if (_collecting) {
        if (_next > live.rangeTo) {
          _collecting = false;
          _worker!.finishCollect();
          return;
        }
        _inFlight = true;
        _worker!.feedCollect(_next, _paras(d, _next));
      } else {
        if (_next >= live.totalCh) return; // 锚点遍越界：worker 侧自行定稿
        _inFlight = true;
        _worker!.feedAnchor(_next, _paras(d, _next));
      }
    } catch (e) {
      // catch-ok: 同上——统一走 _onFail 落 failed 态并弹层报出。
      _inFlight = false;
      _onFail('$e');
    }
  }

  static List<String> _paras(EpubDoc d, int ci) => [
        for (final p in d.chapters[ci].paras)
          if (p.text.isNotEmpty) p.text,
      ];

  void _onChapterDone(int ci) {
    _inFlight = false;
    if (_cancelled) return;
    if (_collecting) {
      live.doneCh = ci - live.rangeFrom + 1;
      _next = ci + 1;
      _queuePersist(() => _sched.dao.patchTaskProgress(
          md5: live.md5, processedCh: ci + 1, status: xs.xrayStatusRunning));
      _sched.ping();
      _pumpNext();
    } else {
      _next = ci + 1;
      _pumpNext();
    }
  }

  /// 第二遍（术语锚点回填）：worker 逐章索取，全书章号顺序推进，越界即由
  /// worker 侧定稿发 result。
  ///
  /// **锚点遍的 worker 回执只有 'w' 没有 'd'**（真 isolate 协议，见 `_entry`），
  /// 所以在飞标记必须在这里落回——否则第一章之后 `_pumpNext` 永远直返，
  /// 主线程等 result、worker 等下一章，任务卡在「解析中 100%」且零词条
  /// （2026-10-01 真机首跑撞实；假通道此前自走锚点遍，把这段掩盖成了死代码）。
  void _onWantAnchor(int ci) {
    if (_cancelled) return;
    _inFlight = false;
    _collecting = false;
    _next = ci;
    _pumpNext();
  }

  void _onResult(List<Map<String, Object?>> ents) {
    _worker = null;
    live.running = false;
    if (isScan && ents.isNotEmpty) {
      final m0 = ents.first;
      unawaited(() async {
        try {
          final ent = await _sched.dao.entityByName(live.md5, m0['name'] as String);
          if (ent != null) {
            await _sched.dao.applyScanResult(
              md5: live.md5,
              word: ent.name,
              entityId: ent.id,
              n: m0['n'] as int,
              chs: m0['chs'] as int,
              anchors: [
                for (final a in (m0['m'] as List))
                  XrayMention((a as List)[0] as int, (a)[1] as int,
                      (a)[2] as String?),
              ],
            );
          }
          AppLog.add('X-Ray 补扫完成 书#$bookId 词「${m0['name']}」'
              '出场 ${m0['n']} 处 · 用时 '
              '${(_watch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');
          final pat = m0['pat'];
          if (pat is List && pat.length == 2) {
            _sched._suggestions[bookId] = XraySuggestion(
              word: m0['name'] as String,
              title: pat[0] as String,
              pct: pat[1] as int,
            );
          }
        } catch (e) {
          // catch-ok: 补扫失败写进 live.error（面板头显示「上次失败」），非吞掉。
          live.error = '$e';
        }
        _sched._bumpRevision();
      }());
      return;
    }
    unawaited(() async {
      try {
        await _persistTail;
        await _sched.dao.writeRunResult(md5: live.md5, rows: [
          for (final m in ents) XrayWriteEntity.fromMap(m),
        ]);
        await _sched.dao.upsertTask(
          md5: live.md5,
          totalCh: live.totalCh,
          rangeStart: live.rangeFrom,
          rangeEnd: live.rangeTo,
          status: xs.xrayStatusSuccess,
          processedCh: live.totalCh,
        );
        AppLog.add('X-Ray 解析完成 书#$bookId 词条 ${ents.length} 枚 · 用时 '
            '${(_watch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');
        _sched._bumpRevision();
        _sched.ping();
      } catch (e) {
        // catch-ok: 落库链异常同样转 _onFail 上报（任务态 failed + 弹层）。
        _onFail('$e');
      }
    }());
  }

  void _onFail(String message) {
    AppLog.add('X-Ray 解析失败 书#$bookId 停在第 ${live.doneCh} 章: $message',
        level: LhLevel.error);
    _worker?.cancel();
    _worker = null;
    _cancelled = true;
    live.running = false;
    live.error = message;
    unawaited(() async {
      try {
        await _persistTail;
        if (!isScan) {
          await _sched.dao.patchTaskProgress(
              md5: live.md5, processedCh: live.doneCh, status: xs.xrayStatusFailed);
        }
      } catch (_) {
        // catch-ok: failed 态写库自身失败无处可报（DB 已异常）；仍会 bump 刷新 UI。
      }
      _sched._bumpRevision();
      _sched.ping();
    }());
  }
}

// ============================================================ isolate worker

/// 真·计算通道：`Isolate.spawn` 常驻 worker，主线程按章喂、worker 按章回执。
/// 消息协议（Map 直发，全为纯数据）：
///   main→w：{'t':'c',ci,p} 收集章 / {'t':'a',ci,p} 锚点章 / {'t':'e'} 收集结束 / {'t':'x'} 杀
///   w→main：首消息=worker 收件端口，随后 {'t':'d',ci} {'t':'w',ci} {'t':'r',ents} {'t':'f',m}
class _IsoXrayWorker implements XrayWorker {
  _IsoXrayWorker._(this._toWorker, this._port);

  final SendPort _toWorker;
  final ReceivePort _port;
  StreamSubscription<Object?>? _sub;
  bool _dead = false;

  static Future<XrayWorker> spawn(XrayJobSpec spec, XrayWorkerEvents ev) async {
    final assets = await _loadAssets();
    final mainPort = ReceivePort();
    final errors = ReceivePort();
    final booted = Completer<SendPort>();
    late StreamSubscription<Object?> sub;
    Isolate.spawn(
      _entry,
      _XrBoot(
        mainSend: mainPort.sendPort,
        assets: assets,
        spec: spec,
      ),
      debugName: 'xray-engine',
      // 引擎炸了（坏词表/坏文本）必须能回到 UI，不吞栈。
      onError: errors.sendPort,
      errorsAreFatal: true,
    );
    sub = mainPort.listen((m) {
      if (m is SendPort) {
        if (!booted.isCompleted) booted.complete(m);
        return;
      }
      if (m is! Map) return;
      switch (m['t']) {
        case 'd':
          ev.onChapterDone(m['ci'] as int);
        case 'w':
          ev.onWantAnchor(m['ci'] as int);
        case 'r':
          ev.onResult((m['ents'] as List).cast<Map<String, Object?>>());
        case 'f':
          ev.onFail('${m['m']}');
      }
    });
    final w = _IsoXrayWorker._(await booted.future, mainPort);
    w._sub = sub;
    errors.listen((m) {
      // 未捕获异常（errorsAreFatal）→ onFail 一次即终结；后续消息被 _dead 吞掉。
      ev.onFail('解析进程异常: $m');
    });
    return w;
  }

  void _send(Map<String, Object?> m) {
    if (_dead) return;
    _toWorker.send(m);
  }

  @override
  void feedCollect(int ci, List<String> paras) => _send({'t': 'c', 'ci': ci, 'p': paras});

  @override
  void feedAnchor(int ci, List<String> paras) => _send({'t': 'a', 'ci': ci, 'p': paras});

  @override
  void finishCollect() => _send({'t': 'e'});

  @override
  void cancel() {
    if (_dead) return;
    _dead = true;
    _send({'t': 'x'});
    unawaited(_sub?.cancel());
    _port.close();
  }
}

class _XrBoot {
  _XrBoot({
    required this.mainSend,
    required this.assets,
    required this.spec,
  });
  final SendPort mainSend;
  final Map<String, String> assets;
  final XrayJobSpec spec;
}

/// worker 主循环（常驻 isolate 入口；只做纯计算，零 IO）。
void _entry(_XrBoot boot) {
  final rp = ReceivePort();
  boot.mainSend.send(rp.sendPort);
  final spec = boot.spec;
  final bank = XrayWordBank.parse(boot.assets);
  final engine = XrayEngine(
    bank: bank,
    book: XrayUserLayer(added: spec.added, forbidden: spec.forbidden),
    totalChars: spec.totalChars,
    sens: spec.sens,
  );
  List<XrayEntity>? keep;
  XrayWordScan? scanner;  void deliver() {
    boot.mainSend.send({'t': 'r', 'ents': _payload(keep!)});
    Isolate.exit();
  }

  /// 锚点回填遍：逐章向主线程索取（勿整本驻留，§8）；走完即定稿。
  void anchorFrom(int ci) {
    if (ci >= spec.totalCh) {
      deliver();
      return;
    }
    boot.mainSend.send({'t': 'w', 'ci': ci});
  }

  rp.listen((m) {
    if (m is! Map) return;
    if (spec.word != null) {
      // 批B 加词补扫：不建榜单，只累加该词出场（协议消息与解析共用）。
      scanner ??= XrayWordScan(
          word: spec.word!, type: spec.wordType ?? 'term', bank: bank);
      switch (m['t']) {
        case 'c':
          final ci = m['ci'] as int;
          scanner!.addChapter(ci, (m['p'] as List).cast<String>());
          boot.mainSend.send({'t': 'd', 'ci': ci});
        case 'e':
          boot.mainSend
              .send({'t': 'r', 'ents': [scanner!.payload()]});
          Isolate.exit();
        case 'x':
          rp.close();
          Isolate.exit();
      }
      return;
    }
    switch (m['t']) {
      case 'c':
        final ci = m['ci'] as int;
        engine.runChapter(
            XrayChapter(idx: ci, paras: (m['p'] as List).cast<String>()));
        boot.mainSend.send({'t': 'd', 'ci': ci});
      case 'e':
        // finish 只许一次：定榜结果存下来，锚点遍走完后直接投递。
        keep = engine.finish(tocTitles: spec.tocTitles);
        if (engine.needsAnchorPass) {
          anchorFrom(0);
        } else {
          deliver();
        }
      case 'a':
        final ci = m['ci'] as int;
        engine.anchorPass(
            XrayChapter(idx: ci, paras: (m['p'] as List).cast<String>()));
        anchorFrom(ci + 1);
      case 'x':
        rp.close();
        Isolate.exit();
    }
  });
}

/// 定稿实体 → 可跨 isolate 的平铺 Map（DAO 侧 XrayWriteEntity.fromMap 还原）。
List<Map<String, Object?>> _payload(List<XrayEntity> ents) => [
      for (final e in ents)
        {
          'name': e.name,
          'type': e.type.code,
          'n': e.n,
          'chs': e.chs,
          'score': e.score,
          'ch': e.channels,
          'toc': e.tocFlag ? 1 : 0,
          'al': e.aliases.toList(),
          'm': [
            for (final mm in e.mentions) [mm.ch, mm.para, mm.snippet],
          ],
        },
    ];

Map<String, String>? _assetsCache;

/// 词表资产只在生产首次解析时读一次（widget 测试走 fake 工厂，永不触发）。
Future<Map<String, String>> _loadAssets() async => _assetsCache ??= {
      for (final n in XrayWordBank.assetNames)
        n: await rootBundle.loadString('assets/xray/dicts/$n'),
    };
