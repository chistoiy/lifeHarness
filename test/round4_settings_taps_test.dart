import 'helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/calendar/data/category_dao.dart';
import 'package:lifeharness/features/calendar/data/event_dao.dart';
import 'package:lifeharness/features/calendar/data/time_block_dao.dart';
import 'package:lifeharness/features/calendar/domain/event_repository.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart';
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/domain/journal_repository.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/settings/presentation/settings_page.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:lifeharness/shared/linkage/stats_providers.dart'
    show shelfBookCountProvider;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 真机反馈轮4 批B③ 常驻回归（独立文件防 isolate 污染）：
/// 我的页统计三宫格与头像副标题行可点直达对应列表页。
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

  Future<void> pumpSettings(WidgetTester tester) async {
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      todoRepositoryProvider.overrideWithValue(TodoRepository(TodoDao(db), bus)),
      journalRepositoryProvider
          .overrideWithValue(JournalRepository(JournalDao(db))),
      readRepositoryProvider.overrideWithValue(ReadRepository(db)),
      eventRepositoryProvider
          .overrideWithValue(EventRepository(EventDao(db), bus)),
      timeBlockDaoProvider.overrideWithValue(TimeBlockDao(db)),
      categoryDaoProvider.overrideWithValue(CategoryDao(db)),
    ]);
    addTearDown(c.dispose);
    final router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
        GoRoute(
            path: '/todo',
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('STUB-todo')))),
        GoRoute(
            path: '/journal',
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('STUB-journal')))),
        GoRoute(
            path: '/read/shelf',
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('STUB-shelf')))),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c, child: MaterialApp.router(routerConfig: router)));
    await settle5(tester);
  }

  testWidgets('完成任务→待办清单页', (t) async {
    await pumpSettings(t);
    await t.tap(find.byKey(const ValueKey('stat-done')));
    await settle5(t);
    expect(find.text('STUB-todo'), findsOne);
  });

  testWidgets('连续记录天→记录页（日记）', (t) async {
    await pumpSettings(t);
    await t.tap(find.byKey(const ValueKey('stat-streak')));
    await settle5(t);
    expect(find.text('STUB-journal'), findsOne);
  });

  testWidgets('在册书籍→书架（push 保栈）', (t) async {
    await pumpSettings(t);
    await t.tap(find.byKey(const ValueKey('stat-books')));
    await settle5(t);
    expect(find.text('STUB-shelf'), findsOne);
  });

  testWidgets('头像下副标题行→记录页（日记）', (t) async {
    await pumpSettings(t);
    await t.tap(find.byKey(const ValueKey('profile-sub')));
    await settle5(t);
    expect(find.text('STUB-journal'), findsOne);
  });

  // 轮7（2026-10-04）：真机「我的 24 在册 vs 书架 6」——booksProvider 含
  // 垃圾箱软删行（trash_repository 依赖，不能改 its 语义），「在册」计数
  // 必须自行剔除 deleted_at 非空者。
  test('在册书籍数剔除软删行', () async {
    final now = DateTime(2026, 10, 4).millisecondsSinceEpoch;
    await db.insert('books',
        {'id': 'bk-a', 'title': '在册A', 'created_at': now, 'updated_at': now});
    await db.insert('books',
        {'id': 'bk-b', 'title': '在册B', 'created_at': now, 'updated_at': now});
    await db.insert('books', {
      'id': 'bk-c',
      'title': '垃圾箱里的',
      'created_at': now,
      'updated_at': now,
      'deleted_at': now - 86400000,
    });
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      readRepositoryProvider.overrideWithValue(ReadRepository(db)),
    ]);
    addTearDown(c.dispose);
    expect(await c.read(shelfBookCountProvider.future), 2);
  });
}
