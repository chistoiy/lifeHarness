import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/items/domain/item_calc.dart';
import 'package:lifeharness/features/items/domain/item_models.dart';
import 'package:lifeharness/features/items/domain/items_filter.dart';

/// 物品批A · 列表搜索/筛选/排序（I02＋I04）纯函数口径。
/// 固定钟 2026-09-19（与 items_calc_test 同一时间源缝口径）。
void main() {
  final now = DateTime(2026, 9, 19);

  // A：数码·使用中，购入价 9999 + 两次二次付费 ⇒ 成本池 10554（池≠价，用来分档）
  ItemProfile macbook() => ItemProfile(
        id: 1,
        name: 'MacBook Air M3',
        category: '数码',
        buyDate: '2025-03-12',
        price: 9999,
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
              label: '二次付费：扩展坞',
              amount: 399,
              date: '2025-06-02'),
          ItemEvent(
              id: 3,
              itemId: 1,
              kind: kEvExtra,
              label: '二次付费：换电池',
              amount: 156,
              date: '2025-09-02'),
        ],
      );

  // B：服饰·闲置，池 1099（落「1000 以内」与「1000–5000」边界外）
  ItemProfile shoes() => const ItemProfile(
        id: 2,
        name: '跑鞋',
        category: '服饰',
        buyDate: '2026-01-10',
        price: 1099,
        status: kItemStatusIdle,
      );

  // C：数码·已回收(转出)，池 6200（落「5000 以上」）
  ItemProfile sofa() => const ItemProfile(
        id: 3,
        name: '布艺沙发',
        category: '家具',
        buyDate: '2024-11-01',
        price: 6800,
        status: kItemStatusRecycleOut,
        events: [
          ItemEvent(
              itemId: 3,
              kind: kEvRecycle,
              label: '回收转出',
              amount: 600,
              date: '2026-05-01'),
        ],
      );

  // D：已报废（billing=false ⇒ costPerDay 为 null），池 1499
  ItemProfile oldMonitor() => const ItemProfile(
        id: 4,
        name: '旧显示器',
        category: '数码',
        buyDate: '2023-05-30',
        price: 1499,
        billing: false,
        status: kItemStatusScrapped,
      );

  List<ItemProfile> all() => [macbook(), shoes(), sofa(), oldMonitor()];

  group('I02 关键词', () {
    test('命中名称·大小写不敏感', () {
      final r = filterItems(
          all(), ItemFilter(keyword: normalizeItemKeyword('  macbook ')), now);
      expect(r.map((e) => e.name).toList(), ['MacBook Air M3']);
    });

    test('命中分类与状态（同一关键词两种条目都算命中）', () {
      expect(
          filterItems(all(), ItemFilter(keyword: '数码'), now)
              .map((e) => e.name)
              .toList(),
          ['MacBook Air M3', '旧显示器']);
      expect(
          filterItems(all(), ItemFilter(keyword: '闲置'), now)
              .map((e) => e.name)
              .toList(),
          ['跑鞋']);
    });

    test('不命中＝空集；空关键词＝不限', () {
      expect(filterItems(all(), const ItemFilter(keyword: '不存在'), now),
          isEmpty);
      expect(filterItems(all(), const ItemFilter(), now).length, 4);
      expect(normalizeItemKeyword('  AbC '), 'abc');
    });
  });

  group('I04 状态筛选', () {
    test('「已回收」按前缀覆盖抵扣留用/转出两子态', () {
      final r = filterItems(
          all(),
          const ItemFilter(statuses: {'已回收'}),
          now);
      expect(r.map((e) => e.name).toList(), ['布艺沙发']);
    });

    test('多档取并集，空集＝不限', () {
      final r = filterItems(all(), const ItemFilter(statuses: {'闲置', '已报废'}), now);
      expect(r.map((e) => e.name).toList(), ['跑鞋', '旧显示器']);
      expect(filterItems(all(), const ItemFilter(), now).length, 4);
    });
  });

  group('I04 金额段（按成本池，不是购入价）', () {
    double pool(String name) =>
        poolOf(all().firstWhere((e) => e.name == name));

    test('池口径：二次付费计入、回收抵扣', () {
      expect(pool('MacBook Air M3'), 10554);
      expect(pool('布艺沙发'), 6200);
    });

    test('边界左开右闭：≤1000 / (1000,5000] / >5000', () {
      List<String> hit(ItemPoolBand b) =>
          filterItems(all(), ItemFilter(band: b), now).map((e) => e.name).toList();
      expect(hit(ItemPoolBand.low), isEmpty); // 最便宜 1099 > 1000
      expect(hit(ItemPoolBand.mid), ['跑鞋', '旧显示器']);
      expect(hit(ItemPoolBand.high), ['MacBook Air M3', '布艺沙发']);
      expect(hit(ItemPoolBand.all).length, 4);
    });

    test('分档判据用池不用价：9999 的机器若池落进 mid 就该出现在 mid', () {
      // 价 9999、回收抵扣 5500 ⇒ 池 4499，落 mid
      final rebated = ItemProfile(
        id: 5,
        name: '折抵手机',
        category: '数码',
        buyDate: '2026-02-01',
        price: 9999,
        events: const [
          ItemEvent(
              itemId: 5,
              kind: kEvRecycle,
              label: '回收抵扣',
              amount: 5500,
              date: '2026-08-01'),
        ],
      );
      final r = filterItems([rebated], const ItemFilter(band: ItemPoolBand.mid), now);
      expect(r.map((e) => e.name).toList(), ['折抵手机']);
    });
  });

  group('I04 排序', () {
    test('五档顺序', () {
      List<String> by(ItemSort s) =>
          filterItems(all(), ItemFilter(sort: s), now).map((e) => e.name).toList();

      // 日均：MacBook 10554/556≈18.98；沙发 6200/687≈9.03；跑鞋 1099/252≈4.36；旧显示器 null 沉底
      expect(by(ItemSort.dailyCostDesc),
          ['MacBook Air M3', '布艺沙发', '跑鞋', '旧显示器']);
      expect(by(ItemSort.poolDesc),
          ['MacBook Air M3', '布艺沙发', '旧显示器', '跑鞋']);
      expect(by(ItemSort.priceDesc),
          ['MacBook Air M3', '布艺沙发', '旧显示器', '跑鞋']);
      expect(by(ItemSort.buyDateDesc),
          ['跑鞋', 'MacBook Air M3', '布艺沙发', '旧显示器']);
      expect(by(ItemSort.nameAsc), ['MacBook Air M3', '布艺沙发', '旧显示器', '跑鞋']);
    });

    test('同值保持原顺序（稳定排序·不晃眼）', () {
      ItemProfile same(int id, String name) => ItemProfile(
          id: id, name: name, category: '其他', buyDate: '2026-01-01', price: 100);
      final src = [same(1, '甲'), same(2, '乙'), same(3, '丙')];
      expect(
          filterItems(src, const ItemFilter(sort: ItemSort.poolDesc), now)
              .map((e) => e.name)
              .toList(),
          ['甲', '乙', '丙']);
      expect(
          filterItems(src, const ItemFilter(sort: ItemSort.dailyCostDesc), now)
              .map((e) => e.name)
              .toList(),
          ['甲', '乙', '丙']);
    });

    test('不改入参（纯函数）', () {
      final src = all();
      final before = src.map((e) => e.name).toList();
      filterItems(src, const ItemFilter(sort: ItemSort.nameAsc), now);
      expect(src.map((e) => e.name).toList(), before);
    });
  });

  group('复合与参数', () {
    test('分类闸在前（itemsByCat 结果）+ 关键词/状态/金额段叠加', () {
      // 模拟 UI：先分类「数码」→ 再只留使用中 + 池 >5000
      final cat = all().where((e) => e.billing && e.category == '数码').toList();
      final r = filterItems(
          cat,
          const ItemFilter(statuses: {'使用中'}, band: ItemPoolBand.high),
          now);
      expect(r.map((e) => e.name).toList(), ['MacBook Air M3']);
    });

    test('activeCount 只数非排序条件', () {
      expect(const ItemFilter().activeCount, 0);
      expect(
          const ItemFilter(
                  keyword: 'a', statuses: {'闲置', '已报废'}, band: ItemPoolBand.mid)
              .activeCount,
          4);
      expect(
          const ItemFilter(sort: ItemSort.nameAsc).activeCount, 0);
    });

    test('copyWith 只换指定项', () {
      const f = ItemFilter(keyword: 'x', band: ItemPoolBand.low);
      final g = f.copyWith(sort: ItemSort.nameAsc);
      expect(g.keyword, 'x');
      expect(g.band, ItemPoolBand.low);
      expect(g.sort, ItemSort.nameAsc);
      expect(g.statuses, isEmpty);
    });

    test('ItemSort.of 未知值回落默认档（旧数据/脏值不炸）', () {
      expect(ItemSort.of('nameAsc'), ItemSort.nameAsc);
      expect(ItemSort.of('nope'), ItemSort.dailyCostDesc);
    });
  });
}
