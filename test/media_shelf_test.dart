import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lifeharness/core/database/schema/media.dart' as md;
import 'package:lifeharness/features/media/data/media_repository.dart';
import 'package:lifeharness/features/media/domain/media_item.dart';
import 'package:lifeharness/features/media/presentation/media_providers.dart';
import 'package:lifeharness/features/media/presentation/media_routes.dart';
import 'package:lifeharness/features/media/presentation/media_shelf_page.dart';
import 'package:lifeharness/features/media/presentation/media_workbench.dart';

import 'helpers.dart';

/// 影音游批2 · 影音架屏（工单执行面板第 3 项新增常驻用例）。
///
/// 独立文件＝全 app 点火类用例拆文件防 isolate 污染（AGENTS 门禁条）。
/// 数据面在 `media_dao_test.dart`，录入弹层在 `media_add_sheet_test.dart`。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late MediaRepository repo;
  final ids = <String, String>{};

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in md.mediaSchemaStatements) {
      await db.execute(sql);
    }
    repo = MediaRepository(db);
    ids.clear();
    // 四类各两条（面板第 3 项）：桌面视图应数得出 8 张卡。
    for (final (kind, title) in [
      (MediaItem.kMovie, '电影甲'),
      (MediaItem.kMovie, '电影乙'),
      (MediaItem.kSeries, '剧集甲'),
      (MediaItem.kSeries, '剧集乙'),
      (MediaItem.kMusic, '专辑甲'),
      (MediaItem.kMusic, '专辑乙'),
      (MediaItem.kGame, '游戏甲'),
      (MediaItem.kGame, '游戏乙'),
    ]) {
      ids[title] = await repo.addItem(MediaItem(
        kind: kind,
        title: title,
        state: MediaItem.initialState(kind),
        progressWay: MediaItem.defaultWay(kind),
        creator: '主创$title',
        createdAt: 1,
        updatedAt: 1,
      ));
    }
  });
  tearDown(() => db.close());

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget home, {
    String initialRoute = '/x',
  }) async {
    final container = ProviderContainer(
      overrides: [mediaRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: initialRoute,
      routes: [
        GoRoute(
          path: '/root',
          builder: (_, _) => const Scaffold(body: SizedBox.shrink()),
        ),
        GoRoute(path: '/x', builder: (_, _) => home),
        ...mediaPageRoutes(),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle5(tester);
    return container;
  }

  Finder cardsOnShelf() => find.byWidgetPredicate(
        (w) => w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('mds-card-'),
      );

  testWidgets('桌面视图＝8 张卡，四类各两条都在场', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    await pump(tester, const MediaShelfPage());
    expect(cardsOnShelf(), findsNWidgets(8));
    for (final title in ids.keys) {
      expect(
        find.byKey(ValueKey('mds-card-${ids[title]}')),
        findsOneWidget,
        reason: '架面缺卡：$title',
      );
    }
    // 类型 chip 角标＝在册计数（与数据面同源，不写死）
    expect(find.byKey(const ValueKey('mds-kind-movie')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mds-kind-all')),
        matching: find.text('全部 8'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('脊视图＝电影不出现，其余三类出现（刀2 钉这条判定）', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    await pump(tester, const MediaShelfPage());
    await tester.tap(find.byKey(const ValueKey('mds-view-spine')));
    await settle5(tester);
    for (final title in ['电影甲', '电影乙']) {
      expect(
        find.byKey(ValueKey('mds-spine-${ids[title]}')),
        findsNothing,
        reason: '电影没有侧脊，$title 不该出现在脊视图',
      );
    }
    for (final title in ['剧集甲', '剧集乙', '专辑甲', '专辑乙', '游戏甲', '游戏乙']) {
      expect(
        find.byKey(ValueKey('mds-spine-${ids[title]}')),
        findsOneWidget,
        reason: '脊视图少了 $title',
      );
    }
    expect(find.byKey(ValueKey('mds-spine-${ids['电影甲']}')), findsNothing);
  });

  testWidgets('类型 chip 选「电影」＝只剩两条；此时脊视图钮置灰点不动', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    await pump(tester, const MediaShelfPage());
    await tester.tap(find.byKey(const ValueKey('mds-kind-movie')));
    await settle5(tester);
    expect(cardsOnShelf(), findsNWidgets(2));
    // 点不动＝视图不切换（LH-K36 口径：置灰项点了不许静默改状态）
    await tester.tap(find.byKey(const ValueKey('mds-view-spine')));
    await settle5(tester);
    // 点不动＝视图不切换（LH-K36 口径）：判据用「桌面卡仍在场」，不去断脊视图里电影有没有——
    // 那条判定在脊视图本身就不画电影，拿它当「没切过去」的证据是空断言。
    expect(cardsOnShelf(), findsNWidgets(2), reason: '置灰钮被点动了＝视图切到脊');
    expect(find.text('电影无侧脊 · 请切桌面或列表视图'), findsNothing);
  });

  testWidgets('列表视图与搜索：关键词只留命中那条', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    await pump(tester, const MediaShelfPage());
    await tester.tap(find.byKey(const ValueKey('mds-view-list')));
    await settle5(tester);
    expect(find.byKey(ValueKey('mds-row-${ids['游戏甲']}')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('mds-search')), '专辑乙');
    await settle5(tester);
    expect(find.byKey(ValueKey('mds-row-${ids['专辑乙']}')), findsOneWidget);
    expect(find.byKey(ValueKey('mds-row-${ids['专辑甲']}')), findsNothing);
  });

  testWidgets('长按进管理态→删除走二次确认→软删后卡出列（不物理删）', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    await pump(tester, const MediaShelfPage());
    final id = ids['电影乙']!;
    await tester.longPress(find.byKey(ValueKey('mds-card-$id')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('mds-multi-bar')), findsOneWidget);
    expect(find.text('选中 1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mds-bulk-删除')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('d-confirm-ok')), findsOneWidget,
        reason: '破坏性动作必须给确认（LH-S31 全仓唯一版式）');
    await tester.tap(find.byKey(const ValueKey('d-confirm-ok')));
    await settle5(tester);
    await clearToasts(tester);
    expect(find.byKey(ValueKey('mds-card-$id')), findsNothing);
    expect(cardsOnShelf(), findsNWidgets(7));
    final row = (await db.query(
      md.tMediaItems,
      columns: ['deleted_at'],
      where: 'id = ?',
      whereArgs: [id],
    )).single;
    expect(row['deleted_at'], isNotNull, reason: '删除＝打标，行还在库里');
  });

  testWidgets('长按后点其它卡＝加选，取消管理态后不残留选中', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    await pump(tester, const MediaShelfPage());
    await tester.longPress(find.byKey(ValueKey('mds-card-${ids['游戏甲']}')));
    await settle5(tester);
    await tester.tap(find.byKey(ValueKey('mds-card-${ids['游戏乙']}')));
    await settle5(tester);
    expect(find.text('选中 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mds-manage')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('mds-multi-bar')), findsNothing);
  });

  testWidgets('记录页影音游 tab＝真实影音架入口＋四类计数（面板第 4 项回灌面）', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final router = GoRouter(
      initialLocation: '/root',
      routes: [
        GoRoute(
          path: '/root',
          builder: (_, _) => const Scaffold(body: MediaWorkbench()),
        ),
        ...mediaPageRoutes(),
      ],
    );
    final container = ProviderContainer(
      overrides: [mediaRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle5(tester);
    expect(find.byKey(const ValueKey('media-open-shelf')), findsOneWidget);
    // 占位文案不复活（本 tab 曾是「规划 V1.1」占位卡）
    expect(find.textContaining('与阅读同构'), findsNothing);
    expect(find.text('影音架'), findsWidgets, reason: '入口行与架面标题同名，此处只看在册计数');
    expect(find.text('在册 8'), findsOneWidget);
    expect(find.text('电影 2'), findsOneWidget);
    // 点入口＝直达架面（栈页走 push）
    await tester.tap(find.byKey(const ValueKey('media-open-shelf')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('mds-view-desk')), findsOneWidget);
  });
}
