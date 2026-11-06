part of 'reader_page.dart';

// 二期批5 · F5-3／F5-6：滚动模式的「真实位置」与手感统一。
//
// 旧行为：滚动模式没有位置概念——切过来是列表顶端或按段数×行高瞎估；滚完不写回；
// 退出/切章/切模式都用上一帧的 `_pos` 写进度 ⇒ 换模式、重进、记录阅读位置全错位。
//
// 这里的唯一事实源＝**当前可见首段**（原文锚点＝章号+段号）：
//   · 滚动中每 500ms 节流写回，停笔（ScrollEnd）立即写回；
//   · 进/切到滚动模式先定位到当前页首段；
//   · 退出/切章/切模式一律先 flush 再读位置。
// 读位置靠「行的 reveal 偏移」而不是像素估算：`getOffsetToReveal` 给出的偏移与
// 视口坐标系无关，滚动/缩放/换行都自洽；没建出来的行不参与（懒列表只认已建行）。

/// F5-6：手动翻页与自动翻页**同一条动效**（曲线与时长只有这一份）。
const Duration kBrScrollFlipMs = Duration(milliseconds: 260);
const Curve kBrScrollCurve = Curves.easeOut;

/// 滚动模式的位置状态（挂在 _ReaderPageState 上，见 reader_page 的 `_scr`）。
class _ScrState {
  /// 行 → GlobalKey（量位置用；行只建一次，键可复用）。
  final Map<(int, int), GlobalKey> keys = {};

  /// 当前渲染窗口的 (章, 段) 序列（与 stage 的 flat 同源）。
  List<(int, int)> flat = const <(int, int)>[];

  /// (章,段) → 窗口内行号。
  Map<(int, int), int> pos = const {};

  /// 500ms 节流写回的定时器。
  Timer? tick;

  /// 最近一次确认的真实锚点（切模式/重进时优先用它）。
  (int, int)? anchor;

  /// 本轮进入滚动模式是否已定位过（stage 每帧都会调，定位只做一次）。
  bool entered = false;
}

extension _ReaderScroll on _ReaderPageState {
  GlobalKey _scrKey(int ci, int pi) => _scr.keys.putIfAbsent(
    (ci, pi),
    () => GlobalKey(debugLabel: 'brrow-$ci-$pi'),
  );

  /// stage 每帧登记窗口序列（顺带清理离窗太远的旧键，防大书长读键堆积）。
  void _scrPrepare(List<(int, int)> flat) {
    _scr.flat = flat;
    _scr.pos = {for (var i = 0; i < flat.length; i++) flat[i]: i};
    if (_scr.keys.length > flat.length * 2 && _scr.keys.length > 512) {
      final keep = flat.toSet();
      _scr.keys.removeWhere((k, _) => !keep.contains(k));
    }
  }

  int _scrIndex(int ci, int pi) => _scr.pos[(ci, pi)] ?? -1;

  /// 已建行的 (行号, 让该行顶边贴视口顶所需偏移)。
  List<(int, double)> _scrBuiltRows() {
    final out = <(int, double)>[];
    for (final e in _scr.keys.entries) {
      final ctx = e.value.currentContext;
      final box = ctx?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final vp = RenderAbstractViewport.maybeOf(box);
      if (vp == null) continue;
      final i = _scrIndex(e.key.$1, e.key.$2);
      if (i < 0) continue;
      double off;
      try {
        off = vp.getOffsetToReveal(box, 0.0).offset;
      } catch (_) {
        continue; // catch-ok: 行正被回收/重建，这一帧不给读数即可
      }
      out.add((i, off));
    }
    return out;
  }

  /// 当前可见首段（原文锚点）：偏移 ≤ 当前像素的**最靠下**那一行。
  (int, int)? _scrFirstVisible() {
    if (!_scrollCtrl.hasClients) return null;
    final px = _scrollCtrl.position.pixels;
    final rows = _scrBuiltRows();
    if (rows.isEmpty) return null;
    rows.sort((a, b) => a.$2.compareTo(b.$2));
    var pick = rows.first;
    for (final r in rows) {
      if (r.$2 <= px + 1.0) {
        pick = r;
      } else {
        break;
      }
    }
    final f = _scr.flat;
    if (pick.$1 < 0 || pick.$1 >= f.length) return null;
    return f[pick.$1];
  }

  /// 把可见首段写回 `_pos`（`pg` 换算仍走排版表，进度/书签/会话起止都用同一口径；
  /// `pi` 记原文锚点，重进/切模式才能回到**同一段**而不是同一页）。
  void _scrFlushPos({bool save = true}) {
    if (_cfg.mode != 'scroll') return;
    final a = _scrFirstVisible();
    if (a == null) return;
    _scr.anchor = a;
    final pag = _pag;
    final pg = pag == null || !pag.laidOut(a.$1)
        ? 0
        : pag.pageOfPara(a.$1, a.$2);
    final changed = _pos.ci != a.$1 || _pos.pg != pg || _pos.pi != a.$2;
    _pos.ci = a.$1;
    _pos.pg = pg;
    _pos.pi = a.$2;
    if (changed && save) _savePos();
  }

