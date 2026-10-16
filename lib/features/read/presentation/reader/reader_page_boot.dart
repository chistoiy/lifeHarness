part of 'reader_page.dart';

/// 高保真批6c·刀3（2026-10-16）：装载/取证/定位恢复群（_boot＋_clampPos/_posKey/
/// _savePos/_locSnap）自 _ReaderPageState 拆入同库扩展（G7c 族口径·reader_page_pag
/// 先例·行为零改动·直访私有字段），主文件还 size_budget 默认 1200 面。_boot 内 9 处
/// setState 按先例逐点挂 ignore。

extension _ReaderBoot on _ReaderPageState {
  Future<void> _boot() async {
    final repo = ref.read(readRepositoryProvider);
    final b = await repo.bookById(widget.bookId);
    if (!mounted) return;
    if (b == null || !b.local || b.epub == null) {
      // ignore: invalid_use_of_protected_member // 同库扩展里调 State.setState（note_edit_* 先例）
      setState(() => _err = '这本书没有可用的本地 EPUB 文件');
      return;
    }
    // ignore: invalid_use_of_protected_member // 同库扩展里调 State.setState（note_edit_* 先例）
    setState(() => _book = b);
    // 批3.5 入口守卫（防御：正常路径书架/详情已分流）：
    // 已清缓存回书架走三态恢复。V1.60（§3G）：预载中**不再拦截**——
    // 按首次加载口径直接开，[svc.warming] 与在跑的预载解析并路。
    final ep = b.epub!;
    if (ep.cleared) {
      // ignore: invalid_use_of_protected_member // 同库扩展里调 State.setState（note_edit_* 先例）
      setState(() => _err = '本地副本已清理 · 回书架点封面重新载入');
      return;
    }
    // 真机修⑥：文档解析（或等书架预热）与外观/位置读取并行，
    // 冷启动重进时省掉一段串行等待。
    final svc = ref.read(epubPreloadProvider);
    final docF = () async {
      // 真机反馈（2026-10-04）：「打开书要等 3~5 秒」——先取证再优化，这里把
      // **文档从哪来、花了多久**记进自建日志（一条记录＝落盘一行），日志页直接读数。
      final swd = Stopwatch()..start();
      var src = '内存缓存';
      var d = svc.docs.get(b.id);
      if (d == null) {
        await svc.warming(b.id);
        d = svc.docs.get(b.id);
        if (d != null) src = '预热等待';
      }
      // 批5 秒开：无内存文档先吃排版快照（读索引+当前章＝毫秒级）；
      // 快照也没有才整本解析，且解析结果回灌快照让下次也秒开。
      d ??= await svc.snap(b);
      if (d == null) {
        src = '整本解析';
        d = await ref.read(epubDocLoaderProvider)(b.epub!.path);
        unawaited(svc.saveSnap(b, d));
      }
      _docSrc = src;
      _docMs = swd.elapsedMilliseconds;
      return d;
    }();
    // 立即挂接错误：解析异常延后到 try 里再抛，避免成未处理异步错误。
    final docR = Completer<(EpubDoc?, Object?)>();
    docF.then(
      (d) => docR.complete((d, null)),
      onError: (Object e, StackTrace _) => docR.complete((null, e)),
    );
    _slowHint = false;
    _loadWatch?.cancel();
    _loadWatch = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      if (_doc == null && _err == null) {
        AppLog.add('阅读器装载超时 书#${b.id} 8s 未就绪（大书/isolate 卡点）',
            level: LhLevel.warn);
        // ignore: invalid_use_of_protected_member // 同库扩展里调 State.setState（note_edit_* 先例）
        setState(() => _slowHint = true);
      }
    });
    // 外观/位置先读，渲染即按记忆恢复（CFI 自动定位 · V1.50 口径③）。
    // 批4：全局 reader.cfg + 逐书 reader.cfg.<id> 补丁合并生效。
    final fGlobal = repo.kv('reader.cfg');
    final fPatch = repo.kv('reader.cfg.${b.id}');
    final fBright = repo.kv('read.brBright');
    final fPos = repo.kv('reader.pos.${b.id}');
    final fSync = repo.kv('read.brSync');
    final fMin = repo.kv('read.brMinSecs');
    // V1.53.4④⑤ 选区设置：长按粒度（默认选字）与工具条名单（默认 8 项全开）。
    final fGran = repo.kv('read.brSelGran');
    final fBar = repo.kv('read.brSelBar');
    final fHl = repo.kv('reader.hl');
    final fQuotes = repo.quotesOf(b.id);
    _global = ReaderCfg.decode(await fGlobal);
    _bookPatch = brDecodePatch(await fPatch);
    _cfg = ReaderCfg.mergePatch(_global, _bookPatch);
    // 设置组 read.brBright ⇄ 面板常亮（原型 rsFlip/brMoreBright 双向）。
    if (await fBright == 'true' && !_cfg.bright) {
      _cfg = _cfg.copyWith(bright: true);
    }
    _pos = _Pos.decode(await fPos);
    _homePos = (ci: _pos.ci, pg: _pos.pg);
    _backPill = false;
    // 划线同库数据（批3）：同步开关 + 本书划线行 + brSync 关时暂存。
    _brSync = await fSync != 'false';
    _minSecs = int.tryParse(await fMin ?? '') ?? 30;
    _brSelGran = await fGran ?? '选字';
    _brSelTools = brSelToolsDecode(await fBar);
    _localHl = _LocalHl.decodeAll(await fHl);
    _hlQuotes = (await fQuotes)
        .where((q) => q.deletedAt == null && q.cf != null)
        .toList();
    if (!mounted) return;
    // ignore: invalid_use_of_protected_member // 同库扩展里调 State.setState（note_edit_* 先例）
    setState(() {});
    // 进阅读器自动开始计时；他处已在计时则沿用该计时条（原型 brV.ownT）。
    // 真机反馈（2026-09-28）：在跑会话属于「别书」（含崩溃遗留的挂死行）时
    // 接管＝startSession 内部先收口那行再为本书开新行；本书在跑则沿用。
    // 修复前：别书在跑 → 本页不记时长、进度也不落库。
    final running = await repo.runningSession();
    if (running != null && running.bookId == b.id) {
      // 他处已为本书开计时：沿用该会话（起止快照补在同一行上）。
      _sessId = running.id;
    } else {
      final ses = await repo.startSession(b.id);
      _ownTimer = true;
      _sessId = ses.id;
    }
    _t0 = DateTime.now();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      // 时钟胶囊只在 chrome/抽屉可见时展示；平时不整页重建（大书滑动掉帧根因之一）。
      if (!mounted || (_t0 == null && _accSecs == 0)) return;
      final secs = _readSecs;
      if (_chrome || _drawerOpen) {
        // ignore: invalid_use_of_protected_member // 同库扩展里调 State.setState（note_edit_* 先例）
        setState(() => _sessSecs = secs);
      } else {
        _sessSecs = secs;
      }
    });
    try {
      // 秒进：预载缓存命中直接用（分页表也已落盘）；未命中走懒归档再开。
      final (doc0, docErr) = await docR.future;
      if (docErr != null) throw docErr;
      final doc = doc0!;
      // 现开的文档也回灌缓存（真机修⑥）：退出重进不再二次整本解析。
      svc.docs.put(b.id, doc);
      _loadWatch?.cancel();
      if (!mounted) return;
      // ignore: invalid_use_of_protected_member // 同库扩展里调 State.setState（note_edit_* 先例）
      setState(() => _doc = doc);
      // 首帧已定 _viewport 时 LayoutBuilder 不会再触发；此处直接建分页。
      _rebuildPag();
      // 真机反馈（2026-10-04）「开书要等 3~5 秒」的取证行：文档来源与耗时先落日志，
      // 排版侧那半条在 reader_page_pag._applyPag 里（两条各一行＝一条记录落盘一行）。
      AppLog.add(
        '开书·文档 书#${widget.bookId} 源=$_docSrc ${_docMs}ms '
        '章=${doc.chapters.length} 段=${doc.chapters.fold<int>(0, (s, c) => s + c.paras.length)}',
      );
      if (_pag == null) _clampPos();
      // 轮5.2②：分页就绪＝位置可算 → 回填会话起始快照（此后无需手填）。
      _sessFrom = _locSnap();
      final sid = _sessId;
      if (sid != null && _sessFrom != null) {
        await repo.stampSessionStart(sid, _sessFrom!);
      }
      // 批4：常亮与自动翻页按生效外观接入。
      _syncBright();
      _syncAuto();
    } on EpubFormatException catch (e) {
      // ignore: invalid_use_of_protected_member // 同库扩展里调 State.setState（note_edit_* 先例）
      if (mounted) setState(() => _err = e.reason);
    } catch (_) {
      // ignore: invalid_use_of_protected_member // 同库扩展里调 State.setState（note_edit_* 先例）
      if (mounted) setState(() => _err = '文件无法读取');
    }
  }

  void _clampPos() {
    final doc = _doc;
    if (doc == null || doc.chapters.isEmpty) return;
    _pos.ci = _pos.ci.clamp(0, doc.chapters.length - 1);
    if (_cfg.mode == 'page') {
      final n = _pag?.chapterPages(_pos.ci) ?? 1;
      _pos.pg = _pos.pg.clamp(0, n - 1);
    }
  }

  String get _posKey => 'reader.pos.${widget.bookId}';

  void _savePos() {
    unawaited(ref.read(readRepositoryProvider).setKv(_posKey, _pos.encode()));
  }

  /// 当前位置快照（轮5.2②：会话起止自动记录 · 原型 brLocSnap）。
  BrLoc? _locSnap() {
    final doc = _doc, pag = _pag;
    if (doc == null || pag == null || doc.chapters.isEmpty) return null;
    final ci = _pos.ci.clamp(0, doc.chapters.length - 1);
    return BrLoc(
      page: pag.gPosEst(ci, _pos.pg) + 1,
      pct: pag.pct(ci, _pos.pg).toDouble(),
      chapter: doc.chapters[ci].title,
    );
  }
}
