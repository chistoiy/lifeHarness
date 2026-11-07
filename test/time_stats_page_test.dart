import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/features/calendar/data/category_dao.dart';
import 'package:lifeharness/features/calendar/data/time_block_dao.dart';
import 'package:lifeharness/features/calendar/domain/time_block.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart';
import 'package:lifeharness/features/calendar/presentation/time_stats_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// V1.52 批4 时间账本页：四档切换 / 实算聚合 / 空态 / 折叠。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late TimeBlockDao dao;
  late EventBus bus;
  final now = DateTime.now();
  final d0 = DateTime(now.year, now.month, now.day);

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    dao = TimeBlockDao(db);
    bus = EventBus();
  });
  tearDown(() async {
    await db.close();
    await bus.dispose();
  });

  Future<void> pump(WidgetTester tester) async {
    await useSurface(tester, const Size(900, 2600)); // 长列表尾卡入树（懒构建）
    await tester.pumpWidget(ProviderScope(
      overrides: [
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
        timeBlockDaoProvider.overrideWithValue(dao),
      ],
      child: MaterialApp(home: const TimeStatsPage()),
    ));
    await settle5(tester);
  }

  testWidgets('空态：无块时给引导文案', (tester) async {
    await pump(tester);
    expect(find.textContaining('该时段还没有时间块'), findsWidgets);
    expect(find.text('日'), findsOneWidget);
    expect(find.text('年'), findsOneWidget);
  });

  testWidgets('周档实算：hero 总时长与排行随块变化', (tester) async {
    await dao.insert(TimeBlock(
        day: d0, startMin: 540, endMin: 600, catName: '工作', note: '晨间规划'));
    await dao.insert(TimeBlock(
        day: d0, startMin: 600, endMin: 690, catName: '学习', note: '读书'));
    await pump(tester);

    expect(find.textContaining('2 时 30 分'), findsWidgets,
        reason: '60+90 分钟合计');
    expect(find.textContaining('总时长汇总'), findsOneWidget);
    expect(find.textContaining('分类时长汇总'), findsOneWidget);
    expect(find.textContaining('工作'), findsWidgets);
    expect(find.textContaining('学习'), findsWidgets);
    expect(find.textContaining('未记录'), findsWidgets);
    expect(find.byType(CustomPaint), findsWidgets, reason: '环形/柱图自绘');
  });

  testWidgets('四档切换与翻页不抛错（计时中块计入）', (tester) async {
    await dao.startTiming(d0, 540, catName: '娱乐');
    await pump(tester);
    for (final m in ['日', '月', '年', '周']) {
      await tester.tap(find.text(m).last);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('日').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('计时中'), findsWidgets);
  });

  testWidgets('卡片可折叠：点排行标题行收起内容且不抛错', (tester) async {
    await dao.insert(TimeBlock(
        day: d0, startMin: 540, endMin: 600, catName: '工作', note: '晨间规划'));
    await pump(tester);
    final title = find.textContaining('分类时长汇总');
    expect(title, findsOneWidget);
    final rowsBefore = find.textContaining('工作').evaluate().length;
    await tester.tap(title);
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('分类时长汇总'), findsOneWidget);
    expect(find.textContaining('工作').evaluate().length, lessThan(rowsBefore),
        reason: '折叠后内容行消失');
  });
}
