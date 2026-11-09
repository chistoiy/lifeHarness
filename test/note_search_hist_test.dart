import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/data/note_dao.dart';
import 'package:lifeharness/features/journal/data/note_folder_dao.dart';
import 'package:lifeharness/features/journal/domain/journal_repository.dart';
import 'package:lifeharness/features/journal/domain/note.dart';
import 'package:lifeharness/features/journal/presentation/journal_page.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 批7 A3（2026-11-08 · 评估件 A3）· 搜索半屏常驻用例。
///
/// 锁三件：① 空态不再是「一行灰字」（有图形空态 + 一句引导，且无教学文案）；
/// ② 输入框为填充圆角（原下划线式偏轻）；③ 最近搜索＝本机持久化，点即搜、可清空。
/// 独立文件（全 app pump 拆分铁律）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late NoteDao dao;
  late SharedPreferences prefs;

  const histKey = 'note_search_history';

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

  Widget scope() => ProviderScope(
        overrides: [
          noteDaoProvider.overrideWithValue(dao),
          noteFolderDaoProvider.overrideWithValue(NoteFolderDao(db)),
          journalRepositoryProvider
              .overrideWithValue(JournalRepository(JournalDao(db))),
          todoRepositoryProvider
              .overrideWithValue(TodoRepository(TodoDao(db), EventBus())),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(
            home: JournalPage(section: 'note')),
      );

  Future<void> openSearch(WidgetTester t) async {
    await t.tap(find.byKey(const ValueKey('rec-search')));
    await t.pumpAndSettle();
  }

  testWidgets('空态＝图形空态＋一句引导；输入框为填充圆角', (t) async {
    await t.pumpWidget(scope());
    await t.pumpAndSettle();
    await openSearch(t);

    expect(find.byKey(const ValueKey('note-search-hint')), findsOneWidget,
        reason: '空态要有引导句（原来只有一行灰字）');
    expect(find.text('输入关键词开始搜索'), findsNothing,
        reason: '旧空态文案已撤（换成图形空态）');
    // 无历史时不出「最近」行
    expect(find.text('最近'), findsNothing);

    final tf = t.widget<TextField>(
        find.byKey(const ValueKey('note-search-input')));
    expect(tf.decoration?.filled, isTrue,
        reason: 'A3：下划线式输入 → 填充圆角，与命名/移动半屏同款');
  });

  testWidgets('提交查询→落本机；重开半屏出 chip，点 chip 回填并搜', (t) async {
    await dao.save(Note(
        title: 'WebDAV 选型',
        content: '坚果云应用密码',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now()));

    await t.pumpWidget(scope());
    await t.pumpAndSettle();
    await openSearch(t);

    await t.enterText(
        find.byKey(const ValueKey('note-search-input')), 'WebDAV');
    await t.pumpAndSettle();
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();

    expect(prefs.getStringList(histKey), ['WebDAV'],
        reason: '键盘搜索键＝一次被采纳的查询，记进最近搜索');

    // 关半屏再开：chip 出现在「最近」行
    await t.tapAt(const Offset(400, 20));
    await t.pumpAndSettle();
    await openSearch(t);
    expect(find.text('最近'), findsOneWidget);
    expect(find.byKey(const ValueKey('note-search-hist-WebDAV')),
        findsOneWidget);

    // 点 chip＝回填 + 立即搜
    await t.tap(find.byKey(const ValueKey('note-search-hist-WebDAV')));
    await t.pumpAndSettle();
    expect(
        t
            .widget<TextField>(
                find.byKey(const ValueKey('note-search-input')))
            .controller!
            .text,
        'WebDAV');
    expect(find.byKey(const ValueKey('note-search-list')), findsOneWidget);
  });

  testWidgets('重复查询不重复记；清空后 chip 消失且本机键移除', (t) async {
    SharedPreferences.setMockInitialValues({
      histKey: ['WebDAV', '日记', '跑步'],
    });
    prefs = await SharedPreferences.getInstance();

    await t.pumpWidget(scope());
    await t.pumpAndSettle();
    await openSearch(t);

    expect(find.byKey(const ValueKey('note-search-hist-日记')), findsOneWidget);

    // 再搜一次 '日记'：仍只有一条
    await t.enterText(find.byKey(const ValueKey('note-search-input')), '日记');
    await t.pumpAndSettle();
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
    expect(prefs.getStringList(histKey), ['日记', 'WebDAV', '跑步'],
        reason: '同词前插去重（最近在上），不重复堆条目');

    // 清空：先用输入框的 ✕ 回到空态，「最近」行才出现
    await t.tap(find.byKey(const ValueKey('note-search-clear')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('note-search-hist-clear')));
    await t.pumpAndSettle();
    expect(find.text('最近'), findsNothing);
    expect(prefs.getStringList(histKey), isNull);
  });
}
