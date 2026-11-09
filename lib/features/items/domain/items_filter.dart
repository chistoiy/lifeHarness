/// 物品列表的搜索 / 筛选 / 排序（竞品补全·物品批A I02＋I04 的纯函数层）。
///
/// 为什么单独成文件：搜索框、筛选、排序是「同一份列表的三种视图参数」，
/// 判定全在这里、UI 只传参数——单测与变异刀能直接钉住口径，不必起整机。
/// 分类 seg 仍走 `itemsByCat`（既有口径不动），本层负责它之后的三道闸。
library;

import 'item_calc.dart';
import 'item_models.dart';

/// 排序档（I04 用户可选；默认日均↓＝列表原有顺序，切过去不跳变）。
enum ItemSort {
  dailyCostDesc('日均成本 · 高→低'),
  poolDesc('成本池 · 高→低'),
  priceDesc('购入价 · 高→低'),
  buyDateDesc('购入时间 · 新→旧'),
  nameAsc('名称 · A→Z');

  const ItemSort(this.label);
  final String label;

  static ItemSort of(String wire) => ItemSort.values.firstWhere(
        (e) => e.name == wire,
        orElse: () => ItemSort.dailyCostDesc,
      );
}

/// 成本池金额段（I04「金额段筛选」）。边界取左闭右开：
/// ≤1000 / (1000, 5000] / >5000。三档覆盖家庭物品常见价位，
/// 不做自由区间——自由区间是表单负担，且与「筛选胶囊」心智不符。
enum ItemPoolBand {
  all('不限价位', null, null),
  low('¥1,000 以内', null, 1000),
  mid('¥1,000 – 5,000', 1000, 5000),
  high('¥5,000 以上', 5000, null);

  const ItemPoolBand(this.label, this.min, this.max);

  /// 下限（不含）；null＝无下限。
  final double? min;

  /// 上限（含）；null＝无上限。
  final double? max;
  final String label;

  bool hit(double pool) {
    if (min != null && pool <= min!) return false;
    if (max != null && pool > max!) return false;
    return true;
  }
}

/// 状态档（四档·与 hero 计数同口径；「已回收」按前缀覆盖抵扣留用/转出两子态）。
const kItemFilterStatuses = ['使用中', '闲置', '已回收', '已报废'];

/// 列表视图参数。不可变；加条件走 [copyWith]。
class ItemFilter {
  const ItemFilter({
    this.keyword = '',
    this.statuses = const {},
    this.band = ItemPoolBand.all,
    this.sort = ItemSort.dailyCostDesc,
  });

  /// 已归一化（trim + 小写）的关键词；空＝不限。
  final String keyword;

  /// 选中的状态前缀（空集＝不限）。
  final Set<String> statuses;

  final ItemPoolBand band;
  final ItemSort sort;

  bool get hasQuery => keyword.isNotEmpty;

  /// 除排序外的激活条件数（决定筛选按钮角标与「重置」是否可点）。
  int get activeCount =>
      (keyword.isEmpty ? 0 : 1) + statuses.length + (band == ItemPoolBand.all ? 0 : 1);

  ItemFilter copyWith({
    String? keyword,
    Set<String>? statuses,
    ItemPoolBand? band,
    ItemSort? sort,
  }) =>
      ItemFilter(
        keyword: keyword ?? this.keyword,
        statuses: statuses ?? this.statuses,
        band: band ?? this.band,
        sort: sort ?? this.sort,
      );

  static const empty = ItemFilter();
}

/// 关键词归一化（搜索框输入 → 判定用；去首尾空白 + 小写）。
String normalizeItemKeyword(String raw) => raw.trim().toLowerCase();

/// 命中文本（I02 口径：名称 / 分类 / 状态；I03 加列后并入品牌 / 序列号 / 物品备注）。
///
/// 集中在这一处：搜索框、判定、将来的「相关档案」检索都吃同一条 haystack，
/// 加字段只改这里，不必每个调用方各改一遍。
String itemHaystack(ItemProfile it) =>
    '${it.name}\n${it.category}\n${it.status}\n${it.brand ?? ''}\n${it.serial ?? ''}\n${it.note ?? ''}'
        .toLowerCase();

bool _hitStatus(ItemProfile it, Set<String> statuses) {
  if (statuses.isEmpty) return true;
  for (final s in statuses) {
    if (it.status.startsWith(s)) return true;
  }
  return false;
}

/// 三道闸 + 排序。输入通常是 `itemsByCat(...)` 的结果，返回新列表（不改入参）。
List<ItemProfile> filterItems(
    List<ItemProfile> src, ItemFilter f, DateTime now) {
  final kw = f.keyword;
  final out = <ItemProfile>[
    for (final it in src)
      if ((kw.isEmpty || itemHaystack(it).contains(kw)) &&
          _hitStatus(it, f.statuses) &&
          f.band.hit(poolOf(it)))
        it,
  ];
  _sortItems(out, f.sort, now);
  return out;
}

int _cmp(ItemProfile a, ItemProfile b, ItemSort sort, DateTime now) {
  switch (sort) {
    case ItemSort.dailyCostDesc:
      // 日均可能为 null（非计费/数据不足）——null 一律沉底，
      // 否则「没算出来的」会浮到榜首并被当成最贵。
      final ca = costPerDay(a, now);
      final cb = costPerDay(b, now);
      if (ca == null && cb == null) return 0;
      if (ca == null) return 1;
      if (cb == null) return -1;
      return cb.compareTo(ca);
    case ItemSort.poolDesc:
      return poolOf(b).compareTo(poolOf(a));
    case ItemSort.priceDesc:
      return b.price.compareTo(a.price);
    case ItemSort.buyDateDesc:
      return b.buyDate.compareTo(a.buyDate); // YYYY-MM-DD 字典序＝时间序
    case ItemSort.nameAsc:
      return a.name.compareTo(b.name);
  }
}

/// 稳定排序：Dart 的 List.sort 不稳定，同值项会乱序跳动。
/// 用原索引做第二关键字，保证「同日均」的条目始终按原顺序排列（可测且不晃眼）。
void _sortItems(List<ItemProfile> list, ItemSort sort, DateTime now) {
  final idx = List<int>.generate(list.length, (i) => i);
  final copy = List<ItemProfile>.of(list);
  idx.sort((ia, ib) {
    final c = _cmp(copy[ia], copy[ib], sort, now);
    return c != 0 ? c : ia.compareTo(ib);
  });
  for (var i = 0; i < idx.length; i++) {
    list[i] = copy[idx[i]];
  }
}
