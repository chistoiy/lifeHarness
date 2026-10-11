import 'helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/journal/data/note_dao.dart';
import 'package:lifeharness/features/journal/data/note_folder_dao.dart';
import 'package:lifeharness/features/journal/domain/note.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/journal/presentation/note_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// 2026-10-11 真机反馈轮（产品定「左边缘右滑开树·点树外收起」）·独立文件（全 app pump 拆分铁律）。
// 默认测试画布 800×600：边缘判定带 28、抽屉宽 62%＝496 → 右侧空白取 x=700。

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

  ProviderScope scope() => ProviderScope(
        overrides: [
          noteDaoProvider.overrideWithValue(dao),
          noteFolderDaoProvider.overrideWithValue(NoteFolderDao(db)),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(home: Scaffold(body: NoteTab())),
      );

  Future<void> open(WidgetTester t) async {
    await t.pumpWidget(scope());
    await t.pumpAndSettle();
  }

  Note note(String title) => Note(
      title: title,
      content: '正文',
      folder: '甲夹',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now());

  testWidgets('左边缘右滑＝开文件树（不需要先按文件夹钮）', (t) async {
    await open(t);
    expect(find.text('全部笔记'), findsNothing);
    await t.dragFrom(const Offset(6, 320), const Offset(150, 0));
    await t.pumpAndSettle();
    expect(find.text('全部笔记'), findsOneWidget, reason: '边缘右滑必须能开树');
    expect(find.text('导入本地 · 目录或文件'), findsOneWidget);
    await drainLogTimer(t);
  });

  testWidgets('树开着时点右侧内容区＝自动收起', (t) async {
    await open(t);
    await t.dragFrom(const Offset(6, 320), const Offset(150, 0));
    await t.pumpAndSettle();
    expect(find.text('全部笔记'), findsOneWidget);
    await t.tapAt(const Offset(700, 300));
    await t.pumpAndSettle();
    expect(find.text('全部笔记'), findsNothing, reason: '点树外必收起（barrierDismissible）');
    await drainLogTimer(t);
  });

  testWidgets('起点不在边缘的右滑＝不开树（防误触）', (t) async {
    await open(t);
    await t.dragFrom(const Offset(400, 320), const Offset(150, 0));
    await t.pumpAndSettle();
    expect(find.text('全部笔记'), findsNothing);
    await drainLogTimer(t);
  });

  testWidgets('边缘竖滑（滚列表）＝不开树', (t) async {
    await dao.save(note('甲'));
    await dao.save(note('乙'));
    await dao.save(note('丙'));
    await open(t);
    await t.dragFrom(const Offset(6, 200), const Offset(12, 320));
    await t.pumpAndSettle();
    expect(find.text('全部笔记'), findsNothing, reason: '横向位移没超过纵向就不该算开树手势');
    await drainLogTimer(t);
  });

  testWidgets('卡片左滑仍是移入回收站（新监听不许抢这条手势）', (t) async {
    final saved = await dao.save(note('左滑我'));
    await open(t);
    await t.fling(find.byKey(ValueKey('note-card-${saved.id}')),
        const Offset(-400, 0), 1200);
    await t.pump();
    await t.pumpAndSettle();
    expect((await dao.trash()).single.title, '左滑我');
    expect(find.text('全部笔记'), findsNothing, reason: '左滑卡片不该顺手把树也开出来');
    await drainLogTimer(t);
  });
}
