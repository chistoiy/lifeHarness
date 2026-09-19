import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/features/calendar/data/event_dao.dart';
import 'package:lifeharness/features/calendar/domain/cal_event.dart';
import 'package:lifeharness/features/calendar/domain/event_repository.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_page.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart';
import 'package:lifeharness/features/calendar/presentation/widgets/event_sheet.dart';
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
      overrides: [eventRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: CalendarPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('${now.month}'), findsWidgets); // 月历含今天
    expect(find.text('产品评审'), findsOneWidget); // 日视图时间轴
    expect(find.textContaining('月视图展开'), findsOneWidget);
    expect(find.textContaining('新建日程'), findsOneWidget);

    // 切周/月视图。
    await tester.tap(find.text('周视图'));
    await tester.pumpAndSettle();
    expect(find.textContaining('产品评审'), findsWidgets);

    await tester.tap(find.text('月视图'));
    await tester.pumpAndSettle();
    expect(find.textContaining('· 1 项'), findsOneWidget);
  });

  testWidgets('智能折叠：向下滚动收起月历为周行', (tester) async {
    final now = DateTime.now();
    // 造足量事件使页面可滚动。
    for (var i = 0; i < 14; i++) {
      await repo.create(CalEvent(
          title: '日程$i', start: DateTime(now.year, now.month, now.day, 8 + (i % 10))));
    }
    await tester.pumpWidget(ProviderScope(
      overrides: [eventRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: CalendarPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('月视图展开'), findsOneWidget);

    await tester.fling(find.byType(ListView), const Offset(0, -150), 800);
    await tester.pumpAndSettle();
    expect(find.textContaining('已收起为周'), findsOneWidget);
    // 回滚到顶使周行可见，点当前日 → 重新展开。
    await tester.fling(find.byType(ListView), const Offset(0, 400), 800);
    await tester.pumpAndSettle();
    await tester.tap(find.text('${DateTime.now().day}').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('月视图展开'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('事件补录：presetDay 决定新建日程的日期（点17号不落到今天）', (tester) async {
    final preset = DateTime(2026, 3, 17);
    await tester.pumpWidget(ProviderScope(
      overrides: [eventRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () => showEventSheet(context, ref, presetDay: preset),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('新建日程'), findsOneWidget);
    expect(find.text('开始 09:00'), findsOneWidget); // 非今天 → 默认上午9点

    await tester.enterText(find.byType(TextField), '补录事项');
    await tester.tap(find.text('创建（预约）'));
    await tester.pumpAndSettle();

    final all = await repo.listAll();
    expect(all.single.start, DateTime(2026, 3, 17, 9));
    expect(all.single.end, DateTime(2026, 3, 17, 10));
  });
}
