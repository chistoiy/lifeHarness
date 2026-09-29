import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/kits/data/kit_repository.dart';
import 'package:lifeharness/features/kits/domain/kit_models.dart';
import 'package:lifeharness/features/kits/presentation/kit_providers.dart';
import 'package:lifeharness/features/kits/presentation/kit_routes.dart';

/// V1.47 小工具批0 · 首页控制盘 widget 测试（网格/筛选/搜索/足迹落库）。
/// 独立文件防 isolate 污染；DB 走内存 ffi（与 habits_page_test 同法）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late KitRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = KitRepository(db);
  });
  tearDown(() => db.close());

  Future<void> pumpHome(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/kits',
      routes: [
        ShellRoute(builder: (_, _, child) => child, routes: kitShellRoutes()),
        ...kitPageRoutes(),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [kitRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle5(tester);
  }

  int tileCount(WidgetTester tester) =>
      find.byWidgetPredicate((w) => w.key.toString().contains('kit-tile-')).evaluate().length;

  group('1 · 首页骨架', () {
    testWidgets('标题 + 13 枚工具卡 + hero 四枚数据位', (tester) async {
      await useSurface(tester);
      await pumpHome(tester);
      expect(find.text('小工具合集'), findsWidgets);
      expect(find.text('本地轻工具 · 可插件拓展'), findsOneWidget);
      expect(tileCount(tester), 13);
      for (final m in ['total', 'week', 'fav', 'plug']) {
        expect(find.byKey(ValueKey('kit-hero-slot-$m')), findsOneWidget,
            reason: '数据位 $m 缺失');
      }
      expect(find.text('累计使用'), findsOneWidget);
      expect(find.text('近7天'), findsOneWidget);
      expect(find.text('已装插件'), findsOneWidget);
      await drainLogTimer(tester);
    });

    testWidgets('未使用过的工具显示「未用过」', (tester) async {
      await useSurface(tester);
      await pumpHome(tester);
      expect(find.text('未用过'), findsNWidgets(13));
      await drainLogTimer(tester);
    });
  });

  group('2 · 筛选与搜索', () {
    testWidgets('分类 chips 收窄到该分类', (tester) async {
      await useSurface(tester);
      await pumpHome(tester);
      await tester.tap(find.byKey(const ValueKey('kit-cat-network')));
      await settle5(tester);
      expect(tileCount(tester), 2);
      expect(find.text('Ping 工具'), findsOneWidget);
      expect(find.text('尺子'), findsNothing);
      await drainLogTimer(tester);
    });

    testWidgets('搜索命中名称与分类，无命中给空态', (tester) async {
      await useSurface(tester);
      await pumpHome(tester);
      await tester.enterText(find.byKey(const ValueKey('kit-search')), '色');
      await settle5(tester);
      expect(tileCount(tester), 2);
      await tester.enterText(find.byKey(const ValueKey('kit-search')), '不存在的工具');
      await settle5(tester);
      expect(tileCount(tester), 0);
      expect(find.textContaining('没有匹配的工具'), findsOneWidget);
      await drainLogTimer(tester);
    });

    testWidgets('隐藏项不进网格', (tester) async {
      await repo.setHidden(['speed', 'tele']);
      await useSurface(tester);
      await pumpHome(tester);
      expect(tileCount(tester), 11);
      expect(find.text('网络测速'), findsNothing);
      await drainLogTimer(tester);
    });
  });

  group('3 · 打开工具与足迹落库', () {
    testWidgets('点工具卡 → 写一条足迹并进工具屏', (tester) async {
      await useSurface(tester);
      await pumpHome(tester);
      await tester.tap(find.byKey(const ValueKey('kit-tile-ruler')));
      await settle5(tester);
      expect(find.text('尺子'), findsWidgets);
      expect(find.text('小工具合集 · 长度'), findsOneWidget);
      expect(find.textContaining('本地计算 · 抓包 0 请求'), findsOneWidget);
      final log = await repo.usage();
      expect(log.map((e) => e.tool), ['ruler']);
      await drainLogTimer(tester);
    });

    testWidgets('二次进入同一工具累计两条流水，卡片次数随之更新', (tester) async {
      await repo.logUse('pick');
      await useSurface(tester);
      await pumpHome(tester);
      expect(find.text('已用 1 次'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('kit-tile-pick')));
      await settle5(tester);
      expect((await repo.usage()).length, 2);
      await drainLogTimer(tester);
    });

    testWidgets('收藏位工具卡带 ★ 角标', (tester) async {
      await repo.setFavorites([kKitTools.first.key]);
      await useSurface(tester);
      await pumpHome(tester);
      expect(find.byIcon(Icons.star), findsOneWidget);
      await drainLogTimer(tester);
    });
  });

  group('4 · 长按收藏与编排（批1b）', () {
    List<String> tileKeys(WidgetTester tester) => tester
        .widgetList<GestureDetector>(find.byType(GestureDetector))
        .map((w) => w.key)
        .whereType<ValueKey<Object>>()
        .map((k) => '${k.value}')
        .where((s) => s.startsWith('kit-tile-'))
        .toList();

    testWidgets('长按卡片=收藏，再长按=取消', (tester) async {
      await useSurface(tester);
      await pumpHome(tester);
      expect(find.byIcon(Icons.star), findsNothing);
      await tester.longPress(find.byKey(const ValueKey('kit-tile-ping')));
      await settle5(tester);
      expect(await repo.favorites(), ['ping']);
      expect(find.text('已收藏 Ping 工具'), findsOneWidget);
      await clearToasts(tester);
      await tester.longPress(find.byKey(const ValueKey('kit-tile-ping')));
      await settle5(tester);
      expect(await repo.favorites(), isEmpty);
      expect(find.text('已取消收藏 Ping 工具'), findsOneWidget);
      await clearToasts(tester);
    });

    testWidgets('收藏满 6 个后长按给上限提示且不再增加', (tester) async {
      await repo.setFavorites(['ping', 'speed', 'ruler', 'dist', 'wheel', 'rand']);
      await useSurface(tester);
      await pumpHome(tester);
      await tester.longPress(find.byKey(const ValueKey('kit-tile-pick')));
      await settle5(tester);
      expect(find.textContaining('收藏最多 6 个'), findsOneWidget);
      expect(await repo.favorites(), hasLength(6));
      await clearToasts(tester);
    });

    testWidgets('编排生效：order 内的按 order 排，其余按默认序追加', (tester) async {
      await repo.setOrder(['tele', 'b64']);
      await useSurface(tester);
      await pumpHome(tester);
      final keys = tileKeys(tester);
      expect(keys.take(2), ['kit-tile-tele', 'kit-tile-b64']);
      expect(keys.length, 13);
      expect(keys.sublist(2).first, 'kit-tile-ping');
      await drainLogTimer(tester);
    });

    test('流水上限 600：超出裁最旧（原型同口径）', () async {
      for (var i = 0; i < 605; i++) {
        await db.insert(DbSchema.tKitUsage,
            {'tool': 'ping', 'ts': 1000 + i, 'kind': 'builtin'});
      }
      await repo.logUse('rand');
      final log = await repo.usage();
      // 605 条 ping + 1 条 rand = 606 → 裁到 600，最旧 6 条 ping 被剪掉。
      expect(log, hasLength(600));
      expect(log.first.tool, 'ping');
      expect(log.first.ts, 1006);
      expect(log.last.tool, 'rand');
      expect(await repo.recent(), hasLength(1), reason: 'recent 只留最新一枚工具键');
    });
  });
}
