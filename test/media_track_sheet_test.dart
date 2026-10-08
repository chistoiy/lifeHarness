import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema/core.dart' as core;
import 'package:lifeharness/core/database/schema/media.dart' as md;
import 'package:lifeharness/features/media/data/media_repository.dart';
import 'package:lifeharness/features/media/domain/media_item.dart';
import 'package:lifeharness/features/media/domain/media_session.dart';
import 'package:lifeharness/features/media/domain/media_stats.dart';
import 'package:lifeharness/features/media/presentation/media_providers.dart';
import 'package:lifeharness/features/media/presentation/media_routes.dart';

import 'helpers.dart';

/// 影音游批7 · 单条目轨迹半屏弹层（原型 `m-sheet-track` · 词典 LH-S37）。
///
/// 四条判定（工单 §⚙ 面板第 3 项）：逐次柱只留最近 [kMdsTrackCols] 根且柱高/副行恒吃
/// **真实耗时**；倍速 >1 才出柱顶角标；里程碑**只列已达成**（刀2 靶点＝摘掉达成判定会红）；
/// 改与删一律跳计时明细整屏，本面不铺编辑态；空条目走虚线一行、不拿 0 冒充读数。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late MediaRepository repo;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 21, 30);
  DateTime day(int back, {int hour = 21}) =>
      DateTime(today.year, today.month, today.day, hour).subtract(Duration(days: back));
  String pad(int v) => v.toString().padLeft(2, '0');
  String ymd(DateTime d) => '${d.year}-${pad(d.month)}-${pad(d.day)}';

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in md.mediaSchemaStatements) {
      await db.execute(sql);
    }
    await db.execute(
      'CREATE TABLE IF NOT EXISTS ${core.tSettings} (key TEXT PRIMARY KEY, value TEXT)',
    );
    // 轨迹的「计时明细」去路会读账本表；跳过去得让它建得起来
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${core.tTimeBlocks} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        day INTEGER NOT NULL,
        start_min INTEGER NOT NULL,
        end_min INTEGER NOT NULL,
        category TEXT NOT NULL DEFAULT '其他',
        note TEXT,
        source TEXT NOT NULL DEFAULT 'mark',
        event_id INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        cat_id INTEGER
      )
    ''');
    repo = MediaRepository(db);
  });
  tearDown(() => db.close());

  Future<String> addItem(
    String title, {
    String kind = MediaItem.kMovie,
    int durationMin = 0,
    bool completed = false,
    int? endedAt,
  }) =>
      repo.addItem(MediaItem(
        kind: kind,
        title: title,
        state: completed ? '看完' : '在看',
        progressWay: kind == MediaItem.kMovie ? MediaItem.kWayPct : MediaItem.kWayMainPct,
        durationMin: durationMin,
        completed: completed,
        endedAt: endedAt,
        createdAt: 1,
        updatedAt: 1,
      ));

  /// 落一条已结算会话，返回自增 id（逐次柱/角标 key 都按它拼）。
  Future<int> addSession(
    String itemId,
    String kind,
    DateTime start,
    int minutes, {
    double? speed,
  }) =>
      db.insert(
        md.tMediaSessions,
        MediaSession(
          itemId: itemId,
          kind: kind,
          startedAt: start.millisecondsSinceEpoch,
          endedAt: start.add(Duration(minutes: minutes)).millisecondsSinceEpoch,
          minutes: minutes,
          speed: speed,
        ).toRow(),
      );

  Finder colOf(String prefix) => find.byWidgetPredicate((w) =>
      w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith(prefix));
  final colFinder = colOf('mds-track-col-');
  // 里程碑行 key＝mds-track-mile-<label>，段头 key 以 -head 结尾要摘掉
  final mileFinder = find.byWidgetPredicate((w) {
    final k = w.key;
    return k is ValueKey<String> &&
        k.value.startsWith('mds-track-mile-') &&
        !k.value.endsWith('-head');
  });

  /// 经详情页动作条真入口起弹层（回灌成句：「轨迹」钮与「条目资料」同排）。
  Future<GoRouter> pumpDetail(WidgetTester tester, String id) async {
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
    router.push('/media/item/$id');
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('mds-detail-track')));
    await settle5(tester);
    return router;
  }

  Text sub(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('mds-track-sub')));

  testWidgets('详情「轨迹」钮＝就地起半屏只读面；副行「N 次 · 真实 …」与柱数现算', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    final id = await addItem('轨迹片', durationMin: 200);
    final t = <int>[
      await addSession(id, MediaItem.kMovie, day(5), 30),
      await addSession(id, MediaItem.kMovie, day(4), 40),
      await addSession(id, MediaItem.kMovie, day(3), 30),
    ];
    await pumpDetail(tester, id);

    expect(find.text('条目轨迹'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('mds-track-title'))).data, '轨迹片');
    expect(sub(tester).data, '${t.length} 次 · 真实 ${mdsHm(100)}',
        reason: '副行＝条数＋真实耗时合计（30+40+30＝100 分钟）');
    expect(colFinder, findsNWidgets(3));
    for (final sid in t) {
      expect(find.byKey(ValueKey('mds-track-col-$sid')), findsOneWidget);
    }
  });

  testWidgets('逐次柱只留最近 14 根；柱高与副行恒吃真实耗时，倍速 >1 才出柱顶角标', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    final id = await addItem('长剧列', durationMin: 600);
    final ids = <int, int>{}; // day → session id
    for (var d = 16; d >= 1; d--) {
      ids[d] = await addSession(id, MediaItem.kMovie, day(d), 10, speed: d == 1 ? 2.0 : null);
    }
    await pumpDetail(tester, id);

    expect(colFinder, findsNWidgets(kMdsTrackCols), reason: '16 条只画最近 14 根');
    expect(find.byKey(ValueKey('mds-track-col-${ids[16]}')), findsNothing);
    expect(find.byKey(ValueKey('mds-track-col-${ids[15]}')), findsNothing);
    expect(find.byKey(ValueKey('mds-track-col-${ids[14]}')), findsOneWidget);
    expect(sub(tester).data, '16 次 · 真实 2h 40m',
        reason: '16×10＝160 分钟；折算（2x 那条算 20）＝2h 50m＝不许出现在轨迹面');
    expect(tester.widget<Text>(find.byKey(ValueKey('mds-track-spd-${ids[1]}'))).data, '2x');
    expect(tester.widget<Text>(find.byKey(ValueKey('mds-track-spd-${ids[2]}'))).data, '',
        reason: '没倍速＝角标位空着，不重复报同一个 1x');
  });

  testWidgets('里程碑只列已达成：片长没过半／没标记看完＝整行不出现（刀2 靶点）', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    final id = await addItem('半程不够', durationMin: 200);
    await addSession(id, MediaItem.kMovie, day(5), 60);
    await pumpDetail(tester, id);

    expect(mileFinder, findsNWidgets(1), reason: '只出「开始观影」，其余算不出＝整行不铺');
    expect(find.byKey(const ValueKey('mds-track-mile-开始观影')), findsOneWidget);
    expect(find.byKey(const ValueKey('mds-track-mile-看过一半')), findsNothing,
        reason: '60 < 200/2＝过半没达成，不摆「未达成」占位');
    expect(find.byKey(const ValueKey('mds-track-mile-看完')), findsNothing,
        reason: 'completed=false＝不编完结日期');
  });

  testWidgets('里程碑三档齐＝开始／看过一半／看完各一行，日期一律取真料', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    final id = await addItem('三档齐', durationMin: 200, completed: true, endedAt: day(1).millisecondsSinceEpoch);
    await addSession(id, MediaItem.kMovie, day(9), 40); // 开始＝这天
    await addSession(id, MediaItem.kMovie, day(6), 40);
    await addSession(id, MediaItem.kMovie, day(3), 40); // 累计 120 ≥ 100＝过半这天
    await pumpDetail(tester, id);

    expect(mileFinder, findsNWidgets(3));
    expect(find.byKey(const ValueKey('mds-track-mile-开始观影')), findsOneWidget);
    expect(find.byKey(const ValueKey('mds-track-mile-看过一半')), findsOneWidget);
    expect(find.byKey(const ValueKey('mds-track-mile-看完')), findsOneWidget);
    // 日期现算：开始＝最早会话日，过半＝跨过半那条的会话日，完结＝条目 ended_at
    expect(find.text(ymd(day(9))), findsOneWidget);
    expect(find.text(ymd(day(3))), findsOneWidget);
    expect(find.text(ymd(day(1))), findsOneWidget);
  });

  testWidgets('时段五档恒在场；有账那档报真实分钟，没账那档出「—」不拿 0 凑', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    final id = await addItem('时段片');
    await addSession(id, MediaItem.kMovie, day(3, hour: 21), 30);
    await addSession(id, MediaItem.kMovie, day(2, hour: 8), 45);
    await pumpDetail(tester, id);

    for (final (k, _, _, _) in kMdsHours) {
      expect(find.byKey(ValueKey('mds-track-hour-$k')), findsOneWidget, reason: '五档缺一＝$k');
    }
    expect(
      find.descendant(
          of: find.byKey(const ValueKey('mds-track-hour-night')), matching: find.text('30m')),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: find.byKey(const ValueKey('mds-track-hour-am')), matching: find.text('45m')),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: find.byKey(const ValueKey('mds-track-hour-dawn')), matching: find.text('—')),
      findsOneWidget,
    );
  });

  testWidgets('明细入口＝收起弹层跳计时明细整屏（改与删只在整屏，批4 拍板①）', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    final id = await addItem('去明细节', durationMin: 100);
    await addSession(id, MediaItem.kMovie, day(2), 30);
    await pumpDetail(tester, id);

    final log = find.byKey(const ValueKey('mds-track-sesslog'));
    await tester.ensureVisible(log);
    await tester.tap(log);
    await settle5(tester);
    expect(find.byKey(const ValueKey('mds-track-title')), findsNothing, reason: '跳走前收起弹层');
    expect(find.text('计时明细'), findsOneWidget, reason: '落点＝计时明细整屏');
    expect(find.byKey(const ValueKey('mds-sess-add')), findsOneWidget);
  });

  testWidgets('空条目＝虚线一行不拿 0 冒充读数，柱/里程碑/明细入口整段不铺', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    final id = await addItem('没账片', durationMin: 100);
    await pumpDetail(tester, id);

    expect(find.textContaining('还没有计时记录'), findsOneWidget);
    expect(colFinder, findsNothing);
    expect(find.byKey(const ValueKey('mds-track-mile-head')), findsNothing);
    expect(find.byKey(const ValueKey('mds-track-sesslog')), findsNothing,
        reason: '没账＝这条去路先不铺，避免空屏套空屏');
    expect(find.byKey(const ValueKey('mds-track-bars')), findsNothing);
  });

  testWidgets('LH-S34「影音轨迹」行＝从「更多」动作面进同一面', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    final id = await addItem('走更多面', durationMin: 100);
    await addSession(id, MediaItem.kMovie, day(2), 30);

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
    router.push('/media/item/$id');
    await settle5(tester);

    await tester.tap(find.byKey(const ValueKey('mds-detail-ops')));
    await settle5(tester);
    await tester.tap(find.text('条目操作'));
    await settle5(tester);
    final row = find.byKey(const ValueKey('mds-ops-影音轨迹'));
    expect(row, findsOneWidget);
    await tester.ensureVisible(row);
    await tester.tap(row);
    await settle5(tester);
    expect(find.text('条目轨迹'), findsOneWidget, reason: '与详情动作条同一面＝一套渲染不两式');
    expect(find.byKey(const ValueKey('mds-track-title')).evaluate().isNotEmpty, isTrue);
  });
}
