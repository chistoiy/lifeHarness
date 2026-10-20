import 'helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/journal/data/note_dao.dart';
import 'package:lifeharness/features/journal/data/note_folder_dao.dart';
import 'package:lifeharness/features/journal/domain/note.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/journal/presentation/note_edit_page.dart';
import 'package:lifeharness/features/journal/presentation/note_tab.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// 批1 顺滑（工单 docs/handoff/交棒话术-20261011-笔记模块结构与手感优化 §1）：
// ① 列表视图懒构建 ② 瀑布流高度按篇缓存 ③ 编辑页专注段懒构建 ④ 树底「展开/折叠」真双向。
// 独立文件（全 app pump 拆分铁律）；默认画布 800×600 ⇒ 懒构建的「可见项远少于总数」可观测。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late NoteDao dao;
  late SharedPreferences prefs;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    dao = NoteDao(db);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    kNoteEstComputeCount = 0; // 全局计数器：每例归零
  });
  tearDown(() async => db.close());

  ProviderScope scope(Widget home) => ProviderScope(
        overrides: [
          noteDaoProvider.overrideWithValue(dao),
          noteFolderDaoProvider.overrideWithValue(NoteFolderDao(db)),
          todoRepositoryProvider
              .overrideWithValue(TodoRepository(TodoDao(db), EventBus())),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
            home: home is NoteTab ? Scaffold(body: home) : home),
      );

  Note note(String title, {String content = '正文'}) => Note(
      title: title,
      content: content,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now());

  testWidgets('批1-① 列表视图懒构建：delegate＝builder（回退 children 全量建＝红）',
      (t) async {
    for (var i = 0; i < 120; i++) {
      await dao.save(note('第$i篇'));
    }
    await t.pumpWidget(scope(const NoteTab()));
    await t.pumpAndSettle();
    expect(find.byType(Dismissible), findsWidgets, reason: '首屏应有可见卡片');
    // 断言必须钉 **delegate 类型**：`find.byType` 默认 skipOffstage，ListView 缓存区
    // 子件不算 onstage ⇒ 数 Dismissible/TextField 个数对 eager 与 lazy 都不变（本批实锤，
    // 首版按个数写＝假绿）。`SliverChildListDelegate`＝children 列表一次性全量建。
    final lv = t.widget<ListView>(find.byKey(const ValueKey('note-list')));
    expect(lv.childrenDelegate, isA<SliverChildBuilderDelegate>(),
        reason: '列表须懒构建：SliverChildListDelegate＝eager 一次性建满 120 个卡片件'
            '（回退 ListView(children:)＝刀①红）');
    await drainLogTimer(t);
  });

  testWidgets('批1-② 瀑布流高度按篇缓存：选中重绘不重算（摘缓存＝红）', (t) async {
    final saved = <Note>[];
    for (var i = 0; i < 6; i++) {
      saved.add(await dao.save(note('标题$i', content: '正文若干字')));
    }
    await t.pumpWidget(scope(const NoteTab()));
    await t.pumpAndSettle();
    // 列表 → 2 列卡片（瀑布流）。
    await t.tap(find.byKey(const ValueKey('note-view')));
    await t.pumpAndSettle();
    expect(find.byKey(ValueKey('note-card-${saved.first.id}')), findsOneWidget);
    final afterFirst = kNoteEstComputeCount;
    expect(afterFirst, 6, reason: '每篇各算一次高度');

    // 触发整屏重绘（长按进多选）：瀑布流重排 → 缓存命中，绝不该重跑 TextPainter。
    await t.longPress(find.byKey(ValueKey('note-card-${saved.first.id}')));
    await t.pumpAndSettle();
    expect(kNoteEstComputeCount, afterFirst,
        reason: '高度已缓存：重绘不得对同一篇重算（摘缓存会翻倍＝刀②旁证）');
    await drainLogTimer(t);
  });

  testWidgets('批1-③ 编辑页专注段懒构建：delegate＝builder（回退 children 全建＝红）',
      (t) async {
    final content = List.generate(80, (i) => '第 $i 段内容').join('\n\n');
    final n = await dao.save(note('长文', content: content));
    await t.pumpWidget(scope(NoteEditPage(noteId: n.id)));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-para-0')), findsOneWidget,
        reason: '首段必须可见可编辑');
    final lv =
        t.widget<ListView>(find.byKey(const ValueKey('note-focus-list')));
    expect(lv.childrenDelegate, isA<SliverChildBuilderDelegate>(),
        reason: '80 段长文须懒构建：SliverChildListDelegate＝eager 一次建满全部输入框'
            '（回退 ListView(children:)＝刀③红）');
    await drainLogTimer(t);
  });

  testWidgets('批1-④ 树底「全部展开/折叠」真双向：再点收起（只 addAll＝红）', (t) async {
    final fdao = NoteFolderDao(db);
    final parent = await fdao.create('父夹');
    await fdao.create('子夹', parentId: parent.id);
    await t.pumpWidget(scope(const NoteTab()));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('note-folder')));
    await t.pumpAndSettle();

    expect(find.text('子夹'), findsNothing, reason: '初始折叠：子夹不可见');
    await t.tap(find.byKey(const ValueKey('nt-bt-expand')));
    await t.pumpAndSettle();
    expect(find.text('子夹'), findsOneWidget, reason: '第一下＝全部展开');
    await t.tap(find.byKey(const ValueKey('nt-bt-expand')));
    await t.pumpAndSettle();
    expect(find.text('子夹'), findsNothing,
        reason: '第二下＝全部折叠（原实现只 addAll：这里不会收起＝刀④红）');
    await drainLogTimer(t);
  });
}
