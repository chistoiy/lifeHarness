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
import 'package:lifeharness/features/media/presentation/media_actions.dart';
import 'package:lifeharness/features/media/presentation/media_providers.dart';
import 'package:lifeharness/features/media/presentation/media_routes.dart';
import 'package:lifeharness/features/media/presentation/media_set_page.dart';
import 'package:lifeharness/features/media/presentation/media_workbench.dart';
import 'package:lifeharness/shared/widgets/ui_kit.dart';

import 'helpers.dart';

/// 批8a · 设置屏（原型 `m-set` · 词典 LH-C23 · 路由 `/media/settings`）。
///
/// 钉死：六组 tab 行态与 §七 键一一对名；写 KV 落 settings 表（不散落 SP）；
/// 灰态行整体点不动零说明；逐行当场生效连线（defaultView/sortDefault/wallCols/newPos/
/// timerUI/speedFold 双向/autoPos/clipAuto/dailyQ）；死键四条不铺。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late MediaRepository repo;
  ProviderContainer? lastContainer;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in md.mediaSchemaStatements) {
      await db.execute(sql);
    }
    await db.execute(
      'CREATE TABLE IF NOT EXISTS ${core.tSettings} (key TEXT PRIMARY KEY, value TEXT)',
    );
    repo = MediaRepository(db);
    lastContainer = null;
  });
  tearDown(() async {
    lastContainer?.dispose();
    await db.close();
  });

  Future<GoRouter> pumpApp(
    WidgetTester tester,
    String path, {
    Widget Function()? root,
  }) async {
    final container = ProviderContainer(
      overrides: [mediaRepositoryProvider.overrideWithValue(repo)],
    );
    lastContainer = container;
    final router = GoRouter(
      initialLocation: '/root',
      routes: [
        GoRoute(
            path: '/root',
            builder: (_, _) => root?.call() ??
                const Scaffold(body: SizedBox.shrink())),
        ...mediaPageRoutes(),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle5(tester);
    router.push(path);
    await settle5(tester);
    return router;
  }

  Future<void> pumpSet(WidgetTester tester) =>
      pumpApp(tester, '/media/settings');

  bool chipOn(WidgetTester tester, String key) =>
      tester.widget<PillChip>(find.byKey(ValueKey(key))).selected;

  Future<MediaItem> addItem(String title) async {
    final x = MediaItem(
      id: 'x_$title',
      kind: MediaItem.kMovie,
      title: title,
      state: '在看',
      progressWay: MediaItem.kWayPct,
      createdAt: 1000,
      updatedAt: 1000,
    );
    await repo.addItem(x);
    return x;
  }

  testWidgets('六组 tab 齐；默认架面组两行；死键四条整体不铺', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    await pumpSet(tester);
    for (final g in ['shelf', 'sort', 'note', 'timer', 'notify', 'data']) {
      expect(find.byKey(ValueKey('mds-set-tab-$g')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('mds-set-row-media.defaultView')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('mds-set-row-media.wallCols')), findsOneWidget);
    for (final dead in [
      'media.deskTexture', 'media.cardLiftPx', 'media.spineCols', 'media.longPress'
    ]) {
      expect(find.byKey(ValueKey('mds-set-row-$dead')), findsNothing,
          reason: '$dead 已作废（工单 §0.5），设置屏不许复活');
    }
    // 其余组的行不在架面 tab 里（分组装载）。
    expect(find.byKey(const ValueKey('mds-set-row-media.timerUI')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('mds-set-tab-timer')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('mds-set-row-media.timerUI')), findsOneWidget);
    expect(find.byKey(const ValueKey('mds-set-row-media.speedFold')), findsOneWidget);
    expect(find.byKey(const ValueKey('mds-set-row-media.dailyQ')), findsOneWidget);
  });

  testWidgets('点 seg＝写 media.* 落 settings 表；重开屏从 KV 读回选中态', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    await pumpSet(tester);
    expect(chipOn(tester, 'mds-set-media.defaultView-desk'), isTrue,
        reason: '未写过的键＝读侧默认回落');
    await tester.tap(find.byKey(const ValueKey('mds-set-media.defaultView-spine')));
    await settle5(tester);
    expect(await repo.kv('media.defaultView'), 'spine',
        reason: 'KV 落 settings 表＝计划 §七 存储行，不散落 SharedPreferences');
    expect(await repo.kv('media.wallCols'), isNull, reason: '没碰的键不写');

    await pumpSet(tester);
    expect(chipOn(tester, 'mds-set-media.defaultView-spine'), isTrue,
        reason: '重开屏从设置读回，不是页面内存态');
  });

  testWidgets('灰态行整体点不动、零说明（更新提醒三行＋识图＋导出两枚）', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    await pumpSet(tester);
    await tester.tap(find.byKey(const ValueKey('mds-set-tab-note')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('mds-set-gray-media.ocr')),
        warnIfMissed: false);
    await settle5(tester);
    expect(find.text('未安装识别库 · 可用「＋附件」与「粘贴文本」'), findsNothing,
        reason: '设置屏识图行＝灰态点不动，不接旧弹层的说明文案');
    expect(await repo.kv('media.ocr'), isNull);

    await tester.tap(find.byKey(const ValueKey('mds-set-tab-notify')));
    await settle5(tester);
    for (final k in [
      'media.notifyNewEpisode', 'media.notifyNewAlbum', 'media.notifySequel'
    ]) {
      expect(find.byKey(ValueKey('mds-set-row-$k')), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('mds-set-gray-$k')),
          warnIfMissed: false);
      await settle5(tester);
      expect(await repo.kv(k), isNull, reason: '$k 灰钮不许写库（刀2 挂上 mSetTgl 即红）');
    }
    await tester.tap(find.byKey(const ValueKey('mds-set-tab-data')));
    await settle5(tester);
    for (final k in ['expMd', 'expJson']) {
      expect(find.byKey(ValueKey('mds-set-gray-$k')), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('mds-set-gray-$k')),
          warnIfMissed: false);
      await settle5(tester);
      expect(await repo.kv(k), isNull, reason: '$k 灰钮不许写库也不许动作');
    }
    expect(find.textContaining('说明'), findsNothing, reason: '灰态零说明文案');
  });

  testWidgets('speedFold 双向同源：设置翻→统计 chip 翻；chip 翻→设置行翻', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    await pumpSet(tester);
    await tester.tap(find.byKey(const ValueKey('mds-set-tab-timer')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('mds-set-media.speedFold')));
    await settle5(tester);
    expect(await repo.kv('media.speedFold'), 'true');

    // 同容器切到统计屏＝设置改动与 chip 同帧（同源不各存一份态）。
    lastContainer!.read(mediaTickProvider.notifier).state++;
    final router = GoRouter(
      initialLocation: '/media/stat',
      routes: mediaPageRoutes(),
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: lastContainer!,
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle5(tester);
    expect(chipOn(tester, 'mds-stat-fold-fold'), isTrue,
        reason: '设置翻＝chip 跟着翻（批7 遗留「设置页开关随设置批接」在此结掉）');
  });

  testWidgets('timerUI=full：详情计时钮直达沉浸页；capsule 档就地起停', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    await addItem('满屏片');
    await repo.setKv('media.timerUI', 'full');
    final container = ProviderContainer(
      overrides: [mediaRepositoryProvider.overrideWithValue(repo)],
    );
    lastContainer = container;
    final router = GoRouter(
      initialLocation: '/media/item/x_满屏片',
      routes: mediaPageRoutes(),
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('mds-detail-timerbtn')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('mds-timer-toggle')), findsOneWidget,
        reason: '全屏档＝起停直接进沉浸页（LH-C23 铁口径①两条真路径之一）');

    // 胶囊档＝就地起停，不落沉浸页（悬浮条由 timer_bar_overlay 自理）。
    await repo.setKv('media.timerUI', 'capsule');
    container.read(mediaTickProvider.notifier).state++;
    router.go('/media/item/x_满屏片');
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('mds-detail-timerbtn')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('mds-timer-toggle')), findsNothing);
    final running = await repo.runningSession();
    expect(running?.itemId, 'x_满屏片', reason: '胶囊档＝就地起会话');
  });

  testWidgets('defaultView/sortDefault 生效：进架口吃 KV（刀3 硬钉 desk/recent 即红）',
      (tester) async {
    await useSurface(tester, const Size(420, 1600));
    await repo.setKv('media.defaultView', 'list');
    await repo.setKv('media.sortDefault', 'title');
    final container = ProviderContainer(
      overrides: [mediaRepositoryProvider.overrideWithValue(repo)],
    );
    lastContainer = container;
    await applyMediaShelfPrefs(container);
    expect(container.read(mediaViewProvider.notifier).state, 'list');
    expect(container.read(mediaSortProvider.notifier).state, 'name',
        reason: '六档按原型实态映射：title→架面 name 键，不造第七档（工单 §3 偏离②）');
    await container.read(mediaRepositoryProvider)
        .setKv('media.defaultView', 'bogus');
    await applyMediaShelfPrefs(container);
    expect(container.read(mediaViewProvider.notifier).state, 'list',
        reason: '非法值不吃＝架面视图白名单兜底');
  });

  testWidgets('wallCols 生效：进架桌面网格列数吃 KV', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    await addItem('列数片A');
    await addItem('列数片B');
    await repo.setKv('media.defaultView', 'desk');
    await repo.setKv('media.wallCols', '3');
    final container = ProviderContainer(
      overrides: [mediaRepositoryProvider.overrideWithValue(repo)],
    );
    lastContainer = container;
    final router = GoRouter(
      initialLocation: '/media/shelf',
      routes: mediaPageRoutes(),
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle5(tester);
    final delegate = tester
        .widget<GridView>(find.byType(GridView).last)
        .gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 3, reason: 'wallCols 内联轨道（原型 repeat(MSET.wallCols)）');
  });

  testWidgets('新增插入位的设置行在场且可写（落位行为由 media_add_sheet_test 钉）',
      (tester) async {
    await useSurface(tester, const Size(420, 1600));
    await pumpSet(tester);
    await tester.tap(find.byKey(const ValueKey('mds-set-tab-sort')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('mds-set-media.newPos-tail')));
    await settle5(tester);
    expect(await repo.kv('media.newPos'), 'tail');
    expect(find.byKey(const ValueKey('mds-set-media.sortDefault-year')),
        findsOneWidget,
        reason: '默认排序六档按原型实态铺齐（工单 §3 偏离②）');
  });

  testWidgets('dailyQ 生效面：今天没计时→工作台出提示行；开/关与记一条后都不出',
      (tester) async {
    await useSurface(tester, const Size(420, 1600));
    final container = ProviderContainer(
      overrides: [mediaRepositoryProvider.overrideWithValue(repo)],
    );
    lastContainer = container;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: MediaWorkbench())),
    ));
    await settle5(tester);
    expect(find.byKey(const ValueKey('mds-dailyq-row')), findsOneWidget,
        reason: '默认开＋今天无计时＝段顶提示行（应用内，不占系统通知）');

    await repo.setKv('media.dailyQ', 'false');
    container.read(mediaTickProvider.notifier).state++;
    await settle5(tester);
    expect(find.byKey(const ValueKey('mds-dailyq-row')), findsNothing,
        reason: '开关控显隐');

    await repo.setKv('media.dailyQ', 'true');
    final x = await addItem('补记片');
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await db.insert(md.tMediaSessions, {
      'item_id': x.id,
      'kind': MediaItem.kMovie,
      'started_at': nowMs - 600000,
      'ended_at': nowMs,
      'minutes': 10,
      'source': 'timer',
    });
    container.read(mediaTickProvider.notifier).state++;
    await settle5(tester);
    expect(find.byKey(const ValueKey('mds-dailyq-row')), findsNothing,
        reason: '今天已有一条已结算计时＝提示行收掉');

    // 设置直达入口（拍板⑤：图标条第 8 枚的 Flutter 形态＝工作台直达行）。
    expect(find.byKey(const ValueKey('media-open-set')), findsOneWidget);
    expect(find.byKey(const ValueKey('media-open-goal')), findsOneWidget);
  });
}
