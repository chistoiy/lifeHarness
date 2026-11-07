/// C 案批1 真机补口（2026-11-07）常驻守护。
/// 产品反馈：① 今日页缺拆分后的 日记/笔记 入口（阅读/影音游本就在）；
/// ② 笔记页筛选/排序/文件夹/视图等按钮没合并到顶部。
/// 规格＝原型 `prototype/index.html`「全部功能」宫格＋`recToolBar` 顶栏，
/// 样张口径＝「只补两枚、不打乱其余次序」。
library;

import 'dart:io';

import 'helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/journal/data/diary_template_dao.dart';
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/domain/journal_repository.dart';
import 'package:lifeharness/features/journal/presentation/journal_page.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/journal/presentation/journal_routes.dart';
import 'package:lifeharness/features/journal/presentation/note_tab.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late EventBus bus;
  late ProviderContainer container;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    bus = EventBus();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [
      journalRepositoryProvider
          .overrideWithValue(JournalRepository(JournalDao(db))),
      todoRepositoryProvider.overrideWithValue(TodoRepository(TodoDao(db), bus)),
      diaryTemplateDaoProvider.overrideWithValue(DiaryTemplateDao(db)),
      sharedPreferencesProvider.overrideWithValue(prefs),
      readRepositoryProvider.overrideWithValue(ReadRepository(db)),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    await bus.dispose();
  });

  /// 只挂 journal 域壳路由，直达 `/notes` 独立页（与 `journal_deeplink_test` 同款）。
  Future<void> pumpNotes(WidgetTester tester) async {
    final router = GoRouter(routes: journalShellRoutes());
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router)));
    router.go('/notes');
    // 段切换走 180ms AnimatedSwitcher；推过过渡帧再断言（禁 pumpAndSettle）。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('① 今日页「全部功能」补齐拆分后四模块', () {
    test('日记/笔记补在「时间」后，四枚入口都在且直达各自页面', () {
      const f = 'lib/features/dashboard/presentation/dashboard_page.dart';
      final s = File(f).readAsStringSync();
      const entries = [
        "    (Icons.schedule_outlined, '时间', '/calendar', null),",
        "    (Icons.auto_stories_outlined, '日记', '/diary', null),",
        "    (Icons.note_outlined, '笔记', '/notes', null),",
        "    (Icons.menu_book_outlined, '阅读', '/readhub', null),",
      ];
      for (final e in entries) {
        expect(s, contains(e), reason: '宫格缺入口 $e');
      }
      // 样张口径：只补两枚、不打乱其余次序（日记/笔记紧跟时间）。
      final order = [for (final e in entries) s.indexOf(e)];
      for (var i = 1; i < order.length; i++) {
        expect(order[i], greaterThan(order[i - 1]),
            reason: '宫格次序被打乱，与已确认样张不符');
      }
      expect(s, contains("(Icons.movie_outlined, '影音游', '/media/shelf', null),"),
          reason: '影音游入口仍在（原本就在册，不得因补口误删）');
      expect(s, isNot(contains('?tab=')),
          reason: '旧四段深链已退役，宫格不得复活段参');
    });

    test('四条独立页路由在册（宫格入口不是死链）', () {
      final paths = journalShellRoutes().map((r) => r.path).toList();
      for (final p in ['/notes', '/diary', '/readhub', '/mediahub']) {
        expect(paths, contains(p), reason: '$p 不在册，宫格入口点不动');
      }
    });
  });

  group('② 独立笔记页：四枚操作并入顶栏第一行', () {
    testWidgets('顶栏含筛选/排序/文件夹/视图/更多/搜索，各只此一份',
        (tester) async {
      await pumpNotes(tester);
      final appBar = find.byType(AppBar);
      expect(appBar, findsOneWidget);
      for (final k in <String>[
        'note-source',
        'note-sort',
        'note-folder',
        'note-view',
        'rec-more',
        'rec-search',
      ]) {
        expect(
            find.descendant(
                of: appBar, matching: find.byKey(ValueKey(k))),
            findsOneWidget,
            reason: '$k 未挂在顶栏第一行');
        expect(find.byKey(ValueKey(k)), findsOneWidget,
            reason: '$k 在整页出现多份＝第二行没撤干净');
      }
      expect(find.byKey(const ValueKey('rec-switch')), findsNothing,
          reason: '独立页不得复活 ⇄ 四段切换钮');
      await settleLogTimer(tester);
    });

    testWidgets('笔记段内不再单独占一排工具条', (tester) async {
      await pumpNotes(tester);
      final noteTab = find.byType(NoteTab);
      expect(noteTab, findsOneWidget);
      for (final k in <String>[
        'note-source',
        'note-sort',
        'note-folder',
        'note-view',
      ]) {
        expect(
            find.descendant(
                of: noteTab, matching: find.byKey(ValueKey(k))),
            findsNothing,
            reason: '$k 仍在列表上方单独一排');
      }
      await settleLogTimer(tester);
    });

    testWidgets('顶栏排序菜单可展开、点空白可收起', (tester) async {
      await pumpNotes(tester);
      await tester.tap(find.byKey(const ValueKey('note-sort')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('最后修改'), findsOneWidget,
          reason: '排序菜单应锚在顶栏按钮下方展开');
      await tester.tapAt(const Offset(200, 400));
      await tester.pump();
      // 弹出层退出动画约 300ms；只推一帧会看到残留菜单文字。
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('最后修改'), findsNothing,
          reason: '点空白应关闭菜单（原型 recToolBar 口径）');
      await settleLogTimer(tester);
    });

    test('接线单一来源：顶栏托管与页内守卫', () {
      final jp = File('lib/features/journal/presentation/journal_page.dart')
          .readAsStringSync();
      expect(jp, contains('inAppBar: true'),
          reason: '顶栏按钮组必须用收窄形态，否则 390 宽顶栏会溢出');
      expect(jp, contains('toolbarInAppBar: true'),
          reason: '独立页的笔记段必须声明工具条已托管');
      expect(jp, contains('treeKey: _noteTreeKey'),
          reason: '顶栏文件夹钮必须与段内树叠层共用同一把键');
      final nt = File('lib/features/journal/presentation/note_tab.dart')
          .readAsStringSync();
      expect(nt, contains('if (!widget.toolbarInAppBar)'),
          reason: '未托管形态仍要保留第二行（存量用例直接挂载笔记段）');
      expect(nt, contains('widget.treeKey ?? _treeKey'),
          reason: '树叠层键必须两态共用，文件夹钮不能开空树');
    });
  });

  group('③ 兼容形态：直接挂载的笔记段仍保留旧第二行', () {
    testWidgets('未托管时四枚操作仍可点（不因顶栏改动打红存量用例）',
        (tester) async {
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: NoteTab()))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      for (final k in <String>[
        'note-source',
        'note-sort',
        'note-folder',
        'note-view',
      ]) {
        expect(find.byKey(ValueKey(k)), findsOneWidget,
            reason: '$k 在直接挂载笔记段时消失');
      }
      expect(find.byType(AppBar), findsNothing,
          reason: '未托管形态不该凭空多出顶栏');
      await settleLogTimer(tester);
    });
  });
}
