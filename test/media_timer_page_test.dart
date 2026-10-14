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
import 'package:lifeharness/features/media/presentation/media_providers.dart';
import 'package:lifeharness/features/media/presentation/media_routes.dart';
import 'package:lifeharness/shared/linkage/timer_bar_overlay.dart';

import 'helpers.dart';

/// 影音游批3 · 沉浸计时页＋悬浮计时条（工单执行面板第 3 项）。
///
/// 计时页带秒级周期 Timer＝禁 pumpAndSettle（既定坑），一律定步长多推几拍
/// （真库 Future 在 FakeAsync 下只随 pump 排空微任务，不等墙钟）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late MediaRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in md.mediaSchemaStatements) {
      await db.execute(sql);
    }
    await db.execute(
      'CREATE TABLE IF NOT EXISTS ${core.tSettings} '
      '(key TEXT PRIMARY KEY, value TEXT)',
    );
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

  Future<String> add({
    String kind = MediaItem.kMovie,
    String title = '计时测试',
  }) => repo.addItem(
    MediaItem(
      kind: kind,
      title: title,
      state: MediaItem.initialState(kind),
      progressWay: MediaItem.defaultWay(kind),
      durationMin: 120,
      createdAt: 1,
      updatedAt: 1,
    ),
  );

  /// 周期 Timer 页的推帧口径：10 拍×120ms（≈1.2s 假时钟），足够把
  /// 起停后的 provider 链（kv→会话→详情）排空，并让大计时走一格。
  Future<void> beat(WidgetTester tester, {int n = 10}) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<ProviderContainer> pumpTimer(WidgetTester tester, String id) async {
    final container = ProviderContainer(
      overrides: [mediaRepositoryProvider.overrideWithValue(repo)],
    );
    // 兜底 dispose：addTearDown 跑在用例体（含「挂起定时器」断言）之后；
    // 需要断言前取消 ticker 的用例（悬浮条那条）在自己收尾处再 dispose 一次。
    final router = GoRouter(
      initialLocation: '/root',
      routes: [
        GoRoute(
          path: '/root',
          builder: (_, _) => const Scaffold(body: SizedBox.shrink()),
        ),
        ...mediaPageRoutes(),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await beat(tester);
    router.push('/media/timer/$id');
    await beat(tester);
    return container;
  }

  /// 把在跑会话起点拨早 [secs] 秒（不真等）。
  Future<void> shiftStart(int sessionId, int secs) => db.update(
    md.tMediaSessions,
    {'started_at': DateTime.now().millisecondsSinceEpoch - secs * 1000},
    where: 'id = ?',
    whereArgs: [sessionId],
  );

  testWidgets('未开始＝00:00:00 且状态行读「未开始」；名场面钮已开工＝点它开表单且不预填 0 分', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final id = await add();
    await pumpTimer(tester, id);
    expect(find.text('00:00:00'), findsOneWidget);
    expect(find.text('未开始'), findsOneWidget);
    // 批5 回灌：占位旁注退场（禁令「不写教学性说明文案」同口径，不留替代文案）
    expect(find.text('名场面记录随影音笔记批开放'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('mds-timer-scene')));
    await beat(tester, n: 14);
    expect(find.text('记一条影音笔记'), findsOneWidget, reason: '名场面＝唯一录入表单');
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('mde-at'))).controller!.text,
      isEmpty,
      reason: '未起计时＝不预填 0 分，时间点留空',
    );
    await tester.tapAt(const Offset(6, 6)); // 遮罩收起
    await beat(tester, n: 14);
  });

  testWidgets('计时在跑＝名场面钮把当前读数带进时间点', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final id = await add();
    final container = await pumpTimer(tester, id);
    await tester.tap(find.byKey(const ValueKey('mds-timer-toggle')));
    await beat(tester);
    final run = await repo.runningSession();
    await shiftStart(run!.id!, 185); // 3 分 5 秒
    container.read(mediaTickProvider.notifier).state++; // 等价写库后的模块重取
    await beat(tester);
    await tester.tap(find.byKey(const ValueKey('mds-timer-scene')));
    await beat(tester, n: 14);
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('mde-at'))).controller!.text,
      '3 分',
      reason: '在跑读数＝secs~/60 走 mediaNoteAtTx',
    );
    await tester.tap(find.byKey(const ValueKey('mde-cancel')));
    await beat(tester, n: 14);
  });

  testWidgets('点开始＝会话落库、大计时走字、分区自动进「在看」', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final id = await add();
    final container = await pumpTimer(tester, id);
    await tester.tap(find.byKey(const ValueKey('mds-timer-toggle')));
    await beat(tester);
    final run = await repo.runningSession();
    expect(run?.itemId, id, reason: '点开始必须真落一条会话');
    await shiftStart(run!.id!, 65);
    container.read(mediaTickProvider.notifier).state++; // 等价写库后的模块重取
    await beat(tester);
    final parts = tester
        .widget<Text>(find.byKey(const ValueKey('mds-timer-clock')))
        .data!
        .split(':')
        .map(int.parse)
        .toList();
    expect(
      parts[0] * 3600 + parts[1] * 60 + parts[2],
      greaterThanOrEqualTo(65),
      reason: '拨到 65 秒前＝大计时至少读到 01:05',
    );
    expect(find.textContaining('观影中 · 结束后可直接记进度'), findsOneWidget);
    final m = await repo.itemById(id);
    expect(m!.state, '在看', reason: '起计时＝进在场分区');
  });

  testWidgets('四类 kind 的计时文案各不同（刀3：退回单一「观影中」三例即红）', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    const cases = {
      MediaItem.kMovie: '观影中',
      MediaItem.kSeries: '追剧中',
      MediaItem.kMusic: '听歌中',
      MediaItem.kGame: '游玩中',
    };
    for (final e in cases.entries) {
      final id = await add(kind: e.key, title: '条${e.key}');
      final s = await repo.startSession(id);
      final c = await pumpTimer(tester, id);
      c.read(mediaTickProvider.notifier).state++;
      await beat(tester);
      expect(
        find.textContaining('${e.value} · 结束后可直接记进度'),
        findsOneWidget,
        reason: '${e.key} 的计时状态行应为「${e.value}」',
      );
      // 满 1 分钟再收，避免短会话删行干扰下一条
      await shiftStart(s.id!, 70);
      await repo.endSession(id);
    }
  });

  testWidgets('点结束＝结算入账，L4 块分类=娱乐，autoAsk 默认开弹记进度', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final id = await add(title: '沙丘');
    final s = await repo.startSession(id);
    await shiftStart(s.id!, 5 * 60);
    await pumpTimer(tester, id);
    await tester.tap(find.byKey(const ValueKey('mds-timer-toggle')));
    await beat(tester);
    final blocks = await db.query(core.tTimeBlocks);
    expect(blocks, hasLength(1));
    expect(blocks.single['category'], '娱乐');
    // autoAsk 默认开：结束即出「记进度」弹层（保存钮在场）
    expect(find.byKey(const ValueKey('mds-prog-save')), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('杀进程重开延续＝库内有在跑会话即显示实时读数（不依赖内存态）', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final id = await add(title: '续航');
    final s = await repo.startSession(id);
    await shiftStart(s.id!, 180);
    // 全新 container＋新页面＝模拟冷启动后重建 provider 树
    await pumpTimer(tester, id);
    expect(find.textContaining('观影中'), findsWidgets);
    final p2 = tester
        .widget<Text>(find.byKey(const ValueKey('mds-timer-clock')))
        .data!
        .split(':')
        .map(int.parse)
        .toList();
    expect(
      p2[0] * 3600 + p2[1] * 60 + p2[2],
      greaterThanOrEqualTo(180),
      reason: '冷启动延续＝从库内起点续算，至少读到 3 分钟',
    );
  });

  testWidgets('悬浮计时条跨页常驻＝文案按 kind，■ 结束就地结算并退场', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final id = await add(kind: MediaItem.kGame, title: '双人成行');
    final s = await repo.startSession(id);
    await shiftStart(s.id!, 4 * 60);
    final container = ProviderContainer(
      overrides: [mediaRepositoryProvider.overrideWithValue(repo)],
    );
    final router = GoRouter(
      initialLocation: '/root',
      routes: [
        GoRoute(
          path: '/root',
          builder: (_, _) => const Scaffold(
            // 壳层同款装配：条挂在任意页之上（跨页常驻的最小复现形）
            body: SafeArea(child: TimerBarOverlay(child: SizedBox.expand())),
          ),
        ),
        ...mediaPageRoutes(),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await beat(tester);
    expect(find.byKey(const ValueKey('media-bar')), findsOneWidget);
    // 批A 两形态：默认紧凑不显书名，点「时间」展开书名字样后再断言文案。
    await tester.tap(find.byKey(const ValueKey('media-pill-time')));
    await beat(tester);
    expect(find.textContaining('《双人成行》 · 游玩中 4 分钟'), findsOneWidget);
    await tester.tap(find.text('■ 结束'));
    await beat(tester);
    expect(await repo.runningSession(), isNull);
    expect(
      find.byKey(const ValueKey('media-bar')),
      findsNothing,
      reason: '结束后条必须退场',
    );
    final blocks = await db.query(core.tTimeBlocks);
    expect(
      blocks.single['category'],
      '娱乐',
      reason: '条上结束与页面结束同一条 L4 路径',
    );
    await clearToasts(tester);
    await drainLogTimer(tester);
    // 当场拆容器：calendarTicker 的秒级流定时器必须在「挂起定时器」断言前取消
    container.dispose();
  });
}
