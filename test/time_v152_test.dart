import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/features/calendar/data/category_dao.dart';
import 'package:lifeharness/features/calendar/data/event_dao.dart';
import 'package:lifeharness/features/calendar/data/time_block_dao.dart';
import 'package:lifeharness/features/calendar/domain/event_repository.dart';
import 'package:lifeharness/features/calendar/domain/time_block.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_page.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart';
import 'package:lifeharness/features/calendar/presentation/widgets/time_pick_sheet.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// V1.52 时间模块 UI 回归：统一添加/编辑弹层 + 单一计时态 + 速记列开计时块。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late TimeBlockDao tbDao;
  late EventBus bus;
  final now = DateTime.now();
  final d0 = DateTime(now.year, now.month, now.day);
  int nowMin() => now.hour * 60 + now.minute;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    tbDao = TimeBlockDao(db);
    bus = EventBus();
  });
  tearDown(() async {
    await db.close();
    await bus.dispose();
  });

  Future<void> pumpCal(WidgetTester tester, {String view = 'axis'}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        eventRepositoryProvider.overrideWithValue(
            EventRepository(EventDao(db), bus)),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
        timeBlockDaoProvider.overrideWithValue(tbDao),
        calViewModeProvider.overrideWith((ref) => view),
      ],
      child: const MaterialApp(home: CalendarPage()),
    ));
    await settle5(tester);
  }

  testWidgets('轴视图点已有块 → 打开与添加同款的统一编辑弹层', (tester) async {
    await tbDao.insert(TimeBlock(
        day: d0, startMin: 570, endMin: 585, catName: '娱乐', note: '娱乐'));
    await pumpCal(tester);

    await tester.tap(find.textContaining('娱乐').first);
    await tester.pumpAndSettle();

    expect(find.text('编辑事件 / 时间块'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    expect(find.text('保存修改'), findsOneWidget);
    // V1.52：不再出现旧「取消标记」详情层
    expect(find.text('取消标记'), findsNothing);
    // 弹层瘦身：时长快捷钮已删 · 分类入口并入标题行
    expect(find.text('15分'), findsNothing);
    expect(find.text('管理 ›'), findsOneWidget);
    expect(find.text('1 分一档 · 滚轮循环'), findsOneWidget);
  });

  testWidgets('编辑弹层预填该块的分类与备注', (tester) async {
    await tbDao.insert(TimeBlock(
        day: d0, startMin: 570, endMin: 585, catName: '清洁', note: '擦桌子'));
    await pumpCal(tester);
    await tester.tap(find.textContaining('擦桌子').first);
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.controller!.text, '擦桌子');
    // V1.52 真机反馈⑤：分类格改自绘 CatPill（ChoiceChip 窄列会把名称挤没）
    final chip = tester.widget<CatPill>(
        find.widgetWithText(CatPill, '清洁').first);
    expect(chip.selected, isTrue);
  });

  testWidgets('今天 FAB 添加：起止默认当前分钟 · 确认即计时中并出结束按钮',
      (tester) async {
    await pumpCal(tester);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('添加事件 / 时间块'), findsOneWidget);
    expect(find.textContaining('${nowMin() ~/ 60}'.padLeft(2, '0')), findsWidgets);

    await tester.tap(find.text('添加'));
    await settle5(tester);
    await clearToasts(tester);

    final act = await tbDao.activeTiming();
    expect(act, isNotNull, reason: '确认添加即为计时中块');
    expect(act!.startMin, nowMin());
    expect(act.source, kSrcTiming);

    await pumpCal(tester);
    expect(find.textContaining('● 计时中'), findsOneWidget);
    expect(find.text('■ 结束计时'), findsOneWidget);
  });

  testWidgets('计时中再添加新事件 → 上一段自动收口（单活）', (tester) async {
    final t = await tbDao.startTiming(d0, nowMin() - 10, catName: '工作');
    await pumpCal(tester);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加'));
    await settle5(tester);

    final day = await tbDao.listByDay(d0);
    final old = day.firstWhere((b) => b.id == t.id);
    expect(old.source, kSrcMark, reason: '旧计时段被收口');
    expect(old.endMin, greaterThanOrEqualTo(t.startMin));
    final active = await tbDao.activeTiming();
    expect(active?.id, isNot(t.id));
  });

  testWidgets('块视图速记列：未选中点分类=开计时块（非今天拒绝）', (tester) async {
    await pumpCal(tester, view: 'block');
    // 计时块会启动 _pulse 无限动画 → 禁用 pumpAndSettle（永不收敛），改有界 pump。
    await tester.tap(find.text('工作').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    var act = await tbDao.activeTiming();
    for (var i = 0; i < 40 && act == null; i++) {
      // 治理G6 悬案根治：点按后开块落库在高负载下可迟一拍（本用例曾随机挂）→
      // 有界轮询等行出现，超时仍由下方 isNotNull 判失败。
      await Future<void>.delayed(const Duration(milliseconds: 50));
      act = await tbDao.activeTiming();
    }
    expect(act, isNotNull);
    expect(act!.catName, '工作');
    // 治理G6：原严格比对文件头 now，断言跨分钟即假失败 → 容忍点按/开块 +0~2 分钟。
    final mSeed = now.hour * 60 + now.minute;
    expect(act.startMin,
        anyOf(mSeed, (mSeed + 1) % 1440, (mSeed + 2) % 1440),
        reason: '开块分钟=点按时刻（容忍轮询期跨分钟）');
  });

  testWidgets('非今天点速记列不开计时块（拒绝并提示）', (tester) async {
    final other = d0.subtract(const Duration(days: 5));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        eventRepositoryProvider.overrideWithValue(
            EventRepository(EventDao(db), bus)),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
        timeBlockDaoProvider.overrideWithValue(tbDao),
        calSelectedProvider.overrideWith((ref) => other),
      ],
      child: const MaterialApp(home: CalendarPage()),
    ));
    await settle5(tester);
    await tester.tap(find.text('工作').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(await tbDao.activeTiming(), isNull);
    expect(await tbDao.listByDay(other), isEmpty);
  });

  testWidgets('轴视图空隙可点补录（≥15 分钟空档出条）', (tester) async {
    await tbDao.insert(TimeBlock(
        day: d0, startMin: 540, endMin: 600, catName: '工作', note: '晨间规划'));
    await pumpCal(tester);
    expect(find.textContaining('空闲'), findsWidgets);

    await tester.tap(find.textContaining('空闲').first);
    await tester.pumpAndSettle();
    expect(find.text('添加事件 / 时间块'), findsOneWidget);
  });

  testWidgets('时间页顶栏账本入口存在（V1.52 批4）', (tester) async {
    await pumpCal(tester);
    expect(find.byIcon(Icons.bar_chart_rounded), findsOneWidget);
  });
}
