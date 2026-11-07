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
// **轮4 口径**：起手面＝整屏任意位置右滑都开树（判定带 110 作废），入树阈值 24，横>纵防竖滑误开。
// **常驻叠层批（本文件现行形态）**：承载从路由式弹层换成 NoteTreeOverlay——
// 开侧恢复真跟手三判定＝中途随指／抬手 p>0.4 或甩速>500px/s 补间全开／不足回弹。

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

  /// 带真时间戳的右滑：moveBy 的 timeStamp 是绝对时刻（同帧事件算不出速度，
  /// 见 tmp/mut_tree3.md 与工单 §4），逐步给步长与间隔即可造出「慢拖」或「轻甩」。
  Future<void> flap(WidgetTester t,
      {required List<double> steps,
      required int everyMs,
      Offset start = const Offset(6, 320)}) async {
    final g = await t.startGesture(start);
    var ms = 0;
    for (final dx in steps) {
      ms += everyMs;
      await g.moveBy(Offset(dx, 0), timeStamp: Duration(milliseconds: ms));
      await t.pump();
    }
    await g.up(timeStamp: Duration(milliseconds: ms));
  }

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

  // ---- 树手感批2 T-B ＋ 常驻叠层批：开合两侧的跟手形态 ----
  // 常驻叠层（NoteTreeOverlay）下拖拽期间不往 Navigator 插任何东西，指针不被取消
  // （轮4 定位：路由插入＝navigator.dart:5822 逐个 cancel），开侧真跟手成立。
  // 面板宽 62%＝496；卡左缘 x＝8+496*(p-1)。

  testWidgets('贴边轻推 120px 短甩＝入树并补间到全开（阈值 24 守护：挪 20px 不入树＝刀①）',
      (t) async {
    await open(t);
    expect(find.text('全部笔记'), findsNothing);
    // 常驻叠层抬手判定＝位置腿或速度腿；dragFrom 的 0 时长单事件算不出速度，按工单 §4 造真甩速。
    await flap(t, steps: [40, 40, 40], everyMs: 25); // v＝1600px/s，p≈.24
    await t.pumpAndSettle();
    expect(find.text('全部笔记'), findsOneWidget,
        reason: '小位移轻甩也要开得出——旧形态要推足一指宽才动');
    expect(t.getTopLeft(find.byKey(const ValueKey('nt-card-shape'))).dx,
        closeTo(8, 1), reason: '过阈即补间到底');
    await drainLogTimer(t);
  });

  testWidgets('阈值守护另一腿：只挪 20 像素（<24）抬手＝根本不入树', (t) async {
    await open(t);
    await flap(t, steps: [10, 10], everyMs: 25);
    await t.pumpAndSettle();
    expect(find.text('全部笔记'), findsNothing);
    await drainLogTimer(t);
  });

  testWidgets('T-B：面板面上左滑＝叠层同一条 controller 反向跟手收起', (t) async {
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

  // ---- 常驻叠层批：开侧真跟手三判定（工单 §2 恢复轮4 撤下的形态；新增常驻 3 例＋命中闭环例） ----

  testWidgets('常驻叠层：拖到中途面板随指、遮罩同帧变淡；过半抬手补间全开', (t) async {
    await open(t);
    final g = await t.startGesture(const Offset(6, 320));
    Future<void> step(double dx) async {
      await g.moveBy(Offset(dx, 0));
      await t.pump();
    }
    await step(120); // p≈.242
    expect(t.getTopLeft(find.byKey(const ValueKey('nt-card-shape'))).dx,
        closeTo(-367.8, 2), reason: '面板必须停在半途随指，不是等抬手才动');
    await step(80); // p≈.403
    expect(t.getTopLeft(find.byKey(const ValueKey('nt-card-shape'))).dx,
        closeTo(-287.8, 2), reason: '继续拖＝继续跟手（摘掉逐帧钉值＝本例红＝刀①）');
    final scrim = t.widget<ColoredBox>(find.byKey(const ValueKey('nt-barrier')));
    expect(scrim.color.a, closeTo(.403 * .54, .05),
        reason: '遮罩透明度＝p*0.54 同帧（工单 §1）');
    await step(100); // p≈.608
    await g.up();
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.byKey(const ValueKey('nt-card-shape'))).dx,
        closeTo(8, 1), reason: '过半抬手＝补间全开');
    await drainLogTimer(t);
  });

  testWidgets('常驻叠层：慢拖剩不到四成抬手＝回弹不开（位置腿与速度腿都不成立）', (t) async {
    await open(t);
    // 200ms/步＝v＝300<500（速度腿不成立）；p＝90/496≈.18<.4（位置腿不成立）。
    await flap(t, steps: [60, 30], everyMs: 200);
    await t.pumpAndSettle();
    expect(find.text('全部笔记'), findsNothing, reason: '不足判定必须回弹，停在场不算开');
    await drainLogTimer(t);
  });

  testWidgets('常驻叠层：慢拖过半＝位置腿补间全开（摘掉位置腿＝本例红＝刀②）', (t) async {
    await open(t);
    // v＝300 不过甩速线，只有 p≈.605>.4 能开——专测位置腿。
    await flap(t, steps: [60, 120, 120], everyMs: 200);
    await t.pumpAndSettle();
    expect(find.text('全部笔记'), findsOneWidget, reason: '慢拖过半也要开得出');
    expect(t.getTopLeft(find.byKey(const ValueKey('nt-card-shape'))).dx,
        closeTo(8, 1));
    await drainLogTimer(t);
  });

  testWidgets('常驻叠层：轻甩 120px＝速度腿补间全开（p≈.24 不过位置线，专测速度腿）',
      (t) async {
    await open(t);
    await flap(t, steps: [30, 30, 30, 30], everyMs: 25); // v＝1200px/s
    await t.pumpAndSettle();
    expect(find.text('全部笔记'), findsOneWidget,
        reason: '短促轻甩＝速度腿成立（阈值 24 仍在：不足 24px 的挪动不入树）');
    await drainLogTimer(t);
  });

  testWidgets('常驻叠层：返回键＝收起而不是退掉笔记页（PopScope 接管）', (t) async {
    await open(t);
    await t.dragFrom(const Offset(6, 320), const Offset(400, 0));
    await t.pumpAndSettle();
    expect(find.text('全部笔记'), findsOneWidget);
    expect(Navigator.of(t.element(find.text('全部笔记'))).canPop(), isFalse,
        reason: '树在场时最上层路由 must 不可直接 pop（不许再靠 Navigator.pop 收树）');
    // 3.38 的模拟入口＝WidgetsBinding.handlePopRoute（popRoute 系统通知）。
    expect(await t.binding.handlePopRoute(), isTrue,
        reason: '返回事件必须被树接住（返回键吞掉＝退 app）');
    await t.pumpAndSettle();
    expect(find.text('全部笔记'), findsNothing, reason: '返回键＝走同一条 close 动画');
    expect(find.byKey(const ValueKey('note-folder')), findsOneWidget,
        reason: '收起后仍在笔记页＝没退模块');
    await drainLogTimer(t);
  });

}
