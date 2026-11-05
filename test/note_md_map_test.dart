import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/journal/data/note_dao.dart';
import 'package:lifeharness/features/journal/data/note_folder_dao.dart';
import 'package:lifeharness/features/journal/domain/note.dart';
import 'package:lifeharness/features/journal/domain/note_outline.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/journal/presentation/note_edit_page.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 笔记「导图」视图（md 结构 → 横向树只读视图）。
///
/// 覆盖两件事：① 解析口径（标题定主干、列表挂标题下、跳级归祖先、行内标记
/// 剥离、代码围栏整块跳过）；② 顶行第三枚视图钮的落位与切换行为。
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
        child: MaterialApp(home: home),
      );

  Future<int> seed(String content, {String kind = 'md'}) async {
    final n = await dao.save(Note(
      title: '资治通鉴',
      content: content,
      kind: kind,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    return n.id!;
  }

  group('解析口径（笔记 md → 大纲）', () {
    test('① 标题定主干、列表挂到当前标题下（笔记正文的主体形态）', () {
      final root = parseNoteOutline('''
## 开篇总纲
- 天子命韩虔、赵籍、魏斯为诸侯
- 名分、礼器不可假人
## 一、智氏兴衰
- 智宣子择嗣
- 智瑶五贤
''', rootTitle: '资治通鉴');

      expect(root.title, '资治通鉴');
      expect(root.children.map((c) => c.title).toList(), ['开篇总纲', '一、智氏兴衰'],
          reason: '两层 `##` 都挂在中心主题下（层级相对首个标题归一）');
      expect(root.children.first.children.length, 2,
          reason: '列表项挂到「当前标题」下，不是与标题并列成根');
      expect(root.count, 7, reason: '根 1 ＋ 两标题 ＋ 四条列表项');
    });

    test('② 层级跳级归最近祖先，不凭空造父', () {
      final root = parseNoteOutline('# A\n### C\n', rootTitle: 'R');
      final a = root.children.single;
      expect(a.title, 'A');
      expect(a.children.single.title, 'C',
          reason: '`###` 前只有 `#`，中间缺失的一级按最近可见祖先降层挂靠');
    });

    test('③ 行内标记剥离、代码围栏整块跳过', () {
      final root = parseNoteOutline('''
## **粗体** 与 [链接](https://x)
- `行内码` 与 ~~删除~~
```
- 围栏里的行不是结构
```
- 围栏外的一条
''', rootTitle: 'R');
      final h = root.children.single;
      expect(h.title, '粗体 与 链接', reason: '节点标题只留文字');
      expect(h.children.map((c) => c.title).toList(), ['行内码 与 删除', '围栏外的一条'],
          reason: '围栏内的 `- ` 行不产生节点');
    });

    test('④ 纯段落（无标题无列表）也入图，一段一枚节点', () {
      final root = parseNoteOutline('第一段\n\n第二段\n', rootTitle: 'R');
      expect(root.children.map((c) => c.title).toList(), ['第一段', '第二段']);
    });

    test('⑤ 根标题为空回落「未命名笔记」', () {
      expect(parseNoteOutline('## A', rootTitle: '  ').title, '未命名笔记');
    });
  });

  group('顶行第三枚视图钮', () {
    testWidgets('⑥ md 笔记：导图钮排在预览右侧，点开换视图、再点回落写作', (t) async {
      final id = await seed('## 甲\n- 乙\n- 丙');
      await t.pumpWidget(scope(NoteEditPage(noteId: id)));
      await t.pumpAndSettle();

      final viewBtn = find.byKey(const ValueKey('note-mode-view'));
      final mapBtn = find.byKey(const ValueKey('note-mode-map'));
      expect(mapBtn, findsOneWidget, reason: 'md 笔记顶行有导图钮');
      expect(t.getTopLeft(mapBtn).dx, greaterThan(t.getTopLeft(viewBtn).dx),
          reason: '落位＝预览按钮右边（产品指定位置）');

      expect(find.byKey(const ValueKey('note-title')), findsOneWidget,
          reason: '首屏是写作视图');
      await t.tap(mapBtn);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('body-map')), findsOneWidget,
          reason: '导图视图已上屏');
      expect(find.byKey(const ValueKey('note-title')), findsNothing,
          reason: '写作视图的正文标题框不参与导图视图');

      await t.tap(mapBtn);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('body-map')), findsNothing);
      expect(find.byKey(const ValueKey('note-title')), findsOneWidget,
          reason: '再点当前激活项＝回落写作视图');
    });

    testWidgets('⑦ 非 md 笔记不挂导图钮（导图只对 md 结构有意义）', (t) async {
      final id = await seed('正文', kind: 'plain');
      await t.pumpWidget(scope(NoteEditPage(noteId: id)));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('note-mode-map')), findsNothing);
      expect(find.byKey(const ValueKey('note-mode-view')), findsNothing);
    });
  });
}
