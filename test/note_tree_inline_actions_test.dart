import 'helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/journal/data/note_dao.dart';
import 'package:lifeharness/features/journal/data/note_folder_dao.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/journal/presentation/note_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// 树手感批2 · T-E 长按就地动作（2026-10-11，工单 §批2/§⚙ 面板指定独立文件＝全 app pump 拆分铁律）。
// 规格＝原型 index-bookshelf.html 的 ntLong/ntAct/nt-act-rename/nt-act-del：
// 长按手建夹＝行尾就地现「重命名/删除」两枚线性图标钮（替掉计数位），再长按同夹或点别的行即收起；
// 旧的白色 showModalBottomSheet 菜单撤掉（与胶囊语言不符）。挂载节点照旧走「移除挂载」半屏。

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late NoteDao dao;
  late NoteFolderDao folders;
  late SharedPreferences prefs;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    dao = NoteDao(db);
    folders = NoteFolderDao(db);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  tearDown(() async => db.close());

  Future<void> openTree(WidgetTester t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        noteDaoProvider.overrideWithValue(dao),
        noteFolderDaoProvider.overrideWithValue(folders),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const MaterialApp(home: Scaffold(body: NoteTab())),
    ));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('note-folder')));
    await t.pumpAndSettle();
    expect(find.text('全部笔记'), findsOneWidget, reason: '树要开着才谈长按');
  }

  testWidgets('T-E：长按手建夹＝行尾就地两钮，不再开白色半屏菜单', (t) async {
    await folders.create('甲夹');
    await openTree(t);
    expect(find.byKey(const ValueKey('nt-act-rename')), findsNothing);
    await t.longPress(find.byKey(const ValueKey('nt-甲夹')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('nt-act-rename')), findsOneWidget,
        reason: '就地动作＝本批核心形态（回退成半屏菜单即红＝刀③）');
    expect(find.byKey(const ValueKey('nt-act-del')), findsOneWidget);
    expect(find.text('删除文件夹'), findsNothing,
        reason: '长按不许再叠一层白色半屏菜单（旧菜单条目是文字标题，就地钮只有图标＋tooltip）');
    await drainLogTimer(t);
  });

  testWidgets('T-E：再长按同一夹＝收起；点别的行＝也收起（原型 ntAct 清态）', (t) async {
    await folders.create('甲夹');
    await folders.create('乙夹');
    await openTree(t);
    await t.longPress(find.byKey(const ValueKey('nt-甲夹')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('nt-act-del')), findsOneWidget);
    await t.longPress(find.byKey(const ValueKey('nt-甲夹')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('nt-act-del')), findsNothing,
        reason: '再长按同夹＝toggle 收起（摘掉清态即红＝刀②）');
    await t.longPress(find.byKey(const ValueKey('nt-甲夹')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('nt-act-del')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('nt-乙夹')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('nt-act-del')), findsNothing,
        reason: '点别的行＝选目录并收起动作态');
    await drainLogTimer(t);
  });

  testWidgets('T-E：点 caret 展开/折叠也收起动作态', (t) async {
    final parent = await folders.create('甲夹');
    await folders.create('子夹', parentId: parent.id);
    await openTree(t);
    await t.longPress(find.byKey(const ValueKey('nt-甲夹')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('nt-act-del')), findsOneWidget);
    expect(find.text('子夹'), findsNothing);
    await t.tap(find.byKey(const ValueKey('nt-甲夹-caret')));
    await t.pumpAndSettle();
    expect(find.text('子夹'), findsOneWidget);
    expect(find.byKey(const ValueKey('nt-act-del')), findsNothing);
    await drainLogTimer(t);
  });

  testWidgets('T-E：行内删除钮＝摘掉文件夹；行内重命名钮＝就地开输入并落库', (t) async {
    await folders.create('甲夹');
    await folders.create('乙夹');
    await openTree(t);
    await t.longPress(find.byKey(const ValueKey('nt-甲夹')));
    await t.pumpAndSettle();
    // 模拟器装机验出的真缺陷：命中区被压到图标尺寸时，手指点在图标上会落到整行＝变成「选中目录」，
    // 而按 key 点中心永远点得中＝用例抓不到。所以这里断尺寸＋**故意点角落**。
    final box = t.getSize(find.byKey(const ValueKey('nt-act-del')));
    expect(box.width, greaterThanOrEqualTo(40),
        reason: '动作钮命中区下限 40（U6 同口径），不许缩成图标大小');
    expect(box.height, greaterThanOrEqualTo(40));
    await t.tapAt(t.getCenter(find.byKey(const ValueKey('nt-act-del'))) +
        Offset(-box.width / 2 + 3, box.height / 2 - 3));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('nt-甲夹')), findsNothing,
        reason: '删除钮必须真删（就地化不改语义）');
    expect(find.byKey(const ValueKey('nt-乙夹')), findsOneWidget,
        reason: '删一个不牵连别的夹');

    await t.longPress(find.byKey(const ValueKey('nt-乙夹')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('nt-act-rename')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('nt-name-input')), findsOneWidget,
        reason: '输入类仍可弹层（工单：重命名输入框弹层保留）');
    await t.enterText(find.byKey(const ValueKey('nt-name-input')), '乙夹改名');
    await t.tap(find.byKey(const ValueKey('nt-name-ok')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('nt-乙夹改名')), findsOneWidget);
    expect(find.byKey(const ValueKey('nt-act-rename')), findsNothing,
        reason: '开输入即收起动作态');
    await drainLogTimer(t);
  });

  testWidgets('T-E：挂载节点长按仍走「移除挂载」半屏（不就地化）', (t) async {
    // 本地导入目录档＝source 'local_dir'：挂载节点的长按入口维持 N-1c 已定形态。
    await folders.create('手机目录',
        source: 'local_dir',
        originPath: 'Download/手机目录',
        originUri: 'content://x/1');
    await openTree(t);
    await t.longPress(find.byKey(const ValueKey('nt-手机目录')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('nt-act-del')), findsNothing,
        reason: '挂载夹不给行内删除，只给移除挂载');
    expect(find.text('移除挂载 · 手机目录'), findsOneWidget);
    expect(find.text('手机里的目录与文件不删除'), findsOneWidget);
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    await drainLogTimer(t);
  });
}
