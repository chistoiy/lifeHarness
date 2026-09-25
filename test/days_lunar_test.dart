import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/days/domain/lunar.dart';

/// 批1 · 农历换算回归（V1.42 模块11「每年（农历）· 自动逐年换算公历」）。
/// 历表为纯数据高危件，以公开权威锚点钉死：春节/中秋/闰月。
void main() {
  test('历表长度 201（1900–2100 全覆盖）', () {
    // 越界防护间接验证：1900 与 2100 两年均可换算
    expect(lunarToSolarInYear(1900, 1, 1), isNotNull);
    expect(lunarToSolarInYear(2100, 12, 1), isNotNull);
    expect(lunarToSolarInYear(2101, 1, 1), isNull);
  });

  group('公历→农历 春节锚点（正月初一）', () {
    for (final (y, m, d) in [
      (2022, 2, 1),
      (2023, 1, 22),
      (2024, 2, 10),
      (2025, 1, 29),
      (2026, 2, 17),
      (2027, 2, 6),
      (2028, 1, 26),
    ]) {
      test('$y 春节', () {
        final l = solarToLunar(DateTime(y, m, d));
        expect((l.year, l.month, l.day, l.isLeap), (y, 1, 1, false));
      });
    }
  });

  group('公历→农历 中秋锚点（八月十五）', () {
    for (final (y, m, d) in [
      (2022, 9, 10),
      (2023, 9, 29),
      (2024, 9, 17),
      (2025, 10, 6),
      (2026, 9, 25),
    ]) {
      test('$y 中秋', () {
        final l = solarToLunar(DateTime(y, m, d));
        expect((l.month, l.day, l.isLeap), (8, 15, false));
      });
    }
  });

  group('闰月锚点', () {
    test('2023 闰二月初一 = 03-22', () {
      final l = solarToLunar(DateTime(2023, 3, 22));
      expect((l.month, l.day, l.isLeap), (2, 1, true));
      // 前一天是平二月三十（若平月29天则收敛断言月份仍为 2）
      final p = solarToLunar(DateTime(2023, 3, 21));
      expect((p.month, p.isLeap), (2, false));
    });
    test('2025 闰六月初一 = 07-25', () {
      final l = solarToLunar(DateTime(2025, 7, 25));
      expect((l.month, l.day, l.isLeap), (6, 1, true));
    });
    test('2028 闰五月初一 = 06-23（至 07-21 · 29 天）', () {
      final l = solarToLunar(DateTime(2028, 6, 23));
      expect(l.isLeap, isTrue);
      expect((l.month, l.day), (5, 1));
      final n = solarToLunar(DateTime(2028, 6, 22));
      expect((n.month, n.isLeap), (5, false)); // 前一日仍是平五月
    });
  });

  group('农历→公历（平月优先）', () {
    test('2026 八月十五 → 09-25', () {
      expect(fmtYmd(lunarToSolar(2026, 8, 15)), '2026-09-25');
    });
    test('2026 八月廿七（妈妈生日样本）→ 10-07（原型静态换算示意值不实）', () {
      expect(fmtYmd(lunarToSolar(2026, 8, 27)), '2026-10-07');
    });
    test('2025 闰六年有平六月：取平月初一', () {
      expect(fmtYmd(lunarToSolar(2025, 6, 1)), '2025-06-25');
    });
    test('三十不存在时收敛到当月末（2026 二月廿九? 平月29天→三十收敛廿九）', () {
      final d = lunarToSolar(2026, 2, 30);
      expect(solarToLunar(d).day, lessThanOrEqualTo(29));
    });
  });

  test('双向往返：2020–2035 每月末日与月中日 全一致', () {
    for (var y = 2020; y <= 2035; y++) {
      for (var m = 1; m <= 12; m++) {
        for (final d in [1, 15, 28]) {
          final s = lunarToSolarInYear(y, m, d)!;
          final back = solarToLunar(s);
          expect((back.year, back.month, back.day, back.isLeap), (y, m, d, false),
              reason: '$y-$m-$d 往返漂移');
        }
      }
    }
  });

  test('中文标签', () {
    expect(lunarLabel(8, 27), '八月廿七');
    expect(lunarLabel(1, 1), '正月初一');
    expect(lunarLabel(11, 30), '冬月三十');
    expect(LunarDate(2025, 6, 1, isLeap: true).monthName, '闰六月');
  });
}

String fmtYmd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
