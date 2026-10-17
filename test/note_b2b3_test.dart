import 'helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

// 批2/批3（工单 docs/handoff/交棒话术-20261011-笔记模块结构与手感优化 §2）：
// 批2 手感准则欠账 —— ① 左滑删补撤销条 ② 多选态返回先退多选 ③ 长按进多选补触觉；
// 批3 编辑页结构 —— ① 头部标题滚动浮出（src/预览常显）② 三段基线归一
// ③ 尾部按模式收敛 ④ 保存态降噪 ⑤ 三视图切换过渡。
// 独立文件（全 app pump 拆分铁律）；默认画布 800×600。
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
          todoRepositoryProvider
              .overrideWithValue(TodoRepository(TodoDao(db), EventBus())),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
            home: home is NoteTab ? Scaffold(body: home) : home),
      );

  Note note(String title, {String content = '正文', String kind = 'plain'}) =>
      Note(
          title: title,
          content: content,
          kind: kind,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now());

  /// 触觉锚判法（沿 haptic_confirm_test）：mock `SystemChannels.platform`
  /// 收 `HapticFeedback.vibrate` 的 pattern 参数实读值。
  List<String> captureHaptics() {
    final patterns = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        patterns.add('${call.arguments}');
      }
      return null;
    });
    return patterns;
  }

  // ------------------------------------------------------------------ 批2

  testWidgets('批2① 左滑＝一划即删＋一次「撤销」（点撤销则库与卡片都回归）', (t) async {
    final n = await dao.save(note('待删'));
    await t.pumpWidget(scope(const NoteTab()));
    await t.pumpAndSettle();
    expect(find.byKey(ValueKey('note-card-${n.id}')), findsOneWidget);

    await t.drag(
        find.byKey(ValueKey('note-swipe-${n.id}')), const Offset(-600, 0));
    // 走完位移＋resize 两段动画（onDismissed 在 resize 完成后才调）。
    // pumpAndSettle 只等帧不等 SnackBar 的 4s 存活 Timer ⇒ 撤销条仍在。
    await t.pumpAndSettle();

    expect(find.byKey(ValueKey('note-card-${n.id}')), findsNothing,
        reason: '左滑＝一划即删（不再停在「露出删除区再点」的中间态）');
    expect((await dao.byId(n.id!))!.deletedAt, isNotNull, reason: '库里已软删');
    expect(find.text('撤销'), findsOneWidget,
        reason: '滑动即删必须配退路：动作后提示带撤销（回收站＝长时效退路）');

    await t.tap(find.text('撤销'));
    await t.pumpAndSettle();

    expect((await dao.byId(n.id!))!.deletedAt, isNull,
        reason: '撤销＝从回收站恢复');
    expect(find.byKey(ValueKey('note-card-${n.id}')), findsOneWidget,
        reason: '撤销后卡片回归列表（`_gone` 垫片须一并撤掉，否则撤销了也看不见）');
    await drainLogTimer(t);
    // 点撤销已 closeWindow，但条仍要在场退完；清干净免得漏给下一条用例。
    await clearToasts(t);
  });

  testWidgets('批2② 多选态系统返回＝先退多选（不退出记录页）', (t) async {
    final n = await dao.save(note('甲'));
    await t.pumpWidget(scope(const NoteTab()));
    await t.pumpAndSettle();

    await t.longPress(find.byKey(ValueKey('note-card-${n.id}')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-sel-top')), findsOneWidget);

    expect(await t.binding.handlePopRoute(), isTrue, reason: '返回被本页接住');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-sel-top')), findsNothing,
        reason: '返回先退多选（准则 HG-H4；日记段已如此，笔记段此前漏接）');
    expect(find.byKey(ValueKey('note-card-${n.id}')), findsOneWidget,
        reason: '人仍在记录页（未随返回退出）');
    await drainLogTimer(t);
  });

  testWidgets('批2③ 长按进多选＝一记 MediumImpact（触觉锚·与影音架同语义）', (t) async {
    final patterns = captureHaptics();
    final n = await dao.save(note('甲'));
    await t.pumpWidget(scope(const NoteTab()));
    await t.pumpAndSettle();
    expect(patterns, isEmpty, reason: '未长按前零震');

    await t.longPress(find.byKey(ValueKey('note-card-${n.id}')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-sel-top')), findsOneWidget);
    expect(patterns, ['HapticFeedbackType.mediumImpact'],
        reason: '长按进管理态＝触觉锚（〇B 四处之一）；同一动作不许两种手感');
    await drainLogTimer(t);
  });

  // ------------------------------------------------------------------ 批3

  testWidgets('批3① 头部标题「滚动浮出」：标题在视口内不显示、滚出后淡入', (t) async {
    final content = List.generate(60, (i) => '第 $i 段内容').join('\n\n');
    final n = await dao.save(note('论克制', content: content));
    await t.pumpWidget(scope(NoteEditPage(noteId: n.id)));
    await t.pumpAndSettle();

    double headOpacity() => t
        .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('note-head-title')))
        .opacity;
    expect(headOpacity(), 0,
        reason: '标题仍在视口内 ⇒ 头部不显示（同一屏只出现一次标题）');

    await t.drag(
        find.byKey(const ValueKey('note-focus-list')), const Offset(0, -260));
    await t.pumpAndSettle();
    expect(headOpacity(), 1, reason: '标题滚出视口 ⇒ 头部淡入吸顶小标题');
    await drainLogTimer(t);
  });

  testWidgets('批3① src/预览视图标题常显（这两个视图没有体部标题位）', (t) async {
    final n =
        await dao.save(note('MD 标题', content: '# 标题\n\n正文', kind: 'md'));
    await t.pumpWidget(scope(NoteEditPage(noteId: n.id)));
    await t.pumpAndSettle();
    double headOpacity() => t
        .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('note-head-title')))
        .opacity;

    expect(headOpacity(), 0, reason: '写作视图首屏：头部不显示');
    await t.tap(find.byKey(const ValueKey('note-mode-src')));
    await t.pumpAndSettle();
    expect(headOpacity(), 1, reason: '源码视图标题常显');
    await t.tap(find.byKey(const ValueKey('note-mode-view')));
    await t.pumpAndSettle();
    expect(headOpacity(), 1, reason: '预览视图标题常显');
    await drainLogTimer(t);
  });

  testWidgets('批3③ 尾部按模式收敛：预览视图同样不挂 MD 条', (t) async {
    final n = await dao.save(note('MD', content: '# 标题', kind: 'md'));
    await t.pumpWidget(scope(NoteEditPage(noteId: n.id)));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('note-md-bold')), findsNothing,
        reason: '写作视图不挂 MD 条');
    await t.tap(find.byKey(const ValueKey('note-mode-view')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-md-bold')), findsNothing,
        reason: '预览视图同样不挂（只有源码视图有可用的 MD 键）');
    await drainLogTimer(t);
  });

  testWidgets('批3④ 保存态降噪：安静两态点（教学文案已删·无每键明暗闪烁）', (t) async {
    final n = await dao.save(note('既有', content: '原稿'));
    await t.pumpWidget(scope(NoteEditPage(noteId: n.id)));
    await t.pumpAndSettle();
    expect(find.text('已保存'), findsOneWidget,
        reason: '打开既有篇＝无改动＝已保存（原实现首屏错显「编辑中…」）');
    expect(find.textContaining('输入即存'), findsNothing,
        reason: '教学性文案已删');

    await t.enterText(find.byKey(const ValueKey('note-para-0')), '改一下');
    await t.pump();
    expect(find.text('编辑中'), findsOneWidget, reason: '有未落库改动');

    await t.pump(const Duration(milliseconds: 1200));
    await t.pumpAndSettle();
    expect(find.text('已保存'), findsOneWidget,
        reason: '900ms 防抖自动保存后回到已保存');
    await drainLogTimer(t);
  });

  testWidgets('批3⑤ 三视图切换＝180ms 淡入过渡（非整块瞬切·旧件立即移除）', (t) async {
    final n = await dao.save(note('MD', content: '# 标题', kind: 'md'));
    await t.pumpWidget(scope(NoteEditPage(noteId: n.id)));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('body-focus')), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('note-mode-src')));
    await t.pump(); // 切换首帧
    await t.pump(const Duration(milliseconds: 60)); // 过渡进行中
    expect(find.byKey(const ValueKey('body-src')), findsOneWidget);
    expect(find.byKey(const ValueKey('body-focus')), findsNothing,
        reason: '旧件立即移除（只做入场淡入，与原型 .pw-anim-in 一致）');

    final fade = t.widget<FadeTransition>(find
        .ancestor(
            of: find.byKey(const ValueKey('body-src')),
            matching: find.byType(FadeTransition))
        .first);
    expect(fade.opacity.value, greaterThan(0));
    expect(fade.opacity.value, lessThan(1),
        reason: '切换中应处于淡入过程（硬切＝opacity 恒 1）');

    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('body-src')), findsOneWidget);
    await drainLogTimer(t);
  });
}
