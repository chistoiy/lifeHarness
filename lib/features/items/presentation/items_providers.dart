import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../data/items_repository.dart';
import '../domain/item_calc.dart';
import '../domain/item_models.dart';

/// 物品模块 providers（仿 care/days：写库后 tick++ 全量重取快照）。
/// 跨模块（记账 L12）组合动作在 shared/linkage/item_mounts.dart（R1 守护）。

final itemsRepositoryProvider = Provider<ItemsRepository>(
  (ref) => ItemsRepository(AppDatabase.instance.db),
);

final itemsTickProvider = StateProvider<int>((ref) => 0);

/// 时间源缝：测试固定「今天」，计费曲线/近30天窗口/触线日全按单一 now 实算。
final itemsClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 全域快照（列表/详情/编辑回显/统计/决算/仪表盘持有成本卡共用）。
final itemsDataProvider = FutureProvider<ItemsData>((ref) {
  ref.watch(itemsTickProvider);
  return ref.watch(itemsRepositoryProvider).loadAll();
});

void itemsTouch(WidgetRef ref) => ref.read(itemsTickProvider.notifier).state++;
void itemsTouchRef(Ref ref) => ref.read(itemsTickProvider.notifier).state++;

/// 列表分类 seg（全部 / 五类 / 历史（决算）——原型 ITEM_CATS 口径）。
List<String> get itemSegCats =>
    ['全部', ...kItemCats.take(5), '历史（决算）'];

/// 分类过滤（「全部」不含冻结条目；「历史（决算）」＝billing=0）。
List<ItemProfile> itemsByCat(ItemsData d, String cat) {
  if (cat == '全部') return d.items.where((x) => x.billing).toList();
  if (cat == '历史（决算）') return d.items.where((x) => !x.billing).toList();
  return d.items
      .where((x) => x.billing && x.category == cat)
      .toList();
}

/// 统计环图数据（分类→成本池占比，按池降序；含冻结条目＝全周期口径）。
List<(String, double)> catPoolShare(ItemsData d) {
  final pools = <String, double>{};
  for (final it in d.items) {
    pools[it.category] = (pools[it.category] ?? 0) + poolOf(it);
  }
  final total = pools.values.fold<double>(0, (s, v) => s + v);
  if (total <= 0) return const [];
  final list = pools.entries.map((e) => (e.key, e.value)).toList()
    ..sort((a, b) => b.$2.compareTo(a.$2));
  return list;
}

/// 近 6 个自然月「购入+二次付费−残值回收」净额柱（含月份键 YYYY-MM）。
List<(String, double)> monthlyItemCashflow(ItemsData d, DateTime today) {
  final out = <(String, double)>[];
  for (var back = 5; back >= 0; back--) {
    final monthStart = DateTime(today.year, today.month - back, 1);
    final key =
        '${monthStart.year}-${monthStart.month.toString().padLeft(2, '0')}';
    var sum = 0.0;
    for (final it in d.items) {
      for (final e in it.events) {
        if (e.kind == kEvBuy || e.kind == kEvExtra) {
          if (e.date.startsWith(key)) sum += e.amount;
        } else if (e.kind == kEvRecycle) {
          if (e.date.startsWith(key)) sum -= e.amount;
        }
      }
    }
    out.add((key, sum));
  }
  return out;
}
