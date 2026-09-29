part of 'reader_page.dart';

// 治理G7c2：选区/划线逻辑群自 _ReaderPageState 移入同库扩展（行为零改动·直访私有字段）。
// 群内成员＝选区文本/句粒度命中/划线增删/工具条动作（复制·分享·书摘·词典·AI），
// 以及手柄定位（_selAnchor/_paraRender/_dragSel/_paraHitAt）与 AI 解读弹层 _BrAiSheet。
extension _ReaderSelOps on _ReaderPageState {
  // ---------- 批3 划词/划线（原型 brSelect / brAddHl / brDelHl · L5 同库） ----------


  String get _selTxt {
    final sel = _sel;
    final doc = _doc;
    if (sel == null || doc == null) return '';
    final ps = doc.chapters[sel.ci].paras;
    final out = <String>[];
    for (var i = sel.p0; i <= sel.p1 && i < ps.length; i++) {
      final t = ps[i].text;
      out.add(
        i == sel.p0 && i == sel.p1
            ? t.substring(sel.o0.clamp(0, t.length), sel.o1.clamp(0, t.length))
            : i == sel.p0
            ? t.substring(sel.o0.clamp(0, t.length))
            : i == sel.p1
            ? t.substring(0, sel.o1.clamp(0, t.length))
            : t,
      );
    }
    return out.join('\n');
  }

  // ---------- 轮4③ 句粒度选区（参考微信读书：长按默认选中一句） ----------



  /// 长按落点 → 段内字符偏移（RenderParagraph 精确命中；拿不到回落段首）。
  int? _charPosInPara(int ci, int pi, Offset global) {
    final doc = _doc;
    if (doc == null) return null;
    final ps = doc.chapters[ci].paras;
    if (pi >= ps.length) return null;
    // 治理backlog④：定位链改复用 _paraRender（key→Element→renderObject→首
    // RenderParagraph 与其完全同形，旧写法在此重复一遍并多一次 `as Element` 硬转）。
    final rb = _paraRender(ci, pi);
    if (rb == null) return null;
    final local = rb.globalToLocal(global);
    final pos = rb.getPositionForOffset(local);
    // 显示文本 = kParaIndent 前缀 + 原文（仅 text 段且开缩进）。
    final shift = ps[pi].kind == EpubParaKind.text && _cfg.indent
        ? kParaIndent.length
        : 0;
    return (pos.offset - shift).clamp(0, ps[pi].text.length);
  }


  /// 真机反馈（2026-09-28）+ 轮4③：长按命中一句；同段再长按＝收起；
  /// 点其它段落＝移动选区。点按已不落到这里（冒泡 body 层收放 chrome）。
  void _selectPara(int ci, int pi, {Offset? at}) {
    final doc = _doc;
    if (doc == null) return;
    final ps = doc.chapters[ci].paras;
    if (pi >= ps.length) return;
    if (_sel != null && _lpCi == ci && _lpPi == pi) {
      _clearSel();
      return;
    }
    final idx = at == null ? 0 : _charPosInPara(ci, pi, at) ?? 0;
    final se = _sentenceAt(ps[pi].text, idx);
    _lpCi = ci;
    _lpPi = pi;
    // ignore: invalid_use_of_protected_member
    setState(() {
      _sel = (ci: ci, p0: pi, p1: pi, o0: se.a, o1: se.b);
      _hlPop = false;
      // 真机反馈（2026-09-28）：摘抄操作要在有顶栏的界面里做——
      // 建选区即展开 chrome，书名/计时/搜索/设置随顶栏可见。
      _chrome = true;
    });
  }

  // ignore: invalid_use_of_protected_member
  void _clearSel() => setState(() {
    _sel = null;
    _hlPop = false;
    _lpCi = -1;
    _lpPi = -1;
  });

  /// 段生效划线（原型 brHlAt：库内行优先，多条取最后；回落暂存行）。
  ({String tg, Color c, bool hasThought})? _hlAt(int ci, int pi) {
    ({String tg, Color c, bool hasThought})? hit;
    for (final h in _localHl) {
      if (h.bookId == widget.bookId && h.cf.covers(ci, pi)) {
        hit = (
          tg: h.tg,
          c: Color(0xFF000000 | (BookQuote.hexToInt(BookQuote.colorHex[h.tg]) ?? 0xFDE047)),
          hasThought: false,
        );
      }
    }
    for (final q in _hlQuotes) {
      if (q.cf!.covers(ci, pi)) {
        hit = (
          tg: q.tag,
          c: Color(0xFF000000 | q.colorInt),
          hasThought: (q.thought ?? '').isNotEmpty,
        );
      }
    }
    return hit;
  }

