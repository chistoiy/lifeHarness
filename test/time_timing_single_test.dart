import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/calendar/data/time_block_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// F1-5（时间模块批1 · 冻结口径）「计时中」单活收口：
/// 全库同日至多一条 `tm=1`（source='timing'）——再开一段自动收口上一段。
/// B10（2026-10-13 裁决）：原 C7「两表并存收口」三例随 events 面退役整组删除
/// ——旧 active 事件由 LegacyEventMerge 并入时收口，守卫见 time_legacy_merge_test。
void main() {
  sqfliteFfiInit();

  late Database db;
  late TimeBlockDao dao;
  final day0 = DateTime(2026, 9, 19);

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    dao = TimeBlockDao(db);
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
}
