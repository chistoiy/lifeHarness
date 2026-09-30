import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/settings/settings_repository.dart';
import 'package:lifeharness/core/settings/user_settings.dart';
import 'package:lifeharness/features/kits/data/kit_repository.dart';
import 'package:lifeharness/features/kits/domain/kit_models.dart';
import 'package:lifeharness/features/kits/presentation/kit_providers.dart';
import 'package:lifeharness/features/kits/presentation/kit_routes.dart';

/// V1.47 批1a · 首页 hero 动作与弹层族（数据位草稿制 / 模块设置四开关 / 收藏上限 / 最近条）。
/// 独立文件防 isolate 污染；DB 走内存 ffi，prefs 走 mock。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late KitRepository repo;
  late ProviderContainer container;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = KitRepository(db);
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => db.close());

  Future<void> pumpHome(WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [
      kitRepositoryProvider.overrideWithValue(repo),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/kits',
      routes: [
        ShellRoute(builder: (_, _, child) => child, routes: kitShellRoutes()),
        ...kitPageRoutes(),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle5(tester);
  }

  group('1 · hero 动作区', () {
    testWidgets('两枚胶囊钮 + 四功能入口 + 状态行都在位', (tester) async {
      await useSurface(tester);
      await pumpHome(tester);
      expect(find.byKey(const ValueKey('kit-hero-cfg')), findsOneWidget);
      expect(find.byKey(const ValueKey('kit-hero-set')), findsOneWidget);
      for (final k in ['fav', 'recent', 'plug', 'stats']) {
        expect(find.byKey(ValueKey('kit-func-$k')), findsOneWidget, reason: '缺入口 $k');
      }
      expect(find.textContaining('今日 0 次'), findsOneWidget);
      expect(find.byKey(const ValueKey('kit-recent-strip')), findsNothing,
          reason: '无足迹时最近条整条不占位');
      await drainLogTimer(tester);
    });

    testWidgets('最近使用条：无记录不占位，用过即出现', (tester) async {
      await useSurface(tester);
      await repo.logUse('b64');
      await pumpHome(tester);
      expect(find.byKey(const ValueKey('kit-recent-strip')), findsOneWidget);
      expect(find.byKey(const ValueKey('kit-recent-tile-b64')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('kit-func-recent')));
      await settle5(tester);
      expect(find.byKey(const ValueKey('kit-recent-b64')), findsOneWidget);
      await drainLogTimer(tester);
    });

    testWidgets('清空足迹两段式：首点只武装，再点才落清空并提示', (tester) async {
      await useSurface(tester);
      await repo.logUse('pick');
      await pumpHome(tester);
      expect((await repo.usage()), hasLength(1));
      await tester.tap(find.text('清空足迹'));
      await settle5(tester);
      expect(find.text('再点一次确认'), findsOneWidget);
      expect((await repo.usage()), hasLength(1), reason: '首点不得清空');
      await tester.tap(find.text('再点一次确认'));
      await settle5(tester);
      expect((await repo.usage()), isEmpty);
      expect(await repo.recent(), isEmpty);
      await clearToasts(tester);
    });
  });

  group('2 · 数据位配置弹层（草稿保存制）', () {
    testWidgets('点选只改草稿：预览跟随，取消不落库，保存才落库', (tester) async {
      await useSurface(tester);
      await pumpHome(tester);
      await tester.tap(find.byKey(const ValueKey('kit-hero-cfg')));
      await settle5(tester);
      // 草稿里去掉默认第 2 枚（近7天），换成「今日」
      await tester.tap(find.byKey(const ValueKey('kit-cfg-week')));
      await settle5(tester);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('kit-cfg-preview')),
              matching: find.text('近7天')),
          findsNothing,
          reason: '预览区应即时移除近7天（下方指标库仍列着它）');
      await tester.tap(find.byKey(const ValueKey('kit-cfg-today')));
      await settle5(tester);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('kit-cfg-preview')),
              matching: find.text('今日')),
          findsOneWidget);
      await tester.tap(find.text('取消'));
      await settle5(tester);
      expect(await repo.heroSlots(), kKitHeroDefault);
      // 再来一次，这次保存
      await tester.tap(find.byKey(const ValueKey('kit-hero-cfg')));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('kit-cfg-week')));
      await tester.tap(find.byKey(const ValueKey('kit-cfg-today')));
      await settle5(tester);
      await tester.tap(find.text('保存'));
      await settle5(tester);
      expect(await repo.heroSlots(),
          [KitMetric.total, KitMetric.fav, KitMetric.plug, KitMetric.today]);
      await drainLogTimer(tester);
    });

    testWidgets('选满 4 枚后再点给行内提示且不落库（弹层内不挂 SnackBar）', (tester) async {
      await useSurface(tester);
      await pumpHome(tester);
      await tester.tap(find.byKey(const ValueKey('kit-hero-cfg')));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('kit-cfg-size')));
      await settle5(tester);
      expect(find.textContaining('最多 4 枚'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await tester.tap(find.text('取消'));
      await settle5(tester);
      await drainLogTimer(tester);
    });
  });

  group('3 · 模块设置弹层（四开关进 prefs）', () {
    testWidgets('四项默认值与原型一致', (tester) async {
      await useSurface(tester);
      await pumpHome(tester);
      final k = container.read(settingsControllerProvider).kit;
      expect(k, const TypeMatcher<KitSettings>());
      expect(k.scan, isTrue);
      expect(k.wifiCheck, isFalse);
      expect(k.backupPlugins, isTrue);
      expect(k.backupFootprint, isTrue);
      await tester.tap(find.byKey(const ValueKey('kit-hero-set')));
      await settle5(tester);
      for (final key in ['scan', 'wifi', 'backupPlugins', 'backupFootprint']) {
        expect(find.byKey(ValueKey('kit-set-$key')), findsOneWidget, reason: '缺开关 $key');
      }
      expect(find.text('插件中心'), findsOneWidget);
      await drainLogTimer(tester);
    });

    testWidgets('拨开关即写 prefs 并可读回（真持久化，非只改内存）', (tester) async {
      await useSurface(tester);
      await pumpHome(tester);
      await tester.tap(find.byKey(const ValueKey('kit-hero-set')));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('kit-set-wifi')));
      await settle5(tester);
      expect(container.read(settingsControllerProvider).kit.wifiCheck, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(SettingsRepository(prefs).load().kit.wifiCheck, isTrue);
      await tester.tap(find.text('完成'));
      await settle5(tester);
      await drainLogTimer(tester);
    });
  });

  group('4 · 收藏管理弹层', () {
    testWidgets('勾选→保存落库；超过 6 个给行内提示', (tester) async {
      await useSurface(tester);
      await pumpHome(tester);
      await tester.tap(find.byKey(const ValueKey('kit-func-fav')));
      await settle5(tester);
      for (final k in ['ruler', 'dist', 'wheel', 'rand', 'comp', 'datec']) {
        await tester.tap(find.byKey(ValueKey('kit-fav-$k')));
      }
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('kit-fav-pick')));
      await settle5(tester);
      expect(find.textContaining('最多收藏'), findsOneWidget);
      await tester.tap(find.text('保存'));
      await settle5(tester);
      expect(await repo.favorites(), ['ruler', 'dist', 'wheel', 'rand', 'comp', 'datec']);
      await drainLogTimer(tester);
    });

    testWidgets('↑↓ 调序只影响收藏行顺序', (tester) async {
      await repo.setFavorites(['ruler', 'dist']);
      await useSurface(tester);
      await pumpHome(tester);
      await tester.tap(find.byKey(const ValueKey('kit-func-fav')));
      await settle5(tester);
      await tester.tap(find.byIcon(Icons.arrow_downward).first);
      await settle5(tester);
      await tester.tap(find.text('保存'));
      await settle5(tester);
      expect(await repo.favorites(), ['dist', 'ruler']);
      await drainLogTimer(tester);
    });
  });
}
