import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/items/domain/item_calc.dart';
import 'package:lifeharness/features/items/domain/item_models.dart';
import 'package:lifeharness/features/items/presentation/items_providers.dart';

/// 批2 · 每日成本引擎实算（原型 D.items MacBook 样本回归 · HG-E1）。
/// 固定钟 2026-09-19（与 UI 测试同一时间源缝口径）。
void main() {
  final now = DateTime(2026, 9, 19);

  // 原型样本：MacBook Air M3（price 9999 + extra 399/156 · 持有 556 天）
  ItemProfile macbook() => ItemProfile(
        id: 1,
        name: 'MacBook Air M3',
        category: '数码',
        buyDate: '2025-03-12',
        price: 9999,
        warranty: '2026-03-12',
        events: const [
          ItemEvent(
              id: 1,
              itemId: 1,
              kind: kEvBuy,
              label: '购入',
              amount: 9999,
              date: '2025-03-12'),
          ItemEvent(
              id: 2,
              itemId: 1,
              kind: kEvExtra,
              label: '二次付费：Type-C 扩展坞',
              amount: 399,
              date: '2025-06-02'),
          ItemEvent(
              id: 3,
              itemId: 1,
              kind: kEvExtra,
              label: '二次付费：官方换电池（补差）',
              amount: 156,
              date: '2026-01-20'),
        ],
      );

  // 原型样本：Nike 跑鞋（按次 · pool 899 ÷ 计划 300 · 近 30 天 45 次）
  ItemProfile shoes() => ItemProfile(
        id: 2,
        name: 'Nike 跑鞋',
        category: '服饰',
        buyDate: '2026-08-18',
        price: 899,
        mode: ItemMode.times,
        planUnits: 300,
        unit: '次',
        usages: const [
          ItemUsage(id: 1, itemId: 2, day: '2026-08-25', qty: 20),
          ItemUsage(id: 2, itemId: 2, day: '2026-09-10', qty: 25),
          // 窗口外用量（不参与近30天折算）
          ItemUsage(id: 3, itemId: 2, day: '2026-08-10', qty: 6),
        ],
      );

  // 止损样本：净值已跌破 50% 线（预期 1 年 · 购入 2026-01-01）
  ItemProfile stopNear() => const ItemProfile(
        id: 3,
        name: '平板',
        buyDate: '2026-01-01',
        price: 1000,
        expectedYears: 1,
        mode: ItemMode.stop,
        stopPct: 50,
      );

  group('直线法 day', () {
    test('MacBook 样本：(9999+555-0)÷556 ≈ 18.98', () {
      final it = macbook();
      expect(daysHeld(it.buyDate, now), 556);
      expect(extraSum(it), 555);
      expect(poolOf(it), 10554);
      expect(investedOf(it), 10554);
      final c = costPerDay(it, now)!;
      expect(c, closeTo(18.982, 1e-3));
      expect(itemMoneyStatic(c), '¥18.98');
    });
    test('poolOf 派生自 events（不落档案列）', () {
      final base = macbook();
      final noExtra = ItemProfile(
          name: base.name, buyDate: base.buyDate, price: base.price);
      expect(poolOf(noExtra), 9999);
      // 回收事件追加 → 成本池即时下降
      final withRecycled = base.copyWith(events: [
        ...base.events,
        const ItemEvent(
            itemId: 1,
            kind: kEvRecycle,
            label: '回收/出售 · 转出',
            amount: 4200,
            date: '2026-09-19'),
      ]);
      expect(poolOf(withRecycled), 6354);
      expect(investedOf(withRecycled), 10554); // 总投入不含回收
    });
  });

  group('按次均摊 times', () {
    test('跑鞋：pool÷300 · ×近30天45次/30 折算日均', () {
      final it = shoes();
      expect(poolOf(it), 899);
      expect(perUseCost(it), closeTo(2.9966666, 1e-5));
      expect(usedLast30(it, now), 45); // 窗口 2026-08-21..09-19，08-10 不计
      expect(usedTotal(it), 51);
      expect(costPerDay(it, now), closeTo(4.495, 1e-9));
    });
    test('计划次数缺省 → 每次成本 0（不炸）', () {
      final it = ItemProfile(
          name: 'x', buyDate: '2026-09-01', price: 100, mode: ItemMode.times);
      expect(perUseCost(it), 0);
      expect(costPerDay(it, now), 0);
    });
  });

  group('预估止损 stop', () {
    test('net/line/lineDate/接近线文案口径', () {
      final it = stopNear();
      final si = stopInfoOf(it, now);
      // days=261 · net=1000×(1-261/365)=284.93 · line=500
      expect(si.net, closeTo(284.93, 0.01));
      expect(si.line, 500);
      expect(si.expired, isTrue);
      expect(si.near, isTrue); // net < line×1.2
      // 触线日＝购入 + (365×(1-0.5)=182.5).round()=183 天
      expect(si.lineDate, DateTime(2026, 7, 3));
    });
    test('相机镜头样本：未接近线走常规建议文案', () {
      final it = const ItemProfile(
          id: 4,
          name: '相机镜头 35mm',
          buyDate: '2025-04-22',
          price: 1299,
          expectedYears: 5,
          mode: ItemMode.stop,
          stopPct: 30);
      final si = stopInfoOf(it, now);
      expect(si.net, closeTo(932.43, 0.01));
      expect(si.line, closeTo(389.7, 0.01));
      expect(si.near, isFalse);
      expect(si.near || si.net < si.line * 1.5, isFalse); // UI 建议文案分支
    });
  });

  group('冻结与合计', () {
    test('billing=false → costPerDay null（停止计费）', () {
      final it = macbook().copyWith(billing: false, status: kItemStatusScrapped);
      expect(costPerDay(it, now), isNull);
      expect(it.archived, isTrue);
    });
    test('totalDailyCost 只对计费中求和：18.98 + 4.50 = 23.48', () {
      const frozen = ItemProfile(
          id: 9,
          name: '旧显示器',
          buyDate: '2023-05-30',
          price: 1499,
          billing: false,
          status: kItemStatusScrapped);
      expect(totalDailyCost([macbook(), shoes(), frozen], now),
          closeTo(23.477, 1e-3));
    });
    test('billingForStatus：已报废/转出冻结，留用/闲置计费', () {
      expect(billingForStatus(kItemStatusScrapped), isFalse);
      expect(billingForStatus(kItemStatusRecycleOut), isFalse);
      expect(billingForStatus(kItemStatusRecycleKeep), isTrue);
      expect(billingForStatus(kItemStatusIdle), isTrue);
    });
  });

  group('决算 settleOf 六值', () {
    test('iPhone13 样本：投入6198/残值1800/净4398/回收率29%', () {
      final it = ItemProfile(
        id: 5,
        name: 'iPhone 13',
        buyDate: '2024-01-08',
        price: 5999,
        status: kItemStatusRecycleOut,
        billing: false,
        events: const [
          ItemEvent(
              itemId: 5,
              kind: kEvBuy,
              label: '购入',
              amount: 5999,
              date: '2024-01-08'),
          ItemEvent(
              itemId: 5,
              kind: kEvExtra,
              label: '二次付费：碎屏维修',
              amount: 199,
              date: '2024-11-02'),
          ItemEvent(
              itemId: 5,
              kind: kEvRecycle,
              label: '回收/出售 · 转出',
              amount: 1800,
              date: '2026-07-15'),
        ],
      );
      final s = settleOf(it, now);
      expect(s.invested, 6198);
      expect(s.days, daysHeld('2024-01-08', now));
      expect(s.residue, 1800);
      expect(s.netHold, 4398);
      expect(s.realDaily, closeTo(4398 / s.days, 1e-6));
      expect(s.recoverRate, (1800 / 6198 * 100).round());
      expect(s.auditCount, 3);
    });
  });

  group('近 6 月现金流（monthlyItemCashflow）', () {
    test('月份窗口：仅 2026-04..09 六个桶 · buy/extra 加 recycle 减', () {
      final it = ItemProfile(
        id: 6,
        name: 'x',
        buyDate: '2026-08-18',
        price: 899,
        events: const [
          ItemEvent(
              itemId: 6, kind: kEvBuy, label: '购入', amount: 899, date: '2026-08-18'),
          ItemEvent(
              itemId: 6, kind: kEvExtra, label: 'e', amount: 100, date: '2026-09-01'),
          ItemEvent(
              itemId: 6, kind: kEvRecycle, label: 'r', amount: 50, date: '2026-09-02'),
          // 窗口外（去年）不进任何桶
          ItemEvent(
              itemId: 6, kind: kEvExtra, label: 'e', amount: 700, date: '2025-05-01'),
        ],
      );
      final data = ItemsData(items: [it]);
      final months = monthlyItemCashflow(data, now);
      expect(months.length, 6);
      expect(months.first.$1, '2026-04');
      expect(months.last.$1, '2026-09');
      expect(months.firstWhere((m) => m.$1 == '2026-08').$2, 899);
      expect(months.firstWhere((m) => m.$1 == '2026-09').$2, 50); // 100-50
      expect(months.fold<double>(0, (s, m) => s + m.$2), 949); // 700 被排除
    });
  });

  group('providers 派生', () {
    test('itemsByCat：全部不含冻结 · 历史=冻结 · 分类过滤', () {
      const frozen = ItemProfile(
          id: 9,
          name: '旧显示器',
          buyDate: '2023-05-30',
          price: 1499,
          billing: false,
          status: kItemStatusScrapped);
      final data = ItemsData(items: [
        macbook(),
        shoes(),
        frozen,
      ]);
      expect(itemsByCat(data, '全部').length, 2);
      expect(itemsByCat(data, '历史（决算）').length, 1);
      expect(itemsByCat(data, '数码').length, 1);
      expect(itemsByCat(data, '家电'), isEmpty);
    });
    test('catPoolShare 含冻结条目全周期口径、按池降序', () {
      final data = ItemsData(items: [macbook(), shoes()]);
      final shares = catPoolShare(data);
      expect(shares.map((s) => s.$1).toList(), ['数码', '服饰']);
      expect(shares.first.$2, 10554);
    });
    test('itemSegCats 按 providers 口径（7 段含交通工具+历史）', () {
      expect(itemSegCats,
          ['全部', '数码', '家电', '家具', '服饰', '交通工具', '历史（决算）']);
    });
  });
}

/// 展示口径 helper（与 items_kit.itemMoney 同式，测试独立复算防漂移）。
String itemMoneyStatic(num v) => fmtY(double.parse(v.toStringAsFixed(2)));
