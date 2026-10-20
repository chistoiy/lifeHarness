import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/calendar/data/legacy_event_merge.dart';
import 'package:lifeharness/features/calendar/domain/time_block.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// B10（2026-10-13 裁决「搬，旧表不维护了」）旧 events 一次性并入守卫：
/// ① 换算口径：planning 计划窗 / done 实际窗 / active 收口至此刻 / 跨天拆段 /
///    all_day 全天段 / cat_id→分类名映射（缺落「其他」）；
/// ② 幂等护栏：搬完删行 ⇒ 表空即空跑，双跑不重、备份回滚后可重搬；
/// ③ source='event'＋event_id 保留原 id（审计可溯）。
void main() {
  sqfliteFfiInit();

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    // 分类种子由 schema.createStatements 自带（含「工作」），勿重复插。
  });

  tearDown(() async => db.close());

  Future<List<Map<String, Object?>>> blocks() =>
      db.query(DbSchema.tTimeBlocks, orderBy: 'day ASC, start_min ASC');
  Future<int> eventCount() async {
    final rows = await db.query(DbSchema.tEvents);
    return rows.length;
  }

  int dayMs(DateTime d) =>
      DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;

  test('空表：run 返回 0 且无副作用（幂等护栏的空跑支路）', () async {
    expect(await LegacyEventMerge.run(db), 0);
    expect(await blocks(), isEmpty);
    expect(await eventCount(), 0);
  });

  test('planning 计划窗并入：day/start_min/end_min/category/note/source/event_id',
      () async {
    final d = DateTime(2026, 9, 19);
    final workCat = await db.query(DbSchema.tCategories,
        where: 'name = ?', whereArgs: ['工作']);
    await db.insert(DbSchema.tEvents, {
      'title': '产品评审',
      'start_at': DateTime(d.year, d.month, d.day, 10).millisecondsSinceEpoch,
      'end_at': DateTime(d.year, d.month, d.day, 11, 30).millisecondsSinceEpoch,
      'all_day': 0,
      'status': 0,
      'cat_id': workCat.single['id'],
      'created_at': 0,
      'updated_at': 0,
    });
    expect(await LegacyEventMerge.run(db), 1);
    final bs = await blocks();
    expect(bs, hasLength(1));
    expect(bs.single['day'], dayMs(d));
    expect(bs.single['start_min'], 600);
    expect(bs.single['end_min'], 690);
    expect(bs.single['category'], '工作');
    expect(bs.single['note'], '产品评审');
    expect(bs.single['source'], kSrcEvent);
    expect(bs.single['event_id'], bs.single['id'] /* 单行自证 id 通路 */);
    // 旧表清空（护栏闭环）。
    expect(await eventCount(), 0);
  });

  test('done 事件按实际窗并入（end_at 优先）；无 cat_id 落「其他」', () async {
    final d = DateTime(2026, 9, 20);
    await db.insert(DbSchema.tEvents, {
      'title': '复盘',
      'start_at': DateTime(d.year, d.month, d.day, 14).millisecondsSinceEpoch,
      'end_at': DateTime(d.year, d.month, d.day, 15).millisecondsSinceEpoch,
      'status': 2,
      'duration_min': 60,
      'created_at': 0,
      'updated_at': 0,
    });
    expect(await LegacyEventMerge.run(db), 1);
    final bs = await blocks();
    expect(bs.single['start_min'], 840);
    expect(bs.single['end_min'], 900);
    expect(bs.single['category'], kCatOther);
  });

  test('active 事件收口至当前时刻（status=1 不再存活于块表）', () async {
    final start = DateTime.now().subtract(const Duration(hours: 2));
    await db.insert(DbSchema.tEvents, {
      'title': '旧进行中',
      'start_at': start.millisecondsSinceEpoch,
      'status': 1,
      'created_at': 0,
      'updated_at': 0,
    });
    expect(await LegacyEventMerge.run(db), 1);
    final bs = await blocks();
    expect(bs, hasLength(1));
    final nowMin = DateTime.now().hour * 60 + DateTime.now().minute;
    final sMin = bs.single['start_min'] as int;
    final eMin = bs.single['end_min'] as int;
    expect(eMin, greaterThan(sMin));
    // 收口窗覆盖「此刻」（允许跨 0 点折算：end<=start 只可能发生在跨天段尾）。
    if (sMin < 1440 && eMin > 0) {
      expect(eMin >= nowMin - 2, isTrue,
          reason: 'end_min=$eMin 应≈此刻 $nowMin');
    }
    expect(await eventCount(), 0);
  });

  test('跨天事件按日拆段：首日 [s,1440) ＋ 末日 [0,e)', () async {
    final d0 = DateTime(2026, 9, 19);
    await db.insert(DbSchema.tEvents, {
      'title': '出差',
      'start_at': DateTime(d0.year, d0.month, d0.day, 13).millisecondsSinceEpoch,
      'end_at':
          DateTime(d0.year, d0.month, d0.day + 2, 12).millisecondsSinceEpoch,
      'status': 0,
      'created_at': 0,
      'updated_at': 0,
    });
    expect(await LegacyEventMerge.run(db), 3);
    final bs = await blocks();
    // 首日 13:00-24:00。
    expect(bs[0]['day'], dayMs(d0));
    expect(bs[0]['start_min'], 780);
    expect(bs[0]['end_min'], 1440);
    // 中间整日 0-1440。
    expect(bs[1]['day'], dayMs(d0.add(const Duration(days: 1))));
    expect(bs[1]['start_min'], 0);
    expect(bs[1]['end_min'], 1440);
    // 末日 0-12:00。
    expect(bs[2]['day'], dayMs(d0.add(const Duration(days: 2))));
    expect(bs[2]['start_min'], 0);
    expect(bs[2]['end_min'], 720);
  });

  test('all_day：每日 0-1440 全天段', () async {
    final d0 = DateTime(2026, 9, 19);
    await db.insert(DbSchema.tEvents, {
      'title': '周年庆',
      'start_at': dayMs(d0),
      'end_at': dayMs(d0.add(const Duration(days: 1))),
      'all_day': 1,
      'status': 0,
      'created_at': 0,
      'updated_at': 0,
    });
    expect(await LegacyEventMerge.run(db), 2);
    final bs = await blocks();
    for (final b in bs) {
      expect(b['start_min'], 0);
      expect(b['end_min'], 1440);
      expect(b['note'], '周年庆');
    }
  });

  test('双跑不重：搬完删行后第二次 run 空跑（幂等护栏主判据）', () async {
    final d = DateTime(2026, 9, 19);
    await db.insert(DbSchema.tEvents, {
      'title': '唯一一条',
      'start_at': DateTime(d.year, d.month, d.day, 9).millisecondsSinceEpoch,
      'end_at': DateTime(d.year, d.month, d.day, 10).millisecondsSinceEpoch,
      'status': 0,
      'created_at': 0,
      'updated_at': 0,
    });
    expect(await LegacyEventMerge.run(db), 1);
    expect(await LegacyEventMerge.run(db), 0);
    expect(await blocks(), hasLength(1));
    expect(await eventCount(), 0);
  });
}
