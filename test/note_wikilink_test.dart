/// C02 子批B · 双向链接守护（竞品补全批1）：
/// - MdView onLinkTap：行内链接点击拿到 href（recognizer 接线）；
/// - 预览层 [[标题]] 渲染：可解析的成链接、已删除的留占位不生成死链；
/// - 「被引用」面板：引用本篇标题的笔记列出；
/// - 改名跟随：本篇改名后其他笔记的 [[旧标题]] 批量换成 [[新标题]]。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/platform/open_intent.dart' show noteWriteBack;
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/journal/data/note_dao.dart';
import 'package:lifeharness/features/journal/data/note_folder_dao.dart';
import 'package:lifeharness/features/journal/domain/note.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/journal/presentation/note_edit_page.dart';
import 'package:lifeharness/features/journal/presentation/widgets/md_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
  });

  tearDown(() async => db.close());

  ProviderScope scope(Widget home) => ProviderScope(
        overrides: [
          noteDaoProvider.overrideWithValue(dao),
          noteFolderDaoProvider.overrideWithValue(NoteFolderDao(db)),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(home: home),
      );

  Note note(String title, String content) => Note(
      title: title,
      content: content,
      kind: 'md',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now());

  testWidgets('MdView onLinkTap：点行内链接 → 回调拿到 href（recognizer 接线）',
      (tester) async {
    final taps = <String>[];
    // 链接独占一段（find.text 是整段精确匹配，段内混排会找不到）。
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MdView(
          source: '[目标笔记](lh://note/42)\n\n[外链](https://e.com)',
          fg: Colors.black,
          onLinkTap: taps.add,
        ),
      ),
    ));
    // tap 打在字形上（整宽 RichText 的中心在右侧空白，recognizer 收不到）。
    Future<void> tapText(String t) async {
      final box = tester
          .renderObject<RenderBox>(find.text(t, findRichText: true));
      await tester.tapAt(box.localToGlobal(const Offset(8, 10)));
      await tester.pump();
    }

    await tapText('目标笔记');
    expect(taps, ['lh://note/42']);
    await tapText('外链');
    expect(taps, ['lh://note/42', 'https://e.com']);
  });

  testWidgets('预览：[[标题]] 可解析的渲染成链接文本，已删除的留占位不生成死链',
      (tester) async {
    await dao.save(note('目标笔记', '目标的内容'));
    final me = await dao.save(note('本篇', '进度看 [[目标笔记]]，旧稿看 [[已删的笔记]]。'));
    await tester.pumpWidget(scope(NoteEditPage(noteId: me.id)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-mode-view')));
    await tester.pumpAndSettle();
    // 可解析：链接文本存在（lh://note/<id> 投影，RichText 内联 span）；
    // 不可解析：占位文本。
    expect(find.textContaining('目标笔记', findRichText: true), findsOneWidget);
    expect(find.textContaining('（已删除的笔记）', findRichText: true),
        findsOneWidget);
  });

  testWidgets('「被引用」面板：正文含 [[本篇标题]] 的笔记列出，其余不出', (tester) async {
    final me = await dao.save(note('本篇', '正文'));
    await dao.save(note('引用方', '细节见 [[本篇]]。'));
    await dao.save(note('无关', '没有引用。'));
    await tester.pumpWidget(scope(NoteEditPage(noteId: me.id)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-mode-view')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-backlinks')), findsOneWidget);
    expect(find.text('1 处'), findsOneWidget);
    expect(find.byKey(const ValueKey('note-backlink-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('note-backlink-3')), findsNothing);
  });

  testWidgets('改名跟随：本篇改名 → 其他笔记 [[旧标题]] 批量换 [[新标题]]，正文同名词不动',
      (tester) async {
    final me = await dao.save(note('旧名', '正文'));
    final other = await dao.save(note('引用方', '见 [[旧名]]，普通词 旧名 不动。'));
    await tester.pumpWidget(scope(NoteEditPage(noteId: me.id)));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('note-title')), '新名');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('note-back')));
    await tester.pumpAndSettle();
    final rows = await dao.list();
    final changed = rows.firstWhere((n) => n.id == other.id);
    expect(changed.content, '见 [[新名]]，普通词 旧名 不动。');
  });

  testWidgets('批2留白①：引用方挂在本地导入目录 → 改名跟随当场回写挂载文件',
      (tester) async {
    await NoteFolderDao(db).create('vault',
        source: 'local_dir', originUri: 'content://tree/v1');
    final me = await dao.save(note('旧名', '正文'));
    final other = await dao.save(Note(
        title: '引用方',
        content: '见 [[旧名]]',
        kind: 'md',
        folder: 'vault',
        originUri: 'content://doc/e1',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now()));
    // 挂载回写走全局缝（默认实现依赖原生通道，测试替换为捕获表）。
    final written = <String, String>{};
    final orig = noteWriteBack;
    noteWriteBack = (uri, content) async {
      written[uri] = content;
      return 'ok';
    };
    addTearDown(() => noteWriteBack = orig);
    await tester.pumpWidget(scope(NoteEditPage(noteId: me.id)));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('note-title')), '新名');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('note-back')));
    await tester.pumpAndSettle();
    // 挂载文件当场落新正文（原留白＝要等引用方下次自身保存才对齐）。
    expect(written['content://doc/e1'], '见 [[新名]]');
    // 库内正文同批跟随（回写与落库同源）。
    final rows = await dao.list();
    expect(rows.firstWhere((n) => n.id == other.id).content, '见 [[新名]]');
  });
}
