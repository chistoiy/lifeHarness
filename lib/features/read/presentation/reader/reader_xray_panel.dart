/// V1.54 X-Ray 全书索引 · 批A 面板段（形态事实源＝prototype/index-bookshelf.html
/// `?xr=` 深链 + tools/attic/xrfrag/{hdr,pane,js,css}.frag 的 DOM→Widget 1:1 对照）。
///
/// 段结构（xrfrag/pane.frag）：头部两行（状态+范围段）→ 类型 tab 行 → 列表滚动区 →
/// 底部排序 pill。点词条进**段内详情子页**（不是路由）；F12 剧透保护默认只展已读引用。
/// 自学习三件套（＋加词/整理词条/并词候选/不再显示该词）＝批B；这里只落形态与数据面。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/schema/xray.dart' as xs;
import '../../data/epub_doc.dart';
import '../../data/xray/xray_dao.dart';
import '../../data/xray/xray_scheduler.dart';
import '../../domain/book.dart';
import '../read_providers.dart';
import '../read_sheets.dart' show readToast;
import './reader_pager.dart';
import './reader_xray_learn_sheets.dart';
import './reader_xray_refine.dart' show XrRefineCard;
import './reader_xray_sheets.dart';

part 'reader_xray_panel_learn.dart';

const List<(String, String)> kXrTypes = [
  ('per', '人名'),
  ('loc', '地点'),
  ('org', '机构'),
  ('term', '术语'),
  ('abbr', '缩写'),
  ('book', '书名'),
];

/// 低置信折叠线＝全书最高分的 70%（引擎分是开放量纲，面板侧按本书归一后
/// 沿用原型 <0.7 的判定形状；设计书 §2 F4）。
const double _kLowRatio = 0.7;

class _XrStyle {
  static const accent = Color(0xFF6366F1);
  static const muted = Color(0xFF94A3B8);
  static const amber = Color(0xFFF59E0B);
  static const rose = Color(0xFFF43F5E);
  static const dot = Color(0xFF6366F1);
}

/// X-Ray 段主体（由上拉面板在 xrTab 时挂载）。
class ReaderXrayPanel extends ConsumerStatefulWidget {
  const ReaderXrayPanel({
    super.key,
    required this.book,
    required this.doc,
    required this.pager,
    required this.ci,
    required this.pg,
    required this.kw,
    required this.onJump,
  });

  final Book book;
  final EpubDoc doc;
  final BookPagination pager;
  final int ci;
  final int pg;

  /// 头部搜索独占态传入的词条过滤词（段感知：xrTab 时过滤词条行）。
  final String kw;

  /// 出场跳转（章+段锚点）。
  final void Function(int ch, int para) onJump;

  @override
  ConsumerState<ReaderXrayPanel> createState() => _ReaderXrayPanelState();
}

class _ReaderXrayPanelState extends ConsumerState<ReaderXrayPanel> {
  String _scope = 'book';
  String _type = 'all';
  String _sort = 'score';
  bool _lowOpen = false;
  int? _curId; // 非空＝详情子页
  bool _failShown = false;
  bool? _showCitesOverride; // 弹层内「显示全部引用」的本页覆盖（null＝跟随持久偏好）
  int _seenRev = -1;
  // 批B 整理模式（xrfrag：行前勾选 + 底部「合并/移除」条）。
  bool _org = false;
  final Set<int> _sel = {};
  // 接力两半拆开（批1 修 20261002）：选区 kw 不依赖快照，照旧首帧消费；
  // 直达详情改等快照可用——老逻辑首帧就把一次性标志烧在空快照上，
  // 全等匹配必败且永不重试＝选了词还得手动再搜。
  bool _kwRelayed = false;
  bool _focusRelayed = false;
  // 批2修③：选区未命中带进来的搜索词（面板内过滤；空态给加词入口）。
  String? _selKw;

  double get _confTop => _topScore;
  double _topScore = 1;

