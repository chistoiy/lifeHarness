import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/kits/domain/kit_calc.dart';
import 'package:lifeharness/features/kits/domain/kit_models.dart';

/// V1.47 小工具批0 · 纯计算口径（时钟全部注入，禁时间炸弹）。
void main() {
  // 固定「现在」：2026-03-05 12:00（非跨日窗口，用例在任何日期运行结果一致）。
  final now = DateTime(2026, 3, 5, 12, 0);
  int ms(int dayOffset, [int hour = 9]) => DateTime(2026, 3, 5, hour)
      .subtract(Duration(days: dayOffset))
      .millisecondsSinceEpoch;

  KitUsage u(String tool, int ts, {String kind = kKitKindBuiltin}) =>
      KitUsage(tool: tool, ts: ts, kind: kind);

  group('1 · 日窗与聚合', () {
    test('kitDayStart 抹平时分秒', () {
      expect(kitDayStart(now), DateTime(2026, 3, 5));
    });

    test('近 7 天窗口起点=含今天往前 6 天零点', () {
      expect(kitWindowStart(now, 7), DateTime(2026, 2, 27));
      expect(kitWindowStart(now, 1), DateTime(2026, 3, 5));
    });

    test('按工具/按日/按分类三种聚合同源', () {
      final log = [
        u('pick', ms(0)),
        u('pick', ms(1)),
        u('datec', ms(1)),
        u('ruler', ms(30)),
      ];
      expect(kitCountByTool(log), {'pick': 2, 'datec': 1, 'ruler': 1});
      expect(kitCountByDay(log, now, 7).values.fold<int>(0, (a, b) => a + b), 3);
      expect(kitCountByCat(log), {KitCat.color: 2, KitCat.calc: 1, KitCat.length: 1});
    });

    test('未登记工具键归入兜底分类而不抛', () {
      expect(kitCountByCat([u('ghost', ms(0))]).keys.single, KitCat.demo);
    });

    test('最近一次使用取最大时间戳', () {
      final log = [u('b64', ms(3)), u('b64', ms(1)), u('tele', ms(0))];
      expect(kitLastUse(log, 'b64'), ms(1));
      expect(kitLastUse(log, 'rand'), isNull);
    });
  });

  group('2 · 八枚数据位取值', () {
    final log = [u('pick', ms(0)), u('pick', ms(0)), u('dist', ms(10))];

    test('total / today / week / fav / recent 各自口径', () {
      expect(
          kitMetricValue(KitMetric.total, log: log, now: now, fav: const []), 3);
      expect(
          kitMetricValue(KitMetric.today, log: log, now: now, fav: const []), 2);
      expect(
          kitMetricValue(KitMetric.week, log: log, now: now, fav: const []), 2);
      expect(
          kitMetricValue(KitMetric.fav, log: log, now: now, fav: const ['a', 'b', 'c']),
          3);
      expect(
          kitMetricValue(KitMetric.recent, log: log, now: now, fav: const []), 2);
    });

    test('插件三枚取调用侧传入值（仓储负责查询）', () {
      expect(
          kitMetricValue(KitMetric.plug,
              log: log, now: now, fav: const [], plugCount: 3),
          3);
      expect(
          kitMetricValue(KitMetric.plugOn,
              log: log, now: now, fav: const [], plugOnCount: 2),
          2);
      expect(
          kitMetricValue(KitMetric.size,
              log: log, now: now, fav: const [], plugSizeKb: 90),
          90);
    });

    test('窗口边界：第 7 天前夜计入、更早不计入', () {
      final edge = [
        u('pick', kitWindowStart(now, 7).millisecondsSinceEpoch),
        u('pick', kitWindowStart(now, 7).millisecondsSinceEpoch - 1),
      ];
      expect(kitMetricValue(KitMetric.week, log: edge, now: now, fav: const []), 1);
    });
  });

  group('3 · 文案可读化', () {
    test('相对时间六档（刚刚/分钟前/小时前/昨天/天前/日期）', () {
      expect(kitRelText(null, now), '未使用');
      expect(kitRelText(now.millisecondsSinceEpoch, now), '刚刚');
      expect(kitRelText(now.subtract(const Duration(minutes: 7)).millisecondsSinceEpoch, now),
          '7 分钟前');
      expect(kitRelText(now.subtract(const Duration(hours: 3)).millisecondsSinceEpoch, now),
          '3 小时前');
      expect(kitRelText(ms(1), now), '昨天');
      expect(kitRelText(ms(3), now), '3 天前');
      expect(kitRelText(ms(30), now), '2-3');
    });

    test('体积：0 / B / KB / M 四档（走查 A6 口径）', () {
      expect(kitKbText(0), '0 B');
      expect(kitKbText(1), '1KB');
      expect(kitKbText(2048), '2.0M');
      expect(kitKbText(90), '90KB');
    });
  });

  group('4 · 工具登记与原型同源', () {
    test('11 个内置工具、8 个分类、键唯一', () {
      expect(kKitTools, hasLength(11));
      expect(KitCat.values, hasLength(8));
      expect(kKitTools.map((t) => t.key).toSet(), hasLength(11));
    });

    test('每个分类都有工具落位（网格不会出现空组）', () {
      for (final c in KitCat.values) {
        expect(kKitTools.where((t) => t.cat == c), isNotEmpty,
            reason: '分类「${c.label}」无工具');
      }
    });

    test('默认数据位=累计使用/近7天/收藏/已装插件（原型 KITS.hero）', () {
      expect(kKitHeroDefault,
          [KitMetric.total, KitMetric.week, KitMetric.fav, KitMetric.plug]);
    });

    test('未知枚举名回落 total（脏数据不炸）', () {
      expect(KitMetric.fromId('nope'), KitMetric.total);
      expect(KitMetric.fromId('size'), KitMetric.size);
    });
  });
}
