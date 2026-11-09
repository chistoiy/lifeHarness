import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/settings/settings_repository.dart';
import 'package:lifeharness/features/calendar/data/category_dao.dart';
import 'package:lifeharness/features/calendar/data/time_block_dao.dart';
import 'package:lifeharness/features/calendar/domain/time_block.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_page.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart';
import 'package:lifeharness/features/calendar/presentation/widgets/time_pick_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// B10（2026-10-13 裁决）批注：原 EventRepository 两态流/冲突组随 events 面退役
/// 整组删除（规格退役，非回归）——「计时中」唯一源=时间块（V1.52），轴卡内结束；
/// 旧数据并入守卫见 time_legacy_merge_test.dart。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late TimeBlockDao tbDao;
  // F2-2 后切档持久化走 settingsController ⇒ 每个 pump 都要给真仓（mock prefs）。
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    tbDao = TimeBlockDao(db);
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('日程页：月历42格/视图切换/块卡可见（B10 后块单源）', (tester) async {
    final now = DateTime.now();
    final day0 = DateTime(now.year, now.month, now.day);
    await tbDao.markRange(day0, 10 * 60, 11 * 60,
        catId: 1, catName: '工作', note: '产品评审');

    await tester.pumpWidget(ProviderScope(
      overrides: [
        timeBlockDaoProvider.overrideWithValue(tbDao),
        legacyEventMergeDbProvider.overrideWithValue(db),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
        // 轮5 F5-2 后块视图默认折叠：本组用例靶子是展开态行为，显式给前提。
        settingsRepositoryProvider.overrideWithValue(SettingsRepository(prefs)),
        monthExpandedProvider.overrideWith((ref) => true),
      ],
      child: const MaterialApp(home: CalendarPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('${now.month}'), findsWidgets); // 月历含今天
    expect(find.textContaining('全天 0-24'), findsOneWidget); // 默认块视图（V1.19 四视图 · R14-8 后为刻度读数）

    // 视图菜单切轴：块卡可见（标题=note）。
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('☰ 轴 · 时间轴'));
    await tester.pumpAndSettle();
    expect(find.text('产品评审'), findsOneWidget);
  });

  testWidgets('V1.27 C1/C6：日历无「时间」标题行·月历去切月按钮行·展开态左右滑动切月',
      (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        timeBlockDaoProvider.overrideWithValue(tbDao),
        legacyEventMergeDbProvider.overrideWithValue(db),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
        // 轮5 F5-2 后块视图默认折叠：本组用例靶子是展开态行为，显式给前提。
        settingsRepositoryProvider.overrideWithValue(SettingsRepository(prefs)),
        monthExpandedProvider.overrideWith((ref) => true),
      ],
      child: const MaterialApp(home: CalendarPage()),
    ));
    await tester.pumpAndSettle();

    // C1：页内标题行删除（不再渲染「时间」大字标题），搜索在本行不丢
    expect(find.text('时间'), findsNothing);
    expect(find.byIcon(Icons.search), findsOneWidget);
    // C1：左上默认只显月日（当年不显年）
    expect(find.text('年'), findsNothing);
    // C6：切月按钮行已删
    expect(find.byIcon(Icons.chevron_left), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);

    // C6：展开态月历左滑 → 切到下月（分段移动手势保证 HorizontalDrag 过 slop+速度阈值）
    Future<void> swipeMonthPanel(int dx) async {
      final g = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('month-panel'))));
      await g.moveBy(Offset(dx / 4, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await g.moveBy(Offset(dx / 2, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await g.moveBy(Offset(dx / 4, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await g.up();
      await tester.pumpAndSettle();
    }

    await swipeMonthPanel(-200);
    final nm = now.month + 1;
    final wantMonth = ((nm - 1) % 12 + 1).toString().padLeft(2, '0');
    expect(tester.widget<Text>(find.byKey(const ValueKey('hd-month'))).data,
        wantMonth,
        reason: '头部月份应为下月 $wantMonth');

    // 右滑切回
    await swipeMonthPanel(200);
    expect(tester.widget<Text>(find.byKey(const ValueKey('hd-month'))).data,
        now.month.toString().padLeft(2, '0'));
  });

  testWidgets('V1.28 回归：月历末行日期完整可见（修复行高随屏宽放大被裁切）',
      (tester) async {
    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        timeBlockDaoProvider.overrideWithValue(tbDao),
        legacyEventMergeDbProvider.overrideWithValue(db),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
        // 轮5 F5-2 后块视图默认折叠：本组用例靶子是展开态行为，显式给前提。
        settingsRepositoryProvider.overrideWithValue(SettingsRepository(prefs)),
        monthExpandedProvider.overrideWith((ref) => true),
      ],
      child: const MaterialApp(home: CalendarPage()),
    ));
    await tester.pumpAndSettle();

    final panel = tester.getRect(find.byKey(const ValueKey('month-panel')));
    final cell = tester.getRect(find.text('$lastDay').last);
    expect(cell.top, greaterThanOrEqualTo(panel.top));
    expect(cell.bottom, lessThanOrEqualTo(panel.bottom + 0.5),
        reason: '末行（$lastDay 号）超出月历卡=被裁切，宽屏下曾必现');
  });

  testWidgets('智能折叠：下滚收起月历为周行 · 点展开 ▾ 回切', (tester) async {
    final now = DateTime.now();
    final day0 = DateTime(now.year, now.month, now.day);
    // B10：原 14 条事件种子改块表种子（撑出滚动量的作用不变）。
    for (var i = 0; i < 14; i++) {
      final s = (8 + (i % 10)) * 60;
      await tbDao.insert(TimeBlock(
          day: day0, startMin: s, endMin: s + 30, catName: '工作', note: '日程$i'));
    }
    await tester.pumpWidget(ProviderScope(
      overrides: [
        timeBlockDaoProvider.overrideWithValue(tbDao),
        legacyEventMergeDbProvider.overrideWithValue(db),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
        // 轮5 F5-2 后块视图默认折叠：本组用例靶子是展开态行为，显式给前提。
        settingsRepositoryProvider.overrideWithValue(SettingsRepository(prefs)),
        monthExpandedProvider.overrideWith((ref) => true),
      ],
      child: const MaterialApp(home: CalendarPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('展开 ▾'), findsNothing);

    await tester.fling(find.byType(ListView).first, const Offset(0, -150), 800);
    await tester.pumpAndSettle();
    expect(find.text('展开 ▾'), findsOneWidget);

    // 收起后列表停在滚动位，回顶再点展开（避免按钮被顶栏遮挡点不中）
    tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.text('展开 ▾'));
    await tester.pumpAndSettle();
    expect(find.text('展开 ▾'), findsNothing);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('V1.28⑧ 周视图：点已添加格子→详情可编辑 · 空格子才开补录弹层', (tester) async {
    final now = DateTime.now();
    final day0 = DateTime(now.year, now.month, now.day);
    await tbDao.markRange(day0, 10 * 60, 11 * 60,
        catId: 1, catName: '工作', note: '周视图评审');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        timeBlockDaoProvider.overrideWithValue(tbDao),
        legacyEventMergeDbProvider.overrideWithValue(db),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
        // 轮5 F5-2 后块视图默认折叠：本用例靶子是展开↔收起动画，显式给前提。
        settingsRepositoryProvider.overrideWithValue(SettingsRepository(prefs)),
        monthExpandedProvider.overrideWith((ref) => true),
      ],
      child: const MaterialApp(home: CalendarPage()),
    ));
    await tester.pumpAndSettle();

    // 切周视图（7×24）
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('▤ 周 · 7×24'));
    await tester.pumpAndSettle();
    expect(find.textContaining('空格子 → 添加时间段'), findsOneWidget);

    // C6 自然周（周日起算）：选中日列 di = weekday % 7（周一=1…周日=0），不再钉死 3。
    final di = now.weekday % 7;
    final used = find.byKey(ValueKey('wk-cell-$di-10'));
    await tester.ensureVisible(used);
    await tester.pumpAndSettle();
    await tester.tap(used);
    await tester.pumpAndSettle();
    expect(find.text('编辑时间块'), findsOneWidget);
    expect(find.text('保存修改'), findsOneWidget);
    expect(find.text('添加时间块'), findsNothing);

    // 关详情（点遮罩）后点 4 点空格子 → 才应开补录弹层
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    final empty = find.byKey(ValueKey('wk-cell-$di-4'));
    await tester.ensureVisible(empty);
    await tester.pumpAndSettle();
    await tester.tap(empty);
    await tester.pumpAndSettle();
    expect(find.text('添加时间块'), findsOneWidget);
  });

  testWidgets('V1.28⑤ 展开↔收起与切月动画：过渡后布局收敛，月历/周行各自就位',
      (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        timeBlockDaoProvider.overrideWithValue(tbDao),
        legacyEventMergeDbProvider.overrideWithValue(db),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
        // 轮5 F5-2 后块视图默认折叠：本用例靶子是展开↔收起动画，显式给前提。
        settingsRepositoryProvider.overrideWithValue(SettingsRepository(prefs)),
        monthExpandedProvider.overrideWith((ref) => true),
      ],
      child: const MaterialApp(home: CalendarPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('month-panel')), findsOneWidget);

    // 点选中日=收起为周行（AnimatedSize+Switcher 接管），settle 后无月历。
    // 限定月历卡内：块视图小时格也显「21」，全树 .last 会点错。
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('month-panel')),
        matching: find.text('${now.day}')));
    await tester.pumpAndSettle();
    expect(find.text('展开 ▾'), findsOneWidget);
    expect(find.byKey(const ValueKey('month-panel')), findsNothing);

    // 周行左右滑动切天（动画后仍收敛），再点展开回月历
    final g = await tester.startGesture(
        tester.getCenter(find.text('展开 ▾')).translate(0, 20));
    await g.moveBy(const Offset(-30, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await g.moveBy(const Offset(-60, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await g.up();
    await tester.pumpAndSettle();
    expect(find.text('展开 ▾'), findsOneWidget); // 未挂死/未溢出

    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.text('展开 ▾'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('month-panel')), findsOneWidget);
  });

  testWidgets('统一添加弹层：预选选中日时段 → 添加落库（补录·四视图同步）', (tester) async {
    final preset = DateTime(2026, 3, 17);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        timeBlockDaoProvider.overrideWithValue(tbDao),
        legacyEventMergeDbProvider.overrideWithValue(db),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () => showTimePickSheet(context, ref, day: preset, startMin: 9 * 60),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('添加时间块'), findsOneWidget);
    expect(find.textContaining('3/17'), findsWidgets); // 起始轮定位到 3月17日

    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    final rows = await db.query('time_blocks');
    expect(rows, hasLength(1));
    expect(rows.single['start_min'], 540);
    expect(rows.single['end_min'], 600);
  });
}
