/// C04 子批B · ICS 收集器守护（竞品补全批1）：三域映射 + 已完成待办状态。
/// 纯函数用例：不碰 DB、不碰 Widget。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/calendar/domain/ics_export.dart';
import 'package:lifeharness/features/calendar/domain/time_block.dart';
import 'package:lifeharness/features/days/domain/day_models.dart';
import 'package:lifeharness/features/todo/domain/todo.dart';
import 'package:lifeharness/shared/linkage/ics_collect.dart';

void main() {
  final d = DateTime(2026, 11, 6);

  test('时间块 → VEVENT：DTSTART=当日+startMin，SUMMARY=分类（note 并入标题）', () {
    final items = icsOfTimeBlocks([
      TimeBlock(
          day: d,
          startMin: 9 * 60,
          endMin: 11 * 60,
          catName: '阅读',
          note: '思考快与慢'),
      TimeBlock(day: d, startMin: 20 * 60, endMin: 21 * 60, catName: '运动'),
    ]);
    expect(items, hasLength(2));
    final ics = buildIcs(items, now: d);
    expect(ics, contains('SUMMARY:阅读 · 思考快与慢'));
    expect(ics, contains('DTSTART:20261106T090000'));
    expect(ics, contains('DTEND:20261106T110000'));
    expect(ics, contains('SUMMARY:运动'));
    expect(ics, isNot(contains('VTODO')));
  });

  test('时间块时间范围过滤：区间外的不导出（闭区间含端点）', () {
    final items = icsOfTimeBlocks([
      TimeBlock(day: DateTime(2026, 1, 1), startMin: 0, endMin: 60, catName: 'A'),
      TimeBlock(day: d, startMin: 0, endMin: 60, catName: 'B'),
    ], range: (from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 30)));
    expect(items.map((i) => i.title), ['B']);
  });

  test('待办 → VTODO：无到期日跳过；done 默认排除、includeDone 时导出且 STATUS:COMPLETED',
      () {
    final todos = [
      Todo(title: '买书', dueAt: d, done: false),
      Todo(title: '已完', dueAt: d, done: true),
      Todo(title: '无日期'), // dueAt=null → 没法落日历，跳过
    ];
    expect(icsOfTodos(todos).map((i) => i.title), ['买书']);
    final withDone = icsOfTodos(todos, includeDone: true);
    expect(withDone.map((i) => i.title), containsAll(['买书', '已完']));
    final ics = buildIcs(withDone, now: d);
    expect(ics, contains('BEGIN:VTODO'));
    expect(ics, contains('STATUS:NEEDS-ACTION'));
    expect(ics, contains('STATUS:COMPLETED'));
  });

  test('重要日子：once 无 RRULE；solarYear 出 FREQ=YEARLY；归档不导出', () {
    final days = [
      DayEntry(
          title: '纪念日',
          iconId: 'i',
          colorKey: 'c',
          category: '纪念',
          repeat: DayRepeat.once,
          targetDate: d),
      DayEntry(
          title: '生日',
          iconId: 'i',
          colorKey: 'c',
          category: '纪念',
          repeat: DayRepeat.solarYear,
          targetDate: DateTime(1990, 5, 20)),
      DayEntry(
          title: '归档项',
          iconId: 'i',
          colorKey: 'c',
          category: '纪念',
          repeat: DayRepeat.once,
          targetDate: d,
          archived: true),
    ];
    final ics = buildIcs(icsOfDays(days), now: d);
    expect(ics, contains('SUMMARY:纪念日'));
    // once 的那个 VEVENT 块不带 RRULE（按块切分断言，不能整串否定——
    // 生日(solarYear) 合法地带 RRULE）。
    final segs = ics.split('BEGIN:VEVENT');
    final once = segs.firstWhere((s) => s.contains('纪念日'));
    expect(once, isNot(contains('RRULE:')));
    expect(ics, contains('SUMMARY:生日'));
    expect(ics, contains('RRULE:FREQ=YEARLY'));
    expect(ics, isNot(contains('归档项')));
  });

  test('农历日子：按年展开为独立 VEVENT（UID 带年份后缀），无农历月日的跳过', () {
    final days = [
      DayEntry(
          title: '中秋家宴',
          iconId: 'i',
          colorKey: 'c',
          category: '纪念',
          repeat: DayRepeat.lunar,
          targetDate: DateTime(2026, 9, 25),
          lunarMonth: 8,
          lunarDay: 15),
      DayEntry(
          title: '缺月日',
          iconId: 'i',
          colorKey: 'c',
          category: '纪念',
          repeat: DayRepeat.lunar,
          targetDate: DateTime(2026, 9, 25)),
    ];
    final ics = buildIcs(icsOfDays(days), now: DateTime(2026, 11, 6));
    // 3 年视野内每年一个实例（2026/2027/2028）；缺 lunarMonth/Day 的不导出。
    expect('中秋家宴'.allMatches(ics).length, 3);
    expect(ics, contains('-2027@lifeharness.local'));
    expect(ics, isNot(contains('SUMMARY:缺月日')));
  });
}
