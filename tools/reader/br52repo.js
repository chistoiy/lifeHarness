const fs = require('fs');
const f = 'lib/features/read/data/read_repository.dart';
let s = fs.readFileSync(f, 'utf8');
const subs = [
  [`  /// 开始计时（工作台右上/详情页顶栏）：先结束任何在跑会话，再落新行；
  /// 想读/已读外的状态不变，started_at 为空时补当下。
  Future<BookSession> startSession(String bookId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final old = await runningSession();
    if (old != null) {
      await _close(old, now);
    }
    final id = await db.insert(
      DbSchema.tBookSessions,
      BookSession(bookId: bookId, startedAt: now).toRow(),
    );`,
   `  /// 开始计时（工作台右上/详情页顶栏）：先结束任何在跑会话，再落新行；
  /// 想读/已读外的状态不变，started_at 为空时补当下。
  /// [at]＝起始位置快照（阅读器进入即知 → 轮5.2② 自动记，不再手填）。
  Future<BookSession> startSession(String bookId, {BrLoc? at}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final old = await runningSession();
    if (old != null) {
      await _close(old, now);
    }
    final id = await db.insert(
      DbSchema.tBookSessions,
      BookSession(
        bookId: bookId,
        startedAt: now,
        fromPage: at?.page,
        fromPct: at?.pct,
        fromChapter: at?.chapter,
      ).toRow(),
    );`],
  [`  /// 结束计时（胶囊/计时页共用）：返回已关闭会话供 L4 流水（批2）；
  /// 无在跑会话或不属于该书返回 null。
  Future<BookSession?> endSession(String bookId) async {
    final old = await runningSession();
    if (old == null || old.bookId != bookId) return null;
    return _close(old, DateTime.now().millisecondsSinceEpoch);
  }

  /// 关闭一条在跑会话：正常→落 ended_at/minutes + L4 流水；回拨→删行不入账（§2.4）。
  Future<BookSession?> _close(BookSession s, int nowMs) async {
    final closed = closeRunning(s, nowMs);`,
   `  /// 结束计时（胶囊/计时页/退出阅读器共用）：返回已关闭会话供 L4 流水（批2）；
  /// 无在跑会话或不属于该书返回 null。
  /// [to]＝结束位置快照；[minSecs]＝短会话门槛（轮5.2②：不足门槛整条丢弃，
  /// 时长与会话都不入账，读页退出时按 read.brMinSecs 传入）。
  Future<BookSession?> endSession(
    String bookId, {
    BrLoc? to,
    int minSecs = 0,
  }) async {
    final old = await runningSession();
    if (old == null || old.bookId != bookId) return null;
    return _close(
      old,
      DateTime.now().millisecondsSinceEpoch,
      to: to,
      minSecs: minSecs,
    );
  }

  /// 就地补写进行中会话的起始位置快照（进阅读器时文档尚未就绪 → 就绪后回填）。
  Future<void> stampSessionStart(int sessionId, BrLoc at) => db.update(
    DbSchema.tBookSessions,
    {
      'from_page': at.page,
      'from_pct': at.pct,
      'from_chapter': at.chapter,
    },
    where: 'id = ?',
    whereArgs: [sessionId],
  );

  /// 关闭一条在跑会话：正常→落 ended_at/minutes/结束位置 + L4 流水；
  /// 回拨或未达门槛→删行不入账（§2.4 / 轮5.2②）。
  Future<BookSession?> _close(
    BookSession s,
    int nowMs, {
    BrLoc? to,
    int minSecs = 0,
  }) async {
    final closed = closeRunning(s, nowMs, minSecs: minSecs);`],
  [`    await db.update(
      DbSchema.tBookSessions,
      {'ended_at': closed.endedAt, 'minutes': closed.minutes},
      where: 'id = ?',
      whereArgs: [s.id],
    );`,
   `    await db.update(
      DbSchema.tBookSessions,
      {
        'ended_at': closed.endedAt,
        'minutes': closed.minutes,
        if (to != null) 'to_page': to.page,
        if (to != null) 'to_pct': to.pct,
        if (to != null) 'to_chapter': to.chapter,
      },
      where: 'id = ?',
      whereArgs: [s.id],
    );`],
];
for (const [a0, b0] of subs) {
  const EOL = s.includes('\r\n') ? '\r\n' : '\n';
  const nl = (x) => x.split('\n').join(EOL);
  const a = nl(a0), b = nl(b0);
  if (!s.includes(a)) throw new Error('未命中：' + a0.split('\n')[0]);
  s = s.replace(a, b);
}
if (!s.includes('stampSessionStart')) throw new Error('缺 stampSessionStart');
fs.writeFileSync(f, s, 'utf8');
console.log('ok repo');
