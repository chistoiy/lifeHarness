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

/// 影音游批4b · 计时明细屏（原型 `m-sesslog` · LH-C17）。
///
/// 钉死四条既定口径：行上时长恒＝真实耗时、折算只在倍速>1 另出一列；
/// 改/删/补记都走仓储差量口（同一条 `time_blocks` UPDATE，`txn_id` 复用不新建）；
/// 日期/时长/起讫就地内嵌输入（无二段弹层）；「没有记录」与「当前范围没有记录」两句空态分开。
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

  Future<String> addMovie() => repo.addItem(MediaItem(
        kind: MediaItem.kMovie,
        title: '沙丘 2',
        state: '在看',
        progressWay: MediaItem.kWayPct,
        progressTo: '40',
        durationMin: 155,
        creator: '维伦纽瓦',
        createdAt: 1,
        updatedAt: 1,
      ));

  String ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<ProviderContainer> pumpSesslog(WidgetTester tester, String id) async {
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
        ...mediaPageRoutes(),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle5(tester);
    // 栈页入口一律 push（R6：go 会把栈页变栈底）
    router.push('/media/item/$id/sessions');
    await settle5(tester);
    return container;
  }

  Future<int> blockCount() async {
    final r = await db.rawQuery('SELECT COUNT(*) AS n FROM ${core.tTimeBlocks}');
    return (r.single['n'] as int?) ?? 0;
  }

  /// 就地填草稿：日期／时长／起点（不拉系统选择器，直接写进内嵌输入框）。
  Future<void> fillDraft(WidgetTester tester, {String? date, String? min, String? from}) async {
    await tester.enterText(
        find.byKey(const ValueKey('mds-sess-date-new')), date ?? ymd(DateTime.now()));
    if (min != null) {
      await tester.enterText(find.byKey(const ValueKey('mds-sess-min-new')), min);
    }
    await tester.enterText(
        find.byKey(const ValueKey('mds-sess-from-new')), from ?? '20:00');
    await tester.pump();
  }

  testWidgets('空态＝虚线一行不拿 0 冒充读数；补记落库同时账本只落一条娱乐块', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final id = await addMovie();
    await pumpSesslog(tester, id);

    expect(find.textContaining('还没有计时记录'), findsOneWidget);
    expect(find.byKey(const ValueKey('mds-sess-form')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mds-sess-add')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('mds-sess-form')), findsOneWidget,
        reason: '补记就地展开，不是再起一层弹层');

    await fillDraft(tester, min: '45');
    await tester.tap(find.byKey(const ValueKey('mds-sess-save')));
    // SnackBar 断言前禁 settle5（会把 fake 时间推过 1.6s 自动消失期）
    expect(await pollText(tester, '已补记 45m · 账本同步'), isTrue);

    final sessions = await repo.sessionsOf(id);
    expect(sessions, hasLength(1));
    expect(sessions.single.minutes, 45, reason: '会话行只存真实耗时');
    expect(sessions.single.endedAt, isNotNull);
    expect(await blockCount(), 1, reason: 'L4「娱乐」同场落一条，不是不写也不是写两条');

    await clearToasts(tester);
  });

  testWidgets('倍速三档就地选；1x 折叠行不重复报同一个数，>1x 才另出折算列', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final id = await addMovie();
    final now = DateTime.now();
    final a = await repo.addManualDetail(
        itemId: id,
        kind: MediaItem.kMovie,
        startedAtMs: now.subtract(const Duration(hours: 3)).millisecondsSinceEpoch,
        minutes: 40,
        speed: 1.5);
    final b = await repo.addManualDetail(
        itemId: id,
        kind: MediaItem.kMovie,
        startedAtMs: now.subtract(const Duration(hours: 6)).millisecondsSinceEpoch,
        minutes: 30,
        speed: 1);
    await pumpSesslog(tester, id);

    expect(find.byKey(ValueKey('mds-sess-fold-${a.id}')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(ValueKey('mds-sess-fold-${a.id}'))).data,
        contains('1h'), reason: '40m ×1.5 折算＝1h，真实列仍是 40m');
    expect(find.byKey(ValueKey('mds-sess-fold-${b.id}')), findsNothing,
        reason: '1x 的折算与真实同值＝不重复出一列');
    expect(find.text('1.5x'), findsOneWidget);
    expect(find.text('1x'), findsNothing, reason: '1x 行不出倍速芯片');

    // 补记表单里的倍速就地四档，点选不循环；选中 2x 后草稿当场折算
    await tester.tap(find.byKey(const ValueKey('mds-sess-add')));
    await settle5(tester);
    await fillDraft(tester, min: '40');
    expect(find.textContaining('折算 40m'), findsOneWidget,
        reason: '草稿默认 1x：折算与真实同值');
    await tester.tap(find.byKey(const ValueKey('mds-sess-speed-2.0')));
    await settle5(tester);
    expect(find.textContaining('折算 1h 20m'), findsOneWidget);
  });

  testWidgets('时长/日期就地校验：不猜、不起弹窗，红字落在表单内且不许落库', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final id = await addMovie();
    await pumpSesslog(tester, id);

    await tester.tap(find.byKey(const ValueKey('mds-sess-add')));
    await settle5(tester);
    await fillDraft(tester); // 时长留空
    await tester.tap(find.byKey(const ValueKey('mds-sess-save')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('mds-sess-err')), findsOneWidget);
    expect(find.textContaining('大于 0 的分钟数'), findsOneWidget);
    expect(await repo.sessionsOf(id), isEmpty, reason: '校验没过不许落库');

    await tester.enterText(find.byKey(const ValueKey('mds-sess-date-new')), '10月8日');
    await tester.enterText(find.byKey(const ValueKey('mds-sess-min-new')), '30');
    await tester.tap(find.byKey(const ValueKey('mds-sess-save')));
    await settle5(tester);
    expect(find.textContaining('格式不对'), findsOneWidget);
    expect(find.byKey(const ValueKey('mds-sess-cancel')), findsOneWidget,
        reason: '表单仍在原地可改，没有换成对话框');

    await tester.tap(find.byKey(const ValueKey('mds-sess-cancel')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('mds-sess-form')), findsNothing);
  });

  testWidgets('范围三档点选不循环：本月不含 4 个月前那条，近 3 月含 2 个月前那条', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final id = await addMovie();
    final now = DateTime.now();
    final fresh = await repo.addManualDetail(
        itemId: id,
        kind: MediaItem.kMovie,
        startedAtMs: now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
        minutes: 50,
        speed: 1);
    final mid = await repo.addManualDetail(
        itemId: id,
        kind: MediaItem.kMovie,
        startedAtMs: DateTime(now.year, now.month - 2, 1, 20).millisecondsSinceEpoch,
        minutes: 60,
        speed: 1);
    final old = await repo.addManualDetail(
        itemId: id,
        kind: MediaItem.kMovie,
        startedAtMs: DateTime(now.year, now.month - 4, 1, 20).millisecondsSinceEpoch,
        minutes: 90,
        speed: 1);
    await pumpSesslog(tester, id);

    for (final s in [fresh, mid, old]) {
      expect(find.byKey(ValueKey('mds-sess-row-${s.id}')), findsOneWidget,
          reason: '默认「全部」应见三条');
    }

    await tester.tap(find.byKey(const ValueKey('mds-sess-scope-quarter')));
    await settle5(tester);
    expect(find.byKey(ValueKey('mds-sess-row-${old.id}')), findsNothing);
    expect(find.byKey(ValueKey('mds-sess-row-${mid.id}')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mds-sess-scope-month')));
    await settle5(tester);
    expect(find.byKey(ValueKey('mds-sess-row-${mid.id}')), findsNothing);
    expect(find.byKey(ValueKey('mds-sess-row-${fresh.id}')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mds-sess-scope-all')));
    await settle5(tester);
    expect(find.byKey(ValueKey('mds-sess-row-${old.id}')), findsOneWidget);
  });

  testWidgets('范围内一条都没有＝另一句空态（区别于「还没有计时记录」）', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final id = await addMovie();
    final now = DateTime.now();
    final old = await repo.addManualDetail(
        itemId: id,
        kind: MediaItem.kMovie,
        startedAtMs: DateTime(now.year, now.month - 4, 1, 20).millisecondsSinceEpoch,
        minutes: 90,
        speed: 1);
    await pumpSesslog(tester, id);
    expect(find.byKey(ValueKey('mds-sess-row-${old.id}')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mds-sess-scope-month')));
    await settle5(tester);
    expect(find.textContaining('当前范围没有记录'), findsOneWidget);
    expect(find.textContaining('还没有计时记录'), findsNothing,
        reason: '有记录只是范围筛空了，不许说成「还没计时过」');
  });

  testWidgets('改一条＝同一 txn_id 差量 UPDATE（账本不新建第二条）；删一条＝同块一并扣掉', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final id = await addMovie();
    final now = DateTime.now();
    final s = await repo.addManualDetail(
        itemId: id,
        kind: MediaItem.kMovie,
        startedAtMs: now.subtract(const Duration(hours: 3)).millisecondsSinceEpoch,
        minutes: 40,
        speed: 1,
        toText: '40%');
    await pumpSesslog(tester, id);
    final rid = s.id!;
    expect(await blockCount(), 1);
    expect(s.txnId, isNotNull);

    await tester.tap(find.byKey(ValueKey('mds-sess-row-$rid')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('mds-sess-form')), findsOneWidget);
    expect(find.byKey(ValueKey('mds-sess-del-$rid')), findsOneWidget);

    await tester.enterText(find.byKey(ValueKey('mds-sess-min-$rid')), '70');
    await tester.tap(find.byKey(const ValueKey('mds-sess-save')));
    expect(await pollText(tester, '已更新 · 累计 1h 10m'), isTrue);

    final after = await repo.sessionsOf(id);
    expect(after.single.minutes, 70);
    expect(after.single.txnId, s.txnId, reason: '改时长沿用同一条 L4 块，不新建');
    expect(await blockCount(), 1, reason: '账本仍只有一条，多写＝重复计时的机器闸');
    await clearToasts(tester);

    await tester.tap(find.byKey(ValueKey('mds-sess-row-$rid')));
    await settle5(tester);
    await tester.tap(find.byKey(ValueKey('mds-sess-del-$rid')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('d-confirm-ok')), findsOneWidget,
        reason: '删除要有确认，不许一键即删');
    await tester.tap(find.byKey(const ValueKey('d-confirm-ok')));
    expect(await pollText(tester, '已删除这条 · 账本同条扣减'), isTrue);

    expect(await repo.sessionsOf(id), isEmpty);
    expect(await blockCount(), 0, reason: '会话删除后账本同条一并扣掉');
    await clearToasts(tester);
  });
}
