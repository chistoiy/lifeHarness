import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema/media.dart' as md;
import 'package:lifeharness/features/media/data/media_repo_dict.dart';
import 'package:lifeharness/features/media/data/media_repository.dart';
import 'package:lifeharness/features/media/domain/media_item.dart';
import 'package:lifeharness/features/media/presentation/media_providers.dart';
import 'package:lifeharness/features/media/presentation/media_routes.dart';

import 'helpers.dart';

/// 影音游批3续 · 通用管理器屏（原型 `m-mgr` 五类实体一张屏）。
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
    repo = MediaRepository(db);
    // 三类各两条，且跨 kind（创作者「是枝裕和」同时有电影与剧集＝反查要跨类）
    for (final (kind, title, creator, source) in [
      (MediaItem.kMovie, '怪物', '是枝裕和', '豆瓣'),
      (MediaItem.kSeries, '重启人生', '坂元裕二', 'B 站'),
      (MediaItem.kMovie, '呼吸', '是枝裕和', 'IMDb'),
    ]) {
      final id = await repo.addItem(
        MediaItem(
          kind: kind,
          title: title,
          state: MediaItem.initialState(kind),
          progressWay: MediaItem.defaultWay(kind),
          creator: creator,
          source: source,
          tags: const ['日剧'],
          createdAt: 1,
          updatedAt: 1,
        ),
      );
      await repo.registerItemNames((await repo.itemById(id))!);
    }
  });
  tearDown(() => db.close());

  Future<void> pumpMgr(WidgetTester tester, {String? tab}) async {
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
    router.push(tab == null ? '/media/mgr' : '/media/mgr?tab=$tab');
    await settle5(tester);
  }

  testWidgets('五类 tab 一次看全；默认「来源」列出预置＋条目实际值', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    await pumpMgr(tester);
    for (final t in ['source', 'grp', 'creator', 'pub', 'tags']) {
      expect(find.byKey(ValueKey('mds-mgr-tab-$t')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('mds-mgr-row-豆瓣')), findsOneWidget);
    expect(find.byKey(const ValueKey('mds-mgr-row-自建')), findsOneWidget,
        reason: '预置 14 家也在名册里（不是只列条目用过的）');
    // 引用数逐行现算：豆瓣只有《怪物》在用＝1 条
    expect(
      tester.widget<ListTile>(find.byKey(const ValueKey('mds-mgr-row-豆瓣'))).subtitle,
      isNotNull,
    );
    expect(find.textContaining('1 条 · 点击反查'), findsWidgets);
  });

  testWidgets('切「创作者」＝引用数与条目同源；点行＝反查落架面只留命中', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    await pumpMgr(tester, tab: 'creator');
    await tester.tap(find.byKey(const ValueKey('mds-mgr-row-是枝裕和')));
    await settle5(tester);
    // 反查落点＝架面关键词口径，跨 kind 都能看见（两片同为电影，此处验架面在场＋搜索词带入）
    expect(find.byKey(const ValueKey('mds-search')), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('mds-search'))).controller?.text,
        '是枝裕和');
    expect(find.byKey(ValueKey('mds-card-${(await repo.itemIdsOf('creator', '是枝裕和')).first}')),
        findsOneWidget);
    // 非命中那条（坂元裕二的《重启人生》）不得出现在反查结果里
    expect(find.byKey(ValueKey('mds-card-${(await repo.itemIdsOf('creator', '坂元裕二')).first}')),
        findsNothing);
  });

  testWidgets('改名＝弹层就地输入，空值就地报错不借道提示条；确定后条目跟上', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    await pumpMgr(tester, tab: 'creator');
    await tester.tap(find.byKey(const ValueKey('mds-mgr-rename-坂元裕二')));
    await settle5(tester);
    // 对话框有入场缩放动画：多推两拍让 TextField 入树（settle5 在弹层里会早退）
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    // 先清成空格——直接点确定会带着预填原名「改名成功」把弹层关掉，测不到就地校验
    await tester.enterText(find.byKey(const ValueKey('mds-mgr-rename-input')), ' ');
    await tester.tap(find.byKey(const ValueKey('mds-mgr-rename-ok')));
    await settle5(tester);
    expect(find.text('请写新名字'), findsOneWidget);
    expect(find.byKey(const ValueKey('mds-mgr-rename-ok')), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing, reason: '校验落字段旁，不出提示条');
    await tester.enterText(find.byKey(const ValueKey('mds-mgr-rename-input')), '坂元');
    await tester.tap(find.byKey(const ValueKey('mds-mgr-rename-ok')));
    await settle5(tester);
    final id = (await repo.itemIdsOf('creator', '坂元')).single;
    expect((await repo.itemById(id))!.creator, '坂元');
    await clearToasts(tester);
  });

  testWidgets('删除引用守卫＝有在用条目只报数不动库；无引用才走二次确认', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    await repo.ensureDict('group', '周末档'); // 名册里的空名字（没被条目用）
    await pumpMgr(tester, tab: 'source');
    // 被占用：点删除＝一行读数，不弹确认、名册不动
    await tester.tap(find.byKey(const ValueKey('mds-mgr-del-豆瓣')));
    await settle5(tester);
    expect(find.textContaining('还有 1 条在册条目在用'), findsOneWidget);
    expect(find.byKey(const ValueKey('d-confirm-ok')), findsNothing);
    await clearToasts(tester);
    // 空闲名字：删除＝公共二次确认（LH-S31 唯一版式）
    await tester.tap(find.byKey(const ValueKey('mds-mgr-del-自建')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('d-confirm-ok')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('d-confirm-ok')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('mds-mgr-row-自建')), findsNothing);
    expect(await repo.deleteDict('source', '自建'), isFalse,
        reason: '名册里没有的名字不许谎报「已删除」');
    await clearToasts(tester);
  });

  testWidgets('标签类改名撞已有标签＝合并去重（名册读数是合并后的两页）', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    await repo.ensureDict('tag', '日剧');
    await repo.ensureDict('tag', '日劇');
    await pumpMgr(tester, tab: 'tags');
    await tester.tap(find.byKey(const ValueKey('mds-mgr-rename-日剧')));
    await settle5(tester);
    await tester.enterText(find.byKey(const ValueKey('mds-mgr-rename-input')), '日劇');
    await tester.tap(find.byKey(const ValueKey('mds-mgr-rename-ok')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('mds-mgr-row-日劇')), findsOneWidget);
    expect(find.byKey(const ValueKey('mds-mgr-row-日剧')), findsNothing);
    expect(find.textContaining('3 条 · 点击反查'), findsOneWidget);
    await clearToasts(tester);
  });
}
