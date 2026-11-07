import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/calendar/data/time_block_dao.dart';
import 'package:lifeharness/features/calendar/domain/block_ops.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// F1-2/B2/C8（时间模块批1 · 冻结口径）计时块跨 0 点：
/// ① 23:50 开始、次日 00:10 结束 ⇒ 落两段行（首日 [1430,1440) ＋ 次日 [0,10)）；
/// ② 账本口径两日均计入（各段分别归属所在日）；
/// ③ 「已 X 分钟」= 跨零点真实时长（effEnd 不 clamp 1440）。
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

  test('23:50 起计 · 次日 00:10 结束 ⇒ 拆两段行且时长不丢（20 分钟）', () async {
    final b = await dao.startTiming(day0, 23 * 60 + 50, catName: '工作');
    expect(b.isTiming, isTrue);

    // 次日 00:10 收口：atMin(10) < startMin(1430) ⇒ 跨 0 点分支。
    final ended = await dao.endTiming(b.id, 10);
    expect(ended, isNotNull);
    expect(ended!.isTiming, isFalse);

    final head = await dao.listByDay(day0);
    expect(head, hasLength(1));
    expect(head.single.startMin, 23 * 60 + 50);
    expect(head.single.endMin, 1440);

    final tail = await dao.listByDay(DateTime(2026, 9, 20));
    expect(tail, hasLength(1));
    expect(tail.single.startMin, 0);
    expect(tail.single.endMin, 10);
    expect(tail.single.catName, '工作'); // 分类/备注随段走

    // 账本口径：两段合计 = 真实 20 分钟，且分别计入各「日」。
    final all = await dao.listInRange(DateTime(2026, 9, 19), DateTime(2026, 9, 20));
    expect(all, hasLength(2));
    expect(totalMinutes(all), 20);
    final byDay = <String, int>{};
    for (final blk in all) {
      final k = '${blk.day.month}/${blk.day.day}';
      byDay[k] = (byDay[k] ?? 0) + blk.durationMin();
    }
    expect(byDay['9/19'], 10);
    expect(byDay['9/20'], 10);
  });

  test('effEnd 跨零点折算：00:05 时刻对 23:50 起计的活块 = 1445（不 clamp）', () async {
    final b = await dao.startTiming(day0, 23 * 60 + 50, catName: '工作');
    final at5 = DateTime(2026, 9, 20, 0, 5);
    expect(b.effEnd(at5), 24 * 60 + 5); // 1445
    expect(b.durationMin(at5), 15); // 真实经过 15 分钟
    // 结束后转普通块：effEnd 回归库存值。
    await dao.endTiming(b.id, 10);
    final head = (await dao.listByDay(day0)).single;
    expect(head.effEnd(at5), 1440);
  });

  test('次日 00:00 整点结束 ⇒ 首日到 24:00，无零长尾巴', () async {
    final b = await dao.startTiming(day0, 23 * 60 + 50, catName: '工作');
    await dao.endTiming(b.id, 0);
    expect(await dao.listByDay(DateTime(2026, 9, 20)), isEmpty);
    final head = (await dao.listByDay(day0)).single;
    expect(head.endMin, 1440);
    expect(head.startMin, 23 * 60 + 50);
  });

  test('同日正常收口不拆段：e > s 原位一行（回归护栏）', () async {
    final b = await dao.startTiming(day0, 540, catName: '工作');
    await dao.endTiming(b.id, 600);
    final rows = await dao.listByDay(day0);
    expect(rows, hasLength(1));
    expect(rows.single.startMin, 540);
    expect(rows.single.endMin, 600);
    expect(await dao.listByDay(DateTime(2026, 9, 20)), isEmpty);
  });

  test('同分收口兜底 1 分钟（e==s 不产零长行，回归护栏）', () async {
    final b = await dao.startTiming(day0, 540, catName: '工作');
    await dao.endTiming(b.id, 540);
    final rows = await dao.listByDay(day0);
    expect(rows.single.endMin, 541);
  });

  test('收口后计时中清零：activeTiming 为 null（回归护栏）', () async {
    final b = await dao.startTiming(day0, 540, catName: '工作');
    await dao.endTiming(b.id, 600);
    expect(await dao.activeTiming(), isNull);
    expect(fmtMin(1430), '23:50'); // fmtMin 冒烟（>1440 回绕次日钟面）
  });
}