  Future<void> _reloadHls() async {
    final repo = ref.read(readRepositoryProvider);
    _brSync = (await repo.kv('read.brSync')) != 'false';
    _hlQuotes = (await repo.quotesOf(widget.bookId))
        .where((q) => q.deletedAt == null && q.cf != null)
        .toList(growable: false);
    _localHl = _LocalHl.decodeAll(await repo.kv('reader.hl'));
    // ignore: invalid_use_of_protected_member
    if (mounted) setState(() {});
  }

  Future<void> _addHl(String tg) async {
    final sel = _sel;
    final doc = _doc;
    final pag = _pag;
    final body = _selTxt;
    if (sel == null || doc == null || body.isEmpty) return;
    final repo = ref.read(readRepositoryProvider);
    final cf = QuoteCf(c: sel.ci, p0: sel.p0, p1: sel.p1);
    final rid = 'r${DateTime.now().millisecondsSinceEpoch}';
    if (_brSync) {
      // 硬约束①：划线即一条「划线」型书摘直接进既有摘录表，携带 cf+rid。
      final now = DateTime.now().millisecondsSinceEpoch;
      await repo.addQuote(
        BookQuote(
          bookId: widget.bookId,
          kind: BookQuote.kKindMark,
          tag: tg,
          body: body,
          chapter: doc.chapters[sel.ci].title,
          page: pag == null ? null : pag.gPosEst(sel.ci, 0) + 1,
          cf: cf,
          rid: rid,
          origin: '阅读器',
          createdAt: now,
          updatedAt: now,
        ),
      );
    } else {
      // brSync 关：暂存本地全量 kv，开库后由渲染层按 cf 生效（原型 BR_LOCAL_HL）。
      final next = [
        ..._localHl,
        _LocalHl(id: rid, bookId: widget.bookId, cf: cf, tg: tg),
      ];
      await repo.setKv('reader.hl', _LocalHl.encodeAll(next));
    }
    await _reloadHls();
    if (!mounted) return;
    // ignore: invalid_use_of_protected_member
    setState(() {
      _sel = null;
      _hlPop = false;
    });
    ref.read(readTickProvider.notifier).state++;
    _showFlash('已划线（$tg）· 同步进本书书摘');
    readToast(context, '高亮即一条划线书摘 · 笔记库可查（联动 L5）');
  }

  Future<void> _delHl() async {
    final sel = _sel;
    if (sel == null) return;
    final repo = ref.read(readRepositoryProvider);
    var n = 0;
    // 删除互清：删划线＝软删对应书摘行（笔记库同款可撤销语义）。
    for (final q in _hlQuotes) {
      final cf = q.cf!;
      if (q.id != null && cf.c == sel.ci && cf.p0 == sel.p0 && cf.p1 == sel.p1) {
        await repo.softDeleteQuote(q.id!);
        n++;
      }
    }
    final keep = _localHl.where((h) {
      final cf = h.cf;
      return !(h.bookId == widget.bookId && cf.c == sel.ci && cf.p0 == sel.p0 && cf.p1 == sel.p1);
    }).toList();
    if (keep.length != _localHl.length) {
      n += _localHl.length - keep.length;
      await repo.setKv('reader.hl', _LocalHl.encodeAll(keep));
    }
    await _reloadHls();
    if (!mounted) return;
    // ignore: invalid_use_of_protected_member
    setState(() => _sel = null);
    ref.read(readTickProvider.notifier).state++;
    readToast(context, n > 0 ? '已删除划线（书摘同步移除）' : '此处没有划线可删');
  }

  void _actCopy() {
    final t = _selTxt;
    if (t.isEmpty) return;
    Clipboard.setData(ClipboardData(text: t));
    _clearSel();
    readToast(context, '已复制 ${t.length} 字');
  }

  void _actShare() {
    final sel = _sel;
    final doc = _doc;
    if (sel == null || doc == null) return;
    // 治理backlog⑥：出处引用尾段＝当前页号（与书签/进度条同用 _pos.pg 口径）；
    // 旧实现误传段序号 sel.p0 → 量纲错位（原型 brShare 已同步修正）。
    final txt =
        '$_selTxt\n\n——《${_book?.title ?? ''}》${doc.chapters[sel.ci].title} · ${_cfi(sel.ci, _pos.pg)}';
    Clipboard.setData(ClipboardData(text: txt));
    _clearSel();
    readToast(context, '分享文本已复制 · 含出处引用');
  }

  void _actQuote(bool thought) {
    final sel = _sel;
    final doc = _doc;
    final pag = _pag;
    if (sel == null || doc == null) return;
    final body = _selTxt;
    final ch = doc.chapters[sel.ci].title;
    final pg = pag == null ? null : pag.gPosEst(sel.ci, 0) + 1;
    _clearSel();
    showQuoteEditPage(
      context,
      ref,
      bookId: widget.bookId,
      preBody: body,
      preChapter: ch,
      prePage: pg,
      focusThought: thought,
    );
  }

