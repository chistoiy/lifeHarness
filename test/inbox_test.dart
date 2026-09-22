import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/features/inbox/data/inbox_dao.dart';
import 'package:lifeharness/features/inbox/domain/inbox_item.dart';
import 'package:lifeharness/features/inbox/presentation/inbox_page.dart';
import 'package:lifeharness/features/inbox/presentation/inbox_providers.dart';
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/data/note_dao.dart';
import 'package:lifeharness/features/journal/domain/journal_repository.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/domain/book_quote.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late InboxDao inbox;
  late TodoRepository todoRepo;
  late JournalRepository journalRepo;
  late NoteDao noteDao;
  late EventBus bus;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    bus = EventBus();
    inbox = InboxDao(db);
    todoRepo = TodoRepository(TodoDao(db), bus);
    journalRepo = JournalRepository(JournalDao(db));
    noteDao = NoteDao(db);
  });

  tearDown(() async {
    await db.close();
    await bus.dispose();
  });

  ProviderScope scope() => ProviderScope(
        overrides: [
          inboxDaoProvider.overrideWithValue(inbox),
          todoRepositoryProvider.overrideWithValue(todoRepo),
          journalRepositoryProvider.overrideWithValue(journalRepo),
          noteDaoProvider.overrideWithValue(noteDao),
          readRepositoryProvider.overrideWithValue(ReadRepository(db)),
        ],
        child: const MaterialApp(home: InboxPage()),
      );

  group('InboxItem/InboxDao', () {
    test('ageLabel：刚刚 / N 分钟前 / 今天 HH:MM / N 天前', () {
      final now = DateTime(2026, 9, 20, 12, 0);
      String age(Duration before) => InboxItem(
              rawText: 'x', createdAt: now.subtract(before))
          .ageLabel(now);
      expect(age(const Duration(seconds: 10)), '刚刚');
      expect(age(const Duration(minutes: 30)), '30 分钟前');
      expect(age(const Duration(hours: 3)), '今天 09:00');
      expect(age(const Duration(days: 2, hours: 1)), '2 天前');
    });

    test('listPending 只列未整理；route 后消失', () async {
      final id = await inbox.insert(
          InboxItem(rawText: '想法A', createdAt: DateTime.now()));
      expect(await inbox.listPending(), hasLength(1));
      await inbox.route(id, 'todo', 9);
      expect(await inbox.listPending(), isEmpty);
    });
  });

  group('收集箱页（原型 p-inbox · L6 四向分流）', () {
    testWidgets('存入 → 卡片出现；空态文案', (tester) async {
      await tester.pumpWidget(scope());
      await tester.pumpAndSettle();
      expect(find.text('🎉 收集箱已清空，保持住！'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '买猫粮');
      await tester.tap(find.byKey(const ValueKey('inbox-add')));
      await tester.pumpAndSettle();

      expect(find.text('买猫粮'), findsOneWidget);
      expect(find.text('未整理 · 1'), findsOneWidget);
      expect(find.text('⚡ 已秒记入收集箱'), findsOneWidget);
    });

    testWidgets('→待办：建 q2 待办(tag=收集箱)并移出未整理', (tester) async {
      await inbox.insert(InboxItem(rawText: '预约牙医', createdAt: DateTime.now()));
      await tester.pumpWidget(scope());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('tri-→待办')));
      await tester.pumpAndSettle();

      final todos = await todoRepo.list();
      expect(todos.single.title, '预约牙医');
      expect(todos.single.quadrant, Quadrant.q2);
      expect(todos.single.tag, '收集箱');
      expect(await inbox.listPending(), isEmpty);
    });

    testWidgets('→日记：追加为今晚日记片段（📥 前缀）', (tester) async {
      await inbox.insert(InboxItem(rawText: '今晚晚霞是橘粉色的', createdAt: DateTime.now()));
      await tester.pumpWidget(scope());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('tri-→日记')));
      await tester.pumpAndSettle();

      final e = await journalRepo.byDay(DateTime.now());
      expect(e!.content, contains('📥 今晚晚霞是橘粉色的'));
      expect(await inbox.listPending(), isEmpty);
    });

    testWidgets('→笔记：写入 notes 表 folder=收集箱；✕ 删除', (tester) async {
      await inbox.insert(InboxItem(rawText: '一个长想法，需要展开写很多很多字的笔记素材啊', createdAt: DateTime.now()));
      await tester.pumpWidget(scope());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('tri-→笔记')));
      await tester.pumpAndSettle();
      final notes = await noteDao.list();
      expect(notes.single.folder, '收集箱');
      expect(notes.single.title.endsWith('…'), isTrue); // 超 20 字截断
      expect(await inbox.listPending(), isEmpty);
    });

    testWidgets('✕ 删除：直接丢弃', (tester) async {
      await inbox.insert(InboxItem(rawText: '待删', createdAt: DateTime.now()));
      await tester.pumpWidget(scope());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tri-✕')));
      await tester.pumpAndSettle();
      expect(await inbox.listPending(), isEmpty);
    });

    testWidgets('→摘录：无书提示条目保留；选书后落 book_quotes（origin=收集箱）',
        (tester) async {
      await inbox.insert(InboxItem(rawText: '摘录素材', createdAt: DateTime.now()));
      await tester.pumpWidget(scope());
      await tester.pumpAndSettle();

      // 书架为空：给出指引，条目保留。
      await tester.tap(find.byKey(const ValueKey('tri-→摘录')));
      await tester.pumpAndSettle();
      expect(find.textContaining('书架还没有书'), findsOneWidget);
      expect(await inbox.listPending(), hasLength(1));

      // 有一本书：选书 → 感想型摘录入账 · 条目打标 quote。
      final readRepo = ReadRepository(db);
      await readRepo.addBook(Book(
          id: 'ib1',
          title: '素材书',
          state: Book.kStateReading,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          updatedAt: DateTime.now().millisecondsSinceEpoch));
      await tester.tap(find.byKey(const ValueKey('tri-→摘录')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ibk-ib1')));
      await tester.pumpAndSettle();
      final qs = await readRepo.quotesOf('ib1');
      expect(qs, hasLength(1));
      expect(qs.single.origin, '收集箱');
      expect(qs.single.kind, BookQuote.kKindThought);
      expect(qs.single.thought, '摘录素材');
      expect(await inbox.listPending(), isEmpty);
    });
  });
}
