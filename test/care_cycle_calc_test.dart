import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/care/domain/care_models.dart';
import 'package:lifeharness/features/care/domain/cycle_calc.dart';

/// 呵护批1 · 周期推导纯函数（图例与规则三行逐条覆盖）。
void main() {
  CycleDay cd(String day, {String state = '', String? flow, List<String> syms = const []}) =>
      CycleDay(day: day, state: state, flow: flow, syms: syms);

  group('periodRuns', () {
    test('p1 起始 + 连续 p 合并为一段；断档即闭合', () {
      final days = {
        '2026-09-01': cd('2026-09-01', state: 'p1'),
        '2026-09-02': cd('2026-09-02', state: 'p'),
        '2026-09-03': cd('2026-09-03', state: 'p'),
        '2026-09-04': cd('2026-09-04', state: 'p'),
        '2026-09-08': cd('2026-09-08', state: 'p1'),
        '2026-09-09': cd('2026-09-09', state: 'p'),
      };
      final runs = periodRuns(days);
      expect(runs.length, 2);
      expect(runs[1].start, DateTime(2026, 9, 8));
      expect(runs[1].len, 2);
      expect(runs[0].start, DateTime(2026, 9, 1));
      expect(runs[0].len, 4);
    });

    test('断档 1 天即拆段（非连续经期日不并段）', () {
      final days = {
        '2026-09-01': cd('2026-09-01', state: 'p1'),
        '2026-09-02': cd('2026-09-02', state: 'p'),
        '2026-09-04': cd('2026-09-04', state: 'p'),
      };
      final runs = periodRuns(days);
      expect(runs.length, 2);
      expect(runs[1].len, 1);
    });
  });

  group('统计', () {
    test('cycleLengths / avg / regularity', () {
      final runs = [
        (start: DateTime(2026, 6, 1), len: 5),
        (start: DateTime(2026, 6, 29), len: 5), // +28
        (start: DateTime(2026, 7, 28), len: 4), // +29
        (start: DateTime(2026, 8, 26), len: 5), // +29
      ];
      expect(cycleLengths(runs), [28, 29, 29]);
      expect(avgCycleLen(runs)!, closeTo(28.67, 0.01));
      expect(regularity(runs).label, '优');
    });

    test('abnormalCycles 捕获超 ±7 天', () {
      final runs = [
        (start: DateTime(2026, 1, 1), len: 5),
        (start: DateTime(2026, 1, 29), len: 5), // 28
        (start: DateTime(2026, 3, 7), len: 5), // +37 异常
        (start: DateTime(2026, 4, 5), len: 5), // +29
      ];
      final abn = abnormalCycles(runs);
      expect(abn.length, 1);
      expect(abn.first.len, 37);
      expect(abn.first.index, 2);
    });
  });

  group('cycleNow 推导', () {
    final days = {
      '2026-08-11': cd('2026-08-11', state: 'p1'),
      '2026-09-08': cd('2026-09-08', state: 'p1'),
      '2026-09-09': cd('2026-09-09', state: 'p'),
      '2026-09-10': cd('2026-09-10', state: 'p'),
    };

    test('周期第 N 天 / 下次月经 / 排卵=前14天 / 易孕窗口', () {
      final now = cycleNow(days, DateTime(2026, 9, 19))!;
      expect(now.cycleDay, 12);
      expect(now.nextStart, DateTime(2026, 10, 6)); // 两段起始间隔 28 天为均值
      expect(now.ovDay, DateTime(2026, 9, 22));
      expect(now.fertileStart, DateTime(2026, 9, 17));
      expect(now.fertileEnd, DateTime(2026, 9, 23));
      expect(now.phase, '易孕期');
    });

    test('经期当日相位=月经期', () {
      final now = cycleNow(days, DateTime(2026, 9, 9))!;
      expect(now.phase, '月经期');
    });

    test('无记录返回 null（首屏空态）', () {
      expect(cycleNow(const {}, DateTime(2026, 9, 19)), isNull);
    });
  });

  test('careHms 与月龄口径', () {
    expect(careHms(45), '45min');
    expect(careHms(60), '1h');
    expect(careHms(90), '1h30′');
    expect(careAgeMonths(DateTime(2026, 1, 7), DateTime(2026, 9, 19)),
        closeTo(8.4, 0.05));
  });
}
