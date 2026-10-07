import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema/core.dart' as core;
import 'package:lifeharness/core/database/schema/media.dart' as md;
import 'package:lifeharness/features/media/data/media_repo_session.dart';
import 'package:lifeharness/features/media/data/media_repository.dart';
import 'package:lifeharness/features/media/domain/media_item.dart';
import 'package:lifeharness/features/media/domain/media_session.dart';

/// 影音游批3 · 会话与进度数据面（工单执行面板第 1 项受影响测试）。
///
/// 独立文件＝全 app 点火类用例拆文件防 isolate 污染（AGENTS 门禁条）。
void main() {
  sqfliteFfiInit();

  late Database db;
  late MediaRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in md.mediaSchemaStatements) {
      await db.execute(sql);
    }
    // L4 落块要吃 time_blocks（含 cat_id 列＝mig[3] 后形态）与 settings，
    // 建表口径与真库 schema/core.dart 逐字段一致。
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${core.tTimeBlocks} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        day INTEGER NOT NULL,
        start_min INTEGER NOT NULL,
        end_min INTEGER NOT NULL,
        category TEXT NOT NULL DEFAULT '其他',
        note TEXT,
        source TEXT NOT NULL DEFAULT 'mark',
        event_id INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        cat_id INTEGER
      )
    ''');
    await db.execute(
      'CREATE TABLE IF NOT EXISTS ${core.tSettings} '
      '(key TEXT PRIMARY KEY, value TEXT)',
    );
    // 「娱乐」分类种子（core categorySeed id=5）——cat_id 断言的对照依据。
    repo = MediaRepository(db);
  });
  tearDown(() => db.close());

  Future<MediaItem> get1(String id) async {
    final x = await repo.itemById(id);
    expect(x, isNotNull);
    return x!;
  }

  Future<String> addItem({
    String kind = MediaItem.kMovie,
    String title = '测试条目',
    int durationMin = 120,
    String? progressTo,
    String way = MediaItem.kWayPct,
  }) => repo.addItem(
    MediaItem(
      kind: kind,
      title: title,
      state: MediaItem.initialState(kind),
      progressWay: way,
      progressTo: progressTo,
      durationMin: durationMin,
      createdAt: 1,
      updatedAt: 1,
    ),
  );

  test('起停一条计时＝会话落库、分钟入账、L4 块同场生成且分类=娱乐', () async {
    final id = await addItem();
    final s = await repo.startSession(id);
    expect(s.id, isNotNull);
    // 人为把起点拨早 5 分钟，再结束（不靠真等）。
    await db.update(
      md.tMediaSessions,
      {'started_at': DateTime.now().millisecondsSinceEpoch - 5 * 60000},
      where: 'id = ?',
      whereArgs: [s.id],
    );
    final closed = await repo.endSession(id);
    expect(closed, isNotNull);
    expect(closed!.minutes, greaterThanOrEqualTo(5));
    expect(closed.txnId, isNotNull, reason: '结束即回填 L4 块 id');
    final blocks = await db.query(
      core.tTimeBlocks,
      where: 'id = ?',
      whereArgs: [closed.txnId],
    );
    expect(blocks, hasLength(1));
    expect(blocks.first['category'], '娱乐');
    // 刀1：这一行断言吃的 cat_id 摘掉（写块不带 cat_id），本例即红。
    expect(blocks.first['cat_id'], 5, reason: '娱乐分类种子 id（core categorySeed）');
    expect(await repo.runningSession(), isNull, reason: '结束后不再有在跑会话');
  });

  test('起新先结旧＝全库单活（跨条目也不双跑）', () async {
    final a = await addItem(title: '甲');
    final b = await addItem(title: '乙');
    final s1 = await repo.startSession(a);
    await db.update(
      md.tMediaSessions,
      {'started_at': DateTime.now().millisecondsSinceEpoch - 3 * 60000},
      where: 'id = ?',
      whereArgs: [s1.id],
    );
    await repo.startSession(b);
    final run = await repo.runningSession();
    expect(run?.itemId, b, reason: '在跑的只剩新一条');
    final ofA = await repo.sessionsOf(a);
    expect(ofA.single.endedAt, isNotNull, reason: '旧会话被结算而非删除');
  });

  test('不足 1 分钟的短会话＝删行不入账（同阅读门槛口径）', () async {
    final id = await addItem();
    await repo.startSession(id);
    final closed = await repo.endSession(id);
    expect(closed, isNull);
    expect(await repo.sessionsOf(id), isEmpty);
    expect(await db.query(core.tTimeBlocks), isEmpty);
  });

  test('杀进程重开延续＝在跑会话只吃库内读数', () async {
    final id = await addItem();
    await repo.startSession(id);
    // 模拟「重开」：不依赖任何内存态，直接重查仓储。
    final run = await repo.runningSession();
    expect(run?.itemId, id);
    expect(run!.running, isTrue);
    expect(run.liveMinutes, 0);
  });

  test('明细改时长＝差量回写同一条 L4 块（txn_id 复用不新建）', () async {
    final id = await addItem();
    final s = await repo.startSession(id);
    await db.update(
      md.tMediaSessions,
      {'started_at': DateTime.now().millisecondsSinceEpoch - 10 * 60000},
      where: 'id = ?',
      whereArgs: [s.id],
    );
    final closed = await repo.endSession(id);
    final firstTxn = closed!.txnId;
    await repo.editSession(closed.id!, minutes: 30);
    final rows = await db.query(core.tTimeBlocks);
    expect(rows, hasLength(1), reason: '改动不新建第二块');
    expect(rows.single['id'], firstTxn);
    expect((rows.single['end_min'] as num) > (rows.single['start_min'] as num), isTrue);
    final sess = (await repo.sessionsOf(id)).single;
    expect(sess.minutes, 30);
  });

  test('删除会话＝连删其 L4 块（计划 §八 同事务口径）', () async {
    final id = await addItem();
    final s = await repo.startSession(id);
    await db.update(
      md.tMediaSessions,
      {'started_at': DateTime.now().millisecondsSinceEpoch - 7 * 60000},
      where: 'id = ?',
      whereArgs: [s.id],
    );
    final closed = await repo.endSession(id);
    expect(await db.query(core.tTimeBlocks), hasLength(1));
    await repo.deleteSession(closed!.id!);
    expect(await repo.sessionsOf(id), isEmpty);
    expect(await db.query(core.tTimeBlocks), isEmpty);
  });

  test('进度写回按 kind 分派各自的列（不是同一列四用）', () async {
    final movie = await addItem(
      kind: MediaItem.kMovie,
      title: '电影',
      way: MediaItem.kWayPct,
    );
    await repo.saveProgress(item: await get1(movie), pct: 40);
    var m = await repo.itemById(movie);
    expect(m!.progressTo, '40');
    expect(m.mainPct, 40, reason: '电影 pct 档同步落 main_pct 供卡底画条');

    final series = await addItem(
      kind: MediaItem.kSeries,
      title: '剧集',
      way: MediaItem.kWayEp,
      progressTo: '2',
    );
    await repo.saveProgress(
      item: await get1(series),
      ep: 10,
      state: '追完',
    );
    m = await repo.itemById(series);
    expect(m!.progressTo, '10');
    expect(m.state, '追完');
    expect(m.completed, isTrue, reason: '完结档同场落 completed');

    final game = await addItem(
      kind: MediaItem.kGame,
      title: '游戏',
      way: MediaItem.kWayAchv,
    );
    await repo.saveProgress(
      item: await get1(game),
      pct: 55,
      sidePct: 20,
      playthroughs: 2,
      achPct: 55,
    );
    m = await repo.itemById(game);
    expect(m!.achPct, 55);
    expect(m.sidePct, 20);
    expect(m.playthroughs, 2);
    expect(m.mainPct, 0, reason: '成就档不覆写主线列（串档＝假账）');

    final music = await addItem(
      kind: MediaItem.kMusic,
      title: '专辑',
      way: MediaItem.kWayLoops,
    );
    await repo.saveProgress(
      item: await get1(music),
      state: '循环中',
      myRating: 9.5,
    );
    m = await repo.itemById(music);
    expect(m!.progressTo, isNull, reason: '音乐不落进度列——循环＝会话派生');
    expect(m.myRating, 9.5);
  });

  test('音乐循环次数＝会话条数派生（记一次即 +1，表里无 loops 列）', () async {
    final id = await addItem(
      kind: MediaItem.kMusic,
      title: '循环测试',
      way: MediaItem.kWayLoops,
    );
    expect((await repo.loopCounts())[id] ?? 0, 0);
    await repo.addManualSession(
      itemId: id,
      atMs: DateTime.now().millisecondsSinceEpoch - 60000,
      minutes: 42,
    );
    expect((await repo.loopCounts())[id], 1);
    final m = await repo.itemById(id);
    expect(m!.listenLoops, 1, reason: 'itemById 回填派生循环数');
    expect(await repo.minutesOfItem(id), 42);
  });

  test('settings 表 media.* 键读写（计划 §七：不散落 SharedPreferences）', () async {
    expect(await repo.kv('media.timerUI'), isNull);
    await repo.setKv('media.timerUI', 'full');
    expect(await repo.kv('media.timerUI'), 'full');
  });

  test('ETA 三件：有 pace 才算，没总时长/没会话就整行隐藏（不编数）', () {
    final now = DateTime(2026, 10, 7, 12);
    MediaSession sess(int minsAgo) => MediaSession(
      itemId: 'x',
      kind: MediaItem.kMovie,
      startedAt: now
          .subtract(Duration(minutes: minsAgo + 30))
          .millisecondsSinceEpoch,
      endedAt: now.subtract(Duration(minutes: minsAgo)).millisecondsSinceEpoch,
      minutes: 30,
    );
    // 三条会话分落三个自然日（同 pace 分母口径）
    final closed = [sess(60), sess(1500), sess(2940)];

    final eta = MediaEta.forPct(pct: 50, totalMin: 120, closed: closed, now: now);
    expect(eta, isNotNull);
    expect(eta!.remainMin, 60);
    // 期望值现算：三条各 30 分钟、落在 3 个自然日 → 日均＝总分钟÷天数
    final totalMin = closed.fold<int>(0, (t, x) => t + x.minutes);
    final dayCount = closed.map((x) {
      final d = DateTime.fromMillisecondsSinceEpoch(x.endedAt!);
      return DateTime(d.year, d.month, d.day);
    }).toSet().length;
    expect(eta.avgMinPerDay, (totalMin / dayCount).round());
    expect(dayCount, 3, reason: '用例前提：三条会话落三个自然日');
    expect(eta.remainDays, 2);
    expect(eta.etaDate, DateTime(2026, 10, 9));

    expect(
      MediaEta.forPct(pct: 50, totalMin: 0, closed: closed, now: now),
      isNull,
      reason: '总时长未知＝不预测',
    );
    expect(
      MediaEta.forPct(pct: 50, totalMin: 120, closed: const [], now: now),
      isNull,
      reason: '没有会话＝没有 pace，不编均速',
    );
    expect(
      MediaEta.forPct(pct: 100, totalMin: 120, closed: closed, now: now),
      isNull,
      reason: '已看完＝没有剩余',
    );
  });

  test('倍速只存列不改账：minutes＝真实耗时，折算在读取侧', () {
    final s = MediaSession(
      itemId: 'x',
      kind: MediaItem.kMusic,
      startedAt: 0,
      endedAt: 30 * 60000,
      minutes: 30,
      speed: 2.0,
    );
    expect(s.minutes, 30, reason: '落库分钟＝墙钟真实耗时');
    expect(s.billedMinutes(speedFold: true), 60, reason: '折算只在读取侧');
    expect(s.billedMinutes(speedFold: false), 30);
  });

  group('明细屏写口', () {
    /// 就地相对构造：今天 [hour]:[minute]（禁写死日期，23:55 门槛外不跑）。
    int t(int hour, int minute) {
      final n = DateTime.now();
      return DateTime(n.year, n.month, n.day, hour, minute).millisecondsSinceEpoch;
    }

    test('明细改时长＝差量回写同一条娱乐块（txn_id 复用不新建）', () async {
      final it = await addItem();
      final s = await repo.addManualDetail(
          itemId: it, kind: MediaItem.kMovie,
          startedAtMs: t(20, 0), minutes: 60, speed: 1.5, toPct: 40);
      final before = await db.query('time_blocks',
          where: 'category = ?', whereArgs: ['娱乐']);
      expect(before.length, 1);
      expect(s.txnId, isNotNull, reason: '补记即回填块 id，改口才有沿用依据');
      await repo.updateSessionDetail(s.id!, minutes: 30);
      final after = await db.query('time_blocks', where: 'category = ?', whereArgs: ['娱乐']);
      expect(after.length, 1, reason: '不新建');
      expect(after.single['id'], s.txnId); // 还是那一条
      // 块面跨度＝真实耗时 30 分钟，不是折算出来的 45（60×1.5 那类编数）。
      expect((after.single['end_min'] as int) - (after.single['start_min'] as int), 30);
      expect((await repo.minutesOfItem(it)), 30);
      final row = (await repo.sessionsOf(it)).single;
      expect(row.minutes, 30);
      expect(row.endedAt, t(20, 30), reason: '结束点跟时长重排，不留旧尾巴');
      expect(row.speed, 1.5, reason: '未露的入参不被洗成空');
      expect(row.toPct, 40);
      expect(row.source, MediaSession.kSrcManual, reason: '补记来源＝手动');
    });

    test('倍速只落 speed 列：minutes 恒真实耗时', () async {
      final it = await addItem();
      await repo.addManualDetail(itemId: it, kind: MediaItem.kMovie,
          startedAtMs: t(20, 0), minutes: 30, speed: 2);
      final rows = await repo.sessionsOf(it);
      expect(rows.last.minutes, 30);
      expect(rows.last.speed, 2);
      expect(rows.last.billedMinutes(), 60); // 折算只在读侧
      final blocks = await db.query('time_blocks', where: 'category = ?', whereArgs: ['娱乐']);
      expect((blocks.single['end_min'] as int) - (blocks.single['start_min'] as int), 30,
          reason: '账本吃墙钟分钟，折算绝不下沉到写侧');
      expect(await repo.minutesOfItem(it), 30);
    });
  });
}
