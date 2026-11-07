/// C 案批1 · 旧「记录」四段深链退役守护（2026-11-07 产品拍板 C 案）。
///  ① `/journal?tab=book` 不再进四段页，落 `/readhub` 独立阅读页（标题「阅读」·无 ⇄ 钮）；
///  ② `?tab=diary` → `/diary`；`?tab=note` → `/notes`；无参/非法 → `/notes`；
///  ③ 独立页段只由路由锁定，页内无段切换状态（全局「上次停留段」已删）；
///  ④ 旧 ⇄ 菜单（rec-switch）与「记录 · X」标题都不出现在可达路由上；
///  ⑤ 源码级：仪表盘／DB 概览不再写 `?tab=` 旧深链（防复活）；
///  ⑥ 沿用：我的页「小工具合集」入口行已摘。
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

  /// 只挂 journal 域壳路由：验旧深链 → 兼容跳转 → 独立页这一段接线。
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

  group('旧记录页深链退役（C 案批1）', () {
    testWidgets('① ?tab=book 落独立阅读页：标题「阅读」·无 ⇄ 切换钮',
        (tester) async {
      await pumpRouter(tester, '/journal?tab=book');
      final page = tester.widget<JournalPage>(find.byType(JournalPage));
      expect(page.section, 'book');
      expect(find.text('阅读'), findsWidgets);
      expect(find.byKey(const ValueKey('rec-switch')), findsNothing,
          reason: '独立页不得再画右上角 ⇄ 切换钮（产品 2026-11-07 明令移除）');
      expect(find.text('记录 · 阅读'), findsNothing,
          reason: '标题不得再带「记录 · 」前缀');
      await settleLogTimer(tester);
    });

    testWidgets('② ?tab=diary 落独立日记页：标题「日记」·无 ⇄ 切换钮',
        (tester) async {
      await pumpRouter(tester, '/journal?tab=diary');
      expect(tester.widget<JournalPage>(find.byType(JournalPage)).section,
          'diary');
      expect(find.text('日记'), findsWidgets);
      expect(find.byKey(const ValueKey('rec-switch')), findsNothing);
      await settleLogTimer(tester);
    });

    testWidgets('③ ?tab=note 落独立笔记页：段由路由锁定',
        (tester) async {
      // 段只由路由锁定；页内不存在「上次停留段」这一态。
      await pumpRouter(tester, '/journal?tab=note');
      final page = tester.widget<JournalPage>(find.byType(JournalPage));
      expect(page.section, 'note');
      expect(find.text('笔记'), findsWidgets);
      expect(find.byKey(const ValueKey('rec-switch')), findsNothing);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('rec-switch')), findsNothing,
          reason: '微任务落定后也不许把旧四段菜单带回来');
      await settleLogTimer(tester);
    });

    testWidgets('④ 无参／非法段名一律落笔记页（不再有「沿用上次段」这一态）',
        (tester) async {
      await pumpRouter(tester, '/journal');
      expect(tester.widget<JournalPage>(find.byType(JournalPage)).section,
          'note');
      expect(find.text('笔记'), findsWidgets);
      expect(find.text('记录 · 日记'), findsNothing);
      await settleLogTimer(tester);

      await pumpRouter(tester, '/journal?tab=chat');
      expect(tester.widget<JournalPage>(find.byType(JournalPage)).section,
          'note');
      expect(find.byKey(const ValueKey('rec-switch')), findsNothing);
      await settleLogTimer(tester);
    });

    test('⑤ 旧 ?tab= 深链不得在两个入口文件里复活', () {
      for (final f in [
        'lib/features/dashboard/presentation/dashboard_page.dart',
        'lib/features/settings/presentation/db_overview_page.dart',
      ]) {
        final s = File(f).readAsStringSync();
        expect(s, isNot(contains('?tab=')),
            reason: '$f 又写回旧四段深链');
      }
    });

    test('⑥ 我的页「小工具合集」入口行已摘（入口只留全部功能宫格）', () {
      final s = File('lib/features/settings/presentation/settings_page.dart')
          .readAsStringSync();
      expect(s, isNot(contains("title: '小工具合集'")));
      expect(s, isNot(contains("context.go('/kits')")),
          reason: '设置页不得再留第二个小工具入口');
      // V1.58 小工具整模块下架：宫格里也不再有这一枚。
      final d = File('lib/features/dashboard/presentation/dashboard_page.dart')
          .readAsStringSync();
      expect(d, isNot(contains("'小工具'")));
    });
  });

  group('独立页本体（不经路由·单段壳）', () {
    testWidgets('笔记独立页：顶栏标题「笔记」·搜索钮在·切换钮不在',
        (tester) async {
      await tester.pumpWidget(
          wrap(const JournalPage(section: 'note')));
      await tester.pump();
      expect(find.text('笔记'), findsWidgets);
      expect(find.byKey(const ValueKey('rec-search')), findsOneWidget);
      expect(find.byKey(const ValueKey('rec-switch')), findsNothing);
      await settleLogTimer(tester);
    });
  });
}
