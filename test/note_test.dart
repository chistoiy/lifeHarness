import 'dart:convert';
import 'dart:io';

import 'helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/journal/data/note_dao.dart';
import 'package:lifeharness/features/journal/data/note_folder_dao.dart';
import 'package:lifeharness/features/journal/domain/note.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/journal/presentation/note_edit_page.dart';
import 'package:lifeharness/features/journal/presentation/note_tab.dart';
import 'package:lifeharness/features/settings/presentation/recmg_page.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 1×1 有效 PNG（插图测试用真实可解码字节）。
const _png1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

class _FakeImagePicker extends ImagePickerPlatform {
  _FakeImagePicker(this.path);
  final String path;
  @override
  Future<XFile?> getImageFromSource(
          {required ImageSource source,
          ImagePickerOptions options = const ImagePickerOptions()}) async =>
      XFile(path);
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

/// M1 批1a/1b/1c · 笔记列表与管理 + 编辑器（原型 recNote / p-noteEdit）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late NoteDao dao;
  late TodoRepository trepo;
  late SharedPreferences prefs;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    dao = NoteDao(db);
    trepo = TodoRepository(TodoDao(db), EventBus());
    // V1.29批A4：恢复方式读 settingsControllerProvider，需 prefs 桩
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async => db.close());

  ProviderScope scope(Widget home) => ProviderScope(
        overrides: [
          noteDaoProvider.overrideWithValue(dao),
          noteFolderDaoProvider.overrideWithValue(NoteFolderDao(db)),
          todoRepositoryProvider.overrideWithValue(trepo),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
            home: home is NoteTab ? Scaffold(body: home) : home),
      );

  /// 经 NoteTab 元素拿到容器：切筛选/读视图状态（V1.29批A3 用例）。
  void mutate(WidgetTester tester, void Function(ProviderContainer c) fn) {
    fn(ProviderScope.containerOf(tester.element(find.byType(NoteTab))));
  }

  Note note(String title,
          {String content = '正文',
          String? folder,
          bool pinned = false,
          String kind = 'plain'}) =>
      Note(
          title: title,
          content: content,
          kind: kind,
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
          (await dao.list(sort: NoteSort.title)).map((n) => n.title).toList(),
          ['读书', '写作']); // 置顶仍优先，其后标题序
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

  group('笔记 tab（原型 recNote · V1.29轮6 重构）', () {
    testWidgets('无页内搜索与写笔记钮；精简卡；长按批量→删除入回收站；回收站长按恢复', (tester) async {
      await dao.save(note('WebDAV 选型', folder: '工作', content: '坚果云应用密码模式'));
      await tester.pumpWidget(scope(const NoteTab()));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('note-search')), findsNothing);
      expect(find.text('✎ 写笔记'), findsNothing);
      expect(find.textContaining('WebDAV 选型'), findsOneWidget);
      expect(find.textContaining('共 1 篇'), findsOneWidget);
      expect(find.textContaining('工作 · '), findsNothing); // 卡片已去目录/字数行

      // 长按=进入批量选择（toast 会盖住底部操作条，先让其退场）
      await tester.longPress(find.byKey(const ValueKey('note-card-1')));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('note-sel-bar')), findsOneWidget);
      expect(find.text('已选 1'), findsOneWidget);

      // 批量删除 → 回收站（toast 会临时盖住底部条，直接触发回调验证逻辑）
      tester.widget<TextButton>(find.byKey(const ValueKey('sel-del'))).onPressed!();
      await settle5(tester);
      expect((await dao.trash()).map((n) => n.title), ['WebDAV 选型']); // 先验 DB
      expect(find.textContaining('WebDAV 选型'), findsNothing); // 再验 UI

      // 回收站视图：长按=恢复
      mutate(tester, (c) => c.read(noteFilterProvider.notifier).state =
          (folder: kNoteTrash, sort: c.read(noteFilterProvider).sort));
      await tester.pumpAndSettle();
      expect(find.textContaining('WebDAV 选型'), findsOneWidget);
      await tester.longPress(find.byKey(const ValueKey('note-card-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('♻️ 恢复'));
      await tester.pumpAndSettle();
      expect((await dao.trash()), isEmpty);
    });

    testWidgets('排序菜单三方式（当前项✓）与视图循环 列表→2→3→4→列表', (tester) async {
      await dao.save(note('乙笔记'));
      await dao.save(note('甲笔记'));
      await tester.pumpWidget(scope(const NoteTab()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('note-sort')));
      await tester.pumpAndSettle();
      expect(find.text('最后修改 ↓'), findsOneWidget);
      expect(find.text('创建时间 ↓'), findsOneWidget);
      expect(find.text('标题 A→Z'), findsOneWidget);
      await tester.tap(find.text('标题 A→Z'));
      await tester.pumpAndSettle();
      expect(tester
          .widgetList<Widget>(find.byKey(const ValueKey('note-card-1')))
          .isNotEmpty, isTrue);

      // 视图循环
      int cols() => ProviderScope.containerOf(tester.element(find.byType(NoteTab)))
          .read(noteViewColsProvider);
      for (final _ in [1, 2, 3]) {
        await tester.tap(find.byKey(const ValueKey('note-view')));
        await tester.pumpAndSettle();
      }
      expect(cols(), 4);
      await tester.tap(find.byKey(const ValueKey('note-view')));
      await tester.pumpAndSettle();
      expect(cols(), 0);
    });

    testWidgets('左滑卡片 → 直接入回收站', (tester) async {
      await dao.save(note('滑动删除我'));
      await tester.pumpWidget(scope(const NoteTab()));
      await tester.pumpAndSettle();
      await tester.fling(find.byKey(const ValueKey('note-card-1')),
          const Offset(-400, 0), 1200);
      await tester.pump();
      await settle5(tester);
      expect((await dao.trash()).single.title, '滑动删除我');
    });

    testWidgets('文件夹树抽屉：顶层新建→点选目录（不关抽屉）→在其下建子夹', (tester) async {
      await tester.pumpWidget(scope(const NoteTab()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('note-folder')));
      await tester.pumpAndSettle();
      expect(find.text('文件夹'), findsOneWidget);
      expect(find.text('全部笔记'), findsOneWidget);
      expect(find.textContaining('添加文件夹 · 顶层'), findsOneWidget);

      // 顶层新建「灵感」
      await tester.tap(find.byKey(const ValueKey('nt-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('nt-name-input')), '灵感');
      await tester.tap(find.byKey(const ValueKey('nt-name-ok')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nt-灵感')), findsOneWidget);

      // 点选「灵感」=选中目录，抽屉保持打开，添加目标联动
      await tester.tap(find.byKey(const ValueKey('nt-灵感')));
      await tester.pumpAndSettle();
      expect(find.text('文件夹'), findsOneWidget); // 未关闭
      expect(find.textContaining('添加文件夹 · 灵感'), findsOneWidget);
      mutate(tester, (c) =>
          expect(c.read(noteFilterProvider).folder, '灵感'));

      // 在灵感下建子夹「工作」
      await tester.tap(find.byKey(const ValueKey('nt-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('nt-name-input')), '工作');
      await tester.tap(find.byKey(const ValueKey('nt-name-ok')));
      await tester.pumpAndSettle();
      final folders = await NoteFolderDao(db).list();
      final g = folders.firstWhere((f) => f.name == '灵感');
      final w = folders.firstWhere((f) => f.name == '工作');
      expect(w.parentId, g.id);
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
    testWidgets('停输 30s 自动快照；⋯ 笔记选项进快照；恢复(默认替换)=替换当前正文+替换前留快照',
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

      // 再改当前稿：恢复应把它替换回快照内容
      await tester.enterText(
          find.byKey(const ValueKey('note-para-0')), '改到一半的当前稿');
      await tester.pump(const Duration(milliseconds: 1200));

      // 头部 🕘 钮已收进 ⋯ 笔记选项（V1.29轮2②）
      expect(find.byKey(const ValueKey('note-snap-open')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('note-export')));
      await settle5(tester);
      expect(find.text('笔记选项'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('exp-snap')));
      await settle5(tester);
      expect(find.byKey(const ValueKey('snap-row-0')), findsOneWidget);
      expect(find.textContaining('恢复默认直接替换当前正文'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('snap-rest-0')));
      expect(await pollText(tester, '已恢复 · 当前正文已替换（替换前已留快照）'), isTrue);
      await tester.pump(const Duration(seconds: 2));
      await settle5(tester);
      await tester.pump(const Duration(milliseconds: 1200)); // 替换后自动保存

      final after = await dao.list();
      expect(after, hasLength(1)); // 替换模式不新增笔记
      expect(after.single.content, '第一段完整的论述');
      expect(await dao.snapshotsOf(after.single.id!), hasLength(2)); // 替换前自动留快照
    });

    testWidgets('记录管理切「新增为副本」后恢复=新建副本不动当前稿', (tester) async {
      final n = await dao.save(note('正主', content: '当前稿'));
      await dao.snapshot(n.id!, '旧稿内容');
      await tester.pumpWidget(scope(NoteEditPage(noteId: n.id)));
      await tester.pumpAndSettle();
      final container =
          ProviderScope.containerOf(tester.element(find.byType(NoteEditPage)));
      await container
          .read(settingsControllerProvider.notifier)
          .setNoteRestoreMode('copy');
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('note-export')));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('exp-snap')));
      await settle5(tester);
      expect(find.textContaining('恢复=新增一条副本笔记'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('snap-rest-0')));
      expect(await pollText(tester, '已恢复为一条副本笔记，当前正文不动'), isTrue);
      await tester.pump(const Duration(seconds: 2));
      await settle5(tester);

      final after = await dao.list();
      expect(after, hasLength(2)); // 原稿 + 副本
      expect(after.map((e) => e.title), contains('正主（副本）'));
      expect(
          after.firstWhere((e) => e.title == '正主').content, '当前稿'); // 当前稿未动
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

  group('V1.29批A4 · 段首退格并段 + 记录管理页', () {
    testWidgets('专注模式：光标在段首退格 → 与上一段合并并聚焦合并处', (tester) async {
      final n = await dao.save(note('两段', content: '甲段\n\n乙段'));
      await tester.pumpWidget(scope(NoteEditPage(noteId: n.id)));
      await tester.pumpAndSettle();

      // 直接置段2 光标于段首并聚焦（等价于用户退格键位前状态）
      final tf = tester
          .widget<TextField>(find.byKey(const ValueKey('note-para-1')));
      tf.focusNode!.requestFocus();
      tf.controller!.value = const TextEditingValue(
          text: '乙段', selection: TextSelection.collapsed(offset: 0));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('note-para-1')), findsNothing); // 两段并一段
      final merged = tester
          .widget<TextField>(find.byKey(const ValueKey('note-para-0')))
          .controller!;
      expect(merged.text, '甲段乙段');
      expect(merged.selection.baseOffset, 2); // 光标停在拼接处

      await tester.tap(find.byKey(const ValueKey('note-back')));
      await settle5(tester);
      expect((await dao.byId(n.id!))!.content, '甲段乙段');
    });

    testWidgets('段中有文本时退格不触发并段（正常删除）', (tester) async {
      final n = await dao.save(note('两段', content: '甲段\n\n乙段'));
      await tester.pumpWidget(scope(NoteEditPage(noteId: n.id)));
      await tester.pumpAndSettle();

      final tf = tester
          .widget<TextField>(find.byKey(const ValueKey('note-para-1')));
      final ctl = tf.controller!;
      tf.focusNode!.requestFocus();
      ctl.value = const TextEditingValue(
          text: '乙段', selection: TextSelection.collapsed(offset: 2));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('note-para-1')), findsOneWidget);
      expect(ctl.text, '乙');
    });

    testWidgets('记录管理页：五段分组渲染；nr-mode 行切换持久化', (tester) async {
      await useSurface(tester); // 五段较长，加高视口让懒构建全部入树
      await tester.pumpWidget(scope(const RecmgSettingsPage()));
      await tester.pumpAndSettle();

      for (final label in ['📔 日记', '📝 笔记', '📚 阅读', '🎬 影音游', '⚙️ 通用']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('回收站自动清理'), findsOneWidget);
      final container =
          ProviderScope.containerOf(tester.element(find.byType(RecmgSettingsPage)));
      expect(container.read(settingsControllerProvider).noteRestoreMode,
          'replace');

      await tester.tap(find.byKey(const ValueKey('nr-mode')));
      await tester.pumpAndSettle();
      expect(find.text('新增为副本'), findsOneWidget);
      expect(container.read(settingsControllerProvider).noteRestoreMode, 'copy');
      expect(prefs.getString('lh.note_restore_mode'), 'copy'); // 已持久化

      await tester.tap(find.byKey(const ValueKey('nr-mode')));
      await tester.pumpAndSettle();
      expect(find.text('直接替换正文'), findsOneWidget);
    });
  });

  group('V1.29批B · 富文本（flutter_quill · 原型 pwRichBar）', () {
    testWidgets('rich 新建：Quill 编辑器+九键工具栏；输入→Delta JSON 落库',
        (tester) async {
      await tester.pumpWidget(scope(const NoteEditPage(initialKind: 'rich')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('note-rich-editor')), findsOneWidget);
      for (final k in ['bold', 'ital', 'under', 'h', 'ul', 'task', 'img',
        'undo', 'redo']) {
        expect(find.byKey(ValueKey('note-rich-$k')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('note-md-h')), findsNothing); // MD 栏隐藏
      expect(find.byKey(const ValueKey('note-mode-focus')), findsNothing);

      final ctl = tester
          .widget<QuillEditor>(
              find.byKey(const ValueKey('note-rich-editor')))
          .controller;
      ctl.replaceText(0, 0, '富文本第一段', const TextSelection.collapsed(offset: 6));
      await tester.pump(const Duration(milliseconds: 1200)); // 自动保存

      final list = await dao.list();
      expect(list.single.kind, 'rich');
      expect(list.single.content, contains('"insert"')); // Delta JSON 存储
      expect(Note.richToPlain(list.single.content), contains('富文本第一段'));
      expect(list.single.preview, contains('富文本第一段')); // 列表预览无 JSON 痕迹
    });

    testWidgets('B 键加粗作用于选区；☑ 键循环 待办→已勾→清', (tester) async {
      await tester.pumpWidget(scope(const NoteEditPage(initialKind: 'rich')));
      await tester.pumpAndSettle();
      final ctl = tester
          .widget<QuillEditor>(
              find.byKey(const ValueKey('note-rich-editor')))
          .controller;
      ctl.replaceText(0, 0, '加粗我', const TextSelection.collapsed(offset: 3));
      ctl.replaceText(0, 0, '', const TextSelection(baseOffset: 0, extentOffset: 3));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('note-rich-bold')));
      await tester.pump();
      expect(jsonEncode(ctl.document.toDelta().toJson()), contains('"bold":true'));

      ctl.replaceText(3, 0, '', const TextSelection.collapsed(offset: 3));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('note-rich-task')));
      await tester.pump();
      expect(jsonEncode(ctl.document.toDelta().toJson()),
          contains('"list":"unchecked"'));
      await tester.tap(find.byKey(const ValueKey('note-rich-task')));
      await tester.pump();
      expect(jsonEncode(ctl.document.toDelta().toJson()),
          contains('"list":"checked"'));
      await tester.tap(find.byKey(const ValueKey('note-rich-task')));
      await tester.pump();
      expect(jsonEncode(ctl.document.toDelta().toJson()), isNot(contains('"list"')));
    });

    testWidgets('note-kind 三态循环 纯文本→MD→富文本→纯文本（内容往返不丢）',
        (tester) async {
      final n = await dao.save(note('三态', content: '正文在'));
      await tester.pumpWidget(scope(NoteEditPage(noteId: n.id)));
      await tester.pumpAndSettle();
      expect(find.text('🖊 纯文本'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('note-kind')));
      await tester.pumpAndSettle();
      expect(find.text('⌨️ MD'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('note-kind')));
      await tester.pumpAndSettle();
      expect(find.text('📝 富文本'), findsOneWidget);
      expect(find.byKey(const ValueKey('note-rich-editor')), findsOneWidget);
      // 纯文本被包成 Delta 文档
      final ctl = tester
          .widget<QuillEditor>(
              find.byKey(const ValueKey('note-rich-editor')))
          .controller;
      expect(ctl.document.toPlainText(), contains('正文在'));

      await tester.tap(find.byKey(const ValueKey('note-kind')));
      await tester.pumpAndSettle();
      expect(find.text('🖊 纯文本'), findsOneWidget);
      expect(find.byKey(const ValueKey('note-rich-editor')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('note-back')));
      await settle5(tester);
      expect((await dao.byId(n.id!))!.content, '正文在'); // 无 JSON 残留
    });

    test('Note.richToPlain：Delta JSON→纯文本；图片嵌入→🖼；非 JSON 容错回退', () {
      expect(
          Note.richToPlain(jsonEncode([
            {'insert': '甲\n'},
            {'insert': {'image': '/x/y.png'}},
            {'insert': '\n'},
          ])),
          '甲\n🖼\n');
      expect(Note.richToPlain('不是JSON'), '不是JSON');
    });

    testWidgets('快照恢复（rich）：替换=重建 Delta 文档；字数按纯文本计', (tester) async {
      final n = await dao.save(note('富稿',
          kind: 'rich',
          content: jsonEncode([
            {'insert': '旧版内容\n'}
          ])));
      await dao.snapshot(n.id!, jsonEncode([
        {'insert': '更完整的旧稿共十九个字啦\n'}
      ]));
      await tester.pumpWidget(scope(NoteEditPage(noteId: n.id)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('note-rich-editor')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('note-export')));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('exp-snap')));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('snap-rest-0')));
      expect(await pollText(tester, '已恢复 · 当前正文已替换（替换前已留快照）'), isTrue);
      await tester.pump(const Duration(seconds: 2));
      await settle5(tester);

      final ctl = tester
          .widget<QuillEditor>(
              find.byKey(const ValueKey('note-rich-editor')))
          .controller;
      expect(ctl.document.toPlainText(), contains('更完整的旧稿共十九个字啦'));
    });

    testWidgets('🖼 插图：相册弹层→拷贝 note_images→Delta image 嵌入并落库',
        (tester) async {
      final tmp = Directory.systemTemp.createTempSync('lh_img');
      final docs = Directory.systemTemp.createTempSync('lh_docs');
      addTearDown(() {
        tmp.deleteSync(recursive: true);
        docs.deleteSync(recursive: true);
      });
      File(p.join(tmp.path, 'a.png'))
          .writeAsBytesSync(base64Decode(_png1x1));
      ImagePickerPlatform.instance = _FakeImagePicker(p.join(tmp.path, 'a.png'));
      PathProviderPlatform.instance = _FakePathProvider(docs.path);

      await tester.pumpWidget(scope(const NoteEditPage(initialKind: 'rich')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('note-rich-img')));
      await settle5(tester);
      expect(find.byKey(const ValueKey('img-gallery')), findsOneWidget);
      expect(find.byKey(const ValueKey('img-camera')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('img-gallery')));
      await tester.pumpAndSettle(); // 弹层退场，续体推进到真实 IO 等待处
      // 图片拷贝是真实磁盘 IO：FakeAsync 帧循环不驱动它；交替
      // runAsync(真等) + pump(排 fake 微任务) 直到 toast 出现
      for (var i = 0;
          i < 10 &&
              find.textContaining('🖼 已插入图片').evaluate().isEmpty;
          i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.textContaining('🖼 已插入图片'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await settle5(tester);
      await tester.pump(const Duration(milliseconds: 1200)); // 自动保存

      final stored =
          Directory(p.join(docs.path, 'note_images')).listSync();
      expect(stored, hasLength(1)); // 已拷贝进应用目录
      final list = await dao.list();
      expect(list.single.content, contains('"image"'));
      expect(Note.richToPlain(list.single.content), contains('🖼')); // 预览无路径
    });
  });

  group('NoteFolderDao（V1.29 批A1 · 多层文件夹树）', () {
    late NoteFolderDao fdao;
    setUp(() => fdao = NoteFolderDao(db));

    test('create 顶层与子级；sort 同级顺延；list 全量', () async {
      final a = await fdao.create('方法论');
      final b = await fdao.create('灵感');
      final c = await fdao.create('工作', parentId: b.id);
      expect(a.parentId, isNull);
      expect(c.parentId, b.id);
      expect((await fdao.list()).map((f) => f.name).toList(),
          ['方法论', '工作', '灵感']); // 全局 sort,id：顶层 方法论1/灵感2，工作=灵感下同级1
      expect(a.sort, 1);
      expect(b.sort, 2); // 与方法论同为顶层·同级顺延
      expect(c.sort, 1); // 灵感下首子级
    });

    test('rename 改名；move 换父级', () async {
      final a = await fdao.create('旧名');
      final b = await fdao.create('另一夹');
      await fdao.rename(a.id!, '新名');
      await fdao.move(a.id!, b.id);
      final moved = (await fdao.list()).firstWhere((f) => f.name == '新名');
      expect(moved.parentId, b.id);
    });

    test('deleteTree：子夹上移到父级、本夹笔记 folder 置空、笔记不删', () async {
      final root = await fdao.create('灵感');
      await fdao.create('速记', parentId: root.id);
      await dao.save(note('夹内篇', folder: '灵感'));
      await dao.save(note('子夹篇', folder: '速记'));
      await fdao.deleteTree(root.id!);
      // 子夹上移（root 的 parentId=null → 子夹变顶层）
      final left = await fdao.list();
      expect(left.map((f) => f.name).toList(), ['速记']);
      expect(left.single.parentId, isNull);
      // root 内笔记 folder 置空；子夹笔记不动；都不被删除
      expect((await dao.byId((await dao.list(query: '夹内篇')).single.id!))!.folder,
          isNull);
      expect((await dao.list(query: '子夹篇')).single.folder, '速记');
    });

    test('subtreeNames 含全部后代；buildTree 组树+计数', () async {
      final a = await fdao.create('灵感');
      final b = await fdao.create('工作', parentId: a.id);
      await fdao.create('速记', parentId: b.id);
      expect(await fdao.subtreeNames(a.id!), {'灵感', '工作', '速记'});
      await dao.save(note('x', folder: '速记'));
      await dao.save(note('y', folder: '速记'));
      final tree = NoteFolderDao.buildTree(await fdao.list(),
          noteCounts: await dao.folderCounts());
      expect(tree.single.name, '灵感');
      final gong = tree.single.children.single;
      expect(gong.name, '工作');
      expect(gong.children.single.noteCount, 2);
    });
  });
}
