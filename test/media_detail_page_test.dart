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

import 'helpers.dart';

/// 影音游批3 · 条目详情屏（原型 `m-detail` 的 Flutter 落面）。
///
/// 四条判定＝面板第 3 项＋§0：四套 kind 结构、反查芯片、进度行开弹层、
/// 空态不照抄原型演示数据（名场面/曲目没有真数据＝虚线行）。
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

  Future<ProviderContainer> pumpDetail(
    WidgetTester tester,
    String id,
  ) async {
    final container = ProviderContainer(
      overrides: [mediaRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/root',
      routes: [
        GoRoute(
          path: '/root',
          builder: (_, _) => const Scaffold(body: SizedBox.shrink()),
        ),
        GoRoute(
          path: '/root2',
          builder: (_, _) => const Scaffold(body: SizedBox.shrink()),
        ),
        ...mediaPageRoutes(),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle5(tester);
    // 栈页入口一律 push（R6：go 会把栈页变栈底）
    router.push('/media/item/$id');
    await settle5(tester);
    return container;
  }

  Future<String> add(MediaItem Function() make) async {
    final id = await repo.addItem(make());
    return id;
  }

  testWidgets('电影详情＝名场面空态＋进度行＋计时/记进度钮，记笔记钮置灰不隐藏', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final id = await add(() => MediaItem(
          kind: MediaItem.kMovie,
          title: '沙丘 2',
          state: '在看',
          progressWay: MediaItem.kWayPct,
          progressTo: '40',
          durationMin: 155,
          creator: '维伦纽瓦',
          publisher: '华纳',
          createdAt: 1,
          updatedAt: 1,
        ));
    await pumpDetail(tester, id);
    expect(find.text('沙丘 2'), findsWidgets);
    expect(find.textContaining('进度 40%'), findsOneWidget);
    // 名场面属笔记批＝空态虚线行，不造演示数据
    expect(find.textContaining('名场面记录随影音笔记批开放'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mds-detail-note')),
      findsOneWidget,
      reason: '能力边界要显式声明：置灰不隐藏',
    );
    expect(
      tester.widget<OutlinedButton>(find.byKey(const ValueKey('mds-detail-note'))).onPressed,
      isNull,
    );
    // 创作者芯片点＝反查同值条目（带 q 直达架面）
    await tester.tap(find.byKey(const ValueKey('mds-chip-creator')));
    await settle5(tester);
    expect(find.text('影音架'), findsOneWidget, reason: '反查落点＝架面');
    expect(find.text('电影 1'), findsOneWidget);
  });

  testWidgets('剧集详情＝季集读数（已看集数从库取，不是原型演示的 S01E05）', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final id = await add(() => MediaItem(
          kind: MediaItem.kSeries,
          title: '熊家餐馆',
          state: '在追',
          progressWay: MediaItem.kWayEp,
          progressTo: '7',
          seasonsCount: 3,
          episodesTotal: 18,
          durationMin: 30,
          creator: '范·威特',
          createdAt: 1,
          updatedAt: 1,
        ));
    await pumpDetail(tester, id);
    expect(find.textContaining('看到第 7 集'), findsOneWidget);
    expect(find.text('共 18 集 · 已看 7 集'), findsOneWidget);
    expect(find.text('S3'), findsOneWidget);
    // 没登记的曲目/名场面演示行不得出现
    expect(find.textContaining('曲目 1'), findsNothing);
  });

  testWidgets('音乐详情＝循环次数走会话派生；没有会话时读数 0 不编数', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final id = await add(() => MediaItem(
          kind: MediaItem.kMusic,
          title: '河运',
          state: '在听',
          progressWay: MediaItem.kWayLoops,
          tracksCount: 0,
          creator: 'Florence',
          createdAt: 1,
          updatedAt: 1,
        ));
    await pumpDetail(tester, id);
    final container = await pumpDetail(tester, id);
    expect(find.textContaining('循环 0 次'), findsOneWidget);
    expect(find.text('还没登记曲目 · 在录入弹层补上'), findsOneWidget);
    // 记一次循环（补一条会话）后按 tick 重取，派生数当场 +1（不编数的反面＝派生真算）
    await repo.addManualSession(
      itemId: id,
      atMs: DateTime.now().millisecondsSinceEpoch - 10 * 60000,
      minutes: 42,
    );
    container.read(mediaTickProvider.notifier).state++;
    await settle5(tester);
    expect(find.textContaining('循环 1 次'), findsOneWidget);
  });

  testWidgets('游戏详情＝三档环各按库值，支线/成就为 0 时不画（不铺假环）', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final id = await add(() => MediaItem(
          kind: MediaItem.kGame,
          title: '双人成行',
          state: '在玩',
          progressWay: MediaItem.kWayMainPct,
          mainPct: 60,
          sidePct: 0,
          achPct: 0,
          playthroughs: 1,
          durationMin: 600,
          creator: 'Hazelight',
          publisher: 'EA',
          createdAt: 1,
          updatedAt: 1,
        ));
    await pumpDetail(tester, id);
    expect(find.byKey(const ValueKey('mds-ring-主线')), findsOneWidget);
    expect(find.byKey(const ValueKey('mds-ring-支线')), findsNothing);
    expect(find.byKey(const ValueKey('mds-ring-全成就')), findsNothing);
    expect(find.text('还没有游玩记录 · 点下方「▶ 计时」开始'), findsOneWidget);
  });

  testWidgets('进度行点开四套弹层；弹层关闭回详情不残留遮罩', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final id = await add(() => MediaItem(
          kind: MediaItem.kMovie,
          title: '奥本海默',
          state: '在看',
          progressWay: MediaItem.kWayPct,
          progressTo: '10',
          durationMin: 180,
          createdAt: 1,
          updatedAt: 1,
        ));
    await pumpDetail(tester, id);
    await tester.tap(find.byKey(const ValueKey('mds-detail-progline')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('mds-prog-save')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mds-prog-cancel')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('mds-prog-save')), findsNothing);
  });
}
