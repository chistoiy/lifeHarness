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
import 'package:lifeharness/shared/widgets/ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// 2026-10-11 真机反馈轮（产品定「右滑开树·点树外收起」）·独立文件（全 app pump 拆分铁律）。
// 默认测试画布 800×600：抽屉宽 62%＝496 → 右侧空白取 x=700。
// **真机反馈轮4 口径变更**：起手判定带 110（轮2 为绕开 Android 系统边缘返回而立）作废，
// 改按 Obsidian 逻辑＝**整块屏幕任意位置右滑都开树**，起手阈值 56→24，
// 抬手＝速度优先（甩速 >500px/s 即开）＋三成位移兜底（净位移过 496*.3 才开）。

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
    await t.dragFrom(const Offset(6, 320), const Offset(400, 0));
    await t.pumpAndSettle();
    expect(find.text('全部笔记'), findsOneWidget, reason: '边缘右滑必须能开树');
    expect(find.text('导入本地 · 目录或文件'), findsOneWidget);
    await drainLogTimer(t);
  });

  testWidgets('离边一指宽（x=80）右滑开树（真机反馈轮4：整屏都算起手，判定带 110 作废）', (t) async {
    await open(t);
    expect(find.text('全部笔记'), findsNothing);
    await t.dragFrom(const Offset(80, 320), const Offset(400, 0));
    await t.pumpAndSettle();
    expect(find.text('全部笔记'), findsOneWidget,
        reason: '起手不必贴边——贴边段还会被 Android 系统返回吃掉');
    await drainLogTimer(t);
  });

  testWidgets('树开着时点右侧内容区＝自动收起', (t) async {
    await open(t);
    await t.dragFrom(const Offset(6, 320), const Offset(400, 0));
    await t.pumpAndSettle();
    expect(find.text('全部笔记'), findsOneWidget);
    await t.tapAt(const Offset(700, 300));
    await t.pumpAndSettle();
    expect(find.text('全部笔记'), findsNothing, reason: '点树外必收起（barrierDismissible）');
    await drainLogTimer(t);
  });

  testWidgets('屏幕中部起手右滑＝也开树（真机反馈轮4 整屏口径；旧「非边缘不开」作废）', (t) async {
    await open(t);
    expect(find.text('全部笔记'), findsNothing);
    await t.dragFrom(const Offset(400, 320), const Offset(300, 0));
    await t.pumpAndSettle();
    expect(find.text('全部笔记'), findsOneWidget,
        reason: '产品要的是 Obsidian 逻辑：整块屏幕只要右滑都开侧栏（起手带退回 110 即红＝刀②）');
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

  testWidgets('笔记树手感批 T-A：树面板＝悬浮圆角卡（圆角 16·产品 2026-10-11 定稿）', (t) async {
    await open(t);
    await t.dragFrom(const Offset(6, 320), const Offset(400, 0));
    await t.pumpAndSettle();
    final shape = find.byKey(const ValueKey('nt-card-shape'));
    expect(shape, findsOneWidget);
    final rr = t.widget<ClipRRect>(shape);
    expect((rr.borderRadius as BorderRadius).topLeft, const Radius.circular(16),
        reason: '直角回潮＝红（Obsidian 式悬浮圆角卡）');
    await drainLogTimer(t);
  });

  testWidgets('笔记树手感批 T-C：文件夹子层挂 AnimatedSize（展开/折叠有动画宿主）', (t) async {
    await NoteFolderDao(db).create('甲夹');
    await open(t);
    await t.dragFrom(const Offset(6, 320), const Offset(400, 0));
    await t.pumpAndSettle();
    expect(find.text('甲夹'), findsOneWidget);
    expect(find.byType(AnimatedSize), findsWidgets,
        reason: '摘掉 AnimatedSize＝展开折叠退回整树瞬建跳变（变异刀②）');
    await drainLogTimer(t);
  });

  testWidgets('笔记树手感批 T-D：笔记卡外套 Pressable（按压有缩放反馈）', (t) async {
    final saved = await dao.save(note('按我'));
    await open(t);
    expect(
        find.ancestor(
            of: find.byKey(ValueKey('note-card-${saved.id}')),
            matching: find.byType(Pressable)),
        findsOneWidget,
        reason: '裸 GestureDetector 无按压态＝本批实锤缺口（摘包裹层即红＝刀①）');
    await drainLogTimer(t);
  });

  // ---- 树手感批2 T-B ＋ 真机反馈轮4：开树侧的确定性形态 ----
  // 轮4 定位结论：**拖拽中途 push 路由＝这路指针被 Navigator 取消**（navigator.dart:5822），
  // 所以「面板随指推出」在路由式弹层上做不到；开＝过阈即交路由补间到底。
  // 常驻守护落三处：小位移即开（阈值 24＝刀①）·整屏起手（判定带作废＝刀②）·面板左滑真跟手（刀③）。
  // 面板宽 62%＝496。

  testWidgets('轮4：贴边轻推 40px 即开树并补间到全开（阈值 24 守护＝刀①，退回 56 即红）', (t) async {
    await open(t);
    expect(find.text('全部笔记'), findsNothing);
    await t.dragFrom(const Offset(6, 320), const Offset(40, 0));
    await t.pumpAndSettle();
    expect(find.text('全部笔记'), findsOneWidget,
        reason: '小位移轻推也要开得出——旧形态要推足一指宽才动');
    expect(t.getTopLeft(find.byKey(const ValueKey('nt-card-shape'))).dx, closeTo(8, 1),
        reason: '开＝路由补间到底，不再等抬手判位置/速度');
    await drainLogTimer(t);
  });

  testWidgets('T-B：面板面上左滑＝同一路由反向跟手收起', (t) async {
    await open(t);
    await t.dragFrom(const Offset(6, 320), const Offset(400, 0));
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.byKey(const ValueKey('nt-card-shape'))).dx,
        closeTo(8, 1));
    // 起手取卡内一处可命中锚点（顶栏 ✕ 是 IconButton，命中区稳），只往左拖不点它。
    final g = await t.startGesture(t.getCenter(find.byKey(const ValueKey('nt-close-hd'))));
    await g.moveBy(const Offset(-19, 0)); // 识别器在这一步被接受，该段位移按 start 语义不计入
    await g.moveBy(const Offset(-250, 0)); // p＝1-250/496≈.50
    await t.pump();
    final back = t.getTopLeft(find.byKey(const ValueKey('nt-card-shape'))).dx;
    expect(back, lessThan(7.0), reason: '左滑要跟手往回走，不是松手才弹');
    expect(back, greaterThan(-471.0), reason: '仍在开合之间＝中途态');
    await g.up();
    await t.pumpAndSettle();
    expect(find.text('全部笔记'), findsNothing);
    await drainLogTimer(t);
  });

}
