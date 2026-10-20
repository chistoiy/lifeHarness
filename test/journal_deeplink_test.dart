/// V1.58 反馈轮5 · 记录页段深链用例（原型 index.html `D.grid` 阅读枚带第 4 位段名）。
///  ① 路由把 `?tab=` 查询参交给 JournalPage.initialTab；
///  ② 首帧即落在该段视图（标题随段 · 不再闪回日记段）；
///  ③ 段状态同步回 recordTabProvider，⇄ 菜单选段可覆盖深链；
///  ④ 无参/非法段名不改段（沿用上次停留）；
///  ⑤ 仪表盘宫格与「我的」页入口行的摘除在源码级钉住（防回归加回）。
library;

import 'dart:io';

import 'helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/journal/data/diary_template_dao.dart';
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/domain/journal_repository.dart';
import 'package:lifeharness/features/journal/presentation/journal_page.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/journal/presentation/journal_routes.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late EventBus bus;
  late ProviderContainer container;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    bus = EventBus();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [
      journalRepositoryProvider
          .overrideWithValue(JournalRepository(JournalDao(db))),
      todoRepositoryProvider.overrideWithValue(TodoRepository(TodoDao(db), bus)),
      diaryTemplateDaoProvider.overrideWithValue(DiaryTemplateDao(db)),
      sharedPreferencesProvider.overrideWithValue(prefs),
      // 阅读段真数据化后工作台要读库（与 journal_test 同款口径）。
      readRepositoryProvider.overrideWithValue(ReadRepository(db)),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    await bus.dispose();
  });

  /// 关动画：日记页 FAB 的呼吸环是无限循环动画，`pumpAndSettle` 会等不到静止。
  Widget wrap(Widget home) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: home,
        ),
      ));

  /// 只挂 journal 域壳路由：验查询参 → 构造参数这一段接线。
  Future<GoRouter> pumpRouter(WidgetTester tester, String url) async {
    final router = GoRouter(routes: journalShellRoutes());
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router)));
    router.go(url);
    // 转场中的页面尚未入树：推过 fade 动画再断言（禁 pumpAndSettle·工作台有异步读库）。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    return router;
  }

  group('记录页段深链（反馈轮5）', () {
    testWidgets('①  ?tab=book 落到阅读段：标题随段 · 日记段未构建', (tester) async {
      await pumpRouter(tester, '/journal?tab=book');
      expect(tester.widget<JournalPage>(find.byType(JournalPage)).initialTab,
          'book',
          reason: '路由未把查询参交给页面，宫格点了仍停默认段');
      expect(find.text('记录 · 阅读'), findsOneWidget);
      // §4c-2 后顶行三枚图标已整行移除，改用日记段 FAB 作「日记段是否构建」的探针
      // （日记段未构建 ⇒ 树上不会有这枚钮；其 key 仅在日记段 FAB 出现）。
      expect(find.byKey(const ValueKey('diary-fan-fab')), findsNothing,
          reason: '仍画日记段 = 深链没生效');

      // ③ 微任务落定后 provider 与视图同源：再推两帧不得回弹。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(container.read(recordTabProvider), 'book');
      expect(find.text('记录 · 阅读'), findsOneWidget);
      await settleLogTimer(tester);
    });

    testWidgets('③  菜单选段覆盖深链：选「日记」后标题与 provider 同步', (tester) async {
      await tester.pumpWidget(wrap(const JournalPage(initialTab: 'book')));
      await tester.pump();
      expect(find.text('记录 · 阅读'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('rec-switch')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('日记'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('记录 · 日记'), findsOneWidget);
      expect(container.read(recordTabProvider), 'diary',
          reason: '深链残留盖住用户选段 = 菜单失效');
      await settleLogTimer(tester);
    });

    testWidgets('④ 无段参不改段：停留段沿用（?tab 缺省 = 上次结果）', (tester) async {
      container.read(recordTabProvider.notifier).state = 'note';
      await pumpRouter(tester, '/journal');
      await tester.pump();
      expect(find.text('记录 · 笔记'), findsOneWidget);
      expect(container.read(recordTabProvider), 'note');
      await settleLogTimer(tester);
    });

    testWidgets('④ 非法段名忽略：?tab=chat 不炸也不改段', (tester) async {
      container.read(recordTabProvider.notifier).state = 'diary';
      await pumpRouter(tester, '/journal?tab=chat');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('记录 · 日记'), findsOneWidget);
      expect(container.read(recordTabProvider), 'diary');
      await settleLogTimer(tester);
    });

    // 清单 A-1：本文件原有一条「仪表盘宫格：日记/笔记摘除 · 阅读枚带段参」的源码级断言，
    // 与 `test/g2_entry_wiring_test.dart:36-45` 钉同一文件、同三条断言，且 g2 的正锚写得更完整
    // （含图标与 null 位），本条是其严格子集 → 删除，锚点唯一留在 g2（零覆盖损失）。
    // 提醒：若将来嫌 g2 的长锚太脆要改松，请**先删本文件这条历史注释、把断言搬回来**，别反过来。

    test('⑤ 我的页「小工具合集」入口行已摘（入口只留全部功能宫格）', () {
      final s =
          File('lib/features/settings/presentation/settings_page.dart')
              .readAsStringSync();
      expect(s, isNot(contains("title: '小工具合集'")));
      expect(s, isNot(contains("context.go('/kits')")),
          reason: '设置页不得再留第二个小工具入口');
      // V1.58 小工具整模块下架：宫格里也不再有这一枚。
      final d = File(
              'lib/features/dashboard/presentation/dashboard_page.dart')
          .readAsStringSync();
      expect(d, isNot(contains("'小工具'")));
    });
  });
}
