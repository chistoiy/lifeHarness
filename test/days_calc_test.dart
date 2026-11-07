import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/days/domain/day_calc.dart';
import 'package:lifeharness/features/days/domain/day_models.dart';

/// 批1 · 日子引擎回归（V1.42 模块11 四重复方式实算口径）。
void main() {
  final today = DateTime(2026, 9, 19);

  DayEntry entry({
    int id = 1,
    DayRepeat repeat = DayRepeat.solarYear,
    DateTime? target,
    int? lm,
    int? ld,
    int? md,
    List<int> rem = const [30, 7, 0],
    bool pinned = false,
    bool archived = false,
    String cat = '倒数',
  }) =>
      DayEntry(
        id: id,
        title: 'T$id',
        iconId: 'cake',
        colorKey: 'rose',
        category: cat,
        repeat: repeat,
        targetDate: target,
        lunarMonth: lm,
        lunarDay: ld,
        monthDay: md,
        remOffsets: rem,
        pinned: pinned,
        archived: archived,
      );

  group('nextOccurrence', () {
    test('solarYear：本月已过则滚到明年同日', () {
      final d = entry(target: DateTime(2025, 3, 12));
      expect(nextOccurrence(d, today), DateTime(2027, 3, 12));
      final e = entry(target: DateTime(2025, 9, 19));
      expect(nextOccurrence(e, today), DateTime(2026, 9, 19)); // 当天=今天
    });
    test('solarYear：2/29 平年收敛 2/28', () {
      final d = entry(target: DateTime(2024, 2, 29));
      expect(nextOccurrence(d, today), DateTime(2027, 2, 28)); // 09-19 视角：2026 收敛日已过
      final d28 = DateTime(2026, 2, 28);
      expect(nextOccurrence(d, d28), DateTime(2026, 2, 28)); // 当年收敛日=今天
    });
    test('lunar：八月廿七 2026 实算 10-07（原型示意值 10-17 不实）', () {
      final d = entry(repeat: DayRepeat.lunar, lm: 8, ld: 27);
      expect(nextOccurrence(d, today), DateTime(2026, 10, 7));
    });
    test('lunar：本年已过自动换下一年', () {
      final d = entry(repeat: DayRepeat.lunar, lm: 1, ld: 1); // 春节
      expect(nextOccurrence(d, today), DateTime(2027, 2, 6));
    });
    test('monthly：31 号在小月收敛月末，2 月 30 日 → 28/29', () {
      final d = entry(repeat: DayRepeat.monthly, md: 31);
      expect(nextOccurrence(d, today), DateTime(2026, 9, 30));
      expect(nextOccurrence(d, DateTime(2026, 10, 1)), DateTime(2026, 10, 31));
      final f = entry(repeat: DayRepeat.monthly, md: 30);
      expect(nextOccurrence(f, DateTime(2027, 2, 1)), DateTime(2027, 2, 28));
    });
    test('once：锚点即结果（可过去）', () {
      final d = entry(repeat: DayRepeat.once, target: DateTime(2026, 9, 16));
      expect(countdownDays(d, today), -3);
      expect(isOverdue(d, today), isTrue);
    });
  });

  group('countdown 与标签', () {
    test('once 未来＝正数；标签显完整日期', () {
      final d = entry(repeat: DayRepeat.once, target: DateTime(2026, 10, 17));
      expect(countdownDays(d, today), 28);
      expect(occurrenceLabel(d, today), '2026-10-17');
    });
    test('lunar 标签带农历与实算公历对应', () {
      final d = entry(repeat: DayRepeat.lunar, lm: 8, ld: 27);
      expect(occurrenceLabel(d, today), '农历 八月廿七 · 对应公历 10-07');
    });
    test('monthly 标签', () {
      final d = entry(repeat: DayRepeat.monthly, md: 30);
      expect(occurrenceLabel(d, today), '每月 30 日 · 循环');
    });
    test('once 过期标签带「去处理」', () {
      final d = entry(repeat: DayRepeat.once, target: DateTime(2026, 9, 16));
      expect(occurrenceLabel(d, today), '已过 3 天 · 去处理');
    });
  });

  group('upcomingReminders（视界 45 天）', () {
    test('10-07 农历生日 · 提前30 触发日 09-07 已过不排，仅 7/0 落窗', () {
      final d = entry(repeat: DayRepeat.lunar, lm: 8, ld: 27);
      final hits = upcomingReminders(d, today, 45);
      // 按触发日升序；30 档触发日在过去 → 排除
      expect(hits.map((h) => h.offset).toList(), [7, 0]);
      final o7 = hits.firstWhere((h) => h.offset == 7);
      expect(o7.remindAt, DateTime(2026, 9, 30)); // 10-07 减 7 天
    });
    test('锚点超窗（提前档落在窗内也要评估）', () {
      // 发生日 10-07（18 天后）+ 提前 30 → 触发日 09-07 已过 → 不排
      final d = entry(repeat: DayRepeat.lunar, lm: 8, ld: 27, rem: [30]);
      expect(upcomingReminders(d, today, 10), isEmpty);
    });
    test('归档与无 id 不排', () {
      expect(upcomingReminders(entry(archived: true), today, 45), isEmpty);
      final noId = DayEntry(
          title: 'x',
          iconId: 'cake',
          colorKey: 'rose',
          category: '倒数',
          repeat: DayRepeat.once,
          targetDate: DateTime(2026, 10, 1));
      expect(upcomingReminders(noId, today, 45), isEmpty);
    });
  });

  group('排序与仪表盘', () {
    test('sortDays：置顶恒前，其余按 |倒数| 最近/最久', () {
      final a = entry(id: 1, repeat: DayRepeat.once, target: DateTime(2026, 12, 31));
      final b = entry(id: 2, repeat: DayRepeat.once, target: DateTime(2026, 9, 22), pinned: true);
      final c = entry(id: 3, repeat: DayRepeat.once, target: DateTime(2026, 10, 17));
      final asc = sortDays([a, b, c], today).map((d) => d.id).toList();
      expect(asc, [2, 3, 1]);
      final desc = sortDays([a, b, c], today, asc: false).map((d) => d.id).toList();
      expect(desc, [2, 1, 3]);
    });
    test('dashboardUpcoming：排除过期 once，置顶第一，剩 3 条升序', () {
      final past = entry(id: 1, repeat: DayRepeat.once, target: DateTime(2026, 9, 1));
      final far = entry(id: 2, repeat: DayRepeat.once, target: DateTime(2027, 1, 25));
      final soon = entry(id: 3, repeat: DayRepeat.once, target: DateTime(2026, 9, 30));
      final mid = entry(id: 4, repeat: DayRepeat.once, target: DateTime(2026, 11, 3));
      final pin = entry(id: 5, repeat: DayRepeat.once, target: DateTime(2026, 12, 1), pinned: true);
      final out = dashboardUpcoming([past, far, soon, mid, pin], today)
          .map((d) => d.id)
          .toList();
      expect(out, [5, 3, 4]);
    });
  });
}
