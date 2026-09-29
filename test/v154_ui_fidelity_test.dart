/// V1.54 UI 保真批（R14-7/8/12/13/14 落 Flutter）验收钉桩：
///  ① 问候卡四个数字与「今日日程」列表同源同数（今日待办谓词＝截止日=今天）；
///  ② 问候语随「我的」页昵称联动，且卡面不含图形 emoji；
///  ③ 我的页资料可编辑：空昵称就地报错、保存后头像/昵称/副行与 prefs 同步；
///  ④ 在册书籍随书目联动；
///  ⑤ 设置族三页源码零图形 emoji、块视图与仪表盘教学文案已摘（源码级守门）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/settings/settings_repository.dart';
import 'package:lifeharness/features/calendar/data/category_dao.dart';
import 'package:lifeharness/features/calendar/data/event_dao.dart';
import 'package:lifeharness/features/calendar/data/time_block_dao.dart';
import 'package:lifeharness/features/calendar/domain/event_repository.dart';
import 'package:lifeharness/features/calendar/domain/time_block.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart';
import 'package:lifeharness/features/dashboard/presentation/dashboard_page.dart';
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/domain/journal_repository.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/settings/presentation/settings_page.dart';
import 'package:lifeharness/shared/linkage/stats_providers.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// 图形 emoji 判据（与原型校验脚本同款）：✓ ● › 这类文本符号不算。
final _emojiRe = RegExp(r'[\u{1F300}-\u{1FAFF}\u{FE0F}]', unicode: true);

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late SharedPreferences prefs;
  late EventBus bus;
  late TodoRepository todoRepo;
  late ReadRepository readRepo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    bus = EventBus();
    todoRepo = TodoRepository(TodoDao(db), bus);
    readRepo = ReadRepository(db);
  });

  tearDown(() async {
    await bus.dispose();
    await db.close();
  });

  ProviderContainer boot() => ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        todoRepositoryProvider.overrideWithValue(todoRepo),
        journalRepositoryProvider.overrideWithValue(JournalRepository(JournalDao(db))),
        readRepositoryProvider.overrideWithValue(readRepo),
        eventRepositoryProvider
            .overrideWithValue(EventRepository(EventDao(db), bus)),
        timeBlockDaoProvider.overrideWithValue(TimeBlockDao(db)),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
      ]);

  Future<ProviderContainer> pumpDash(WidgetTester tester) async {
    final c = boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c, child: const MaterialApp(home: DashboardPage())));
    await settle5(tester);
    return c;
  }

  Future<ProviderContainer> pumpSettings(WidgetTester tester) async {
    final c = boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c, child: const MaterialApp(home: SettingsPage())));
    await settle5(tester);
    return c;
  }

  String heroCount(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data ?? '';

  final today = DateTime.now();
  DateTime atToday(int hour) => DateTime(today.year, today.month, today.day, hour);

  group('问候卡口径（R14-14）', () {
    testWidgets('今日待办只数截止日=今天；无截止日与逾期不计', (tester) async {
      await todoRepo.add(Todo(title: '今天要办', dueAt: atToday(18)));
      await todoRepo.add(Todo(title: '没有期限'));
      await todoRepo.add(
          Todo(title: '已经逾期', dueAt: atToday(9).subtract(const Duration(days: 2))));
      await pumpDash(tester);
      expect(heroCount(tester, 'hero-todo-count'), '1',
          reason: '只有截止日=今天的那条计入');
    });

    testWidgets('完成环按今日 x/y 实算', (tester) async {
      final a = Todo(title: '已完成', dueAt: atToday(9), done: true);
      await todoRepo.add(a);
      await todoRepo.add(Todo(title: '未完成', dueAt: atToday(10)));
      final c = await pumpDash(tester);
      c.invalidate(todosProvider);
      await settle5(tester);
      expect(find.textContaining('1/2'), findsOneWidget,
          reason: '今日 2 条、完成 1 条');
    });

    testWidgets('场安排＝今日日程列表条数（事件+手动块，回填块不重复计）',
        (tester) async {
      await EventDao(db).insert(CalEvent(
          title: '评审', start: atToday(10), end: atToday(11), catId: null));
      final day0 = DateTime(today.year, today.month, today.day);
      await TimeBlockDao(db).insert(TimeBlock(
          day: day0, startMin: 540, endMin: 585, catName: '工作', note: '晨间规划'));
      // 事件回填块（source=event）不应再算一场：由事件本身表达。
      await TimeBlockDao(db).insert(TimeBlock(
          day: day0,
          startMin: 600,
          endMin: 660,
          catName: '工作',
          note: '评审',
          source: kSrcEvent));
      await pumpDash(tester);
      final shown = heroCount(tester, 'hero-plan-count');
      expect(shown, '2', reason: '1 事件 + 1 手动块');
      expect(find.byKey(const ValueKey('plan-row-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-row-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-row-2')), findsNothing);
    });

    testWidgets('问候语随昵称联动且不含图形 emoji', (tester) async {
      await SettingsRepository(prefs)
          .save(SettingsRepository(prefs).load().copyWith(profileNick: '小舟'));
      await pumpDash(tester);
      expect(find.textContaining('，小舟'), findsOneWidget);
      final greet = tester.widget<Text>(find.textContaining('，小舟')).data ?? '';
      expect(_emojiRe.hasMatch(greet), isFalse, reason: '问候语：$greet');
    });
  });

  group('我的页资料（R14-12/13）', () {
    testWidgets('编辑弹层：空昵称就地报错，保存后三处联动并落盘', (tester) async {
      await pumpSettings(tester);
      expect(find.text('本地用户'), findsOneWidget, reason: '未设置时的回落名');

      await tester.tap(find.byKey(const ValueKey('profile-edit')));
      await settle5(tester);
      expect(find.text('编辑资料'), findsOneWidget);

      // 空昵称：报错且不关弹层、不写库。
      await tester.tap(find.byKey(const ValueKey('pf-save')));
      await tester.pump();
      expect(find.text('昵称不能为空'), findsOneWidget);
      expect(find.text('编辑资料'), findsOneWidget);
      expect(SettingsRepository(prefs).load().profileNick, '');

      await tester.enterText(find.byKey(const ValueKey('pf-nick')), '小舟');
      await tester.enterText(find.byKey(const ValueKey('pf-bio')), '数据在手心里');
      await tester.tap(find.byKey(const ValueKey('pf-save')));
      await settle5(tester);

      expect(find.text('编辑资料'), findsNothing, reason: '保存后弹层关闭');
      expect(find.text('小舟'), findsOneWidget);
      expect(find.textContaining('数据在手心里'), findsOneWidget,
          reason: '签名并进资料卡副行');
      expect(find.text('小'), findsOneWidget, reason: '头像取昵称首字');
      final back = SettingsRepository(prefs).load();
      expect(back.profileNick, '小舟');
      expect(back.profileBio, '数据在手心里');
    });

    testWidgets('在册书籍随书目联动', (tester) async {
      final c = await pumpSettings(tester);
      expect(find.text('0'), findsWidgets, reason: '初始无书');
      final ms = DateTime.now().millisecondsSinceEpoch;
      await db.insert('books', {
        'id': 'b-test',
        'title': '测试书',
        'created_at': ms,
        'updated_at': ms,
      });
      // 只重算不重挂：二次 pumpWidget 会留下未到期定时器（框架断言会炸）。
      expect(await readRepo.allBooks(), hasLength(1),
          reason: '仓库应读到刚插入的书（否则是注入库与断言库不同一）');
      // 与写库侧同一触发方式：心跳自增（invalidate 会把 StateProvider 复位成同值，
      // 下游 watch 判定「没变化」就不重算了——这是个真坑）。
      c.read(readTickProvider.notifier).state++;
      expect(await c.read(shelfBookCountProvider.future), 1,
          reason: '数据层应随书目心跳重算');
      await settle5(tester);
      final cell = find.descendant(
          of: find.byKey(const ValueKey('stat-books')),
          matching: find.byType(Text));
      expect(tester.widgetList<Text>(cell).map((t) => t.data), contains('1'),
          reason: '加一本书后第三格应为 1');
    });
  });

  group('源码级守门（R14-7/8）', () {
    test('设置族三页零图形 emoji', () {
      for (final f in [
        'lib/features/settings/presentation/settings_page.dart',
        'lib/features/settings/presentation/recmg_page.dart',
        'lib/features/settings/presentation/notify_settings_page.dart',
        'lib/features/settings/presentation/profile_edit_sheet.dart',
      ]) {
        final src = File(f).readAsStringSync();
        final hits = _emojiRe.allMatches(src).map((m) => m[0]).toSet();
        expect(hits, isEmpty, reason: '$f 仍含图形 emoji：$hits');
      }
    });

    test('块视图与仪表盘教学文案已摘、刻度读数与分类标题在位', () {
      final grid = File(
              'lib/features/calendar/presentation/widgets/grid_day_view.dart')
          .readAsStringSync();
      expect(grid, contains(r"'1 格 = $gran 分 · 全天 0-24'"));
      expect(grid, isNot(contains('点右列分类=直接标记')));
      expect(grid, isNot(contains('选中=标记')));
      expect(grid, contains("Text('分类'"));
      final dash =
          File('lib/features/dashboard/presentation/dashboard_page.dart')
              .readAsStringSync();
      expect(dash, isNot(contains('长按任意卡片可编排顺序')));
      expect(dash, isNot(contains('点一下，记录今天的心情')));
      expect(dash, isNot(contains('CHIST')), reason: '问候语不再写死昵称');
    });
  });
}
