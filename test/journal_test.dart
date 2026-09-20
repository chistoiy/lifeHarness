import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/features/calendar/data/event_dao.dart';
import 'package:lifeharness/features/calendar/domain/event_repository.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart';
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/domain/journal_entry.dart';
import 'package:lifeharness/features/journal/domain/journal_repository.dart';
import 'package:lifeharness/features/journal/presentation/diary_edit_page.dart';
import 'package:lifeharness/features/journal/presentation/journal_page.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late JournalRepository jrepo;
  late TodoRepository trepo;
  late EventBus bus;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    bus = EventBus();
    jrepo = JournalRepository(JournalDao(db));
    trepo = TodoRepository(TodoDao(db), bus);
  });

  tearDown(() async {
    await db.close();
    await bus.dispose();
  });

  ProviderScope scope(Widget home) => ProviderScope(
        overrides: [
          journalRepositoryProvider.overrideWithValue(jrepo),
          todoRepositoryProvider.overrideWithValue(trepo),
          eventRepositoryProvider
              .overrideWithValue(EventRepository(EventDao(db), bus)),
        ],
        child: MaterialApp(home: home),
      );

  group('JournalRepository（M0 业务③）', () {
    test('save 新建后同日再 save = 更新（一天一篇）', () async {
      final a = await jrepo.save(JournalEntry(
          day: DateTime(2026, 9, 20),
          content: '初稿',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      expect(a.id, isNotNull);
      final b = await jrepo.save(JournalEntry(
          day: DateTime(2026, 9, 20),
          content: '改稿',
          mood: 2,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      expect(b.id, a.id);
      expect(await jrepo.list(), hasLength(1));
      final read = await jrepo.byDay(DateTime(2026, 9, 20));
      expect(read!.content, '改稿');
      expect(read.mood, 2);
    });

    test('setMoodOfDay：无条目建空文；有条目只更新心情不覆盖正文（L4）', () async {
      await jrepo.save(JournalEntry(
          day: DateTime.now(),
          content: '正文保留',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await jrepo.setMoodOfDay(DateTime.now(), 3);
      final e = await jrepo.byDay(DateTime.now());
      expect(e!.mood, 3);
      expect(e.content, '正文保留');

      await jrepo.setMoodOfDay(DateTime(2020, 1, 1), 5);
      final n = await jrepo.byDay(DateTime(2020, 1, 1));
      expect(n!.mood, 5);
      expect(n.content, '');
    });

    test('streak 连续记录天数（今天+昨天+前天=3，中断即止）', () async {
      final now = DateTime.now();
      for (var i = 0; i < 3; i++) {
        final d = now.subtract(Duration(days: i));
        await jrepo.save(JournalEntry(
            day: d, content: 'x', createdAt: now, updatedAt: now));
      }
      // 跳过 3 天前 → 4 天前再写一条不应计入。
      await jrepo.save(JournalEntry(
          day: now.subtract(const Duration(days: 4)),
          content: 'x',
          createdAt: now,
          updatedAt: now));
      expect(await jrepo.streak(), 3);
    });

    test('☐ 待办行与 #标签 解析', () async {
      final e = JournalEntry(
          day: DateTime.now(),
          content: '上午开会\n- ☐ 回复邮件\n☐ 约牙医\n\n#复盘 #运动',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now());
      expect(e.todoLines(), ['回复邮件', '约牙医']);
      expect(e.hashTags(), containsAll(['复盘', '运动']));
      final saved = await jrepo.save(e);
      expect(saved.tags, containsAll(['复盘', '运动']));
    });

    test('v5 迁移：旧表（无回望列）升级后默认值可读', () async {
      await databaseFactoryFfiNoIsolate.deleteDatabase('jtest_migration_v5.db');
      final db2 = await databaseFactoryFfiNoIsolate
          .openDatabase('jtest_migration_v5.db');
      await db2.execute('''
        CREATE TABLE journal_entries (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          entry_date INTEGER NOT NULL,
          mood INTEGER,
          content TEXT NOT NULL,
          tags TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      await db2.insert('journal_entries', {
        'entry_date': DateTime(2026, 9, 1).millisecondsSinceEpoch,
        'content': '老数据',
        'created_at': 1,
        'updated_at': 1,
      });
      for (final sql in DbSchema.migrations[4]!) {
        await db2.execute(sql);
      }
      final e = JournalEntry.fromRow((await db2.query('journal_entries')).first);
      expect(e.starred, isFalse);
      expect(e.liked, isFalse);
      expect(e.viewCount, 0);
      await db2.close();
    });
  });

  group('记录页（原型 p-records 日记 tab）', () {
    testWidgets('渲染四段 tab + 心情月历卡 + 写今天入口 + 真实条目卡', (tester) async {
      await jrepo.save(JournalEntry(
          day: DateTime.now(),
          mood: 2,
          content: '今天跑了 5 公里\n#运动',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await tester.pumpWidget(scope(const JournalPage()));
      await tester.pumpAndSettle();

      expect(find.text('📔 日记'), findsOneWidget);
      expect(find.text('📝 笔记'), findsOneWidget);
      expect(find.text('写今天的日记'), findsOneWidget);
      expect(find.textContaining('已记录 1 篇'), findsOneWidget);
      expect(find.textContaining('连续记录 1 天'), findsOneWidget);
      expect(find.textContaining('今天跑了 5 公里'), findsOneWidget);
      expect(find.text('#运动'), findsWidgets);

      // 其余 tab 占位。
      await tester.tap(find.text('📚 阅读'));
      await tester.pumpAndSettle();
      expect(find.textContaining('规划 V0.5'), findsWidgets);
    });

    testWidgets('INS 卡片流：点 ❤️ 落库 liked', (tester) async {
      final e = await jrepo.save(JournalEntry(
          day: DateTime.now(),
          content: '回望测试',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await tester.pumpWidget(scope(const JournalPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('📱 INS 卡片流'));
      await tester.pumpAndSettle();
      expect(find.text('CHIST · ${_two(DateTime.now().month)}-${_two(DateTime.now().day)}'),
          findsOneWidget);

      await tester.tap(find.byKey(ValueKey('ins-like-${e.id}')));
      await tester.pumpAndSettle();
      final after = await jrepo.byDay(DateTime.now());
      expect(after!.liked, isTrue);
    });
  });

  group('日记编辑页（原型 p-diaryEdit）', () {
    testWidgets('输入正文+选心情+☐ 行 → 保存落库并同步待办（L3）', (tester) async {
      await tester.pumpWidget(scope(const DiaryEditPage()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '晨会定了排期\n☐ 整理评审纪要');
      await tester.tap(find.byKey(ValueKey('jm-1'))); // 😌 平静
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -420));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('diary-save')));
      await tester.pumpAndSettle();

      final e = await jrepo.byDay(DateTime.now());
      expect(e, isNotNull);
      expect(e!.mood, 2);
      expect(e.content, contains('整理评审纪要'));

      final todos = await trepo.list();
      expect(todos.map((t) => t.title), contains('整理评审纪要'));
      expect(todos.first.quadrant, Quadrant.q2);
      expect(todos.first.tag, '日记');
    });

    testWidgets('再次打开同日 = 续写并累计浏览（view_count）', (tester) async {
      await jrepo.save(JournalEntry(
          day: DateTime.now(),
          content: '已有正文',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await tester.pumpWidget(scope(const DiaryEditPage()));
      await tester.pumpAndSettle();
      expect(find.text('已有正文'), findsOneWidget); // 编辑器回填

      final e = await jrepo.byDay(DateTime.now());
      expect(e!.viewCount, 1);
    });

    testWidgets('今日概览草稿（L2 真数据）：完成/未完成与日程行 + 插入正文', (tester) async {
      await trepo.add(Todo(title: '已完成任务', quadrant: Quadrant.q1, done: true));
      await trepo.add(Todo(title: '未完成任务', quadrant: Quadrant.q3));
      await tester.pumpWidget(scope(const DiaryEditPage()));
      await tester.pumpAndSettle();

      expect(find.textContaining('今日完成 1 · 未完成 1'), findsOneWidget);
      await tester.tap(find.text('插入正文 ↑'));
      await tester.pump();
      expect(find.textContaining('【今日概览 · 自动生成】'), findsOneWidget);
    });
  });
}

String _two(int v) => v.toString().padLeft(2, '0');