  /// 词典取词（原型 BR_DICT：去空白 ≤4 字 · 互含模糊匹配 · 未收录回退）。
  void _actDict() {
    final sel = _sel;
    if (sel == null) return;
    // 治理backlog②：_selTxt 只读 _sel/_doc，本函数内同步取一次复用（旧代码取两次）。
    final selTxt = _selTxt;
    final w = selTxt.replaceAll(RegExp(r'\s'), '');
    final word = w.length > 4 ? w.substring(0, 4) : w;
    String? hitKey;
    for (final k in _kBrDict.keys) {
      if (word.contains(k) || k.contains(word)) {
        hitKey = k;
        break;
      }
    }
    final e = hitKey == null ? null : _kBrDict[hitKey];
    final bodyText = selTxt;
    _clearSel();
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sc) => _BrSheetShell(
        sheetKey: const ValueKey('sheetBrDict'),
        children: [
              Text(
                word.isEmpty ? '选词' : word,
                key: const ValueKey('brDcWord'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                e == null ? '— · 短语' : '${e.$1} · ${e.$2}',
                key: const ValueKey('brDcPh'),
                style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 10),
              Text(
                e?.$3 ?? '（本地词典未收录该词 · 可下载扩展词库）',
                style: const TextStyle(fontSize: 12.5, height: 1.6),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sc).pop(),
                      child: const Text('关闭'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('brDcToQuote'),
                      onPressed: () {
                        Navigator.of(sc).pop();
                        showQuoteEditPage(
                          context,
                          ref,
                          bookId: widget.bookId,
                          preBody: bodyText,
                          preThought:
                              '【$word】${e?.$3 ?? '释义见本地词典包'}',
                          focusThought: true,
                        );
                      },
                      child: const Text('释义填入想法'),
                    ),
                  ),
                ],
              ),
        ],
      ),
    );
  }

  /// AI 解读：走统一入口 aiRunWithReview（架构守护 R7 · 需求清单 §六 原则 8）。
  /// 门控/发送前审阅/进度与取消/四态留痕与 token 台账都在通道内，阅读侧只渲染结果。
  Future<void> _actAi() async {
    final sel = _sel;
    final doc = _doc;
    if (sel == null || doc == null) return;
    final quote = _selTxt;
    final book = _book?.title ?? doc.title;
    _clearSel();
    final res = await aiRunWithReview(
      context,
      ref,
      taskId: 'read.quote_insight',
      vars: {'quote': quote, 'book': book},
    );
    if (res == null || !mounted) return; // 取消/门控拒绝/失败已由通道提示并留痕
    final j = res.json;
    final insight =
        ('${j != null ? j['insight'] ?? '' : res.requireText()}').trim();
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sc) => _BrAiSheet(
        insight: insight.isEmpty ? '（返回为空）' : insight,
        onToQuote: (txt) {
          Navigator.of(sc).pop();
          showQuoteEditPage(
            context,
            ref,
            bookId: widget.bookId,
            preBody: quote.length > 120 ? quote.substring(0, 120) : quote,
            preThought: '【AI 解读】$txt',
            focusThought: true,
          );
        },
      ),
    );
  }

  /// 选区端点 → 舞台 Stack 内坐标（RenderParagraph 取字符盒）。
  Offset? _selAnchor(bool end) {
    final s = _sel, doc = _doc;
    final sb = _stackKey.currentContext?.findRenderObject();
    if (s == null || doc == null || sb is! RenderBox || !sb.hasSize) return null;
    final ps = doc.chapters[s.ci].paras;
    final pi = end ? s.p1 : s.p0;
    if (pi < 0 || pi >= ps.length) return null;
    final rb = _paraRender(s.ci, pi);
    if (rb == null) return null;
    final full = rb.text.toPlainText();
    if (full.isEmpty) return null;
    // 渲染文本比原始段文本多出的＝2em 缩进前缀（选中态也恒带前缀，见 _subSpan）。
    final shift = (full.length - ps[pi].text.length).clamp(0, full.length);
    final o = (end ? s.o1 : s.o0).clamp(0, ps[pi].text.length) + shift;
    final at = o.clamp(0, full.length);
    final r = end
        ? TextSelection(
            baseOffset: (at - 1).clamp(0, full.length),
            extentOffset: at,
          )
        : TextSelection(
            baseOffset: at,
            extentOffset: (at + 1).clamp(0, full.length),
          );
    final boxes = rb.getBoxesForSelection(r);
    if (boxes.isEmpty) return null;
    final b = end ? boxes.last : boxes.first;
    final g = rb.localToGlobal(Offset(end ? b.right : b.left, end ? b.bottom : b.top));
    return sb.globalToLocal(g);
  }

  RenderParagraph? _paraRender(int ci, int pi) {
    final ctx = _paraKeys['$ci:$pi']?.currentContext;
    if (ctx is! Element) return null;
    final ro = ctx.renderObject;
    if (ro == null) return null;
    return _firstRenderParagraph(ro);
  }

  /// 手柄拖动：把端点落到指针所在段/字符（跨段自动整段吞并），两端可互换。
  void _dragSel({required bool end, required Offset global}) {
    final s = _sel, doc = _doc;
    if (s == null || doc == null) return;
    final hit = _paraHitAt(s.ci, global);
    if (hit == null) return;
    // ignore: invalid_use_of_protected_member
    setState(() {
      if (end) {
        if (hit.pi < s.p0 || (hit.pi == s.p0 && hit.off <= s.o0)) {
          // 拖过首端＝互换，首端跟随旧尾端。
          _sel = (
            ci: s.ci,
            p0: hit.pi,
            p1: s.p0,
            o0: hit.off,
            o1: s.o0,
          );
        } else {
          _sel = (
            ci: s.ci,
            p0: s.p0,
            p1: hit.pi,
            o0: s.o0,
            // 治理backlog①：旧式 `hit.off==0 && 空段 ? 0 : hit.off` 两分支同值＝恒等死条件，
            // 简化为 hit.off（伴随删去仅此处使用的 ps 局部）。
            o1: hit.off,
          );
        }
        _lpPi = _sel!.p1;
      } else {
        if (hit.pi > s.p1 || (hit.pi == s.p1 && hit.off >= s.o1)) {
          _sel = (
            ci: s.ci,
            p0: s.p1,
            p1: hit.pi,
            o0: s.o1,
            o1: hit.off,
          );
        } else {
          _sel = (
            ci: s.ci,
            p0: hit.pi,
            p1: s.p1,
            o0: hit.off,
            o1: s.o1,
          );
        }
        _lpPi = _sel!.p0;
      }
      _hlPop = false;
    });
  }

  /// 指针 → (段序号, 段内字符偏移)：取垂直距离最近的可渲染文本段。
  ({int pi, int off})? _paraHitAt(int ci, Offset g) {
    final doc = _doc;
    if (doc == null) return null;
    final ps = doc.chapters[ci].paras;
    int? best;
    var bestD = double.infinity;
    for (var pi = 0; pi < ps.length; pi++) {
      if (ps[pi].kind != EpubParaKind.text) continue;
      final rb = _paraRender(ci, pi);
      if (rb == null || !rb.hasSize) continue;
      final top = rb.localToGlobal(Offset.zero);
      final rect = Rect.fromLTWH(top.dx, top.dy, rb.size.width, rb.size.height);
      final d = g.dy < rect.top
          ? rect.top - g.dy
          : (g.dy > rect.bottom ? g.dy - rect.bottom : 0.0);
      if (d < bestD) {
        bestD = d;
        best = pi;
      }
    }
    if (best == null) return null;
    final off = _charPosInPara(ci, best, g);
    if (off == null) return null;
    return (pi: best, off: off);
  }
}