  @override
  void didUpdateWidget(covariant ReaderXrayPanel old) {
    super.didUpdateWidget(old);
    // 换书/重开面板回到列表态（详情不跨书残留）。
    if (old.book.id != widget.book.id) _curId = null;
  }

  // ---------- 数据组装 ----------

  /// 当前页段落集合（xrOnPage 判定用；滚动模式视作整屏宽裕＝当前章首段前全部）。
  Set<int> get _pagePis {
    final per = widget.pager.pages[widget.ci];
    if (per == null) return const {};
    if (widget.pg >= per.length) return const {};
    return per[widget.pg].toSet();
  }

  /// 已读判定锚（章+段）：页模式＝当前页最后一段；滚动模式＝当前章末。
  ({int ch, int para}) get _readTo {
    final per = widget.pager.pages[widget.ci];
    final pis = per != null && widget.pg < per.length ? per[widget.pg] : const <int>[];
    return (ch: widget.ci, para: pis.isEmpty ? 1 << 30 : pis.reduce((a, b) => a > b ? a : b));
  }

  bool _onPage(XrayEntityRow e, List<XrayAnchorRow>? ms) {
    if (ms == null) return false;
    final pis = _pagePis;
    for (final m in ms) {
      if (m.ch == widget.ci && pis.contains(m.para)) return true;
    }
    return false;
  }

  bool _inCh(XrayEntityRow e, List<XrayAnchorRow>? ms) =>
      ms != null && ms.any((m) => m.ch == widget.ci);

  List<XrayEntityRow> _scoped(
      List<XrayEntityRow> all, Map<int, List<XrayAnchorRow>> anchors) {
    if (_scope == 'page') {
      return all.where((e) => _onPage(e, anchors[e.id])).toList();
    }
    if (_scope == 'chapter') {
      return all.where((e) => _inCh(e, anchors[e.id])).toList();
    }
    return all;
  }

  List<XrayEntityRow> _sorted(List<XrayEntityRow> a) {
    if (_sort == 'n') {
      return [...a]..sort((x, y) => y.n.compareTo(x.n));
    }
    if (_sort == 'name') {
      return [...a]..sort((x, y) => x.name.compareTo(y.name));
    }
    return [...a]..sort((x, y) => y.score.compareTo(x.score));
  }

