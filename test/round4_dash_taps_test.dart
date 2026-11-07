import 'helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/calendar/data/category_dao.dart';
import 'package:lifeharness/features/calendar/data/time_block_dao.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart';
import 'package:lifeharness/features/dashboard/presentation/dashboard_page.dart';
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/domain/journal_repository.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 真机反馈轮4 批B② 常驻回归（独立文件防 isolate 污染）：
/// 首页 hero 数字与今日待办环卡可点直达对应列表页。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late SharedPreferences prefs;
  late EventBus bus;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    bus = EventBus();
  });

  tearDown(() async {
    await bus.dispose();
    await db.close();
  });

  Future<void> pumpDash(WidgetTester tester) async {
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      todoRepositoryProvider.overrideWithValue(TodoRepository(TodoDao(db), bus)),
      journalRepositoryProvider
          .overrideWithValue(JournalRepository(JournalDao(db))),
      readRepositoryProvider.overrideWithValue(ReadRepository(db)),
      timeBlockDaoProvider.overrideWithValue(TimeBlockDao(db)),
      categoryDaoProvider.overrideWithValue(CategoryDao(db)),
    ]);
    addTearDown(c.dispose);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const DashboardPage()),
        GoRoute(
            path: '/todo',
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('STUB-todo')))),
        GoRoute(
            path: '/calendar',
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('STUB-cal')))),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c, child: MaterialApp.router(routerConfig: router)));
    await settle5(tester);
  }

  testWidgets('待办数字→待办清单页', (t) async {
    await pumpDash(t);
    await t.tap(find.byKey(const ValueKey('hero-todo-tap')));
    await settle5(t);
    expect(find.text('STUB-todo'), findsOne);
  });

  testWidgets('场安排数字→日程页', (t) async {
    await pumpDash(t);
    await t.tap(find.byKey(const ValueKey('hero-plan-tap')));
    await settle5(t);
    expect(find.text('STUB-cal'), findsOne);
  });

  testWidgets('今日待办环卡整卡→待办清单页', (t) async {
    await pumpDash(t);
    await t.tap(find.byKey(const ValueKey('dash-todo-card')));
    await settle5(t);
    expect(find.text('STUB-todo'), findsOne);
  });
}
