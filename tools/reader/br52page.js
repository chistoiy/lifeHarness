const fs = require('fs');
const f = 'lib/features/read/presentation/reader_page.dart';
let s = fs.readFileSync(f, 'utf8');
const EOL = s.includes('\r\n') ? '\r\n' : '\n';
const nl = (x) => x.split('\n').join(EOL);
const subs = [
  [`  /// 轮5.4：本页是否已把全局读书计时条挂起（ dispose 时按此还原）。
  bool _readerCounted = false;`,
   `  /// 轮5.4：本页是否已把全局读书计时条挂起（ dispose 时按此还原）。
  bool _readerCounted = false;

  /// 轮5.2②：本页在跑会话 id + 起始位置快照（退出时自动结算，写起止章节/页/百分比）。
  int? _sessId;
  BrLoc? _sessFrom;

  /// read.brMinSecs：短于该秒数的阅读不记时长也不记会话（默认 30 · 设置组可调）。
  int _minSecs = 30;

  /// 出页后的结算提示：页面已销毁，用离开前抓住的 messenger。
  ScaffoldMessengerState? _ms;`],
  [`    final fSync = repo.kv('read.brSync');`,
   `    final fSync = repo.kv('read.brSync');
    final fMin = repo.kv('read.brMinSecs');`],
  [`    _brSync = await fSync != 'false';`,
   `    _brSync = await fSync != 'false';
    _minSecs = int.tryParse(await fMin ?? '') ?? 30;`],
  [`    final running = await repo.runningSession();
    if (running == null) {
      await repo.startSession(b.id);
      _ownTimer = true;
    }`,
   `    final running = await repo.runningSession();
    if (running == null) {
      final ses = await repo.startSession(b.id);
      _ownTimer = true;
      _sessId = ses.id;
    } else if (running.bookId == b.id) {
      // 他处已为本书开计时：沿用该会话（起止快照补在同一行上）。
      _sessId = running.id;
    }`],
  [`      // 批4：常亮与自动翻页按生效外观接入。
      _syncBright();
      _syncAuto();`,
   `      // 轮5.2②：分页就绪＝位置可算 → 回填会话起始快照（此后无需手填）。
      _sessFrom = _locSnap();
      final sid = _sessId;
      if (sid != null && _sessFrom != null) {
        await repo.stampSessionStart(sid, _sessFrom!);
      }
      // 批4：常亮与自动翻页按生效外观接入。
      _syncBright();
      _syncAuto();`],
  [`  /// 结算：本页开启的计时才由本页结束；进度按全局页百分比写回书籍记录。
  void _leave() {
    _clock?.cancel();
    if (!_ownTimer) return;
    final repo = ref.read(readRepositoryProvider);
    final doc = _doc;
    final pag = _pag;
    unawaited(repo.endSession(widget.bookId));
    if (doc != null && pag != null && _book != null) {
      final pct = pag.pct(_pos.ci, _pos.pg);
      final b = _book!;
      final pages = b.pages > 0 ? b.pages : pag.estTotal;
      unawaited(
        repo.saveProgress(
          widget.bookId,
          Book.kWayPage,
          (pages * pct / 100).round().toDouble(),
          chapterTitle: doc.chapters[_pos.ci].title,
        ),
      );
    }
    ref.read(readTickProvider.notifier).state++;
  }`,
   `  /// 当前位置快照（轮5.2②：会话起止自动记录 · 原型 brLocSnap）。
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

  /// 结算：本页开启的计时才由本页结束；进度按全局页百分比写回书籍记录。
  /// 轮5.2②：起止位置随会话自动落库；短于 read.brMinSecs 的会话整条丢弃
  /// （不记时长、不入明细），但进度仍然保存。
  void _leave() {
    _clock?.cancel();
    if (!_ownTimer) return;
    final repo = ref.read(readRepositoryProvider);
    final doc = _doc;
    final pag = _pag;
    final to = _locSnap();
    final from = _sessFrom ?? to;
    final gate = _minSecs;
    final secs = _t0 == null ? 0 : DateTime.now().difference(_t0!).inSeconds;
    final ms = _ms;
    final title = _book?.title ?? '';
    unawaited(() async {
      final closed = await repo.endSession(
        widget.bookId,
        to: to,
        minSecs: gate,
      );
      if (doc != null && pag != null && _book != null) {
        final pct = pag.pct(_pos.ci, _pos.pg);
        final b = _book!;
        final pages = b.pages > 0 ? b.pages : pag.estTotal;
        unawaited(
          repo.saveProgress(
            widget.bookId,
            Book.kWayPage,
            (pages * pct / 100).round().toDouble(),
            chapterTitle: doc.chapters[_pos.ci].title,
          ),
        );
      }
      if (ms == null) return;
      final span = from != null && to != null && to.chapter != from.chapter
          ? from.chapter + '→' + to.chapter
          : (to?.chapter ?? '');
      ms
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(milliseconds: 2200),
            content: Text(
              closed == null
                  ? '《' + title + '》本次 ' + secs + ' 秒 · 短于 ' + gate + ' 秒不计入计时'
                  : '《' + title + '》本次 ' + closed.minutes + ' 分钟 · 自动记 ' + span +
                      ' P' + (from?.page ?? 0) + '→P' + (to?.page ?? 0) +
                      ' · ' + (from?.pct?.round() ?? 0) + '%→' + (to?.pct?.round() ?? 0) + '%',
            ),
          ),
        );
    }());
    ref.read(readTickProvider.notifier).state++;
  }`],
  [`    final th = brThemeResolved(_cfg);
    final bar = brBarOf(th.$2, th.$3);`,
   `    final th = brThemeResolved(_cfg);
    final bar = brBarOf(th.$2, th.$3);
    // 出页后的结算提示要用还活着的 messenger（离开前抓住）。
    _ms ??= ScaffoldMessenger.of(context);`],
];
for (const [a0, b0] of subs) {
  const a = nl(a0), b = nl(b0);
  if (!s.includes(a)) throw new Error('未命中：' + a0.split('\n')[0]);
  s = s.replace(a, b);
}
fs.writeFileSync(f, s, 'utf8');
console.log('ok page');