/// AI 解读结果弹层（原型 sheetBrAi）：只渲染 aiRunWithReview 的应答。
/// 门控/审阅/进度/留痕都在通道内完成，这里不再有第二条 AI 调用路径（R7 接入门）。
/// 治理backlog③：阅读器小弹层统一外壳（原型 `.sheet` 内边距口径）。
/// 词典弹层与 _BrAiSheet 旧各自展开一份完全同形的 SafeArea+Padding+Column，现共用本件；
/// `key` 透传给 Column 以保持既有取证锚（sheetBrDict / sheetBrAi 不变）。
class _BrSheetShell extends StatelessWidget {
  const _BrSheetShell({required this.sheetKey, required this.children});

  final Key sheetKey;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
      child: Column(
        key: sheetKey,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    ),
  );
}

class _BrAiSheet extends StatelessWidget {
  const _BrAiSheet({required this.insight, required this.onToQuote});

  final String insight;
  final void Function(String insight) onToQuote;

  @override
  Widget build(BuildContext context) {
    return _BrSheetShell(
      sheetKey: const ValueKey('sheetBrAi'),
      children: [
            const Text(
              'AI 解读',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            SizedBox(
              key: const ValueKey('brAiOut'),
              height: 108,
              child: SingleChildScrollView(
                child: Text(insight, style: const TextStyle(fontSize: 13, height: 1.7)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('brAiCopy'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: insight));
                      readToast(context, '解读已复制');
                    },
                    child: const Text('复制'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('brAiToQuote'),
                    onPressed: () => onToQuote(insight),
                    child: const Text('填为感想'),
                  ),
                ),
              ],
            ),
      ],
    );
  }
}

