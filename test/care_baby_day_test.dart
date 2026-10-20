import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/care/data/care_repository.dart';
import 'package:lifeharness/features/care/domain/care_models.dart';
import 'package:lifeharness/features/care/presentation/baby_day_page.dart';
import 'package:lifeharness/features/care/presentation/care_page.dart';
import 'package:lifeharness/features/care/presentation/care_providers.dart';

/// 呵护批4 · p-babyDay 全天记录 / sheetDayFilter / hero 数据位入口用例。
/// 独立文件防 isolate 污染；每例临时内存库 + close 释放。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late CareRepository repo;
  late ProviderContainer container;
  late int babyId;

  // T19 收口：固定时间源——日期取真实今天、时刻钉死 15:30。
  // 播种与页面徽章/日分组重算全部走同一 instant（careClockProvider override），
  // 根治旧写法 DateTime.now()-5min 与墙钟重算跨分钟/跨日界的抖动 flake。
  final wallNow = DateTime.now();
  final fixedNow =
      DateTime(wallNow.year, wallNow.month, wallNow.day, 15, 30);

  String key0(DateTime d) => careDayKey(d);
  String hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = CareRepository(db);
    babyId = await repo.addBaby(
        name: '团子', sex: '女', birth: '2026-01-07', color: 'sky');
  });

  tearDown(() async {
    await db.close();
    container.dispose();
  });

  Future<void> add(CareRecord r) => repo.addLog(
      CareRecord.fromRow(r.toRow()..['baby_id'] = babyId));

  /// 三条跨日样本（时刻全部相对 fixedNow 钉死）：
  /// 今天瓶喂（15:25 始 · 15:30 止 → 徽章恒为「5分钟前」）+ 今天尿布 07:40（远离徽章窗口），
  /// 昨天配方奶。
  Future<void> seedStandard() async {
    final s = fixedNow.subtract(const Duration(minutes: 5));
    await add(CareRecord(
        babyId: 0,
        day: key0(fixedNow),
        k: 'bmilk',
        s: hhmm(s),
        e: hhmm(fixedNow),
        dur: 5,
        ml: 150,
        rec: '妈妈'));
    await add(CareRecord(
        babyId: 0,
        day: key0(fixedNow),
        k: 'diaper',
        s: '07:40',
        dia: 'pee',
        rec: '爸爸'));
    await add(CareRecord(
        babyId: 0,
        day: key0(fixedNow.subtract(const Duration(days: 1))),
        k: 'formula',
        s: '21:00',
        e: '21:10',
        dur: 10,
        ml: 180,
        rec: '妈妈'));
  }

  Future<void> pumpRoot(WidgetTester tester) async {
    container = ProviderContainer(
      overrides: [
        careRepositoryProvider.overrideWithValue(repo),
        careClockProvider.overrideWithValue(() => fixedNow),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/x',
            routes: [
              GoRoute(path: '/x', builder: (_, _) => const CarePage()),
              GoRoute(
                  path: '/care/day',
                  builder: (_, _) => const CareBabyDayPage()),
              GoRoute(
                  path: '/care/stats',
                  builder: (_, _) =>
                      const Scaffold(body: Center(child: Text('汇总-STUB')))),
            ],
          ),
        ),
      ),
    );
    await settle5(tester);
    if (container.read(careViewProvider) == 'cycle') {
      await tester.tap(find.byKey(const ValueKey('care-swap')));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> openDay(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('today-to-day')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
  }

  Future<void> tapK(WidgetTester tester, Key key) async {
    Finder f = find.byKey(key);
    if (f.evaluate().length > 1) f = f.first;
    await tester.ensureVisible(f);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(f);
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('今日卡「全天时间线」入口 + 日分组/汇总行/内容串/分钟前徽章',
      (tester) async {
    await useSurface(tester, const Size(800, 2800));
    await seedStandard();
    await pumpRoot(tester);
    await openDay(tester);
    expect(find.byKey(const ValueKey('bd-range')), findsOneWidget);
    expect(find.text('近 2 天 · 3 条记录'), findsOneWidget);
    // 今天/昨天分组标题（日期均相对今天，标题走 今天/昨天）
    expect(find.text('今天'), findsWidgets);
    expect(find.text('昨天'), findsWidgets);
    // 日汇总行（今天：瓶喂母乳 1次 150ml + 换尿布 1次）
    expect(find.text('瓶喂母乳 1次 150ml'), findsOneWidget);
    expect(find.text('换尿布 1次'), findsOneWidget);
    // 内容串由数据生成（红线 6）：尿布=嘘嘘；配方奶=180ml + 起止区间
    expect(find.text('嘘嘘'), findsOneWidget);
    expect(find.text('180ml'), findsOneWidget);
    expect(find.text('21:00-21:10'), findsOneWidget);
    // 「N分钟前」徽章：固定钟 15:30 − 播种 15:25 → 恒为「5分钟前」，
    // 且全页仅此一枚（尿布 07:40 在 60min 窗口外，配方奶属昨日）。
    expect(find.text('4分钟前'), findsNothing);
    expect(find.text('5分钟前'), findsOneWidget);
    // 无筛选时标签=全部
    expect(find.textContaining('全部'), findsOneWidget);
  });

  testWidgets('sheetDayFilter：多选→已选 N 项；不筛选回落全部', (tester) async {
    await useSurface(tester, const Size(800, 2800));
    await seedStandard();
    await pumpRoot(tester);
    await openDay(tester);
    await tapK(tester, const ValueKey('bd-filter'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    await tapK(tester, const ValueKey('bdf-diaper'));
    await tester.pump();
    await tapK(tester, const ValueKey('bdf-sleep'));
    await tester.pump();
    await tapK(tester, const ValueKey('bdf-ok'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    expect(find.textContaining('已选 2 项'), findsOneWidget);
    // 只剩尿布行（瓶喂/配方奶行隐藏）
    expect(find.text('嘘嘘'), findsOneWidget);
    expect(find.text('180ml'), findsNothing);
    expect(find.text('昨天'), findsNothing);
    // 不筛选回落
    await tapK(tester, const ValueKey('bd-filter'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    await tapK(tester, const ValueKey('bdf-clear'));
    await tapK(tester, const ValueKey('bdf-ok'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    expect(find.textContaining('全部'), findsOneWidget);
    expect(find.text('180ml'), findsOneWidget);
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('hero 数据位「喂养」→ 预置筛选进入全天记录', (tester) async {
    await useSurface(tester, const Size(800, 2800));
    await seedStandard();
    await pumpRoot(tester);
    await tapK(tester, const ValueKey('hero-feed'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    expect(find.textContaining('已选 6 项'), findsOneWidget);
    expect(find.text('嘘嘘'), findsNothing); // 尿布不在喂养组
    expect(find.text('150ml'), findsOneWidget);
    expect(find.text('180ml'), findsOneWidget);
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('快速记录宫格（sheetEvPanel）→ 选事件开录入弹层', (tester) async {
    await useSurface(tester, const Size(800, 2800));
    await seedStandard();
    await pumpRoot(tester);
    await openDay(tester);
    await tapK(tester, const ValueKey('bd-quick'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    expect(find.text('快速记录'), findsOneWidget);
    expect(find.text('回宝宝页 · 管理事件顺序 ›'), findsOneWidget);
    await tapK(tester, const ValueKey('evp-water'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    expect(find.text('喝水'), findsWidgets); // 录入弹层标题=E事件名
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('行点按→二次编辑弹层；喂养分析钮走路由', (tester) async {
    await useSurface(tester, const Size(800, 2800));
    await seedStandard();
    await pumpRoot(tester);
    await openDay(tester);
    final d0 = await repo.loadAll();
    final formula = d0.logs.firstWhere((r) => r.k == 'formula');
    await tapK(tester, ValueKey('day-rec-${formula.id}'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    expect(find.text('配方奶 · 二次修改'), findsOneWidget);
    // 点顶部遮罩收起弹层（禁 pageBack：模态屏障吞命中）
    await tester.tapAt(const Offset(400, 30));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    expect(find.text('配方奶 · 二次修改'), findsNothing);
    await tapK(tester, const ValueKey('bd-stats'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    expect(find.text('汇总-STUB'), findsOneWidget);
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });

  testWidgets('筛选后无命中日 → 空态文案', (tester) async {
    await useSurface(tester, const Size(800, 2800));
    await seedStandard();
    await pumpRoot(tester);
    await openDay(tester);
    container.read(careDayFilterProvider.notifier).state = const {'swim'};
    await tester.pump();
    expect(find.text('暂无该类型记录'), findsOneWidget);
    expect(find.text('今天'), findsNothing);
    await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
  });
}