  @override
  Widget build(BuildContext context) {
    final sched = ref.watch(xraySchedulerProvider);
    // 终态自愈：调度器完成/失败/重置后（revision 变）重取词条。生产路径 provider
    // 装配了 onRevised→xrayRevisionProvider，这里再兜一层＝测试 override 或
    // 装配缺口时面板也不会在旧快照上打转。
    if (_seenRev == -1) {
      _seenRev = sched.revision;
    } else if (sched.revision != _seenRev) {
      _seenRev = sched.revision;
      final m = ref.read(bookMd5Provider(widget.book.id)).valueOrNull;
      if (m != null && m.isNotEmpty) ref.invalidate(xraySnapProvider(m));
    }
    final md5a = ref.watch(bookMd5Provider(widget.book.id));
    final md5 = md5a.valueOrNull;
    if (md5 == null || md5.isEmpty) {
      // 指纹未落库＝从未接线：空态 + 生成入口（ensureMd5 由按钮动作触发，被动渲染零 IO）。
      return _neverParsed(sched);
    }
    final snapA = ref.watch(xraySnapProvider(md5));
    final snap = snapA.valueOrNull ?? XrayPanelData.empty;
    final live = sched.live(widget.book.id);
    // 失败弹层一次机会（xrfrag ?xr=fail 形态：面板打开时任务态 failed 自动挂出）。
    final task = snap.task;
    if (!_failShown &&
        live?.running != true &&
        task != null &&
        task.status == xs.xrayStatusFailed) {
      _failShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showXrFailSheet(context, ref, book: widget.book, md5: md5, task: task, error: live?.error);
        }
      });
    }
    // 接力：选区未命中＝面板带入搜索（批2修③，空态给加词入口）；命中详情等快照可用。
    if (!_kwRelayed) {
      final kw = ref.read(readerXrKwProvider);
      if (kw != null) {
        _kwRelayed = true;
        _selKw = kw; // 本帧即渲染横幅
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // build 期间禁改 provider，旗标清场推到帧外。
          ref.read(readerXrKwProvider.notifier).state = null;
        });
      }
    }
    if (!_focusRelayed && (snapA.hasValue || snapA.hasError)) {
      final focusId = ref.read(readerXrFocusIdProvider);
      final focusWord = ref.read(readerXrFocusWordProvider);
      if (focusId != null || focusWord != null) {
        _focusRelayed = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(readerXrFocusIdProvider.notifier).state = null;
          ref.read(readerXrFocusWordProvider.notifier).state = null;
          // id 优先；id 失效（重解析换行）回退词全等，再回退互含
          // （与选区查询 dao.searchEntities 的命中判同式）。
          final byId = focusId == null
              ? null
              : snap.entities.where((e) => e.id == focusId).firstOrNull;
          final byName = focusWord == null
              ? null
              : snap.entities.where((e) => e.name == focusWord).firstOrNull;
          final fuzzy = focusWord == null
              ? null
              : snap.entities
                  .where((e) =>
                      e.name.contains(focusWord) ||
                      focusWord.contains(e.name))
                  .firstOrNull;
          final target = byId ?? byName ?? fuzzy;
          if (target != null) setState(() => _curId = target.id);
        });
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
          child: _head(sched, md5, task, live),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: _typeRow(_scoped(snap.entities, snap.anchors)),
        ),
        if (sched.suggestion(widget.book.id) case final sug?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: _suggestionCard(sched, md5, sug),
          ),
        // 批4 · AI 精化进度卡（原型 #xrAiBar）：逐批进度/暂停续跑/失败提示/查看汇总。
        // R3-5：holder 全局单槽——只显当前书的 runner，别的书的进度/汇总不跨书借用。
        if (ref.watch(xrRefineHolderProvider) case final xrR?
            when xrR.bookId == widget.book.id)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: XrRefineCard(runner: xrR, md5: md5),
          ),
        Expanded(
          key: const ValueKey('xrScroll'),
          child: _curId == null
              ? _list(snap, md5)
              : _detail(snap, md5, _curId!),
        ),
        if (_org && _curId == null) _orgBar(sched, md5, snap),
      ],
    );
  }

  Future<void> _openAdd(String? md5, {String prefill = ''}) => showXrAddSheet(
        context,
        ref,
        book: widget.book,
        md5: md5,
        prefill: prefill,
        ensureMd5: () =>
            ref.read(xraySchedulerProvider).ensureMd5(widget.book),
      );

  /// 养成词库开关（批2 `read.xrUserDict`，默认开）。快照 provider watch 同一 kv，
  /// 翻转即重取（DAO presetView 换读侧口径），无需手动失效。
  bool get _udOn =>
      ref.watch(readKvProvider(('read.xrUserDict', 'true'))).valueOrNull !=
      'false';

  Future<void> _flipUserDict() async {
    // 回调内只能 read（watch 仅限 build）；键值即取即翻。
    final onNow =
        ref.read(readKvProvider(('read.xrUserDict', 'true'))).valueOrNull !=
            'false';
    final next = onNow ? 'false' : 'true';
    await ref.read(readRepositoryProvider).setKv('read.xrUserDict', next);
    ref.read(readTickProvider.notifier).state++;
    if (mounted) {
      readToast(
        context,
        next == 'true'
            ? '养词库已开启 · 我的词条与屏蔽恢复生效'
            : '已切纯预置视角 · 已整理状态不回滚，重开即恢复',
      );
    }
  }

  // ---------- 头部（xrHeadHtml 1:1） ----------

  Widget _head(XrayScheduler sched, String md5, XrayTaskRow? task, XrayLive? live) {
    final running = live != null && live.running;

    final done = task?.processedCh ?? 0;
    final total = task?.totalCh ?? 0;
    final status = task?.status;
    final String lbl;
    if (live != null && live.running) {
      lbl = '解析中 ${live.pct}%';
    } else if (live != null && live.error != null) {
      lbl = '上次失败';
    } else if (task == null) {
      lbl = '未解析';
    } else if (status == xs.xrayStatusPause) {
      lbl = '已暂停 · 断点已存';
    } else if (status == xs.xrayStatusFailed) {
      lbl = '上次失败';
    } else {
      lbl = '已解析 $done/$total 章';
    }
    return Column(
      children: [
        Row(
          children: [
            Text(
              lbl,
              key: const ValueKey('xrStatus'),
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
            ),
            const Spacer(),
            if (task == null && !running)
              // 有指纹但从未解析：头部直接给生成入口（xrEntry「未解析→范围弹层」口径）。
              _chip('xrGen', '生成全书索引', () => showXrScopeSheet(
                    context,
                    ref,
                    book: widget.book,
                    doc: widget.doc,
                    md5: md5,
                    ci: widget.ci,
                  )),
            if (!running &&
                task != null &&
                (done < total || status == xs.xrayStatusPause))
              // 暂停态一律给续跑出口：锚点遍里暂停时 processedCh 已等于总章数，
              // 只看 done<total 会让「已暂停 · 断点已存」变成没有按钮的死状态。
              _chip('xrBarContinue', '继续生成', () => sched.resume(widget.book, md5)),
            if (!running && task != null) ...[
              const SizedBox(width: 6),
              _chip('xrReparse', '重新解析', () => showXrScopeSheet(
                    context,
                    ref,
                    book: widget.book,
                    doc: widget.doc,
                    md5: md5,
                    ci: widget.ci,
                  )),
            ],
            if (task != null) ...[
              const SizedBox(width: 6),
              _chip('xrReset', '重置', () => _confirmReset(sched, md5)),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final s in const [('page', '当前页'), ('chapter', '本章'), ('book', '全书')])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  key: ValueKey('xr-scope-${s.$1}'),
                  onTap: () => setState(() {
                    _scope = s.$1;
                    _curId = null;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _scope == s.$1
                          ? Colors.white.withValues(alpha: .9)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      s.$2,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: _scope == s.$1
                            ? const Color(0xFF0F172A)
                            : _XrStyle.muted,
                      ),
                    ),
                  ),
                ),
              ),
            const Spacer(),
            // 批B：段头部「＋加词 / 整理词条」（原型 xrHeadHtml r2 右组）。
            _chip('xrAddBtn', '＋加词', () => _openAdd(md5)),
            const SizedBox(width: 6),
            GestureDetector(
              key: const ValueKey('xrOrgBtn'),
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() {
                _org = !_org;
                if (!_org) _sel.clear();
                _curId = null;
              }),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _org ? _XrStyle.accent : null,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: _org
                          ? _XrStyle.accent
                          : Theme.of(context).dividerColor),
                ),
                child: Text(
                  '整理词条',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: _org ? Colors.white : null),
                ),
              ),
            ),
            // 批2 · 养词库开关快捷位（关＝纯预置视角：快照随 kv 重取）。
            const SizedBox(width: 6),
            GestureDetector(
              key: const ValueKey('xrUserDictBtn'),
              behavior: HitTestBehavior.opaque,
              onTap: _flipUserDict,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _udOn ? _XrStyle.accent : null,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: _udOn
                          ? _XrStyle.accent
                          : Theme.of(context).dividerColor),
                ),
                child: Text(
                  '养词库 ${_udOn ? '开' : '关'}',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: _udOn ? Colors.white : null),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _chip(String key, String label, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      key: ValueKey(key),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Future<void> _confirmReset(XrayScheduler sched, String md5) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (sc) => AlertDialog(
        title: const Text('重置全书索引'),
        content: const Text('将清除该书的实体、出场与任务态（你加过/屏蔽过的词保留）。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(sc, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(sc, true),
            child: const Text('重置', style: TextStyle(color: _XrStyle.rose)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await sched.reset(widget.book.id, md5);
      if (mounted) readToast(context, '已重置 · 实体/出场/任务态已清空');
    }
  }

  // ---------- 类型段（xrTypesHtml：空类隐藏） ----------

  Widget _typeRow(List<XrayEntityRow> pool) {
    Widget tab(String key, String label, String sel) {
      final on = _type == sel;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: GestureDetector(
          key: ValueKey('xr-tp-$key'),
          onTap: () => setState(() {
            _type = sel;
            _curId = null;
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              color: on ? _XrStyle.accent : const Color(0x2994A3B8),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: on ? Colors.white : const Color(0xFF64748B),
              ),
            ),
          ),
        ),
      );
    }

    final visible = <Widget>[tab('all', '全部 · ${pool.length}', 'all')];
    for (final t in kXrTypes) {
      final n = pool.where((e) => e.type == t.$1).length;
      if (n == 0) continue;
      visible.add(tab(t.$1, '${t.$2} · $n', t.$1));
    }
    return SizedBox(
      height: 30,
      key: const ValueKey('xrTypes'),
      child: ListView(scrollDirection: Axis.horizontal, children: visible),
    );
  }

  // ---------- 列表（xrListHtml：高/低置信 + 排序 pill · ④全书态不置顶「在当前页」分组） ----------

  Widget _list(XrayPanelData snap, String md5) {
    var pool = _scoped(snap.entities, snap.anchors);
    if (_type != 'all') pool = pool.where((e) => e.type == _type).toList();
    final kw = widget.kw.trim();
    if (kw.isNotEmpty) pool = pool.where((e) => e.name.contains(kw)).toList();
    // 批2修③：选区未命中带入的搜索词（空态给「加为词条」入口）。
    final skw = _selKw?.trim() ?? '';
    if (skw.isNotEmpty) {
      pool = pool.where((e) => e.name.contains(skw)).toList();
    }
    _topScore =
        pool.isEmpty ? 1 : pool.map((e) => e.score).reduce((a, b) => a > b ? a : b);
    if (_topScore <= 0) _topScore = 1;
    final cut = _topScore * _kLowRatio;
    final hi = _sorted(pool.where((e) => e.score >= cut).toList());
    final lo = _sorted(pool.where((e) => e.score < cut).toList());

    if (pool.isEmpty) {
      return ListView(
        key: const ValueKey('xrList'),
        children: [
          if (skw.isNotEmpty) _kwBanner(),
          if (skw.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  Text('没有找到「$skw」',
                      key: const ValueKey('xrMissLbl'),
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(fontSize: 10, color: _XrStyle.muted)),
                  const SizedBox(height: 10),
                  GestureDetector(
                    key: const ValueKey('xrKwAdd'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openAdd(md5, prefill: skw),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: _XrStyle.accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text('＋ 加为词条',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Text(
                snap.entities.isEmpty ? '还没有词条 · 点「重新解析」生成全书索引' : '该范围没有词条',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, color: _XrStyle.muted),
              ),
            ),
        ],
      );
    }

    final rows = <Widget>[
      // 批2修③：选区搜索横幅（列表态任意时刻可清）。
      if (skw.isNotEmpty) _kwBanner(),
    ];
    // ④（工单20261001轮2·用户拍板）：全书范围不显示「在当前页」分组，
    // 当前页只由范围段选「当前页」表达（_scoped 过滤），与原型同步摘组。
    rows.addAll(hi.map((e) => _row(e, snap.anchors[e.id])));
    if (lo.isNotEmpty) {
      rows.add(GestureDetector(
        key: const ValueKey('xr-lowmore'),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _lowOpen = !_lowOpen),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 10, 2, 4),
          child: Text(
            _lowOpen ? '收起低置信' : '低置信 · ${lo.length} · 展开',
            style: const TextStyle(
                fontSize: 10, fontWeight: FontWeight.w900, color: _XrStyle.muted),
          ),
        ),
      ));
      if (_lowOpen) rows.addAll(lo.map((e) => _row(e, snap.anchors[e.id])));
    }
    rows.add(Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: GestureDetector(
          key: const ValueKey('xrSortBtn'),
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _sort = const ['score', 'n', 'name'][(_sort == 'score') ? 1 : (_sort == 'n') ? 2 : 0]),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${const {'score': '按相关度', 'n': '按出场', 'name': '按名称'}[_sort]} ▾',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    ));
    rows.add(Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        '${snap.entities.length} 个词条 · 出场锚点全量 · 上下文截断',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 9, color: _XrStyle.muted),
      ),
    ));
    return ListView(key: const ValueKey('xrList'), children: rows);
  }

  /// 批2修③：选区搜索横幅（列表/空态两分支共用；清除钮任意时刻可关）。
  Widget _kwBanner() {
    final skw = _selKw?.trim() ?? '';
    return Padding(
      key: const ValueKey('xrKwBar'),
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 6),
      child: Row(
        children: [
          Expanded(
            child: Text('搜索「$skw」',
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _XrStyle.muted)),
          ),
          GestureDetector(
            key: const ValueKey('xrKwClr'),
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _selKw = null),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text('清除',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _XrStyle.accent)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(XrayEntityRow e, List<XrayAnchorRow>? ms) {
    final cs = Theme.of(context).colorScheme;
    final sel = _sel.contains(e.id);
    return GestureDetector(
      key: ValueKey('xrRow-${e.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        if (_org) {
          sel ? _sel.remove(e.id) : _sel.add(e.id);
        } else {
          _curId = e.id;
        }
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: .5)),
        ),
        foregroundDecoration: _org && sel
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _XrStyle.accent, width: 2),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_org)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Container(
                      key: ValueKey('xr-ck-${e.id}'),
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: sel ? _XrStyle.accent : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: sel
                          ? const Icon(Icons.check_rounded,
                              size: 12, color: Colors.white)
                          : null,
                    ),
                  ),
                Flexible(
                  child: Text(
                    e.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 6),
                Text('${e.n}次',
                    style: const TextStyle(fontSize: 9, color: _XrStyle.muted)),
                if (e.tocFlag) ...[
                  const SizedBox(width: 4),
                  const _Badge('目录词', outline: true),
                ],
                if (e.userAdded) ...[
                  const SizedBox(width: 4),
                  const _Badge('我的词条', violet: true),
                ],
                const Spacer(),
                _XrBar(
                  mentions: [
                    for (final m in ms ?? const <XrayAnchorRow>[]) m.ch,
                  ],
                  totalCh: widget.doc.chapters.length,
                  curCh: widget.ci,
                ),
              ],
            ),
            if ((e.aiDesc ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  e.aiDesc!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9.5, color: _XrStyle.muted, height: 1.4),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------- 详情子页（xrDetailHtml + F12 剧透保护） ----------

  Widget _detail(XrayPanelData snap, String md5, int id) {
    final e = snap.entities.where((x) => x.id == id).firstOrNull;
    if (e == null) {
      // 词条在整理动作后可能消失：静默回列表。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _curId = null);
      });
      return const SizedBox.shrink();
    }
    final all = snap.anchors[id] ?? const <XrayAnchorRow>[];
    // F12：默认只展已读范围内引用；偏好键 read.xrSpoilers（默认开＝保护）。
    final protect =
        (ref.read(readKvProvider(('read.xrSpoilers', 'true'))).valueOrNull ?? 'true') !=
            'false';
    final showAll = _showCitesOverride ?? !protect;
    final readTo = _readTo;
    final vis = showAll
        ? all
        : all
            .where((m) =>
                m.ch < readTo.ch || (m.ch == readTo.ch && m.para <= readTo.para))
            .toList();
    final hidden = all.length - vis.length;
    final cs = Theme.of(context).colorScheme;
    return ListView(
      key: const ValueKey('xrDetail'),
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
      children: [
        Row(
          children: [
            GestureDetector(
              key: const ValueKey('xr-back'),
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _curId = null),
              child: const Padding(
                padding: EdgeInsets.fromLTRB(2, 8, 8, 8),
                child: Text('‹ 词条列表',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w900, color: _XrStyle.accent)),
              ),
            ),
            Expanded(
              child: Text(e.name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
            ),
            Text('置信 ${(e.score / _confTop).clamp(0.0, 1.0).toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 10, color: _XrStyle.muted)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Badge(e.userAdded ? '我的词条' : (kXrTypes.firstWhere((t) => t.$1 == e.type).$2),
                  violet: e.userAdded, type: e.type),
              if (e.tocFlag) const _Badge('目录词', outline: true),
              Text(
                '${e.n} 次 · 跨 ${e.chs} 章'
                '${e.aliases.isNotEmpty ? ' · 曾用名 ${e.aliases.join('、')}' : ''}',
                style: const TextStyle(fontSize: 9, color: _XrStyle.muted),
              ),
            ],
          ),
        ),
        if ((e.aiDesc ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(e.aiDesc!,
                style: TextStyle(fontSize: 11, height: 1.6, color: cs.onSurfaceVariant)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 12, 2, 0),
          child: _XrBar(
            mentions: [for (final m in all) m.ch],
            totalCh: widget.doc.chapters.length,
            curCh: widget.ci,
            large: true,
            keyTag: 'xr-bar-${e.id}',
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('书首', style: TextStyle(fontSize: 8, color: _XrStyle.muted)),
              Text('橙线＝读到第${widget.ci + 1}章',
                  style: const TextStyle(fontSize: 8, color: _XrStyle.muted)),
              const Text('书尾', style: TextStyle(fontSize: 8, color: _XrStyle.muted)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
          child: Row(
            children: [
              const Expanded(
                child: Text('出场 · 点按跳回阅读位置',
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700, color: _XrStyle.muted)),
              ),
              GestureDetector(
                key: const ValueKey('xr-cites'),
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  final next = !(showAll);
                  setState(() => _showCitesOverride = next);
                  await ref
                      .read(readRepositoryProvider)
                      .setKv('read.xrSpoilers', next ? 'false' : 'true');
                  if (mounted) readToast(context, next ? '已显示全部引用' : '剧透保护已开启');
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: showAll ? _XrStyle.accent : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '显示全部引用',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: showAll ? Colors.white : null),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (vis.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('已读范围内没有出场',
                style: TextStyle(fontSize: 10, color: _XrStyle.muted)),
          ),
        for (final m in vis)
          GestureDetector(
            key: ValueKey('xr-clip-${e.id}-${m.ch}-${m.para}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onJump(m.ch, m.para),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0x1A94A3B8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_chTitle(m.ch)} · 段 ${m.para + 1}',
                    style: const TextStyle(
                        fontSize: 9, fontWeight: FontWeight.w900, color: _XrStyle.muted),
                  ),
                  const SizedBox(height: 3),
                  Text.rich(_mark(m.snippet ?? e.name, e.name)),
                ],
              ),
            ),
          ),
        if (hidden > 0)
          Padding(
            key: const ValueKey('xr-spoiler'),
            padding: const EdgeInsets.only(left: 4, top: 2),
            child: Text('剧透保护 · 隐藏未读 $hidden 处引用',
                style: const TextStyle(fontSize: 9, color: _XrStyle.muted)),
          ),
        ..._detailLearn(snap, md5, e),
      ],
    );
  }

  String _chTitle(int ch) =>
      ch < widget.doc.chapterTitles.length ? widget.doc.chapterTitles[ch] : '第${ch + 1}章';

  /// 关键词琥珀高亮（原型 xrKwHl 的 <b> 口径）。
  TextSpan _mark(String text, String name) {
    if (!text.contains(name)) {
      return TextSpan(text: text, style: const TextStyle(fontSize: 11, height: 1.55));
    }
    final parts = text.split(name);
    final children = <InlineSpan>[];
    for (var i = 0; i < parts.length; i++) {
      children.add(TextSpan(
          text: parts[i], style: const TextStyle(fontSize: 11, height: 1.55)));
      if (i != parts.length - 1) {
        children.add(TextSpan(
          text: name,
          style: const TextStyle(
              fontSize: 11,
              height: 1.55,
              fontWeight: FontWeight.w900,
              color: _XrStyle.accent),
        ));
      }
    }
    return TextSpan(children: children);
  }

  // ---------- 未接线空态 ----------

  Widget _neverParsed(XrayScheduler sched) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('还没有全书索引',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          GestureDetector(
            key: const ValueKey('xrGen'),
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              final md5 = await sched.ensureMd5(widget.book);
              if (!mounted) return;
              if (md5 == null) {
                readToast(context, '文件暂不可读 · 稍后再试');
                return;
              }
              final task = await sched.dao.task(md5);
              if (!mounted) return;
              if (task == null) {
                showXrScopeSheet(context, ref,
                    book: widget.book,
                    doc: widget.doc,
                    md5: md5,
                    ci: widget.ci);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                color: _XrStyle.accent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text('生成全书索引',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- 行内迷你分布条（xrBarHtml：出场圆点·未读淡显·橙线＝当前章） ----------

class _XrBar extends StatelessWidget {
  const _XrBar({
    required this.mentions,
    required this.totalCh,
    required this.curCh,
    this.large = false,
    this.keyTag,
  });

  final List<int> mentions;
  final int totalCh;
  final int curCh;
  final bool large;
  final String? keyTag;

  @override
  Widget build(BuildContext context) {
    final w = large ? MediaQuery.sizeOf(context).width - 36 : 118.0;
    final h = large ? 22.0 : 14.0;
    final t = totalCh <= 0 ? 1 : totalCh;
    double left(int ch) => ((ch + 0.5) / t * w).clamp(1.0, w - 3.0);
    return SizedBox(
      key: keyTag == null ? null : ValueKey(keyTag),
      width: w,
      height: h,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0x2E94A3B8),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          for (var i = 0; i < mentions.length; i++)
            Positioned(
              key: ValueKey('${keyTag ?? 'xrbar'}-t$i'),
              left: left(mentions[i]),
              top: large ? 4 : 2,
              bottom: large ? 4 : 2,
              child: Container(
                width: large ? 4 : 3,
                decoration: BoxDecoration(
                  color: mentions[i] > curCh
                      ? _XrStyle.dot.withValues(alpha: .3)
                      : _XrStyle.dot,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          Positioned(
            key: ValueKey('${keyTag ?? 'xrbar'}-now'),
            left: left(curCh),
            top: 0,
            bottom: 0,
            child: Container(
              width: 2,
              decoration: BoxDecoration(
                color: _XrStyle.amber,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {this.outline = false, this.violet = false, this.type});
  final String text;
  final bool outline;
  final bool violet;
  final String? type;

  static const _typeColor = {
    'per': Color(0xFF6366F1),
    'loc': Color(0xFF059669),
    'org': Color(0xFFB45309),
    'term': Color(0xFF0284C7),
    'abbr': Color(0xFF475569),
    'book': Color(0xFFDB2777),
  };

  @override
  Widget build(BuildContext context) {
    final c = violet
        ? const Color(0xFF7C3AED)
        : _typeColor[type] ?? const Color(0xFF6366F1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: outline ? Colors.transparent : c.withValues(alpha: .12),
        border: outline ? Border.all(color: c.withValues(alpha: .5)) : null,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 8, fontWeight: FontWeight.w900, color: c)),
    );
  }
}

