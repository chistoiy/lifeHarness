import 'helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/features/journal/data/note_dao.dart';
import 'package:lifeharness/features/journal/domain/note.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/journal/presentation/note_edit_page.dart';
import 'package:lifeharness/features/journal/presentation/note_tab.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// M1 批1a/1b/1c · 笔记列表与管理 + 编辑器（原型 recNote / p-noteEdit）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late NoteDao dao;
  late TodoRepository trepo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    dao = NoteDao(db);
    trepo = TodoRepository(TodoDao(db), EventBus());
  });

  tearDown(() async => db.close());

  ProviderScope scope(Widget home) => ProviderScope(
        overrides: [
          noteDaoProvider.overrideWithValue(dao),
          todoRepositoryProvider.overrideWithValue(trepo),
        ],
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
          find.byKey(const ValueKey('note-para-0')), '写作工具的第一要务');
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

  group('笔记编辑页（批1b · 四模式+快捷栏+字号纸色）', () {
    testWidgets('专注模式快捷栏=守卫 toast；切 MD源码 后 H 循环标题级、加粗包裹',
        (tester) async {
      await tester.pumpWidget(scope(const NoteEditPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('note-md-bold')));
      await tester.pump();
      expect(find.textContaining('当前为专注模式'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('note-mode-src')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('note-body')), '# 标题');
      await tester.tap(find.byKey(const ValueKey('note-md-h')));
      final ctl = tester
          .widget<TextField>(find.byKey(const ValueKey('note-body')))
          .controller!;
      expect(ctl.text, '## 标题');
      expect(await pollText(tester, '标题级别：h2（再点循环升级至 h6）'), isTrue);
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byKey(const ValueKey('note-md-bold')));
      await tester.pump();
      expect(ctl.text, '## 标题****'); // 空选区=在光标处插入成对标记
    });

    testWidgets('分屏：源码输入实时同步右侧预览区与字数', (tester) async {
      await tester.pumpWidget(scope(const NoteEditPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('note-mode-split')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('note-body')), '一二三四');
      await tester.pump();
      expect(find.text('一二三四'), findsWidgets); // 源码+预览两处
      expect(find.textContaining('4 字 · 约 1 分钟'), findsOneWidget);
    });

    testWidgets('纸色四选：切深夜米黑底墨色反转', (tester) async {
      await tester.pumpWidget(scope(const NoteEditPage()));
      await tester.pumpAndSettle();
      expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          const Color(0xFFFBF8F1));
      await tester.tap(find.byKey(const ValueKey('note-paper-3')));
      await tester.pumpAndSettle();
      expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          const Color(0xFF1E1D1B));
    });

    testWidgets('专注段落：空段成段·输入空行拆段·聚焦淡出其余段', (tester) async {
      final n = await dao.save(note('两段', content: '甲段\n\n乙段'));
      await tester.pumpWidget(scope(NoteEditPage(noteId: n.id)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('note-para-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('note-para-1')), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('note-para-0')), '丙段\n\n丁段');
      await tester.pump();
      expect(find.byKey(const ValueKey('note-para-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('note-para-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('note-para-2')), findsOneWidget); // 丙|丁|乙

      await tester.tap(find.byKey(const ValueKey('note-focus')));
      await tester.pump();
      expect(find.textContaining('聚焦模式：当前段高亮'), findsOneWidget);
      final dim = tester
          .widget<TextField>(find.byKey(const ValueKey('note-para-2')))
          .style!;
      expect(dim.color!.a, closeTo(.22, .01)); // 非当前段淡出
    });

    testWidgets('源码模式编辑后返回：内容落库', (tester) async {
      await tester.pumpWidget(scope(const NoteEditPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('note-mode-src')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('note-body')), '**克制**设计');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('note-back')));
      await tester.pumpAndSettle();
      final list = await dao.list();
      expect(list.single.content, '**克制**设计');
    });
  });

  group('笔记渲染层（批1c · MdView + ☑L3）', () {
    const blockTex = r'x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}';
    final rich = '# 论克制\n\n**写作工具**的第一要务，行内公式 \$E=mc^2\$ 与 '
        '`行内码`。\n\n- [ ] 回复邮件\n- [x] 自动保存\n\n'
        '| 模式 | 用途 |\n| --- | --- |\n| 专注 | 沉浸 |\n\n'
        '\$\$$blockTex\$\$\n\n> 纸会接住你\n\n~~删除线~~\n\n'
        '```\ncode block\n```\n';

    testWidgets('预览模式全要素渲染：标题/公式/表格/任务行/引用/代码块',
        (tester) async {
      final n = await dao.save(note('富文本', content: rich));
      await tester.pumpWidget(scope(NoteEditPage(noteId: n.id)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('note-mode-view')));
      await settle5(tester);

      expect(find.byKey(const ValueKey('md-view')), findsOneWidget);
      expect(find.byKey(const ValueKey('md-h1-论克制')), findsOneWidget);
      expect(find.byKey(const ValueKey('md-math-E=mc^2')), findsOneWidget); // 行内公式
      expect(find.byKey(const ValueKey('md-math-$blockTex')),
          findsOneWidget); // 块级公式 flutter_math_fork
      expect(find.byKey(const ValueKey('md-table')), findsOneWidget);
      expect(find.byKey(const ValueKey('md-pre-code block')), findsOneWidget);
      expect(find.text('☐'), findsOneWidget); // 未勾选任务行
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('md-task-1')),
              matching: find.text('☑')),
          findsOneWidget); // 已勾选任务行（避开快捷栏 ☑ 字面）
      expect(find.textContaining('回复邮件'), findsWidgets);
      expect(find.textContaining('纸会接住你'), findsOneWidget); // 引用
      expect(find.textContaining('删除线'), findsOneWidget); // 删除线
    });

    testWidgets('预览勾选 ☑ → 回写源码 - [x] 并联动 L3', (tester) async {
      final n =
          await dao.save(note('任务', content: '- [ ] 回复邮件\n- [ ] 买菜'));
      await tester.pumpWidget(scope(NoteEditPage(noteId: n.id)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('note-mode-view')));
      await settle5(tester);

      await tester.tap(find.byKey(const ValueKey('md-task-0')));
      expect(
          await pollText(tester, '已勾选 ☑ · 保存后同步至待办'), isTrue); // 无同名待办=提示保存同步
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.byKey(const ValueKey('note-mode-src')));
      await tester.pumpAndSettle();
      final ctl = tester
          .widget<TextField>(find.byKey(const ValueKey('note-body')))
          .controller!;
      expect(ctl.text, startsWith('- [x] 回复邮件'));
      expect(ctl.text, contains('- [ ] 买菜')); // 只翻第 0 个
    });

    testWidgets('返回保存：未勾选任务行 → 新待办（q2·tag 笔记）；已勾选不建',
        (tester) async {
      final n =
          await dao.save(note('任务', content: '- [ ] 整理书架\n- [x] 已办的'));
      await tester.pumpWidget(scope(NoteEditPage(noteId: n.id)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('note-back')));
      await settle5(tester);

      final todos = await trepo.list();
      expect(todos.map((t) => t.title), ['整理书架']);
      expect(todos.first.quadrant, Quadrant.q2);
      expect(todos.first.tag, '笔记');
    });
  });

  group('笔记快照与导出（批1d）', () {
    testWidgets('停输 30s 自动快照；🕘 弹层列表；恢复=新建副本不动当前稿',
        (tester) async {
      await tester.pumpWidget(scope(const NoteEditPage()));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('note-para-0')), '第一段完整的论述');
      await tester.pump(const Duration(milliseconds: 1200)); // 自动保存拿到 id
      await tester.pump(const Duration(seconds: 31)); // 停输 30s → 快照
      await tester.pump();

      final list = await dao.list();
      expect(list, hasLength(1));
      expect(await dao.snapshotsOf(list.single.id!), hasLength(1));

      await tester.tap(find.byKey(const ValueKey('note-snap-open')));
      await settle5(tester);
      expect(find.byKey(const ValueKey('snap-row-0')), findsOneWidget);
      expect(find.textContaining('恢复为副本不覆盖当前稿'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('snap-rest-0')));
      await settle5(tester);

      final after = await dao.list();
      expect(after, hasLength(2)); // 原稿 + 副本
      expect(after.map((e) => e.title), contains('未命名笔记（副本）'));
      expect(
          after.firstWhere((e) => !e.title.endsWith('（副本）')).content,
          '第一段完整的论述'); // 当前稿未被覆盖
    });

    testWidgets('每 +500 字 → 里程碑快照（不必等停输）', (tester) async {
      final n = await dao.save(note('长文', content: '起手'));
      await tester.pumpWidget(scope(NoteEditPage(noteId: n.id)));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('note-para-0')), '一' * 520);
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pump();
      expect(await dao.snapshotsOf(n.id!), hasLength(1));
    });

    testWidgets('快照比当前稿完整 → 打开时草稿提醒 toast', (tester) async {
      final n = await dao.save(note('断点', content: '只剩半句'));
      await dao.snapshot(n.id!, '前半句加后半句一共二十三个字刚刚好');
      await tester.pumpWidget(scope(NoteEditPage(noteId: n.id)));
      await tester.pumpAndSettle();
      expect(
          await pollText(tester,
              '🕘 有比当前更完整的快照（+13 字）· 可从版本快照恢复'),
          isTrue);
    });

    testWidgets('⋯ 导出弹层：复制全文（TXT）入剪贴板', (tester) async {
      final n = await dao.save(note('可复制', content: '全文内容在此'));
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await tester.pumpWidget(scope(NoteEditPage(noteId: n.id)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('note-export')));
      await settle5(tester);
      expect(find.byKey(const ValueKey('exp-md')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('exp-copy')));
      await settle5(tester);
      expect(copied, contains('全文内容在此'));
      expect(await pollText(tester, '已复制全文到剪贴板'), isTrue);
    });
  });
}
