part of 'reader_page.dart';

// 治理G7c1：顶/底栏与文本构建六件自 _ReaderPageState 移入同库扩展（行为零改动·直访私有字段）。
extension _ReaderChrome on _ReaderPageState {
  Widget _topBar(BrBar bar) {
    final doc = _doc!;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: KeyedSubtree(
        key: const ValueKey('br-top'),
        // 真机反馈（2026-09-28）：不再用 BackdropFilter 毛玻璃——弹层/选区触发
        // 重合成时会把整页正文卷进模糊（引擎 backdrop 扩散）。底色改不透明（brBarOf）。
        // R14-6：外包尺寸探针回灌实测高度（选区工具条让位 cT 用）。
        child: BrSizeProbe(
          onSize: (s) {
            // ignore: invalid_use_of_protected_member
            if (mounted && s.height != _topBarH) setState(() => _topBarH = s.height);
          },
          child: Container(
          key: const ValueKey('brTopBox'),
          decoration: BoxDecoration(
            color: bar.bg,
            border: Border(bottom: BorderSide(color: bar.line)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      key: const ValueKey('br-back'),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.chevron_left_rounded,
                        color: bar.fg,
                        // R14-10：纯图标钮补语义标签（真机 uiautomator 可命中）。
                        semanticLabel: '返回',
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            _book?.title ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: bar.fg,
                            ),
                          ),
                          Text(
                            '${doc.chapters[_pos.ci.clamp(0, doc.chapters.length - 1)].title} · ${_cfg.mode == 'page' ? '翻页' : '滚动'}模式',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9,
                              color: bar.fg.withValues(alpha: .6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Container(
                        key: const ValueKey('br-sess-chip'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: bar.chip,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _clockText,
                          style: TextStyle(
                            fontSize: 9,
                            color: bar.fg,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                    // 全书检索入口（双入口之一；另一入口＝抽屉「搜本书」Tab）。
                    IconButton(
                      key: const ValueKey('brBtnSearch'),
                      visualDensity: VisualDensity.compact,
                      onPressed: _openSearch,
                      icon: Icon(
                        Icons.search_rounded,
                        size: 17,
                        color: bar.fg,
                        semanticLabel: '全书搜索', // R14-10
                      ),
                    ),
                    // 本书操作弹层入口（原型顶栏 ⋯）。
                    IconButton(
                      key: const ValueKey('brBtnMore'),
                      visualDensity: VisualDensity.compact,
                      onPressed: _openMoreSheet,
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        size: 19,
                        color: bar.fg,
                        semanticLabel: '更多操作', // R14-10
                      ),
                    ),
                  ],
                ),
                if (_hits.isNotEmpty && _hitI >= 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 2),
                    child: Row(
                      key: const ValueKey('brHitsBar'),
                      children: [
                        Text(
                          '${_hitI + 1}/${_hits.length} 处匹配 · “$_hitQ”',
                          style: TextStyle(
                            fontSize: 10,
                            color: bar.fg.withValues(alpha: .75),
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          key: const ValueKey('brHitPrev'),
                          onPressed: () => _hitStep(-1),
                          child: Text(
                            '上一处',
                            style: TextStyle(
                              fontSize: 10,
                              color: bar.fg,
                            ),
                          ),
                        ),
                        TextButton(
                          key: const ValueKey('brHitNext'),
                          onPressed: () => _hitStep(1),
                          child: Text(
                            '下一处',
                            style: TextStyle(
                              fontSize: 10,
                              color: bar.fg,
                            ),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('brHitClear'),
                          visualDensity: VisualDensity.compact,
                          // ignore: invalid_use_of_protected_member
                          onPressed: () => setState(() {
                            _hits = const [];
                            _hitI = -1;
                            _hitMark = null;
                          }),
                          icon: Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: bar.fg.withValues(alpha: .6),
                            semanticLabel: '清除搜索', // R14-10
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
          ),
          ),
        ),
      ),
    );
  }

  Widget _bottomBar(BrBar bar, Size size) {
    final pag = _pag!;
    final n = pag.chapterPages(_pos.ci);
    final gpEst = pag.gPosEst(_pos.ci, _pos.pg);
    final total = pag.estTotal;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: KeyedSubtree(
        key: const ValueKey('br-bottom'),
        // 同顶栏：去 BackdropFilter，防弹层/选区时整页模糊。
        // R14-6：外包尺寸探针回灌实测高度（选区工具条让位 cB 用）。
        child: BrSizeProbe(
          onSize: (s) {
            // ignore: invalid_use_of_protected_member
            if (mounted && s.height != _bottomBarH) setState(() => _bottomBarH = s.height);
          },
          child: Container(
          key: const ValueKey('brBottomBox'),
          decoration: BoxDecoration(
            color: bar.bg,
            border: Border(top: BorderSide(color: bar.line)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    // 轮5.4 后不再显示内部定位串（原型底栏只有页码标签 · 真机反馈 R14-3）。
                    Text(
                      // 全书页码为字符加权估算（约 1500 字/页 · foliate 口径）。
                      '${_pos.pg + 1}/$n 页 · 约第 ${gpEst + 1}/$total 页 · ${pag.pct(_pos.ci, _pos.pg)}%',
                      key: const ValueKey('brPgLbl'),
                      style: TextStyle(
                        fontSize: 9,
                        color: bar.fg.withValues(alpha: .7),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                // 轮5.1：三图标底栏（目录 / 进度 / 外观），主题·亮度·字号并入外观弹层。
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _brIconBtn(bar, 'brBtnToc', '目录', Icons.menu_rounded, () {
                        // ignore: invalid_use_of_protected_member
                        setState(() => _drawerOpen = true);
                      }),
                      _brIconBtn(
                        bar,
                        'brBtnProg',
                        '进度',
                        Icons.tune_rounded,
                        _openProgressSheet,
                      ),
                      _brIconBtn(
                        bar,
                        'brBtnLook',
                        '外观',
                        Icons.palette_outlined,
                        _openAppearance,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ),
        ),
      );
  }

  Widget _brIconBtn(
    BrBar bar,
    String key,
    String label,
    IconData icon,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      key: ValueKey(key),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: bar.chip.withValues(alpha: .0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 19, color: bar.fg),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: bar.fg.withValues(alpha: .8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 章节名闪现提示（轮5.2 拍板保留）：随主题取色，不再是固定黑底。
  Widget _flashBar(BrBar bar) {
    return Positioned(
      bottom: 120,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          key: const ValueKey('brFlash'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: bar.bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: bar.line),
          ),
          child: Text(
            _flash!,
            style: TextStyle(fontSize: 10, color: bar.fg),
          ),
        ),
      ),
    );
  }

  /// 轮4③：段内子串选中（无链接事件，仅选区底色一段）。
  TextSpan _subSpan((String, Color, Color) th, EpubPara p, int q0, int q1) {
    final base = paraStyle(
      p,
      TextStyle(
        fontSize: _cfg.fs,
        height: _cfg.lh,
        letterSpacing: _cfg.ls,
        fontFamily: _cfg.fontFamily,
        color: th.$3,
      ),
    );
    final a = q0.clamp(0, p.text.length);
    final b = q1.clamp(a, p.text.length);
    // 真机反馈（2026-09-28）：缩进前缀恒以普通文本渲染在最前——选中任何子串
    // 显示文本都与未选中一致，不再顶格重排；高亮也只包子串本体、不吞缩进。
    // R3-2 ③：前缀有无改按段判定（与 paraDisplayText 同一函数，两者不许分叉）。
    final pre = paraIndented(p, _cfg.indMode) ? kParaIndent : '';
    // R3-6：高亮支路也必须走 paraBody——它按原文偏移切片，转换器逐字等长，
    // 所以 a/b 在转换后的串上仍指同一个字；漏转＝选中一段就露出原文，简繁白切。
    final body = paraBody(p, _cfg.s2t);
    return TextSpan(
      style: base,
      children: [
        if (pre.isNotEmpty) TextSpan(text: pre),
        if (a > 0) TextSpan(text: body.substring(0, a)),
        TextSpan(
          text: body.substring(a, b),
          style: base.copyWith(backgroundColor: const Color(0x4D6366F1)),
        ),
        if (b < p.text.length) TextSpan(text: body.substring(b)),
      ],
    );
  }

  /// 段渲染：首行缩进（③ 按段判定）+ 链接 span（点击区）+ 命中底色。
  /// ① 注释体走正文色小字；④ 只有外链给链接绿。
  /// 轮4①：[hlRange]（原文坐标）＋[hlColor]＝已入库划线的**字符区间铺底**——
  /// 底色与链接/命中样式可叠加（背景只加不改字色），旧整段数据不走这里。
  TextSpan _textSpan(
    (String, Color, Color) th,
    EpubDoc doc,
    int ci,
    EpubPara p,
    int pi,
    bool hit, {
    ({int a, int b})? hlRange,
    Color? hlColor,
  }) {
    final base = paraStyle(
      p,
      TextStyle(
        fontSize: _cfg.fs,
        height: _cfg.lh,
        letterSpacing: _cfg.ls,
        fontFamily: _cfg.fontFamily,
        color: th.$3,
      ),
    );
    final display = paraDisplayText(
      p,
      indent: _cfg.indent,
      indMode: _cfg.indMode,
      s2t: _cfg.s2t,
    );
    // 段首缩进前缀的显示偏移＝显示文本比原文多出来的长度（③ 后不再恒为 2；
    // R3-6 的简繁转换逐字等长，所以这一差值仍然只反映缩进前缀）。
    final ind = display.length - p.text.length;
    final markStyle = base.copyWith(
      backgroundColor: const Color(0xFF6366F1).withValues(alpha: .28),
    );
    // 轮4①：划线底色＝色标 27% 透明（与旧整段 Container 铺底同值，观感连续）。
    final hlBg = hlColor?.withValues(alpha: .27);
    final children = <InlineSpan>[];
    // 事件流：链接起/止 + 命中起/止（显示文本偏移＝原始 +ind 缩进）+ 划线起/止。
    final events = <(int, int, EpubLink?)>[
      for (final l in p.links) ...[
        (l.start + ind, 0, l),
        (l.end + ind, 1, l),
      ],
      if (hit && _hitQ.isNotEmpty) ...[
        for (var idx = p.text.indexOf(_hitQ); idx >= 0; idx = p.text.indexOf(_hitQ, idx + 1)) ...[
          (idx + ind, 2, null),
          (idx + ind + _hitQ.length, 3, null),
        ],
      ],
      if (hlRange != null && hlBg != null && hlRange.b > hlRange.a) ...[
        (hlRange.a + ind, 4, null),
        (hlRange.b + ind, 5, null),
      ],
    ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    var cursor = 0;
    var inLink = 0;
    var inMark = 0;
    var inHl = 0;
    void flush(int to) {
      if (to <= cursor) return;
      final t = display.substring(cursor.clamp(0, display.length), to.clamp(0, display.length));
      if (t.isEmpty) {
        cursor = to;
        return;
      }
      final link = p.links.firstWhere(
        (l) => l.start + ind == cursor || (cursor >= l.start + ind && cursor < l.end + ind),
        orElse: () => EpubLink(start: -1, end: -1, href: '', external: false),
      );
      // ①④ 上色分派：外链绿 · 站内锚点正文色下划线 · 注释引用正文色小字。
      // 轮4①：划线底色独立叠加（在链接/命中样式之上 copyWith 背景）。
      var style = inLink > 0 ? linkStyleFor(base, link) : (inMark > 0 ? markStyle : base);
      if (inHl > 0 && hlBg != null) {
        style = style.copyWith(backgroundColor: hlBg);
      }
      children.add(
        TextSpan(
          text: t,
          style: style,
          recognizer: (inLink > 0 && link.start >= 0)
              ? (TapGestureRecognizer()..onTap = () => _onLink(link))
              : null,
        ),
      );
      cursor = to;
    }
    for (final (at, kind, _) in events) {
      flush(at);
      switch (kind) {
        case 0:
          inLink++;
        case 1:
          inLink = (inLink - 1).clamp(0, 1 << 20);
        case 2:
          inMark++;
        case 3:
          inMark = (inMark - 1).clamp(0, 1 << 20);
        case 4:
          inHl++;
        case 5:
          inHl = (inHl - 1).clamp(0, 1 << 20);
      }
    }
    flush(display.length);
    return TextSpan(style: base, children: children);
  }
}

// ---------- ③ 正文沉浸（工单20261001轮2·用户拍板 chrome 收起才隐藏系统栏） ----------

extension _ReaderImmersive on _ReaderPageState {
  /// 每帧落定后同步：chrome 收起（且用户主动收放过）→ immersiveSticky；
  /// 点出顶/底栏、开抽屉/面板、选区出现 → 还原。弹层均由展开态 chrome 入口
  /// 进入（进入前一步已还原），故无需逐弹层埋点；「在当前页」分组等不影响此链。
  void _syncSysUi() {
    if (_chrome) _chromeShownOnce = true;
    final want = _chromeShownOnce &&
        !_chrome &&
        !_drawerOpen &&
        _selController.sel == null;
    if (want == _sysImmersive) return;
    _sysImmersive = want;
    _applySysUi(!want);
  }

  /// 退出阅读页还原系统栏，不把别的页带成无状态栏。
  void _sysUiRestore() {
    if (!_sysImmersive) return;
    _sysImmersive = false;
    _applySysUi(true);
  }

  void _applySysUi(bool visible) {
    if (visible) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }
}
