import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema/core.dart' as core;
import 'package:lifeharness/core/database/schema/media.dart' as md;
import 'package:lifeharness/features/media/data/media_repo_session.dart';
import 'package:lifeharness/features/media/data/media_repository.dart';
import 'package:lifeharness/features/media/domain/media_item.dart';
import 'package:lifeharness/features/media/domain/media_session.dart';
import 'package:lifeharness/features/media/domain/media_stats.dart';
import 'package:lifeharness/features/media/presentation/media_providers.dart';
import 'package:lifeharness/features/media/presentation/media_routes.dart';
import 'package:lifeharness/features/media/presentation/widgets/media_card.dart';
import 'package:lifeharness/shared/widgets/ui_kit.dart';

import 'helpers.dart';

/// 影音游批7 · 全站统计屏（原型 `m-stat` · 词典 LH-C21 · 路由 `/media/stat`）。
///
/// 钉死屏上五件事：口径 chip 就是 `media.speedFold`（切换即写回、重进屏仍从设置读回）；
/// 八块读数随口径／度量／构成／年月同源重算；近 30 天恒 30 格且强度在屏上真分得出档；
/// 没记录一律虚线或「—」；目标未设＝只出「未设目标」＋入口，**该块内不许出现百分比**。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late MediaRepository repo;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 21, 30);
  DateTime day(int back, {int hour = 21}) =>
      DateTime(today.year, today.month, today.day, hour).subtract(Duration(days: back));

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in md.mediaSchemaStatements) {
      await db.execute(sql);
    }
    await db.execute(
      'CREATE TABLE IF NOT EXISTS ${core.tSettings} (key TEXT PRIMARY KEY, value TEXT)',
    );
    repo = MediaRepository(db);
  });
  tearDown(() => db.close());

  Future<MediaItem> addItem(String title,
      {String kind = MediaItem.kMovie, double myRating = 0, int durationMin = 0}) async {
    final x = MediaItem(
      id: 'x_$title',
      kind: kind,
      title: title,
      state: '在看',
      progressWay: MediaItem.kWayPct,
      durationMin: durationMin,
      myRating: myRating,
      createdAt: 1,
      updatedAt: 1,
    );
    await repo.addItem(x);
    return x;
  }

  Future<void> addSession(MediaItem x, DateTime start, int minutes, {double? speed}) =>
      db.insert(
        md.tMediaSessions,
        MediaSession(
          itemId: x.id,
          kind: x.kind,
          startedAt: start.millisecondsSinceEpoch,
          endedAt: start.add(Duration(minutes: minutes)).millisecondsSinceEpoch,
          minutes: minutes,
          speed: speed,
        ).toRow(),
      );

  Future<GoRouter> pumpStat(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [mediaRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/root',
      routes: [
        GoRoute(path: '/root', builder: (_, _) => const Scaffold(body: SizedBox.shrink())),
        ...mediaPageRoutes(),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle5(tester);
    router.push('/media/stat');
    await settle5(tester);
    return router;
  }

  String heatKey(DateTime d) =>
      'mds-stat-heat-${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 格子主色挂在 GestureDetector 的 child Container 上（key 在热区、色在画层），
  /// 直接 byKey 取到的是热区件，必须按后代取。
  Container heatCell(WidgetTester tester, DateTime d) => tester.widget<Container>(find.descendant(
      of: find.byKey(ValueKey(heatKey(d))), matching: find.byType(Container)));

  double cellAlpha(WidgetTester tester, DateTime d) {
    final color = (heatCell(tester, d).decoration as BoxDecoration).color;
    return color == null ? 0 : color.a;
  }

  bool chipOn(WidgetTester tester, String key) =>
      tester.widget<PillChip>(find.byKey(ValueKey(key))).selected;

  testWidgets('首屏＝口径 chip＋四行筛选＋八块读数在场；默认选中真实时长；目标块内零百分比', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    final x = await addItem('在场片', myRating: 8);
    await addSession(x, day(1), 60);
    await pumpStat(tester);

    for (final k in [
      'mds-stat-fold',
      'mds-stat-drill',
      'mds-stat-heat',
      'mds-stat-trend',
      'mds-stat-kinds',
      'mds-stat-hours',
      'mds-stat-rating',
      'mds-stat-goal',
      'mds-stat-totals',
    ]) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: '统计屏缺块 $k');
    }
    expect(find.text('近 $kMdsHeatDays 天 · 时长热力 · 真实'), findsOneWidget);
    expect(chipOn(tester, 'mds-stat-fold-real'), isTrue);
    expect(chipOn(tester, 'mds-stat-fold-fold'), isFalse);
    expect(find.text('总计 1h'), findsOneWidget, reason: '60 分钟＝1h，读数现算');
    expect(find.text('未设目标'), findsOneWidget);
    expect(
      find.descendant(
          of: find.byKey(const ValueKey('mds-stat-goal')),
          matching: find.textContaining('%')),
      findsNothing,
      reason: '目标没设＝这块不许出现任何百分比（构成条的百分比在另一张卡里）',
    );
  });

  testWidgets('切「折算时长」＝写 media.speedFold 并按倍速重算，重进屏仍在折算档', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    final x = await addItem('倍速片');
    await addSession(x, day(1), 40, speed: 1.5);
    await addSession(x, day(2), 30);
    final router = await pumpStat(tester);

    expect(find.text('总计 1h 10m'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mds-stat-fold-fold')));
    await settle5(tester);
    expect(find.text('总计 1h 30m'), findsOneWidget, reason: '40×1.5＋30＝90 分钟，当场重算');
    expect(find.text('近 $kMdsHeatDays 天 · 时长热力 · 折算'), findsOneWidget);
    expect(await repo.kv('media.speedFold'), 'true', reason: 'chip 就是设置项的可见表达＝必须落库');

    router.pop();
    await settle5(tester);
    router.push('/media/stat');
    await settle5(tester);
    expect(chipOn(tester, 'mds-stat-fold-fold'), isTrue,
        reason: '重进屏＝从设置读回，不是页面内存态');
    expect(find.text('总计 1h 30m'), findsOneWidget);
  });

  testWidgets('构成筛选＝构成只剩一行·总时长只剩该类＋总计', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    final m = await addItem('构成电影');
    final s = await addItem('构成剧集', kind: MediaItem.kSeries);
    await addSession(m, day(1), 100);
    await addSession(s, day(2), 100);
    await pumpStat(tester);

    expect(find.byKey(const ValueKey('mds-stat-kind-row-movie')), findsOneWidget);
    expect(find.byKey(const ValueKey('mds-stat-kind-row-series')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mds-stat-kind-movie')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('mds-stat-kind-row-series')), findsNothing);
    expect(find.byKey(const ValueKey('mds-stat-total-series')), findsNothing);
    expect(find.byKey(const ValueKey('mds-stat-total-movie')), findsOneWidget);
    expect(find.byKey(const ValueKey('mds-stat-total-all')), findsOneWidget);
  });

  testWidgets('度量三档各换纵轴语义（时长→次数→平均评分）', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    final m = await addItem('度量电影', myRating: 8);
    final s = await addItem('度量剧集', kind: MediaItem.kSeries, myRating: 10);
    await addSession(m, day(1), 100);
    await addSession(s, day(2), 100);
    await addSession(s, day(3), 100);
    await pumpStat(tester);

    expect(tester.widget<Text>(find.byKey(const ValueKey('mds-stat-kind-val-series'))).data,
        contains('3h 20m'));
    await tester.tap(find.byKey(const ValueKey('mds-stat-metric-cnt')));
    await settle5(tester);
    expect(tester.widget<Text>(find.byKey(const ValueKey('mds-stat-kind-val-series'))).data,
        contains('2 次'));
    expect(find.text('近 $kMdsHeatDays 天 · 次数热力 · 真实'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mds-stat-metric-rate')));
    await settle5(tester);
    expect(tester.widget<Text>(find.byKey(const ValueKey('mds-stat-kind-val-series'))).data,
        contains('10.0'), reason: '评分档＝按条目取均值，不吃分钟');
    expect(tester.widget<Text>(find.byKey(const ValueKey('mds-stat-rating-avg'))).data, '9.0');
  });

  testWidgets('点热力格＝出当日读数行，再点收起；没记录那格出「没记录」', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    final m = await addItem('读数电影');
    final s = await addItem('读数剧集', kind: MediaItem.kSeries);
    await addSession(m, day(1), 60);
    await addSession(s, day(1), 30);
    await pumpStat(tester);

    expect(find.byKey(const ValueKey('mds-stat-dayread')), findsNothing);
    await tester.tap(find.byKey(ValueKey(heatKey(day(1)))));
    await settle5(tester);
    expect(find.byKey(const ValueKey('mds-stat-dayread')), findsOneWidget);
    // 读数行按 kind 各一枚（总时长 chips 在另一张卡里＝同名文案会撞，断言取带 key 的那枚）
    expect(tester.widget<Text>(find.byKey(const ValueKey('mds-stat-dayread-movie'))).data,
        '观影 1h');
    expect(tester.widget<Text>(find.byKey(const ValueKey('mds-stat-dayread-series'))).data,
        '追剧 30m');
    expect(find.text('2 条'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey(heatKey(day(1)))));
    await settle5(tester);
    expect(find.byKey(const ValueKey('mds-stat-dayread')), findsNothing, reason: '同格再点＝收起');

    await tester.tap(find.byKey(ValueKey(heatKey(day(9)))));
    await settle5(tester);
    expect(
      find.descendant(
          of: find.byKey(const ValueKey('mds-stat-dayread')),
          matching: find.textContaining('没记录')),
      findsOneWidget,
      reason: '空档日点开＝如实说没记录，不摆 0m',
    );
  });

  testWidgets('强度分档在屏上真分得出档（刀3 靶点：摘掉分档＝三格同色会红）', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    final x = await addItem('分档片', durationMin: 600);
    await addSession(x, day(2), 10);
    await addSession(x, day(3), 60);
    await addSession(x, day(4), 120);
    await addSession(x, day(5), 300);
    await pumpStat(tester);

    final a1 = cellAlpha(tester, day(2));
    final a2 = cellAlpha(tester, day(3));
    final a3 = cellAlpha(tester, day(4));
    expect(a1, greaterThan(0));
    expect(a2, greaterThan(a1), reason: '值跨过分位数＝格子必须更实');
    expect(a3, greaterThan(a2));
    expect(cellAlpha(tester, day(5)), a3, reason: '顶档并列＝同一档同色（不是连续色阶）');
    expect(cellAlpha(tester, day(9)), 0, reason: '没记录那天不涂色');
  });

  testWidgets('空库＝三块各走虚线空态，不拿 0 冒充读数', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    await pumpStat(tester);
    expect(find.text('这个窗口没有记录'), findsOneWidget);
    expect(find.text('这个窗口没有评分记录'), findsOneWidget);
    expect(find.text('未设目标'), findsOneWidget);
    expect(find.text('总计 —'), findsOneWidget);
  });

  testWidgets('年 chips 来自实际数据；选年后趋势标题·月柱·总账跟着换', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    final x = await addItem('去年片');
    await addSession(x, day(1), 60);
    await addSession(x, day(400), 45);
    await pumpStat(tester);

    final lastYear = day(400).year;
    expect(find.byKey(ValueKey('mds-stat-year-$lastYear')), findsOneWidget);
    expect(find.text('按年趋势 · 时长 · 真实'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('mds-stat-year-$lastYear')));
    await settle5(tester);
    expect(find.text('$lastYear 年趋势 · 时长 · 真实'), findsOneWidget);
    expect(find.byKey(const ValueKey('mds-stat-trend-12')), findsOneWidget,
        reason: '选定年份＝12 根月柱在场');
    expect(find.text('总计 45m'), findsOneWidget, reason: '窗口收进去年＝只算那年的账');
  });

  testWidgets('格子颜色＝四类扁平主色（微拟物材质渐变不许回流）', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    final m = await addItem('色卡电影');
    await addSession(m, day(1), 60);
    await pumpStat(tester);
    final painted = (heatCell(tester, day(1)).decoration as BoxDecoration).color!;
    expect(painted.toARGB32() & 0x00FFFFFF, mdsKindColor(MediaItem.kMovie).toARGB32() & 0x00FFFFFF,
        reason: '格底＝该 kind 的扁平主色，只叠透明度，不换成渐变材质');
  });
}
