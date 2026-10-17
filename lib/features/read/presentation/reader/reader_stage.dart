part of 'reader_page.dart';

// 治理G7c3：舞台渲染群自 _ReaderPageState 移入同库扩展（行为零改动·直访私有字段）。
// _stage＝错误态/加载态/滚动窗口/翻页 AnimatedSwitcher 四态；_para＝段型分派＋划线底色＋选区子串高亮。
extension _ReaderStage on _ReaderPageState {
  // ---------- 舞台（翻页/滚动） ----------

  Widget _stage((String, Color, Color) th) {
    if (_err != null) {
      // F2-8（LH-L15）：取数/装载失败不再自绘红字+「返回」薄壳，接仓库既有失败卡
      // （人话标题＋原因＋重试＋查看详情）；重试＝清错重跑装载链。
      return LoadErrorBanner(
        title: '这本书没能打开',
        error: _err!,
        onRetry: () {
          _clock?.cancel();
          // ignore: invalid_use_of_protected_member
          setState(() {
            _err = null;
            _doc = null;
            _slowHint = false;
          });
          unawaited(_boot());
        },
      );
    }
    final doc = _doc;
    final pag = _pag;
    if (doc == null || pag == null) {
      // R3-8④：装载挂住 8 秒后给可读状态与出口（白屏转圈只有强停一条路是事故）。
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            if (_slowHint) ...[
              const SizedBox(height: 12),
              const Text(
                key: ValueKey('br-slow-hint'),
                '整本书装载较慢 · 大书或内存紧张',
                style: TextStyle(fontSize: 11, color: Color(0x99000000)),
              ),
              TextButton(
                key: const ValueKey('br-load-giveup'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('先返回 · 稍后再进'),
              ),
            ],
          ],
        ),
      );
    }
    if (_cfg.mode == 'scroll') {
      // V1.53.1 轮4：滚动模式只渲染当前章窗口（前8后24章）——大书不再
      // 一次性 materialize 全书 2409 章（那是滚动卡顿的另一主因）。
      final lo = _pos.ci - 8 < 0 ? 0 : _pos.ci - 8;
      final hi = _pos.ci + 24 > doc.chapters.length - 1
          ? doc.chapters.length - 1
          : _pos.ci + 24;
      final flat = <(int, int)>[];
      for (var ci = lo; ci <= hi; ci++) {
        final ps = doc.chapters[ci].paras;
        for (var pi = 0; pi < ps.length; pi++) {
          flat.add((ci, pi));
        }
      }
      return ListView.builder(
        key: const ValueKey('br-scroll'),
        controller: _scrollCtrl,
        padding: EdgeInsets.fromLTRB(_cfg.mar, _cfg.mar + 30, _cfg.mar, _cfg.mar + 56),
        itemCount: flat.length,
        itemBuilder: (_, k) {
          final (ci, pi) = flat[k];
          // 滚动模式不分页＝整段一块（区间给 0..段长，与翻页模式走同一个 _para）。
          final pp = doc.chapters[ci].paras[pi];
          return _para(th, doc, ci, pp, pi, 0, pp.text.length);
        },
      );
    }
    final pages = pag.pages[_pos.ci] ?? const <PagPage>[<PagPiece>[]];
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
        // 键里必须是**插值后的章号**：`'page-$_pos.ci-$pg'` 取的是 `_pos` 的
        // toString＋字面量 ".ci"（探针按键找页容器时实测拿到
        // `page-Instance of '_Pos'.ci-11`）。
        key: ValueKey('page-${_pos.ci}-$pg'),
        alignment: Alignment.center,
        padding: EdgeInsets.fromLTRB(
          _cfg.mar,
          _cfg.mar + kBrChromeTopPad,
          _cfg.mar,
          _cfg.mar + kBrChromeBottomPad,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 页内逐块上屏（块＝段＋段内区间；超长段跨页续排，工单 §3H-A）。
            for (final b in pages[pg])
              _para(
                th,
                doc,
                _pos.ci,
                doc.chapters[_pos.ci].paras[b.pi],
                b.pi,
                b.from,
                b.to,
              ),
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



  /// 用户外观 → 文本样式（字号/行距/字距/字族/正文色）。
  /// **测量侧唯一对应物是 `ReaderLayout.base`**（两者字段必须一一对应，
  /// 少一项就是「按 A 量、按 B 画」＝页底裁字，工单 §3H-A 同源红线）。
  TextStyle _userText((String, Color, Color) th) => TextStyle(
    fontSize: _cfg.fs,
    height: _cfg.lh,
    letterSpacing: _cfg.ls,
    fontFamily: _cfg.fontFamily,
    fontFamilyFallback: _cfg.fontFamilyFallback,
    color: th.$3,
  );

  /// 页内一块的上屏（[from],[to]＝段内**原文坐标**区间；整段＝0..段长）。
  /// 超长段跨页续排后，同一 `pi` 会在相邻两页各出现一块（工单 §3H-A），
  /// 所以**容器键、命中闪底、GlobalKey 都必须带上 from**，只按 pi 判会两块同时命中。
  Widget _para(
    (String, Color, Color) th,
    EpubDoc doc,
    int ci,
    EpubPara p,
    int pi,
    int from,
    int to,
  ) {
    final isHit = _hitMark != null &&
        _hitMark!.ci == ci &&
        _hitMark!.pi == pi &&
        _hitMark!.from == from;
    // 批3：划线色底（原型 background: c+'44'）与选中段高亮；点段即划词。
    // F-13（2026-10-07）：一段吃**全部**生效划线，旧实现单条＝同段后划的线把先划的挤掉。
    const noHl = <BrHl>[];
    final hls = p.kind == EpubParaKind.image ? noHl : _hlsAt(ci, pi);
    final s = _selController.sel;
    final inSel = s != null && s.ci == ci && pi >= s.p0 && pi <= s.p1;
    // 轮4①：入库带偏移的 text 段＝span 级精确铺底（Container 不再整段涂）；
    // 旧数据无偏移、引文/标题段＝维持整段底色。活跃选区在场时瞬态整段浅底照旧。
    // 拆块后先与**本块区间求交**：交在外面的那段底色归另一页，本块不铺（§3H-A）。
    // F-13：多条各自求交成 hlSpans（createdAt 升序，重叠字符靠 `_textSpan` 取靠后者色）。
    // F-14（2026-10-07 真机反馈）：**选区在场时也算**——旧口径靠 Container 整段浅底兜住
    // 已有划线，改成多区间后不铺就会让划线在长按那一刻整段消失（产品图1）。
    final hlSpans = <({int a, int b, Color c})>[];
    bool hlLegacy = false; // 段内存在无精确 cf 的旧数据行
    if (p.kind == EpubParaKind.text) {
      for (final hl in hls) {
        if (!hl.cf.isPrecise) {
          hlLegacy = true;
          continue;
        }
        final r = hl.cf.rangeAt(pi, p.text.length);
        if (r == null) continue;
        final a = r.a > from ? r.a : from, b = r.b < to ? r.b : to;
        if (b > a) hlSpans.add((a: a, b: b, c: hl.c));
      }
    }
    // 整段底色只给「无任一精确区间」的旧数据口径（F-13 步骤3）；有 span 在场不再整段涂。
    final hlFull = hlLegacy && hlSpans.isEmpty;
    // 段内任一条带感想即出小标记（旧实现只看单条）。
    final hasThought = hls.any((h) => h.hasThought);
    // 轮4③：段内精确子串高亮（同段＝句选 o0/o1；跨段首尾各切一头）。
    var q0 = 0, q1 = p.text.length;
    if (s != null && inSel) {
      if (s.p0 == s.p1) {
        q0 = s.o0;
        q1 = s.o1;
      } else {
        if (pi == s.p0) q0 = s.o0;
        if (pi == s.p1) q1 = s.o1;
      }
    }
    final partSel = s != null && inSel && (q0 > 0 || q1 < p.text.length);
    Widget wrap(Widget child) => GestureDetector(
      // 块级键：首块（from==0）沿用旧串 `brpTap-章-段`，只有续排块才带起点后缀
      // ——同一段被拆两页时两个 GlobalKey 不会撞车，既有选区用例的命中键也不必整体改写。
      key: ValueKey('brpTap-$ci-$pi${from == 0 ? '' : '-$from'}'),
      behavior: HitTestBehavior.translucent,
      // V1.53 轮3（参考图4）：长按选中段落才弹摘抄工具条；
      // 点按不再命中这里 → 冒泡到 body 层分派（收放 chrome / 清选区）。
      // 轮4③：长按落点命中整句（微信读书口径），d.globalPosition → 段内偏移。
      // V1.53.2：长按拖动跟手扩到手指下的句子；放大镜改挂到手柄微调（见 brHandleWidget）。
      onLongPressStart: (d) =>
          _selectPara(ci, pi, at: d.globalPosition, from: from),
      onLongPressMoveUpdate: (d) => _extendSelTo(ci, d.globalPosition),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: kBrPadWrapH,
          vertical: kBrPadWrapV,
        ),
        // V1.53.2 修②：选中态不再整段铺底——部分选中（首/尾/单段局部）交给
        // _subSpan 精确子串高亮；仅整段选中（跨段的中间段）才铺段级底色。
        // 轮4①：精确划线的稳态底色进 span（hlSpans），Container 只在整段口径时铺。
        // F-13：整段底色（旧数据无 cf 偏移）取**最新**那条的色标。
        decoration: !hlFull && !(inSel && !partSel)
            ? null
            : BoxDecoration(
                color: inSel && !partSel
                    ? context.tokens.accent.withValues(alpha: .3) // F3-3
                    : (hls.isEmpty
                        ? null
                        : hls.last.c.withValues(alpha: .27)),
                borderRadius: BorderRadius.circular(3),
              ),
        child: hasThought
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  child,
                  // 原型 br-pulse 橙点：该划线带感想，点按提示去书摘库查看。
                  // F3-8：命中槽 24²（点 7 视觉右上对齐原位；44 不可行＝会把段后
                  // 空隙撑大 30px+，密排指示点例外登记工单）。
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 2),
                    child: GestureDetector(
                      key: ValueKey('brHlDot-$ci-$pi'),
                      onTap: () => readToast(context, '该划线已在书摘库 · 详情页可查看'),
                      child: Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.topRight,
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
          padding: const EdgeInsets.only(bottom: kBrPadImageBottom),
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
        // 样式改走 [paraStyle]（§3H-A 同源）：标题字号档与字重此前上屏自建、
        // 测量按基准字号量，每条标题少算约 1/4 行高。
        return Padding(
          padding: const EdgeInsets.only(
            top: kBrPadHeadTop,
            bottom: kBrPadHeadBottom,
          ),
          child: wrap(
            Text(
              // R3-6：标题与引文同样吃显示层简繁（走同一条 paraBody 通道）。
              // 拆块后只画本块区间（标题极少超页，但口径与正文保持一致）。
              paraBody(p, _cfg.s2t).substring(
                from,
                math.min(to, p.text.length),
              ),
              style: paraStyle(
                p,
                _userText(th),
                orig: _cfg.orig,
                pageBg: th.$2,
              ),
            ),
          ),
        );
      case EpubParaKind.quote:
        return Padding(
          padding: const EdgeInsets.only(bottom: kBrPadQuoteBottom),
          child: wrap(
            Container(
              padding: const EdgeInsets.only(left: kBrQuoteLeft),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: th.$3, width: kBrQuoteBarW),
                ),
              ),
              child: Text.rich(
                // ① 引文型注释体（blockquote epub:type=footnote 等）同样走正文色小字，
                // 与 [EpubPager.pieceHeight] 共用 paraSpan/paraOuter/paraMeasureW
                // ＋行高归一（§3H-A/B 同源红线：任何一件两边各算一份都会溢出或不齐）。
                paraSpan(
                  p,
                  _userText(th).copyWith(color: th.$3.withValues(alpha: .85)),
                  orig: _cfg.orig,
                  pageBg: th.$2,
                  s2t: _cfg.s2t,
                  from: from,
                  to: to,
                ),
              ),
            ),
          ),
        );
      case EpubParaKind.text:
        // 块级键：`$ci:$pi:$from`（同段两块＝两个不同的 GlobalKey，
        // 只按 pi 建键会在拆页后撞「重复 GlobalKey」并把同段两块同时点亮）。
        final bk = from == 0 ? '$ci:$pi' : '$ci:$pi:$from';
        final pk = _paraKeys.putIfAbsent(
          bk,
          () => GlobalKey(debugLabel: 'brp$bk'),
        );
        final span = partSel
            ? _subSpan(th, p, q0, q1, from, to, hlSpans: hlSpans)
            : _textSpan(
                th,
                doc,
                ci,
                p,
                pi,
                isHit,
                // 整段选中（跨段的中间段）时选区色优先，不再叠划线底色；
                // 部分选中走 _subSpan，那里划线与选区各铺各的（F-14）。
                hlSpans: inSel ? const [] : hlSpans,
                from: from,
                to: to,
              );
        return Padding(
          key: ValueKey('brp-$ci-$pi${from == 0 ? '' : '-$from'}'),
          padding: const EdgeInsets.only(bottom: kBrPadTextBottom),
          child: wrap(
            Text.rich(
              key: pk,
              span,
              // R3-2 ②：中文正文默认左对齐（两端对齐会把末行不满的字距拉散，
              // 真机读起来像表格）；两端对齐只在外观里显式开，默认关。
              textAlign: _cfg.just ? TextAlign.justify : TextAlign.start,
              // 行距拉平（§3H-B 拍板）：span 里每个字档的 height 已按本段最大字号归一。
            ),
          ),
        );
    }
  }
}
