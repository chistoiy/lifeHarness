import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/widgets/wheel_time.dart';
import 'package:lifeharness/features/calendar/data/category_dao.dart';
import 'package:lifeharness/features/calendar/data/event_dao.dart';
import 'package:lifeharness/features/calendar/domain/cal_event.dart';
import 'package:lifeharness/features/calendar/domain/event_repository.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart';
import 'package:lifeharness/features/calendar/presentation/widgets/event_sheet.dart';
import 'package:lifeharness/features/calendar/presentation/widgets/wheel_date.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_page.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 内嵌滚轮（InlineWheelTime）专项守护。
///
/// 背景（2026-09-20 事故复盘）：`CupertinoPicker` 的 `onSelectedItemChanged`
/// 若**无条件 setState**，会把滚轮从"自己的选择回调"里重建一遍；新 children
/// delegate 可能再次触发选择上报 → 再 setState → 帧永不停（重则同帧无限重建，
/// `--timeout` 也杀不掉）。本文件锁定三类断言：
///   1. 挂载后 / 滑动后**没有待处理帧**（自激重建会让帧永不停）；
///   2. 滑动**必须回调父层**（不能为了消抖把功能改坏）；
///   3. 值要能一路走到落库（端到端，不只测控件）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late TodoRepository todoRepo;
  late EventRepository eventRepo;
  late EventBus bus;
  late SharedPreferences prefs;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    bus = EventBus();
    todoRepo = TodoRepository(TodoDao(db), bus);
    eventRepo = EventRepository(EventDao(db), bus);
    // TodoListView 监听 settingsControllerProvider（临期升紧急开关），需 prefs 桩
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    await db.close();
    await bus.dispose();
  });

  /// 挂载/滑动后必须"静止"：帧永不停 == 存在自激重建回环。
  void expectSettled(WidgetTester tester, String stage) {
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: '$stage：仍有待处理帧 → CupertinoPicker 与父层存在自激重建回环（会挂死）');
  }

  // ---------------------------------------------------------------- 控件级
  testWidgets('InlineWheelTime：挂载即静止，滑动回调父层且不自激重建', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 220,
            child: InlineWheelTime(
              initial: const TimeOfDay(hour: 9, minute: 30),
              onChanged: (h, m) => picked.add('$h:$m'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expectSettled(tester, '挂载后');

    // 小时轮上滑一格（itemExtent = 32）→ 9 时变 10 时
    await tester.drag(find.byType(CupertinoPicker).first, const Offset(0, -32));
    await tester.pumpAndSettle();
    expectSettled(tester, '小时轮滑动后');

    expect(picked, isNotEmpty, reason: '滑动必须回调父层（onChanged 不能失效）');
    expect(picked.last, '10:30', reason: '小时轮应上滑一格且分钟保持 30');
  });

  // ------------------------------------------------------- 真实入口：待办「时间点」
  testWidgets('待办添加弹层「时间点」：滚轮不挂死，选中值一路落库', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        todoRepositoryProvider.overrideWithValue(todoRepo),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const MaterialApp(home: TodoPage()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add).last); // FAB
    await tester.pumpAndSettle();
    expect(find.text('新建待办'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '带时间点的任务');
    await tester.tap(find.text('时间点'));
    await tester.pumpAndSettle();
    expectSettled(tester, '切到「时间点」后');

    // 读控件初值 → 上滑一格 → 期望"时 +1、分不变"（不依赖墙上时钟，可确定断言）
    final wheel = find.byKey(const ValueKey('tk-point'));
    expect(wheel, findsOneWidget);
    final initial = tester.widget<InlineWheelTime>(wheel).initial;

    await tester.drag(find.byType(CupertinoPicker).first, const Offset(0, -32));
    await tester.pumpAndSettle();
    expectSettled(tester, '「时间点」滚轮滑动后');

    final wantHour = (initial.hour + 1) % 24;
    final wantMin = wantHour * 60 + initial.minute;

    await tester.ensureVisible(find.text('存入四象限'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('存入四象限'));
    await tester.pumpAndSettle();

    final saved = await todoRepo.list();
    expect(saved.single.title, '带时间点的任务');
    expect(saved.single.timeMode, 'point');
    expect(saved.single.startMin, wantMin,
        reason: '滚轮选中的时间必须落库（初值 ${initial.hour}:${initial.minute} 上滑一格 → $wantMin 分）');
  });

  // ------------------------------------------------------- 真实入口：待办「时间段」
  testWidgets('待办添加弹层「时间段」：两只滚轮并存不挂死，起止均可落库', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        todoRepositoryProvider.overrideWithValue(todoRepo),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const MaterialApp(home: TodoPage()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '带时间段的任务');
    await tester.tap(find.text('时间段'));
    await tester.pumpAndSettle();
    expectSettled(tester, '切到「时间段」后');

    final startWheel = find.byKey(const ValueKey('tk-start'));
    final endWheel = find.byKey(const ValueKey('tk-end'));
    expect(startWheel, findsOneWidget);
    expect(endWheel, findsOneWidget);
    expect(find.byType(InlineWheelTime), findsNWidgets(2));

    final startInit = tester.widget<InlineWheelTime>(startWheel).initial;

    // 「起」上滑一格 → 时 +1；「止」上滑两格 → 时 +2。
    // 两者起点相同，因此最终差值直接证明两只滚轮互不串味。
    await tester.drag(find.byType(CupertinoPicker).at(0), const Offset(0, -32));
    await tester.pumpAndSettle();
    expectSettled(tester, '「起」滑动后');
    for (var i = 0; i < 2; i++) {
      await tester.drag(find.byType(CupertinoPicker).at(2), const Offset(0, -32));
      await tester.pumpAndSettle();
    }
    expectSettled(tester, '「止」滑动后');

    // 时间段模式表单更高，保存按钮会被挤出视口，先滚到可见再点。
    await tester.ensureVisible(find.text('存入四象限'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('存入四象限'));
    await tester.pumpAndSettle();

    final saved = await todoRepo.list();
    expect(saved.single.timeMode, 'range');
    expect(saved.single.startMin, ((startInit.hour + 1) % 24) * 60 + startInit.minute);
    expect(saved.single.endMin,
        ((startInit.hour + 2) % 24) * 60 + startInit.minute,
        reason: '「止」轮独立于「起」轮，两轮不能串味');
  });

  // ------------------------------------------------------- 真实入口：日程编辑弹层
  testWidgets('日程编辑弹层：开始时间滚轮不挂死，并可改开始时分', (tester) async {
    final e = CalEvent(
        title: '评审',
        start: DateTime(2026, 3, 17, 9, 30),
        end: DateTime(2026, 3, 17, 10, 30));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        eventRepositoryProvider.overrideWithValue(eventRepo),
        categoryDaoProvider.overrideWithValue(CategoryDao(db)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () => showEventEditSheet(context, ref, e),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expectSettled(tester, '日程编辑弹层打开后');

    // 表单里唯一的开关是「全天」；关闭状态才显示开始时间滚轮。
    expect(find.byType(InlineWheelTime), findsOneWidget);
    final init = tester.widget<InlineWheelTime>(find.byType(InlineWheelTime)).initial;
    expect(init, const TimeOfDay(hour: 9, minute: 30)); // 初值来自事件开始时间

    await tester.drag(find.byType(CupertinoPicker).first, const Offset(0, -32));
    await tester.pumpAndSettle();
    expectSettled(tester, '日程编辑滚轮滑动后');
    expect(find.text('10'), findsWidgets, reason: '开始时间应可由滚轮改为 10 时');
  });

  // ------------------------------------------------- 同族：日期轮（年/月/日三列）
  testWidgets('日期轮（年/月/日）：三列并存不挂死，滑动后可确定返回新日期', (tester) async {
    DateTime? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async =>
                result = await showWheelDatePick(context, DateTime(2026, 3, 17)),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expectSettled(tester, '日期轮弹层打开后');
    expect(find.text('选择日期'), findsOneWidget);
    expect(find.byType(CupertinoPicker), findsNWidgets(3)); // 年 / 月 / 日

    // 第 2 列 = 月，上滑一格（itemExtent = 34）→ 3 月变 4 月
    await tester.drag(find.byType(CupertinoPicker).at(1), const Offset(0, -34));
    await tester.pumpAndSettle();
    expectSettled(tester, '月份轮滑动后');

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.year, 2026);
    expect(result!.month, 4, reason: '月份轮上滑一格应从 3 月到 4 月');
    expect(result!.day, 17, reason: '只动了月份列，日不应被牵动');
  });
}
