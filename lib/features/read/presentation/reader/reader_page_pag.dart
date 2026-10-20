part of 'reader_page.dart';

// 治理（G7c 族口径）：分页群七件（_rebuildPag/_weights/_applyPag/_ensure/_ensureCur/
//_pagSaveTick/_layout）自 _ReaderPageState 移入同库扩展＝行为零改动、直访私有字段。
// 本刀动机＝归还 reader_page 的 1204 体积债（登记项「只许减不许增」，批三刀4 加了
// 外观页 unsupported 两行后顶破线）；拆完删掉 size_budget 登记项，归还默认 1200 面。
// V1.60（§3G）：_pagSaveTick（整本防抖写表）退役——表按章分片读写；新增
// _startBgPaginate「首次开书全书续算」（空闲让帧补齐，导入/预载链已摘表）。
extension _ReaderPag on _ReaderPageState {
  void _rebuildPag() {
    final doc = _doc;
    if (doc == null || _viewport.width <= 0) return;
    final gen = ++_pagGen;
    final l = _layout();
    unawaited(_applyPag(doc, l, gen));
  }

  List<int> _weights(EpubDoc doc) => doc.chapterCharCounts;

  /// V1.60（§3G）：首帧＝当前章同步实算（轮4 口径不动，单章毫秒级）；
  /// **不取全书表**——旧落盘表一次取表随书体积从 7ms 涨到约 1 秒（结论二），
  /// 现在开书只读几 KB 的分片索引，全书表由本之后的按章后台续算逐片补齐。
  /// 开书取证两条之一（§3F）：首章实算＋落盘表命中与否各记一段，只在
  /// 首次建表（gen==1）时记，改字号/切开关的后续重排不刷屏。
  Future<void> _applyPag(EpubDoc doc, ReaderLayout l, int gen) async {
    final svc = ref.read(epubPreloadProvider);
    final fresh = BookPagination.lazy(_weights(doc));
    final swEns = Stopwatch()..start();
    _ensure(fresh, doc, l, _pos.ci.clamp(0, doc.chapters.length - 1));
    final ensMs = swEns.elapsedMilliseconds;
    // ignore: invalid_use_of_protected_member // 同库扩展里调 State.setState（note_edit_* 先例）
    setState(() {
      _pag = fresh;
      _clampPos();
    });
    if (svc.docsPath == null) {
      if (gen == 1) {
        AppLog.add('开书·排版 书#${widget.bookId} 首章实算=${ensMs}ms 落盘表=无目录');
      }
      return;
    }
    final swTab = Stopwatch()..start();
    final hit = await svc.pagHit(widget.bookId, l);
    if (gen == 1) {
      AppLog.add(
        '开书·排版 书#${widget.bookId} 首章实算=${ensMs}ms '
        '落盘表=${hit ? "命中" : "未命中"} 取表=${swTab.elapsedMilliseconds}ms',
      );
    }
    if (!mounted || gen != _pagGen) return;
    _startBgPaginate(doc, l, gen);
  }

  /// 指定章未排版则实算（同步读快照章 + TextPainter，单章毫秒级），
  /// 并即时落该章分片（V1.60：不再有整本防抖写表）。
  void _ensure(BookPagination pag, EpubDoc doc, ReaderLayout l, int ci) {
    if (ci < 0 || ci >= doc.chapters.length || pag.laidOut(ci)) return;
    pag.setChapter(ci, EpubPager.layoutChapter(doc.chapters[ci].paras, l));
    final svc = ref.read(epubPreloadProvider);
    if (svc.docsPath != null) {
      unawaited(svc.savePagChapter(
        widget.bookId,
        l,
        ci,
        pag.pages[ci]!,
        doc.chapters.length,
      ));
    }
  }

  /// 确保当前章已排版（翻页/跳章/ seek 落章后统一走这里）。
  void _ensureCur() {
    final doc = _doc, pag = _pag;
    if (doc == null || pag == null) return;
    _ensure(pag, doc, _layout(), _pos.ci.clamp(0, doc.chapters.length - 1));
  }

  /// V1.60 §3G「首次开书后台续算全书分页」：从当前章起环形补齐——分片命中
  /// 直接采用，否则实算＋落分片。**只在空闲间隙干活**（有在跑帧就让 120ms、
  /// 章间让 60ms），「第一次加载耗时不限、加载完开书必须秒开」的账在这里付清。
  /// 工单闸：页面销毁 / 外观重排（gen 变）/ 再次开书（票据推进）立刻停。
  void _startBgPaginate(EpubDoc doc, ReaderLayout l, int gen) {
    final svc = ref.read(epubPreloadProvider);
    if (svc.docsPath == null) return;
    final my = ++_bgTicket;
    final swAll = Stopwatch()..start();
    unawaited(() async {
      final n = doc.chapters.length;
      if (n <= 1) return;
      bool alive() =>
          mounted && my == _bgTicket && gen == _pagGen && _doc == doc;
      var ci = _pos.ci.clamp(0, n - 1);
      // 开书动作落定再开工：首帧排版/进度恢复先跑完。
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      for (var k = 0; k < n - 1; k++) {
        ci = (ci + 1) % n;
        if (!alive()) return;
        final pag = _pag;
        if (pag == null || pag.chapterCount != n) return;
        if (pag.laidOut(ci)) continue;
        // 翻页/动画在跑帧＝不抢主线程（轮4 整本循环霸占的教训）。
        while (alive() && WidgetsBinding.instance.hasScheduledFrame) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
        if (!alive()) return;
        PagChapter? ch;
        try {
          ch = await svc.loadPagChapter(widget.bookId, l, ci);
        } catch (_) {
          // catch-ok: 分片读失败按「未排」处理＝实算兜回，与无表同语义。
        }
        if (!alive()) return;
        final now = _pag;
        if (now == null || now.chapterCount != n) return;
        if (now.laidOut(ci)) continue; // 翻页路径已补上，本轮跳过。
        if (ch != null) {
          now.setChapter(ci, ch);
        } else {
          now.setChapter(
            ci,
            EpubPager.layoutChapter(doc.chapters[ci].paras, l),
          );
          unawaited(
            svc.savePagChapter(widget.bookId, l, ci, now.pages[ci]!, n),
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      if (gen == 1 && alive()) {
        AppLog.add(
          '开书·续算 书#${widget.bookId} 全书分页补齐 章=$n 用时='
          '${swAll.elapsedMilliseconds}ms',
        );
      }
    }());
  }

  /// 分页布局（R3-2 起与整本预载共用 [ReaderLayout.of]：indMode 三档进指纹后，
  /// 两处各写一份映射迟早分叉，预载表就再也命中不了）。
  /// 高＝**舞台可视高**而非视口高：正文在 SafeArea 内、`_viewport` 在 SafeArea 外，
  /// 吃视口高会让每页多塞一个状态栏＝页底裁字（工单 §3H-A 候选1，2026-10-04 实测虚增 44.67px）。
  ReaderLayout _layout() => ReaderLayout.of(
    _cfg,
    width: _viewport.width,
    height: brStageHeight(context, viewportH: _viewport.height),
  );
}
