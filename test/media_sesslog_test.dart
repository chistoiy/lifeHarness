import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema/core.dart' as core;
import 'package:lifeharness/core/database/schema/media.dart' as md;
import 'package:lifeharness/features/media/data/media_repository.dart';
import 'package:lifeharness/features/media/data/media_repo_session.dart';
import 'package:lifeharness/features/media/domain/media_item.dart';
import 'package:lifeharness/features/media/domain/media_session.dart';
import 'package:lifeharness/features/media/domain/media_stats.dart';
import 'package:lifeharness/features/media/presentation/media_providers.dart';
import 'package:lifeharness/features/media/presentation/media_routes.dart';

import 'helpers.dart';

/// 影音游「计时明细」整屏（原型 `index-media.html#m-sesslog` · 批4 拍板①
/// 「改与删一律在整屏」的落点）。
///
/// 四条判定对齐工单 §1 的三把刀：
/// - 汇总四格**只读一侧**（累计＝真实、折算＝`billedMinutes`），另算一套必红；
/// - 列表＝月分组降序＋组内开始时间降序（刀②：去掉页面排序必红）；
/// - 补记走 `addManualDetail`、行内改走 `updateSessionDetail`、删走 `deleteSession`，
///   **L4 娱乐块同场落定／差量不新建／同删**（刀③：补记直接 insert 必红）。
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
      'CREATE TABLE IF NOT EXISTS ${core.tSettings} (key TEXT PRIMARY KEY, value TEXT)',
    );
    // 明细屏的写口都要回写时间账本 L4 娱乐块，缺这张表＝写口直接抛
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

  /// 直接落一条已结算会话（不走写口：本组要验的是整屏写口，夹具须零副作用）。
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

  /// 从路由真入口进整屏（`/media/item/:id/sessions`，与轨迹弹层同一落点）。
  Future<void> pumpSesslog(WidgetTester tester, String id) async {
    final container = ProviderContainer(
      overrides: [mediaRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/media/item/$id/sessions',
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
  }

  /// 汇总格读数（`mds-sess-stat-<label>` 的子树文案）。
  Finder stat(String label, String value) => find.descendant(
        of: find.byKey(ValueKey('mds-sess-stat-$label')),
        matching: find.text(value),
      );

  /// 明细行按树内顺序取出（只认 `mds-sess-<纯数字 id>`，把 add/min/spd 等控件键排掉）。
  List<String> rowKeys(WidgetTester tester) {
    final re = RegExp(r'^mds-sess-\d+$');
    return [
      for (final e in find
          .byWidgetPredicate((w) {
            final k = w.key;
            return k is ValueKey<String> && re.hasMatch(k.value);
          })
          .evaluate())
        (e.widget.key! as ValueKey<String>).value,
    ];
  }

  testWidgets('汇总四格＝累计真实／折算只读 billedMinutes／天数去重／日均现算，另算一套必红', (tester) async {
    await useSurface(tester, const Size(420, 1400));
    final id = await addItem('汇总片', durationMin: 200);
    await addSession(id, MediaItem.kMovie, DateTime(2026, 1, 10, 21), 30);
    // 45 分钟 2 倍速：真实 45、折算 90——「折算≠累计」的靶点就在这条上
    await addSession(id, MediaItem.kMovie, DateTime(2026, 1, 11, 20), 45, speed: 2.0);
    await addSession(id, MediaItem.kMovie, DateTime(2026, 2, 2, 19), 15);
    await pumpSesslog(tester, id);

    expect(stat('累计', mdsHm(90)), findsOneWidget, reason: '30+45+15＝90 分钟真实耗时');
    expect(stat('折算', mdsHm(135)), findsOneWidget,
        reason: '30 + 45×2 + 15＝135；等于累计＝折算口径被写成了另一套');
    expect(stat('天数', '3'), findsOneWidget, reason: '三个自然日，同日多条不重复计');
    expect(stat('日均', mdsHm(30)), findsOneWidget, reason: '90 分钟 ÷ 3 天＝30');
    expect(find.text('共 3 次'), findsOneWidget);
    expect(find.byKey(const ValueKey('mds-sess-empty')), findsNothing);
  });

  testWidgets('列表＝月分组降序、组内开始时间降序（刀②：页面不排序即红）', (tester) async {
    await useSurface(tester, const Size(420, 1400));
    final id = await addItem('倒序片', durationMin: 200);
    final jan5 = await addSession(id, MediaItem.kMovie, DateTime(2026, 1, 5, 21), 20);
    final jan20 = await addSession(id, MediaItem.kMovie, DateTime(2026, 1, 20, 22), 20);
    final feb3 = await addSession(id, MediaItem.kMovie, DateTime(2026, 2, 3, 19), 20);
    final feb10 = await addSession(id, MediaItem.kMovie, DateTime(2026, 2, 10, 23), 20);
    await pumpSesslog(tester, id);

    expect(rowKeys(tester), [
      'mds-sess-$feb10',
      'mds-sess-$feb3',
      'mds-sess-$jan20',
      'mds-sess-$jan5',
    ], reason: '新月份在上、组内新的在上（原型 mSessSorted 同口径）');
    expect(find.text('02 月 · 2 次'), findsOneWidget);
    expect(find.text('01 月 · 2 次'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('02 月 · 2 次')).dy,
      lessThan(tester.getTopLeft(find.text('01 月 · 2 次')).dy),
      reason: '分组键本身也降序，不是行序碰巧',
    );
  });

  testWidgets('补记走 addManualDetail：会话落库＋同场落一条 L4 娱乐块（刀③：直接 insert 必红）', (tester) async {
    await useSurface(tester, const Size(420, 1400));
    final id = await addItem('补记片', durationMin: 200);
    await pumpSesslog(tester, id);

    expect(find.byKey(const ValueKey('mds-sess-empty')), findsOneWidget,
        reason: '没账＝虚线一行，不拿 0 冒充读数');
    await tester.tap(find.byKey(const ValueKey('mds-sess-add')));
    await settle5(tester);
    await tester.enterText(find.byKey(const ValueKey('mds-sess-min')), '45');
    await tester.tap(find.byKey(const ValueKey('mds-sess-save')));
    await settle5(tester);

    final sess = await db.query(md.tMediaSessions);
    expect(sess.length, 1);
    expect(sess.first['minutes'], 45);
    expect(sess.first['source'], MediaSession.kSrcManual, reason: '补记＝manual，不是计时');
    final txnId = sess.first['txn_id'] as int?;
    expect(txnId, isNotNull, reason: '补记必须同场落 L4 块，不能只写会话表');
    final blocks = await db.query(core.tTimeBlocks);
    expect(blocks.length, 1);
    expect(blocks.first['id'], txnId, reason: '会话的 txn_id 指向这条块');
    expect(blocks.first['category'], '娱乐');
    expect(blocks.first['cat_id'], 5, reason: '分类种子 id 固定＝娱乐');
    expect(blocks.first['note'], '补记片');
    // 块时段＝补记那 45 分钟（起点走 DateTime.now() 不可钉死，改核区间长度；
    // 跨零点时 start_min 按未同日口径落 0，区间长度即 end_min 本身）
    final startMin = blocks.first['start_min'] as int;
    final endMin = blocks.first['end_min'] as int;
    expect(startMin == 0 ? endMin : endMin - startMin, 45, reason: '块时段＝补记时长');

    // UI 侧同步：空态退场、行入列、汇总与条数跟上
    expect(find.byKey(const ValueKey('mds-sess-empty')), findsNothing);
    expect(rowKeys(tester), ['mds-sess-${sess.first['id']}']);
    expect(stat('累计', mdsHm(45)), findsOneWidget);
    expect(find.text('共 1 次'), findsOneWidget);
  });

  testWidgets('行内改走 updateSessionDetail：倍速入列、L4 块差量改不新建；删行走 deleteSession 并同删块',
      (tester) async {
    await useSurface(tester, const Size(420, 1400));
    final id = await addItem('改删片', durationMin: 200);
    final start = DateTime(2026, 3, 8, 20);
    // 用写口落初值：本组要验的是「改不新建块／删同删块」，初值必须已带块
    final s = await repo.addManualDetail(
      itemId: id,
      kind: MediaItem.kMovie,
      startedAtMs: start.millisecondsSinceEpoch,
      minutes: 30,
    );
    await pumpSesslog(tester, id);

    // —— 行内改：30 → 90 分钟，倍速 1.5
    await tester.tap(find.byKey(ValueKey('mds-sess-${s.id}')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('mds-sess-edit')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('mds-sess-min')), '90');
    await tester.tap(find.byKey(const ValueKey('mds-sess-spd-1.5')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('mds-sess-save')));
    await settle5(tester);

    final edited = (await db.query(md.tMediaSessions)).single;
    expect(edited['minutes'], 90);
    expect(edited['speed'], 1.5);
    expect(edited['ended_at'], start.add(const Duration(minutes: 90)).millisecondsSinceEpoch);
    expect(edited['txn_id'], s.txnId, reason: '差量写口沿用同一条块（洗成新块＝账本错位）');
    final kept = (await db.query(core.tTimeBlocks)).single;
    expect(kept['id'], s.txnId);
    expect(kept['start_min'], 20 * 60);
    expect(kept['end_min'], 21 * 60 + 30, reason: '块时段跟着重排（20:00 起 90 分钟＝21:30）');
    // 折算侧：真实 90、倍速 1.5 ＝ 135
    expect(stat('累计', mdsHm(90)), findsOneWidget);
    expect(stat('折算', mdsHm(135)), findsOneWidget);

    // —— 删除：会话行与块同一写口同删
    await tester.tap(find.byKey(ValueKey('mds-sess-${s.id}')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('mds-sess-del')));
    await settle5(tester);
    expect(await db.query(md.tMediaSessions), isEmpty);
    expect(await db.query(core.tTimeBlocks), isEmpty, reason: 'L12：删会话联动删流水');
    expect(find.byKey(const ValueKey('mds-sess-empty')), findsOneWidget);
    expect(find.text('共 0 次'), findsOneWidget);
  });
}
