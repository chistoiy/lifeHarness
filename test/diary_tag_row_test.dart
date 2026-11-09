import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/settings/settings_repository.dart';
import 'package:lifeharness/features/journal/data/diary_template_dao.dart';
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/data/note_dao.dart';
import 'package:lifeharness/features/journal/data/tag_dao.dart';
import 'package:lifeharness/features/journal/domain/journal_entry.dart';
import 'package:lifeharness/features/journal/domain/journal_repository.dart';
import 'package:lifeharness/features/journal/domain/tag.dart';
import 'package:lifeharness/features/journal/presentation/diary_edit_page.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/journal/presentation/tag_pick_sheet.dart';
import 'package:lifeharness/features/journal/presentation/widgets/diary_tag_row.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 批2b · 日记编辑页标签行与选标签弹层。
///
/// 钉三件事：① 已选标签渲染成可移除胶囊；② 弹层只列 `scopes` 含 diary 的标签
/// （口径③）；③ 选择结果真的落到 `tag_links`（不是只改页面内存）。
void main() {
  sqfliteFfiInit();

  late Database db;
  late TagDao tagDao;
  late JournalRepository jrepo;
  late TodoRepository trepo;
  late SharedPreferences prefs;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    tagDao = TagDao(db);
    jrepo = JournalRepository(JournalDao(db));
    trepo = TodoRepository(TodoDao(db), EventBus());
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async => db.close());

  Widget host(Widget home) => ProviderScope(
        overrides: [
          journalRepositoryProvider.overrideWithValue(jrepo),
          tagDaoProvider.overrideWithValue(tagDao),
          todoRepositoryProvider.overrideWithValue(trepo),
          diaryTemplateDaoProvider.overrideWithValue(DiaryTemplateDao(db)),
          noteDaoProvider.overrideWithValue(NoteDao(db)),
          readRepositoryProvider.overrideWithValue(ReadRepository(db)),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: home,
          ),
        ),
      );

  testWidgets('D1 标签行：已选胶囊 + ✕ 回调 + 末尾「标签」入口', (tester) async {
    final removed = <String>[];
    var added = 0;
    await tester.pumpWidget(host(Scaffold(
      body: DiaryTagRow(
        tags: const ['生活', '复盘'],
        pool: const [
          Tag(id: 1, name: '生活'),
          Tag(id: 2, name: '复盘'),
        ],
        onRemove: removed.add,
        onAdd: () => added++,
      ),
    )));

    expect(find.text('生活'), findsOneWidget);
    expect(find.text('复盘'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dtag-x-生活')));
    expect(removed, ['生活']);
    await tester.tap(find.byKey(const ValueKey('dtag-add')));
    expect(added, 1);
  });

  testWidgets('D2 选标签弹层：只列 diary 侧标签，点选实时回调', (tester) async {
    await tagDao.create('晨间页', scopes: {'diary'});
    await tagDao.create('读书笔记', scopes: {'note'});
    await tagDao.create('通用', scopes: {'diary', 'note', 'time'});

    final picked = <List<String>>[];
    await tester.pumpWidget(host(Consumer(builder: (ctx, ref, _) {
      return Scaffold(
        body: TextButton(
          key: const ValueKey('open'),
          onPressed: () => showDiaryTagSheet(
            context: ctx,
            ref: ref,
            selected: const [],
            onChanged: (v) => picked.add(v),
          ),
          child: const Text('open'),
        ),
      );
    })));
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('dtag-pick-晨间页')), findsOneWidget);
    expect(find.byKey(const ValueKey('dtag-pick-通用')), findsOneWidget);
    expect(find.byKey(const ValueKey('dtag-pick-读书笔记')), findsNothing,
        reason: '口径③：日记页只列 scopes 含 diary 的标签');

    await tester.tap(find.byKey(const ValueKey('dtag-pick-晨间页')));
    await tester.pump();
    expect(picked.last, ['晨间页']);
    await tester.tap(find.byKey(const ValueKey('dtag-pick-晨间页')));
    await tester.pump();
    expect(picked.last, isEmpty, reason: '再点一次＝取消选择');
  });

  testWidgets('D3 编辑页：载入既有篇带标签行；选中后保存落关联表', (tester) async {
    await tagDao.create('复盘', scopes: {'diary'});
    await tagDao.create('生活', scopes: {'diary'});
    final e = await jrepo.save(JournalEntry(
      day: DateTime.now(),
      content: '已有正文',
      tags: const ['复盘'],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));

    await tester.pumpWidget(host(DiaryEditPage(entryId: e.id)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dtag-chip-复盘')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('dtag-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dtag-pick-生活')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dtag-sheet-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dtag-chip-生活')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('diary-save')));
    await tester.pumpAndSettle();
    final names = await tagDao.namesOf('diary', e.id!);
    expect(names, containsAll(['复盘', '生活']));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  });

  testWidgets('D4 编辑页：✕ 移除后保存，关联表只剩其余标签', (tester) async {
    await tagDao.create('复盘', scopes: {'diary'});
    await tagDao.create('生活', scopes: {'diary'});
    final e = await jrepo.save(JournalEntry(
      day: DateTime.now(),
      content: '正文',
      tags: const ['复盘', '生活'],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    await tester.pumpWidget(host(DiaryEditPage(entryId: e.id)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('dtag-x-复盘')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('diary-save')));
    await tester.pumpAndSettle();
    expect(await tagDao.namesOf('diary', e.id!), ['生活']);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  });
}
