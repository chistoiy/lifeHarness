import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/features/calendar/data/time_block_dao.dart';
import 'package:lifeharness/features/calendar/presentation/widgets/time_pick_sheet.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 时间模块批1 测试环境（自用小件，不入全局 helpers）。
/// B10（2026-10-13 裁决）：events 面退役，原 eventsDaoOf 摘除——种子数据一律走块表。

/// 时间块 DAO 便捷构造（ffi 内存库直用）。
Future<TimeBlockDao> blocksDaoOf(Database db) async => TimeBlockDao(db);

/// 事件总线便捷构造。
EventBus busForTest() => EventBus();

/// 泵一个最小宿主页：点 `open-pick` 钮即开统一添加/编辑弹层（day/startMin 可预填）。
/// 各用例经 overrides 注入 ffi 内存库 DAO（不触 AppDatabase.instance）。
Future<void> pumpTimeHost(
  WidgetTester tester, {
  DateTime? day,
  int? startMin,
  required List<Override> overrides,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Consumer(
        builder: (context, ref, _) => Scaffold(
          floatingActionButton: FloatingActionButton(
            key: const ValueKey('open-pick'),
            onPressed: () =>
                showTimePickSheet(context, ref, day: day, startMin: startMin),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}
