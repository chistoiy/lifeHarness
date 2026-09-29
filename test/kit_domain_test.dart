import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/kits/domain/kit_datec.dart';
import 'package:lifeharness/features/kits/domain/kit_rand.dart';

/// V1.47 批2 · 日期计算 + 随机数域层用例（时钟与随机源全部注入，禁时间炸弹）。
void main() {
  group('1 · 日期换算基础', () {
    test('ISO 互转与非法输入', () {
      expect(kitIsoDate(DateTime(2026, 9, 5)), '2026-09-05');
      expect(kitParseIsoDate('2026-9-5'), DateTime(2026, 9, 5));
      expect(kitParseIsoDate('2026-13-01'), isNull);
      expect(kitParseIsoDate(''), isNull);
      expect(kitParseIsoDate('今天'), isNull);
    });

    test('自然日差不受时分秒影响', () {
      expect(kitDayDiff(DateTime(2026, 1, 1, 23, 59), DateTime(2026, 1, 2, 0, 1)), 1);
      expect(kitDayDiff(DateTime(2026, 3, 1), DateTime(2026, 3, 1)), 0);
      expect(kitDayDiff(DateTime(2026, 3, 5), DateTime(2026, 3, 1)), -4);
    });

    test('周几中文（周一~周日）', () {
      expect(kitWeekdayLabel(DateTime(2026, 9, 27)), '日');
      expect(kitWeekdayLabel(DateTime(2026, 9, 28)), '一');
    });

    test('农历换算锚点：2026 春节 = 正月初一', () {
      expect(kitLunarLabel(DateTime(2026, 2, 17)), '正月初一');
      expect(kitLunarLabel(DateTime(1899, 1, 1)), ''); // 超出历表面静默留空
    });
  });

  group('2 · ① 两日期间隔', () {
    test('同一天 / 30 天 / 目标在前', () {
      final d = DateTime(2026, 6, 1);
      expect(kitDateDiffText(d, d), contains('（同一天）'));
      final t = kitDateDiffText(d, d.add(const Duration(days: 30)));
      expect(t, startsWith('相差 30 天 ≈ 4.3 周 · 1.0 个月'));
      expect(t, contains('目标在后'));
      expect(kitDateDiffText(d.add(const Duration(days: 10)), d), contains('目标在前'));
    });

    test('双端农历串带出两色日期', () {
      final s = kitDateDiffLunarText(DateTime(2026, 2, 17), DateTime(2026, 9, 25));
      expect(s, contains('2026-02-17（正月初一）'));
      expect(s, contains('2026-09-25'));
    });
  });

  group('3 · ② 日期 ± 天数', () {
    test('0 天不产出结果（原型无该分支）', () {
      expect(kitDateAdd(DateTime(2026, 6, 1), 0), isNull);
    });

    test('往后 N 天文案 + 分享串', () {
      final r = kitDateAdd(DateTime(2026, 9, 28), 100)!;
      expect(kitIsoDate(r.date), '2027-01-06');
      expect(r.label, contains('100 天后'));
      expect(r.label, contains('周三'));
      expect(r.isWeekend, isFalse);
      expect(r.shareFrom(DateTime(2026, 9, 28)), '2026-09-28 +100 → 2027-01-06');
    });

    test('往前落周末要标注', () {
      final r = kitDateAdd(DateTime(2026, 9, 28), -2)!; // 周六
      expect(kitIsoDate(r.date), '2026-09-26');
      expect(r.label, contains('往前 2 天'));
      expect(r.label, contains('落在周末'));
      expect(r.lunar, isNotEmpty);
    });
  });

  group('4 · ③ 今天速览与快捷锚点', () {
    test('年中：已过 / 剩余 / 距元旦', () {
      final s = kitTodayQuick(DateTime(2026, 6, 1));
      expect(s, contains('今年已过 152 天'));
      expect(s, contains('剩余 213 天'));
      expect(s, contains('距元旦 214 天'));
      expect(s, contains('2026-06-01 · 周一'));
    });

    test('元旦/圣诞取「下一个」，今年未过则取今年', () {
      final mid = DateTime(2026, 9, 29);
      expect(kitAnchorDate(KitDateAnchor.newYear, mid), DateTime(2027, 1, 1));
      expect(kitAnchorDate(KitDateAnchor.newYear, DateTime(2026, 1, 1)), DateTime(2026, 1, 1));
      expect(kitAnchorDate(KitDateAnchor.christmas, mid), DateTime(2026, 12, 25));
      expect(kitAnchorDate(KitDateAnchor.christmas, DateTime(2026, 12, 26)), DateTime(2027, 12, 25));
      expect(kitAnchorDate(KitDateAnchor.today, DateTime(2026, 9, 29, 23, 59)), DateTime(2026, 9, 29));
    });

    test('春节按农历历表取下一个正月初一', () {
      expect(kitAnchorDate(KitDateAnchor.spring, DateTime(2026, 1, 1)), DateTime(2026, 2, 17));
      expect(kitAnchorDate(KitDateAnchor.spring, DateTime(2026, 3, 1)), DateTime(2027, 2, 6));
    });
  });

  group('5 · 随机数生成', () {
    test('区间非法与不重复个数上限', () {
      final rnd = math.Random(1);
      expect(kitRandGenerate(min: 5, max: 1, count: 3, unique: false, rnd: rnd).error,
          '区间不合法：起点需 ≤ 终点');
      final u = kitRandGenerate(min: 1, max: 3, count: 4, unique: true, rnd: rnd);
      expect(u.error, '不重复模式下个数需 ≤ 区间大小（3）');
    });

    test('不重复模式结果互不相同且落在区间内', () {
      final o = kitRandGenerate(min: 1, max: 49, count: 6, unique: true, rnd: math.Random(7));
      expect(o.ok, isTrue);
      expect(o.values.length, 6);
      expect(o.values.toSet().length, 6);
      for (final v in o.values) {
        final n = int.parse(v);
        expect(n, inInclusiveRange(1, 49));
      }
    });

    test('个数截到 50（原型 Math.min(50,…)）', () {
      final o = kitRandGenerate(min: 1, max: 100, count: 999, unique: false, rnd: math.Random(2));
      expect(o.values.length, kKitRandMaxCount);
    });

    test('可复现：固定种子同参数同结果', () {
      a() => kitRandGenerate(min: 1, max: 100, count: 3, unique: false, rnd: math.Random(42)).text;
      expect(a(), a());
    });

    test('分享文案（原型 KIT_SHARE_TXT）', () {
      final o = kitRandGenerate(min: 1, max: 6, count: 1, unique: false, rnd: math.Random(3));
      expect(kitRandShareText(1, 6, o, false), startsWith('随机数 1~6 ×1：'));
      expect(kitRandShareText(1, 6, o, true), contains('（不重复）'));
    });

    test('抽牌：牌面合法且历史按 1~52 记', () {
      for (var s = 0; s < 30; s++) {
        final r = kitRandCard(rnd: math.Random(s), ts: 1000 + s);
        expect(r.card.length, greaterThanOrEqualTo(2));
        expect(kKitCardSuits.contains(r.card[0]), isTrue);
        expect(kKitCardRanks.contains(r.card.substring(1)), isTrue);
        expect(r.record.min, 1);
        expect(r.record.max, 52);
        expect(r.record.valuesText, r.card);
      }
    });

    test('历史截断 6 组 + 编解码往返', () {
      var h = <KitRandRecord>[];
      for (var i = 0; i < 9; i++) {
        h = kitRandPush(h, KitRandRecord(min: i, max: i + 1, values: ['$i'], unique: i.isEven, ts: i));
      }
      expect(h.length, kKitRandHistMax);
      expect(h.first.min, 8);
      final back = kitRandDecode(kitRandEncode(unique: true, history: h));
      expect(back.unique, isTrue);
      expect(back.history.length, kKitRandHistMax);
      expect(back.history.first.paramsText, '[8, 9] ×1 不重复');
      expect(back.history.first.unique, isTrue); // i=8 为偶数 → 不重复
      expect(back.history[1].paramsText, '[7, 8] ×1');
    });

    test('损坏数据按空处理', () {
      final s = kitRandDecode({'u': 'notbool', 'rHist': 5});
      expect(s.unique, isFalse);
      expect(s.history, isEmpty);
    });
  });
}
