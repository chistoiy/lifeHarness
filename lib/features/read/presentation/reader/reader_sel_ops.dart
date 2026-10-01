part of 'reader_page.dart';

// 治理G7c2：选区/划线逻辑群自 _ReaderPageState 移入同库扩展（行为零改动·直访私有字段）。
// 群内成员＝选区文本/句粒度命中/划线增删/工具条动作（复制·分享·书摘·词典·AI），
// 以及手柄定位（_selAnchor/_paraRender/_dragSel/_paraHitAt）与 AI 解读弹层 _BrAiSheet。
extension _ReaderSelOps on _ReaderPageState {
  // ---------- 批3 划词/划线（原型 brSelect / brAddHl / brDelHl · L5 同库） ----------


  String get _selTxt {
    final sel = _selController.sel;
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



  /// 长按落点 → 段内字符偏移（纯原生 RenderParagraph，确定性）。
  /// V1.53.2：停用 ParaBoxCache 命中（缓存填充时机不定 + 与 anchor 坐标源不一致，
  /// 导致「时偏时不偏」）；shift 改动态取渲染前缀长度，与 _selAnchor 完全同源。
  int? _charPosInPara(int ci, int pi, Offset global) {
    final doc = _doc;
    if (doc == null) return null;
    final ps = doc.chapters[ci].paras;
    if (pi >= ps.length) return null;
    final rb = _paraRender(ci, pi);
    if (rb == null) return null;
    final local = rb.globalToLocal(global);
    final pos = rb.getPositionForOffset(local);
    final full = rb.text.toPlainText();
    // 渲染文本比原文多出的＝缩进前缀（动态，与 _selAnchor 的 shift 同式）。
    final shift = (full.length - ps[pi].text.length).clamp(0, full.length);
    final r = (pos.offset - shift).clamp(0, ps[pi].text.length);
    return r;
  }


  /// V1.53.4④ 选字档命中盒：[idx, idx+1)；段尾越界回退一格（空段=0..0）。
  ({int a, int b}) _charSel(String t, int idx) {
    if (t.isEmpty) return (a: 0, b: 0);
    final a = idx >= t.length ? t.length - 1 : idx;
    return (a: a, b: a + 1);
  }

  /// 真机反馈（2026-09-28）+ 轮4③：长按命中一句；同段再长按＝收起；
  /// 点其它段落＝移动选区。点按已不落到这里（冒泡 body 层收放 chrome）。
  void _selectPara(int ci, int pi, {Offset? at}) {
    final doc = _doc;
    if (doc == null) return;
    final ps = doc.chapters[ci].paras;
    if (pi >= ps.length) return;
    if (_selController.sel != null && _lpCi == ci && _lpPi == pi) {
      _clearSel();
      return;
    }
    final idx = at == null ? 0 : _charPosInPara(ci, pi, at) ?? 0;
    // V1.53.4④ 长按选择粒度（read.brSelGran）：选字＝命中单字可拖手柄扩；选句＝整句。
    final se = _brSelGran == '选句'
        ? _sentenceAt(ps[pi].text, idx)
        : _charSel(ps[pi].text, idx);
    _lpCi = ci;
    _lpPi = pi;
    // ignore: invalid_use_of_protected_member
    setState(() {
      _selController.setSelection(ci: ci, p0: pi, p1: pi, o0: se.a, o1: se.b);
      _hlPop = false;
      // 真机反馈（2026-09-28）：摘抄操作要在有顶栏的界面里做——
      // 建选区即展开 chrome，书名/计时/搜索/设置随顶栏可见。
      _chrome = true;
    });
  }

  /// V1.53.2 选区放大镜：抓正文快照 + 记录手指落点（Stack 局部坐标）。
  void _setLoupe(Offset? global) {
    if (global == null) {
      _loupeImage?.dispose();
      _loupeImage = null;
      // ignore: invalid_use_of_protected_member
      setState(() => _loupeFocal = null);
      return;
    }
    final rb = _stackKey.currentContext?.findRenderObject();
    final local = rb is RenderBox ? rb.globalToLocal(global) : global;
    _loupeAtFocal(local);
  }

  /// V1.53.2 选区放大镜：以**选区端点 anchor** 为焦点（与手柄圆点同源坐标），
  /// 而非手指触点——消除手指按在有尺寸圆点上造成的 2~3 汉字偏差。
  void _loupeAtEnd(bool end) {
    final anchor = _selAnchor(end); // 已是 Stack 局部坐标
    if (anchor == null) return;
    _loupeAtFocal(anchor);
  }

  /// 抓帧 + 落焦（focal 为 Stack 局部坐标）。
  void _loupeAtFocal(Offset local) {
    final bo = _contentBoundaryKey.currentContext?.findRenderObject();
    ui.Image? img;
    if (bo is RenderRepaintBoundary) {
      img = bo.toImageSync(
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
    }
    _loupeImage?.dispose();
    _loupeImage = img;
    // ignore: invalid_use_of_protected_member
    setState(() => _loupeFocal = local);
  }

  /// V1.53.2 选区放大镜：长按拖动时，选区实时跟随手指下的句子（松手前不落定工具条）。
  void _extendSelTo(int ci, Offset global) {
    final doc = _doc;
    if (doc == null) return;
    final hit = _paraHitAt(ci, global);
    if (hit == null) return;
    final ps = doc.chapters[ci].paras;
    if (hit.pi >= ps.length) return;
    // V1.53.4④ 拖动跟手同样按粒度档命中（选字＝单字随指走）。
    final se = _brSelGran == '选句'
        ? _sentenceAt(ps[hit.pi].text, hit.off)
        : _charSel(ps[hit.pi].text, hit.off);
    _lpCi = ci;
    _lpPi = hit.pi;
    // ignore: invalid_use_of_protected_member
    setState(() {
      _selController.setSelection(
        ci: ci,
        p0: hit.pi,
        p1: hit.pi,
        o0: se.a,
        o1: se.b,
      );
      _hlPop = false;
    });
  }

  // ignore: invalid_use_of_protected_member
  void _clearSel() => setState(() {
    _selController.clear();
    _hlPop = false;
    _lpCi = -1;
    _lpPi = -1;
    // 关闭选区时一并收起放大镜，避免残留。
    _loupeImage?.dispose();
    _loupeImage = null;
    _loupeFocal = null;
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
    // V1.53.4④⑤ 设置组改动即时生效（与 brSync 同链路重读）。
    _brSelGran = (await repo.kv('read.brSelGran')) ?? '选字';
    _brSelTools = brSelToolsDecode(await repo.kv('read.brSelBar'));
    _hlQuotes = (await repo.quotesOf(widget.bookId))
        .where((q) => q.deletedAt == null && q.cf != null)
        .toList(growable: false);
    _localHl = _LocalHl.decodeAll(await repo.kv('reader.hl'));
    // ignore: invalid_use_of_protected_member
    if (mounted) setState(() {});
  }

  Future<void> _addHl(String tg) async {
    final sel = _selController.sel;
    final doc = _doc;
    final pag = _pag;
    final body = _selTxt;
    if (sel == null || doc == null || body.isEmpty) return;
    final repo = ref.read(readRepositoryProvider);
    final cf = QuoteCf(c: sel.ci, p0: sel.p0, p1: sel.p1);
    final rid = 'r${DateTime.now().millisecondsSinceEpoch}';
    var flash = '已划线（$tg）· 同步进本书书摘';
    if (_brSync) {
      // 硬约束①：划线即一条「划线」型书摘直接进既有摘录表，携带 cf+rid。
      final now = DateTime.now().millisecondsSinceEpoch;
      final ch = doc.chapters[sel.ci].title;
      final pg = pag == null ? null : pag.gPosEst(sel.ci, 0) + 1;
      final id = await repo.addQuote(
        BookQuote(
          bookId: widget.bookId,
          kind: BookQuote.kKindMark,
          tag: tg,
          body: body,
          chapter: ch,
          page: pg,
          cf: cf,
          rid: rid,
          origin: '阅读器',
          createdAt: now,
          updatedAt: now,
        ),
      );
      if (id == null) {
        // 真机反馈⑤：同键在库行（手抄摘录无 cf）撞车——旧实现静默丢划线致
        // 「正文不上色、书摘里却有」；现在给命中行补 cf/rid/色类，划线定位到该行。
        final hit = await repo.attachCfOnDup(
            widget.bookId, ch, pg, body, cf, rid, tg);
        if (hit) flash = '已在书摘中，已定位（$tg）';
      }
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
      _selController.clear();
      _hlPop = false;
    });
    ref.read(readTickProvider.notifier).state++;
    _showFlash(flash);
    readToast(context, '高亮即一条划线书摘 · 笔记库可查（联动 L5）');
  }

  Future<void> _delHl() async {
    final sel = _selController.sel;
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
    setState(() => _selController.clear());
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
    final sel = _selController.sel;
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
    final sel = _selController.sel;
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
    final sel = _selController.sel;
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

  /// AI 解读（V1.53.4② 二选一）：先弹「解释词句 / 深度解读」，选后进统一入口
  /// aiRunWithReview（架构守护 R7 · 需求清单 §六 原则 8）。解释走新能力点
  /// read.explain（expect text，占位 text/book），深度解读沿用 read.quote_insight。
  /// 门控/发送前审阅/进度与取消/四态留痕与 token 台账都在通道内，阅读侧只渲染结果。
  Future<void> _actAi() async {
    final sel = _selController.sel;
    final doc = _doc;
    if (sel == null || doc == null) return;
    final quote = _selTxt;
    final book = _book?.title ?? doc.title;
    _clearSel();
    final mode = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sc) => _BrAiChoiceSheet(quote: quote),
    );
    if (mode == null || !mounted) return; // 关掉弹层＝放弃
    final explain = mode == 'explain';
    final res = await aiRunWithReview(
      context,
      ref,
      taskId: explain ? 'read.explain' : 'read.quote_insight',
      vars: explain
          ? {'text': quote, 'book': book}
          : {'quote': quote, 'book': book},
    );
    if (res == null || !mounted) return; // 取消/门控拒绝/失败已由通道提示并留痕
    final j = res.json;
    final insight = explain
        ? res.requireText().trim()
        : ('${j != null ? j['insight'] ?? '' : res.requireText()}').trim();
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sc) => _BrAiSheet(
        title: explain ? 'AI 解释' : 'AI 深度解读',
        insight: insight.isEmpty ? '（返回为空）' : insight,
        onToQuote: (txt) {
          Navigator.of(sc).pop();
          showQuoteEditPage(
            context,
            ref,
            bookId: widget.bookId,
            preBody: quote.length > 120 ? quote.substring(0, 120) : quote,
            preThought:
                '${explain ? '【AI 解释】' : '【AI 解读】'}$txt',
            focusThought: true,
          );
        },
      ),
    );
  }

  /// R14-6 · 选区工具条让位（原型 brSelBarPlace 三规则直译，2026-09-30 C 方案）：
  /// ① 首选上贴：条底边贴选区上方空白 · 箭头朝下；
  /// ② 上方放不下（选区贴近顶栏）→ 下压到选区底边之下 · 箭头翻上；
  /// ③ 下方也放不下 → 贴屏下沿（底栏上方），选区留在条下方。
  /// 选区跨度取首/尾端整段盒（原型 el0/el1 getBoundingClientRect 口径）。
  ({double top, bool flip}) _selBarPlace(Size size) {
    const fallback = (top: 120.0, flip: false);
    final s = _selController.sel, doc = _doc;
    final sb = _stackKey.currentContext?.findRenderObject();
    if (s == null || doc == null || sb is! RenderBox || !sb.hasSize) {
      return fallback;
    }
    final rb0 = _paraRender(s.ci, s.p0);
    if (rb0 == null) return fallback;
    final rb1 = _paraRender(s.ci, s.p1) ?? rb0;
    final selTop = sb.globalToLocal(rb0.localToGlobal(Offset.zero)).dy;
    final selBottom =
        sb.globalToLocal(rb1.localToGlobal(Offset.zero)).dy + rb1.size.height;
    // cT/cB＝顶/底栏实测高（可见时）＋ 8px 间距（原型 cT/cB 口径）。
    final cT = (_chrome ? _topBarH : 0.0) + 8;
    final cB = (_chrome && _pag != null ? _bottomBarH : 0.0) + 8;
    final tAbove = selTop - 8 - kBrSelBarH; // 上贴：条底边＝选区顶-8
    final tBelow = selBottom + 8; // 下压：条顶边＝选区底+8
    final roomAbove = tAbove >= cT;
    final roomBelow = tBelow + kBrSelBarH <= size.height - cB;
    if (!roomAbove && roomBelow) return (top: tBelow, flip: true);
    if (!roomBelow) return (top: size.height - cB - kBrSelBarH, flip: false);
    return (top: tAbove, flip: false);
  }

  /// 选区端点 → 舞台 Stack 内坐标（RenderParagraph 取字符盒）。
  Offset? _selAnchor(bool end) {
    final s = _selController.sel, doc = _doc;
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

  /// 当前页已渲染文字段的垂直范围（全局坐标）；一页都没渲染则 null。
  ({double top, double bottom})? _pageRect(int ci, List<int> page) {
    double? top, bottom;
    for (final pi in page) {
      final rb = _paraRender(ci, pi);
      if (rb == null || !rb.hasSize) continue;
      final o = rb.localToGlobal(Offset.zero);
      if (top == null || o.dy < top) top = o.dy;
      if (bottom == null || o.dy + rb.size.height > bottom) bottom = o.dy + rb.size.height;
    }
    if (top == null || bottom == null) return null;
    return (top: top, bottom: bottom);
  }

  /// 页内首个/末个可命中文字段（与 _paraHitAt 同口径跳过非 text 段）。
  int? _pageEdgePi(int ci, List<int> page, {required bool last}) {
    final ps = _doc!.chapters[ci].paras;
    for (final pi in last ? page.reversed : page) {
      if (ps[pi].kind == EpubParaKind.text) return pi;
    }
    return null;
  }

  /// V1.53.4 ① 头/尾手柄跨页扩选（工单 20261001-①）：翻页模式只渲染当前页，
  /// 拖出页文字区上（首手柄）/下（尾手柄）沿时——同章内自动翻页一次，并把被拖端
  /// 落锚到邻页交界段（首端＝上一页末段整段、尾端＝下一页首段整段），后续帧在新页
  /// 上按手指位置继续命中扩选。跨章扩选受划线 cf（单章 c/p0/p1）模型限制，本批
  /// 不做，维持旧「钳到页边」行为。返回 true＝本帧已由翻页逻辑消费。
  bool _edgeFlipSel(bool end, Offset global) {
    if (_selFlipPending) return true; // 新页渲染落定前吞事件，防一帧连翻多页
    if (_cfg.mode == 'scroll') return false;
    final doc = _doc, pag = _pag, s = _selController.sel;
    if (doc == null || pag == null || s == null) return false;
    if (_pos.ci != s.ci) return false; // 显示章≠选区章：交回原命中逻辑
    final pages = pag.pages[s.ci];
    if (pages == null || pages.isEmpty) return false;
    final pg = _pos.pg.clamp(0, pages.length - 1);
    final d = end ? 1 : -1;
    final target = pg + d;
    if (target < 0 || target >= pages.length) return false; // 章界：不跨章
    final cur = _pageRect(s.ci, pages[pg]);
    if (cur == null) return false;
    final outside = d < 0 ? global.dy < cur.top : global.dy > cur.bottom;
    if (!outside) return false;
    final a = _pageEdgePi(s.ci, pages[target], last: d < 0);
    if (a == null) return false;
    _flip(d);
    // ignore: invalid_use_of_protected_member
    setState(() {
      if (d < 0) {
        _selController.setSelection(ci: s.ci, p0: a, p1: s.p1, o0: 0, o1: s.o1);
      } else {
        _selController.setSelection(
          ci: s.ci, p0: s.p0, p1: a, o0: s.o0, o1: doc.chapters[s.ci].paras[a].text.length,
        );
      }
      _lpPi = d < 0 ? _selController.sel!.p0 : _selController.sel!.p1;
      _hlPop = false;
      _selFlipPending = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ignore: invalid_use_of_protected_member
      if (mounted) setState(() => _selFlipPending = false);
    });
    return true;
  }

  /// 手柄拖动：把端点落到指针所在段/字符（跨段自动整段吞并），两端可互换。
  /// V1.53.4 ①：拖出当前页文字区上/下沿 → 同章自动翻页并延续扩选。
  void _dragSel({required bool end, required Offset global}) {
    final s = _selController.sel, doc = _doc;
    if (s == null || doc == null) return;
    if (_edgeFlipSel(end, global)) return;
    final hit = _paraHitAt(s.ci, global);
    if (hit == null) return;
    // ignore: invalid_use_of_protected_member
    setState(() {
      if (end) {
        if (hit.pi < s.p0 || (hit.pi == s.p0 && hit.off <= s.o0)) {
          // 拖过首端＝互换，首端跟随旧尾端。
          _selController.setSelection(
            ci: s.ci,
            p0: hit.pi,
            p1: s.p0,
            o0: hit.off,
            o1: s.o0,
          );
        } else {
          _selController.setSelection(
            ci: s.ci,
            p0: s.p0,
            p1: hit.pi,
            o0: s.o0,
            // 治理backlog①：旧式 `hit.off==0 && 空段 ? 0 : hit.off` 两分支同值＝恒等死条件，
            // 简化为 hit.off（伴随删去仅此处使用的 ps 局部）。
            o1: hit.off,
          );
        }
        _lpPi = _selController.sel!.p1;
      } else {
        if (hit.pi > s.p1 || (hit.pi == s.p1 && hit.off >= s.o1)) {
          _selController.setSelection(
            ci: s.ci,
            p0: s.p1,
            p1: hit.pi,
            o0: s.o1,
            o1: hit.off,
          );
        } else {
          _selController.setSelection(
            ci: s.ci,
            p0: hit.pi,
            p1: s.p1,
            o0: hit.off,
            o1: s.o1,
          );
        }
        _lpPi = _selController.sel!.p0;
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

/// V1.53.4② AI 解读二选一（原型 sheetBrAiChoice）：解释词句 / 深度解读。
/// 返回 'explain' / 'insight'；直接关掉＝null（放弃）。引文只回显，不请求。
class _BrAiChoiceSheet extends StatelessWidget {
  const _BrAiChoiceSheet({required this.quote});

  final String quote;

  Widget _row(BuildContext context, String key, String mode, String title,
          String sub, IconData ic) =>
      InkWell(
        key: ValueKey(key),
        onTap: () => Navigator.pop(context, mode),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: .6)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(ic, size: 17, color: const Color(0xFF6366F1)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(sub,
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFF94A3B8))),
                  ],
                ),
              ),
              const Text('›',
                  style: TextStyle(fontSize: 14, color: Color(0xFFCBD5E1))),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => _BrSheetShell(
        sheetKey: const ValueKey('sheetBrAiChoice'),
        children: [
          const Text('AI 解读',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: .05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              quote,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, height: 1.5),
            ),
          ),
          const SizedBox(height: 12),
          _row(context, 'brAiChoiceExplain', 'explain', '解释词句', '释义 · 背景 · 简析',
              Icons.menu_book_outlined),
          const SizedBox(height: 8),
          _row(context, 'brAiChoiceInsight', 'insight', '深度解读', '论证链 · 感想与标签',
              Icons.auto_awesome_rounded),
        ],
      );
}

class _BrAiSheet extends StatelessWidget {
  const _BrAiSheet({
    required this.title,
    required this.insight,
    required this.onToQuote,
  });

  final String title;
  final String insight;
  final void Function(String insight) onToQuote;

  @override
  Widget build(BuildContext context) {
    return _BrSheetShell(
      sheetKey: const ValueKey('sheetBrAi'),
      children: [
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
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

