import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/features/calendar/data/event_dao.dart';
import 'package:lifeharness/features/calendar/domain/event_repository.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart';
import 'package:lifeharness/features/journal/data/diary_template_dao.dart';
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/domain/diary_template.dart';
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
          diaryTemplateDaoProvider.overrideWithValue(DiaryTemplateDao(db)),
          eventRepositoryProvider
              .overrideWithValue(EventRepository(EventDao(db), bus)),
        ],
        child: MaterialApp(home: home),
      );

  group('JournalRepository（M0 业务③）', () {
    test('V1.28 一天多篇：save 无 id=新增一篇；带 id=更新该篇', () async {
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
      expect(b.id, isNot(a.id)); // 新篇而非覆盖
      final all = await jrepo.list();
      expect(all, hasLength(2));
      final day = await jrepo.listByDay(DateTime(2026, 9, 20));
      expect(day.first.content, '改稿'); // 新→旧
      // 带 id 更新指定篇
      final a2 = await jrepo.save(a.copyWith(
          id: a.id, content: '初稿·改', mood: 5, updatedAt: DateTime.now()));
      expect(a2.id, a.id);
      expect(await jrepo.list(), hasLength(2));
      final re = await jrepo.open(a.id!);
      expect(re!.content, '初稿·改');
      expect(re.mood, 5);
    });

    test('V1.28 结构化篇：分节落 journal_sections + content 快照 + 重写', () async {
      final saved = await jrepo.save(JournalEntry(
          day: DateTime(2026, 9, 20),
          templateId: 1,
          sections: const [
            DiarySection(title: '感恩 ①', body: '阳光'),
            DiarySection(title: '感恩 ②', body:'☐ 买牛奶'),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      final open = await jrepo.open(saved.id!);
      expect(open!.sections.map((s) => s.title), ['感恩 ①', '感恩 ②']);
      expect(open.content, contains('## 感恩 ①\n阳光'));
      // 快照里的 ☐ 行仍可被 L3 解析
      expect(open.todoLines(), contains('买牛奶'));
      // 更新：分节重写不残留
      final upd = await jrepo.save(saved.copyWith(
          sections: const [DiarySection(title: '感恩 ①', body: '晚风')],
          updatedAt: DateTime.now()));
      expect(upd.id, saved.id);
      final again = await jrepo.open(saved.id!);
      expect(again!.sections, hasLength(1));
      expect(again.sections.first.body, '晚风');
    });

    test('V1.28 模板 DAO：内置种子 2 套 + 自定义增删', () async {
      final dao = DiaryTemplateDao(db);
      final list = await dao.list();
      expect(list, hasLength(2));
      expect(list.every((t) => t.builtin), isTrue);
      expect(list.first.sections, hasLength(3));
      final id = await dao.create(const DiaryTemplate(name: '每日三省', sections: [
        TemplateSection(title: '早晨问自己'),
        TemplateSection(title: '晚间问自己'),
      ]));
      final all = await dao.list();
      expect(all, hasLength(3));
      final custom = all.firstWhere((t) => t.id == id);
      expect(custom.builtin, isFalse);
      expect(custom.sections, hasLength(2));
      await dao.remove(id);
      expect(await dao.list(), hasLength(2));
    });

    test('setMoodOfDay（V1.28）：已有正文篇则新增仅心情篇；再点更新空白篇不叠加（L4）', () async {
      await jrepo.save(JournalEntry(
          day: DateTime.now(),
          content: '正文保留',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await jrepo.setMoodOfDay(DateTime.now(), 3);
      var entries = await jrepo.listByDay(DateTime.now());
      expect(entries, hasLength(2));
      expect(entries.first.mood, 3); // 最新=仅心情篇
      expect(entries.first.content, '');
      expect(entries.last.content, '正文保留'); // 原篇不动
      await jrepo.setMoodOfDay(DateTime.now(), 4); // 复用空白篇
      entries = await jrepo.listByDay(DateTime.now());
      expect(entries, hasLength(2));
      expect(entries.first.mood, 4);

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

      // V1.28 v6：模板/分节表 + template_id 列 + 内置种子
      for (final sql in DbSchema.migrations[5]!) {
        await db2.execute(sql);
      }
      final tpls = await db2.query('diary_templates');
      expect(tpls, hasLength(2));
      final secs = await db2.query('template_sections');
      expect(secs, hasLength(6));
      final cols =
          await db2.rawQuery('PRAGMA table_info(journal_entries)');
      expect(cols.map((c) => c['name']), contains('template_id'));
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

    testWidgets('V1.28 打开既有篇=回填+浏览计数；新建篇=空白且「第 N+1 篇」', (tester) async {
      final e1 = await jrepo.save(JournalEntry(
          day: DateTime.now(),
          content: '已有正文',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await tester.pumpWidget(scope(DiaryEditPage(key: UniqueKey(), entryId: e1.id)));
      await tester.pumpAndSettle();
      expect(find.text('已有正文'), findsOneWidget); // 编辑器回填
      expect(find.text('第 1 篇'), findsOneWidget);
      final re = await jrepo.open(e1.id!);
      expect(re!.viewCount, 1); // 打开累计浏览

      await tester.pumpWidget(scope(DiaryEditPage(key: UniqueKey())));
      await tester.pumpAndSettle();
      expect(find.text('第 2 篇'), findsOneWidget); // 写今天=新篇
      expect(find.text('已有正文'), findsNothing); // 不再覆盖旧篇
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

    testWidgets('V1.28 模板弹层：应用 KPT → 3 分节卡 · 保存 toast 含节数', (tester) async {
      // 加高视口：文档态 ListView 懒构建，保证模板行/分节卡/保存钮全部在树内。
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(scope(const DiaryEditPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('tpl-open-sheet')));
      await tester.pumpAndSettle();
      expect(find.text('📋 日记模板'), findsOneWidget);
      expect(find.byKey(const ValueKey('tpl-row-2')), findsOneWidget); // KPT 种子
      expect(find.byKey(const ValueKey('tpl-row-free')), findsOneWidget);
      expect(find.byKey(const ValueKey('tpl-del-1')), findsNothing); // 内置不可删
      expect(find.byKey(const ValueKey('tpl-del-2')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('tpl-row-2')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('sec-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('sec-2')), findsOneWidget);
      expect(find.textContaining('3 节 · 各节独立保存'), findsOneWidget);
      expect(find.text('📋 模板：KPT 复盘 ▾'), findsOneWidget);

      await tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey('sec-0')),
              matching: find.byType(TextField)),
          '坚持了晨跑');
      await tester.tap(find.byKey(const ValueKey('diary-save')));
      // 单帧即可：toast 1600ms 自动消失，pumpAndSettle 会推进过其生命周期。
      await tester.pump();
      expect(find.textContaining('第 1 篇 · KPT 复盘（3 节）'), findsOneWidget);
      await tester.pumpAndSettle();

      final day = await jrepo.listByDay(DateTime.now());
      expect(day.first.sections, hasLength(3));
      expect(day.first.sections.first.body, '坚持了晨跑');
      expect(day.first.content, contains('## Keep · 做对了什么\n坚持了晨跑'));
    });
  });
}

String _two(int v) => v.toString().padLeft(2, '0');
