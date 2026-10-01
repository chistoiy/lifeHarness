part of 'reader_page.dart';

// V1.54 批A · X-Ray 在阅读页的挂接四处之三（底栏目录／⋯菜单行／出场跳转）：
// - `xrStatusLabel/_openXrTab`：⋯菜单行「全书索引（X-Ray）+状态字」（形态＝more.frag）；
// - `_xrJump`：复用目录跳章 + 检索命中定位链路（章+段锚点 → 现算页位），
//   落定后照 shelf_locate 先例给目标段挂 1.6s 描边闪烁环（原型 .br-flash-xr）；
// - 退后台守护：调度器自动暂停（§8 断点已逐章落库）。

extension _ReaderXray on _ReaderPageState {
/// ⋯菜单行状态字（只读缓存值，渲染路径零 IO；解析中优先看 live）。
String xrStatusLabel() {
  final sched = ref.read(xraySchedulerProvider);
  final live = sched.live(widget.bookId);
  if (live != null && live.running) return '解析中 ${live.pct}%';
  final md5 = ref.read(bookMd5Provider(widget.bookId)).valueOrNull;
  if (md5 == null || md5.isEmpty) return '未解析';
  final snap = ref.read(xraySnapProvider(md5)).valueOrNull;
  final t = snap?.task;
  if (t == null) return '未解析';
  if (t.status == xs.xrayStatusRunning) return '解析中';
  if (t.status == xs.xrayStatusPause) return '已暂停';
  if (t.status == xs.xrayStatusFailed) return '上次失败';
  return '已解析 ${t.processedCh}/${t.totalCh} 章';
}

/// 打开上拉面板并停在 X-Ray 段（⋯菜单行与书架长按「管理」共用入口）。
void openXrTab() {
  // ignore: invalid_use_of_protected_member
  setState(() {
    _drState.xrTab = true;
    _drState.searching = false;
    _drawerOpen = true;
    _chrome = false;
  });
}

/// 出场跳转：关面板 → 现算页位 → 段闪烁（_jumpHit 同构，但不挂「上/下一处」序列）。
void xrJumpTo(int ch, int para) {
  final doc = _doc;
  final pag = _pag;
  if (doc == null || pag == null || doc.chapters.isEmpty) return;
  final ci = ch.clamp(0, doc.chapters.length - 1);
  final pi = para.clamp(0, doc.chapters[ci].paras.length - 1);
  if (_cfg.mode == 'page') {
    _ensure(pag, doc, _layout(), ci);
  }
  // ignore: invalid_use_of_protected_member
  setState(() {
    _drawerOpen = false;
    // ①（工单20261001轮2）：跳章前记来源位置——与 _gotoChapter 同式，
    // 让目录抽屉的「回到刚才在读」返回行自然出现（同一 UI 语言，零新组件）。
    if (ci != _pos.ci) {
      _jumpFrom = (
        ci: _pos.ci,
        pg: _pos.pg,
        title: doc.chapters[_pos.ci.clamp(0, doc.chapters.length - 1)].title,
      );
    }
    _pos.ci = ci;
    if (_cfg.mode == 'page') {
      _pos.pg = pag.pageOfPara(ci, pi);
      _hitMark = (ci: ci, pg: _pos.pg, pi: pi);
    } else {
      _hitMark = (ci: ci, pg: 0, pi: pi);
    }
    _flash = doc.chapters[ci].title;
  });
  _ensureCur();
  _savePos();
  _flashT?.cancel();
  _flashT = Timer(const Duration(milliseconds: 1300), () {
    // ignore: invalid_use_of_protected_member
    if (mounted) setState(() => _flash = null);
  });
  if (_cfg.mode == 'scroll') _scrollToPara(ci, pi);
  // 段元素要等新页渲染那一帧才拿得到 rect。
  WidgetsBinding.instance.addPostFrameCallback((_) => _brFlashPara(ci, pi));
}

/// 目标段的一次性描边闪烁环（shelf_locate `_LocateFlashRing` 同法，色取原型
/// .br-flash-xr 的 emerald；帧驱动 1.6s 自移除，测试 settle 友好）。
void _brFlashPara(int ci, int pi) {
  if (!mounted) return;
  Element? found;
  void visit(Element e) {
    if (found != null) return;
    final k = e.widget.key;
    if (k is ValueKey<String> && k.value == 'brpTap-$ci-$pi') {
      found = e;
      return;
    }
    e.visitChildren(visit);
  }

  (context as Element).visitChildren(visit);
  final el = found;
  if (el == null) return;
  final ro = el.renderObject;
  if (ro is! RenderBox || !ro.hasSize || !ro.attached) return;
  final rect = ro.localToGlobal(Offset.zero) & ro.size;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: _XrParaFlash(
          onDone: () {
            entry.remove();
          },
        ),
      ),
    ),
  );
  Overlay.of(context, rootOverlay: true).insert(entry);
}

/// 选区工具条「X-Ray」（F6）：命中实体词→迷你卡（查看全部位置→面板详情）；
/// 未命中→面板「加为词条」弹层预填（名单驱动 read.brSelBar）。
void xrSelToLearn() {
  final raw = _selTxt.trim();
  _clearSel();
  if (raw.isEmpty) return;
  final w = raw.length > 24 ? raw.substring(0, 24) : raw;
  unawaited(_xrSelLookup(w));
}

Future<void> _xrSelLookup(String w) async {
  final b = _book;
  if (b == null) return;
  final dao = ref.read(xrayDaoProvider);
  String? md5 = await dao.bookMd5(b.id);
  if (md5 == null || md5.isEmpty) {
    md5 = await ref.read(xraySchedulerProvider).ensureMd5(b);
  }
  if (!mounted) return;
  if (md5 != null && md5.isNotEmpty) {
    final hits = await dao.searchEntities(md5, w);
    if (!mounted) return;
    XrayEntityRow? hit;
    for (final e in hits) {
      if (e.name == w) {
        hit = e;
        break;
      }
    }
    hit ??= hits.where((e) => e.name.contains(w) || w.contains(e.name)).firstOrNull;
    if (hit != null) {
      final name = hit.name;
      showXrPeekSheet(
        context,
        ent: hit,
        onViewAll: () {
          ref.read(readerXrFocusWordProvider.notifier).state = name;
          openXrTab();
        },
      );
      return;
    }
  }
  ref.read(readerXrAddWordProvider.notifier).state = w;
  openXrTab();
}

/// 退后台自动暂停解析（§8 一期不做后台续跑；回前台在面板头一键恢复）。
void xrNoteBackground() {
  try {
    ref.read(xraySchedulerProvider).noteBackground();
  } catch (e) {
    // 真机 2026-10-01 16:28：退后台暂停没生效，而这条静默 catch 是唯一可能吞掉
    // 原因的地方（容器销毁只是其中一种）。留痕后再判，不再裸吞。
    AppLog.add('X-Ray 退后台暂停未执行: $e', level: LhLevel.warn);
  }
}

}

class _XrParaFlash extends StatefulWidget {
  const _XrParaFlash({required this.onDone});
  final VoidCallback onDone;

  @override
  State<_XrParaFlash> createState() => _XrParaFlashState();
}

class _XrParaFlashState extends State<_XrParaFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: .6 * (1 - _c.value)),
              spreadRadius: 3,
              blurRadius: 0,
            ),
          ],
        ),
      ),
    );
  }
}
