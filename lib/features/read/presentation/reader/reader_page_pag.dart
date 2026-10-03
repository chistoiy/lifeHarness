part of 'reader_page.dart';

// 治理（G7c 族口径）：分页群七件（_rebuildPag/_weights/_applyPag/_ensure/_ensureCur/
//_pagSaveTick/_layout）自 _ReaderPageState 移入同库扩展＝行为零改动、直访私有字段。
// 本刀动机＝归还 reader_page 的 1204 体积债（登记项「只许减不许增」，批三刀4 加了
// 外观页 unsupported 两行后顶破线）；拆完删掉 size_budget 登记项，归还默认 1200 面。
extension _ReaderPag on _ReaderPageState {
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
    // ignore: invalid_use_of_protected_member // 同库扩展里调 State.setState（note_edit_* 先例）
    setState(() {
      _pag = fresh;
      _clampPos();
    });
    if (svc.docsPath == null) return;
    BookPagination? tab;
    try {
      tab = await svc.loadPag(widget.bookId, l, _weights(doc));
    } catch (_) {
      // catch-ok: 落盘分页表读不到就按现算走（懒排路径本来就自给），不值得为缓存打断开书。
    }
    if (!mounted || gen != _pagGen || tab == null) return;
    final cur = _pag;
    if (cur == null) return;
    for (var i = 0; i < cur.pages.length && i < tab.pages.length; i++) {
      if (cur.pages[i] == null) cur.pages[i] = tab.pages[i];
    }
    // ignore: invalid_use_of_protected_member // 同上
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

  /// 分页布局（R3-2 起与整本预载共用 [ReaderLayout.of]：indMode 三档进指纹后，
  /// 两处各写一份映射迟早分叉，预载表就再也命中不了）。
  ReaderLayout _layout() =>
      ReaderLayout.of(_cfg, width: _viewport.width, height: _viewport.height);
}
