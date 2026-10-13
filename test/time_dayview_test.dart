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
import 'package:lifeharness/features/calendar/presentation/calendar_page.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart';
import 'package:lifeharness/features/todo/domain/todo.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// F4-1（时间模块批2 · 冻结口径）日视图三件：
/// ① 定时待办紫行按起始小时落位（与轴视图同源口径，仅今天、非 all）；
/// ② 当前时间红线游标落当前小时（「现在」标）；
/// ③ 秒级 HH:MM:SS 时钟每秒刷新。
///
/// 注意：日视图今天档有 1s 周期 Timer ⇒ 本文件**禁用 pumpAndSettle**（永不收敛），
/// 一律用有界 pump。时钟文本取真实墙钟 ⇒ 不可比文本值（pump 1s 实墙钟只走毫秒），
/// 改断言「格式合法 ＋ Timer 触发重建（Text 实例更换）」。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    prefs = await SharedPreferences.getInstance();
  });
  tearDown(() async => db.close());

  Future<void> pumpDay(WidgetTester tester, {List<Todo> todos = const []}) async {
    // 大视口：24 小时行全量构建（ListView 懒构建，默认 800x600 下方行不进树）。
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        calViewModeProvider.overrideWith((ref) => 'day'),
        monthExpandedProvider.overrideWith((ref) => true),
        eventRepositoryProvider.overrideWithValue(EventRepository(
            EventDao(db), EventBus(),
            tbDao: TimeBlockDao(db))),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
        timeBlockDaoProvider.overrideWithValue(TimeBlockDao(db)),
        settingsRepositoryProvider.overrideWithValue(SettingsRepository(prefs)),
        todosProvider.overrideWith((ref) async => todos),
      ],
      child: const MaterialApp(home: CalendarPage()),
    ));
    // 有界 pump 刷异步 provider（禁 pumpAndSettle：今天档时钟 Timer 永动）。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
  }

  Finder hourRow(String label) => find
      .ancestor(of: find.text(label), matching: find.byType(InkWell))
      .first;

  testWidgets('① 紫行落位：point/span 定时待办按起始小时入行，all 不入',
      (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // 归属日=截止日，无截止日=创建日 ⇒ 三条都用 createdAt 钉今天。
    await pumpDay(tester, todos: [
      Todo(
          title: '回邮件',
          timeMode: 'point',
          startMin: 9 * 60 + 30,
          createdAt: today),
      Todo(
          title: '写周报',
          timeMode: 'span',
          startMin: 13 * 60,
          endMin: 14 * 60,
          createdAt: today),
      const Todo(title: '全天事项', timeMode: 'all'),
    ]);

    // point：9:30 落 9 点行。
    expect(find.textContaining('定时待办 · 回邮件'), findsOneWidget);
    expect(
        find.descendant(
            of: hourRow('9:00'),
            matching: find.textContaining('定时待办 · 回邮件')),
        findsOneWidget);
    expect(
        find.descendant(
            of: hourRow('10:00'),
            matching: find.textContaining('定时待办 · 回邮件')),
        findsNothing);

    // span：13:00-14:00 落 13 点行，且时间前缀带区间。
    expect(find.textContaining('13:00-14:00 定时待办 · 写周报'), findsOneWidget);
    expect(
        find.descendant(
            of: hourRow('13:00'),
            matching: find.textContaining('定时待办 · 写周报')),
        findsOneWidget);

    // all（全天）不入日视图小时行（与轴视图「全天」行口径分离，原型同款）。
    expect(find.textContaining('定时待办 · 全天事项'), findsNothing);
  });

  testWidgets('② 红线游标：当前小时行含「现在」标且小时号正确', (tester) async {
    await pumpDay(tester);

    // 占位「现在」24 行全有（透明对齐原型）⇒ 只钉玫红可见那枚。
    final roseNow = find.byWidgetPredicate((w) =>
        w is Text &&
        w.data == '现在' &&
        w.style?.color == const Color(0xFFF43F5E));
    expect(roseNow, findsOneWidget);
    final nowHour = DateTime.now().hour;
    final curRow = find
        .ancestor(of: roseNow, matching: find.byType(InkWell))
        .first;
    expect(
        find.descendant(of: curRow, matching: find.text('$nowHour:00')),
        findsOneWidget);
    // 非当前小时行不带「现在」标（全局唯一已由 findsOneWidget 覆盖）。
  });

  testWidgets('③ 秒级时钟：HH:MM:SS 格式合法且 Timer 每秒触发重建', (tester) async {
    await pumpDay(tester);

    final clock = find.byKey(const ValueKey('day-clock'));
    expect(clock, findsOneWidget);
    final t1 = tester.widget<Text>(clock);
    expect(RegExp(r'^\d{2}:\d{2}:\d{2}$').hasMatch(t1.data ?? ''), isTrue,
        reason: '时钟文本须为秒级 HH:MM:SS，实际=${t1.data}');

    // 推进 1 秒 ⇒ Timer.periodic 触发 setState ⇒ 时钟 Text 重建（实例更换）。
    await tester.pump(const Duration(seconds: 1, milliseconds: 50));
    final t2 = tester.widget<Text>(clock);
    expect(identical(t1, t2), isFalse,
        reason: '1 秒后时钟 Text 未重建 ⇒ 秒级刷新 Timer 未生效');
    expect(RegExp(r'^\d{2}:\d{2}:\d{2}$').hasMatch(t2.data ?? ''), isTrue);

    // 再推 1 秒仍持续跳动（抽查第二拍）。
    await tester.pump(const Duration(seconds: 1, milliseconds: 50));
    final t3 = tester.widget<Text>(clock);
    expect(identical(t2, t3), isFalse);
  });
}
