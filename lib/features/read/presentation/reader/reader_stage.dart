part of 'reader_page.dart';

// 治理G7c3：舞台渲染群自 _ReaderPageState 移入同库扩展（行为零改动·直访私有字段）。
// _stage＝错误态/加载态/滚动窗口/翻页 AnimatedSwitcher 四态；_para＝段型分派＋划线底色＋选区子串高亮。
extension _ReaderStage on _ReaderPageState {
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
          return _para(th, doc, ci, doc.chapters[ci].paras[pi], pi);
        },
      );
    }
    final pages = pag.pages[_pos.ci] ?? const <List<int>>[<int>[]];
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
    // 批3：划线色底（原型 background: c+'44'）与选中段高亮；点段即划词。
    final hl = p.kind == EpubParaKind.image ? null : _hlAt(ci, pi);
    final s = _selController.sel;
    final inSel = s != null && s.ci == ci && pi >= s.p0 && pi <= s.p1;
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
      key: ValueKey('brpTap-$ci-$pi'),
      behavior: HitTestBehavior.translucent,
      // V1.53 轮3（参考图4）：长按选中段落才弹摘抄工具条；
      // 点按不再命中这里 → 冒泡到 body 层分派（收放 chrome / 清选区）。
      // 轮4③：长按落点命中整句（微信读书口径），d.globalPosition → 段内偏移。
      // V1.53.2：长按拖动跟手扩到手指下的句子；放大镜改挂到手柄微调（见 brHandleWidget）。
      onLongPressStart: (d) => _selectPara(ci, pi, at: d.globalPosition),
      onLongPressMoveUpdate: (d) => _extendSelTo(ci, d.globalPosition),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        // V1.53.2 修②：选中态不再整段铺底——部分选中（首/尾/单段局部）交给
        // _subSpan 精确子串高亮；仅整段选中（跨段的中间段）才铺段级底色。
        decoration: hl == null && !(inSel && !partSel)
            ? null
            : BoxDecoration(
                color: inSel && !partSel
                    ? const Color(0x4D6366F1)
                    : hl?.c.withValues(alpha: .27),
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
        final pk = _paraKeys.putIfAbsent(
          '$ci:$pi',
          () => GlobalKey(debugLabel: 'brp$ci-$pi'),
        );
        final span = partSel
            ? _subSpan(th, p, q0, q1)
            : _textSpan(th, doc, ci, p, pi, isHit);
        return Padding(
          key: ValueKey('brp-$ci-$pi'),
          padding: const EdgeInsets.only(bottom: 8),
          child: wrap(
            Text.rich(key: pk, span, textAlign: TextAlign.justify),
          ),
        );
    }
  }
}
