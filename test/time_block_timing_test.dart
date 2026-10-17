import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/calendar/data/time_block_dao.dart';
import 'package:lifeharness/features/calendar/domain/time_block.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// V1.52 时间块数据层用例：单一「计时中」状态机（source=timing）+ 自动收口 + 撤销快照。
void main() {
  sqfliteFfiInit();

  late Database db;
  late TimeBlockDao dao;
  final today = DateTime.now();
  final d0 = DateTime(today.year, today.month, today.day);

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    dao = TimeBlockDao(db);
  });

  tearDown(() async => db.close());

  group('计时中块（source=timing）', () {
    test('startTiming 建行时结束=起始（随当前推进由 effEnd 表达）', () async {
      final b = await dao.startTiming(d0, 540, catName: '工作', note: '写周报');
      expect(b.source, kSrcTiming);
      expect(b.endMin, 540);
      expect(b.isTiming, isTrue);
      final one = await dao.activeTiming();
      expect(one?.id, b.id);
    });

    test('再开一段会收口上一段并保持单活', () async {
      final a = await dao.startTiming(d0, 540, catName: '工作');
      final b = await dao.startTiming(d0, 600, catName: '娱乐');
      final active = await dao.activeTiming();
      expect(active?.id, b.id);
      final day = await dao.listByDay(d0);
      final old = day.firstWhere((x) => x.id == a.id);
      expect(old.source, kSrcMark, reason: '上一段转普通块');
      expect(old.endMin, 600, reason: '收口到新段起始');
    });

    test('endTiming 落实际结束时刻并转回 mark', () async {
      final b = await dao.startTiming(d0, 540, catName: '清洁');
      final done = await dao.endTiming(b.id, 585);
      expect(done?.source, kSrcMark);
      expect(done?.endMin, 585);
      expect(await dao.activeTiming(), isNull);
    });

    test('计时中块不再被 activeTiming 命中（结束后）', () async {
      final b = await dao.startTiming(d0, 540, catName: '清洁');
      await dao.endTiming(b.id, 560);
      expect(await dao.activeTiming(), isNull);
    });
  });

  group('markRange 与计时块的收口联动', () {
    test('同日起始更晚的新段 → 计时块自动收口', () async {
      final t = await dao.startTiming(d0, 540, catName: '工作');
      await dao.markRange(d0, 600, 660, catName: '娱乐');
      final day = await dao.listByDay(d0);
      final row = day.firstWhere((x) => x.id == t.id);
      expect(row.source, kSrcMark);
      expect(row.endMin, lessThanOrEqualTo(600),
          reason: '收口=min(当前, 新段起始) 且不早于 540');
      expect(row.endMin, greaterThanOrEqualTo(540));
    });

    test('补录更早时段 → 计时块继续计时不受影响', () async {
      final t = await dao.startTiming(d0, 600, catName: '工作');
      await dao.markRange(d0, 480, 540, catName: '餐饮');
      final day = await dao.listByDay(d0);
      final row = day.firstWhere((x) => x.id == t.id);
      expect(row.source, kSrcTiming, reason: '新段起始更早=纯补录，不收口');
      expect(row.startMin, 600);
    });

    test('其他日期的补录不触碰今天的计时块', () async {
      final other = d0.subtract(const Duration(days: 3));
      await dao.startTiming(d0, 540, catName: '工作');
      await dao.markRange(other, 300, 360, catName: '学习');
      final act = await dao.activeTiming();
      expect(act?.startMin, 540, reason: '跨日补录不收口今日计时');
    });
  });

  group('编辑 / 撤销快照', () {
    test('save 改写起止与分类', () async {
      final b = await dao.insert(TimeBlock(
          day: d0, startMin: 540, endMin: 585, catName: '工作', note: '晨间规划'));
      await dao.save(b.copyWith(startMin: 550, endMin: 600, catName: '学习', note: '读书'));
      final row = (await dao.listByDay(d0)).first;
      expect([row.startMin, row.endMin, row.catName, row.note], [550, 600, '学习', '读书']);
    });

    test('restoreDay 回滚删除（撤销语义）', () async {
      await dao.insert(TimeBlock(day: d0, startMin: 540, endMin: 585, catName: '工作'));
      await dao.insert(TimeBlock(day: d0, startMin: 600, endMin: 660, catName: '学习'));
      final snap = await dao.snapshotDay(d0);
      expect(snap.length, 2);
      await dao.remove(snap.first.id!);
      expect((await dao.listByDay(d0)).length, 1);
      await dao.restoreDay(d0, snap);
      final back = await dao.listByDay(d0);
      expect(back.length, 2);
      expect(back.map((b) => b.startMin).toSet(), {540, 600});
    });
  });

  group('区间查询与月统计', () {
    test('listInRange 覆盖跨日区间', () async {
      final y = d0.subtract(const Duration(days: 2));
      final t = d0.add(const Duration(days: 1));
      await dao.insert(TimeBlock(day: y, startMin: 540, endMin: 600, catName: '工作'));
      await dao.insert(TimeBlock(day: t, startMin: 540, endMin: 600, catName: '工作'));
      final all = await dao.listInRange(y, t);
      expect(all.length, 2);
      expect((await dao.listInRange(t, t)).length, 1);
    });

    test('daysWithTiming 只命中计时中所在日', () async {
      await dao.insert(TimeBlock(day: d0, startMin: 300, endMin: 330, catName: '工作'));
      await dao.startTiming(d0, 540, catName: '娱乐');
      final days = await dao.daysWithTiming(d0.year, d0.month);
      expect(days, {d0.day});
      expect((await dao.daysWithBlocks(d0.year, d0.month)).contains(d0.day), isTrue);
    });
  });
}
