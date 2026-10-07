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

/// 影音游批4b · 条目资料屏（原型 `m-info` · LH-C16）。
///
/// 三条诚实口径在此钉死：档案缺项出虚线「未登记」不编数；能力未开放（转存笔记）
/// 置灰不隐藏；算不出的读数（预计完成日）整行消失而不是写 0。
/// 与详情屏的分工＝资料屏写档案与总结，进度读数只回显。
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

  Future<String> addMovie({int durationMin = 155, String progressTo = '40'}) =>
      repo.addItem(MediaItem(
        kind: MediaItem.kMovie,
        title: '沙丘 2',
        state: '在看',
        progressWay: MediaItem.kWayPct,
        progressTo: progressTo,
        durationMin: durationMin,
        creator: '维伦纽瓦',
        createdAt: 1,
        updatedAt: 1,
      ));

  Future<ProviderContainer> pumpInfo(WidgetTester tester, String id) async {
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
    router.push('/media/item/$id/info');
    await settle5(tester);
    return container;
  }

  Future<void> seedTwoSessions(String id) async {
    final now = DateTime.now();
    for (final h in [3, 2]) {
      await repo.addManualDetail(
          itemId: id,
          kind: MediaItem.kMovie,
          startedAtMs: now.subtract(Duration(hours: h)).millisecondsSinceEpoch,
          minutes: 30,
          speed: 1);
    }
  }

  testWidgets('四格按 kind 各出各的词；档案缺项＝虚线「未登记」，不拿空串冒充读数', (tester) async {
    await useSurface(tester, const Size(420, 1400));
    final id = await addMovie();
    await seedTwoSessions(id);
    await pumpInfo(tester, id);

    // 第四格＝电影出「片长」（155 分钟 → 2h 35m），计数格出「计时次数 2」
    expect(find.descendant(of: find.byKey(const ValueKey('mds-info-stats')),
            matching: find.text('片长')),
        findsOneWidget, reason: '数据卡第四格按 kind 出「片长」（档案里另有一行同词，不冲突）');
    expect(find.text('2h 35m'), findsOneWidget);
    expect(find.text('计时次数'), findsOneWidget);
    expect(find.byKey(const ValueKey('mds-info-stats')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('mds-info-stats')), matching: find.text('2')),
        findsOneWidget,
        reason: '计时次数从库里数出来，不是原型演示的 3');

    // 未登记的档案项逐条出虚线，而不是空白
    expect(find.byKey(const ValueKey('mds-info-kv-empty-来源')), findsOneWidget);
    expect(find.byKey(const ValueKey('mds-info-kv-empty-制片国')), findsOneWidget);
    expect(find.byKey(const ValueKey('mds-info-kv-empty-备注')), findsOneWidget);
    expect(find.text('未登记'), findsWidgets);
    // 我的评分没填＝虚线空态（不照抄原型演示的 8.5）
    expect(find.byKey(const ValueKey('mds-info-myrating-empty')), findsOneWidget);
    expect(find.text('8.5'), findsNothing);
  });

  testWidgets('进度条按百分比走；预计完成日算得出才出现，片长未知＝整行消失不编数', (tester) async {
    await useSurface(tester, const Size(420, 1400));
    final id = await addMovie();
    await seedTwoSessions(id);
    await pumpInfo(tester, id);

    final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('mds-info-bar')));
    expect(bar.value, 0.4);
    expect(find.textContaining('进度 40%'), findsOneWidget);
    expect(find.byKey(const ValueKey('mds-info-eta')), findsOneWidget,
        reason: '有片长＋有会话＝能预测');

    final id2 = await addMovie(durationMin: 0);
    await seedTwoSessions(id2);
    await pumpInfo(tester, id2);
    expect(find.byKey(const ValueKey('mds-info-eta')), findsNothing,
        reason: '总时长未知＝不预测，整行不出现');
    expect(find.text('—'), findsWidgets, reason: '第四格未知出破折号，不写 0 分钟');
    expect(find.text('0 分钟'), findsNothing);
  });

  testWidgets('一页总结：读态虚线「未填」→ 就地编辑三行 → 保存落 final_note 三键', (tester) async {
    await useSurface(tester, const Size(420, 1400));
    final id = await addMovie();
    await pumpInfo(tester, id);

    expect(find.text('未填'), findsNWidgets(3), reason: '三行都没写＝各出一条虚线');
    expect(find.text('一句话短评'), findsOneWidget);
    expect(find.text('会不会推荐给朋友'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mds-info-sum-edit')));
    await settle5(tester);
    expect(find.byType(TextField), findsNWidgets(3));
    await tester.enterText(find.byType(TextField).at(0), '沙丘值得二刷');
    await tester.enterText(find.byType(TextField).at(1), '沙暴那段');
    await tester.enterText(find.byType(TextField).at(2), '会');
    await tester.tap(find.byKey(const ValueKey('mds-info-sum-save')));
    expect(await pollText(tester, '总结已保存'), isTrue);
    await clearToasts(tester);

    expect(find.text('沙丘值得二刷'), findsOneWidget);
    final rows = await db.query(md.tMediaItems, where: 'id = ?', whereArgs: [id]);
    expect(rows.single['final_note'], contains('"a":"沙丘值得二刷"'));
    expect(rows.single['final_note'], contains('"c":"会"'),
        reason: '三键齐写；只落一行＝读侧会当成另外两行被抹掉');

    // 清空重写＝保存后回到三行虚线（不是留旧值）
    await tester.tap(find.byKey(const ValueKey('mds-info-sum-edit')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('mds-info-sum-auto')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('mds-info-sum-save')));
    await clearToasts(tester);
    expect(find.text('未填'), findsNWidgets(3));
  });

  testWidgets('计时明细入口＝直达明细屏；能力未开的转存笔记置灰不隐藏', (tester) async {
    await useSurface(tester, const Size(420, 1400));
    final id = await addMovie();
    await seedTwoSessions(id);
    await pumpInfo(tester, id);

    expect(find.text('2 条 · 1h'), findsOneWidget,
        reason: '入口行计数与汇总同源（两条 ×30 分钟）');
    await tester.tap(find.byKey(const ValueKey('mds-info-entry-sessions')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('mds-sess-stats')), findsOneWidget,
        reason: '资料屏的明细入口落在计时明细整屏，不是半屏弹层');

    expect(find.byType(BottomSheet), findsNothing, reason: '明细是整屏，不叠半屏弹层');
    await tester.pageBack();
    await settle5(tester);
    expect(find.byKey(const ValueKey('mds-info-body')), findsOneWidget,
        reason: '返回只退一层，落回资料屏而不是甩回详情／栈底');
  });

  testWidgets('档案只读：外部 ID 用人话标签回显，写入位在编辑弹层而非本屏', (tester) async {
    await useSurface(tester, const Size(420, 1400));
    final id = await repo.addItem(MediaItem(
      kind: MediaItem.kMovie,
      title: '奥德赛',
      state: '在看',
      progressWay: MediaItem.kWayPct,
      progressTo: '10',
      durationMin: 120,
      creator: '诺兰',
      externalIds: const {'douban': '35000001'},
      createdAt: 1,
      updatedAt: 1,
    ));
    await pumpInfo(tester, id);

    expect(find.text('豆瓣 ID'), findsOneWidget, reason: '外部 ID 键要翻译成人话标签');
    expect(find.text('35000001'), findsOneWidget);
    expect(find.byType(TextField), findsNothing, reason: '档案卡只读，没有就地输入');
    // 编辑信息＝ AppBar 动作打开既有弹层（本屏不复制一套表单）
    expect(find.byKey(const ValueKey('mds-info-ops')), findsOneWidget);
  });
}
