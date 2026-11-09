import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'helpers.dart';
import 'package:lifeharness/features/calendar/domain/block_ops.dart';
import 'package:lifeharness/features/calendar/domain/time_block.dart';
import 'package:lifeharness/features/calendar/presentation/widgets/ts_cat_sheet.dart';

/// V1.57 C 批 · 时间账本分类明细下钻（原型 sheetTsCat/tsCatSegs）。
/// 硬验收：明细段数与合计 **必须等于** 汇总行「(N 次)」与时长（三处同源）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final from = DateTime(2026, 9, 14);
  final to = DateTime(2026, 9, 20);
  final now = DateTime(2026, 9, 16, 12);

  List<TimeBlock> seed() => [
        TimeBlock(
            id: 1,
            day: DateTime(2026, 9, 15),
            startMin: 540,
            endMin: 600,
            catName: '阅读',
            note: '第三章'),
        TimeBlock(
            id: 2,
            day: DateTime(2026, 9, 16),
            startMin: 600,
            endMin: 660,
            catName: '阅读'),
        TimeBlock(
            id: 3,
            day: DateTime(2026, 9, 14),
            startMin: 900,
            endMin: 990,
            catName: '工作',
            note: '评审'),
        // 窗外（上周日）同分类——不得入明细。
        TimeBlock(
            id: 4,
            day: DateTime(2026, 9, 13),
            startMin: 0,
            endMin: 30,
            catName: '阅读'),
        // 零时长块——不得计入（与汇总 cnt 的 mins<=0 skip 同口径）。
        TimeBlock(
            id: 5,
            day: DateTime(2026, 9, 17),
            startMin: 300,
            endMin: 300,
            catName: '阅读'),
      ];

  group('tsCatSegs 谓词与汇总同源', () {
    test('段数/合计 == 汇总行 (N 次)/byCat（剔除窗外与零时长）', () {
      final blocks = seed();
      final segs = tsCatSegs(blocks, '阅读', from, to, now);
      // 汇总口径复刻：dao listInRange 先按期滤块 → _aggregate（同源两段式）。
      final inRange = blocks.where((b) =>
          !DateTime(b.day.year, b.day.month, b.day.day).isBefore(from) &&
          !DateTime(b.day.year, b.day.month, b.day.day).isAfter(to)).toList();
      final sum = minutesByCat(inRange, now)['阅读'] ?? 0;
      final cnt = blocks
          .where((b) =>
              b.catName == '阅读' &&
              b.durationMin(now) > 0 &&
              !DateTime(b.day.year, b.day.month, b.day.day)
                  .isBefore(from) &&
              !DateTime(b.day.year, b.day.month, b.day.day).isAfter(to))
          .length;
      expect(segs.length, cnt);
      expect(segs.fold<int>(0, (t, x) => t + x.mins), sum);
      expect(segs.length, 2); // 9-15/9-16 两段
    });

    test('排序＝日升序·同日按起始升序；备注优先于分类名', () {
      final segs = tsCatSegs(seed(), '阅读', from, to, now);
      expect(segs.map((x) => x.day.day).toList(), [15, 16]);
      expect(segs.first.label, '第三章');
      expect(segs.last.label, '阅读'); // 无备注回落分类名
    });

    test('跨零点兜底：end>1440 拆两段且合计不变（DAO 钳制下正常不触发）', () {
      final b = TimeBlock(
          id: 9,
          day: DateTime(2026, 9, 15),
          startMin: 1380,
          endMin: 1500,
          catName: '观影');
      final segs = tsCatSegs([b], '观影', from, to, now);
      expect(segs.length, 2);
      expect(segs[0].mins, 60);
      expect(segs[0].cross, isFalse);
      expect(segs[1].mins, 60);
      expect(segs[1].cross, isTrue);
      expect(segs[1].day, DateTime(2026, 9, 16));
      expect(segs.fold<int>(0, (t, x) => t + x.mins), b.durationMin(now));
    });
  });

  group('半屏 UI', () {
    Future<void> open(WidgetTester tester,
        {List<TimeBlock>? blocks, String cat = '阅读'}) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => showTsCatSheet(ctx,
                      blocks: blocks ?? seed(),
                      cat: cat,
                      from: from,
                      to: to,
                      spanDays: 7,
                      periodText: '本周 · 9.14-9.20',
                      color: const Color(0xFF0EA5E9)),
                  child: const Text('open'),
                ),
              )),
        ),
      ));
      await tester.tap(find.text('open'));
      await settle5(tester);
    }

    testWidgets('三格+逐段列表：段数/合计/日均与行内起止·时长', (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('ts-cat-sheet')), findsOneWidget);
      expect(find.text('本周 · 9.14-9.20'), findsOneWidget);
      expect(find.text('段数'), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // 段数=2（与汇总 (N 次) 同源）
      expect(find.text('合计'), findsOneWidget);
      expect(find.text('2 时'), findsOneWidget); // 60+60 分=合计（=汇总时长）
      expect(find.text('日均'), findsOneWidget);
      expect(find.text('17 分'), findsOneWidget); // 120÷7 天
      expect(find.textContaining('第三章'), findsOneWidget);
      expect(find.text('09:00–10:00'), findsOneWidget);
      expect(find.text('10:00–11:00'), findsOneWidget);
      expect(find.text('1 时'), findsNWidgets(2)); // 两段行内时长
      expect(find.textContaining('明细列表（模拟）'), findsNothing);
      await tester.tap(find.text('收起'));
      await settle5(tester);
      expect(find.byKey(const ValueKey('ts-cat-sheet')), findsNothing);
    });

    testWidgets('空态文案逐字', (tester) async {
      await open(tester, cat: '健身');
      expect(find.text('该时段没有此分类的时间块'), findsOneWidget);
      expect(find.text('0'), findsOneWidget); // 段数=0
    });

    testWidgets('去时间页＝关弹层并回 /calendar tab', (tester) async {
      final navKey = GlobalKey<NavigatorState>();
      await tester.binding.setSurfaceSize(const Size(420, 900));
      final router = GoRouter(
        navigatorKey: navKey,
        initialLocation: '/time-stats',
        routes: [
          GoRoute(
              path: '/calendar',
              builder: (_, _) => const Scaffold(body: Text('CALENDAR-TAB'))),
          GoRoute(
              path: '/time-stats',
              builder: (ctx, _) => Scaffold(
                    body: Builder(builder: (c) => Center(
                          child: ElevatedButton(
                            onPressed: () => showTsCatSheet(c,
                                blocks: seed(),
                                cat: '阅读',
                                from: from,
                                to: to,
                                spanDays: 7,
                                periodText: '本周 · 9.14-9.20',
                                color: const Color(0xFF0EA5E9)),
                            child: const Text('open'),
                          ),
                        ))),
              ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.tap(find.text('open'));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('ts-cat-goto')));
      await settle5(tester);
      expect(find.byKey(const ValueKey('ts-cat-sheet')), findsNothing);
      expect(find.text('CALENDAR-TAB'), findsOneWidget);
      await drainLogTimer(tester);
    });
  });
}
