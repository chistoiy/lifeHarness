/// 9-① 拍板落钉（2026-09-30）：共享时间滚轮统一 **1 分钟粒度**，
/// 以及提醒下拉第二项必须写「自定义时间…」（真机反馈：原来跟着当前时刻显示成
/// 「提醒 · 当天 09:00」，与第一项同字面，看着像重复项）。
///
/// 滚轮是 `core/widgets/wheel_time.dart` 的共享件，待办提醒 / 待办设置时间 /
/// 日程事件 / 习惯提醒四处共用——这里钉「滑一格＝1 分钟」，防再被改回 5 分档。
library;

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/widgets/wheel_time.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_page.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('分钟滚轮滑一格＝1 分钟（不再 5 分吸附）', (tester) async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
    );
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    final repo = TodoRepository(TodoDao(db), EventBus());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todoRepositoryProvider.overrideWithValue(repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(home: TodoPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add).last); // FAB → 类型二选一
    await tester.pumpAndSettle();
    await tester.tap(find.text('普通待办'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '一分钟粒度校验');
    await tester.tap(find.text('时间点'));
    await tester.pumpAndSettle();

    final wheel = find.byKey(const ValueKey('tk-point'));
    final initial = tester.widget<InlineWheelTime>(wheel).initial;
    // 分钟柱＝第二只 CupertinoPicker；贴边时反向滑，保证断言可确定。
    final dir = initial.minute >= 59 ? -1 : 1;
    await tester.drag(
      find.byType(CupertinoPicker).last,
      Offset(0, -32.0 * dir),
    );
    await tester.pumpAndSettle();
    expect(
      tester.binding.hasScheduledFrame,
      isFalse,
      reason: '分钟柱滑一格后仍有待处理帧 → 滚轮与父层自激重建回环',
    );

    await tester.ensureVisible(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final saved = await repo.list();
    expect(
      saved.single.startMin! % 60,
      initial.minute + dir,
      reason:
          '滑一格应正好 ±1 分钟（初值 ${initial.minute} 分 → '
          '${initial.minute + dir} 分），改回 5 分档即红',
    );
  });

  group('提醒下拉第二项文案', () {
    const sheet = 'lib/features/todo/presentation/widgets/todo_edit_sheet.dart';

    /// 表单主体已按体积预算整块外提为 part（`todo_add_sheet.dart`），
    /// 源码级断言要扫**整个库**：宿主文件 + 同目录所有 `part of 'todo_edit_sheet.dart'` 的分片，
    /// 否则一拆文件就把文案锚点扫成假红（本用例首拆即踩）。
    String librarySrc() {
      final dir = File(sheet).parent;
      final parts = dir
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.path != sheet &&
              f.readAsStringSync().startsWith("part of 'todo_edit_sheet.dart';"))
          .map((f) => f.readAsStringSync());
      return [File(sheet).readAsStringSync(), ...parts].join('\n');
    }

    test('未选中时菜单写「自定义时间…」，选中后才显具体时刻', () {
      final src = librarySrc();
      expect(
        src,
        contains("'提醒 · 自定义时间…'"),
        reason: '菜单项要能一眼看出是自定义入口（原型 ntRemind 同字面）',
      );
      expect(src, contains('_remind == 3'), reason: '具体时刻只在选中自定义后才作为当前值显示');
    });

    test('共享滚轮不再出现 5 分档常量', () {
      final src = File('lib/core/widgets/wheel_time.dart').readAsStringSync();
      expect(
        src,
        contains('List.generate(60, (i) => i)'),
        reason: '分钟列必须 60 档',
      );
      expect(src, isNot(contains('i * 5')), reason: '5 分档字面不得回潮');
      expect(src, isNot(contains('clamp(0, 11)')), reason: '12 档索引钳制不得回潮');
    });
  });
}
