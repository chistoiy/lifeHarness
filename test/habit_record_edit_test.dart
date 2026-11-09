import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/habit/data/habit_repository.dart';
import 'package:lifeharness/features/habit/domain/habit.dart';
import 'package:lifeharness/features/habit/domain/habit_calc.dart';
import 'package:lifeharness/features/habit/domain/habit_entry.dart';
import 'package:lifeharness/features/habit/presentation/habit_detail_page.dart';
import 'package:lifeharness/features/habit/presentation/habit_providers.dart';

/// 习惯批E · **打卡记录可改可删**（2026-10-18 产品令）。
///
/// 产品原话：「缺少修改打卡记录，删除或修改（打卡时间，数值这一类的）」。
/// 本组钉住三件事：
/// ① 详情页「打卡流水」每行可点开**那一天的记录编辑**（原来只读）；
/// ② 编辑弹层有**打卡时间**可改（原来只有自动落的首次时刻，没有入口）；
/// ③ 删除/撤销走仓库唯一出口 `deleteEntry`，改值保留原来源与补记标记
///    （改一条历史补记不该被洗成「手动」）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late dynamic db;
  late HabitRepository repo;

  String key(int back) => dayKey(DateTime.now().subtract(Duration(days: back)));

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = HabitRepository(db);
  });
  tearDown(() async => db.close());

  Future<void> pump(WidgetTester tester, String id) async {
    final c = ProviderContainer(
      overrides: [habitRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(home: HabitDetailPage(habitId: id)),
      ),
    );
    await settle5(tester);
  }

  testWidgets('流水行点开那一天的记录编辑（改打卡时间／数值／删除）', (tester) async {
    final h = await repo.saveHabit(Habit(name: '晨跑', startDate: key(30)));
    await repo.upsertEntry(
      h.id,
      day: key(2),
      checked: true,
      checkAt: '07:15',
      origin: HabitEntry.oBackfill,
      backfilled: true,
    );
    await pump(tester, h.id);

    // ① 点那天的流水行 → 打开记录编辑弹层（历史日标题是「记录 · 名」）。
    final row = find.byKey(ValueKey('hd-rec-${key(2)}'));
    await tester.ensureVisible(row);
    await settle5(tester);
    await tester.tap(row);
    await settle5(tester);
    expect(find.text('记录 · 晨跑'), findsOneWidget);
    // ② 打卡时间行在，且带着原记录的时刻（不是「此刻」）。
    expect(find.byKey(const ValueKey('hlog-at')), findsOneWidget);
    // 只断言弹层里的时刻行（详情页流水行本身也带同一串 '07:15'，不能全局找）。
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('hlog-at')),
        matching: find.text('07:15'),
      ),
      findsOneWidget,
    );
    // ③ 删除按钮（历史日叫「删除」，不叫「撤销」）。
    expect(find.text('删除'), findsOneWidget);

    // ④ 删除 → 库里当天记录消失。
    await tester.tap(find.byKey(const ValueKey('btn-hlog-undo')));
    await settle5(tester);
    expect((await repo.entriesOf(h.id))[key(2)], isNull);
  });

  testWidgets('日历点「今天」不再是死提示，而是打开当天记录编辑', (tester) async {
    final h = await repo.saveHabit(Habit(name: '早起', startDate: key(10)));
    await pump(tester, h.id);

    await tester.tap(find.byKey(ValueKey('hd-cal-${key(0)}')));
    await settle5(tester);
    // 旧实现只弹 toast「今天请在卡片上打卡或记量」，没有任何编辑入口。
    expect(find.text('打卡记量 · 早起'), findsOneWidget);
    expect(find.byKey(const ValueKey('hlog-at')), findsOneWidget);
    expect(find.byKey(const ValueKey('btn-hlog-save')), findsOneWidget);
  });

  testWidgets('布尔型习惯：记录编辑不出现数值区（量块按 hasVal 收）', (tester) async {
    final h = await repo.saveHabit(Habit(name: '冥想', startDate: key(10)));
    await repo.upsertEntry(h.id, day: key(1), checked: true, checkAt: '06:40');
    await pump(tester, h.id);

    final row = find.byKey(ValueKey('hd-rec-${key(1)}'));
    await tester.ensureVisible(row);
    await settle5(tester);
    await tester.tap(row);
    await settle5(tester);
    expect(find.byKey(const ValueKey('hlog-at')), findsOneWidget);
    // 布尔型没有「量」：数值输入框（hlog-val-0）不该出现。
    expect(find.byKey(const ValueKey('hlog-val-0')), findsNothing);
  });

  group('源码守护（防口径回退）', () {
    final sheets = File('lib/features/habit/presentation/habit_sheets.dart')
        .readAsStringSync();
    final detail = File('lib/features/habit/presentation/habit_detail_page.dart')
        .readAsStringSync();

    test('编辑弹层按日参数化，且打卡时间可改', () {
      expect(sheets, contains('Future<void> showHabitLogSheet('));
      expect(sheets, contains('String? day,'), reason: '缺 day 参数 ⇒ 只能编辑今天');
      expect(sheets, contains('String get k => widget.day ?? todayK;'));
      expect(sheets, contains("const ValueKey('hlog-at')"), reason: '缺打卡时间入口');
      expect(sheets, contains('showTimePicker('), reason: '打卡时间要能改到任意分钟');
      expect(sheets, contains('alwaysUse24HourFormat: true'), reason: '24 小时制，与流水列一致');
    });

    test('改记录保留原来源与补记标记（禁洗成手动）', () {
      expect(sheets, contains('origin: e?.origin ?? HabitEntry.oManual'),
          reason: '改一条补记/自动源记录不该把它改成「手动」');
      expect(sheets, contains('backfilled: e?.backfilled ?? !isToday'),
          reason: '补记标记要保留；历史日首次建记录按补记算');
      expect(sheets, contains('checkAt: _at'), reason: '保存必须用弹层里改过的时刻');
      expect(sheets, contains('await repo.deleteEntry(h.id, k)'),
          reason: '删除走仓库唯一出口（禁另写一套）');
    });

    test('详情页两处入口都指向它（今天格 ＋ 流水行）', () {
      expect(detail, contains('showHabitLogSheet(context, ref, h, day: k)'),
          reason: '日历今天格必须打开当天记录编辑');
      expect(detail, contains("ValueKey('hd-rec-"), reason: '流水行要可点');
      expect(detail, contains('day: dayKey(fd)'), reason: '流水行打开的是**那一天**');
      expect(detail, isNot(contains('今天请在卡片上打卡或记量')),
          reason: '旧的死提示已被编辑入口取代');
    });
  });
}
