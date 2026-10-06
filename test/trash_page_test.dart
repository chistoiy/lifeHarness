import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/habit/data/habit_repository.dart';
import 'package:lifeharness/features/habit/domain/habit.dart';
import 'package:lifeharness/features/habit/presentation/habit_providers.dart';
import 'package:lifeharness/features/items/data/items_repository.dart';
import 'package:lifeharness/features/items/domain/item_models.dart';
import 'package:lifeharness/features/journal/data/note_dao.dart';
import 'package:lifeharness/features/journal/domain/note.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/domain/book_list.dart';
import 'package:lifeharness/features/read/domain/book_quote.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/settings/presentation/trash_page.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:lifeharness/features/todo/presentation/widgets/todo_trash_entry.dart';
import 'package:lifeharness/shared/trash/trash_models.dart';
import 'package:lifeharness/shared/trash/trash_providers.dart';
import 'package:lifeharness/shared/trash/trash_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// V1.60 全局回收站 · 统一屏与入口改道（原型 p-sub-trash / GT_K 对译）。
///
/// 屏单一归属：待办旧专屏 `/todo/trash` 与笔记页内垃圾箱视图本批一并下架，
/// 恢复/彻底删除只在此屏发生（笔记屏侧回归见 test/note_test.dart）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late EventBus bus;
  late TodoDao todoDao;
  late TodoRepository todoRepo;
  late NoteDao noteDao;
  late HabitRepository habitRepo;
  late ReadRepository readRepo;
  late ItemsRepository itemsRepo;
  late TrashRepository trashRepo;
  late SharedPreferences prefs;

  /// 保留期走真实读盘路径（记录管理·通用同源），用例可按需改桩值。
  Future<void> boot({int keepDays = 30}) async {
    SharedPreferences.setMockInitialValues({'lh.trash_keep_days': keepDays});
    prefs = await SharedPreferences.getInstance();
  }

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    bus = EventBus();
    todoDao = TodoDao(db);
    todoRepo = TodoRepository(todoDao, bus);
    noteDao = NoteDao(db);
    habitRepo = HabitRepository(db);
    readRepo = ReadRepository(db);
    itemsRepo = ItemsRepository(db);
    trashRepo = TrashRepository(db);
    await boot();
  });

  tearDown(() async {
    await db.close();
    await bus.dispose();
  });

  /// 各类各塞一条垃圾箱内容（V1.61 起七类；quote 的父书已彻底删除＝孤行）。
  ///
  /// 注意：`testWidgets` 跑在 FakeAsync 里，用例体内**不许** `Future.delayed`
  /// （不等时间就挂死，既有教训）；跨类排序断言由 test/trash_data_test.dart 负责。
  Future<void> seedSix() async {
    for (final k in TrashKind.values) {
      switch (k) {
        case TrashKind.todo:
          final t = await todoRepo.add(Todo(
              title: '写周报',
              quadrant: Quadrant.q2,
              dueAt: DateTime.now().add(const Duration(days: 1)),
              tag: '工作'));
          await todoRepo.softRemove(t);
        case TrashKind.note:
          final n = await noteDao.save(Note(
              title: 'Drift 选型',
              content: '正文',
              folder: '技术',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now()));
          await noteDao.softDelete(n.id!);
        case TrashKind.habit:
          final h = await habitRepo.saveHabit(
              Habit(name: '晨跑', cycle: Habit.kDay, startDate: '2026-01-01'));
          await habitRepo.deleteHabit(h.id);
        case TrashKind.book:
          final b = await readRepo.addBook(Book(
              title: '思考，快与慢',
              pages: 100,
              readPages: 41,
              createdAt: 1,
              updatedAt: 1));
          await readRepo.addQuote(BookQuote(
              bookId: b.id,
              kind: BookQuote.kKindMark,
              body: '系统一与系统二',
              createdAt: 1,
              updatedAt: 1));
          await readRepo.softDeleteBooks([b.id]);
        case TrashKind.quote:
          final b = await readRepo.addBook(
              Book(title: '孤立之书', createdAt: 1, updatedAt: 1));
          final q = await readRepo.addQuote(BookQuote(
              bookId: b.id,
              kind: BookQuote.kKindMark,
              body: '这句要一起没',
              createdAt: 1,
              updatedAt: 1));
          await readRepo.softDeleteQuote(q!);
          await readRepo.purgeBook(b.id);
        case TrashKind.item:
          final iid = await itemsRepo.addItem(ItemProfile(
              name: '测试相机', buyDate: '2026-01-01', price: 199));
          await itemsRepo.softDeleteItem(iid);
        case TrashKind.list:
          final b = await readRepo.addBook(
              Book(title: '成员甲', createdAt: 1, updatedAt: 1));
          await readRepo.addList(
              BookList(name: '主题单', createdAt: 1, updatedAt: 1),
              bookIds: [b.id]);
          final l = (await readRepo.allLists()).first;
          await readRepo.softDeleteList(l.id!);
      }
    }
  }

  /// 行 key（主键由模块自增/生成，用例不猜，直接从数据层取）。
  Future<String> keyOf(TrashKind kind) async =>
      (await trashRepo.items()).firstWhere((e) => e.kind == kind).key;

  List<Override> ovs() => [
        sharedPreferencesProvider.overrideWithValue(prefs),
        todoRepositoryProvider.overrideWithValue(todoRepo),
        noteDaoProvider.overrideWithValue(noteDao),
        habitRepositoryProvider.overrideWithValue(habitRepo),
        readRepositoryProvider.overrideWithValue(readRepo),
        trashRepositoryProvider.overrideWithValue(trashRepo),
      ];

  Widget trashApp({String? seg}) => ProviderScope(
        overrides: ovs(),
        child: MaterialApp(home: TrashPage(initialSeg: seg)),
      );

  /// 入口改道用真路由（入口行走 context.push）。
  Widget entryApp(Widget entry) {
    final router = GoRouter(
      initialLocation: '/entry',
      routes: [
        GoRoute(
            path: '/entry',
            builder: (_, _) => Scaffold(body: entry)),
        GoRoute(
            path: '/settings/trash',
            builder: (_, s) =>
                TrashPage(initialSeg: s.uri.queryParameters['seg'])),
      ],
    );
    return ProviderScope(
        overrides: ovs(), child: MaterialApp.router(routerConfig: router));
  }

  testWidgets('空态与期限文案（与记录管理档位同源）', (tester) async {
    await tester.pumpWidget(trashApp());
    await settle5(tester);

    expect(find.text('回收站是空的'), findsOneWidget);
    expect(find.textContaining('0 项 · 删除 30 天后自动彻底删除'), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('七类分段 chips 计数同源 · 分段过滤 · 行副信息', (tester) async {
    await seedSix();
    await tester.pumpWidget(trashApp());
    await settle5(tester);

    expect(find.byKey(const ValueKey('tt-segs')), findsOneWidget);
    for (final k in TrashKind.values) {
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('tt-segs')),
              matching: find.text('${k.label} 1')),
          findsOneWidget,
          reason: '缺分段 chip：${k.label}');
    }
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('tt-segs')),
            matching: find.text('全部 ${TrashKind.values.length}')),
        findsOneWidget);

    expect(find.textContaining('写周报'), findsWidgets);
    expect(find.textContaining('含在库划线·笔记 1 条'), findsOneWidget);
    expect(find.textContaining('所属书已彻底删除'), findsOneWidget);
    expect(find.textContaining('成员 1 本'), findsOneWidget);
    // V1.61 第七类：物品行的分类/成本池/流水保留三件都在行上读得到。
    expect(find.textContaining('数码 · 成本池'), findsOneWidget);
    expect(find.textContaining('关联流水 0 条保留'), findsOneWidget);
    expect(find.text('剩 30 天'), findsNWidgets(TrashKind.values.length));

    await tester.tap(find.text('笔记 1'));
    await settle5(tester);
    expect(find.textContaining('Drift 选型'), findsOneWidget);
    expect(find.textContaining('写周报'), findsNothing);
    expect(find.textContaining('1 项 · 删除 30 天后自动彻底删除'), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('深链 ?seg= 直达分段（三入口改道口径）', (tester) async {
    await seedSix();
    await tester.pumpWidget(trashApp(seg: 'todo'));
    await settle5(tester);
    expect(find.textContaining('写周报'), findsOneWidget);
    expect(find.textContaining('晨跑'), findsNothing);
    await clearToasts(tester);
  });

  testWidgets('恢复待办＝原条目回清单，行与计数同时消失（其余五类不动）', (tester) async {
    await seedSix();
    final key = await keyOf(TrashKind.todo);
    await tester.pumpWidget(trashApp(seg: 'todo'));
    await settle5(tester);

    await tester.tap(find.byKey(ValueKey('tt-restore-$key')));
    await settle5(tester);
    expect(find.text('已恢复到「重要不紧急」'), findsOneWidget);
    expect((await todoDao.list()).map((t) => t.title), ['写周报']);
    final left = await trashRepo.items();
    expect(left.map((e) => e.kind), isNot(contains(TrashKind.todo)),
        reason: '恢复后待办行出垃圾箱');
    expect(left, hasLength(TrashKind.values.length - 1));
    await clearToasts(tester);
  });

  testWidgets('孤行无行内钮（不可单独恢复），批量选择里仍可整体彻底删除',
      (tester) async {
    await seedSix();
    final key = await keyOf(TrashKind.quote);
    await tester.pumpWidget(trashApp(seg: 'quote'));
    await settle5(tester);

    expect(find.text('不可单独恢复'), findsOneWidget);
    expect(find.byKey(ValueKey('tt-restore-$key')), findsNothing,
        reason: '孤行不给恢复钮（原型 orph 分支）');
    expect(find.byKey(ValueKey('tt-del-$key')), findsNothing,
        reason: '孤行不给行内删除钮，只能进批量');

    await tester.tap(find.byKey(const ValueKey('tt-pick')));
    await settle5(tester);
    await tester.tap(find.byKey(ValueKey('tt-row-$key')));
    await settle5(tester);
    expect(find.text('已选 1 项'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tt-purge-batch')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('tp-sheet')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tp-go')));
    await settle5(tester);
    expect(find.text('已彻底删除 1 条'), findsOneWidget);
    final left = await trashRepo.items();
    expect(left.map((e) => e.kind), isNot(contains(TrashKind.quote)));
    expect(left, hasLength(TrashKind.values.length - 1),
        reason: '只清这一条孤行，其余各类不动');
    await clearToasts(tester);
  });

  testWidgets('彻底删除书籍：弹层列连带条数，回执说明孤行不可再单独恢复',
      (tester) async {
    await seedSix();
    final key = await keyOf(TrashKind.book);
    await tester.pumpWidget(trashApp(seg: 'book'));
    await settle5(tester);

    await tester.tap(find.byKey(ValueKey('tt-del-$key')));
    await settle5(tester);
    expect(find.textContaining('共 1 条 · 删除后不可恢复'), findsOneWidget);
    expect(find.textContaining('连带清 在库划线·笔记 1 条 · 计时 · 进度'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tp-go')));
    await settle5(tester);
    expect(
        find.textContaining('已彻底删除 1 条 · 该书名下划线书摘不可再单独恢复'),
        findsOneWidget);
    final items = await trashRepo.items();
    expect(items.map((e) => e.kind), isNot(contains(TrashKind.book)));
    final orphan = items.firstWhere((e) => e.kind == TrashKind.quote);
    expect(orphan.orphan, isTrue, reason: '父书出栈后其垃圾箱划线判孤');
    await clearToasts(tester);
  });

  testWidgets('长按进批量 · 批量恢复（跨段只作用于可见行）', (tester) async {
    await seedSix();
    final key = await keyOf(TrashKind.habit);
    await tester.pumpWidget(trashApp(seg: 'habit'));
    await settle5(tester);

    await tester.longPress(find.byKey(ValueKey('tt-row-$key')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('tt-sel-bar')), findsOneWidget);
    expect(find.text('已选 1 项'), findsOneWidget);

    // 弹层要按类写清后果（原型 T7c 同口径）：习惯只清定义，流水留在纪录墙
    await tester.tap(find.byKey(const ValueKey('tt-purge-batch')));
    await settle5(tester);
    expect(find.text('只清定义 · 历史流水保留'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tp-cancel')));
    await settle5(tester);

    await tester.tap(find.byKey(const ValueKey('tt-restore-batch')));
    await settle5(tester);
    expect(find.text('已恢复到习惯列表'), findsOneWidget);
    expect((await habitRepo.allHabits()).map((h) => h.name), ['晨跑']);
    await clearToasts(tester);
  });

  testWidgets('书单彻底删除弹层说明连带成员行·书本身保留', (tester) async {
    await seedSix();
    final key = await keyOf(TrashKind.list);
    await tester.pumpWidget(trashApp(seg: 'list'));
    await settle5(tester);

    await tester.tap(find.byKey(ValueKey('tt-del-$key')));
    await settle5(tester);
    expect(find.text('连成员行一起清 · 书本身保留'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tp-cancel')));
    await settle5(tester);
    expect((await trashRepo.items()).where((e) => e.kind == TrashKind.list),
        hasLength(1), reason: '取消即一条不动');
    await clearToasts(tester);
  });

  testWidgets('保留期改档即时联动期限文案与标红', (tester) async {
    await seedSix();
    await tester.pumpWidget(trashApp());
    await settle5(tester);
    expect(find.text('剩 30 天'), findsNWidgets(TrashKind.values.length));
    await clearToasts(tester);

    // 走真实用户路径：档位是「记录管理 · 通用」那一个开关，改它＝改同一个 provider 态
    final c = ProviderScope.containerOf(tester.element(find.byType(TrashPage)));
    await c.read(settingsControllerProvider.notifier).setTrashKeepDays(7);
    await settle5(tester);
    expect(find.textContaining('删除 7 天后自动彻底删除'), findsOneWidget);
    expect(find.text('剩 7 天'), findsNWidgets(TrashKind.values.length),
        reason: '≤7 天全部标红（数量随类别走，V1.61 起七类）');
    await clearToasts(tester);
  });

  testWidgets('F5-3 档位入口＝屏右上角图标钮：半屏四档·选后落盘·屏头随动', (tester) async {
    await seedSix();
    await tester.pumpWidget(trashApp());
    await settle5(tester);
    final btn = find.byKey(const ValueKey('tt-keep'));
    expect(btn, findsOneWidget, reason: '入口在本屏右上角（记录管理那行已撤出）');
    await tester.tap(btn);
    await settle5(tester);
    expect(find.text('自动清理保留期'), findsOneWidget);
    for (final v in [7, 30, 90, 0]) {
      expect(find.byKey(ValueKey('tt-keep-$v')), findsOneWidget, reason: '缺档 $v');
    }
    expect(find.text('默认档'), findsOneWidget, reason: '副注在册（原型 sheetTrashKeep 同口径）');
    await tester.tap(find.byKey(const ValueKey('tt-keep-7')));
    await settle5(tester);
    expect(prefs.getInt('lh.trash_keep_days'), 7,
        reason: '必须落盘——只改内存态＝重启回 30 天，属假承诺');
    expect(find.textContaining('删除 7 天后自动彻底删除'), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('F5-3 「不清理」档：屏头改口且行内不再显示剩余天数', (tester) async {
    await seedSix();
    await tester.pumpWidget(trashApp());
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('tt-keep')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('tt-keep-0')));
    await settle5(tester);
    expect(prefs.getInt('lh.trash_keep_days'), 0);
    expect(find.textContaining('不自动清理'), findsOneWidget);
    expect(find.textContaining('剩 '), findsNothing, reason: '不清理档＝无期限读数');
    await clearToasts(tester);
  });

  testWidgets('F5-3 已落盘档位冷重载后仍回显·当前档高亮唯一', (tester) async {
    await boot(keepDays: 90);
    await tester.pumpWidget(trashApp());
    await settle5(tester);
    expect(find.textContaining('删除 90 天后自动彻底删除'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tt-keep')));
    await settle5(tester);
    expect(find.byIcon(Icons.check), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('模块写库后回收站自动重取（真机 6059 抓到：屏停在进屏前的缓存）', (tester) async {
    final n = await noteDao.save(Note(
        title: '走查项',
        content: 'x',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now()));
    await tester.pumpWidget(trashApp());
    await settle5(tester);
    expect(find.text('回收站是空的'), findsOneWidget);

    // 笔记模块的写点本来就会 invalidate notesProvider；回收站必须跟着重取
    await noteDao.softDelete(n.id!);
    final c = ProviderScope.containerOf(tester.element(find.byType(TrashPage)));
    c.invalidate(notesProvider);
    await settle5(tester);
    expect(find.textContaining('走查项'), findsOneWidget);
    expect(find.textContaining('1 项 · 删除 30 天后自动彻底删除'), findsOneWidget);
    expect(find.text('笔记 1'), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('待办页入口行：直达回收站待办段，计数与屏内同源', (tester) async {
    await seedSix();
    await tester.pumpWidget(entryApp(const TodoTrashEntry()));
    await settle5(tester);

    expect(find.text('回收站'), findsOneWidget);
    expect(find.textContaining('待办 1 项 · 保留期内可恢复'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('todo-trash-entry')));
    await settle5(tester);
    expect(find.byType(TrashPage), findsOneWidget);
    expect(find.textContaining('写周报'), findsOneWidget);
    expect(find.textContaining('晨跑'), findsNothing,
        reason: '入口落待办段，不是一屏全出');
    await clearToasts(tester);
  });
}
