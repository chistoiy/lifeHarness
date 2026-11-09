import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/data/note_dao.dart';
import 'package:lifeharness/features/journal/data/note_folder_dao.dart';
import 'package:lifeharness/features/journal/domain/journal_repository.dart';
import 'package:lifeharness/features/journal/domain/note.dart';
import 'package:lifeharness/features/journal/domain/note_folder.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/journal/presentation/note_edit_page.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// V1.67（产品令「所有笔记必须有目录归属」）：
// ① 新建笔记未选夹＝归「默认」（夹不存在则建·同名复用）；
// ② 树加载前兜底＝散笔记（folder NULL/''·含删夹遗留）归入「默认」（幂等·零散笔记零写入）。
// 拆分铁律：独立文件；裸容器冷读「watch 了 notesProvider 的 tree.future」悬死＝
// riverpod 存量怪癖（探针 D 实锤·V1.66 原体同样悬，非本批引入）——树用例先热读上游。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late NoteDao dao;
  late NoteFolderDao folderDao;
  late SharedPreferences prefs;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    dao = NoteDao(db);
    folderDao = NoteFolderDao(db);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  tearDown(() async => db.close());

  List<Override> overrides() => [
        noteDaoProvider.overrideWithValue(dao),
        noteFolderDaoProvider.overrideWithValue(folderDao),
        journalRepositoryProvider
            .overrideWithValue(JournalRepository(JournalDao(db))),
        todoRepositoryProvider
            .overrideWithValue(TodoRepository(TodoDao(db), EventBus())),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ];

  Note note(String title, {String? folder}) => Note(
      title: title,
      content: '正文',
      kind: 'plain',
      folder: folder,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now());

  Future<int> folderRowCount(String name) async {
    final rows = await db.query(DbSchema.tNoteFolders,
        where: 'name = ?', whereArgs: [name]);
    return rows.length;
  }

  test('DAO 兜底：散笔记（NULL/\'\'）归入「默认」＋幂等零重复', () async {
    await dao.save(note('散A')); // folder=null
    await dao.save(note('散B', folder: '')); // folder=''
    await dao.save(note('有夹', folder: '方法论'));
    await folderDao.create('方法论');

    expect(await folderDao.ensureDefaultOwnership(), isTrue,
        reason: '首跑＝建夹＋归位，有变更');
    final list = await dao.list();
    expect(
        {for (final n in list) n.title: n.folder},
        allOf(
          containsPair('散A', kDefaultNoteFolder),
          containsPair('散B', kDefaultNoteFolder),
          containsPair('有夹', '方法论'),
        ));
    expect(await folderRowCount(kDefaultNoteFolder), 1);

    // 幂等：二跑无变更（夹不重复、归位不重写）
    expect(await folderDao.ensureDefaultOwnership(), isFalse);
    expect(await folderRowCount(kDefaultNoteFolder), 1);
  });

  test('同名复用：用户自建「默认」夹不重建、散笔记归进去', () async {
    final mine = await folderDao.create(kDefaultNoteFolder);
    await dao.save(note('散C'));
    await folderDao.ensureDefaultOwnership();
    expect(await folderRowCount(kDefaultNoteFolder), 1,
        reason: '同名夹直接复用＝不新建');
    final n = (await dao.list()).single;
    expect(n.folder, kDefaultNoteFolder);
    expect((await folderDao.byName(kDefaultNoteFolder))!.id, mine.id);
  });

  /// 生产时序对齐：列表页常驻 watch notesProvider，树依赖均已被 widget 驱动后才
  /// 有「读树」；裸容器冷读 tree.future 悬死是 riverpod 存量怪癖（探针 D 实锤·
  /// V1.66 原体同样悬），故树用例先热读上游两 provider 再读树。
  Future<void> warm(ProviderContainer c) async {
    await c.read(noteFolderListProvider.future);
    await c.read(notesProvider.future);
  }

  test('树读值：兜底后含「默认」节点且计数正确', () async {
    await dao.save(note('散D'));
    await dao.save(note('散E'));
    await folderDao.create('方法论');
    await dao.save(note('在夹', folder: '方法论'));

    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    await warm(c);
    final tree = await c.read(noteTreeProvider.future);
    final def = tree.where((r) => r.name == kDefaultNoteFolder).toList();
    expect(def, hasLength(1), reason: '树顶恰一个「默认」节点');
    expect(def.single.noteCount, 2);
    expect(def.single.folder.parentId, isNull, reason: '默认夹恒顶层');
  });

  test('删「默认」夹后重读树＝重建＋散笔记归位', () async {
    await folderDao.ensureDefaultOwnership();
    await dao.save(note('在默认', folder: kDefaultNoteFolder));
    final f = await folderDao.byName(kDefaultNoteFolder);
    await folderDao.deleteTree(f!.id!);
    expect(await dao.list().then((l) => l.single.folder), isNull,
        reason: '删夹语义＝夹内笔记归未归类（散）');

    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    await warm(c);
    final tree = await c.read(noteTreeProvider.future);
    expect(tree.any((r) => r.name == kDefaultNoteFolder), isTrue,
        reason: '重读树即重建「默认」');
    expect((await dao.list()).single.folder, kDefaultNoteFolder,
        reason: '散笔记随兜底归位');
  });

  testWidgets('编辑页新建不选夹 → 保存落「默认」', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: overrides(),
      child: MaterialApp(home: const NoteEditPage()),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('note-title')), '未选夹的新笔记');
    await tester.enterText(find.byKey(const ValueKey('note-para-0')), '正文一句');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('note-back')));
    await tester.pumpAndSettle();

    final list = await dao.list();
    expect(list, hasLength(1));
    expect(list.single.folder, kDefaultNoteFolder);
    expect(await folderDao.byName(kDefaultNoteFolder), isNotNull,
        reason: '保存路径也兜底建夹（树从未打开过也成立）');
  });
}
