import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/calendar/data/category_dao.dart';
import 'package:lifeharness/features/calendar/data/time_block_dao.dart';
import 'package:lifeharness/features/calendar/domain/time_block.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/time_env.dart';

/// F1-1/B1/B3（时间模块批1 · 冻结口径）跨天补录守卫：
/// ① 结束日轮=起始日 +0..7 动态窗口（可跨月，如 9/30→10/7）；
/// ② 同日 e ≤ s ⇒ 拦截 + 就地红字「结束不能早于开始」，不落库；
/// ③ 跨天段按两段行落库（首日 [s,1440) ＋ 次日 [0,e)）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late TimeBlockDao dao;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    dao = TimeBlockDao(db);
  });
  tearDown(() async => db.close());

  Future<TimeBlock?> row(DateTime day) async {
    final list = await dao.listByDay(DateTime(day.year, day.month, day.day));
    return list.isEmpty ? null : list.first;
  }

  testWidgets('结束日轮 8 档动态窗口：上拨跨月到 10/1，下拨从最顶回绕到 10/7（9/30 起）',
      (tester) async {
    await pumpTimeHost(
      tester,
      day: DateTime(2026, 9, 30),
      overrides: [
        timeBlockDaoProvider.overrideWithValue(dao),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('open-pick')));
    await tester.pumpAndSettle();

    // 结束日轮 = 弹层 6 个滚轮中的第 4 个（起始 日/时/分 + 结束 日/时/分）。
    final endDayWheel = find.byType(CupertinoPicker).at(3);
    // 上拨一档：+1 天 → 10/1（跨月可表达）。
    await tester.fling(endDayWheel, const Offset(0, -30), 200);
    await tester.pumpAndSettle();
    expect(find.textContaining('10/1'), findsWidgets);

    // 下拨一档：0 −1 回绕到窗口末档 = +7 → 10/7（窗口恰 8 档，回绕不到 9/29）。
    await tester.fling(endDayWheel, const Offset(0, 30), 200);
    await tester.pumpAndSettle();
    await tester.fling(endDayWheel, const Offset(0, 30), 200);
    await tester.pumpAndSettle();
    expect(find.textContaining('10/7'), findsWidgets);
    // absence 目标选窗口外的 10/8：9/29 会作为相邻项出现在起始日轮里，不能当判据。
    expect(find.textContaining('10/8'), findsNothing);
  });

  testWidgets('同日 e ≤ s ⇒ 就地红字拦截，不落库（B3）', (tester) async {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day - 1); // 非今天=纯补录
    await pumpTimeHost(
      tester,
      day: day,
      startMin: 10 * 60, // 10:00 → 默认结束 11:00
      overrides: [
        timeBlockDaoProvider.overrideWithValue(dao),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('open-pick')));
    await tester.pumpAndSettle();

    // 结束小时轮（第 5 个滚轮）精确下拨一档（itemExtent=26，drag +2px 过手势 slop）：
    // 11:00 → 10:00 ⇒ e == s。fling 30px 带惯性会漂过档位。
    await tester.drag(find.byType(CupertinoPicker).at(4), const Offset(0, 28));
    await tester.pumpAndSettle();
// e==s 的判据：时长读数归 0（头部格式是「起 → 结束日 结束时」，中间夹日期，
// 不能拿 '10:00 → 10:00' 当子串判据）。
    expect(find.textContaining('· 0 分钟'), findsOneWidget);

    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    // 就地红字（弹层不关、不落库）。
    expect(find.text('✕ 结束不能早于开始'), findsOneWidget);
    expect(find.text('添加'), findsOneWidget);
    expect(await dao.listByDay(day), isEmpty);
  });

  testWidgets('跨天补录 23:30→次日 00:30 ⇒ 两段行落库（首日 [1410,1440) ＋ 次日 [0,30)）',
      (tester) async {
    await pumpTimeHost(
      tester,
      day: DateTime(2026, 9, 30),
      startMin: 23 * 60 + 30, // 起始 23:30 → 默认结束 = 次日 00:30（1440 折算）
      overrides: [
        timeBlockDaoProvider.overrideWithValue(dao),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('open-pick')));
    await tester.pumpAndSettle();

    // 头部读数：跨天 + 60 分钟（不丢时长）。
    expect(find.textContaining('· 跨天'), findsOneWidget);
    expect(find.textContaining('60 分钟'), findsOneWidget);

    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    final head = await row(DateTime(2026, 9, 30));
    final tail = await row(DateTime(2026, 10, 1));
    expect(head, isNotNull);
    expect(head!.startMin, 23 * 60 + 30);
    expect(head.endMin, 1440);
    expect(tail, isNotNull);
    expect(tail!.startMin, 0);
    expect(tail.endMin, 30);
    // 两段合计 = 真实 60 分钟（不 clamp 丢时长）。
    expect((head.endMin - head.startMin) + (tail.endMin - tail.startMin), 60);
  });

  testWidgets('结束恰为次日 00:00（e==0）⇒ 只落首日到 24:00，无零长尾巴', (tester) async {
    await pumpTimeHost(
      tester,
      day: DateTime(2026, 9, 30),
      startMin: 23 * 60, // 23:00 → 默认结束 = 次日 00:00
      overrides: [
        timeBlockDaoProvider.overrideWithValue(dao),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('open-pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    final head = await row(DateTime(2026, 9, 30));
    expect(head, isNotNull);
    expect(head!.startMin, 23 * 60);
    expect(head.endMin, 1440);
    expect(await dao.listByDay(DateTime(2026, 10, 1)), isEmpty);
  });
}
