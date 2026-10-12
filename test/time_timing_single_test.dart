import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/features/calendar/data/event_dao.dart';
import 'package:lifeharness/features/calendar/data/time_block_dao.dart';
import 'package:lifeharness/features/calendar/domain/cal_event.dart';
import 'package:lifeharness/features/calendar/domain/event_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// F1-5/C7（时间模块批1 · 冻结口径）「计时中」单活收口：
/// ① 全库同日至多一条 `tm=1`（source='timing'）——再开一段自动收口上一段；
/// ② 两表并存（events.status=1 ＋ 块表计时中）⇒ 以时间块为准清理事件侧。
void main() {
  sqfliteFfiInit();

  late Database db;
  late TimeBlockDao dao;
  late EventDao evDao;
  final day0 = DateTime(2026, 9, 19);

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    dao = TimeBlockDao(db);
    evDao = EventDao(db);
  });
  tearDown(() async => db.close());

  Future<int> timingCount() async {
    final rows = await db.query(DbSchema.tTimeBlocks,
        where: 'source = ?', whereArgs: ['timing']);
    return rows.length;
  }

  test('再开一段自动收口上一段 ⇒ 全库至多一条计时中（跨日也单活）', () async {
    await dao.startTiming(day0, 540, catName: '工作');
    expect(await timingCount(), 1);
    // 换一天再开（旧实现若按「当日」查会漏收口）。
    await dao.startTiming(DateTime(2026, 9, 20), 600, catName: '娱乐');
    expect(await timingCount(), 1);
    final active = await dao.activeTiming();
    expect(active!.day.day, 20);
    // 上一段已落实际结束（非计时中）。
    final prev = (await dao.listByDay(day0)).single;
    expect(prev.isTiming, isFalse);
  });

  test('结束计时 ⇒ 计时中清零；单活约束在收口后可再开', () async {
    final a = await dao.startTiming(day0, 540, catName: '工作');
    await dao.endTiming(a.id, 600);
    expect(await timingCount(), 0);
    final b = await dao.startTiming(day0, 700, catName: '学习');
    expect((await dao.activeTiming())!.id, b.id);
  });

  test('C7：两表并存 ⇒ 以时间块为准，事件侧收口为已完成（不回填新块）', () async {
    // 事件侧：历史两态流残留的 status=1 行。
    await evDao.insert(CalEvent(
        title: '旧进行中',
        start: DateTime(2026, 9, 19, 9),
        status: EventStatus.active));
    // 块侧：唯一「计时中」。
    await dao.startTiming(day0, 9 * 60 + 30, catName: '工作');
    final blocksBefore = await dao.listByDay(day0);

    final repo = EventRepository(evDao, EventBus(), tbDao: dao);
    final cleaned = await repo.reconcileStaleActive();
    expect(cleaned, isTrue);

    final stillActive = await evDao.activeOne();
    expect(stillActive, isNull); // 事件侧已收口
    final all = await evDao.listAll();
    expect(all.single.status, EventStatus.done);
    expect(all.single.durationMin, greaterThanOrEqualTo(1));

    // 不回填时间块（块已在计）：块数不变。
    final blocksAfter = await dao.listByDay(day0);
    expect(blocksAfter.length, blocksBefore.length);
  });

  test('C7：只有事件侧进行中（无计时块）⇒ 不动（兼容悬浮条自行收口）', () async {
    await evDao.insert(CalEvent(
        title: '悬浮条在计',
        start: DateTime(2026, 9, 19, 9),
        status: EventStatus.active));
    final repo = EventRepository(evDao, EventBus(), tbDao: dao);
    expect(await repo.reconcileStaleActive(), isFalse);
    expect((await evDao.activeOne())!.title, '悬浮条在计');
  });

  test('C7：只有块侧计时中（无事件行）⇒ 无事可清，返回 false', () async {
    await dao.startTiming(day0, 540, catName: '工作');
    final repo = EventRepository(evDao, EventBus(), tbDao: dao);
    expect(await repo.reconcileStaleActive(), isFalse);
  });
}
