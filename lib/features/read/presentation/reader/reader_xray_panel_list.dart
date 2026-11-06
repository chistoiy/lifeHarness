part of 'reader_xray_panel.dart';

// 批7 F7-6（2026-11-07）：面板**列表渲染群**自 `reader_xray_panel.dart` 拆入同库
// extension part（整组机械搬迁·行为零改动）——主文件回 1200 面以内，列表改造
// （懒构建＋作用域/排序记忆）在这一份里做。
// 群内成员＝`_list`（高/低置信分组＋排序 pill）／`_kwBanner`（选区搜索横幅）／
// `_row`（单条词条行）。

extension _XrPanelList on _ReaderXrayPanelState {
  // ---------- 列表（xrListHtml：高/低置信 + 排序 pill · ④全书态不置顶「在当前页」分组） ----------

  Widget _list(XrayPanelData snap, String md5) {
    // 批2修③：选区未命中带入的搜索词（空态给「加为词条」入口）。
    final skw = _selKw?.trim() ?? '';
    final kw = widget.kw.trim();
    // F7-6（批7）：作用域过滤＋排序走**记忆**——签名＝作用域结果／类型／两个搜索词／
    // 排序键。滚动、勾选、展开低置信都不再触发全表重扫重排；旧实现每帧跑两遍
    // `_scoped`（类型 tab 一次、列表一次）再把 hi/lo 各排一遍。
    final sig = Object.hash(_scopeSig, _type, kw, skw, _sort);
    var cache = _listCache;
    if (cache == null || sig != _listSig) {
      var pool = _scopedOf(snap);
      if (_type != 'all') pool = pool.where((e) => e.type == _type).toList();
      if (kw.isNotEmpty) pool = pool.where((e) => e.name.contains(kw)).toList();
      if (skw.isNotEmpty) pool = pool.where((e) => e.name.contains(skw)).toList();
      var top =
          pool.isEmpty ? 1.0 : pool.map((e) => e.score).reduce((a, b) => a > b ? a : b);
      if (top <= 0) top = 1.0;
      final cut = top * _kLowRatio;
      cache = (
        hi: _sorted(pool.where((e) => e.score >= cut).toList()),
        lo: _sorted(pool.where((e) => e.score < cut).toList()),
        top: top,
      );
      _listSig = sig;
      _listCache = cache;
    }
    final c = cache;
    _topScore = c.top;
    final hi = c.hi;
    final lo = c.lo;
    final poolEmpty = hi.isEmpty && lo.isEmpty;

    if (poolEmpty) {
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
                          TextStyle(fontSize: 10, color: _XrStyle.muted(context))),
                  const SizedBox(height: 10),
                  GestureDetector(
                    key: const ValueKey('xrKwAdd'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openAdd(md5, prefill: skw),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: _XrStyle.accent(context),
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
                style: TextStyle(fontSize: 10, color: _XrStyle.muted(context)),
              ),
            ),
        ],
      );
    }

    // F7-6（批7）：**懒构建**——旧实现先把全部行 new 成 `List<Widget>` 再交给非
    // builder 的 ListView（2000 词条＝当场全建 2000 个 widget，首帧必卡）。现在
    // specs 只存「这一行是什么」，可见才建：
    // ④（工单20261001轮2·用户拍板）全书范围不显示「在当前页」分组，当前页只由
    // 范围段选「当前页」表达（`_scopedOf` 过滤），与原型同步摘组。
    final specs = <Object>[
      // 批2修③：选区搜索横幅（列表态任意时刻可清）。
      if (skw.isNotEmpty) const _XrKwBar(),
      ...hi,
      if (lo.isNotEmpty) const _XrLowMore(),
      if (lo.isNotEmpty && _lowOpen) ...lo,
      const _XrSortPill(),
      const _XrTail(),
    ];
    return ListView.builder(
      key: const ValueKey('xrList'),
      itemCount: specs.length,
      itemBuilder: (_, i) {
        final s = specs[i];
        if (s is XrayEntityRow) return _row(s, snap.anchors[s.id]);
        if (s is _XrKwBar) return _kwBanner();
        if (s is _XrLowMore) return _lowMoreRow(lo.length);
        if (s is _XrSortPill) return _sortPill();
        return _tailRow(snap.entities.length);
      },
    );
  }

  Widget _lowMoreRow(int n) {
    return GestureDetector(
      key: const ValueKey('xr-lowmore'),
      behavior: HitTestBehavior.opaque,
      // ignore: invalid_use_of_protected_member
      onTap: () => setState(() => _lowOpen = !_lowOpen),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 10, 2, 4),
        child: Text(
          _lowOpen ? '收起低置信' : '低置信 · $n · 展开',
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w900, color: _XrStyle.muted(context)),
        ),
      ),
    );
  }

  Widget _sortPill() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: GestureDetector(
          key: const ValueKey('xrSortBtn'),
          behavior: HitTestBehavior.opaque,
          // ignore: invalid_use_of_protected_member
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
    );
  }

  Widget _tailRow(int total) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        '$total 个词条 · 出场锚点全量 · 上下文截断',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 9, color: _XrStyle.muted(context)),
      ),
    );
  }

  /// F7-6：作用域过滤的记忆口（类型 tab 行与列表共用同一次过滤结果）。
  List<XrayEntityRow> _scopedOf(XrayPanelData snap) {
    final sig = Object.hash(
      identityHashCode(snap.entities),
      identityHashCode(snap.anchors),
      _scope,
      widget.ci,
      _pagePis.length,
      _pagePis.isEmpty ? -1 : _pagePis.first,
      _pagePis.isEmpty ? -1 : _pagePis.last,
    );
    if (sig == _scopeSig) return _scopeCache;
    _scopeSig = sig;
    return _scopeCache = _scoped(snap.entities, snap.anchors);
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
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _XrStyle.muted(context))),
          ),
          GestureDetector(
            key: const ValueKey('xrKwClr'),
            behavior: HitTestBehavior.opaque,
            // ignore: invalid_use_of_protected_member
            onTap: () => setState(() => _selKw = null),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text('清除',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _XrStyle.accent(context))),
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
      // ignore: invalid_use_of_protected_member
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
                border: Border.all(color: _XrStyle.accent(context), width: 2),
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
                        color: sel ? _XrStyle.accent(context) : Color(0xFFE2E8F0),
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
                    style: TextStyle(fontSize: 9, color: _XrStyle.muted(context))),
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
                  style: TextStyle(fontSize: 9.5, color: _XrStyle.muted(context), height: 1.4),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------- 详情子页（xrDetailHtml + F12 剧透保护） ----------
}
/// F7-6：列表「一行是什么」的标记（真实词条行直接用 `XrayEntityRow` 本身）。
class _XrKwBar {
  const _XrKwBar();
}

class _XrLowMore {
  const _XrLowMore();
}

class _XrSortPill {
  const _XrSortPill();
}

class _XrTail {
  const _XrTail();
}
