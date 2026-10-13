import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/widgets/wheel_time.dart';
import 'package:lifeharness/features/calendar/data/category_dao.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart';
import 'package:lifeharness/core/widgets/wheel_date.dart';
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
  late EventBus bus;
  late SharedPreferences prefs;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    bus = EventBus();
    todoRepo = TodoRepository(TodoDao(db), bus);
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

    await tester.tap(find.byIcon(Icons.add).last); // FAB → 类型二选一
    await tester.pumpAndSettle();
    await tester.tap(find.text('普通待办'));
    await tester.pumpAndSettle();
    expect(find.text('新建待办'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '带时间点的任务');
    await tester.tap(find.text('时间点'));
    await tester.pumpAndSettle();
    expectSettled(tester, '切到「时间点」后');

    // 读控件初值 → 滑一格 → 期望"时 ±1、分不变"。CupertinoPicker 时柱 0~23 不换行，
    // 23 点向上/0 点向下滑不动，故按初值自适应方向（深夜/凌晨跑测均可确定断言）。
    final wheel = find.byKey(const ValueKey('tk-point'));
    expect(wheel, findsOneWidget);
    final initial = tester.widget<InlineWheelTime>(wheel).initial;
    final dir = initial.hour >= 23 ? -1 : 1;

    await tester.drag(find.byType(CupertinoPicker).first, Offset(0, -32.0 * dir));
    await tester.pumpAndSettle();
    expectSettled(tester, '「时间点」滚轮滑动后');

    final wantHour = (initial.hour + dir + 24) % 24;
    final wantMin = wantHour * 60 + initial.minute;

    await tester.ensureVisible(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final saved = await todoRepo.list();
    expect(saved.single.title, '带时间点的任务');
    expect(saved.single.timeMode, 'point');
    expect(saved.single.startMin, wantMin,
        reason: '滚轮选中的时间必须落库（初值 ${initial.hour}:${initial.minute} 滑一格 → $wantMin 分）');
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

    await tester.tap(find.byIcon(Icons.add).last); // FAB → 类型二选一
    await tester.pumpAndSettle();
    await tester.tap(find.text('普通待办'));
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
    // 时柱 0~23 不换行：需要 +2 格，22/23 点改向下（凌晨 0/1 点恒可向上）。
    final dir = startInit.hour >= 22 ? -1 : 1;

    // V1.27 表单变高：先把「止」轮滚入视口，否则 drag 落点被裁切、手势丢失。
    await tester.ensureVisible(endWheel);
    await tester.pumpAndSettle();

    // 「起」滑一格 → 时 dir；「止」滑两格 → 时 2*dir。
    // 两者起点相同，因此最终差值直接证明两只滚轮互不串味。
    await tester.drag(find.byType(CupertinoPicker).at(0), Offset(0, -32.0 * dir));
    await tester.pumpAndSettle();
    expectSettled(tester, '「起」滑动后');
    for (var i = 0; i < 2; i++) {
      await tester.drag(find.byType(CupertinoPicker).at(2), Offset(0, -32.0 * dir));
      await tester.pumpAndSettle();
    }
    expectSettled(tester, '「止」滑动后');

    // 时间段模式表单更高，保存按钮会被挤出视口，先滚到可见再点。
    await tester.ensureVisible(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final saved = await todoRepo.list();
    expect(saved.single.timeMode, 'range');
    final rawStart = ((startInit.hour + dir) % 24 + 24) % 24 * 60 + startInit.minute;
    final rawEnd = ((startInit.hour + 2 * dir) % 24 + 24) % 24 * 60 + startInit.minute;
    expect(saved.single.startMin, rawStart);
    // 表单既有约定：止≤起（跨零点回绕，深夜 22~23 点跑测时出现）→ endMin 归 0。
    // 「止」轮独立性守护：未回绕时必须=起+1 小时；回绕时也必须≠起（证明两轮不串味）。
    expect(saved.single.endMin, rawEnd <= rawStart ? 0 : rawEnd,
        reason: '「止」轮独立于「起」轮，两轮不能串味');
    expect(saved.single.endMin, isNot(rawStart));
  });
}
