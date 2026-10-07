import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema/core.dart' as core;
import 'package:lifeharness/core/database/schema/media.dart' as md;
import 'package:lifeharness/features/media/data/media_repo_session.dart';
import 'package:lifeharness/features/media/data/media_repository.dart';
import 'package:lifeharness/features/media/domain/media_item.dart';
import 'package:lifeharness/features/media/domain/media_session.dart';
import 'package:lifeharness/features/media/presentation/media_progress_sheet.dart';
import 'package:lifeharness/features/media/presentation/media_providers.dart';

import 'helpers.dart';

/// 影音游批3 · 进度录入弹层（原型 `m-sheet-progress` 四套分派的真实回写面）。
///
/// 刀2 钉这里：kind→写回列的分派若退回单一 pct 口径，第二/三/四例即红。
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

  Future<String> add(MediaItem Function() make) => repo.addItem(make());

  /// 打开弹层（宿主页直接调 showMediaProgressSheet；容器与架面同一 provider 树）。
  Future<void> open(WidgetTester tester, String id) async {
    final item = await repo.itemById(id);
    final container = ProviderContainer(
      overrides: [mediaRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (ctx, ref, _) => TextButton(
              onPressed: () => showMediaProgressSheet(ctx, ref, item!),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await settle5(tester);
  }

  testWidgets('电影＝百分比/时间点两档切换，保存写回进度与完结档', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final id = await add(() => MediaItem(
          kind: MediaItem.kMovie,
          title: '第二十条',
          state: '在看',
          progressWay: MediaItem.kWayPct,
          progressTo: '30',
          durationMin: 140,
          createdAt: 1,
          updatedAt: 1,
        ));
    await open(tester, id);
    // 两档 chip 都在（电影特有＝不是单档换标题）
    expect(find.byKey(const ValueKey('mds-prog-way-pct')), findsOneWidget);
    expect(find.byKey(const ValueKey('mds-prog-way-min')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('mds-prog-field-看到百分之几')),
      '100',
    );
    await tester.tap(find.byKey(const ValueKey('mds-prog-state-看完')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('mds-prog-save')));
    await settle5(tester);
    final m = await repo.itemById(id);
    expect(m!.state, '看完');
    expect(m.completed, isTrue);
    expect(m.progressTo, '100');
    expect(m.mainPct, 100);
    expect(m.endedAt, isNotNull, reason: '完结档落 ended_at（看片完成时间）');
    await clearToasts(tester);
  });

  testWidgets('剧集＝季+集与追更状态；写回是集号列不是百分比', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final id = await add(() => MediaItem(
          kind: MediaItem.kSeries,
          title: '漫长的季节',
          state: '在追',
          progressWay: MediaItem.kWayEp,
          progressTo: '3',
          seasonsCount: 1,
          episodesTotal: 12,
          durationMin: 45,
          createdAt: 1,
          updatedAt: 1,
        ));
    await open(tester, id);
    expect(find.byKey(const ValueKey('mds-prog-way-pct')), findsNothing,
        reason: '剧集没有百分比/时间点两档');
    await tester.enterText(
      find.byKey(const ValueKey('mds-prog-field-看到第几集（共 12 集）')),
      '8',
    );
    await tester.tap(find.byKey(const ValueKey('mds-prog-save')));
    await settle5(tester);
    final m = await repo.itemById(id);
    expect(m!.progressTo, '8');
    expect(m.mainPct, 0, reason: '剧集不串写主线%列');
    expect(m.state, '在追');
    await clearToasts(tester);
  });

  testWidgets('音乐＝循环不落进度列，「记一次」＝补一条会话（派生数 +1）', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final id = await add(() => MediaItem(
          kind: MediaItem.kMusic,
          title: '意外奏',
          state: '在听',
          progressWay: MediaItem.kWayLoops,
          tracksCount: 10,
          createdAt: 1,
          updatedAt: 1,
        ));
    await open(tester, id);
    expect(find.textContaining('循环 0 次 · 按听歌会话自动计'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('mds-prog-field-本次循环（0＝不记）')),
      '1',
    );
    await tester.tap(find.byKey(const ValueKey('mds-prog-save')));
    await settle5(tester);
    final m = await repo.itemById(id);
    expect(m!.progressTo, isNull, reason: '音乐没有可写的进度列——编数即假账');
    expect(m.listenLoops, 1, reason: '循环次数＝会话条数，记一次即派生 +1');
    final sess = await repo.sessionsOf(id);
    expect(sess, hasLength(1));
    expect(sess.single.source, MediaSession.kSrcManual);
    await clearToasts(tester);
  });

  testWidgets('游戏＝周目/主线/支线/成就各归各列；成就档不覆写主线', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final id = await add(() => MediaItem(
          kind: MediaItem.kGame,
          title: '黑神话',
          state: '在玩',
          progressWay: MediaItem.kWayMainPct,
          mainPct: 40,
          playthroughs: 1,
          durationMin: 50,
          createdAt: 1,
          updatedAt: 1,
        ));
    await open(tester, id);
    await tester.enterText(
      find.byKey(const ValueKey('mds-prog-field-周目')),
      '2',
    );
    await tester.enterText(
      find.byKey(const ValueKey('mds-prog-field-主线%')),
      '55',
    );
    await tester.enterText(
      find.byKey(const ValueKey('mds-prog-field-支线%')),
      '30',
    );
    await tester.enterText(
      find.byKey(const ValueKey('mds-prog-field-全成就%')),
      '18',
    );
    await tester.tap(find.byKey(const ValueKey('mds-prog-save')));
    await settle5(tester);
    final m = await repo.itemById(id);
    expect(m!.mainPct, 55);
    expect(m.sidePct, 30);
    expect(m.playthroughs, 2);
    expect(m.achPct, 0, reason: '当档＝主线，成就栏改动不串写（防假账）');
    await clearToasts(tester);
  });

  testWidgets('保存后 toast 报「预计完成日」只在真算得出时出现；无时长＝不编数', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final id = await add(() => MediaItem(
          kind: MediaItem.kMovie,
          title: '无时长片',
          state: '在看',
          progressWay: MediaItem.kWayPct,
          progressTo: '10',
          durationMin: 0, // 总时长未知
          createdAt: 1,
          updatedAt: 1,
        ));
    // 造三条已结算会话撑 pace（日均按真实入账算）
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final day in [3, 2, 1]) {
      await db.insert(md.tMediaSessions, {
        'item_id': id,
        'kind': MediaItem.kMovie,
        'started_at': now - day * 86400000 - 30 * 60000,
        'ended_at': now - day * 86400000,
        'minutes': 30,
        'source': 'timer',
      });
    }
    await open(tester, id);
    await tester.tap(find.byKey(const ValueKey('mds-prog-save')));
    await settle5(tester);
    expect(find.textContaining('预计完成'), findsNothing,
        reason: '总时长未知＝不预测，不许编一个完成日');
    expect(find.textContaining('进度已存'), findsOneWidget);
    await clearToasts(tester);

    // 补上时长后同一份会话＝能算出预计完成日（同一弹层口径）
    await db.update(md.tMediaItems, {'duration_min': 120}, where: 'id = ?', whereArgs: [id]);
    await open(tester, id);
    await tester.tap(find.byKey(const ValueKey('mds-prog-save')));
    await settle5(tester);
    expect(find.textContaining('预计完成'), findsOneWidget);
    await clearToasts(tester);
  });
}
