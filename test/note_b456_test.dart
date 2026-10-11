import 'dart:async';

import 'helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:lifeharness/features/journal/presentation/journal_page.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/journal/presentation/note_tab.dart';
import 'package:lifeharness/features/journal/presentation/widgets/note_sheet_lang.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// 批4/批5/批6（工单 docs/handoff/交棒话术-20261011-笔记模块结构与手感优化 §2）：
// 批4 侧边栏四缺口 —— ① 展开态跨开合保留 ② 行高 44（U6）③ 树内长按触觉 ④ 弹层语言统一；
// 批5 功能缺口五项 —— ① 搜索 ② 顶栏「更多」③ 筛选持久化 ④ 批量删除二次确认 ⑤ 来源筛选；
// 批6 微动效三条 —— ① 四段切换过渡 ② 多选条进出过渡 ③ 侧栏首帧骨架。
// 独立文件（全 app pump 拆分铁律）；默认画布 800×600。
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

  ProviderScope scope(Widget home) => ProviderScope(
        overrides: overrides(),
        child: MaterialApp(
            home: home is NoteTab ? Scaffold(body: home) : home),
      );

  Note note(String title,
          {String content = '正文',
          String kind = 'plain',
          String source = ''}) =>
      Note(
          title: title,
          content: content,
          kind: kind,
          source: source,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now());

  /// 触觉锚判法（沿 note_b2b3_test / haptic_confirm_test）。
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

  Future<void> openTree(WidgetTester t) async {
    await t.tap(find.byKey(const ValueKey('note-folder')));
    await t.pumpAndSettle();
  }

  // ------------------------------------------------------------------ 批4

  testWidgets('批4① 展开态跨开合保留（收起再开树，展开的子夹仍在）', (t) async {
    final root = await folderDao.create('父夹');
    await folderDao.create('子夹', parentId: root.id);
    await t.pumpWidget(scope(const NoteTab()));
    await t.pumpAndSettle();

    await openTree(t);
    expect(find.byKey(const ValueKey('nt-父夹')), findsOneWidget);
    expect(find.byKey(const ValueKey('nt-子夹')), findsNothing, reason: '默认收起');

    await t.tap(find.byKey(const ValueKey('nt-父夹-caret')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('nt-子夹')), findsOneWidget);

    // 收起面板（面板 State dispose）后重开——原为局部态会丢，提到 provider 后应保留。
    await t.tap(find.byKey(const ValueKey('nt-bt-close')));
    await t.pumpAndSettle();
    await openTree(t);
    expect(find.byKey(const ValueKey('nt-子夹')), findsOneWidget,
        reason: '展开集合挂 noteTreeOpenProvider ⇒ 跨开合保留（原 State 局部态会丢）');
  });

  testWidgets('批4② 树行高＝44＋上下 margin（U6 热区下限）', (t) async {
    await folderDao.create('甲夹');
    await t.pumpWidget(scope(const NoteTab()));
    await t.pumpAndSettle();
    await openTree(t);

    // 行卡 = Container(minHeight 44) 外套 margin 1+1 ⇒ InkWell 实测 46。
    expect(t.getSize(find.byKey(const ValueKey('nt-甲夹'))).height,
        closeTo(46, 0.6),
        reason: '行高＝44 热区＋上下各 1px margin（原 padding 11+11 与内容自然高 ≈40）');
  });

  testWidgets('批4③ 树内长按进管理态＝一记 MediumImpact', (t) async {
    final haptics = captureHaptics();
    await folderDao.create('甲夹');
    await t.pumpWidget(scope(const NoteTab()));
    await t.pumpAndSettle();
    await openTree(t);

    await t.longPress(find.byKey(const ValueKey('nt-甲夹')));
    await t.pumpAndSettle();
    // InkWell 的 onLongPress 会先走 Feedback.forLongPress（Android 下＝无参 vibrate），
    // 我们的触觉锚紧随其后 ⇒ 判「包含」而非「全等」。
    expect(haptics, contains('HapticFeedbackType.mediumImpact'),
        reason: '长按进管理态＝触觉锚 〇B 的触发位置扩张（与影音架 _enterSel 同语义）');
    // 管理态＝行尾就地两钮
    expect(find.byKey(const ValueKey('nt-act-rename')), findsOneWidget);
  });

  testWidgets('批4④ 弹层语言单源：「移动到」弹层走 NoteSheetHeader＋NoteSheetRow（无裸 ListTile）',
      (t) async {
    await folderDao.create('甲夹');
    await dao.save(note('甲'));
    await t.pumpWidget(scope(const NoteTab()));
    await t.pumpAndSettle();

    // 先开一次树＝把 `noteTreeProvider` 拉起来（「移动到」弹层要等它落定才能列出夹）。
    await openTree(t);
    await t.tap(find.byKey(const ValueKey('nt-bt-close')));
    await t.pumpAndSettle();

    await t.longPress(find.byKey(const ValueKey('note-card-1')));
    await t.pumpAndSettle();
    t.widget<InkWell>(find.byKey(const ValueKey('sel-move'))).onTap!();
    await t.pumpAndSettle();

    expect(find.byType(NoteSheetHeader), findsOneWidget, reason: '统一头（grabber＋左标题）');
    expect(find.byKey(const ValueKey('mv-甲夹')), findsOneWidget);
    expect(find.byType(NoteSheetRow), findsWidgets, reason: '裸 ListTile → 自绘描边卡行');
    expect(find.byType(ListTile), findsNothing, reason: '不再出现裸 ListTile（默认主题白底那套）');
  });

  // ------------------------------------------------------------------ 批5

  testWidgets('批5① 搜索钮＝真搜索（原僵尸钮）：标题/正文命中', (t) async {
    await dao.save(note('WebDAV 选型', content: '坚果云应用密码'));
    await dao.save(note('别的', content: '无关内容'));
    await t.pumpWidget(scope(const JournalPage(initialTab: 'note')));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('rec-search')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-search-input')), findsOneWidget);

    await t.enterText(
        find.byKey(const ValueKey('note-search-input')), 'WebDAV');
    await t.pumpAndSettle();
    // 命中判定要**限定在搜索结果列表内**——搜索半屏背后仍压着完整笔记列表。
    final results = find.byKey(const ValueKey('note-search-list'));
    expect(results, findsOneWidget);
    expect(find.descendant(of: results, matching: find.text('WebDAV 选型')),
        findsOneWidget);
    expect(find.descendant(of: results, matching: find.text('别的')),
        findsNothing);
  });

  testWidgets('批5② 顶栏「更多」收拢 导入/导出/打开历史（笔记段）', (t) async {
    await dao.save(note('甲'));
    await t.pumpWidget(scope(const JournalPage(initialTab: 'note')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('rec-more')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('rec-more')));
    await t.pumpAndSettle();
    expect(find.text('导入本地'), findsOneWidget);
    expect(find.text('导出为本地目录'), findsOneWidget);
    expect(find.text('系统打开历史'), findsOneWidget);
  });

  testWidgets('批5③ 排序/视图写回设置（新容器＝冷启动也读回，不再复位）', (t) async {
    await dao.save(note('甲'));
    await t.pumpWidget(scope(const NoteTab()));
    await t.pumpAndSettle();
    final container = ProviderScope.containerOf(t.element(find.byType(NoteTab)));

    await t.tap(find.byKey(const ValueKey('note-sort')));
    await t.pumpAndSettle();
    await t.tap(find.text('标题 A→Z'));
    await t.pumpAndSettle();
    expect(container.read(settingsControllerProvider).noteSort, 'title');

    await t.tap(find.byKey(const ValueKey('note-view')));
    await t.pumpAndSettle();
    expect(container.read(settingsControllerProvider).noteViewCols, 2);

    // 新容器（模拟冷启动）：起始值应自设置读回。
    final fresh = ProviderContainer(overrides: overrides());
    addTearDown(fresh.dispose);
    expect(fresh.read(noteFilterProvider).sort, NoteSort.title,
        reason: '排序值已落设置，冷启动不再复位到 最后修改↓');
    expect(fresh.read(noteViewColsProvider), 2, reason: '视图档同样持久化');
  });

  testWidgets('批5④ 批量删除二次确认：取消＝不删且留在多选', (t) async {
    await dao.save(note('甲'));
    await t.pumpWidget(scope(const NoteTab()));
    await t.pumpAndSettle();

    await t.longPress(find.byKey(const ValueKey('note-card-1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('sel-del')));
    await t.pumpAndSettle();

    expect(find.text('删除选中的 1 篇笔记？'), findsOneWidget, reason: '先问一句（与日记段对齐）');
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();

    expect((await dao.byId(1))!.deletedAt, isNull, reason: '取消＝不落库');
    expect(find.byKey(const ValueKey('note-card-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('note-sel-bar')), findsOneWidget,
        reason: '取消后仍留在多选态，可重试');

    // 确认路径：点主钮（key 定位）→ 真删除并退出多选。
    await t.tap(find.byKey(const ValueKey('sel-del')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('note-del-batch-ok')));
    await t.pumpAndSettle();
    expect((await dao.byId(1))!.deletedAt, isNotNull, reason: '确认＝移入回收站');
    expect(find.byKey(const ValueKey('note-sel-bar')), findsNothing,
        reason: '删除后退出多选态');
  });

  testWidgets('批5⑤ 按来源筛选：选「本地导入」只剩 local_* 来源', (t) async {
    await dao.save(note('本地来的', kind: 'md', source: 'local_file'));
    await dao.save(note('手写的'));
    await t.pumpWidget(scope(const NoteTab()));
    await t.pumpAndSettle();
    expect(find.textContaining('本地来的'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('note-source')));
    await t.pumpAndSettle();
    expect(find.byType(NoteSheetHeader), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('nsrc-local')));
    await t.pumpAndSettle();

    expect(find.textContaining('本地来的'), findsOneWidget);
    expect(find.textContaining('手写的'), findsNothing,
        reason: '兑现卸载弹层「来源标仍可筛」——按来源过滤真的可用');
    await clearToasts(t);
  });

  // ------------------------------------------------------------------ 批6

  testWidgets('批6① 四段切换＝180ms 淡入过渡（非硬切）', (t) async {
    await dao.save(note('甲'));
    await t.pumpWidget(scope(const JournalPage(initialTab: 'note')));
    await t.pumpAndSettle();

    final sw = t.widget<AnimatedSwitcher>(find.ancestor(
        of: find.byType(NoteTab), matching: find.byType(AnimatedSwitcher)));
    expect(sw.duration, const Duration(milliseconds: 180), reason: '〇B 微动档 120~180ms');

    await t.tap(find.byKey(const ValueKey('rec-switch')));
    await t.pumpAndSettle();
    await t.tap(find.text('日记'));
    await t.pump(); // 建出新段并启动过渡（此帧 t=0）
    await t.pump(const Duration(milliseconds: 90)); // 推进到过渡中段

    final fades = t.widgetList<FadeTransition>(find.descendant(
        of: find.byType(AnimatedSwitcher),
        matching: find.byType(FadeTransition)));
    expect(fades.any((f) => f.opacity.value > 0 && f.opacity.value < 1), isTrue,
        reason: '切换进行中＝新段正在淡入（硬切时不会出现中间值）');
    await t.pumpAndSettle();
  });

  testWidgets('批6② 多选条进出＝AnimatedSize 过渡', (t) async {
    await dao.save(note('甲'));
    await t.pumpWidget(scope(const NoteTab()));
    await t.pumpAndSettle();

    await t.longPress(find.byKey(const ValueKey('note-card-1')));
    await t.pumpAndSettle();
    expect(
        find.ancestor(
            of: find.byKey(const ValueKey('note-sel-bar')),
            matching: find.byType(AnimatedSize)),
        findsOneWidget,
        reason: '底条槽位恒在、多选态才展开＝才有所谓「进出」补间');
    expect(
        find.ancestor(
            of: find.byKey(const ValueKey('note-sel-top')),
            matching: find.byType(AnimatedSize)),
        findsOneWidget,
        reason: '顶部「已选择 x 项」同档进出');
  });

  testWidgets('批6③ 开树首帧＝骨架（provider 未落定时不铺空树）', (t) async {
    final never = Completer<List<FolderNode>>();
    await t.pumpWidget(ProviderScope(
      overrides: [
        ...overrides(),
        noteTreeProvider.overrideWith((ref) => never.future),
      ],
      child: const MaterialApp(home: Scaffold(body: NoteTab())),
    ));
    await t.pumpAndSettle();
    await openTree(t);
    expect(find.byKey(const ValueKey('nt-skeleton')), findsOneWidget);
  });
}
