import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/journal/data/note_dao.dart';
import 'package:lifeharness/features/journal/domain/note.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/journal/presentation/note_edit_page.dart';
import 'package:lifeharness/features/journal/presentation/note_tab.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// M1 批1a · 笔记列表与管理 + 基础编辑页（原型 recNote / p-noteEdit）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late NoteDao dao;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    dao = NoteDao(db);
  });

  tearDown(() async => db.close());

  ProviderScope scope(Widget home) => ProviderScope(
        overrides: [noteDaoProvider.overrideWithValue(dao)],
        child: MaterialApp(
            home: home is NoteTab ? Scaffold(body: home) : home),
      );

  Note note(String title,
          {String content = '正文', String? folder, bool pinned = false}) =>
      Note(
          title: title,
          content: content,
          folder: folder,
          pinned: pinned,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now());

  group('NoteDao（M1 批1a）', () {
    test('save 新建=分配 id；带 id=更新该篇', () async {
      final a = await dao.save(note('A'));
      expect(a.id, isNotNull);
      final b = await dao.save(a.copyWith(title: 'A·改'));
      expect(b.id, a.id);
      expect((await dao.list()).single.title, 'A·改');
    });

    test('list 排除归档与回收站；置顶优先；文件夹/搜索/字数排序', () async {
      await dao.save(note('写作', folder: '工作', content: '一二三四五'));
      await dao.save(note('读书', folder: '生活', pinned: true, content: '一二三'));
      final arch = await dao.save(note('归档件'));
      final trash = await dao.save(note('回收件'));
      await dao.setArchived(arch.id!, true);
      await dao.softDelete(trash.id!);

      final all = await dao.list();
      expect(all.map((n) => n.title).toList(), ['读书', '写作']); // 置顶优先
      expect((await dao.list(folder: '工作')).single.title, '写作');
      expect((await dao.list(query: '读')).single.title, '读书');
      expect(
          (await dao.list(sort: NoteSort.words)).map((n) => n.title).toList(),
          ['读书', '写作']); // 置顶仍优先，其后字数多在前
      expect((await dao.archived()).single.title, '归档件');
      expect((await dao.trash()).single.title, '回收件');
      expect(await dao.folders(), ['工作', '生活']);
    });

    test('回收站：恢复回列表；彻底删除连带快照；清空回收站', () async {
      final a = await dao.save(note('待删'));
      final b = await dao.save(note('待删2'));
      await dao.snapshot(a.id!, '旧稿');
      await dao.softDelete(a.id!);
      await dao.softDelete(b.id!);
      await dao.restore(a.id!);
      expect((await dao.list()).first.title, '待删'); // a 已恢复
      await dao.purge(a.id!);
      expect(await dao.snapshotsOf(a.id!), isEmpty); // 快照连带删
      await dao.emptyTrash();
      expect(await dao.trash(), isEmpty);
      expect((await dao.list()), isEmpty); // a 已 purge·b 已清空
    });

    test('v7 迁移：旧 notes 表升级后管理列与快照表可用', () async {
      await databaseFactoryFfiNoIsolate.deleteDatabase('ntest_v7.db');
      final db2 =
          await databaseFactoryFfiNoIsolate.openDatabase('ntest_v7.db');
      await db2.execute('''
        CREATE TABLE notes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT,
          content TEXT NOT NULL,
          kind TEXT NOT NULL DEFAULT 'plain',
          folder TEXT,
          pinned INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      await db2.insert('notes', {
        'title': '老笔记',
        'content': 'x',
        'created_at': 1,
        'updated_at': 1,
      });
      for (final sql in DbSchema.migrations[6]!) {
        await db2.execute(sql);
      }
      final rows = await db2.query('notes');
      expect(rows.single['archived'], 0);
      expect(rows.single['deleted_at'], isNull);
      final n = Note.fromRow(rows.single);
      expect(n.archived, isFalse);
      expect(n.deletedAt, isNull);
      await db2.insert('note_snapshots', {
        'note_id': 1,
        'content': 'snap',
        'created_at': 1
      });
      expect(await db2.query('note_snapshots'), hasLength(1));
      await db2.close();
    });
  });

  group('笔记 tab（原型 recNote）', () {
    testWidgets('渲染搜索行+chips+真实卡；长按移入回收站后列表清空', (tester) async {
      await dao.save(note('WebDAV 选型', folder: '工作', content: '坚果云应用密码模式'));
      await tester.pumpWidget(scope(const NoteTab()));
      await tester.pumpAndSettle();

      expect(find.text('✎ 写笔记'), findsOneWidget);
      expect(find.text('全部'), findsOneWidget);
      expect(find.text('🗑 回收站'), findsOneWidget);
      expect(find.textContaining('WebDAV 选型'), findsOneWidget);
      expect(find.textContaining('共 1 篇'), findsOneWidget);

      await tester.longPress(find.byKey(const ValueKey('note-card-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('🗑 移入回收站'));
      await tester.pumpAndSettle();
      expect(find.textContaining('WebDAV 选型'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('note-f-trash')));
      await tester.pumpAndSettle();
      expect(find.textContaining('WebDAV 选型'), findsOneWidget);
    });

    testWidgets('搜索过滤：不匹配时显空态', (tester) async {
      await dao.save(note('甲笔记'));
      await tester.pumpWidget(scope(const NoteTab()));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('note-search')), '乙');
      await tester.pumpAndSettle();
      expect(find.textContaining('甲笔记'), findsNothing);
      expect(find.textContaining('没有匹配'), findsOneWidget);
    });
  });

  group('笔记编辑页（原型 p-noteEdit · 批1a 基础形态）', () {
    testWidgets('新建：输入标题正文 → 返回即落库', (tester) async {
      await tester.pumpWidget(scope(const NoteEditPage()));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('note-title')), '论克制');
      await tester.enterText(
          find.byKey(const ValueKey('note-body')), '写作工具的第一要务');
      await tester.pump();
      expect(find.textContaining('12 字 · 约 1 分钟'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('note-back')));
      await tester.pumpAndSettle();

      final list = await dao.list();
      expect(list, hasLength(1));
      expect(list.single.title, '论克制');
      expect(list.single.content, '写作工具的第一要务');
    });

    testWidgets('打开既有：回填 + 置顶切换持久化', (tester) async {
      final n = await dao.save(note('已存在', content: '原稿'));
      await tester
          .pumpWidget(scope(NoteEditPage(noteId: n.id)));
      await tester.pumpAndSettle();
      expect(find.text('已存在'), findsWidgets); // 顶栏小标题+标题框
      expect(find.text('原稿'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('note-pin')));
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
      expect((await dao.byId(n.id!))!.pinned, isTrue);
    });
  });
}