  /// 滚动通知入口：拖动中 500ms 节流，停笔立即写回。
  bool _scrOnScroll(ScrollNotification n) {
    if (n is ScrollEndNotification) {
      _scr.tick?.cancel();
      _scr.tick = null;
      _scrFlushPos();
      return false;
    }
    _scr.tick ??= Timer(const Duration(milliseconds: 500), () {
      _scr.tick = null;
      if (mounted) _scrFlushPos();
    });
    return false;
  }

  /// 进/切到滚动模式：定位到**当前页首段**的真实位置。
  /// 同章已有真实锚点（本轮刚滚过）→ 回那一段；`_pos.pi` 与当前页自洽时也用它；
  /// 否则用当前页首块（页→滚动的标准换算）。
  void _scrEnter() {
    final doc = _doc;
    if (doc == null || _cfg.mode != 'scroll') return;
    final ci = _pos.ci.clamp(0, doc.chapters.length - 1);
    final a = _scr.anchor;
    final pag = _pag;
    var pi = 0;
    final paraN = doc.chapters[ci].paras.length;
    if (a != null && a.$1 == ci) {
      pi = a.$2;
    } else if (_pos.pi != null &&
        _pos.pi! >= 0 &&
        pag != null &&
        pag.laidOut(ci) &&
        pag.pageOfPara(ci, _pos.pi!) == _pos.pg) {
      pi = _pos.pi!.clamp(0, paraN == 0 ? 0 : paraN - 1);
    } else if (pag != null && pag.laidOut(ci)) {
      final pages = pag.pages[ci]!;
      final pg = _pos.pg.clamp(0, pages.length - 1);
      final blocks = pages[pg];
      if (blocks.isNotEmpty) pi = blocks.first.pi;
    }
    unawaited(_scrJumpTo(ci, pi));
  }

  /// 定位到 (ci,pi)：先按已建行均高估，再逐帧用真行偏移校正（懒列表没法一次算准）。
  Future<void> _scrJumpTo(int ci, int pi) async {
    if (!_scrollCtrl.hasClients) return;
    final target = _scrIndex(ci, pi);
    if (target < 0) return;
    var est = _scrEstimate(target);
    for (var round = 0; round < 6; round++) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      _scrollCtrl.jumpTo(est);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scrollCtrl.hasClients) return;
      final box = _scr.keys[(ci, pi)]?.currentContext?.findRenderObject();
      if (box is RenderBox && box.attached) {
        final vp = RenderAbstractViewport.maybeOf(box);
        if (vp != null) {
          final off = vp
              .getOffsetToReveal(box, 0.0)
              .offset
              .clamp(0.0, _scrollCtrl.position.maxScrollExtent);
          _scrollCtrl.jumpTo(off);
          return;
        }
      }
      final next = _scrEstimate(target);
      if ((next - est).abs() < 0.5) return; // 估不动了＝已到边界
      est = next;
    }
  }

  /// 行号 → 估计偏移：用已建行的平均行高外推；一屏都没有行时退回旧口径。
  double _scrEstimate(int target) {
    final max = _scrollCtrl.hasClients
        ? _scrollCtrl.position.maxScrollExtent
        : 0.0;
    final rows = _scrBuiltRows()..sort((a, b) => a.$1.compareTo(b.$1));
    if (rows.length >= 2) {
      final lo = rows.first, hi = rows.last;
      final di = hi.$1 - lo.$1;
      if (di > 0) {
        final avg = (hi.$2 - lo.$2) / di;
        if (avg > 1) {
          return (lo.$2 + (target - lo.$1) * avg).clamp(0.0, max);
        }
      }
    }
    return (target * _cfg.fs * _cfg.lh * 3).clamp(0.0, max);
  }

  /// 滚动模式下「翻一屏」：手动与自动翻页共用同一条动效（只差让开的呼吸量）。
  void _scrByScreen(int d, {double inset = 120}) {
    if (!_scrollCtrl.hasClients) return;
    final p = _scrollCtrl.position;
    final step = (_viewport.height - inset).clamp(60.0, 4000.0);
    final target = (p.pixels + d * step).clamp(0.0, p.maxScrollExtent);
    unawaited(
      _scrollCtrl.animateTo(
        target,
        duration: kBrScrollFlipMs,
        curve: kBrScrollCurve,
      ),
    );
  }
}
