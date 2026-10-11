import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/journal/data/note_dao.dart';
import 'package:lifeharness/features/journal/data/note_folder_dao.dart';
import 'package:lifeharness/features/journal/domain/note.dart';
import 'package:lifeharness/features/journal/domain/note_folder.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/journal/presentation/note_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

// V1.64 批4 · N-4 历史半屏与树顶固定行（工单 §18 面板）。
// 独立文件＝全 app pump 拆分铁律；跳编辑那条不在这里点（宿主无 GoRouter，见源码守护例）。

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late NoteDao notes;
  late NoteFolderDao folders;
  late SharedPreferences prefs;
  final t0 = DateTime.now().subtract(const Duration(hours: 3));

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    notes = NoteDao(db);
    folders = NoteFolderDao(db);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  tearDown(() async => db.close());

  ProviderScope scope() => ProviderScope(
        overrides: [
          noteDaoProvider.overrideWithValue(notes),
          noteFolderDaoProvider.overrideWithValue(folders),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
            home: Scaffold(body: NoteTab())),
      );

  Future<void> openTree(WidgetTester t) async {
    await t.pumpWidget(scope());
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('note-folder')));
    await t.pumpAndSettle();
    expect(find.text('全部笔记'), findsOneWidget, reason: '树要开着');
  }

  Future<Note> seed(String title,
          {String folder = kSystemOpenFolder, DateTime? wbAt}) =>
      notes.save(Note(
          title: title,
          content: '正文',
          kind: 'md',
          folder: folder,
          source: 'open_with',
          originPath: 'Download/$title.md',
          originUri: 'content://doc/$title',
          openedAt: t0,
          wbAt: wbAt,
          createdAt: t0,
          updatedAt: wbAt ?? t0));

  testWidgets('树顶固定「系统打开」行在场·带临时标与计数·且该夹不在下方重复出现', (t) async {
    await folders.create('灵感');
    // 前提必须造足：临时夹的**行**也在册（批1 的 ensureSystemOpenFolder 就是建这一行），
    // 否则下方没有可排除的节点，「排除重复」这条根本没被压到（首跑刀③不红就是漏在这）。
    await folders.create(kSystemOpenFolder);
    await seed('甲.md');
    await seed('乙.md');
    await openTree(t);
    expect(find.text(kSystemOpenFolder), findsOneWidget,
        reason: '固定行＋普通节点两处出现＝同一夹两种语义（摘掉 _nodes 里的排除＝本例红＝刀③）');
    final row = find.byKey(const ValueKey('nt-sysopen'));
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('临时')), findsOneWidget,
        reason: '原型树顶行带「临时」角标');
    expect(find.descendant(of: row, matching: find.text('2')), findsOneWidget,
        reason: '计数＝同一份 notesProvider 挑出来的条数（与半屏标题同一个数）');
    await drainLogTimer(t);
  });

  testWidgets('没有进件时固定行仍在（计数 0）·点开＝空态虚线行', (t) async {
    await openTree(t);
    expect(find.byKey(const ValueKey('nt-sysopen')), findsOneWidget,
        reason: '恒定在场：没进件也要给入口（否则用户找不到 N-4 这屏）');
    await t.tap(find.byKey(const ValueKey('nt-sysopen')));
    await t.pumpAndSettle();
    expect(find.text('系统打开 · 共 0 条'), findsOneWidget);
    expect(find.byKey(const ValueKey('noh-empty')), findsOneWidget);
    expect(find.text('还没有经系统打开的文件'), findsOneWidget);
    // 第一步只问不动手，第二步才真清（空库也要走完两步才出那句实话）
    await t.tap(find.text('清空'));
    await t.pumpAndSettle();
    expect(find.text('确认清空？'), findsOneWidget);
    await t.tap(find.text('确认清空？'));
    await t.pumpAndSettle();
    expect(await pollText(t, '本来就是空的 · 临时夹里没有待清的进件'), isTrue);
    await clearToasts(t);
  });

  testWidgets('半屏列出三态行·已转入的那行不给「转入正式目录」钮', (t) async {
    await folders.create('方法论');
    await seed('已回写.md', wbAt: t0.add(const Duration(minutes: 1)));
    await seed('仅应用内.md');
    await seed('已转入.md', folder: '方法论');
    await openTree(t);
    await t.tap(find.byKey(const ValueKey('nt-sysopen')));
    await t.pumpAndSettle();
    expect(find.text('已回写原文件'), findsOneWidget);
    expect(find.text('仅应用内'), findsOneWidget);
    expect(find.text('已转正式目录'), findsOneWidget);
    expect(find.text('原文件不在 · 改动仅存应用内'), findsOneWidget,
        reason: '只有 app 态给那行小注（原型同句），别三行都刷一遍');
    expect(find.byKey(const ValueKey('noh-move-3')), findsNothing,
        reason: '已转入的行不再给转入钮（原型 o.st===moved 空串）');
    expect(find.byKey(const ValueKey('noh-move-1')), findsOneWidget);
    await drainLogTimer(t);
  });

  testWidgets('清空＝就地两步确认：第一步只问不动手，第二步才进回收站且已转入不受影响',
      (t) async {
    await seed('甲.md');
    await seed('乙.md');
    final kept = await seed('丙.md', folder: '方法论');
    await openTree(t);
    await t.tap(find.byKey(const ValueKey('nt-sysopen')));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('noh-clear')));
    await t.pumpAndSettle();
    expect(find.text('确认清空？'), findsOneWidget, reason: '破坏性动作必经二次确认');
    expect(await notes.list(), hasLength(3), reason: '第一步什么都不许删');

    await t.tap(find.byKey(const ValueKey('noh-clear')));
    await t.pumpAndSettle();
    expect(await pollText(t, '已清空 2 条 · 已转入的笔记不受影响'), isTrue);
    expect((await notes.list()).map((e) => e.title), ['丙.md'],
        reason: '摘掉「仍在临时夹」这层过滤＝连已转入的一起软删（本例红＝刀②）');
    expect((await notes.byId(kept.id!))!.deletedAt, isNull);
    await clearToasts(t);
    await drainLogTimer(t);
  });

  testWidgets('转入走既有「移动到」弹层·落库后来源标保留、态变已转正式目录', (t) async {
    await folders.create('方法论');
    final n = await seed('甲.md');
    await openTree(t);
    await t.tap(find.byKey(const ValueKey('nt-sysopen')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(ValueKey('noh-move-${n.id}')));
    await t.pumpAndSettle();
    expect(find.text('移动到文件夹'), findsOneWidget,
        reason: '复用既有弹层，不另造一个目录选择器');
    await t.tap(find.byKey(const ValueKey('mv-方法论')));
    await t.pumpAndSettle();
    expect(await pollText(t, '已转入「方法论」 · 临时标记已解除 · 来源标保留'), isTrue);
    final back = (await notes.byId(n.id!))!;
    expect(back.folder, '方法论');
    expect(back.source, 'open_with', reason: '清了来源就再也判不出「已转入」');
    await clearToasts(t);
    await drainLogTimer(t);
  });
}
