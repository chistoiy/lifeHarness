import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/features/calendar/data/category_dao.dart';
import 'package:lifeharness/features/calendar/data/event_dao.dart';
import 'package:lifeharness/features/calendar/data/time_block_dao.dart';
import 'package:lifeharness/features/calendar/domain/cal_event.dart';
import 'package:lifeharness/features/calendar/domain/event_repository.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_page.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart';
import 'package:lifeharness/features/calendar/presentation/widgets/time_pick_sheet.dart';
import 'package:lifeharness/shared/linkage/linkage_events.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late EventRepository repo;
  late EventBus bus;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    bus = EventBus();
    repo = EventRepository(EventDao(db), bus);
  });

  tearDown(() async {
    await db.close();
    await bus.dispose();
  });

  group('EventRepository 两态流与冲突', () {
    test('startNow 建 active 事件并发布 TimeTrackingEvent(started)', () async {
      final events = <TimeTrackingEvent>[];
      final sub = bus.on<TimeTrackingEvent>().listen(events.add);
      final e = await repo.startNow(
          CalEvent(title: '写周报', start: DateTime.now()));
      expect(e.status, EventStatus.active);
      expect(e.end!.difference(e.start).inMinutes, 60);
      await Future.delayed(Duration.zero);
      expect(events.single.started, isTrue);
      await sub.cancel();
    });

    test('已有进行中时 startNow 抛错（单活约束）', () async {
      await repo.startNow(CalEvent(title: 'A', start: DateTime.now()));
      await expectLater(
          repo.startNow(CalEvent(title: 'B', start: DateTime.now())),
          throwsStateError);
    });

    test('endActive 回填实际耗时并转已完成（L1/L4）', () async {
      // 直接造一条 25 分钟前开始的进行中事件。
      final dao = EventDao(db);
      await dao.insert(CalEvent(
          title: '专注',
          start: DateTime.now().subtract(const Duration(minutes: 25)),
          status: EventStatus.active));
      final ended = await repo.endActive();
      expect(ended, isNotNull);
      expect(ended!.durationMin, greaterThanOrEqualTo(25));
      final list = await repo.listAll();
      expect(list.single.status, EventStatus.done);
      expect(list.single.end!.isAfter(list.single.start), isTrue);
    });

    test('冲突检测：重叠 30 分钟成对报告，跨天/全天不参与', () {
      final d = DateTime(2026, 9, 19);
      final conflicts = EventRepository.conflictsOf([
        CalEvent(title: '评审', start: d.add(const Duration(hours: 10)), end: d.add(const Duration(hours: 11))),
        CalEvent(title: '午餐', start: d.add(const Duration(hours: 10, minutes: 30)), end: d.add(const Duration(hours: 11, minutes: 30))),
        CalEvent(title: '全天占位', start: d, allDay: true),
        CalEvent(title: '无重叠', start: d.add(const Duration(hours: 15)), end: d.add(const Duration(hours: 16))),
      ]);
      expect(conflicts, hasLength(1));
      expect(conflicts.single.overlapMin, 30);
      expect({conflicts.single.a.title, conflicts.single.b.title}, {'评审', '午餐'});
    });
  });

  testWidgets('日程页：月历42格/三色点/视图切换/新建入口', (tester) async {
    final now = DateTime.now();
    await repo.create(CalEvent(
        title: '产品评审',
        start: DateTime(now.year, now.month, now.day, 10),
        end: DateTime(now.year, now.month, now.day, 11)));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        eventRepositoryProvider.overrideWithValue(repo),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
      ],
      child: const MaterialApp(home: CalendarPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('${now.month}'), findsWidgets); // 月历含今天
    expect(find.textContaining('全天0-24'), findsOneWidget); // 默认块视图（V1.19 四视图）

    // 视图菜单切轴：事件卡可见。
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('☰ 轴 · 时间轴'));
    await tester.pumpAndSettle();
    expect(find.text('产品评审'), findsOneWidget);
  });

  testWidgets('V1.27 C1/C6：日历无「时间」标题行·月历去切月按钮行·展开态左右滑动切月',
      (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        eventRepositoryProvider.overrideWithValue(repo),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
      ],
      child: const MaterialApp(home: CalendarPage()),
    ));
    await tester.pumpAndSettle();

    // C1：页内标题行删除（不再渲染「时间」大字标题），搜索在本行不丢
    expect(find.text('时间'), findsNothing);
    expect(find.byIcon(Icons.search), findsOneWidget);
    // C1：左上默认只显月日（当年不显年）
    expect(find.text('年'), findsNothing);
    // C6：切月按钮行已删
    expect(find.byIcon(Icons.chevron_left), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);

    // C6：展开态月历左滑 → 切到下月（分段移动手势保证 HorizontalDrag 过 slop+速度阈值）
    Future<void> swipeMonthPanel(int dx) async {
      final g = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('month-panel'))));
      await g.moveBy(Offset(dx / 4, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await g.moveBy(Offset(dx / 2, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await g.moveBy(Offset(dx / 4, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await g.up();
      await tester.pumpAndSettle();
    }

    await swipeMonthPanel(-200);
    final nm = now.month + 1;
    final wantMonth = ((nm - 1) % 12 + 1).toString().padLeft(2, '0');
    expect(tester.widget<Text>(find.byKey(const ValueKey('hd-month'))).data,
        wantMonth,
        reason: '头部月份应为下月 $wantMonth');

    // 右滑切回
    await swipeMonthPanel(200);
    expect(tester.widget<Text>(find.byKey(const ValueKey('hd-month'))).data,
        now.month.toString().padLeft(2, '0'));
  });

  testWidgets('V1.28 回归：月历末行日期完整可见（修复行高随屏宽放大被裁切）',
      (tester) async {
    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        eventRepositoryProvider.overrideWithValue(repo),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
      ],
      child: const MaterialApp(home: CalendarPage()),
    ));
    await tester.pumpAndSettle();

    final panel = tester.getRect(find.byKey(const ValueKey('month-panel')));
    final cell = tester.getRect(find.text('$lastDay').last);
    expect(cell.top, greaterThanOrEqualTo(panel.top));
    expect(cell.bottom, lessThanOrEqualTo(panel.bottom + 0.5),
        reason: '末行（$lastDay 号）超出月历卡=被裁切，宽屏下曾必现');
  });

  testWidgets('智能折叠：下滚收起月历为周行 · 点展开 ▾ 回切', (tester) async {
    final now = DateTime.now();
    for (var i = 0; i < 14; i++) {
      await repo.create(CalEvent(
          title: '日程$i', start: DateTime(now.year, now.month, now.day, 8 + (i % 10))));
    }
    await tester.pumpWidget(ProviderScope(
      overrides: [
        eventRepositoryProvider.overrideWithValue(repo),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
      ],
      child: const MaterialApp(home: CalendarPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('展开 ▾'), findsNothing);

    await tester.fling(find.byType(ListView).first, const Offset(0, -150), 800);
    await tester.pumpAndSettle();
    expect(find.text('展开 ▾'), findsOneWidget);

    // 收起后列表停在滚动位，回顶再点展开（避免按钮被顶栏遮挡点不中）
    tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.text('展开 ▾'));
    await tester.pumpAndSettle();
    expect(find.text('展开 ▾'), findsNothing);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('V1.28⑧ 周视图：点已添加格子→详情可编辑 · 空格子才开补录弹层', (tester) async {
    final now = DateTime.now();
    await repo.create(CalEvent(
        title: '周视图评审',
        start: DateTime(now.year, now.month, now.day, 10),
        end: DateTime(now.year, now.month, now.day, 11)));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        eventRepositoryProvider.overrideWithValue(repo),
        timeBlockDaoProvider.overrideWithValue(TimeBlockDao(db)),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
      ],
      child: const MaterialApp(home: CalendarPage()),
    ));
    await tester.pumpAndSettle();

    // 切周视图（7×24）
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('▤ 周 · 7×24'));
    await tester.pumpAndSettle();
    expect(find.textContaining('空格子 → 添加时间段'), findsOneWidget);

    // 中间列=选中日（di=3），10 点格被事件覆盖 → 点它开统一编辑弹层（V1.52）
    final used = find.byKey(const ValueKey('wk-cell-3-10'));
    await tester.ensureVisible(used);
    await tester.pumpAndSettle();
    await tester.tap(used);
    await tester.pumpAndSettle();
    expect(find.text('编辑事件 / 时间块'), findsOneWidget);
    expect(find.text('保存修改'), findsOneWidget);
    expect(find.text('添加事件 / 时间块'), findsNothing);

    // 关详情（点遮罩）后点 4 点空格子 → 才应开补录弹层
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    final empty = find.byKey(const ValueKey('wk-cell-3-4'));
    await tester.ensureVisible(empty);
    await tester.pumpAndSettle();
    await tester.tap(empty);
    await tester.pumpAndSettle();
    expect(find.text('添加事件 / 时间块'), findsOneWidget);
  });

  testWidgets('V1.28⑤ 展开↔收起与切月动画：过渡后布局收敛，月历/周行各自就位',
      (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        eventRepositoryProvider.overrideWithValue(repo),
        timeBlockDaoProvider.overrideWithValue(TimeBlockDao(db)),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
      ],
      child: const MaterialApp(home: CalendarPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('month-panel')), findsOneWidget);

    // 点选中日=收起为周行（AnimatedSize+Switcher 接管），settle 后无月历。
    // 限定月历卡内：块视图小时格也显「21」，全树 .last 会点错。
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('month-panel')),
        matching: find.text('${now.day}')));
    await tester.pumpAndSettle();
    expect(find.text('展开 ▾'), findsOneWidget);
    expect(find.byKey(const ValueKey('month-panel')), findsNothing);

    // 周行左右滑动切天（动画后仍收敛），再点展开回月历
    final g = await tester.startGesture(
        tester.getCenter(find.text('展开 ▾')).translate(0, 20));
    await g.moveBy(const Offset(-30, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await g.moveBy(const Offset(-60, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await g.up();
    await tester.pumpAndSettle();
    expect(find.text('展开 ▾'), findsOneWidget); // 未挂死/未溢出

    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.text('展开 ▾'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('month-panel')), findsOneWidget);
  });

  testWidgets('统一添加弹层：预选选中日时段 → 添加落库（补录·四视图同步）', (tester) async {
    final tbDao = TimeBlockDao(db);
    final preset = DateTime(2026, 3, 17);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        eventRepositoryProvider.overrideWithValue(repo),
        timeBlockDaoProvider.overrideWithValue(tbDao),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () => showTimePickSheet(context, ref, day: preset, startMin: 9 * 60),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('添加事件 / 时间块'), findsOneWidget);
    expect(find.textContaining('3/17'), findsWidgets); // 起始轮定位到 3月17日

    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    final rows = await db.query('time_blocks');
    expect(rows, hasLength(1));
    expect(rows.single['start_min'], 540);
    expect(rows.single['end_min'], 600);
  });
}
